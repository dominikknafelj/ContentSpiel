require "test_helper"

# The known-device cookie through the real controller: a browser that
# signed in to an account before is not held by the account's lock a bot
# keeps closed, every other browser is, and a cookie that does not open or
# names another account is no cookie. Also what opens the account's bucket
# (a reset, the console) and the rate limit's key.
class SignInKnownDeviceTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  EMAIL = "ann@example.org".freeze
  PASSWORD = "password12345".freeze
  COOKIE = Admin::SignInCompletion::DEVICE_COOKIE.to_s

  setup do
    freeze_time
    @user = User.create!(email_address: EMAIL, password: PASSWORD)
    @guesses = 0
  end

  def sign_in(session = self, email: EMAIL, password: PASSWORD, **env)
    session.post admin_sign_in_path, params: { email_address: email, password: password }, env: env
  end

  # A bot's wrong guess, each from an address of its own behind a trusted
  # hop, so it meets the account's bucket and no address's.
  def bot_guess(bot)
    @guesses += 1
    bot.post admin_sign_in_path, params: { email_address: EMAIL, password: "guess#{@guesses}" },
      headers: { "X-Forwarded-For" => "198.51.#{@guesses / 250}.#{@guesses % 250 + 1}" }, env: { "REMOTE_ADDR" => "10.0.0.2" }
  end

  def locked_events = Audit::Event.where(action: "session.locked").order(:id)

  # The bot guesses until one of its guesses closes the account, and
  # answers the lock's seconds.
  def bot_locks(bot)
    before = locked_events.count
    bot_guess(bot) until locked_events.count > before
    locked_events.last.metadata.fetch("seconds")
  end

  def signed_in_here
    assert_redirected_to admin_root_path
    delete admin_sign_out_path
  end

  test "a bot that closes the account at every lock's end for a day does not keep the person out of the browser they signed in with" do
    sign_in
    signed_in_here
    assert cookies[COOKIE].present?

    bot = open_session
    elsewhere = open_session
    locks = 0
    ends = Time.current + 1.day
    while Time.current < ends
      seconds = bot_locks(bot)
      locks += 1
      travel 1.second

      sign_in(elsewhere)
      assert_equal I18n.t("admin.sessions.locked"), elsewhere.flash[:alert], "without the cookie the account's lock holds"
      sign_in
      signed_in_here

      travel seconds
    end

    assert_operator locks, :>=, 25
    assert_equal 60.minutes.to_i, locked_events.last.metadata["seconds"], "the person's sign-ins handed the bot no fresh run"
    assert_equal %w[account], locked_events.map { it.metadata["bucket"] }.uniq
  end

  test "a forged, a tampered and another account's cookie are no known device" do
    User.create!(email_address: "bea@example.org", password: "another-password-1")
    sign_in(email: "bea@example.org", password: "another-password-1")
    signed_in_here
    bea_cookie = cookies[COOKIE]
    bot_locks(open_session)

    sign_in
    assert_equal I18n.t("admin.sessions.locked"), flash[:alert], "a cookie that names another account"

    cookies[COOKIE] = "forged"
    sign_in
    assert_equal I18n.t("admin.sessions.locked"), flash[:alert], "a cookie that does not open"

    reset!
    travel 2.minutes
    sign_in
    signed_in_here
    valid = cookies[COOKIE]
    bot_locks(open_session)
    middle = valid.length / 2
    cookies[COOKIE] = valid[0...middle] + (valid[middle] == "A" ? "B" : "A") + valid[(middle + 1)..]
    sign_in
    assert_equal I18n.t("admin.sessions.locked"), flash[:alert], "a cookie changed by one character"

    cookies[COOKIE] = valid
    sign_in
    signed_in_here
    assert_not_equal bea_cookie, valid
  end

  test "a known device's own failures close that device alone, record session.locked for it and mail nothing" do
    sign_in
    signed_in_here

    assert_no_enqueued_jobs only: SignIn::Protection::LockoutMailJob do
      5.times { sign_in(password: "wrong") }
    end
    assert_equal I18n.t("admin.sessions.locked"), flash[:alert]
    assert_equal({ "bucket" => "device", "email_address" => EMAIL, "level" => 0, "seconds" => 60 }, locked_events.sole.metadata)
    sign_in
    assert_equal I18n.t("admin.sessions.locked"), flash[:alert], "the device's lock holds the right password too"

    other = open_session
    sign_in(other)
    assert_equal "/cs-studio", URI(other.response.location).path, "the account is open to another browser"
  end

  test "the cookie is set only on a right password: encrypted, HttpOnly, SameSite Lax, Secure over HTTPS, for 90 days, with no email in it" do
    sign_in(password: "wrong")
    assert_nil cookies[COOKIE]

    https!
    sign_in
    header = Array(response.headers["Set-Cookie"]).join("\n").lines.find { it.start_with?("#{COOKIE}=") }
    assert header, "the cookie is set"
    assert_match(/httponly/i, header)
    assert_match(/samesite=lax/i, header)
    assert_match(/secure/i, header)
    assert_equal (Time.current + 90.days).httpdate, header[/expires=([^;]+)/i, 1]
    assert_not_includes CGI.unescape(cookies[COOKIE]), "ann"
    assert_not_includes CGI.unescape(cookies[COOKIE]), "example.org"
  end

  test "a reset of the password opens the account to every browser" do
    bot_locks(open_session)
    sign_in
    assert_equal I18n.t("admin.sessions.locked"), flash[:alert]

    patch admin_update_password_path, params: { token: @user.password_reset_token, password: "a-new-password-1", password_confirmation: "a-new-password-1" }
    assert_redirected_to admin_sign_in_path

    fresh = open_session
    sign_in(fresh, password: "a-new-password-1")
    assert_equal "/cs-studio", URI(fresh.response.location).path
  end

  test "a reset opens the browser whose own failures closed it, at once, with the new password" do
    sign_in
    signed_in_here
    5.times { sign_in(password: "forgotten") }
    sign_in
    assert_equal I18n.t("admin.sessions.locked"), flash[:alert]
    assert_equal "device", locked_events.last.metadata["bucket"]

    patch admin_update_password_path, params: { token: @user.password_reset_token, password: "a-new-password-1", password_confirmation: "a-new-password-1" }
    sign_in(password: "a-new-password-1")
    signed_in_here
  end

  test "a password a manager sets in the user editor opens the account to every browser" do
    sign_in
    signed_in_here
    5.times { sign_in(password: "forgotten") }
    bot_locks(open_session)

    assert as(users(:one)) { Users::Save.call(@user, attributes: { password: "a-new-password-1", password_confirmation: "a-new-password-1" }) }.ok?
    sign_in(password: "a-new-password-1")
    signed_in_here
    fresh = open_session
    sign_in(fresh, password: "a-new-password-1")
    assert_equal "/cs-studio", URI(fresh.response.location).path
  end

  test "the console's password command opens the account" do
    bot_locks(open_session)

    assert Users::UpdatePassword.call(@user, password: "a-new-password-1", password_confirmation: "a-new-password-1").ok?
    sign_in(password: "a-new-password-1")
    signed_in_here
  end

  test "the rate limit counts an IPv6 visitor by their /64, and the store holds no address" do
    10.times { |index| sign_in(password: "wrong", "REMOTE_ADDR" => "2001:db8:1:2::#{index + 1}") }
    assert_equal I18n.t("admin.sessions.locked"), flash[:alert]

    sign_in(email: "bea@example.org", password: "wrong", "REMOTE_ADDR" => "2001:db8:1:2:ffff::9")
    assert_equal I18n.t("admin.sessions.limited"), flash[:alert]
    sign_in(email: "bea@example.org", password: "wrong", "REMOTE_ADDR" => "2001:db8:1:3::1")
    assert_equal I18n.t("admin.sessions.refused"), flash[:alert], "another /64 is another visitor"

    keys = SignIn.store.instance_variable_get(:@data).keys
    assert keys.any? { it.start_with?("rate-limit:") }
    keys.each { |key| assert_no_match(/2001:db8|2001-db8|127\.0\.0\.1|ann|example/, key) }
  end
end
