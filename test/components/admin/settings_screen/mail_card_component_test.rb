require "test_helper"

class Admin::SettingsScreen::MailCardComponentTest < ViewComponent::TestCase
  def render_card(site: SiteSetting.instance.reload, env: {}, errors: nil)
    Current.session = Session.start(user: users(:one), method: "password", user_agent: nil, ip_address: nil)
    render_inline Admin::SettingsScreen::MailCardComponent.new(site_setting: site, values: Admin::SettingsScreen::Values.new(site: site),
      mail_settings: MailSettings.current(site, env: env), errors: errors)
  ensure
    Current.session = nil
  end

  def drawn_as?(button, variant, size: :regular) = (Admin::Ui::ButtonComponent.classes(variant, size: size).split - button[:class].split).empty?

  test "each state is a state chip alone at the head's end, its tone and its word, and what it means as the head's note" do
    { not_set_up: [ "Not set up", "Password resets and invites are off until mail is set up.", :off ],
      untested: [ "Saved, not tested", "Mail is saved but not tested yet.", :warn ],
      working: [ "Working", nil, :ok ],
      failed: [ "Last send failed", "The last mail could not be sent.", :danger ] }.each do |state, (word, note, tone)|
      with_mail_state(state) { render_card }

      assert_equal tone, Admin::SettingsScreen::MailStateComponent::TONES.fetch(state)
      assert_selector "#settings-mail-state[data-mail-state=#{state}] .admin-state-chip[data-state-tone=#{tone}]", text: word
      assert_selector "#settings-mail-state .admin-state-chip > span[aria-hidden=true]", visible: :all
      assert_equal word, page.find("#settings-mail-state").text.strip, "the head's end holds the chip alone"
      assert_selector ".admin-settings-card__note #settings-mail-state-note[data-mail-state=#{state}]", visible: :all
      if note
        assert_selector "#settings-mail-state-note p.text-small.text-dim", text: note
        assert_no_text word.downcase == "not set up" ? "Not set up." : "Saved, not tested."
      else
        assert_no_selector "#settings-mail-state-note p"
      end
    end
  end

  test "a site that is not set up for a reason the person must fix keeps that reason's sentence as the note" do
    with_mail_state(:not_set_up, mail_sender_address: "two@one.test, three@one.test") { render_card }

    assert_selector "#settings-mail-state-note p", text: "Not set up: the sender address is not one address, like no-reply@example.com."
  end

  test "a failed send shows the note, then the failure's sentence and the server's line in mono" do
    with_mail_state(:failed) { render_card }

    assert_selector "#settings-mail-state-note p", text: "The last mail could not be sent."
    assert_selector "#settings-mail-state-note [role=alert]", text: "The server refused the login. Check username and password."
    assert_selector "#settings-mail-state-note [role=alert] code.font-cs-mono", text: "535 5.7.8 Authentication failed"
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

  test "the state stands at the head's end, as the Site card's tabs do, and while mail works its note is empty" do
    with_mail_state(:working) { render_card }

    assert_selector ".admin-settings-card__head > .admin-settings-card__end #settings-mail-state[data-mail-state=working]"
    assert_equal "", page.find(".admin-settings-card__note", visible: :all).text(:all).strip
  end

  test "Save login and Send test mail are small secondaries: the save bar is the screen's one primary" do
    with_mail_state(:not_set_up) { render_card }

    assert drawn_as?(page.find("#settings-mail-login button[form=settings-mail-login-form]", text: "Save login"), :secondary, size: :small)
    assert drawn_as?(page.find("button", text: "Send test mail"), :secondary, size: :small)
    assert_no_selector "button.bg-accent", visible: :all
  end

  # The card stands inside `#settings-form`: Enter in one of its fields
  # presses the form's first submit button. Every submit drawn in the card
  # belongs to another form (the login's, the test mail's) by `form=`, so
  # Enter saves through the bar and never sends a mail or a login.
  test "every submit button in the card names its own form, so Enter in a Mail field never presses one" do
    submits_without_form = lambda do
      submits = page.all("button:not([type]), button[type=submit], input[type=submit], input[type=image]", visible: :all)
      assert_not_empty submits
      submits.reject { |button| button[:form].present? }.map { |button| button.native.to_html }
    end

    render_card
    assert_empty submits_without_form.call, "with no login stored"

    SiteSetting.instance.update!(mail_username: "u", mail_password: "p")
    render_card
    assert_empty submits_without_form.call, "with a login stored"
  end
end
