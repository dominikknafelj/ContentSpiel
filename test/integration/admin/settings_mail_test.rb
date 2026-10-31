require "test_helper"

# Settings → Mail (spec "Settings → Mail", design answers M2 and M3): five
# fields of the Settings form, the login written once through its own forms
# (`Admin::MailLoginsController`), the state in the card's header, "Send test
# mail" outside the save bar, and the sentence a site without encryption keys
# answers for the mail login and the AI key alike.
class Admin::SettingsMailTest < ActionDispatch::IntegrationTest
  include LogCapture
  USERNAME = "mail-login-user-4711".freeze
  PASSWORD = "mail-password-secret-0815".freeze
  NO_KEYS = "This site has no encryption keys, so a password can't be stored. See Hosting: encryption keys.".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @site = site_settings(:default)
    MailTestLimit.store.clear
    ActionMailer::Base.deliveries.clear
    sign_in_as(users(:one))
  end

  teardown { MailTestLimit.store.clear }

  def base = @site.reload.updated_at.iso8601(6)

  def save(fields)
    patch "/cs-studio/settings", params: { site_setting: fields, base_updated_at: base }
  end

  def save_login(username: USERNAME, password: PASSWORD)
    patch "/cs-studio/settings/mail_login",
      params: { site_setting: { mail_username: username, mail_password: password }, main_base_updated_at: base }, as: :turbo_stream
  end

  def remove_login
    delete "/cs-studio/settings/mail_login", params: { main_base_updated_at: base }, as: :turbo_stream
  end

  def send_test_mail
    post "/cs-studio/settings/send_test_mail", as: :turbo_stream
  end

  def user_holding(*keys)
    user = users(:editor_branch)
    keys.each { |key| AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: key, scope: {}) }
    AccessControl::Membership.create!(user: user, group: access_control_groups(:branch_editors)) unless user.groups.exists?(access_control_groups(:branch_editors).id)
    user
  end

  test "the card's five fields save with the save bar and the login with its own form, written once and shown as Set on <date> with Replace and Remove" do
    get "/cs-studio/settings"
    assert_select "#settings-mail-card h2#mail", "Mail"
    assert_select "nav a[href='#mail']", "Mail"
    %w[mail_server mail_port mail_sender_name mail_sender_address].each do |field|
      assert_select "form#settings-form input[name='site_setting[#{field}]']"
    end
    assert_select "form#settings-form input[type=radio][name='site_setting[mail_security]']", 2
    # The login is no field of the Settings form: its inputs belong to the login form by `form=`.
    assert_select "input[name='site_setting[mail_username]'][form=settings-mail-login-form]"
    assert_select "input[type=password][name='site_setting[mail_password]'][form=settings-mail-login-form]"
    assert_select "button[form=settings-mail-test-form]", "Send test mail"

    save(mail_server: "smtp.provider.test", mail_port: "2525", mail_security: "tls", mail_sender_name: "The Site", mail_sender_address: "hello@site.test")
    assert_redirected_to "/cs-studio/settings"
    @site.reload
    assert_equal [ "smtp.provider.test", 2525, "tls", "The Site", "hello@site.test" ],
      [ @site.mail_server, @site.mail_port, @site.mail_security, @site.mail_sender_name, @site.mail_sender_address ]

    travel_to Time.zone.local(2026, 10, 14, 9, 12) do
      save_login
    end
    assert_response :success
    assert_select "turbo-stream[action=append][target=toasts]", /Mail login saved/
    @site.reload
    assert_equal [ USERNAME, PASSWORD ], [ @site.mail_username, @site.mail_password ]
    assert_not_includes response.body, USERNAME
    assert_not_includes response.body, PASSWORD

    get "/cs-studio/settings"
    assert_not_includes response.body, USERNAME
    assert_not_includes response.body, PASSWORD
    assert_select "#settings-mail-login", /Set on 14 Oct 2026/
    assert_select "#settings-mail-login button", "Replace"
    assert_select "#settings-mail-login button", "Remove…"

    remove_login
    assert_select "turbo-stream[action=append][target=toasts]", /Mail login removed/
    @site.reload
    assert_nil @site.mail_username
    assert_nil @site.mail_password
    assert_nil @site.mail_login_saved_at
  end

  test "a login save with both fields blank is refused in the login's slot and writes nothing" do
    save_login(username: " ", password: "")

    assert_response :unprocessable_entity
    assert_select "turbo-stream[target=settings-mail-login] template", /Enter a username or a password first/
    assert_not @site.reload.mail_login_set?
  end

  test "a field from the host is read-only, Set by the host, and a save that names it is refused" do
    with_mail_env("MAIL_SMTP_SERVER" => "smtp.host.test", "MAIL_SMTP_PASSWORD" => "host-password-xyz") do
      get "/cs-studio/settings"
      assert_select "input[name='site_setting[mail_server]']", 0
      assert_select "#settings-mail-card", /smtp\.host\.test/
      assert_select "#settings-mail-card", /Set by the host/
      assert_not_includes response.body, "host-password-xyz"
      assert_select "input[name='site_setting[mail_password]']", 0
      assert_select "input[name='site_setting[mail_username]'][form=settings-mail-login-form]"
      assert_select "#settings-mail-card", { text: /These settings come from the host's environment/, count: 0 }

      save(mail_server: "smtp.forged.test")
      assert_response :unprocessable_entity
      assert_includes response.body, "Server is set by the host and can&#39;t be changed here."
      assert_nil @site.reload.mail_server

      save_login(username: USERNAME, password: PASSWORD)
      assert_response :unprocessable_entity
      assert_not @site.reload.mail_login_set?
    end
  end

  test "every field from the host gives the card the line These settings come from the host's environment." do
    host = { "MAIL_SMTP_SERVER" => "smtp.host.test", "MAIL_SMTP_PORT" => "587", "MAIL_SMTP_SECURITY" => "starttls",
             "MAIL_SMTP_USERNAME" => "u", "MAIL_SMTP_PASSWORD" => "p", "MAIL_SENDER_NAME" => "Host", "MAIL_SENDER_ADDRESS" => "host@site.test" }
    with_mail_env(host) do
      get "/cs-studio/settings"
      assert_select "#settings-mail-card", /These settings come from the host's environment\./
      assert_select "#settings-mail-card input[name^='site_setting[mail_']", 0
      assert_select "button[form=settings-mail-test-form]", "Send test mail"
    end
  end

  test "Send test mail saves nothing, sends to the person pressing it, and answers Test mail sent to <address>. Check your inbox." do
    with_mail_state(:untested) do
      updated = SiteSetting.instance.updated_at
      assert_no_difference -> { Audit::Event.count } do
        send_test_mail
      end

      assert_response :success
      assert_equal [ users(:one).email_address ], ActionMailer::Base.deliveries.last.to
      assert_select "turbo-stream[target=settings-mail-test] template", /Test mail sent to one@example\.com\. Check your inbox\./
      assert_select "turbo-stream[target=settings-mail-state] template", /Working/
      site = SiteSetting.instance
      assert_equal updated, site.updated_at
      assert_equal :working, MailSettings.current(site).state
    end
  end

  test "a failed test mail answers the warn alert with the sentence and the server's line in mono" do
    with_mail_env("MAIL_SMTP_SECURITY" => "none") do
      SmtpStub.start(:sender_refused) do |port, _stub|
        with_mail_state(:untested, mail_server: SmtpStub::HOST, mail_port: port) do
          send_test_mail
        end
      end
    end

    assert_response :unprocessable_entity
    assert_select "turbo-stream[target=settings-mail-test] template" do
      assert_select "[role=alert].border-warn", /The server refused the sender address\./
      assert_select "[role=alert] code.font-cs-mono", /550 5\.7\.1 Sender address rejected/
    end
  end

  test "Send test mail with settings that are not complete says the state and sends nothing" do
    with_mail_state(:not_set_up) do
      send_test_mail
    end

    assert_response :unprocessable_entity
    assert_select "turbo-stream[target=settings-mail-test] template", /Not set up\. Password resets and invites are off\./
    assert_empty ActionMailer::Base.deliveries
  end

  # Ruling F2: the mail gem raised on such an address before the delivery,
  # which answered 500 under the card's own "Send a test mail" sentence.
  test "a host's sender address that is not one address: the card says so, and Send test mail answers it and sends nothing" do
    sentence = "Not set up: the sender address the host sets (MAIL_SENDER_ADDRESS) is not one address, like no-reply@example.com."
    with_mail_env("MAIL_SENDER_ADDRESS" => "no-reply@") do
      with_mail_state(:untested) do
        get "/cs-studio/settings"
        assert_select "#settings-mail-card", /#{Regexp.escape(sentence)}/

        send_test_mail
      end
    end

    assert_response :unprocessable_entity
    assert_select "turbo-stream[target=settings-mail-test] template", /#{Regexp.escape(sentence)}/
    assert_empty ActionMailer::Base.deliveries
  end

  test "test mails are limited to 5 per person per 3 minutes" do
    with_mail_state(:untested) do
      5.times do
        send_test_mail
        assert_response :success
      end
      send_test_mail
      assert_response :too_many_requests
      assert_select "turbo-stream[target=settings-mail-test] template", /Too many test mails\. Try again in a few minutes\./
      assert_equal 5, ActionMailer::Base.deliveries.size

      # Another person has a limit of their own.
      sign_in_as(users(:two))
      send_test_mail
      assert_response :success

      travel 3.minutes + 1.second do
        sign_in_as(users(:one))
        send_test_mail
        assert_response :success
      end
    end
  end

  test "without encryption keys a save of the mail login and of the AI key answers the sentence and writes nothing" do
    without_encryption_keys do
      save_login
      assert_response :unprocessable_entity
      assert_select "turbo-stream[target=settings-mail-login] template", text: /#{Regexp.escape(NO_KEYS)}/
      assert_no_match(/#{USERNAME}|#{PASSWORD}/, response.body)

      patch "/cs-studio/settings/ai_key", params: { site_setting: { ai_api_key: "sk-ant-no-keys-here" }, main_base_updated_at: base }, as: :turbo_stream
      assert_response :unprocessable_entity
      assert_select "turbo-stream[target=settings-ai-key] template", text: /#{Regexp.escape(NO_KEYS)}/
    end

    raw = SiteSetting.connection.select_one("select mail_username, mail_password, ai_api_key, mail_login_saved_at from site_settings where id = #{@site.id}")
    assert raw.values.all?(&:nil?), "nothing written: #{raw.keys.inspect}"
    assert_not Audit::Event.where(action: "settings.updated").exists?
  end

  test "the audit records Mail login set/not set and no value; the login is in no log line of the request" do
    log = capture_log { save_login }

    event = Audit::Event.where(action: "settings.updated").order(:id).last
    assert_equal [ "not set", "set" ], event.field_changes["Mail login"]
    %w[mail_username mail_password mail_verified_fingerprint].each { |column| assert_not event.snapshot.key?(column), column }
    [ event.snapshot.to_json, event.field_changes.to_json, log ].each do |text|
      assert_not_includes text, USERNAME
      assert_not_includes text, PASSWORD
    end
    assert_includes log, "mail_login", "the request was logged at all"

    # Past the window in which one person's settings events are one event.
    travel Audit::COALESCE_WINDOW + 1.second do
      remove_login
    end
    assert_equal [ "set", "not set" ], Audit::Event.where(action: "settings.updated").order(:id).last.field_changes["Mail login"]
  end

  test "a sender name with a line break, and a sender address with two addresses, are refused with their sentences" do
    save(mail_sender_name: "Ana\r\nBcc: victim@example.test", mail_sender_address: "a@site.test, b@site.test")

    assert_response :unprocessable_entity
    assert_includes response.body, "Sender name can&#39;t contain a line break."
    assert_includes response.body, "Sender address must be one address, like no-reply@example.com."
    @site.reload
    assert_nil @site.mail_sender_name
    assert_equal "no-reply@example.test", @site.mail_sender_address
  end

  test "a port outside 1 to 65535 and a security other than STARTTLS or TLS are refused" do
    save(mail_port: "70000", mail_security: "none")

    assert_response :unprocessable_entity
    assert_includes response.body, "Port must be a number from 1 to 65535."
    assert_includes response.body, "Security must be STARTTLS or TLS."
  end

  test "the card is shown to settings.manage only" do
    sign_in_as(user_holding("languages.manage"))
    get "/cs-studio/settings"
    assert_response :success
    assert_select "#settings-mail-card", 0
    assert_select "nav a[href='#mail']", 0

    send_test_mail
    assert_response :forbidden
    save_login
    assert_response :forbidden
    assert_not @site.reload.mail_login_set?
  end
end
