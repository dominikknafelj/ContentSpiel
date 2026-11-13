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

  test "to_json and as_json hold no client secret" do
    provider = SignIn::Oidc::Provider.current(WHOLE)
    [ provider.to_json, provider.as_json.to_s, { provider: provider }.to_json, provider.inspect ].each do |text|
      assert_not_includes text, WHOLE["SSO_CLIENT_SECRET"]
    end
  end

  test "an issuer with a user or password in it is refused without naming it" do
    [ "https://planted-user:planted-pw@sso.example.org", "https://planted-user@sso.example.org" ].each do |value|
      error = assert_raises(SignIn::Oidc::Misconfigured) { SignIn::Oidc::Provider.check!(WHOLE.merge("SSO_ISSUER" => value)) }
      assert_not_includes error.message, "planted"
    end
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

  # The provider's discovery and keys, read from the fake provider on
  # 127.0.0.1 (test/support/oidc_helper.rb), under a server span as a request
  # would make them: a CLIENT span with no recording parent is dropped.
  def discovery_spans(&block)
    exporter = Rails.application.config.x.otel_test_exporter
    exporter.reset
    Telemetry.tracer.in_span("probe", kind: :server, &block)
    exporter.finished_spans.select { |span| span.name == "auth.sso.discovery" }
  end

  def discovery_reads(idp) = idp.requests.count { |request| request.path == "/idp/.well-known/openid-configuration" }

  test "discovery is read once, then from the cache for an hour, and its span says cached" do
    with_fake_idp do |idp|
      spans = discovery_spans do
        configuration = idp.provider.configuration
        assert_equal [ idp.issuer, "#{idp.issuer}/authorize", "#{idp.issuer}/token", "#{idp.issuer}/keys" ],
          [ configuration.issuer, configuration.authorization_endpoint, configuration.token_endpoint, configuration.jwks_uri ]
        assert_includes configuration.scopes_supported, "offline_access"
        assert_equal [ "client_secret_basic" ], configuration.token_auth_methods

        assert_equal configuration, idp.provider.configuration
        assert_equal 1, discovery_reads(idp)

        travel SignIn::Oidc::CACHE_FOR - 1.second
        idp.provider.configuration
        assert_equal 1, discovery_reads(idp)

        travel 2.seconds
        idp.provider.configuration
        assert_equal 2, discovery_reads(idp)
      end

      assert_equal [ false, true, true, false ], spans.map { |span| span.attributes["auth.sso.cached"] }
      assert spans.all? { |span| span.kind == :client && span.attributes["server.address"] == "127.0.0.1" }
    end
  end

  test "the keys are read once and cached, and refresh: reads them again" do
    with_fake_idp do |idp|
      key_reads = -> { idp.requests.count { |request| request.path == "/idp/keys" } }
      keys = idp.provider.keys
      assert_instance_of JSON::JWK::Set, keys
      assert_equal [ idp.key_id ], keys.map { |key| key[:kid] }

      idp.provider.keys
      assert_equal 1, key_reads.call
      idp.provider.keys(refresh: true)
      assert_equal 2, key_reads.call
      idp.provider.keys
      assert_equal 2, key_reads.call
    end
  end

  test "a discovery document naming another issuer is issuer_mismatch, and a refused socket is unreachable" do
    with_fake_idp do |idp|
      idp.answer_discovery_with(body: idp.discovery_document.merge("issuer" => "https://planted.example.org"))
      spans = discovery_spans do
        error = assert_raises(SignIn::Oidc::Unavailable) { idp.provider.configuration }
        assert_equal "issuer_mismatch", error.reason

        idp.down!
        error = assert_raises(SignIn::Oidc::Unavailable) { idp.provider.configuration }
        assert_equal "unreachable", error.reason
      end

      assert_equal [ "issuer_mismatch", "unreachable" ], spans.map { |span| span.attributes["auth.sso.reason"] }
      assert_equal [ "issuer_mismatch", "Errno::ECONNREFUSED" ], spans.map { |span| span.attributes["error.type"] }
      assert spans.none? { |span| span.attributes.values.join(" ").include?("planted") }
    end
  end

  test "a status, a body that is no JSON object, a body over the limit and a missing endpoint each name their reason, and nothing is cached" do
    with_fake_idp do |idp|
      document = idp.discovery_document
      {
        "http_503" => { status: 503, body: "down" },
        "not_json" => { body: "<html>" },
        "not_json " => { body: "[1, 2]" },
        "not_json  " => { body: { "padding" => "x" * SignIn::Oidc::MAX_BODY } },
        "missing_endpoint" => { body: document.except("token_endpoint") },
        "missing_endpoint " => { body: document.except("jwks_uri") }
      }.each do |reason, answer|
        idp.answer_discovery_with(**answer)
        error = assert_raises(SignIn::Oidc::Unavailable, reason) { idp.provider.configuration }
        assert_equal reason.strip, error.reason
      end

      assert_equal idp.issuer, idp.provider.configuration.issuer
      assert_equal 7, discovery_reads(idp)
    end
  end

  # A provider on an https issuer whose document is answered without the
  # network: `OutsideCall.perform` hands back `document` as a 200.
  def with_https_document(document)
    answer = Struct.new(:code, :body).new("200", document.to_json)
    with_singleton_override(SignIn::OutsideCall, :perform, ->(*, **) { answer }) do
      yield SignIn::Oidc::Provider.new(issuer: "https://idp.example.org", client_id: "client-1", secret: "s", name: "Example")
    end
  end

  def https_document
    {
      "issuer" => "https://idp.example.org", "authorization_endpoint" => "https://idp.example.org/authorize",
      "token_endpoint" => "https://idp.example.org/token", "jwks_uri" => "https://idp.example.org/keys",
      "response_types_supported" => [ "code" ], "subject_types_supported" => [ "public" ],
      "id_token_signing_alg_values_supported" => [ "RS256" ]
    }
  end

  test "an https issuer whose document names an http endpoint is refused, and an https one is read" do
    with_https_document(https_document) { |provider| assert_equal "https://idp.example.org/token", provider.configuration.token_endpoint }

    %w[token_endpoint jwks_uri authorization_endpoint].each do |member|
      with_https_document(https_document.merge(member => "http://idp.example.org/#{member}")) do |provider|
        error = assert_raises(SignIn::Oidc::Unavailable, member) { provider.configuration }
        assert_equal "missing_endpoint", error.reason
      end
    end
  end

  test "http to the loopback is an endpoint only outside production, as for the issuer" do
    assert SignIn::Oidc::Provider.secure_address?(URI("http://127.0.0.1:9/token"), production: false)
    assert_not SignIn::Oidc::Provider.secure_address?(URI("http://127.0.0.1:9/token"), production: true)
    assert_not SignIn::Oidc::Provider.secure_address?(URI("http://idp.example.org/token"), production: false)
    assert SignIn::Oidc::Provider.secure_address?(URI("https://idp.example.org/token"), production: true)
    assert_not SignIn::Oidc::Provider.secure_address?(URI("/token"), production: false)
  end

  test "another issuer is refused even with the gem's own issuer check turned off" do
    was = OpenIDConnect.validate_discovery_issuer
    OpenIDConnect.validate_discovery_issuer = false
    with_https_document(https_document.merge("issuer" => "https://planted.example.org")) do |provider|
      error = assert_raises(SignIn::Oidc::Unavailable) { provider.configuration }
      assert_equal "issuer_mismatch", error.reason
    end
  ensure
    OpenIDConnect.validate_discovery_issuer = was
  end

  test "a document missing a required member is missing_endpoint, and one whose endpoint is no URL is not_json" do
    with_https_document(https_document.except("subject_types_supported")) do |provider|
      assert_equal "missing_endpoint", assert_raises(SignIn::Oidc::Unavailable) { provider.configuration }.reason
    end
    with_https_document(https_document.merge("token_endpoint" => "not a url")) do |provider|
      assert_equal "not_json", assert_raises(SignIn::Oidc::Unavailable) { provider.configuration }.reason
    end
  end

  test "the discovery entry's key carries the configuration's version" do
    with_fake_idp do |idp|
      idp.provider.configuration
      digest = Digest::SHA256.hexdigest(idp.issuer)
      assert Rails.cache.exist?("content_spiel/oidc/discovery/#{digest}/v#{SignIn::Oidc::Configuration::CACHE_VERSION}")
      assert_not Rails.cache.exist?("content_spiel/oidc/discovery/#{digest}")
    end
  end
end
