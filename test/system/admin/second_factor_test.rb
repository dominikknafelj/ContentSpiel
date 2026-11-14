require "application_system_test_case"

# The second step as a person meets it: the password on the sign-in page,
# then a passkey (Chrome's virtual authenticator, `PasskeyHelper`) or one
# of the recovery codes. The product layout loads the `application` entry
# point only, so a test waits for what the page shows: "Use your passkey"
# enabled once its options have arrived (`passkey-sign-in`).
class Admin::SecondFactorSystemTest < ApplicationSystemTestCase
  READY = "button[data-passkey-sign-in-target=button]:not([hidden]):not([disabled])".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @user = users(:one)
  end

  def password_step
    visit admin_sign_in_path
    fill_in "Email", with: @user.email_address
    fill_in "Password", with: "password"
    press "Sign in"
    assert_selector "h1", text: "Confirm it's you"
  end

  test "password, then the passkey, signs in" do
    with_virtual_authenticator do |authenticator|
      passkey = add_virtual_passkey(@user, authenticator)
      password_step
      assert_text "Use your passkey to finish signing in as #{@user.email_address}."
      assert_selector READY, text: "Use your passkey"
      assert_equal 0, Session.count

      press "Use your passkey"

      assert_selector "nav[aria-label='Modules']", wait: 15
      assert_equal "passkey", Session.sole.authenticated_with
      assert_not_nil passkey.reload.last_used_at
    end
  end

  test "Use a recovery code, then a code, lands on Your account" do
    add_passkey(@user, client: fake_authenticator)
    code = RecoveryCode.texts.first
    @user.recovery_codes.create!(digest: RecoveryCode.digest(code), generated_at: Time.current)
    password_step

    press "Use a recovery code"
    fill_in "Recovery code", with: code
    press "Sign in"

    assert_current_path admin_account_path, wait: 15
    assert_equal "recovery_code", Session.sole.authenticated_with
  end
end
