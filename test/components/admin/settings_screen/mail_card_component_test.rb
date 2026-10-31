require "test_helper"

class Admin::SettingsScreen::MailCardComponentTest < ViewComponent::TestCase
  def render_card(site: SiteSetting.instance.reload, env: {}, errors: nil)
    Current.session = users(:one).sessions.create!
    render_inline Admin::SettingsScreen::MailCardComponent.new(site_setting: site, values: Admin::SettingsScreen::Values.new(site: site),
      mail_settings: MailSettings.current(site, env: env), errors: errors)
  ensure
    Current.session = nil
  end

  test "each state is a dot and a word, and its sentence" do
    { not_set_up: [ "Not set up", "Not set up. Password resets and invites are off.", ".border-meta" ],
      untested: [ "Saved, not tested", "Saved, not tested. Send a test mail to turn on resets and invites.", ".bg-warn" ],
      working: [ "Working", "Working. Last mail sent", ".bg-ok" ],
      failed: [ "Last send failed", "Last send failed", ".bg-danger" ] }.each do |state, (word, sentence, dot)|
      with_mail_state(state) { render_card }

      assert_selector "#settings-mail-state[data-mail-state=#{state}] .font-semibold", text: word
      assert_selector "#settings-mail-state #{dot}[aria-hidden=true]"
      assert_selector "#settings-mail-state p", text: sentence
    end
  end

  test "a failed send shows its short reason, the failure's sentence and the server's line in mono" do
    with_mail_state(:failed) { render_card }

    assert_selector "#settings-mail-state p", text: /Last send failed \d{1,2} \w{3}, \d{2}:\d{2}: the server refused the login\./
    assert_selector "#settings-mail-state [role=alert]", text: "The server refused the login. Check username and password."
    assert_selector "#settings-mail-state [role=alert] code.font-cs-mono", text: "535 5.7.8 Authentication failed"
  end

  test "the fields, security as STARTTLS by default, the login entry open with nothing set, and the test button" do
    with_mail_state(:not_set_up) { render_card }

    assert_selector "input#settings-mail_server[name='site_setting[mail_server]'][placeholder='smtp.example.com']"
    assert_selector "input#settings-mail_port[type=number]"
    assert_selector "input#settings-mail_security-starttls[checked]"
    assert_selector "input#settings-mail_security-tls[data-port='465']"
    assert_selector "input#settings-mail_sender_address[placeholder='no-reply@yourdomain']"
    assert_selector "#settings-mail-login [data-admin--settings--mail-target=entry]:not([hidden])"
    assert_selector "#settings-mail-login button[form=settings-mail-login-form]", text: "Save login"
    assert_no_selector "#settings-mail-login button", text: "Replace"
    assert_selector "#settings-mail-test button[form=settings-mail-test-form]", text: "Send test mail"
    assert_selector "#settings-mail-test", text: "Sends to one@example.com (your address)"
    assert_selector "#settings-mail-test [data-admin--saving--pending-lock-target=hint][hidden]", text: "Save your changes first", visible: :all
  end

  test "a stored login reads Set on its date with Replace and Remove…, and is never rendered" do
    site = SiteSetting.instance
    site.update!(mail_username: "never-shown-user", mail_password: "never-shown-pw")
    site.update_columns(mail_login_saved_at: Time.zone.local(2026, 10, 14, 12))
    render_card(site: site.reload)

    assert_selector "#settings-mail-login [data-mail-login-state=set]", text: "Set on 14 Oct 2026"
    assert_selector "#settings-mail-login button", text: "Replace"
    assert_selector "#settings-mail-login button", text: "Remove…"
    assert_selector "#settings-mail-login [data-admin--settings--mail-target=entry][hidden]", visible: :all
    assert_not_includes page.native.to_html, "never-shown"
  end

  test "a field from the host is a sunken box with its value and Set by the host, and no input" do
    render_card(env: { "MAIL_SMTP_SERVER" => "smtp.host.test", "MAIL_SMTP_USERNAME" => "host-user-secret" })

    assert_no_selector "input[name='site_setting[mail_server]']"
    assert_selector "[data-field-name=mail_server] .bg-sunken", text: "smtp.host.test"
    assert_selector "[data-field-name=mail_server]", text: "Set by the host"
    assert_no_selector "input[name='site_setting[mail_username]']"
    assert_selector "input[name='site_setting[mail_password]']"
    assert_not_includes page.native.to_html, "host-user-secret"
    assert_no_text "These settings come from the host's environment."
  end

  test "a refused save shows each field's sentence under it" do
    site = SiteSetting.instance
    site.assign_attributes(mail_sender_name: "A\nB")
    site.validate
    render_card(site: site, errors: site.errors)

    assert_selector "#settings-mail_sender_name-errors", text: "Sender name can't contain a line break."
  end
end
