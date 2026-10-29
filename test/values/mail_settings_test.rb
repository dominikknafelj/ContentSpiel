require "test_helper"

class MailSettingsTest < ActiveSupport::TestCase
  ENV_FOR = {
    server: "MAIL_SMTP_SERVER", port: "MAIL_SMTP_PORT", security: "MAIL_SMTP_SECURITY",
    username: "MAIL_SMTP_USERNAME", password: "MAIL_SMTP_PASSWORD",
    sender_name: "MAIL_SENDER_NAME", sender_address: "MAIL_SENDER_ADDRESS"
  }.freeze

  # Production rules without Rails.env: no stand-in, an address, no host variables.
  def settings(site = SiteSetting.instance, env: {}, production: true, address: SiteAddress.parse("https://example.test", source: "PUBLIC_HOST"), stand_in: nil)
    MailSettings.current(site, env: env, production: production, address: address, stand_in: stand_in)
  end

  def site_with(**columns)
    SiteSetting.instance.tap { |site| site.assign_attributes(columns) }
  end

  test "each field comes from the site, from the host when its variable is set, and a blank variable is not set" do
    site = site_with(mail_server: "site.test", mail_port: 465, mail_security: "tls", mail_username: "site-user",
      mail_password: "site-pass", mail_sender_name: "Site", mail_sender_address: "site@example.test")
    host = { server: "host.test", port: "2525", security: "starttls", username: "host-user", password: "host-pass",
             sender_name: "Host", sender_address: "host@example.test" }

    from_site = settings(site)
    from_host = settings(site, env: host.to_h { |field, value| [ ENV_FOR.fetch(field), value ] })
    blank = settings(site, env: ENV_FOR.values.index_with { "" })

    assert_equal MailSettings::FIELDS, ENV_FOR.keys
    assert_equal ENV_FOR.transform_keys(&:to_sym), MailSettings::ENV_NAMES
    MailSettings::FIELDS.each do |field|
      assert_equal :site, from_site.source(field), field
      assert_not from_site.from_host?(field)
      assert_equal :host, from_host.source(field), field
      assert from_host.from_host?(field)
      assert_equal :site, blank.source(field), "a blank variable is not set: #{field}"
      assert_equal from_site.value(field), blank.value(field), field
    end
    assert_equal [ "host.test", 2525, "starttls", "host-user", "host-pass", "Host", "host@example.test" ],
      MailSettings::FIELDS.map { |field| from_host.value(field) }
    assert_equal [ "site.test", 465, "tls", "site-user", "site-pass", "Site", "site@example.test" ],
      MailSettings::FIELDS.map { |field| from_site.value(field) }
    assert from_host.all_from_host?
    assert_not from_site.all_from_host?
    assert_equal :none, settings(SiteSetting.instance).source(:server)
  end

  test "complete needs server, port and sender address; in production without a site address it is never complete" do
    full = site_with(mail_server: "smtp.test", mail_port: 587, mail_sender_address: "a@example.test")
    assert settings(full).complete?
    assert_not settings(site_with(mail_server: nil, mail_port: 587, mail_sender_address: "a@example.test")).complete?
    assert_not settings(site_with(mail_server: "smtp.test", mail_port: nil, mail_sender_address: "a@example.test")).complete?
    assert_not settings(site_with(mail_server: "smtp.test", mail_port: 587, mail_sender_address: nil)).complete?

    assert_not settings(full, address: nil).complete?, "production with no PUBLIC_HOST: no link could be mailed"
    assert settings(full, address: nil, production: false).complete?, "outside production a link follows the request"

    # Ruling 1: a stand-in delivery counts as a server where none is set.
    bare = site_with(mail_server: nil, mail_port: nil, mail_sender_address: "a@example.test")
    assert settings(bare, production: false, stand_in: :test).complete?
    assert settings(bare, production: false, stand_in: :test).stand_in?
    assert_not settings(site_with(mail_sender_address: nil), production: false, stand_in: :test).complete?, "a sender address is always needed"
    assert_not settings(full, production: false, stand_in: :test).stand_in?, "a server that is set is used"
    assert_not settings(bare).complete?
  end

  test "the four states: incomplete is not set up; complete and unverified is untested; verified is working; a failure after the last success is failed" do
    with_mail_state(:not_set_up) { assert_equal :not_set_up, MailSettings.current(production: false, stand_in: nil).state }
    with_mail_state(:untested) { assert_equal :untested, MailSettings.current(env: {}).state }
    with_mail_state(:working) { assert_equal :working, MailSettings.current(env: {}).state }
    with_mail_state(:failed) do
      current = MailSettings.current(env: {})
      assert_equal :failed, current.state
      assert current.ready?
    end
    with_mail_state(:working) { assert MailSettings.current(env: {}).ready? }
    with_mail_state(:untested) { assert_not MailSettings.current(env: {}).ready? }
    with_mail_state(:not_set_up) { assert_not MailSettings.current(env: {}).ready? }

    # A failure older than the last success is history.
    with_mail_state(:working, mail_failed_at: 10.minutes.ago) do
      assert_equal :working, MailSettings.current(env: {}).state
    end
    # An unverified site that failed is still untested: nothing was ever known to work.
    with_mail_state(:untested, mail_failed_at: 1.minute.ago) do
      assert_equal :untested, MailSettings.current(env: {}).state
    end
  end

  test "with_mail_state puts every column back" do
    before = SiteSetting.instance.attributes.slice(*MailState::COLUMNS)
    with_mail_state(:failed) { assert_equal "smtp.example.test", SiteSetting.instance.mail_server }
    assert_equal before, SiteSetting.instance.reload.attributes.slice(*MailState::COLUMNS)
  end

  # The login columns are encrypted: put back as their ciphertext through
  # `update_columns`, they were encrypted a second time and read back as the
  # ciphertext of the old login.
  test "with_mail_state puts a login set before the block back as it was, readable" do
    SiteSetting.instance.update_columns(mail_username: "before-user", mail_password: "before-pass") # version: none (a test's setting)
    with_mail_state(:working, mail_username: "inside-user", mail_password: "inside-pass") do
      assert_equal "inside-user", SiteSetting.instance.mail_username
    end
    with_mail_state(:not_set_up) { assert_nil SiteSetting.instance.mail_password }

    site = SiteSetting.instance.reload
    assert_equal [ "before-user", "before-pass" ], [ site.mail_username, site.mail_password ]
  end

  # The jsonb column's raw value is its JSON text: written back as it was
  # read raw, it was encoded a second time into a JSON string.
  test "a with_mail_state nested inside :failed puts the failure back as the same Hash" do
    with_mail_state(:failed) do
      before = SiteSetting.instance.reload.mail_failure
      assert_kind_of Hash, before

      with_mail_state(:working) { assert_nil SiteSetting.instance.reload.mail_failure }

      assert_equal before, SiteSetting.instance.reload.mail_failure
      assert_equal "login", MailFailure.load(SiteSetting.instance.mail_failure).key
    end
  end

  test "a change of any delivery setting, from either source, makes a verified site untested; a change of the sender name does not" do
    with_mail_state(:working) do
      assert_equal :working, MailSettings.current(env: {}).state

      { mail_server: "other.test", mail_port: 465, mail_security: "tls", mail_sender_address: "other@example.test",
        mail_username: "someone", mail_password: "secret" }.each do |column, value|
        site = SiteSetting.instance.tap { |s| s.assign_attributes(column => value) }
        assert_equal :untested, MailSettings.current(site, env: {}).state, "#{column} from the site"
      end

      { "MAIL_SMTP_SERVER" => "host.test", "MAIL_SMTP_PORT" => "2525", "MAIL_SMTP_SECURITY" => "tls",
        "MAIL_SMTP_USERNAME" => "u", "MAIL_SMTP_PASSWORD" => "p", "MAIL_SENDER_ADDRESS" => "host@example.test" }.each do |name, value|
        assert_equal :untested, MailSettings.current(env: { name => value }).state, "#{name} from the host"
      end

      assert_equal :working, MailSettings.current(env: { "MAIL_SENDER_NAME" => "Another name" }).state
      site = SiteSetting.instance.tap { |s| s.mail_sender_name = "Renamed" }
      assert_equal :working, MailSettings.current(site, env: {}).state

      # The same value from the host that the site holds changes nothing.
      assert_equal :working, MailSettings.current(env: { "MAIL_SMTP_SERVER" => "smtp.example.test" }).state
    end
  end

  test "the fingerprint is an HMAC that holds none of the values" do
    site = site_with(mail_server: "smtp.leaky-host.test", mail_port: 587, mail_username: "leaky-user",
      mail_password: "leaky-password", mail_sender_address: "leaky@example.test")
    fingerprint = settings(site).fingerprint

    assert_match(/\A\h{64}\z/, fingerprint)
    %w[leaky-password leaky-user smtp.leaky-host.test leaky@example.test].each do |value|
      assert_not_includes fingerprint, value
    end
    assert_equal fingerprint, settings(site).fingerprint
    site.mail_password = "another-password"
    assert_not_equal fingerprint, settings(site).fingerprint

    expected_key = Rails.application.key_generator.generate_key("content_spiel mail fingerprint", 32)
    assert_not_equal OpenSSL::HMAC.hexdigest("SHA256", "", [ "smtp.leaky-host.test" ].to_json), fingerprint
    assert_equal 32, expected_key.bytesize
  end

  test "none is taken only from the host and only without a login" do
    site = site_with(mail_server: "relay.test", mail_port: 25, mail_sender_address: "a@example.test")
    none = { "MAIL_SMTP_SECURITY" => "none" }

    relay = settings(site, env: none)
    assert relay.complete?
    assert_equal "none", relay.value(:security)
    options = relay.smtp_options
    assert_not options[:tls]
    # Said, not left out: left out, the mail gem uses STARTTLS when offered
    # (Ruling T2a; the stub test sees no STARTTLS on the wire).
    assert_equal [ false, false ], options.values_at(:enable_starttls, :enable_starttls_auto)

    assert_not settings(site, env: none.merge("MAIL_SMTP_USERNAME" => "user")).complete?
    assert_not settings(site, env: none.merge("MAIL_SMTP_PASSWORD" => "pass")).complete?
    assert_not settings(site_with(mail_server: "relay.test", mail_port: 25, mail_sender_address: "a@example.test", mail_username: "user"), env: none).complete?

    # The column never accepts it: it reads as the default.
    stored = site_with(mail_server: "relay.test", mail_port: 25, mail_security: "none", mail_sender_address: "a@example.test")
    assert_equal "starttls", settings(stored).value(:security)
    assert settings(stored).smtp_options[:enable_starttls]
    assert_not settings(site, env: { "MAIL_SMTP_SECURITY" => "ssl" }).complete?, "a value the host mistyped is not guessed at"
  end

  test "smtp_options: STARTTLS is required, TLS is TLS, and the timeouts are 5 and 10" do
    base = { mail_server: "smtp.test", mail_port: 587, mail_sender_address: "a@example.test" }

    starttls = settings(site_with(**base, mail_security: "starttls")).smtp_options
    assert_equal({ address: "smtp.test", port: 587, enable_starttls: true, enable_starttls_auto: false, open_timeout: 5, read_timeout: 10 }, starttls)

    tls = settings(site_with(**base, mail_port: 465, mail_security: "tls")).smtp_options
    assert_equal({ address: "smtp.test", port: 465, tls: true, enable_starttls: false, enable_starttls_auto: false, open_timeout: 5, read_timeout: 10 }, tls)

    assert_equal true, settings(site_with(**base)).smtp_options[:enable_starttls], "STARTTLS is the default"

    login = settings(site_with(**base, mail_username: "user", mail_password: "pass")).smtp_options
    assert_equal [ "user", "pass", :plain ], login.values_at(:user_name, :password, :authentication)
    assert_not starttls.key?(:authentication)
    assert_not starttls.key?(:user_name)
  end

  test "login_set? reads the raw columns, and the host's variables" do
    assert_not settings(SiteSetting.instance).login_set?
    assert settings(site_with(mail_username: "u")).login_set?
    assert settings(SiteSetting.instance, env: { "MAIL_SMTP_PASSWORD" => "p" }).login_set?
    assert_equal :host, settings(SiteSetting.instance, env: { "MAIL_SMTP_PASSWORD" => "p" }).source(:password)
  end

  test "sender is Name <address>, quoted by the mail gem, and the address alone without a name" do
    assert_equal "Test Site <no-reply@example.test>",
      settings(site_with(mail_sender_name: "Test Site", mail_sender_address: "no-reply@example.test")).sender
    assert_equal "no-reply@example.test", settings(site_with(mail_sender_address: "no-reply@example.test")).sender
    assert_equal "\"Doe, Jane\" <a@example.test>", settings(site_with(mail_sender_name: "Doe, Jane", mail_sender_address: "a@example.test")).sender
  end

  test "record_success! and record_failure! write their columns and move neither updated_at nor the public content version" do
    with_mail_state(:untested) do
      site = SiteSetting.instance
      updated_at = site.updated_at
      version = PublicSite::Version.current
      fingerprint = MailSettings.current(env: {}).fingerprint
      at = Time.utc(2026, 10, 28, 9, 12)

      MailSettings.record_success!(fingerprint: fingerprint, at: at)
      site.reload
      assert_equal at, site.mail_verified_at
      assert_equal at, site.mail_last_sent_at
      assert_equal fingerprint, site.mail_verified_fingerprint
      assert_equal :working, MailSettings.current(site, env: {}).state

      later = at + 1.hour
      MailSettings.record_failure!(key: "login", line: "535 refused", at: later)
      site.reload
      assert_equal later, site.mail_failed_at
      assert_equal({ "key" => "login", "line" => "535 refused" }, site.mail_failure)
      assert_equal :failed, MailSettings.current(site, env: {}).state

      assert_equal updated_at, site.updated_at
      assert_equal version, PublicSite::Version.current
    end
  end

  test "record_success! writes through update_columns: one statement, no callback" do
    with_mail_state(:untested) do
      statements = capture_sql { MailSettings.record_success!(fingerprint: MailSettings.current(env: {}).fingerprint) }
      writes = statements.grep(/\A\s*(UPDATE|INSERT)/i)
      assert_equal 1, writes.size, writes.inspect
      assert_match(/UPDATE "site_settings"/, writes.first)
      assert_no_match(/updated_at/, writes.first)
    end
  end

  test "record_success! with a fingerprint that is not the current one records the send and does not verify" do
    with_mail_state(:untested) do
      MailSettings.record_success!(fingerprint: "0" * 64)
      site = SiteSetting.instance.reload
      assert_not_nil site.mail_last_sent_at
      assert_nil site.mail_verified_at
      assert_nil site.mail_verified_fingerprint
      assert_equal :untested, MailSettings.current(site, env: {}).state
    end
  end

  test "the host's variables answer for a site that has none of its own" do
    with_mail_state(:not_set_up) do
      env = { "MAIL_SMTP_SERVER" => "smtp.host.test", "MAIL_SMTP_PORT" => "587", "MAIL_SENDER_ADDRESS" => "a@host.test" }
      assert_equal :untested, MailSettings.current(env: env, production: true, address: SiteAddress.parse("https://example.test", source: "PUBLIC_HOST"), stand_in: nil).state
    end
  end
end
