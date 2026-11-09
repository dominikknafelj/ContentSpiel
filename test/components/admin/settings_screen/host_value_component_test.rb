require "test_helper"

class Admin::SettingsScreen::HostValueComponentTest < ViewComponent::TestCase
  def render_value(field, label, env)
    render_inline Admin::SettingsScreen::HostValueComponent.new(field: field, label: label, mail_settings: MailSettings.current(SiteSetting.instance, env: env))
  end

  test "a field the host sets shows its label, its value in the sunken box and Set by the host" do
    render_value(:server, "Server", "MAIL_SMTP_SERVER" => "smtp.host.test")

    assert_selector "[data-host-field=server] span", text: "Server"
    assert_selector "[data-host-field=server] .bg-sunken.text-ink", text: "smtp.host.test"
    assert_selector "[data-host-field=server] p.text-meta", text: "Set by the host"
  end

  test "the security is said in its words" do
    render_value(:security, "Security", "MAIL_SMTP_SECURITY" => "starttls")

    assert_selector "[data-host-field=security] .bg-sunken", text: "STARTTLS"
  end

  test "a login half is the mask, hidden from a screen reader, and its value is never in the page" do
    { username: "MAIL_SMTP_USERNAME", password: "MAIL_SMTP_PASSWORD" }.each do |field, variable|
      render_value(field, field.to_s.capitalize, variable => "host-secret-4711")

      assert_selector "[data-host-field=#{field}] .bg-sunken[aria-hidden=true]", text: Admin::SettingsScreen::MailLoginComponent::MASK
      assert_not_includes page.native.to_html, "host-secret-4711"
    end
  end

  # A reader that refuses the login's value: the component must not ask.
  class NoSecretReads < SimpleDelegator
    def value(field)
      raise "the login's #{field} was read" if Admin::SettingsScreen::MailLoginComponent.secret?(field)

      super
    end
  end

  test "a login half's value is never read" do
    settings = NoSecretReads.new(MailSettings.current(SiteSetting.instance, env: { "MAIL_SMTP_USERNAME" => "u", "MAIL_SMTP_PASSWORD" => "p" }))
    %i[username password].each do |field|
      render_inline Admin::SettingsScreen::HostValueComponent.new(field: field, label: "Login", mail_settings: settings)
      assert_selector "[data-host-field=#{field}]"
    end
  end
end
