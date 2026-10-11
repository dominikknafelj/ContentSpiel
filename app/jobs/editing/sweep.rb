module Editing
  # Every 5 minutes (config/recurring.yml): deletes reservations nobody has
  # renewed for `Editing::SWEEP_AFTER`. It signals nothing and nothing depends
  # on it: every read ignores a row after `Editing::HOLD`.
  class Sweep < ApplicationJob
    queue_as :default

    def perform
      Reservation.where(changed_at: ...Editing::SWEEP_AFTER.ago).delete_all # version: none (a reservation is not content)
    end
  end
end
