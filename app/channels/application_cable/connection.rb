module ApplicationCable
  # Who a WebSocket is (notes spec §6.2): the user of the CS Studio session
  # its cookies name, found by the very lookup a request uses
  # (`Session.from_cookies`); no session, no connection.
  #
  # `current_user` is what identifies the connection (and what
  # `Session#disconnect_cable` finds it by). It is A SNAPSHOT FROM CONNECT:
  # a channel never judges a right on it, and reads the user again, through
  # the session, each time something subscribes
  # (`ApplicationCable::Channel#subscriber`). `session_id` is kept for that.
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    attr_reader :session_id

    def connect
      session = Session.from_cookies(cookies) or reject_unauthorized_connection
      @session_id = session.id
      self.current_user = session.user
    end
  end
end
