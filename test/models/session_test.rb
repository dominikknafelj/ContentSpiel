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

  test "live holds a session exactly while expiry says nothing" do
    t = Time.zone.local(2026, 11, 11, 9, 0, 0)
    session = Session.start(user: @user, method: "password", user_agent: nil, ip_address: nil, at: t)
    live = ->(at) { Session.where(id: session.id).live(at).to_a }

    assert_equal [ session ], live.(t + 12.hours - 1.second)
    assert_empty live.(t + 12.hours)
    session.update_column(:last_seen_at, t + 14.days - 1.hour)
    assert_equal [ session ], live.(t + 14.days - 1.second)
    assert_empty live.(t + 14.days)
  end

  test "from_cookies ends an expired session and answers nil" do
    freeze_time
    session = Session.start(user: @user, method: "password", user_agent: nil, ip_address: nil)

    travel 12.hours do
      assert_nil Session.from_cookies(cookie_jar(session))
    end

    assert_not Session.exists?(session.id)
    event = Audit::Event.where(action: "session.ended").sole
    assert_equal({ "reason" => "expired_idle", "count" => 1, "after_hours" => 12 }, event.metadata)
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

  test "unlinking a user from single sign-on disconnects them, keeping nobody else's" do
    @user.update_columns(sso_issuer: "https://id.example.com", sso_subject: "sub-1", sso_linked_at: Time.current) # version: none (a test's setup)

    assert as(nil, channel: :console) { SignIn::Sso::Unlink.call(@user, actor: nil) }.ok?

    assert_equal 0, @user.sessions.count
    assert_equal [ DISCONNECT ] * 2, disconnects(@user)
    assert_empty disconnects(users(:two))
    assert Session.exists?(@other.id)
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

  test "a session starts confirmed at its sign-in and stays so for ten minutes" do
    t = Time.zone.local(2026, 11, 12, 9, 0, 0)
    session = Session.start(user: users(:reader), method: "password", user_agent: "UA", ip_address: "192.0.2.1", at: t)
    stamp = session.updated_at

    assert_equal t, session.confirmed_at
    assert session.confirmed_recently?(t + Session::CONFIRM_WINDOW - 1.second)
    assert_not session.confirmed_recently?(t + 10.minutes)

    travel_to(t + 10.minutes) do
      assert_not session.confirmed_recently?
      session.confirm!
      assert session.reload.confirmed_recently?
    end
    assert_equal stamp, session.updated_at
  end

  test "a session carries whether enrolment is due, false unless it is said" do
    assert_not Session.start(user: users(:reader), method: "password", user_agent: nil, ip_address: nil).enrolment_due
    assert Session.start(user: users(:reader), method: "password", user_agent: nil, ip_address: nil, enrolment_due: true).reload.enrolment_due
  end

  # The ending the session has when it is met at `at` (a session met is seen, so idleness is not in the way).
  def expiry_at(session, at) = session.tap { |row| row.last_seen_at = at }.expiry(at)

  def sso_session(token:, at:)
    Session.start(user: @user, method: "sso", user_agent: nil, ip_address: nil, provider_token: token, at: at)
  end

  test "an sso session with no token expires at 24 hours and one with a token at 26, as expired_sso" do
    t = Time.zone.local(2026, 11, 11, 9, 0, 0)
    bare = sso_session(token: nil, at: t)
    held = sso_session(token: "refresh-token", at: t)

    assert_equal t, bare.provider_checked_at
    assert_nil expiry_at(bare, t + 24.hours - 1.second)
    assert_equal "expired_sso", expiry_at(bare, t + 24.hours)
    assert_nil expiry_at(held, t + 26.hours - 1.second)
    assert_equal "expired_sso", expiry_at(held, t + 26.hours)

    assert_equal [ bare ], Session.expired_sso(t + 24.hours).to_a
    assert_equal [ bare, held ].sort_by(&:id), Session.expired_sso(t + 26.hours).sort_by(&:id)
    assert_empty Session.expired_sso(t + 23.hours)
    assert_equal({ "after_hours" => 24 }, Session.timeout_metadata("expired_sso"))
    assert_equal({ "after_hours" => 24 }, Session.timeout_metadata("expired_sso", bare))
    assert_equal({ "after_hours" => 26 }, Session.timeout_metadata("expired_sso", held))
  end

  test "a session of another method with a check date ends at 26 hours, token or not, and one with none is left alone" do
    t = Time.zone.local(2026, 11, 11, 9, 0, 0)
    gem_session = Session.start(user: @user, method: "password", user_agent: nil, ip_address: nil, at: t)
    gem_session.update_columns(provider_checked_at: t) # version: none (a test's own row)

    assert_nil expiry_at(gem_session, t + 25.hours)
    assert_equal "expired_sso", expiry_at(gem_session, t + 26.hours)
    assert_equal [ gem_session ], Session.expired_sso(t + 26.hours).to_a
    assert_empty Session.expired_sso(t + 25.hours)

    plain = Session.start(user: @user, method: "password", user_agent: nil, ip_address: nil, at: t)
    assert_nil plain.provider_checked_at
    assert_not_includes Session.expired_sso(t + 13.days), plain
  end

  test "a session may be made with a registered method and not with an unknown one" do
    SignIn::Methods.register("acme/saml", label: "acme.sign_in.saml", path: :admin_root_path)
    assert Session.start(user: @user, method: "acme/saml", user_agent: nil, ip_address: nil).persisted?
    assert_raises(ActiveRecord::RecordInvalid) { Session.start(user: @user, method: "acme/other", user_agent: nil, ip_address: nil) }
  ensure
    Rails.application.reloader.prepare!
  end

  test "a method with a recheck gets a check date and its token, and one without neither" do
    SignIn::Methods.register("acme/checked", label: "k", path: :admin_root_path, recheck: ->(_session) { :ok })
    SignIn::Methods.register("acme/unchecked", label: "k", path: :admin_root_path)
    t = Time.zone.local(2026, 11, 11, 9, 0, 0)
    checked = Session.start(user: @user, method: "acme/checked", user_agent: nil, ip_address: nil, provider_token: "tok", at: t)
    unchecked = Session.start(user: @user, method: "acme/unchecked", user_agent: nil, ip_address: nil, provider_token: "tok", at: t)

    assert_equal t, checked.provider_checked_at
    assert_equal "tok", checked.reload.provider_token
    assert_nil unchecked.provider_checked_at
    assert_nil unchecked.reload.provider_token
    assert_not_includes Session.expired_sso(t + 13.days), unchecked
  ensure
    Rails.application.reloader.prepare!
  end

  test "provider_check_due holds the sessions checked 24 hours ago or more" do
    t = Time.zone.local(2026, 11, 11, 9, 0, 0)
    held = sso_session(token: "refresh-token", at: t)

    assert_includes Session.provider_check_due(t + 24.hours), held
    assert_not_includes Session.provider_check_due(t + 24.hours - 1.second), held
  end

  test "the absolute timeout wins over expired_sso" do
    t = Time.zone.local(2026, 11, 11, 9, 0, 0)
    session = sso_session(token: nil, at: t)

    assert_equal "expired_sso", expiry_at(session, t + 30.hours)
    assert_equal "expired_absolute", expiry_at(session, t + 14.days)
  end

  test "a request that meets an SSO session past its check ends it as expired_sso" do
    t = Time.current
    bare = sso_session(token: nil, at: t - 24.hours)
    held = sso_session(token: "refresh-token", at: t - 26.hours)
    alive = sso_session(token: "refresh-token", at: t - 26.hours + 1.second)
    [ bare, held, alive ].each { |row| row.update_columns(last_seen_at: t) } # version: none (a test's own rows)

    assert_nil Session.from_cookies(cookie_jar(bare), at: t)
    assert_nil Session.from_cookies(cookie_jar(held), at: t)
    assert_equal alive, Session.from_cookies(cookie_jar(alive), at: t)
    assert_nil Session.find_by(id: bare.id)
    assert_nil Session.find_by(id: held.id)
    assert_equal [ [ "expired_sso", 24 ], [ "expired_sso", 26 ] ],
      Audit::Event.where(action: "session.ended").order(:id).last(2).map { |e| [ e.metadata["reason"], e.metadata["after_hours"] ] }
  end

  test "without encryption keys an sso session starts with no token" do
    without_encryption_keys do
      session = sso_session(token: "refresh-token", at: Time.current)
      assert_nil session.reload.provider_token
      assert_not_nil session.provider_checked_at
    end
  end

  test "without encryption keys an SSO session with a token still expires at 26 hours, read without decrypting" do
    t = Time.zone.local(2026, 11, 11, 9, 0, 0)
    held = sso_session(token: "refresh-token", at: t)
    without_encryption_keys do
      row = Session.find(held.id)
      assert_nil expiry_at(row, t + 26.hours - 1.second)
      assert_equal "expired_sso", expiry_at(row, t + 26.hours)
      assert_equal({ "after_hours" => 26 }, Session.timeout_metadata("expired_sso", row))
    end
  end

  test "the provider token is stored encrypted" do
    session = sso_session(token: "refresh-token-plain", at: Time.current)
    raw = Session.connection.select_value("SELECT provider_token FROM sessions WHERE id = #{session.id.to_i}") # sql: a test reads the raw column

    assert_not_nil raw
    assert_not_includes raw, "refresh-token-plain"
    assert_equal "refresh-token-plain", session.reload.provider_token
  end

  test "a session of a method that is never asked again stores no provider token" do
    session = Session.start(user: @user, method: "password", user_agent: nil, ip_address: nil, provider_token: "refresh-token")

    assert_nil session.reload.provider_token
    assert_nil session.provider_checked_at
  end
end
