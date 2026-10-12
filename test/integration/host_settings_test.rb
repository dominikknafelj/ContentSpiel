require "test_helper"
require "rack/mock"

# The three middlewares `HostSettings` decides about, built by hand from a
# config it filled, in the order and under the conditions of Rails' own
# production stack (railties' `DefaultMiddlewareStack#build_stack`):
# `ActionDispatch::HostAuthorization` outermost and only when there are
# hosts, then `ActionDispatch::AssumeSSL` when `assume_ssl`, then
# `ActionDispatch::SSL` when `force_ssl`, with the app's own
# `ssl_default_redirect_status`. The order is what makes plain HTTP for a
# foreign host a refusal and not a redirect to that host. The test
# environment's own stack has none of the three, so a request through the app
# would prove nothing.
#
# `Rack::MockRequest` sends no `Host` header, which every real client does
# and which is the very thing host authorisation reads, so `get` here adds
# the one the URL names (with its port when the URL has one, as a browser
# would). Without it every request is refused, the site's own included.
class HostSettingsStackTest < ActiveSupport::TestCase
  HSTS = "max-age=31536000".freeze

  test "under an https address its own host is answered, with HSTS of one year and nothing more" do
    response = get("https://docs.example.org", "https://docs.example.org/")

    assert_equal 200, response.status
    assert_equal HSTS, response.headers["strict-transport-security"]
  end

  test "the host is matched whatever its case and with a port, and a cookie is made Secure" do
    [ "https://DOCS.Example.org/", "https://docs.example.org:8443/" ].each do |url|
      response = get("https://docs.example.org", url)

      assert_equal 200, response.status, url
      assert_match(/; secure/i, cookie(response), url)
    end
  end

  test "under an https address plain HTTP is redirected to it: a GET for good, a POST keeping its method" do
    response = get("https://docs.example.org", "http://docs.example.org/")

    assert_equal 301, response.status
    assert_equal "https://docs.example.org/", response.headers["location"]

    response = stack("https://docs.example.org").post("http://docs.example.org/", "HTTP_HOST" => "docs.example.org")

    assert_equal Rails.application.config.action_dispatch.ssl_default_redirect_status, response.status
    assert_includes [ 307, 308 ], response.status
  end

  test "under an https address another host is refused, www. and a subdomain included" do
    [ "https://evil.example/", "https://www.docs.example.org/", "https://xdocs.example.org/", "https://docs.example.org.evil.example/" ].each do |url|
      assert_equal 403, get("https://docs.example.org", url).status, url
    end
  end

  test "plain HTTP for another host is refused, never redirected to that host" do
    response = get("https://docs.example.org", "http://evil.example/")

    assert_equal 403, response.status
    assert_nil response.headers["location"]
  end

  test "behind a proxy that says the request was HTTPS, a plain request is answered: no redirect, HSTS sent" do
    response = get("https://docs.example.org", "http://docs.example.org/", "HTTP_X_FORWARDED_PROTO" => "https")

    assert_equal 200, response.status
    assert_equal HSTS, response.headers["strict-transport-security"]
  end

  test "behind a proxy that does not say so, a plain request is redirected unless ASSUME_SSL=1" do
    assert_equal 301, get("https://docs.example.org", "http://docs.example.org/").status
    assert_equal 301, get("https://docs.example.org", "http://docs.example.org/", {}, { "ASSUME_SSL" => "true" }).status

    response = get("https://docs.example.org", "http://docs.example.org/", {}, { "ASSUME_SSL" => "1" })

    assert_equal 200, response.status
    assert_equal HSTS, response.headers["strict-transport-security"]
  end

  test "ASSUME_SSL=1 does not open the door to another host" do
    assert_equal 403, get("https://docs.example.org", "http://evil.example/", {}, { "ASSUME_SSL" => "1" }).status
  end

  test "the health check is answered over plain HTTP by IP: no redirect, no refusal, no Secure cookie" do
    [ "http://10.0.0.5/up", "http://10.0.0.5/up?x=1" ].each do |url|
      response = get("https://docs.example.org", url)

      assert_equal 200, response.status, url
      assert_equal "ok", response.body
      assert_no_match(/; secure/i, cookie(response), url)
    end
  end

  test "only /up is the health check: beside it and under it nothing is answered by IP" do
    [ "/up/x", "/up/", "/UP", "/up.json" ].each do |path|
      assert_equal 403, get("https://docs.example.org", "https://10.0.0.5#{path}").status, path
    end
  end

  test "a forwarded host that is not the site's is refused although the Host is right" do
    response = get("https://docs.example.org", "https://docs.example.org/", "HTTP_X_FORWARDED_HOST" => "evil.example")

    assert_equal 403, response.status
  end

  test "under an http address its own host is answered as it is: no redirect, and no HSTS even for a request that was HTTPS" do
    assert_equal 200, get("http://localhost:3030", "http://localhost:3030/").status

    response = get("http://localhost:3030", "https://localhost:3030/")

    assert_equal 200, response.status
    assert_nil response.headers["strict-transport-security"]
    assert_no_match(/; secure/i, cookie(response))
  end

  test "under an http address another host is refused" do
    assert_equal 403, get("http://localhost:3030", "http://evil.example/").status
  end

  test "an IPv6 address is answered in the spelling it was given" do
    assert_equal 200, get("http://[::1]:3000", "http://[::1]:3000/").status
    assert_equal 403, get("http://[::1]:3000", "http://[::2]:3000/").status
  end

  test "with no address any host is answered" do
    assert_equal 200, get(nil, "http://anything.example/").status
  end

  private
    # One string, whichever way Rack hands the header back.
    def cookie(response) = Array(response.headers["set-cookie"]).join("\n")

    def get(address, url, headers = {}, env = {})
      uri = URI.parse(url)
      host = uri.port == uri.default_port ? uri.host : "#{uri.host}:#{uri.port}"
      stack(address, env).get(url, { "HTTP_HOST" => host }.merge(headers))
    end

    def stack(address, env = {})
      config = ActiveSupport::OrderedOptions.new
      config.action_mailer = ActiveSupport::OrderedOptions.new
      config.hosts = []
      HostSettings.apply(config, address: SiteAddress.parse(address), env: env)

      # Innermost first: the last one wrapped is the first a request meets.
      app = ->(_env) { [ 200, { "content-type" => "text/plain", "set-cookie" => "probe=1; path=/" }, [ "ok" ] ] }
      if config.force_ssl
        app = ActionDispatch::SSL.new(app, **config.ssl_options,
          ssl_default_redirect_status: Rails.application.config.action_dispatch.ssl_default_redirect_status)
      end
      app = ActionDispatch::AssumeSSL.new(app) if config.assume_ssl
      app = ActionDispatch::HostAuthorization.new(app, config.hosts, **config.host_authorization) if config.hosts.any?
      Rack::MockRequest.new(app)
    end
end
