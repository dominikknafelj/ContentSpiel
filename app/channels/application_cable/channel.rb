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
    # per unit of work, `AccessControl::ActorGrants`.) The session must be
    # live too (`Session.live`, the rule `Session.from_cookies` ends by): a
    # socket open since before its session passed either timeout subscribes
    # to nothing, though its row stands until a request or the sweep ends it.
    # A session held at enrolment (`Admin::PasskeyEnrolment`) subscribes to
    # nothing either, as its requests reach nothing of CS Studio.
    # One query; a channel rejects on nil.
    def subscriber
      sessions = Session.live(Time.current).where(id: connection.session_id, user_id: current_user.id, enrolment_due: false)
      @subscriber ||= User.where(id: sessions.select(:user_id)).first
    end
  end
end
