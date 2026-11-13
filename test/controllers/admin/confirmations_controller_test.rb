require "test_helper"

# Confirm it's you, through the real endpoints: the signed-in person proves
# it again with their password or one of their own passkeys, and the session
# is confirmed for Session::CONFIRM_WINDOW. A wrong proof counts in the
# account's bucket as a wrong password at sign-in does, and is
# `session.confirmation_failed`; a right one records nothing. The gate the
# confirmation opens (`Admin::RecentConfirmation`) is held through the four
# actions it guards, on the Account screen.
class Admin::ConfirmationsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  PASSWORD = "password".freeze
  WORDS = "admin.components.ui.confirm_identity_dialog".freeze

  setup do
    freeze_time
    site_settings(:default).update!(setup_completed_at: Time.current)
    @user = users(:reader)
    sign_in_as @user
    @session = Current.session
    travel Session::CONFIRM_WINDOW + 1.minute
  end

  def confirm_with_password(password)
    post admin_account_confirmation_path, params: { password: password }, as: :json
  end

  def options
    post admin_account_confirmation_options_path, as: :json
    assert_response :success
    response.parsed_body
  end

  def confirm_with_passkey(credential)
    post admin_account_confirmation_passkey_path, params: { credential: credential }, as: :json
  end

  def account_count
    digest = VisitorAddress.digest(User.normalize_value_for(:email_address, @user.email_address), purpose: SignIn::Protection::Throttle::KEY_PURPOSE)
    SignIn.store.read("sign_in:studio:account:#{digest}").to_i
  end

  def assert_error(status, key)
    assert_response status
    assert_equal({ "error" => I18n.t("#{WORDS}.#{key}") }, response.parsed_body)
  end

  test "a right password confirms the session for ten minutes and records nothing" do
    assert_not @session.reload.confirmed_recently?

    assert_no_difference -> { Audit::Event.count } do
      confirm_with_password(PASSWORD)
    end

    assert_response :ok
    assert_equal({ "confirmed" => true }, response.parsed_body)
    assert_equal Time.current, @session.reload.confirmed_at
    assert @session.confirmed_recently?(Time.current + Session::CONFIRM_WINDOW - 1.second)
    assert_not @session.confirmed_recently?(Time.current + Session::CONFIRM_WINDOW)
    assert_equal 0, account_count, "a right proof forgets the run"
  end

  test "a wrong password says so, records session.confirmation_failed, and counts in the account's bucket; the fifth answers limited" do
    4.times do |index|
      confirm_with_password("wrong-password")
      assert_error :unprocessable_entity, :wrong_password
      assert_equal index + 1, account_count
    end
    assert_empty Audit::Event.where(action: "session.locked")

    confirm_with_password("wrong-password")
    assert_error :too_many_requests, :limited
    locked = Audit::Event.where(action: "session.locked").sole
    assert_equal "account", locked.metadata["bucket"]
    assert_enqueued_jobs 1, only: SignIn::Protection::LockoutMailJob

    confirm_with_password(PASSWORD)
    assert_error :too_many_requests, :limited
    assert_not @session.reload.confirmed_recently?, "the right password meets the lock too"

    failed = Audit::Event.where(action: "session.confirmation_failed").order(:id).to_a
    assert_equal 5, failed.size, "the locked attempt checked nothing and records no failure"
    failed.each do |event|
      assert_equal @user.id, event.user_id
      assert_equal @user.id, event.subject_id
      assert_equal({ "method" => "password" }, event.metadata)
    end
  end

  test "a passkey confirms; another user's is refused with passkey_failed" do
    client = fake_authenticator
    passkey = add_passkey(@user, client: client)
    stranger = fake_authenticator
    other = users(:two)
    other_passkey = add_passkey(other, client: stranger, name: "Bea's")

    offered = options
    assert_equal [ passkey.external_id ], offered.fetch("allowCredentials").map { |credential| credential.fetch("id") },
      "the person's own passkeys alone are offered"
    confirm_with_passkey(passkey_assertion(stranger, challenge: offered.fetch("challenge"), user_handle: other.webauthn_id))
    assert_error :unprocessable_entity, :passkey_failed
    assert_nil other_passkey.reload.last_used_at
    assert_not @session.reload.confirmed_recently?
    assert_equal({ "method" => "passkey" }, Audit::Event.where(action: "session.confirmation_failed").sole.metadata)
    assert_equal 1, account_count

    challenge = options.fetch("challenge")
    confirm_with_passkey(passkey_assertion(client, challenge: challenge, user_handle: @user.webauthn_id))
    assert_response :ok
    assert_equal({ "confirmed" => true }, response.parsed_body)
    assert @session.reload.confirmed_recently?
    assert_not_nil passkey.reload.last_used_at
    assert_equal 0, account_count

    confirm_with_passkey(passkey_assertion(client, challenge: challenge, user_handle: @user.webauthn_id))
    assert_error :unprocessable_entity, :passkey_failed # a challenge is taken once
  end

  # The challenge is in a cookie of its own: a page sent with the session
  # cookie from before the options, answered after them, writes the session
  # back as it read it, and the challenge is still there for the answer.
  test "a request that writes the session back after the options leaves the challenge alone" do
    client = fake_authenticator
    add_passkey(@user, client: client)
    # A session that holds something, as a browser's does, so a page that
    # loads it writes it back.
    session_key = Rails.application.config.session_options.fetch(:key)
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.encrypted[session_key] = { value: { "held" => "1" } }
    cookies[session_key] = before_options = jar[session_key]

    challenge = options.fetch("challenge")
    cookies[session_key] = before_options
    # With forgery protection on, as outside tests, the page's CSRF meta
    # tags load the session, and the cookie store writes it back.
    begin
      ActionController::Base.allow_forgery_protection = true
      get admin_account_path
    ensure
      ActionController::Base.allow_forgery_protection = false
    end
    assert_response :success
    assert Array(response.headers["Set-Cookie"]).join("\n").include?("#{session_key}="), "the page wrote the session cookie back"

    confirm_with_passkey(passkey_assertion(client, challenge: challenge, user_handle: @user.webauthn_id))
    assert_response :ok
    assert @session.reload.confirmed_recently?
  end

  test "a person with no passkey is offered none" do
    post admin_account_confirmation_options_path, as: :json

    assert_response :not_found
  end

  test "a sign-in counts as a confirmation for ten minutes" do
    sign_out
    post admin_sign_in_path, params: { email_address: @user.email_address, password: PASSWORD }
    session = Session.sole

    assert_equal Time.current, session.confirmed_at
    assert session.confirmed_recently?
    travel Session::CONFIRM_WINDOW
    assert_not session.reload.confirmed_recently?
  end

  test "a signed-out request is sent to sign in and confirms nothing" do
    sign_out
    confirm_with_password(PASSWORD)

    assert_redirected_to admin_sign_in_path
  end
end
