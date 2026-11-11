require "test_helper"

class TrustedProxiesTest < ActiveSupport::TestCase
  test "IPv4 and IPv6 ranges and bare addresses are read, in order, with spaces around the commas" do
    ranges = TrustedProxies.parse(" 173.245.48.0/20 , 2400:cb00::/32,198.51.100.7 ")

    assert_equal [ IPAddr.new("173.245.48.0/20"), IPAddr.new("2400:cb00::/32"), IPAddr.new("198.51.100.7") ], ranges
    assert_includes ranges.first, IPAddr.new("173.245.63.255")
  end

  test "unset or blank names no range" do
    assert_equal [], TrustedProxies.parse(nil)
    assert_equal [], TrustedProxies.parse("  ")
    assert_nil TrustedProxies.list({})
  end

  test "an entry that is not a range stops with a message that names the variable and the entry" do
    [ "173.245.48.0/40", "cloudflare", "10.0.0.0/8,,192.0.2.0/24", "2400:cb00::/32;" ].each do |value|
      error = assert_raises(TrustedProxies::Invalid) { TrustedProxies.parse(value) }

      assert_includes error.message, "TRUSTED_PROXIES"
    end
    error = assert_raises(TrustedProxies::Invalid) { TrustedProxies.parse("10.0.0.0/8, cloudflare") }
    assert_includes error.message, "“cloudflare”"
    error = assert_raises(TrustedProxies::Invalid) { TrustedProxies.parse("10.0.0.0/8,,192.0.2.0/24") }
    assert_includes error.message, "“”"
  end

  test "the ranges are added to Rails' own list, never put in its place" do
    proxies = TrustedProxies.list({ "TRUSTED_PROXIES" => "173.245.48.0/20" })

    assert_equal ActionDispatch::RemoteIp::TRUSTED_PROXIES + [ IPAddr.new("173.245.48.0/20") ], proxies
  end

  test "apply sets the configuration only when the variable names a range" do
    config = ActiveSupport::OrderedOptions.new
    config.action_dispatch = ActiveSupport::OrderedOptions.new

    TrustedProxies.apply(config, env: {})
    assert_nil config.action_dispatch.trusted_proxies

    TrustedProxies.apply(config, env: { "TRUSTED_PROXIES" => "2400:cb00::/32" })
    assert_includes config.action_dispatch.trusted_proxies, IPAddr.new("2400:cb00::/32")
    assert_includes config.action_dispatch.trusted_proxies, IPAddr.new("10.0.0.0/8")
  end
end
