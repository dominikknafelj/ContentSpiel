require "test_helper"

# The site's one provider, from five variables: whole or nothing, and a host
# whose variables would open what it meant to close does not boot.
class SignIn::Oidc::ProviderTest < ActiveSupport::TestCase
  WHOLE = {
    "SSO_ISSUER" => "https://example.okta.com/oauth2/default", "SSO_CLIENT_ID" => "client-1",
    "SSO_CLIENT_SECRET" => "s3cret-value-of-the-client", "SSO_NAME" => "Okta"
  }.freeze

  test "all four variables make a provider, and any three make none" do
    provider = SignIn::Oidc::Provider.current(WHOLE)
    assert_equal [ "https://example.okta.com/oauth2/default", "client-1", "Okta", "example.okta.com" ],
      [ provider.issuer, provider.client_id, provider.name, provider.issuer_host ]

    WHOLE.each_key do |left_out|
      assert_nil SignIn::Oidc::Provider.current(WHOLE.except(left_out)), "without #{left_out}"
      assert_nil SignIn::Oidc::Provider.current(WHOLE.merge(left_out => "  ")), "blank #{left_out}"
    end
    assert_nil SignIn::Oidc::Provider.current({})
  end

  test "missing_variables names the missing ones and is empty with none set" do
    assert_empty SignIn::Oidc::Provider.missing_variables({})
    assert_empty SignIn::Oidc::Provider.missing_variables(WHOLE)
    assert_equal [ "SSO_CLIENT_SECRET" ], SignIn::Oidc::Provider.missing_variables(WHOLE.except("SSO_CLIENT_SECRET"))
    assert_equal %w[SSO_CLIENT_ID SSO_CLIENT_SECRET SSO_NAME], SignIn::Oidc::Provider.missing_variables(WHOLE.slice("SSO_ISSUER"))
  end

  test "required? is SSO_REQUIRED=1 with a whole provider, and SignIn::Oidc.required? agrees" do
    assert SignIn::Oidc::Provider.required?(WHOLE.merge("SSO_REQUIRED" => "1"))
    assert SignIn::Oidc.required?(WHOLE.merge("SSO_REQUIRED" => "1"))
    assert_not SignIn::Oidc::Provider.required?(WHOLE)
    assert_not SignIn::Oidc::Provider.required?({ "SSO_REQUIRED" => "1" })
    assert_not SignIn::Oidc::Provider.required?(WHOLE.merge("SSO_REQUIRED" => "yes"))
  end

  test "SSO_REQUIRED without a provider, SSO_REQUIRED=yes and an http issuer to another host each refuse, naming the variable and not the value" do
    error = assert_raises(SignIn::Oidc::Misconfigured) { SignIn::Oidc::Provider.check!({ "SSO_REQUIRED" => "1" }) }
    assert_equal "SSO_REQUIRED is set, but single sign-on is not: set SSO_ISSUER, SSO_CLIENT_ID, SSO_CLIENT_SECRET and SSO_NAME.", error.message

    error = assert_raises(SignIn::Oidc::Misconfigured) { SignIn::Oidc::Provider.check!(WHOLE.merge("SSO_REQUIRED" => "planted-yes")) }
    assert_includes error.message, "SSO_REQUIRED"
    assert_not_includes error.message, "planted-yes"

    error = assert_raises(SignIn::Oidc::Misconfigured) { SignIn::Oidc::Provider.check!(WHOLE.merge("SSO_ISSUER" => "http://planted.example.org/path")) }
    assert_includes error.message, "SSO_ISSUER"
    assert_not_includes error.message, "planted"

    [ "example.org", "ftp://example.org", "https://", "https://exa mple.org" ].each do |value|
      assert_raises(SignIn::Oidc::Misconfigured, value) { SignIn::Oidc::Provider.check!(WHOLE.merge("SSO_ISSUER" => value)) }
    end
  end

  test "a half-set provider never stops the boot, and a whole one passes" do
    assert_nil SignIn::Oidc::Provider.check!({})
    assert_nil SignIn::Oidc::Provider.check!(WHOLE.slice("SSO_ISSUER").merge("SSO_ISSUER" => "http://planted.example.org"))
    assert_nil SignIn::Oidc::Provider.check!(WHOLE.merge("SSO_REQUIRED" => "1"))
  end

  test "an http issuer to 127.0.0.1 is allowed outside production and refused in production" do
    local = WHOLE.merge("SSO_ISSUER" => "http://127.0.0.1:4567")
    assert_nil SignIn::Oidc::Provider.check!(local, production: false)
    assert_nil SignIn::Oidc::Provider.check!(WHOLE.merge("SSO_ISSUER" => "http://localhost:4567"), production: false)
    assert_nil SignIn::Oidc::Provider.check!(WHOLE.merge("SSO_ISSUER" => "http://[::1]:4567"), production: false)
    assert_raises(SignIn::Oidc::Misconfigured) { SignIn::Oidc::Provider.check!(local, production: true) }
  end

  test "inspect never holds the client secret" do
    provider = SignIn::Oidc::Provider.current(WHOLE)
    [ provider.inspect, provider.to_s, "#{provider}" ].each do |text|
      assert_not_includes text, WHOLE["SSO_CLIENT_SECRET"]
      assert_includes text, "example.okta.com"
    end
    assert_raises(NoMethodError) { provider.client_secret }
  end

  test "callback_origin is the admin address, then the public address, then the request's" do
    request = "http://www.example.com"
    assert_equal({ host: "www.example.com", protocol: "http" }, SignIn::Oidc.callback_origin(request_origin: request))
    assert_equal({ host: "127.0.0.1", protocol: "http", port: 3000 }, SignIn::Oidc.callback_origin(request_origin: "http://127.0.0.1:3000"))

    with_site_address("https://docs.example.org") do
      assert_equal({ host: "docs.example.org", protocol: "https" }, SignIn::Oidc.callback_origin(request_origin: request))
      with_admin_address("https://studio.example.net") do
        assert_equal({ host: "studio.example.net", protocol: "https" }, SignIn::Oidc.callback_origin(request_origin: request))
      end
    end
  end
end
