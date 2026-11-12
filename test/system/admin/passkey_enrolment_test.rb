require "application_system_test_case"

# Enrolment as a person meets it: the passkey policy covers them, they hold
# no passkey, and signing in lands them on the enrolment page, where Add
# passkey opens Chrome's virtual authenticator (`with_virtual_authenticator`)
# at once, the codes follow in place of the page, and Done goes where the
# sign-in was going.
class Admin::PasskeyEnrolmentSystemTest < ApplicationSystemTestCase
  CODES_TEXT = "#enrolment [data-admin--ui--recovery-codes-target=list]".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current, passkey_policy: "everyone")
    @user = users(:one)
  end

  test "enrolment adds a passkey and shows the codes" do
    with_virtual_authenticator do
      visit admin_sign_in_path
      fill_in "Email", with: @user.email_address
      fill_in "Password", with: "password"
      press "Sign in"

      assert_selector "#enrolment h1", text: I18n.t("admin.enrolment.show.title"), wait: 15
      assert_current_path admin_enrolment_path
      add = find("#enrolment button[type=submit]", text: I18n.t("admin.enrolment.show.add"))

      add.click
      assert_selector "#enrolment [role=alert]", text: I18n.t("admin.components.account_screen.passkey_dialog.name_blank")
      assert_empty @user.passkeys.reload

      fill_in I18n.t("admin.enrolment.show.name"), with: "This browser"
      add.click

      assert_selector "#enrolment h1", text: I18n.t("admin.components.ui.recovery_codes.title")
      codes = find(CODES_TEXT, visible: :all).text(:all).split
      assert_equal RecoveryCode::COUNT, codes.size
      assert_equal "This browser", @user.passkeys.reload.sole.name
      assert_not Session.where(user: @user).any?(&:enrolment_due?)

      check I18n.t("admin.components.ui.recovery_codes.saved")
      press I18n.t("admin.components.ui.recovery_codes.done")

      assert_selector "nav[aria-label='Modules']", wait: 15
      assert_current_path admin_root_path
      assert_not_includes page.html, codes.first, "no code is left in the page"
    end
  end
end
