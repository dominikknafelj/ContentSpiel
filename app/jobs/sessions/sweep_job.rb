module Sessions
  # Every hour (config/recurring.yml): ends the sessions nobody met again.
  # A request or a cable connection ends the expired session its cookie names
  # (`Session.from_cookies`); this ends the ones whose browser never came
  # back, so an expired row does not wait for a visit to leave the table.
  #
  # It also deletes the spent passkey challenges past their expiry
  # (`SignIn::SpentChallenge.sweep`), which nothing else would.
  #
  # The reasons are swept in `Session#expiry`'s order: the absolute timeout,
  # then the provider's lapsed check (`expired_sso`), then idleness, so each
  # read after the first holds only sessions no earlier reason took, and each
  # session is counted under one reason. Rows go in batches of BATCH, each in
  # its own transaction, through `Session.destroy_each_locked` (a destroy, so
  # the cable disconnects). It records at most one `session.ended` per reason
  # and figure per run, with no actor and no subject, since a sweep is
  # nobody's act, and the count it ended, even when a batch raises after
  # others committed.
  #
  # ONE EVENT PER FIGURE. `expired_sso` ends a session at 24 hours (an SSO
  # session with no refresh token) or at 26 (one the provider could not be
  # asked about in time), and the event's sentence reads the figure from its
  # metadata (`Session.timeout_metadata`). So the ended rows are tallied by
  # the metadata each would state alone, and each figure is its own event: one
  # event under one figure would say "after 24 hours" of a session that stood
  # 26. The other reasons have one figure each, so one event.
  class SweepJob < ApplicationJob
    queue_as :default

    BATCH = 500

    def perform(at: Time.current)
      Telemetry.in_span("auth.session_sweep") do |span|
        total = %w[expired_absolute expired_sso expired_idle].sum { |reason| sweep(reason, at) }
        Telemetry.record(span, "auth.session.count" => total)
        SignIn::SpentChallenge.sweep(at: at)
      end
    end

    private

    # The events are recorded in `ensure`, so a batch that raises (a lost
    # connection, a deadlock) still leaves them for the batches that had
    # committed before it, and the error goes on to the job.
    def sweep(reason, at)
      ended = Hash.new(0)
      loop do
        # A batch's rows are tallied once its transaction has committed.
        figures = []
        Session.transaction do
          Session.public_send(reason, at).limit(BATCH).destroy_each_locked { |row| figures << Session.timeout_metadata(reason, row) }
        end
        figures.each { |figure| ended[figure] += 1 }
        break if figures.empty?
      end
      ended.values.sum
    ensure
      ended&.sort_by { |figure, _| figure.values }&.each do |figure, count|
        Audit.record("session.ended", metadata: { "reason" => reason, "count" => count, **figure })
      end
    end
  end
end
