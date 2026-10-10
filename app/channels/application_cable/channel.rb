module ApplicationCable
  class Channel < ActionCable::Channel::Base
    private

    # The user AS THEY ARE NOW, or nil when the session the socket was
    # opened with has ended or its user is gone. A connection's
    # `current_user` was loaded when the socket connected, perhaps hours
    # ago: its owner flag and its very existence are that old, and
    # `AccessControl` reads the owner flag off the object it is handed. So
    # every subscription is judged on this, never on `current_user` -- an
    # owner demoted since, or a user deleted since, is judged as what they
    # are. (The grants need no such care: they are read from the database
    # per unit of work, `AccessControl::ActorGrants`.) One query; a channel
    # rejects on nil.
    def subscriber
      @subscriber ||= User.where(id: Session.where(id: connection.session_id, user_id: current_user.id).select(:user_id)).first
    end
  end
end
