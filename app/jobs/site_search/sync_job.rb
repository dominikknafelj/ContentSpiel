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
  # The documents are sent first and what is stale is pruned after
  # (`prune_record`, every copy but the ones just sent), so a failure half
  # way leaves the engine holding the record's old documents, never none.
  #
  # A failure is raised as `SiteSearch::Unavailable` (`Unavailable.scrubbing`),
  # so the span, Active Job's retry lines and the report hold the backend's
  # name and the error's class, never its message. It is retried with the
  # job's backoff, five attempts, and reported after the last
  # (`SiteSearch::Reports`); the site goes on searching the engine's last
  # state, which `SiteSearch::Shown` re-checks before a hit is drawn.
  class SyncJob < ApplicationJob
    queue_as :default

    retry_on SiteSearch::Unavailable, attempts: 5, wait: :polynomially_longer do |_job, error|
      SiteSearch::Reports.report(backend: SiteSearch::Backends.current_name, error: error)
    end

    def perform(record_type, record_id)
      record = Indexing::RECORDS.include?(record_type) ? record_type.constantize.find_by(id: record_id) : nil
      documents = record ? Documents.for_record(record, now: Time.current) : []
      name = Backends.current_name

      Telemetry.in_span("search.index", attributes: { "search.backend" => name, "search.documents" => documents.size }) do
        Unavailable.scrubbing(backend: name) do
          backend = Backends.current
          backend.index(documents) if documents.any?
          backend.prune_record(record_type: record_type, record_id: record_id, except_copy_ids: documents.map(&:copy_id).uniq)
        end
      end
      nil
    end
  end
end
