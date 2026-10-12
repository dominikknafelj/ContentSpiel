require "test_helper"
require "rack/mock"

# The two middlewares `HostSettings` configures, built by hand from a config
# it filled, the way Rails' own default stack builds them in production
# (`ActionDispatch::HostAuthorization` only when there are hosts,
# `ActionDispatch::SSL` only when HTTPS is forced). The test environment's
# own stack has neither, so a request through the app would prove nothing.
#
# `Rack::MockRequest` sends no `Host` header, which every real client does
# and which is the very thing host authorisation reads, so `get` here adds
# the one the URL names (with its port when the URL has one, as a browser
# would). Without it every request is refused, the site's own included.
class HostSettingsStackTest < ActiveSupport::TestCase
  test "under an https address its own host is answered, with HSTS" do
    response = get("https://docs.example.org", "https://docs.example.org/")

    assert_equal 200, response.status
    assert response.headers["strict-transport-security"].present?
  end

  test "under an https address plain HTTP is redirected to it" do
    response = get("https://docs.example.org", "http://docs.example.org/")

    assert_equal 301, response.status
    assert_equal "https://docs.example.org/", response.headers["location"]
  end

  test "under an https address another host is refused" do
    assert_equal 403, get("https://docs.example.org", "https://evil.example/").status
  end

  test "the health check is answered over plain HTTP by IP: no redirect, no refusal" do
    response = get("https://docs.example.org", "http://10.0.0.5/up")

    assert_equal 200, response.status
    assert_equal "ok", response.body
  end

  test "only /up is the health check: a path under it by IP is not answered" do
    assert_equal 403, get("https://docs.example.org", "https://10.0.0.5/up/x").status
  end

  test "a forwarded host that is not the site's is refused although the Host is right" do
    response = get("https://docs.example.org", "https://docs.example.org/", "HTTP_X_FORWARDED_HOST" => "evil.example")

    assert_equal 403, response.status
  end

  test "under an http address its own host is answered without HSTS and without a redirect" do
    response = get("http://localhost:3030", "http://localhost:3030/")

    assert_equal 200, response.status
    assert_nil response.headers["strict-transport-security"]
  end

  test "under an http address another host is refused" do
    assert_equal 403, get("http://localhost:3030", "http://evil.example/").status
  end

  test "with no address any host is answered" do
    assert_equal 200, get(nil, "http://anything.example/").status
  end

  private
    def get(address, url, headers = {})
      uri = URI.parse(url)
      host = uri.port == uri.default_port ? uri.host : "#{uri.host}:#{uri.port}"
      stack(address).get(url, { "HTTP_HOST" => host }.merge(headers))
    end

    def stack(address, env = {})
      config = ActiveSupport::OrderedOptions.new
      config.action_mailer = ActiveSupport::OrderedOptions.new
      config.hosts = []
      HostSettings.apply(config, address: SiteAddress.parse(address), env: env)
      app = ->(_env) { [ 200, { "content-type" => "text/plain" }, [ "ok" ] ] }
      app = ActionDispatch::HostAuthorization.new(app, config.hosts, **config.host_authorization) if config.hosts.any?
      app = ActionDispatch::SSL.new(app, **config.ssl_options) if config.force_ssl
      Rack::MockRequest.new(app)
    end
end
