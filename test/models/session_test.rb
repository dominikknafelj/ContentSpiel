require "test_helper"

# A session that ends takes its cable with it (`Session#disconnect_cable`):
# every path that ends one disconnects that user's WebSockets, after the
# commit, and nobody else's. Sign-out, the fourth path, is a request:
# `test/integration/sessions_test.rb`.
class SessionTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  DISCONNECT = { "type" => "disconnect", "reconnect" => true }.freeze

  setup do
    @user = users(:reader)
    @sessions = Array.new(2) { Session.start(user: @user, method: "password", user_agent: nil, ip_address: nil) }
    @other = Session.start(user: users(:two), method: "password", user_agent: nil, ip_address: nil)
  end

  # Action Cable's own name for the channel a user's connections listen on.
  def cable_of(user) = "action_cable/#{user.to_gid_param}"

  def disconnects(user) = broadcasts(cable_of(user)).map { |payload| ActiveSupport::JSON.decode(payload) }

  def cookie_jar(session) = ActionDispatch::TestRequest.create.cookie_jar.tap { |jar| jar.signed[:session_id] = session&.id }

  test "a new session is seen now and ends fourteen days on" do
    t = Time.zone.local(2026, 11, 11, 9, 0, 0)
    session = Session.start(user: users(:reader), method: "password", user_agent: "UA", ip_address: "192.0.2.1", at: t)

    assert_equal t, session.last_seen_at
    assert_equal t + 14.days, session.expires_at
    assert_equal "password", session.authenticated_with
  end

  test "a method outside METHODS is refused" do
    assert_raises(ActiveRecord::RecordInvalid) do
      Session.start(user: users(:reader), method: "magic", user_agent: "UA", ip_address: "192.0.2.1")
    end
  end

  test "the one lookup: a signed cookie's session, and nil for none" do
    assert_equal @other, Session.from_cookies(cookie_jar(@other))
    assert_nil Session.from_cookies(cookie_jar(nil))
    assert_nil Session.from_cookies(ActionDispatch::TestRequest.create.cookie_jar.tap { |jar| jar[:session_id] = @other.id.to_s })
    @other.destroy!
    assert_nil Session.from_cookies(cookie_jar(@other))
  end

  test "a session unused for 12 hours is idle-expired, one at 14 days absolute, and absolute wins" do
    t = Time.zone.local(2026, 11, 11, 9, 0, 0)
    session = Session.start(user: @user, method: "password", user_agent: nil, ip_address: nil, at: t)

    travel_to(t + 12.hours - 1.second) { assert_nil session.expiry }
    travel_to(t + 12.hours) { assert_equal "expired_idle", session.expiry }

    session.update_column(:last_seen_at, t + 14.days - 1.hour)
    travel_to(t + 14.days - 1.second) { assert_nil session.expiry }
    travel_to(t + 14.days) { assert_equal "expired_absolute", session.expiry }

    session.update_column(:last_seen_at, t)
    travel_to(t + 14.days) { assert_equal "expired_absolute", session.expiry, "both hold: the absolute timeout wins" }
  end

  test "from_cookies ends an expired session and answers nil" do
    freeze_time
    session = Session.start(user: @user, method: "password", user_agent: nil, ip_address: nil)

    travel 12.hours do
      assert_nil Session.from_cookies(cookie_jar(session))
    end

    assert_not Session.exists?(session.id)
    event = Audit::Event.where(action: "session.ended").sole
    assert_equal({ "reason" => "expired_idle", "count" => 1 }, event.metadata)
    assert_nil event.actor_id
    assert_nil event.user_id
    assert_equal @user, event.subject
    assert_equal [ DISCONNECT ], disconnects(@user)
    assert_equal @sessions.map(&:id).sort, @user.sessions.ids.sort, "one expired session ends, not the user's others"
  end

  test "from_cookies writes last_seen_at at most every five minutes and never updated_at" do
    t = Time.zone.local(2026, 11, 11, 9, 0, 0)
    session = Session.start(user: @user, method: "password", user_agent: nil, ip_address: nil, at: t)
    updated_at = session.reload.updated_at

    assert_equal session, Session.from_cookies(cookie_jar(session), at: t + 4.minutes)
    assert_equal t, session.reload.last_seen_at
    assert_equal updated_at, session.updated_at

    assert_equal session, Session.from_cookies(cookie_jar(session), at: t + 5.minutes)
    assert_equal t + 5.minutes, session.reload.last_seen_at
    assert_equal updated_at, session.updated_at
  end

  test "a destroyed session disconnects its user's cable after the commit, and not when rolled back" do
    Session.transaction do
      @sessions.first.destroy!
      raise ActiveRecord::Rollback
    end
    assert_empty disconnects(@user)

    Session.transaction do
      @sessions.first.destroy!
      assert_empty disconnects(@user), "sent before the commit"
    end

    assert_equal [ DISCONNECT ], disconnects(@user)
    assert_empty disconnects(users(:two))
  end

  test "changing a password ends the user's sessions and disconnects them, keeping nobody else's" do
    result = as(nil) { Users::UpdatePassword.call(@user, password: "brand-new-pass", password_confirmation: "brand-new-pass", actor: @user, keep_acting_session: false) }

    assert result.ok?, result.errors.inspect
    assert_equal 0, @user.sessions.count
    assert_equal [ DISCONNECT ] * 2, disconnects(@user)
    assert_empty disconnects(users(:two))
    assert Session.exists?(@other.id)
  end

  # The session the change is made in stays, and its tabs are told to
  # reconnect like the rest: they pass, the ended ones are rejected at
  # connect (`test/channels/application_cable/connection_test.rb`).
  test "changing one's own password disconnects for the ended sessions, and the kept one can connect again" do
    result = Current.set(actor: @user, channel: :admin, session: @sessions.first) do
      Users::UpdatePassword.call(@user, password: "brand-new-pass", password_confirmation: "brand-new-pass", actor: @user)
    end

    assert result.ok?, result.errors.inspect
    assert_equal [ @sessions.first.id ], @user.sessions.ids
    assert_equal [ DISCONNECT ], disconnects(@user)
    assert_equal @sessions.first, Session.from_cookies(cookie_jar(@sessions.first))
    assert_nil Session.from_cookies(cookie_jar(@sessions.last))
  end

  test "an admin setting someone's password disconnects that user, and a save without a password nobody" do
    assert Users::Save.call(@user, attributes: { name: "Renamed" }, actor: nil).ok?
    assert_empty disconnects(@user)

    result = Users::Save.call(@user, attributes: { password: "new-password-1", password_confirmation: "new-password-1" }, actor: nil)

    assert result.ok?, result.errors.inspect
    assert_equal 0, @user.sessions.count
    assert_equal [ DISCONNECT ] * 2, disconnects(@user)
    assert_empty disconnects(users(:two))
  end

  test "deleting a user disconnects them, by an id that outlives the row" do
    cable = cable_of(@user)

    assert Users::Destroy.call(@user, actor: nil).ok?

    assert_equal [ DISCONNECT ] * 2, broadcasts(cable).map { |payload| ActiveSupport::JSON.decode(payload) }
    assert_empty disconnects(users(:two))
    assert Session.exists?(@other.id)
  end

  # The session is ended either way: a cable that is away is reported and
  # logged by the error's class alone, and never fails the sign-out.
  test "a disconnect that fails is logged and the session is still ended" do
    broken = Class.new(ActionCable::SubscriptionAdapter::Test) { def broadcast(*) = raise(IOError, "the cable is down") }
    ActionCable.server.instance_variable_set(:@pubsub, broken.new(ActionCable.server)) # put back by ActionCable::TestHelper's teardown
    log = StringIO.new
    logger = ActiveSupport::Logger.new(log)
    Rails.logger.broadcast_to(logger)

    assert_nothing_raised { @sessions.first.destroy! }

    assert_not Session.exists?(@sessions.first.id)
    assert_equal [ "Cable disconnect not sent for an ended session: IOError" ], log.string.lines.grep(/Cable disconnect/).map(&:strip)
    assert_no_match(/cable is down/, log.string)
  ensure
    Rails.logger.stop_broadcasting_to(logger) if logger
  end
end
