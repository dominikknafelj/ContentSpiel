require "test_helper"

class HostSettingsTest < ActiveSupport::TestCase
  Request = Struct.new(:path)
  Credentials = Struct.new(:secret_key_base)

  test "an https address: its host is the only one answered, HTTPS is forced and mailed links carry it" do
    config = apply("https://docs.example.org")

    assert_equal [ "docs.example.org" ], config.hosts
    assert_equal true, config.force_ssl
    assert_equal false, config.assume_ssl
    assert_equal({ host: "docs.example.org", protocol: "https" }, config.action_mailer.default_url_options)
  end

  test "an http address: its host is the only one answered and nothing is forced to HTTPS" do
    config = apply("http://localhost:3030")

    assert_equal [ "localhost" ], config.hosts
    assert_equal false, config.force_ssl
    assert_equal({ host: "localhost", protocol: "http", port: 3030 }, config.action_mailer.default_url_options)
  end

  test "no address: the hosts are left as they were, nothing is forced and mailed links have no host" do
    config = apply(nil)

    assert_equal [], config.hosts
    assert_equal false, config.force_ssl
    assert_equal({}, config.action_mailer.default_url_options)
  end

  test "the hosts a config already holds are left alone when no address is configured" do
    config = fake_config
    config.hosts = [ "kept.example" ]
    HostSettings.apply(config, address: SiteAddress.parse(nil), env: {})

    assert_equal [ "kept.example" ], config.hosts
  end

  test "the health check is excluded from host authorisation and from the redirect, whatever the address" do
    [ "https://docs.example.org", "http://localhost:3030", nil ].each do |address|
      config = apply(address)

      assert_equal({ exclude: HostSettings::HEALTH_CHECK }, config.host_authorization, address.inspect)
      assert_equal({ redirect: { exclude: HostSettings::HEALTH_CHECK } }, config.ssl_options, address.inspect)
    end
  end

  test "assume_ssl is on for ASSUME_SSL=1 and for nothing else" do
    assert_equal true, apply("https://docs.example.org", "ASSUME_SSL" => "1").assume_ssl

    [ "true", "0", "", " 1" ].each do |value|
      assert_equal false, apply("https://docs.example.org", "ASSUME_SSL" => value).assume_ssl, value.inspect
    end
  end

  test "the health check is the path /up and nothing under or beside it" do
    assert HostSettings::HEALTH_CHECK.call(Request.new("/up"))
    assert_not HostSettings::HEALTH_CHECK.call(Request.new("/up/x"))
    assert_not HostSettings::HEALTH_CHECK.call(Request.new("/"))
  end

  test "the boot line says what is served and what is refused" do
    assert_equal "[ContentSpiel] Serving https://docs.example.org. Other host names are refused; plain HTTP is redirected.",
                 HostSettings.announcement(SiteAddress.parse("https://docs.example.org"))
    assert_equal "[ContentSpiel] Serving http://localhost:3030. Other host names are refused. The connection is not encrypted.",
                 HostSettings.announcement(SiteAddress.parse("http://localhost:3030"))
    assert_equal "[ContentSpiel] PUBLIC_HOST is not set. Any host name is accepted and nothing is forced to HTTPS.",
                 HostSettings.announcement(SiteAddress.parse(nil))
  end

  test "a missing or blank SECRET_KEY_BASE is refused with how to make one, and no word of credentials" do
    [ {}, { "SECRET_KEY_BASE" => "" }, { "SECRET_KEY_BASE" => "  " } ].each do |env|
      error = assert_raises(HostSettings::MissingSecret, env.inspect) { HostSettings.require_secret!(env) }

      assert_includes error.message, "SECRET_KEY_BASE"
      assert_includes error.message, "bin/rails secret"
      assert_no_match(/credentials/i, error.message)
    end
  end

  test "a SECRET_KEY_BASE that is there is accepted, with or without credentials" do
    assert_nil HostSettings.require_secret!({ "SECRET_KEY_BASE" => "x" * 64 })
    assert_nil HostSettings.require_secret!({ "SECRET_KEY_BASE" => "x" * 64 }, credentials: Credentials.new(nil))
  end

  test "a secret in the credentials is accepted as Rails accepts it, with no variable set" do
    assert_nil HostSettings.require_secret!({}, credentials: Credentials.new("y" * 64))
    assert_nil HostSettings.require_secret!({ "SECRET_KEY_BASE" => "" }, credentials: Credentials.new("y" * 64))
  end

  test "credentials that hold no secret, a blank one, or that could not be read are refused like none" do
    [ Credentials.new(nil), Credentials.new(""), Credentials.new("  "), nil ].each do |credentials|
      error = assert_raises(HostSettings::MissingSecret, credentials.inspect) do
        HostSettings.require_secret!({}, credentials: credentials)
      end

      assert_includes error.message, "SECRET_KEY_BASE"
      assert_includes error.message, "bin/rails secret"
      assert_no_match(/credentials/i, error.message)
    end
  end

  private
    def fake_config
      config = ActiveSupport::OrderedOptions.new
      config.action_mailer = ActiveSupport::OrderedOptions.new
      config.hosts = []
      config
    end

    def apply(address, env = {})
      fake_config.tap { |config| HostSettings.apply(config, address: SiteAddress.parse(address), env: env) }
    end
end
