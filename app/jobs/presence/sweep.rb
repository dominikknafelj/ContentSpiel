module Presence
  # Every 5 minutes (config/recurring.yml): deletes rows nobody has refreshed
  # for `Presence::SWEEP_AFTER`. It signals nothing: what it deletes nobody
  # could see, as every read ignores a row after `Presence::STALE_AFTER`.
  class Sweep < ApplicationJob
    queue_as :default

    def perform
      Mark.where(seen_at: ...Presence::SWEEP_AFTER.ago).delete_all # version: none (presence is not content)
    end
  end
end
