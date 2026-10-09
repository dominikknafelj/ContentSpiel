# One signed-in browser. The signed cookie holds its id; ending it (sign-out,
# a password change, the user's deletion) destroys the row.
class Session < ApplicationRecord
  belongs_to :user

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
  # `destroy_all`), `Users::Destroy` (`User`'s `dependent: :destroy`).
  # `test/models/session_test.rb` has each.
  after_destroy_commit :disconnect_cable

  # The session a request's cookies name, or nil: the ONE lookup, shared by
  # the controllers (`Authentication`) and the cable's connection, so the
  # two can never authenticate by different rules.
  def self.from_cookies(cookies)
    id = cookies.signed[:session_id]
    find_by(id: id) if id
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
