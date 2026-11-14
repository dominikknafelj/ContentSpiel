module SiteSearch
  # Builds a backend's index when it is empty or stale (spec §6.6),
  # enqueued by the boot's index check (`IndexCheckJob`) and after a change
  # of the languages (`Indexing.languages_changed`); the build is
  # `SiteSearch::Rebuild`.
  #
  # One at a time per backend: two processes booting together enqueue two,
  # and Solid Queue discards the second while the first waits or runs (the
  # semaphore is taken when a job becomes ready and released when it
  # finishes; it lapses after an hour, so a job lost with its worker does
  # not keep the index from being built for ever). A job that slips in after
  # one finished finds the row ready with today's fingerprint and does
  # nothing, so running it twice is safe whatever the queue does.
  #
  # A change of the languages during a build enqueues a job that is
  # discarded, since this one holds the semaphore: so at its end the job
  # reads the fingerprint again, from the settings row as it is now, and
  # enqueues itself again if it moved. Later, by `AGAIN_AFTER`: a job
  # scheduled for later takes the semaphore when it becomes ready, by which
  # time this one has let it go.
  #
  # A backend's failure (`SiteSearch::Unavailable`, scrubbed) is retried
  # with the job's backoff and reported after the last attempt, as
  # `SyncJob`'s is; the row stays `building`, stale for the next check.
  class ReindexJob < ApplicationJob
    AGAIN_AFTER = 10.seconds

    queue_as :default

    limits_concurrency key: ->(name = SiteSearch::Backends.current_name) { "site_search_reindex:#{name}" }, to: 1, duration: 1.hour, on_conflict: :discard

    retry_on SiteSearch::Unavailable, attempts: 5, wait: :polynomially_longer do |job, error|
      SiteSearch::Reports.report(backend: job.arguments.first || SiteSearch::Backends.current_name, error: error)
    end

    # A job enqueued for a backend the site has since stopped using does
    # nothing: the backend in use has its own row, which the boot checks.
    def perform(name = SiteSearch::Backends.current_name)
      return nil unless name == Backends.current_name
      return nil unless IndexState.empty_or_stale?(name)

      Rebuild.new(name: name, backend: Backends.current).call
      self.class.set(wait: AGAIN_AFTER).perform_later(name) if IndexState.empty_or_stale?(name, site: SiteSetting.instance)
      nil
    end
  end
end
