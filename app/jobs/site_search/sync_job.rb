module SiteSearch
  # Keeps an outside backend in step with one record (spec §5.4, §5.5),
  # enqueued by `SiteSearch::Indexing` after the commit of the write that
  # moved it. Idempotent: it reads the record as it is when it runs, forgets
  # every document the backend holds of it, and sends the documents of its
  # copy in force and its pending copy with their time bounds
  # (`Documents.for_record`): none for a record purged, in the trash or
  # neither published nor scheduled. So a job that runs late, twice or out of
  # order leaves the backend holding what the site shows, and nothing runs
  # at a pending copy's time: the engine's filter on the bounds turns from
  # one document to the other.
  #
  # The backend's documents of a withdrawn copy can be forgotten only by
  # forgetting the record's (the copy's id is gone with its row), so for a
  # moment between the two calls the engine holds none of the record's.
  #
  # A failure is retried with the job's backoff, five attempts, and reported
  # after the last as `SiteSearch::Unavailable` (`SiteSearch::Reports`),
  # never with its message; the site goes on searching the engine's last
  # state, which `SiteSearch::Shown` re-checks before a hit is drawn.
  class SyncJob < ApplicationJob
    queue_as :default

    retry_on StandardError, attempts: 5, wait: :polynomially_longer do |_job, error|
      SiteSearch::Reports.report(backend: SiteSearch::Backends.current_name, error: error)
    end

    def perform(record_type, record_id)
      record = Indexing::RECORDS.include?(record_type) ? record_type.constantize.find_by(id: record_id) : nil
      documents = record ? Documents.for_record(record, now: Time.current) : []
      backend = Backends.current

      Telemetry.in_span("search.index", attributes: { "search.backend" => Backends.current_name, "search.documents" => documents.size }) do
        backend.remove(record_type: record_type, record_id: record_id)
        backend.index(documents) if documents.any?
      end
    end
  end
end
