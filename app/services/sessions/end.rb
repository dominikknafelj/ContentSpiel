module Sessions
  # Ends one session: destroys the row (so `Session#disconnect_cable` runs)
  # and records `session.ended` with its reason, in one transaction. It is the
  # low-level ending and asks no permission: `Session.from_cookies` calls it
  # for an expiry, which nobody asked for, and the services a person asks
  # for an ending through authorize before they call it.
  #
  # A session that is already gone (two requests that met the same expired
  # cookie at once) is ended once: the row is read again under its lock, and
  # the second caller finds nothing, records nothing and answers ok.
  class End < ApplicationService
    def initialize(session, reason:, actor: Current.actor)
      raise ArgumentError, "#{reason.inspect} is not among Session::END_REASONS" unless Session::END_REASONS.include?(reason)

      @session = session
      @reason = reason
      @actor = actor
    end

    def call
      # authorize: none (the low-level ending: an expiry has nobody to authorize, and every service a person asks an ending through authorizes before calling this)
      Session.transaction do
        row = Session.lock.find_by(id: @session.id)
        if row
          row.destroy!
          # No snapshot: the user did not change.
          record_event("session.ended", subject: row.user, metadata: { "reason" => @reason, "count" => 1 }, snapshot: nil)
        end
      end
      success(@session)
    end
  end
end
