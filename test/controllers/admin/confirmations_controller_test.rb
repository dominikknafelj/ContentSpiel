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
    digest = VisitorAddress.digest(User.normalize_value_for(:email_address, @user.email_address), purpose: SignIn::Throttle::KEY_PURPOSE)
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
    assert_enqueued_jobs 1, only: SignIn::LockoutMailJob

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
