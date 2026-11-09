require "application_system_test_case"
require "support/held_test_mail"

# Settings → Mail in a real browser: "Send test mail" uses the SAVED
# settings, so it waits while the Settings form holds unsaved changes. The
# suite's mail is Rails' `:test` delivery (the stand-in), so a send succeeds
# without a server.
class Admin::SettingsMailSystemTest < ApplicationSystemTestCase
  include HeldTestMail

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

    click_on "Save changes"
    assert_selector "#toasts .admin-toast", text: "Settings saved"
    await_admin_controllers
    assert_selector "#{test_button}:not([disabled])"
    assert_no_text "Save your changes first"

    find(test_button).click
    assert_selector "#settings-mail-test", text: "Test mail sent to one@example.com. Check your inbox."
    assert_selector "#settings-mail-state[data-mail-state=working]", text: "Working"
    assert_selector "#settings-glance-mail .admin-state-chip[data-state-tone=ok]", text: "Working"
    assert_selector "#{test_button}:not([disabled])"
  end

  test "Send test mail shows it is working while the mail is on its way, and a second press sends nothing" do
    visit "/cs-studio/settings"
    await_admin_controllers

    with_held_test_mail do |entered, release, calls|
      press "Send test mail"
      entered.pop
      assert_selector "#{test_button}[disabled][aria-busy=true]", text: "Sending…"
      find(test_button).click # a native click on the disabled button: nothing is sent
      await_frames
      assert_equal 1, calls.value
      release << true
      assert_selector "#settings-mail-test", text: "Test mail sent to one@example.com"
      assert_equal 1, calls.value
    end
  end

  test "the Mail card's security switch sets the port unless another port was typed" do
    site_settings(:default).update!(mail_port: nil, mail_security: nil)
    visit_screen "/cs-studio/settings"

    within "#settings-mail-card" do
      find("label", exact_text: "TLS").click
      assert_field "Port", with: "465"
      find("label", exact_text: "STARTTLS").click
      assert_field "Port", with: "587"

      fill_in "Port", with: "2525"
      find("label", exact_text: "TLS").click
      assert_field "Port", with: "2525"
    end
    # The port set by the switch counts as a change of the form.
    assert_selector "[data-admin--saving--save-bar-target=count]", text: "Port"
  end
end
