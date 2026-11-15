module SiteSearch
  # The boot's index check (spec §6.6), enqueued by `SiteSearch::BootCheck`:
  # reads the backend in use's state row and enqueues `ReindexJob` when its
  # index is empty or stale. It writes nothing, so it needs no concurrency
  # limit. A database whose migration has not run yet (no state table) is
  # left alone: the boot after the migration checks again.
  class IndexCheckJob < ApplicationJob
    queue_as :default

    def perform
      return nil unless IndexState.table_exists?

      name = Backends.current_name
      ReindexJob.perform_later(name) if IndexState.empty_or_stale?(name)
      nil
    end
  end
end
