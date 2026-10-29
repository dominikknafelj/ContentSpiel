require "application_system_test_case"

# Settings → Mail in a real browser (spec "Settings → Mail", design answer
# M2): "Send test mail" uses the SAVED settings, so it waits while the
# Settings form holds unsaved changes. The suite's mail is Rails' `:test`
# delivery (the stand-in), so a send succeeds without a server.
class Admin::SettingsMailSystemTest < ApplicationSystemTestCase
  setup do
    MailTestLimit.store.clear
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
  end

  def test_button = "button[form='settings-mail-test-form']"

  test "Send test mail is disabled with Save your changes first while the form has unsaved changes, and enabled after Save" do
    visit "/cs-studio/settings"
    await_admin_controllers

    assert_selector "#{test_button}:not([disabled])", text: "Send test mail"
    assert_no_text "Save your changes first"

    fill_in "Sender name", with: "The Test Site"
    assert_selector "#{test_button}[disabled]"
    assert_selector "#settings-mail-test", text: "Save your changes first"

    click_on "Save"
    assert_selector "#toasts .admin-toast", text: "Settings saved"
    await_admin_controllers
    assert_selector "#{test_button}:not([disabled])"
    assert_no_text "Save your changes first"

    find(test_button).click
    assert_selector "#settings-mail-test", text: "Test mail sent to one@example.com. Check your inbox."
    assert_selector "#settings-mail-state[data-mail-state=working]", text: "Working"
    assert_selector "#{test_button}:not([disabled])"
  end
end
