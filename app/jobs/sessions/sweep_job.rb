module Sessions
  # Every hour (config/recurring.yml): ends the sessions nobody met again.
  # A request or a cable connection ends the expired session its cookie names
  # (`Session.from_cookies`); this ends the ones whose browser never came
  # back, so an expired row does not wait for a visit to leave the table.
  #
  # The absolute timeout is swept first, so the idle read after it holds only
  # sessions that are idle alone and each is counted under one reason. Rows
  # go in batches of BATCH, each in its own transaction, through
  # `Session.destroy_each_locked` (a destroy, so the cable disconnects). It
  # records at most one `session.ended` per reason per run, with no actor and
  # no subject, since a sweep is nobody's act, and the count it ended.
  class SweepJob < ApplicationJob
    queue_as :default

    BATCH = 500

    def perform(at: Time.current)
      Telemetry.in_span("auth.session_sweep") do |span|
        total = %w[expired_absolute expired_idle].sum { |reason| sweep(reason, at) }
        Telemetry.record(span, "auth.session.count" => total)
      end
    end

    private

    def sweep(reason, at)
      ended = 0
      loop do
        batch = Session.transaction { Session.public_send(reason, at).limit(BATCH).destroy_each_locked }
        ended += batch
        break if batch.zero?
      end
      Audit.record("session.ended", metadata: { "reason" => reason, "count" => ended }) if ended.positive?
      ended
    end
  end
end
