module SiteSearch
  # One whole build of a backend's index (spec §6.5, §6.6): what
  # `SiteSearch::ReindexJob` runs in the background and `search:reindex` in
  # the foreground. Answers the number of records indexed.
  #
  # It marks the backend's state row `building` with the total, then
  # replaces the documents record by record, `BATCH` records at a time:
  # each kept published or scheduled page's and post's copy in force and
  # pending copy (`Documents.for_record`), sent, and the record's documents
  # of every other copy forgotten after (`prune_record`), as `SyncJob` does.
  # Nothing is cleared first, so search keeps answering from the old
  # documents of the records not reached yet, and a build that stops half
  # way leaves every record with documents. `done` is written after every
  # batch, for System status.
  #
  # At the end the documents of every language not enabled go, of every
  # page and post (a draft's built-in entries included: they stay with its
  # copies), and the row is marked `ready` with the fingerprint read at the
  # start: a change of the languages made during the build leaves the row
  # stale, and the job that enqueued this build sees it (`ReindexJob`).
  #
  # Every call to the backend is scrubbed (`Unavailable.scrubbing`): a
  # failure comes out as `SiteSearch::Unavailable`, the row left `building`.
  class Rebuild
    BATCH = 100
    RECORDS = [ Page, Post ].freeze

    def initialize(name: Backends.current_name, backend: Backends.current)
      @name = name.to_s
      @backend = backend
    end

    def call
      fingerprint = IndexState.fingerprint(@name)
      state = IndexState.start!(@name, total: RECORDS.sum { |model| kept(model).count })
      done = 0

      RECORDS.each do |model|
        kept(model).in_batches(of: BATCH) do |batch|
          now = Time.current
          records = batch.to_a
          documents = records.to_h { |record| [ record, Documents.for_record(record, now: now) ] }
          send_batch(documents)
          done += records.size
          state.progress!(done)
        end
      end

      drop_languages_switched_off
      state.ready!(fingerprint, done: done)
      done
    end

    private

    def kept(model) = model.kept.where.not(published_at: nil)

    def send_batch(documents)
      Telemetry.in_span("search.index", attributes: { "search.backend" => @name, "search.documents" => documents.values.sum(&:size) }) do
        Unavailable.scrubbing(backend: @name) do
          documents.each do |record, sent|
            @backend.index(sent) if sent.any?
            @backend.prune_record(record_type: record.class.polymorphic_name, record_id: record.id, except_copy_ids: sent.map(&:copy_id).uniq)
          end
        end
      end
    end

    def drop_languages_switched_off
      off = SUPPORTED_LOCALES.keys - Locales.enabled
      return if off.empty?

      Unavailable.scrubbing(backend: @name) do
        RECORDS.each do |model|
          model.in_batches(of: BATCH) do |batch|
            batch.ids.each { |id| @backend.remove(record_type: model.polymorphic_name, record_id: id, languages: off) }
          end
        end
      end
    end
  end
end
