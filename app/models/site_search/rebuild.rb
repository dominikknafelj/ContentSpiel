module SiteSearch
  # One whole build of a backend's index (spec §6.5, §6.6): what
  # `SiteSearch::ReindexJob` runs in the background and `search:reindex` in
  # the foreground. Answers the number of records indexed.
  #
  # ONE BUILD AT A TIME PER BACKEND, whoever runs it: the build holds a
  # session advisory lock on the backend's name for its length, and a second
  # one raises `Busy` without touching anything (the job retries later, the
  # task says a build is running).
  #
  # It marks the backend's state row `building` with the total, then
  # replaces the documents record by record, `BATCH` records at a time:
  # each kept published or scheduled page's and post's copy in force and
  # pending copy (`Documents.for_record`), sent, and the record's documents
  # of every other copy forgotten after (`prune_record`), as `SyncJob` does.
  # Nothing is cleared first, so search keeps answering from the old
  # documents of the records not reached yet, and a build that stops half
  # way leaves every record with documents. `done` is written after every
  # batch, for System status. For an outside backend the records that are
  # not kept and published are synced after (`prune_unkept`), which forgets
  # whatever the engine still holds of them.
  #
  # A COPY TAKEN DURING THE BUILD IS NEVER LOST. A record's documents are
  # built right before they are sent, never ahead for a batch. For the
  # built-in (written inline) each record is read again `FOR SHARE` in a
  # transaction of its own; `take!` of `Publishing::Version` locks the same
  # row `FOR UPDATE` first, so the two wait for each other and the
  # documents sent are of the copies that stand. An outside backend is never called
  # inside a transaction (a row lock held open on the network), so there
  # the copies to keep are read again after the send, right before the
  # prune (`SyncJob.sync`, the one routine both run): a copy taken in
  # between is kept, and the copy it superseded goes; its own `SyncJob`,
  # enqueued after its commit, sends its documents.
  #
  # At the end the documents of the languages switched off since the last
  # finished build go (the row's `languages`, what that build indexed; a
  # backend with no finished build sweeps every language not enabled), of
  # every page and post, a draft's built-in entries included: they stay
  # with its copies. A language enabled and switched off again between two
  # builds can leave documents behind; no visitor reads them, since a
  # search is in an enabled language, and enabling it again rebuilds them.
  # Then the row is marked `ready` with the fingerprint read at the start
  # and the languages indexed: a change of the languages made during the
  # build leaves the row stale, and the job that ran it sees it
  # (`ReindexJob`). Before that the built-in's vocabulary is pruned
  # (`Postgres::Vocabulary.prune`), so a build ends with no word that no
  # entry holds: the words of records gone, of copies superseded and of the
  # languages just dropped.
  #
  # Every call to the backend is scrubbed (`Unavailable.scrubbing`): a
  # failure comes out as `SiteSearch::Unavailable`, the row left `building`.
  class Rebuild
    BATCH = 100
    RECORDS = [ Page, Post ].freeze
    ADVISORY_NAMESPACE = 0x5EA2C4
    INT4 = 2**31

    # Another build of the same backend holds the lock.
    class Busy < StandardError
      def initialize(name) = super("a build of the #{name} search index is already running")
    end

    def initialize(name: Backends.current_name, backend: Backends.current)
      @name = name.to_s
      @backend = backend
      @inline = Backends.inline?(@name)
    end

    def call
      connection = IndexState.connection
      raise Busy, @name unless try_lock(connection)

      begin
        build
      ensure
        unlock(connection)
      end
    end

    private

    def build
      fingerprint = IndexState.fingerprint(@name)
      indexed_before = IndexState.for(@name)&.languages
      state = IndexState.start!(@name, total: RECORDS.sum { |model| kept(model).count })
      done = 0

      RECORDS.each do |model|
        kept(model).in_batches(of: BATCH) do |batch|
          ids = batch.ids
          send_batch(model, ids)
          done += ids.size
          state.progress!(done)
        end
      end

      prune_unkept
      drop_languages(Array(indexed_before || SUPPORTED_LOCALES.keys) - Locales.enabled)
      Unavailable.scrubbing(backend: @name) { Postgres::Vocabulary.prune } if @inline
      state.ready!(fingerprint, languages: Locales.enabled.sort, done: done)
      done
    end

    def kept(model) = model.kept.where.not(published_at: nil)

    def send_batch(model, ids)
      Telemetry.in_span("search.index", attributes: { "search.backend" => @name }) do |span|
        sent = Unavailable.scrubbing(backend: @name) { ids.sum { |id| send_record(model, id) } }
        Telemetry.record(span, "search.documents" => sent)
      end
    end

    # The number of documents sent, through the one routine that syncs a
    # record (`SyncJob.sync`).
    def send_record(model, id)
      type = model.polymorphic_name
      unless @inline
        return SyncJob.sync(@backend, name: @name, record_type: type, record_id: id)
      end

      model.transaction do
        record = kept(model).lock("FOR SHARE").find_by(id: id)
        record ? SyncJob.sync(@backend, name: @name, record_type: type, record_id: id, record: record) : 0
      end
    end

    # An outside engine's documents of the records not kept and published
    # (in the trash, unpublished, a draft), which a lost or failed job of
    # theirs could have left behind: each is synced, so a record published
    # since the build read it keeps its documents. The built-in needs none:
    # its query reads each record's state as it searches.
    def prune_unkept
      return if @inline

      RECORDS.each do |model|
        model.where.not(id: kept(model).select(:id)).in_batches(of: BATCH) do |batch|
          Unavailable.scrubbing(backend: @name) do
            batch.ids.each { |id| SyncJob.sync(@backend, name: @name, record_type: model.polymorphic_name, record_id: id) }
          end
        end
      end
    end

    def drop_languages(off)
      return if off.empty?

      Unavailable.scrubbing(backend: @name) do
        RECORDS.each do |model|
          model.in_batches(of: BATCH) do |batch|
            batch.ids.each { |id| @backend.remove(record_type: model.polymorphic_name, record_id: id, languages: off) }
          end
        end
      end
    end

    def lock_key = [ ADVISORY_NAMESPACE, Zlib.crc32(@name) % INT4 ]

    # Uncached: the query cache, on in a job and a request, would answer a
    # second try with the first one's result.
    def try_lock(connection)
      # sql: Arel has no node for Postgres' advisory lock functions
      connection.uncached { connection.select_value(IndexState.sanitize_sql_array([ "SELECT pg_try_advisory_lock(?, ?)", *lock_key ])) }
    end

    def unlock(connection)
      # sql: Arel has no node for Postgres' advisory lock functions
      connection.uncached { connection.select_value(IndexState.sanitize_sql_array([ "SELECT pg_advisory_unlock(?, ?)", *lock_key ])) }
    end
  end
end
