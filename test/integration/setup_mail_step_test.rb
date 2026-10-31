require "test_helper"

# The setup wizard's optional Mail step (spec "The setup wizard", design
# answer M1): after Site identity, skippable, the same fields and service as
# Settings → Mail, a test mail to the admin, and the one test-mail limit.
class SetupMailStepTest < ActionDispatch::IntegrationTest
  include LogCapture

  FIELDS = { mail_server: "smtp.provider.test", mail_port: "2525", mail_security: "tls", mail_sender_name: "The Site",
             mail_sender_address: "hello@site.test", mail_username: "wizard-user-4711", mail_password: "wizard-secret-0815" }.freeze

  setup do
    start_fresh_install
    verify_setup_token
    create_setup_admin
    MailTestLimit.store.clear
    ActionMailer::Base.deliveries.clear
  end

  teardown { MailTestLimit.store.clear }

  def save_mail(fields = FIELDS, **extra)
    patch setup_step_path("mail"), params: { site_setting: fields }.merge(extra)
  end

  test "the Mail step comes after Site identity, can be skipped, and the review then says it is not set up" do
    patch setup_step_path("site"), params: { site_setting: { title: "Dana's Notes" } }
    assert_redirected_to setup_step_path("mail")

    get setup_step_path("mail")
    assert_response :success
    assert_select "h1", text: /Mail/
    assert_select "h1", text: /optional/
    assert_match(/Content Spiel sends two kinds of mail: password reset links and invites\. Use the SMTP details from your mail provider\./, response.body)
    assert_select "a[href=?]", setup_step_path("languages"), text: "Skip for now"

    get setup_step_path("review")
    assert_select "dt", text: "Mail"
    assert_select "dd", text: "Not set up. Password resets and invites stay off until mail works. Set it up later in Settings → Mail."
  end

  test "after the step is filled in the review says the mail's state, not that it is skipped" do
    save_mail
    get setup_step_path("review")
    assert_select "dd", text: "Saved, not tested"
    assert_select "dd a[href=?]", setup_step_path("mail"), text: "Edit"
  end

  test "its fields come in order: Server, Port 587, Security STARTTLS / TLS, Username, Password, Sender name from the site's title, Sender address" do
    patch setup_step_path("site"), params: { site_setting: { title: "Dana's Notes" } }
    get setup_step_path("mail")

    labels = css_select("form label, form legend").map { |node| node.text.strip }.reject(&:blank?)
    assert_equal [ "Server", "Port", "Security", "STARTTLS", "TLS", "Username", "Password", "Sender name", "Sender address" ], labels
    assert_select "input[name='site_setting[mail_server]'][placeholder='smtp.example.com']"
    assert_select "input[name='site_setting[mail_port]'][value='587'][data-setup-mail-target=port]"
    assert_select "input[type=radio][name='site_setting[mail_security]']", 2
    assert_select "input[type=radio][value=starttls][checked][data-port='587'][data-action='change->setup-mail#security']"
    assert_select "input[type=radio][value=tls][data-port='465']"
    assert_select "input[type=password][name='site_setting[mail_password]']"
    assert_select "input[name='site_setting[mail_sender_name]'][value=?]", "Dana's Notes"
    assert_select "input[name='site_setting[mail_sender_address]'][placeholder='no-reply@yourdomain']"
    assert_select "span", text: "Sends to owner@example.com (your address)"
    # Enter submits Continue, never the test mail.
    assert_equal "Continue", css_select("form button[type=submit]").first.text.strip
  end

  test "Continue saves through Settings::Save, goes on to Languages and stores the login encrypted and unseen" do
    save_mail
    assert_redirected_to setup_step_path("languages")

    site = SiteSetting.instance
    assert_equal [ "smtp.provider.test", 2525, "tls", "The Site", "hello@site.test" ],
      [ site.mail_server, site.mail_port, site.mail_security, site.mail_sender_name, site.mail_sender_address ]
    assert site.mail_login_set?
    assert_equal "wizard-user-4711", site.mail_username

    get setup_step_path("mail")
    assert_not_includes response.body, "wizard-user-4711"
    assert_not_includes response.body, "wizard-secret-0815"
    assert_match(/A login is saved\. Leave both blank to keep it\./, response.body)

    save_mail(FIELDS.merge(mail_username: "", mail_password: "", mail_server: "smtp.other.test"))
    assert_equal "wizard-user-4711", SiteSetting.instance.mail_username
    assert_equal "smtp.other.test", SiteSetting.instance.mail_server
  end

  test "a refused field is a 422 with what was typed, and the password is not put back" do
    save_mail(FIELDS.merge(mail_sender_address: "not an address"))

    assert_response :unprocessable_entity
    assert_select "input[name='site_setting[mail_server]'][value='smtp.provider.test']"
    assert_select "input[name='site_setting[mail_password]'][value]", 0
    assert_not_includes response.body, "wizard-secret-0815"
  end

  test "Send test mail saves, sends to the admin's address and says so" do
    save_mail(FIELDS.except(:mail_server, :mail_port, :mail_username, :mail_password), send_test: "1")

    # Turbo refuses a non-redirect 2xx to a form: the success goes back to the step.
    assert_redirected_to setup_step_path("mail")
    follow_redirect!
    assert_response :success
    assert_equal [ "owner@example.com" ], ActionMailer::Base.deliveries.last.to
    assert_select "#setup-mail-test [role=status]", /Test mail sent to owner@example\.com\. Check your inbox\./
    assert_equal "hello@site.test", SiteSetting.instance.mail_sender_address
    assert_equal :working, MailSettings.current.state
  end

  test "a failed test mail is the warn alert with the sentence and the server's line, and the settings stay saved" do
    with_mail_env("MAIL_SMTP_SECURITY" => "none") do
      SmtpStub.start(:sender_refused) do |port, _stub|
        save_mail(FIELDS.except(:mail_username, :mail_password).merge(mail_server: SmtpStub::HOST, mail_port: port.to_s, mail_security: "starttls"), send_test: "1")
      end
    end

    assert_response :unprocessable_entity
    assert_select "#setup-mail-test [role=alert].border-warn", /The server refused the sender address\./
    assert_select "#setup-mail-test [role=alert] code.font-cs-mono", /550 5\.7\.1 Sender address rejected/
    assert_equal SmtpStub::HOST, SiteSetting.instance.mail_server
  end

  test "Send test mail with settings that are not complete sends nothing and says the state" do
    save_mail({ mail_server: "", mail_sender_address: "" }, send_test: "1")

    assert_response :unprocessable_entity
    assert_select "#setup-mail-test [role=alert]", /Not set up\. Password resets and invites are off\./
    assert_empty ActionMailer::Base.deliveries
  end

  test "a field the host sets is not on the form and is not posted" do
    with_mail_env("MAIL_SMTP_SERVER" => "smtp.host.test") do
      get setup_step_path("mail")
      assert_select "input[name='site_setting[mail_server]']", 0
      assert_select "[data-host-field=server]", /smtp\.host\.test.*Set by the host/m

      save_mail(FIELDS.except(:mail_server))
      assert_redirected_to setup_step_path("languages")
    end
  end

  # Spec decision 3 (final review 1): the host's login is a credential. Each
  # half is checked alone, and the whole body is searched, not one element.
  { "MAIL_SMTP_USERNAME" => "host-login-user-4711", "MAIL_SMTP_PASSWORD" => "host-login-pass-0815" }.each do |variable, secret|
    test "the host's #{variable} is Set by the host and its value is nowhere in the step's page" do
      with_mail_env(variable => secret) do
        get setup_step_path("mail")
        assert_response :success

        field = variable.delete_prefix("MAIL_SMTP_").downcase
        assert_select "input[name='site_setting[mail_#{field}]']", 0
        assert_select "[data-host-field=#{field}]", /••••••••.*Set by the host/m
        assert_not_includes response.body, secret

        # A refused save draws the step again: still nowhere.
        save_mail(FIELDS.except(:mail_username, :mail_password).merge(mail_sender_address: "not one address"))
        assert_response :unprocessable_entity
        assert_not_includes response.body, secret
      end
    end
  end

  test "test mails from the wizard and from Settings → Mail by the same person count in one bucket of 5" do
    2.times do
      save_mail(FIELDS.slice(:mail_sender_address), send_test: "1")
      assert_redirected_to setup_step_path("mail")
    end

    # Setup is over: the same signed-in person presses Settings' button.
    site_settings(:default).update!(setup_completed_at: Time.current)
    3.times do
      post "/cs-studio/settings/send_test_mail", as: :turbo_stream
      assert_response :success
    end
    assert_equal 5, ActionMailer::Base.deliveries.size

    post "/cs-studio/settings/send_test_mail", as: :turbo_stream
    assert_response :too_many_requests
    assert_equal 5, ActionMailer::Base.deliveries.size
  end

  test "the wizard's own sixth test mail is refused with the sentence, 429, and Continue is not limited" do
    5.times do
      save_mail(FIELDS.slice(:mail_sender_address), send_test: "1")
      assert_redirected_to setup_step_path("mail")
    end
    save_mail(FIELDS.slice(:mail_sender_address), send_test: "1")

    assert_response :too_many_requests
    assert_select "#setup-mail-test [role=alert]", /Too many test mails\. Try again in a few minutes\./
    assert_equal 5, ActionMailer::Base.deliveries.size

    save_mail(FIELDS.slice(:mail_sender_address))
    assert_redirected_to setup_step_path("languages")
  end
end
