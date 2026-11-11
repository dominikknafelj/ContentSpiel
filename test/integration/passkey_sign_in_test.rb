require "test_helper"

# Signing in with a passkey alone, through the real controller and the
# webauthn gem's fake authenticator (`PasskeyHelper`): the options, the
# challenge kept in the session, the assertion, and what a success writes.
# Every answer is 200 JSON naming where to go, so a script can't tell one
# refusal from another; a refusal's sentence is the flash of the page it
# names.
class PasskeySignInTest < ActionDispatch::IntegrationTest
  EMAIL = "ann@example.org".freeze
  PASSWORD = "password12345".freeze
  # Past the per-address rate limit's pace (10 in 3 minutes), so a run of
  # attempts meets only the throttle's buckets.
  PACE = 20.seconds

  setup do
    freeze_time
    site_settings(:default).update!(setup_completed_at: Time.current)
    @user = User.create!(email_address: EMAIL, password: PASSWORD)
    @client = fake_authenticator
    @passkey = add_passkey(@user, client: @client)
  end

  def options
    post admin_sign_in_passkey_options_path, as: :json
    assert_response :success
    response.parsed_body
  end

  def assertion(challenge, client: @client, user: @user, sign_count: nil)
    passkey_assertion(client, challenge: challenge, user_handle: user.webauthn_id, sign_count: sign_count)
  end

  def send_passkey(credential)
    post admin_sign_in_passkey_path, params: { credential: credential }, as: :json
    assert_response :success
    response.parsed_body.fetch("location")
  end

  def refused_to_sign_in_page(location, sentence = I18n.t("admin.sessions.passkey_failed"))
    assert_equal admin_sign_in_path, location
    assert_equal sentence, flash[:alert]
    assert_nil cookies["session_id"].presence
  end

  # The session cookie holding `values`, encrypted as the cookie store
  # writes it: an integration test has no other way into the session.
  def plant_session(values)
    key = Rails.application.config.session_options.fetch(:key)
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.encrypted[key] = { value: values.deep_stringify_keys }
    cookies[key] = jar[key]
  end

  test "a passkey signs its person in, with the passkey method, the known-device cookie and session.created saying passkey" do
    location = send_passkey(assertion(options.fetch("challenge")))

    assert_equal admin_root_url, location
    session = Session.sole
    assert_equal @user, session.user
    assert_equal "passkey", session.authenticated_with
    assert_not session.enrolment_due
    assert cookies[Admin::SignInCompletion::DEVICE_COOKIE.to_s].present?
    event = Audit::Event.where(action: "session.created").sole
    assert_equal @user.id, event.subject_id
    assert_equal({ "method" => "passkey" }, event.metadata)
    assert_not_nil @passkey.reload.last_used_at
    get admin_root_path
    assert_response :success
  end

  test "an unknown passkey answers the sign-in page with passkey_failed and counts in the address's wide bucket" do
    stranger = fake_authenticator
    other = User.create!(email_address: "bea@example.org", password: PASSWORD)
    passkey_registration(other, client: stranger)

    refused_to_sign_in_page(send_passkey(assertion(options.fetch("challenge"), client: stranger, user: other)))
    assert_equal 0, Audit::Event.where(action: %w[session.created session.failed]).count
    travel PACE

    # 49 more refusals fill the address's wide bucket (50 in an hour); the
    # fiftieth is recorded as the lock it closed, and the next attempt from
    # the address, a right password, meets the closed bucket.
    49.times do
      refused_to_sign_in_page(send_passkey("not a credential"))
      travel PACE
    end
    assert_equal "address_wide", Audit::Event.where(action: "session.locked").sole.metadata.fetch("bucket")
    post admin_sign_in_path, params: { email_address: EMAIL, password: PASSWORD }
    assert_redirected_to admin_sign_in_path
    assert_equal I18n.t("admin.sessions.limited"), flash[:alert]
    refused_to_sign_in_page(send_passkey(assertion(options.fetch("challenge"))), I18n.t("admin.sessions.limited"))
    assert_equal 0, Session.count
  end

  test "an assertion sent twice, one after five minutes and one made for another purpose's challenge are refused, and the second press works with a fresh challenge" do
    # Twice: the first signs in; the same answer again, from a browser
    # with no session, meets no challenge. Made by a synced passkey, whose
    # counter stays 0, so the counter alone would let it through.
    first = assertion(options.fetch("challenge"), sign_count: 0)
    assert_equal admin_root_url, send_passkey(first)
    cookies.delete("session_id")
    refused_to_sign_in_page(send_passkey(first))
    assert_equal 1, Session.count

    # Late: answered one second past the five minutes.
    late = assertion(options.fetch("challenge"))
    travel PasskeyChallenges::LIFETIME + 1.second
    refused_to_sign_in_page(send_passkey(late))

    # Another purpose: a registration's challenge kept in the session, and
    # a sign-in assertion made for it.
    challenge = WebAuthn.standard_encoder.encode(SecureRandom.random_bytes(32))
    plant_session(passkey_challenge: { purpose: "register", challenge: challenge, at: Time.current.to_i })
    refused_to_sign_in_page(send_passkey(assertion(challenge)))

    # Each refusal spent its challenge, and a fresh one signs in.
    travel PACE
    assert_equal admin_root_url, send_passkey(assertion(options.fetch("challenge")))
    assert_equal 2, Session.count
  end

  test "a passkey signs in an account whose email bucket a bot holds closed" do
    # The bot's wrong passwords, each from its own address behind a trusted
    # hop, until the account's bucket is closed.
    (SignIn::Throttle::ACCOUNT_FREE_FAILURES + 1).times do |index|
      post admin_sign_in_path, params: { email_address: EMAIL, password: "guess#{index}" },
        headers: { "X-Forwarded-For" => "198.51.100.#{index + 1}" }, env: { "REMOTE_ADDR" => "10.0.0.2" }
    end
    post admin_sign_in_path, params: { email_address: EMAIL, password: PASSWORD }
    assert_equal I18n.t("admin.sessions.locked"), flash[:alert]

    assert_equal admin_root_url, send_passkey(assertion(options.fetch("challenge")))
    assert_equal @user, Session.sole.user
  end

  test "with an IP request host there is no passkey button and both endpoints answer 404" do
    host! "127.0.0.1"

    get admin_sign_in_path
    assert_response :success
    assert_select "[data-controller~='passkey-sign-in']", count: 0
    post admin_sign_in_passkey_options_path, as: :json
    assert_response :not_found
    post admin_sign_in_passkey_path, params: { credential: "{}" }, as: :json
    assert_response :not_found

    host! "www.example.com"
    get admin_sign_in_path
    assert_select "[data-controller~='passkey-sign-in'] button[hidden][data-passkey-sign-in-target=button]", text: I18n.t("admin.sessions.new.passkey")
    assert_select "[data-passkey-sign-in-target=divider][hidden]", text: I18n.t("admin.sessions.new.or")
    assert_select "input[name=email_address][autocomplete='username webauthn']"
  end
end
