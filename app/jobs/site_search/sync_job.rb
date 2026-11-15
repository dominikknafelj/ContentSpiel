module SiteSearch
  # Keeps an outside backend in step with one record (spec §5.4, §5.5),
  # enqueued by `SiteSearch::Indexing` after the commit of the write that
  # moved it. Idempotent: it reads the record as it is when it runs and
  # sends the documents of its copy in force and its pending copy with
  # their time bounds (`Documents.for_record`): none for a record purged, in
  # the trash or neither published nor scheduled. So a job that runs late,
  # twice or out of order leaves the backend holding what the site shows,
  # and nothing runs at a pending copy's time: the engine's filter on the
  # bounds turns from one document to the other.
  #
  # ONE RECORD IS SYNCED IN ONE PLACE, `SyncJob.sync`, which this job and
  # `SiteSearch::Rebuild` both run. The documents are sent first and what is
  # stale is pruned after (`prune_record`), so a failure half way leaves the
  # engine holding the record's old documents, never none. The copies the
  # prune keeps are read again right before it, row and copies uncached and
  # by a fresh clock, and never taken from the documents just sent: two
  # syncs of one record that overlap (job A built the old copy's documents,
  # job B ran in full for a new copy, then A sends) end with the new copy's
  # documents, whichever finishes last, because the last prune keeps the
  # copies that stand when it runs.
  #
  # A backend's failure is raised as `SiteSearch::Unavailable`
  # (`Unavailable.scrubbing`), so the span, Active Job's retry lines and the
  # report hold the backend's name and the error's class, never its
  # message. It is retried with the job's backoff, five attempts, and
  # reported after the last (`SiteSearch::Reports`); the site goes on
  # searching the engine's last state, which `SiteSearch::Shown` re-checks
  # before a hit is drawn. A database error while the record is read (a
  # deadlock, a lost connection) is retried the same way (spec §5.7): its
  # message is the database's, which holds no visitor's query.
  class SyncJob < ApplicationJob
    queue_as :default

    retry_on ActiveRecord::ActiveRecordError, attempts: 5, wait: :polynomially_longer
    retry_on SiteSearch::Unavailable, attempts: 5, wait: :polynomially_longer do |_job, error|
      SiteSearch::Reports.report(backend: SiteSearch::Backends.current_name, error: error)
    end

    def perform(record_type, record_id)
      name = Backends.current_name
      Telemetry.in_span("search.index", attributes: { "search.backend" => name }) do |span|
        sent = self.class.sync(Backends.current, name: name, record_type: record_type, record_id: record_id)
        Telemetry.record(span, "search.documents" => sent)
      end
      nil
    end

    # Sends `backend` the documents of one record and prunes the rest:
    # `record` as the caller read it (the build's, read `FOR SHARE` for the
    # built-in; nil for none), else read here. Answers the number of
    # documents sent. Only the backend's calls are scrubbed; a database
    # error is raised as it is.
    def self.sync(backend, name:, record_type:, record_id:, record: :read)
      record = find(record_type, record_id) if record == :read
      documents = record ? Documents.for_record(record, now: Time.current) : []
      Unavailable.scrubbing(backend: name) { backend.index(documents) } if documents.any?
      keep = kept_copy_ids(record_type, record_id)
      Unavailable.scrubbing(backend: name) { backend.prune_record(record_type: record_type, record_id: record_id, except_copy_ids: keep) }
      documents.size
    end

    # The copies of the record that stand now: its copy in force and its
    # pending copy; none for a record purged, trashed or neither published
    # nor scheduled. Read past the query cache, which a job and a request
    # keep, so the row and the copies are the database's at this moment.
    def self.kept_copy_ids(record_type, record_id)
      ActiveRecord::Base.uncached do
        record = find(record_type, record_id)
        next [] if record.nil? || record.trashed? || record.published_at.nil?

        now = Time.current
        [ Publishing.current(record, now: now), Publishing.pending(record, now: now) ].compact.map(&:id)
      end
    end

    def self.find(record_type, record_id)
      Indexing::RECORDS.include?(record_type) ? record_type.constantize.find_by(id: record_id) : nil
    end

    private_class_method :kept_copy_ids, :find
  end
end
