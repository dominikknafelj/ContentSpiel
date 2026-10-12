require "test_helper"

class HostSettingsTest < ActiveSupport::TestCase
  Request = Struct.new(:path)
  Credentials = Struct.new(:secret_key_base)
  HSTS = { expires: 31_536_000, subdomains: false, preload: false }.freeze

  # Credentials that say whether they were read, and ones that cannot be.
  class WatchedCredentials
    attr_reader :reads

    def initialize(secret) = (@secret, @reads = secret, 0)

    def secret_key_base
      @reads += 1
      @secret
    end
  end

  class UnreadableCredentials
    class WrongKey < StandardError; end

    def secret_key_base = raise(WrongKey, "the-master-key-as-typed")
  end

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
      assert_equal({ redirect: { exclude: HostSettings::HEALTH_CHECK }, hsts: HSTS }, config.ssl_options, address.inspect)
    end
  end

  test "HSTS is one year for this host alone: no subdomains, no preload, whatever Rails' default is" do
    assert_equal HSTS, HostSettings::HSTS
    assert_equal 365 * 24 * 60 * 60, HostSettings::HSTS[:expires]
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

  test "the boot lines say what is served, that the match is exact, and what is refused" do
    assert_equal [
      "[ContentSpiel] Serving https://docs.example.org. Other host names are refused; plain HTTP is redirected.",
      "[ContentSpiel] Only the exact host name docs.example.org is answered: not www.docs.example.org, not any other subdomain."
    ], HostSettings.announcement(SiteAddress.parse("https://docs.example.org"), {})

    assert_equal [
      "[ContentSpiel] Serving http://localhost:3030. Other host names are refused. The connection is not encrypted.",
      "[ContentSpiel] Only the exact host name localhost is answered: not www.localhost, not any other subdomain."
    ], HostSettings.announcement(SiteAddress.parse("http://localhost:3030"), {})

    assert_equal [ "[ContentSpiel] PUBLIC_HOST is not set. Any host name is accepted and nothing is forced to HTTPS." ],
                 HostSettings.announcement(SiteAddress.parse(nil), {})
  end

  test "the boot lines say that every request is taken as HTTPS when ASSUME_SSL=1, and only then" do
    line = "[ContentSpiel] ASSUME_SSL=1: every request is taken as HTTPS, whatever the proxy says."

    assert_equal line, HostSettings.announcement(SiteAddress.parse("https://docs.example.org"), { "ASSUME_SSL" => "1" }).last
    assert_equal 3, HostSettings.announcement(SiteAddress.parse("https://docs.example.org"), { "ASSUME_SSL" => "1" }).size
    assert_equal line, HostSettings.announcement(SiteAddress.parse(nil), { "ASSUME_SSL" => "1" }).last

    [ "true", "0", "" ].each do |value|
      assert_not_includes HostSettings.announcement(SiteAddress.parse("https://docs.example.org"), { "ASSUME_SSL" => value }), line
    end
  end

  test "a missing SECRET_KEY_BASE is refused with how to make one, and no word of credentials" do
    error = assert_raises(HostSettings::MissingSecret) { HostSettings.require_secret!({}) }

    assert_match(/\ASECRET_KEY_BASE is not set\./, error.message)
    assert_includes error.message, "bin/rails secret"
    assert_no_match(/credentials/i, error.message)
  end

  test "a SECRET_KEY_BASE that is set but blank is refused as set but empty, also when the credentials hold a secret" do
    [ "", "  " ].each do |blank|
      [ nil, Credentials.new("y" * 64) ].each do |credentials|
        error = assert_raises(HostSettings::MissingSecret, [ blank, credentials ].inspect) do
          HostSettings.require_secret!({ "SECRET_KEY_BASE" => blank }, credentials: credentials)
        end

        assert_match(/\ASECRET_KEY_BASE is set but empty\./, error.message)
        assert_includes error.message, "bin/rails secret"
        assert_no_match(/credentials/i, error.message)
      end
    end
  end

  test "a SECRET_KEY_BASE that is there is accepted, and the credentials are not read at all" do
    credentials = WatchedCredentials.new("y" * 64)

    assert_nil HostSettings.require_secret!({ "SECRET_KEY_BASE" => "x" * 64 })
    assert_nil HostSettings.require_secret!({ "SECRET_KEY_BASE" => "x" * 64 }, credentials: credentials)
    assert_nil HostSettings.require_secret!({ "SECRET_KEY_BASE" => "x" * 64 }, credentials: UnreadableCredentials.new)
    assert_equal 0, credentials.reads
  end

  test "a blank variable does not read the credentials either: it is refused before" do
    credentials = WatchedCredentials.new("y" * 64)

    assert_raises(HostSettings::MissingSecret) { HostSettings.require_secret!({ "SECRET_KEY_BASE" => "" }, credentials: credentials) }
    assert_equal 0, credentials.reads
  end

  test "a secret in the credentials is accepted as Rails accepts it, with no variable set" do
    assert_nil HostSettings.require_secret!({}, credentials: Credentials.new("y" * 64))
  end

  test "credentials that hold no secret, a blank one or one that is no text are refused like none" do
    [ Credentials.new(nil), Credentials.new(""), Credentials.new("  "), Credentials.new(12_345), nil ].each do |credentials|
      error = assert_raises(HostSettings::MissingSecret, credentials.inspect) do
        HostSettings.require_secret!({}, credentials: credentials)
      end

      assert_match(/\ASECRET_KEY_BASE is not set\./, error.message)
      assert_includes error.message, "bin/rails secret"
      assert_no_match(/credentials/i, error.message)
    end
  end

  test "credentials that cannot be read are refused, and the message says to check RAILS_MASTER_KEY, with the error's class and not its text" do
    error = assert_raises(HostSettings::MissingSecret) { HostSettings.require_secret!({}, credentials: UnreadableCredentials.new) }

    assert_match(/\ASECRET_KEY_BASE is not set\./, error.message)
    assert_includes error.message, "bin/rails secret"
    assert_includes error.message, "A credentials file exists but could not be read"
    assert_includes error.message, "RAILS_MASTER_KEY"
    assert_includes error.message, "HostSettingsTest::UnreadableCredentials::WrongKey"
    assert_no_match(/credentials:edit/, error.message)
    assert_no_match(/the-master-key-as-typed/, error.message)
    assert_no_match(/the-master-key-as-typed/, error.full_message)
    assert_nil error.cause
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
