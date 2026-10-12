module PublicSite
  # Every five minutes (config/recurring.yml): the clock's own refresh. A
  # scheduled page or post becomes live when `published_at` passes, and a
  # change published with a time comes into force when that time passes;
  # neither writes a row at that moment, so no callback can refresh the
  # addresses that follow. Both are the same event, a published copy that is
  # DUE (`Publishing::Version.settle!`), and every refresh settles what is
  # due before it does anything else. This one touches nothing itself: it
  # only makes sure a refresh happens soon after the moment.
  #
  # No window and nothing to remember: a copy is due until it is settled, so
  # a queue that was down for a week catches up in its first run, and a run
  # with nothing due is one statement. What it cannot see is a record that
  # was scheduled AROUND the services (a console, a test): such a record has
  # no copy to be due, and its going live is acted on by the next refresh
  # that reaches its posts, or by `bin/rails public_paths:rebuild`.
  #
  # `config/recurring.yml` only runs where Solid Queue is the adapter
  # (production), like the trash sweep; in development and test nothing
  # sweeps on its own.
  #
  # No service and no audit event: `public_paths` is derived data the models
  # maintain themselves, and nothing an editor wrote changes here. It still
  # runs as the trusted nil actor on the `:system` channel, like every job
  # that isn't a person's request. A failure is logged and swallowed -- the
  # run's transaction is rolled back, so the copies are still due and the
  # next run, five minutes on, takes them up again -- so one bad record
  # can't leave a failed job retrying in the queue.
  class SyncWentLiveJob < ApplicationJob
    queue_as :default

    def perform
      Current.set(actor: nil, channel: :system) do
        Paths.refresh
      rescue StandardError => e
        Rails.logger.error("[public_paths] couldn't settle what went live: #{e.class}: #{e.message}")
      end
    end
  end
end
