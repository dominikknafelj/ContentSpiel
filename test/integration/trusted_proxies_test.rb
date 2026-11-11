require "test_helper"

# `request.remote_ip` behind Cloudflare and kamal-proxy, through Rails' own
# middleware built with the list production builds (`TrustedProxies.apply`
# hands it to `config.action_dispatch.trusted_proxies`, which is this
# middleware's third argument). The test environment's own stack trusts no
# outside range, so the middleware is built here rather than reconfigured in
# the running app.
#
# The request is the one a deployed site sees: kamal-proxy on the host, a
# private address, sends it on with Cloudflare's edge appended to
# `X-Forwarded-For` after the visitor. Rails takes the nearest hop it does not
# trust, so the private hop alone being trusted (Rails' default) makes the
# edge the visitor.
class TrustedProxiesIntegrationTest < ActiveSupport::TestCase
  CLOUDFLARE_EDGE = "173.245.48.10".freeze
  KAMAL_PROXY = "10.0.0.2".freeze
  PERSON = "203.0.113.5".freeze

  test "with TRUSTED_PROXIES naming the edge's range, the forwarded address is the visitor's, and the private hop stays trusted" do
    assert_equal PERSON, remote_ip(env: { "TRUSTED_PROXIES" => "173.245.48.0/20" })
    assert_equal PERSON, remote_ip(env: { "TRUSTED_PROXIES" => "2400:cb00::/32, 173.245.48.0/20" })
  end

  test "without the variable every visitor is the edge" do
    assert_equal CLOUDFLARE_EDGE, remote_ip(env: {})
    assert_equal CLOUDFLARE_EDGE, remote_ip(env: {}, visitor: "198.51.100.9")
  end

  test "a range that does not hold the edge changes nothing" do
    assert_equal CLOUDFLARE_EDGE, remote_ip(env: { "TRUSTED_PROXIES" => "2400:cb00::/32" })
  end

  private
    def remote_ip(env:, visitor: PERSON)
      app = ->(rack_env) { [ 200, {}, [ ActionDispatch::Request.new(rack_env).remote_ip ] ] }
      middleware = ActionDispatch::RemoteIp.new(app, true, TrustedProxies.list(env))
      request = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => KAMAL_PROXY, "HTTP_X_FORWARDED_FOR" => "#{visitor}, #{CLOUDFLARE_EDGE}")
      _status, _headers, body = middleware.call(request)
      body.first
    end
end
