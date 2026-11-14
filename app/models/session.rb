# One signed-in browser. The signed cookie holds its id; ending it (sign-out,
# a password change, the user's deletion, an expiry, the sign-in provider's
# re-check failing, an account unlinked from its provider) destroys the row.
class Session < ApplicationRecord
  belongs_to :user

  # The idle timeout is how long a session may go unseen, the absolute
  # timeout how long it may live whatever is done with it (it is the cookie's
  # expiry too), and `last_seen_at` is written at most this often.
  IDLE_TIMEOUT = 12.hours
  ABSOLUTE_TIMEOUT = 14.days
  SEEN_EVERY = 5.minutes

  # How long after a session last proved its person (its sign-in, or Confirm
  # it's you) it may add or remove a passkey or make new recovery codes
  # without proving it again.
  CONFIRM_WINDOW = 10.minutes

  # How a person proved who they are. Every session is made through
  # `Session.start`, which refuses a method outside this list.
  METHODS = %w[password passkey sso recovery_code].freeze

  # Why a session ended other than by signing out (`session.destroyed`):
  # `metadata["reason"]` of every `session.ended` (`SignIn::Sessions::End`).
  END_REASONS = %w[expired_idle expired_absolute ended_by_self ended_by_owner password_changed
    sso_revoked sso_unlinked expired_sso].freeze

  # A session made by an outside provider is asked of it again every
  # PROVIDER_CHECK_EVERY (`provider_checked_at` is the last time it answered).
  # A provider that cannot be reached is given PROVIDER_CHECK_GRACE more before
  # the session ends as `expired_sso`. A session of SSO with no refresh token
  # cannot be asked at all, so it ends at the first figure, with no grace.
  PROVIDER_CHECK_EVERY = 24.hours
  PROVIDER_CHECK_GRACE = 2.hours

  # The refresh token, kept only while the site has encryption keys
  # (`Session.start` drops it otherwise). Never rendered, logged or audited.
  encrypts :provider_token

  validates :authenticated_with, inclusion: { in: ->(_) { METHODS + SignIn::Methods.names } }

  # What a `session.ended` for an expiry stores of the timeout it ended by
  # (`SignIn::Sessions::End`, `SignIn::Sessions::SweepJob`): the event's sentence reads it
  # from there, so an old event keeps its words when a timeout changes.
  #
  # `expired_sso` ends at 24 hours or at 26 (`#expiry`): given the session it
  # says its own figure, and without one the base 24.
  def self.timeout_metadata(reason, session = nil)
    case reason
    when "expired_idle" then { "after_hours" => (IDLE_TIMEOUT / 1.hour).to_i }
    when "expired_absolute" then { "after_days" => (ABSOLUTE_TIMEOUT / 1.day).to_i }
    when "expired_sso" then { "after_hours" => (session&.provider_check_limit || PROVIDER_CHECK_EVERY) / 1.hour }
    else {}
    end
  end

  # A SESSION THAT ENDS TAKES ITS CABLE WITH IT. A WebSocket is authenticated
  # once, when it connects (`ApplicationCable::Connection`), and then lives as
  # long as the tab: without this a tab open before a sign-out or a password
  # change would keep its streams, and could open new ones, for as long as it
  # stayed open -- the window `Users::OwnerProtection` says a password change
  # never leaves. So every destroyed row disconnects ITS USER'S connections,
  # once the destroy has committed. All of the user's, not this session's
  # alone: Action Cable finds a connection by what identifies it, which is
  # the user. The tabs are told to reconnect: one whose session still stands
  # (the session a person changed their own password in; their other
  # browser, after a sign-out here) is back in a moment, and one whose
  # session ended is rejected at connect.
  #
  # Every path that ends a session destroys the row through this callback,
  # and none may use `delete_all`, which would skip it: sign-out
  # (`Authentication#terminate_session`, `destroy`), `Users::UpdatePassword`
  # and `Users::Save` (`OwnerProtection#end_sessions_after_password_change`),
  # `SignIn::Sessions::EndOthers`, `SignIn::Sessions::EndAll` and `SignIn::Sso::Unlink` (all four
  # through `.destroy_each_locked`), `Users::Destroy` (`User`'s `dependent: :destroy`),
  # an expiry (`SignIn::Sessions::End`, `destroy!`).
  # `test/models/session_test.rb` has each.
  after_destroy_commit :disconnect_cable

  # The one way a session is made: seen now, confirmed by the sign-in that
  # made it, and ending ABSOLUTE_TIMEOUT on. `enrolment_due` is decided once,
  # here, so a policy changed later reaches a person at their next session.
  #
  # A session of a provider that can be asked again starts with
  # `provider_checked_at` set (the sign-in is the first check); `provider_token`
  # is its refresh token, dropped when the site cannot encrypt it and for a
  # method that is never asked again (a token nothing reads is a secret at rest
  # for nothing).
  def self.start(user:, method:, user_agent:, ip_address:, enrolment_due: false, provider_token: nil, at: Time.current)
    token = provider_token.presence if rechecked_method?(method) && Forms::Encryption.available?
    create!(user: user, authenticated_with: method, user_agent: user_agent, ip_address: ip_address,
      last_seen_at: at, expires_at: at + ABSOLUTE_TIMEOUT, confirmed_at: at, enrolment_due: enrolment_due,
      provider_token: token, provider_checked_at: (at if rechecked_method?(method)))
  end

  # Whether a method's provider is asked again. SSO is, and so is a gem's
  # method whose entry has a `recheck`; one with none is never asked, so it
  # gets no check date and no stored token.
  def self.rechecked_method?(method) = method == "sso" || SignIn::Methods.rechecked?(method)
  private_class_method :rechecked_method?

  # The sessions past their absolute timeout at `at`.
  scope :expired_absolute, ->(at) { where(expires_at: ..at) }

  # The sessions unseen for the idle timeout at `at`; read after the absolute
  # ones are gone (`SignIn::Sessions::SweepJob`), it holds only sessions that are
  # idle alone.
  scope :expired_idle, ->(at) { where(last_seen_at: ..(at - IDLE_TIMEOUT)) }

  # The sessions whose provider has not confirmed the person for too long at
  # `at`: an SSO session with no token past PROVIDER_CHECK_EVERY, any other
  # session with a check date past EVERY + GRACE (`#expiry` says the same).
  scope :expired_sso, ->(at) {
    checked = arel_table[:provider_checked_at]
    tokenless_sso = arel_table[:authenticated_with].eq("sso").and(arel_table[:provider_token].eq(nil))
      .and(checked.lteq(at - PROVIDER_CHECK_EVERY))
    where(tokenless_sso.or(checked.lteq(at - PROVIDER_CHECK_EVERY - PROVIDER_CHECK_GRACE)))
  }

  # The sessions due their daily ask of the provider at `at`: the one place
  # the figure is applied, for the job that asks.
  scope :provider_check_due, ->(at) { where(provider_checked_at: ..(at - PROVIDER_CHECK_EVERY)) }

  # The sessions past neither timeout at `at`: what a person is shown as
  # signed in (an expired row stands until a request meets it or the sweep
  # runs).
  scope :live, ->(at) { where.not(expires_at: ..at).where.not(last_seen_at: ..(at - IDLE_TIMEOUT)) }

  # Ends every session of the relation it is called on and answers how many:
  # each row is read under its lock and destroyed (so `disconnect_cable`
  # runs), and a row another request ended first is simply not among them,
  # so it is counted once. Called inside the transaction that records the
  # ending, which is ONE `session.ended` with this count, however many rows.
  # A block is handed each row once it is destroyed (the sweep tallies the
  # rows by the figure their event states).
  def self.destroy_each_locked
    lock.order(:id).to_a.each { |row| row.destroy!.tap { yield row if block_given? } }.size
  end

  # The live session a request's cookies name, or nil: the ONE lookup,
  # shared by the controllers (`Authentication`) and the cable's connection,
  # so the two can never authenticate by different rules. A session past
  # either timeout is ended here, at the first request or connection that
  # meets it, audited without an actor (nobody ended it) and, inside a
  # request, traced as `auth.session`; a live one is marked seen. The cable's
  # connect runs outside any request's span, where the span would be a root
  # the sampler drops, so there the ending is audited and not traced
  # (`Telemetry.in_child_span`).
  def self.from_cookies(cookies, at: Time.current)
    id = cookies.signed[:session_id]
    session = find_by(id: id) if id
    return unless session

    if (reason = session.expiry(at))
      Telemetry.in_child_span("auth.session", attributes: { "auth.session.reason" => reason }) do
        SignIn::Sessions::End.call(session, reason: reason, actor: nil)
      end
      return
    end

    session.seen!(at)
    session
  end

  # Why the session is over at `at`, or nil while it lives. The absolute
  # timeout wins when both hold: it is the one the cookie carries; the
  # provider's re-check comes before idleness.
  def expiry(at = Time.current)
    if at >= expires_at then "expired_absolute"
    elsif provider_check_lapsed?(at) then "expired_sso"
    elsif at >= last_seen_at + IDLE_TIMEOUT then "expired_idle"
    end
  end

  # Marks the session seen, at most every SEEN_EVERY. `update_column`, so
  # neither `updated_at` nor a callback moves, and two tabs that race the
  # write both just write it.
  def seen!(at = Time.current)
    update_column(:last_seen_at, at) if last_seen_at <= at - SEEN_EVERY # version: none (a session is on no public page)
  end

  # Whether the session proved its person within CONFIRM_WINDOW of `at`.
  def confirmed_recently?(at = Time.current)
    confirmed_at.present? && at < confirmed_at + CONFIRM_WINDOW
  end

  # Marks the session proved again at `at` (Confirm it's you). `update_column`,
  # as `seen!`, so `updated_at` does not move.
  def confirm!(at = Time.current)
    update_column(:confirmed_at, at) # version: none (a session is on no public page)
  end

  # How long after `provider_checked_at` the session may stand: EVERY for an
  # SSO session with no token to ask with, EVERY + GRACE for any other.
  #
  # Whether there is a token is read from the stored column, never decrypted,
  # as `expired_sso`'s `provider_token IS NULL` reads it: a site whose
  # encryption keys are gone must still end its sessions by expiry (a request,
  # the sweep), and decrypting here would raise in each of them instead.
  def provider_check_limit
    tokenless = read_attribute_before_type_cast(:provider_token).nil?
    authenticated_with == "sso" && tokenless ? PROVIDER_CHECK_EVERY : PROVIDER_CHECK_EVERY + PROVIDER_CHECK_GRACE
  end

  private

  def provider_check_lapsed?(at) = provider_checked_at.present? && at >= provider_checked_at + provider_check_limit

  # A user that is only its id: the user's row may be gone with the session
  # (`Users::Destroy`), and Action Cable needs nothing but the id to name
  # the connections. Like a note's signal (`Notes::Signals`), it must not
  # raise into the request that ended the session when the cable is away:
  # the session is ended either way, the failure is reported and logged by
  # its class alone, and a socket that missed it is still refused every
  # subscription (`ApplicationCable::Channel#subscriber`).
  def disconnect_cable
    ActionCable.server.remote_connections.where(current_user: User.new(id: user_id)).disconnect
  rescue StandardError => error
    Rails.logger.warn("Cable disconnect not sent for an ended session: #{error.class}")
    Rails.error.report(error, handled: true)
  end
end
