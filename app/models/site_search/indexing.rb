module SiteSearch
  # The one entry point of the indexing side (spec §5.4): one method per
  # event that changes what a visitor could find, called by the write that
  # makes the event, and the one caller of a backend's `index` and `remove`
  # (`test/lib/site_search_guards_test.rb`). Each answers nil.
  #
  #   Event                               Called from                                      Asks
  #   a copy is taken                     `take!` of `Publishing::Version`, in its         `copy_taken(version)`
  #                                       transaction
  #   a pending copy is withdrawn         `Version.withdraw_pending!`, and the pending     `copies_withdrawn(record, copy_ids:)`
  #                                       copy `take!` replaces
  #   a copy's content is rewritten       `Version.repoint_tag!` (a merged tag's name)      `copies_rewritten(copy_ids)`
  #   a record's time or visibility moves the save services when `published_at`           `record_changed(record)`
  #                                       changes, `Pages::Move`, `Trash::Move`,
  #                                       `Trash::Restore`
  #   a record is purged                  `Trash::Purge` (and so `Trash::Empty`)           `record_purged(type, id)`
  #   the languages change                `Locales::Enable`, `Disable`, `Configure`,       `languages_changed`
  #                                       `MakeDefault`, when the enabled set or a
  #                                       fallback chain moved (`IndexState.languages`)
  #
  # THE BUILT-IN (`Backends.inline?`) is written here, in the caller's
  # transaction, so its entries stand or fall with the copy. It needs only
  # the copies: its query reads each record's state, address and clock as it
  # searches (spec §6.3), and its foreign key's cascade takes a withdrawn or
  # purged copy's entries with the copy. So it is asked something for a copy
  # taken and a copy rewritten, and nothing for the other events; a withdrawn
  # copy and a purge enqueue `SiteSearch::PruneWordsJob` after the commit,
  # for the words of the entries the cascade took (`Postgres::Vocabulary`).
  #
  # AN OUTSIDE BACKEND is never called inside a write, which would hold the
  # write open on the network: every event becomes a `SiteSearch::SyncJob`
  # for its record, enqueued after the commit of the outermost transaction
  # (`ActiveRecord.after_all_transactions_commit`), so a rolled-back write
  # sends nothing. At that moment the record, or the copy, must still be
  # there: the trial copy of `PublicSite::Paths.foresee`, taken in a
  # savepoint that is always rolled back, enqueues nothing. The job reads
  # the record as it is then, so two events of one write cost two
  # idempotent jobs and nothing more. An enqueue that raises (the queue's
  # database unreachable) is reported, never raised: the write it follows
  # has committed, and its answer is not a 500.
  #
  # An outside engine's document `url` can be stale: a subpage's after its
  # parent's slug changes, a listed post's after its listing page is
  # unpublished, since neither is an event of theirs. The `url` is
  # informational; `SiteSearch::Shown` reads every drawn hit's address from
  # `public_paths`, which keeps the results honest.
  module Indexing
    RECORDS = %w[Page Post].freeze

    module_function

    # A copy in force at once makes every older copy of its record one that
    # will never be current again, so their entries go (spec §6.1, "Entries
    # kept"); a pending copy's entries stand beside the current one's until
    # its time. A copy that the clock supersedes later keeps its entries
    # until the record's next copy: its query skips them.
    def copy_taken(version, now: Time.current)
      if inline?
        if version.live_at <= now
          older = Publishing::Version.where(record_type: version.record_type, record_id: version.record_id).where.not(id: version.id).ids
          backend.remove(record_type: version.record_type, record_id: version.record_id, copy_ids: older) if older.any?
        end
        backend.index(Documents.for(version, now: now))
      else
        enqueue_sync(version.record_type, version.record_id) { Publishing::Version.exists?(version.id) }
      end
      nil
    end

    # The built-in's entries went with the copies (the cascade); their words
    # go with the prune after the commit.
    def copies_withdrawn(record, copy_ids:)
      return nil if copy_ids.empty?

      if inline?
        enqueue_prune
      else
        enqueue_sync(record.class.polymorphic_name, record.id) { !Publishing::Version.exists?(id: copy_ids) }
      end
      nil
    end

    # Rebuilt from the rewritten copies as they now stand, those that are
    # what their record shows now or is scheduled to show; an older copy's
    # words are no visitor's.
    def copies_rewritten(copy_ids)
      return nil if copy_ids.empty?

      copies = Publishing::Version.where(id: copy_ids).to_a
      copies.group_by { |copy| [ copy.record_type, copy.record_id ] }.each do |(record_type, record_id), rewritten|
        if inline?
          now = Time.current
          record = rewritten.first.record
          shown = [ Publishing.current(record, now: now), Publishing.pending(record, now: now) ].compact.map(&:id)
          documents = rewritten.select { |copy| shown.include?(copy.id) }.flat_map { |copy| Documents.for(copy, now: now) }
          backend.index(documents)
        else
          enqueue_sync(record_type, record_id) { stands?(record_type, record_id) }
        end
      end
      nil
    end

    # A page's own subpages go and come with it (the trash, a draft parent),
    # so an outside backend's job reads each of them too.
    #
    # `slug: true` for a write that changed the record's slug, which is
    # immediate and in no copy (`docs/reference/publishing.md`) while its
    # words are in the record's documents (`Documents`, the summary): the
    # built-in rebuilds the record's own documents from the copies it shows
    # now or is scheduled to show, in the caller's transaction and after the
    # address was refreshed. A subpage's documents keep their words: they
    # are its own slug's, wherever its parent is.
    def record_changed(record, slug: false)
      if inline?
        reindex_shown(record) if slug
        return nil
      end

      type = record.class.polymorphic_name
      ids = record.is_a?(Page) ? record.self_and_descendant_ids : [ record.id ]
      ids.each { |id| enqueue_sync(type, id) { stands?(type, id) } }
      nil
    end

    # As a withdrawn copy: the cascade took the built-in's entries, the
    # prune takes their words.
    def record_purged(record_type, record_id)
      if inline?
        enqueue_prune
      else
        enqueue_sync(record_type, record_id) { true }
      end
      nil
    end

    # Every document of every record is read through the languages, so the
    # whole index is built again, by `ReindexJob` after the commit of the
    # outermost transaction for every backend: built in the settings
    # transaction, it would hold the settings row's lock for the length of
    # the build (spec §6.5). Until it has run, a language just enabled finds
    # nothing and the others answer from their old fallback text. An
    # enqueue that raises is reported, never raised, as `enqueue_sync`'s.
    def languages_changed
      ActiveRecord.after_all_transactions_commit do
        ReindexJob.perform_later(Backends.current_name)
      rescue StandardError => error
        Reports.report(backend: Backends.current_name, error: error)
      end
      nil
    end

    def backend = Backends.current

    def inline? = Backends.inline?(Backends.current_name)

    # `still:` is asked after the commit, before the enqueue.
    def enqueue_sync(record_type, record_id, &still)
      ActiveRecord.after_all_transactions_commit do
        SyncJob.perform_later(record_type, record_id) if still.call
      rescue StandardError => error
        Reports.report(backend: Backends.current_name, error: error)
      end
    end
    private_class_method :enqueue_sync

    # After the outermost commit, as `enqueue_sync`: a rolled-back purge
    # prunes nothing, and an enqueue that raises is reported, never raised.
    def enqueue_prune
      ActiveRecord.after_all_transactions_commit do
        PruneWordsJob.perform_later
      rescue StandardError => error
        Reports.report(backend: Backends.current_name, error: error)
      end
    end
    private_class_method :enqueue_prune

    def stands?(record_type, record_id) = RECORDS.include?(record_type) && record_type.constantize.exists?(record_id)
    # The built-in's documents of what `record` shows now and is scheduled
    # to show, indexed again in one pass.
    def reindex_shown(record)
      backend.index(Documents.for_record(record, now: Time.current))
    end

    private_class_method :backend, :inline?, :stands?, :reindex_shown
  end
end
