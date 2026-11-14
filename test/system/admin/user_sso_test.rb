require "application_system_test_case"

# The user editor's Single sign-on zone in a real browser: Unlink… opens the
# dialog, Unlink unlinks, the toast says so and the badge and the zone go.
class Admin::UserSsoSystemTest < ApplicationSystemTestCase
  include OidcHelper

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @target = link_to_sso(users(:reader))
    # The toast promises the mail only when mail is ready.
    put_mail_state(:working)
    sign_in_via_form(users(:one))
  end

  test "Unlink… then Unlink unlinks, with the toast, and the badge is gone" do
    visit_screen edit_admin_user_path(@target)
    assert_selector "[data-sso-badge]", text: "Signs in with id.example.com"

    click_button "Unlink…"
    within("dialog#sso-user-#{@target.id}") do
      assert_text "Unlink reader@example.com from id.example.com?"
      press "Unlink"
    end

    assert_text "reader@example.com is unlinked from id.example.com. A mail to set a password is on its way."
    assert_no_selector "[data-sso-badge]"
    assert_no_selector "[data-zone=sso]"
    assert_not @target.reload.sso_linked?
  end
end
