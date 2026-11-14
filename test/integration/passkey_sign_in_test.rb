require "test_helper"

# Signing in with a passkey alone, through the real controller and the
# webauthn gem's fake authenticator (`PasskeyHelper`): the options, the
# challenge kept in its cookie, the assertion, and what a success writes.
# Every answer is 200 JSON naming where to go, so a script can't tell one
# refusal from another; a refusal's sentence is the flash of the page it
# names.
class PasskeySignInTest < ActionDispatch::IntegrationTest
  include LogCapture

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

  CHALLENGE_COOKIE = "#{PasskeyChallenges::COOKIE_PREFIX}sign_in".freeze

  # The sign-in challenge's cookie holding `values`, encrypted as the
  # concern writes it: an integration test has no other way into it.
  def plant_challenge(values)
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.encrypted[CHALLENGE_COOKIE] = { value: values.deep_stringify_keys }
    cookies[CHALLENGE_COOKIE] = jar[CHALLENGE_COOKIE]
  end

  # The challenge's cookie as the browser holds it now, to send again later
  # as someone who copied it would.
  def saved_challenge_cookie = cookies[CHALLENGE_COOKIE]

  def send_again_with(saved_cookie, credential)
    cookies.delete("session_id")
    cookies[CHALLENGE_COOKIE] = saved_cookie
    send_passkey(credential)
  end

  test "a passkey signs its person in, with the passkey method, the known-device cookie and session.created saying passkey" do
    location = send_passkey(assertion(options.fetch("challenge")))

    assert_equal admin_root_url, location
    session = Session.sole
    assert_equal @user, session.user
    assert_equal "passkey", session.authenticated_with
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
    # Made by a synced passkey, whose counter stays 0, so the counter alone
    # would let a second sending through.
    first = assertion(options.fetch("challenge"), sign_count: 0)
    before_first = saved_challenge_cookie
    assert_equal admin_root_url, send_passkey(first)
    assert_equal 1, Session.count
    assert_nil cookies[CHALLENGE_COOKIE].presence, "the take deletes the challenge's cookie"

    # Twice: sent again after the first answer deleted the challenge's
    # cookie, and with that cookie as it was before (which still holds it,
    # as a copy taken by whoever captured the assertion would): both are
    # refused, the second by the challenge's spent mark on the server.
    cookies.delete("session_id")
    refused_to_sign_in_page(send_passkey(first))
    refused_to_sign_in_page(send_again_with(before_first, first))
    assert_equal 1, Session.count

    # A refused answer spends its challenge too: the right assertion for it,
    # sent after a wrong one with the cookie that still holds it, is refused.
    challenge = options.fetch("challenge")
    before_wrong = saved_challenge_cookie
    refused_to_sign_in_page(send_passkey("not a credential"))
    refused_to_sign_in_page(send_again_with(before_wrong, assertion(challenge, sign_count: 0)))

    # Late: answered one second past the five minutes.
    late = assertion(options.fetch("challenge"))
    travel PasskeyChallenges::LIFETIME + 1.second
    refused_to_sign_in_page(send_passkey(late))

    # Another purpose: a registration's challenge in the sign-in cookie, and
    # a sign-in assertion made for it.
    challenge = WebAuthn.standard_encoder.encode(SecureRandom.random_bytes(32))
    plant_challenge(purpose: "register", challenge: challenge, at: Time.current.to_i)
    refused_to_sign_in_page(send_passkey(assertion(challenge)))

    # A fresh challenge signs in.
    travel PACE
    assert_equal admin_root_url, send_passkey(assertion(options.fetch("challenge")))
    assert_equal 2, Session.count
  end

  test "the challenge's cookie lasts the browser's session, and the server alone refuses it after five minutes" do
    challenge = options.fetch("challenge")
    written = Array(response.headers["Set-Cookie"]).flat_map { |line| line.split("\n") }.find { |line| line.start_with?("#{CHALLENGE_COOKIE}=") }

    assert written, "the options write the challenge's cookie"
    assert_no_match(/expires=|max-age=/i, written, "no date of the browser's own: a clock ahead of the server's would drop it at once")

    late = assertion(challenge)
    travel PasskeyChallenges::LIFETIME + 1.second
    assert saved_challenge_cookie.present?, "the browser still sends the cookie"
    refused_to_sign_in_page(send_passkey(late))
    assert_equal 0, Session.count
  end

  test "a database error while a challenge is spent refuses the passkey, signs nobody in and logs the error's class alone" do
    [ ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished ].each do |error|
      credential = assertion(options.fetch("challenge"))

      log = capture_log do
        with_singleton_override(SignIn::SpentChallenge, :insert_all, ->(*, **) { raise error, "the insert failed" }) do
          refused_to_sign_in_page(send_passkey(credential))
        end
      end
      assert_equal [ "[sign-in] a value could not be spent (#{error}), so it is refused" ], log.lines.map(&:strip).grep(/\[sign-in\]/)
      assert_not_includes log, "the insert failed"
      travel PACE
    end
    assert_equal 0, Session.count
  end

  test "an error of the code's own while a challenge is spent is not taken for the database's" do
    credential = assertion(options.fetch("challenge"))

    with_singleton_override(SignIn::SpentChallenge, :insert_all, ->(*, **) { raise ActiveRecord::ReadOnlyError, "a write in a read-only block" }) do
      assert_raises(ActiveRecord::ReadOnlyError) { send_passkey(credential) }
    end
    assert_equal 0, Session.count
  end

  test "the options are limited per address on a count of their own: the thirty-first in a minute is a bare 429 that keeps no challenge" do
    30.times { options }
    cookies.delete(CHALLENGE_COOKIE)

    post admin_sign_in_passkey_options_path, as: :json

    assert_response :too_many_requests
    assert_empty response.body
    assert saved_challenge_cookie.blank?, "no challenge is kept"
    post admin_sign_in_path, params: { email_address: EMAIL, password: PASSWORD }
    assert_not_equal I18n.t("admin.sessions.limited"), flash[:alert], "a password is not counted with the options"

    travel 1.minute + 1.second
    options
  end

  test "under a policy that covers everyone a passkey sign-in owes no enrolment, a password sign-in without a passkey does, and auth.policy is on the request's span" do
    site_settings(:default).update!(passkey_policy: "everyone")
    exporter = Rails.application.config.x.otel_test_exporter
    exporter.reset

    send_passkey(assertion(options.fetch("challenge")))

    assert_not Session.sole.enrolment_due
    span = exporter.finished_spans.find { |each| each.kind == :server && each.attributes["auth.policy"] }
    assert span, "the passkey sign-in's request span carries auth.policy"
    assert_equal "everyone", span.attributes["auth.policy"]

    delete admin_sign_out_path
    User.create!(email_address: "bea@example.org", password: PASSWORD)
    post admin_sign_in_path, params: { email_address: "bea@example.org", password: PASSWORD }
    assert_redirected_to admin_root_path
    assert Session.find_by!(user: User.find_by!(email_address: "bea@example.org")).enrolment_due
  end

  test "with forgery protection on, both endpoints refuse a POST without the page's token and answer one with it" do
    before = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    post admin_sign_in_passkey_options_path, as: :json
    assert_response :unprocessable_content
    post admin_sign_in_passkey_path, params: { credential: "{}" }, as: :json
    assert_response :unprocessable_content
    assert_equal 0, Session.count

    get admin_sign_in_path
    token = css_select("meta[name=csrf-token]").first["content"]
    post admin_sign_in_passkey_options_path, as: :json, headers: { "X-CSRF-Token" => token }
    assert_response :success
    challenge = response.parsed_body.fetch("challenge")
    post admin_sign_in_passkey_path, params: { credential: assertion(challenge) }, as: :json, headers: { "X-CSRF-Token" => token }
    assert_response :success
    assert_equal admin_root_url, response.parsed_body.fetch("location")
  ensure
    ActionController::Base.allow_forgery_protection = before
  end

  test "a passkey signs in an account whose email bucket a bot holds closed" do
    # The bot's wrong passwords, each from its own address behind a trusted
    # hop, until the account's bucket is closed.
    (SignIn::Protection::Throttle::ACCOUNT_FREE_FAILURES + 1).times do |index|
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
    assert_select "[data-passkey-sign-in-target=divider][hidden]", text: I18n.t("admin.components.ui.or_divider.or")
    assert_select "input[name=email_address][autocomplete='username webauthn']"
  end
end
