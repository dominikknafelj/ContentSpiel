module PublicSite
  # Every five minutes (config/recurring.yml): gives the posts listed on a
  # page that went live *by the clock* their address under it. A scheduled
  # page becomes live when `published_at` passes and no row is written at
  # that moment, so no model callback can sync the posts its listing blocks
  # list -- see `PublicSite::Paths.sync_went_live`.
  #
  # The window is the last 24 hours on every run, deliberately overlapping:
  # there is no stored "swept up to here" marker to keep right, the sweep is
  # idempotent and a run with nothing to move writes nothing, and a day's
  # reach covers a queue that was down for hours.
  #
  # `config/recurring.yml` only runs where Solid Queue is the adapter
  # (production), like the trash sweep; in development and test nothing
  # sweeps on its own.
  #
  # No service and no audit event: `public_paths` is derived data the models
  # maintain themselves, and nothing an editor wrote changes here. It still
  # runs as the trusted nil actor on the `:system` channel, like every job
  # that isn't a person's request. A failure is logged and swallowed -- the
  # next run, five minutes on, looks at the same pages again -- so one bad
  # record can't leave a failed job retrying in the queue.
  class SyncWentLiveJob < ApplicationJob
    queue_as :default

    WINDOW = 24.hours

    def perform
      Current.set(actor: nil, channel: :system) do
        Paths.sync_went_live(since: WINDOW.ago)
      rescue StandardError => e
        Rails.logger.error("[public_paths] couldn't sync the pages that went live: #{e.class}: #{e.message}")
      end
    end
  end
end
