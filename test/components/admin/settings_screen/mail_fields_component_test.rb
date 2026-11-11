require "test_helper"

class Admin::SettingsScreen::MailFieldsComponentTest < ViewComponent::TestCase
  STORED = { mail_server: "smtp.stored.test", mail_port: "2525", mail_security: "tls", mail_sender_name: "The Site", mail_sender_address: "hello@site.test" }.freeze

  def render_fields(env: {}, value: ->(name) { STORED.fetch(name) }, changed: nil, errors: nil, &login)
    site = SiteSetting.instance
    component = Admin::SettingsScreen::MailFieldsComponent.new(mail_settings: MailSettings.current(site, env: env), value: value,
      name_prefix: "site_setting", id_prefix: "settings-", errors: errors, changed: changed)
    render_inline(component) { |fields| fields.with_login { login ? login.call : "<p id='login-slot'>Login here</p>".html_safe } }
  end

  test "two groups: Server holds server, port, security and the login slot; Sender holds the name and the address" do
    render_fields

    server = page.find("[role=group][aria-labelledby=settings-mail-server-group]")
    assert_equal "Server", page.find("#settings-mail-server-group").text.strip
    assert server.matches_css?(".rounded-tile.bg-paper.p-3")
    assert page.find("#settings-mail-server-group").matches_css?(".text-label.text-meta")
    assert server.has_css?("span[aria-hidden=true].bg-ic-media-bg svg")
    %w[mail_server mail_port mail_security].each { |name| assert server.has_css?("[data-field-name=#{name}]"), name }
    assert server.has_css?("#login-slot")
    assert_equal %w[mail_server mail_port mail_security], server.all("[data-field-name]").map { |node| node["data-field-name"] }

    sender = page.find("[role=group][aria-labelledby=settings-mail-sender-group]")
    assert_equal "Sender", page.find("#settings-mail-sender-group").text.strip
    assert sender.matches_css?(".rounded-tile.bg-paper.p-3")
    assert sender.has_css?("span[aria-hidden=true].bg-ic-text-bg svg")
    assert_equal %w[mail_sender_name mail_sender_address], sender.all("[data-field-name]").map { |node| node["data-field-name"] }
    assert_no_selector "legend", text: "Server"
    assert_no_selector "h3"

    assert_selector "input#settings-mail_server[name='site_setting[mail_server]'][value='smtp.stored.test'][placeholder='smtp.example.com']"
    assert_selector "input#settings-mail_port[type=number][value='2525'][data-mail-port-target=port]"
    assert_selector "input#settings-mail_sender_name[value='The Site']"
    assert_selector "input#settings-mail_sender_address[placeholder='no-reply@yourdomain']"
  end

  # The login is the slot's: the fields draw no input of it, and the mask of
  # a login half is `Admin::Ui::MailHostValueComponent`'s (mail_host_value_component_test.rb).
  HOST = { "MAIL_SMTP_SERVER" => "smtp.host.test", "MAIL_SMTP_PORT" => "2525", "MAIL_SMTP_SECURITY" => "tls",
           "MAIL_SMTP_USERNAME" => "host-user-secret", "MAIL_SMTP_PASSWORD" => "host-pass-secret",
           "MAIL_SENDER_NAME" => "Host Site", "MAIL_SENDER_ADDRESS" => "host@site.test" }.freeze

  test "a field the host sets is the sunken box with Set by the host, and a login half shows the mask and never its value" do
    render_fields(env: HOST) { "" }

    assert_selector "[data-field-name=mail_server] [data-host-field=server] .bg-sunken", text: "smtp.host.test"
    assert_selector "[data-field-name=mail_server] [data-host-field=server]", text: "Set by the host"
    assert_selector "[data-field-name=mail_security] [data-host-field=security] .bg-sunken", text: "TLS"
    %w[mail_server mail_port mail_security mail_sender_name mail_sender_address mail_username mail_password].each do |name|
      assert_no_selector "input[name='site_setting[#{name}]']", visible: :all
    end
    assert_no_selector "input", visible: :all
    assert_not_includes page.native.to_html, "host-user-secret"
    assert_not_includes page.native.to_html, "host-pass-secret"
  end

  test "the security radios carry their port and mail-port's action, inside a fieldset with its legend" do
    render_fields

    fieldset = page.find("fieldset#settings-mail_security")
    assert_equal "Security", fieldset.find("legend").text.strip
    { "starttls" => "587", "tls" => "465" }.each do |option, port|
      assert fieldset.has_css?("input[type=radio][name='site_setting[mail_security]'][value=#{option}][data-port='#{port}'][data-action='change->mail-port#security']", visible: :all), option
    end
    assert_selector "input#settings-mail_security-tls[checked]", visible: :all
  end

  test "a security never chosen is shown as STARTTLS" do
    render_fields(value: ->(name) { name == :mail_security ? "" : STORED.fetch(name) })

    assert_selector "input#settings-mail_security-starttls[checked]", visible: :all
  end

  test "a changed field's wrapper carries the save bar's mark, and a refused field its sentence" do
    site = SiteSetting.instance
    site.assign_attributes(mail_sender_name: "A\nB")
    site.validate
    render_fields(changed: ->(name) { "saved" if name == :mail_server }, errors: site.errors)

    assert_selector "[data-field-name=mail_server][data-save-bar-changed=saved]"
    assert_no_selector "[data-field-name=mail_port][data-save-bar-changed]"
    assert_selector "#settings-mail_sender_name-errors", text: "Sender name can't contain a line break."
  end

  test "the server icon is drawn by the icon partial" do
    assert_match "<svg", ApplicationController.render(partial: "admin/shared/icon", locals: { name: :server })
  end
end
