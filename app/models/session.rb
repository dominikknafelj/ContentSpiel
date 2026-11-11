# One signed-in browser. The signed cookie holds its id; ending it (sign-out,
# a password change, the user's deletion, an expiry) destroys the row.
class Session < ApplicationRecord
  belongs_to :user

  # The idle timeout is how long a session may go unseen, the absolute
  # timeout how long it may live whatever is done with it (it is the cookie's
  # expiry too), and `last_seen_at` is written at most this often.
  IDLE_TIMEOUT = 12.hours
  ABSOLUTE_TIMEOUT = 14.days
  SEEN_EVERY = 5.minutes

  # How a person proved who they are. Every session is made through
  # `Session.start`, which refuses a method outside this list.
  METHODS = %w[password passkey sso recovery_code].freeze

  # Why a session ended other than by signing out (`session.destroyed`):
  # `metadata["reason"]` of every `session.ended` (`Sessions::End`).
  END_REASONS = %w[expired_idle expired_absolute ended_by_self ended_by_owner password_changed].freeze

  validates :authenticated_with, inclusion: { in: METHODS }

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
  # and `Users::Save` (`OwnerProtection#end_sessions_after_password_change`,
  # `destroy_all`), `Users::Destroy` (`User`'s `dependent: :destroy`), an
  # expiry (`Sessions::End`, `destroy!`).
  # `test/models/session_test.rb` has each.
  after_destroy_commit :disconnect_cable

  # The one way a session is made: seen now and ending ABSOLUTE_TIMEOUT on.
  def self.start(user:, method:, user_agent:, ip_address:, at: Time.current)
    create!(user: user, authenticated_with: method, user_agent: user_agent, ip_address: ip_address,
      last_seen_at: at, expires_at: at + ABSOLUTE_TIMEOUT)
  end

  # The live session a request's cookies name, or nil: the ONE lookup,
  # shared by the controllers (`Authentication`) and the cable's connection,
  # so the two can never authenticate by different rules. A session past
  # either timeout is ended here, at the first request or connection that
  # meets it, audited without an actor (nobody ended it) and traced as
  # `auth.session`; a live one is marked seen.
  def self.from_cookies(cookies, at: Time.current)
    id = cookies.signed[:session_id]
    session = find_by(id: id) if id
    return unless session

    if (reason = session.expiry(at))
      Telemetry.in_span("auth.session", attributes: { "auth.session.reason" => reason }) do
        Sessions::End.call(session, reason: reason, actor: nil)
      end
      return
    end

    session.seen!(at)
    session
  end

  # Why the session is over at `at`, or nil while it lives. The absolute
  # timeout wins when both hold: it is the one the cookie carries.
  def expiry(at = Time.current)
    if at >= expires_at then "expired_absolute"
    elsif at >= last_seen_at + IDLE_TIMEOUT then "expired_idle"
    end
  end

  # Marks the session seen, at most every SEEN_EVERY. `update_column`, so
  # neither `updated_at` nor a callback moves, and two tabs that race the
  # write both just write it.
  def seen!(at = Time.current)
    update_column(:last_seen_at, at) if last_seen_at <= at - SEEN_EVERY # version: none (a session is on no public page)
  end

  private

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
