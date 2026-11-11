require "test_helper"

class VisitorAddressTest < ActiveSupport::TestCase
  PURPOSE = "content_spiel visitor address test".freeze

  test "an IPv4 address is counted whole, and an IPv4-mapped one as IPv4" do
    assert_equal "203.0.113.7", VisitorAddress.normalise("203.0.113.7")
    assert_equal "203.0.113.7", VisitorAddress.normalise("::ffff:203.0.113.7")
    assert_not_equal VisitorAddress.key("203.0.113.7", purpose: PURPOSE), VisitorAddress.key("203.0.113.8", purpose: PURPOSE)
  end

  test "an IPv6 address is counted as its /64" do
    assert_equal "2001:db8:1:2::/64", VisitorAddress.normalise("2001:db8:1:2:abcd:ef01:2345:6789")
    assert_equal VisitorAddress.key("2001:db8:1:2::a", purpose: PURPOSE), VisitorAddress.key("2001:db8:1:2:ffff::b", purpose: PURPOSE)
    assert_not_equal VisitorAddress.key("2001:db8:1:2::a", purpose: PURPOSE), VisitorAddress.key("2001:db8:1:3::a", purpose: PURPOSE)
  end

  test "a value that is no address is counted as written" do
    assert_equal "not an address", VisitorAddress.normalise("not an address")
    assert_equal "", VisitorAddress.normalise(nil)
  end

  test "the key is 64 hex characters so it holds no address" do
    key = VisitorAddress.key("2001:db8:1:2::a", purpose: PURPOSE)
    assert_match(/\A\h{64}\z/, key)
    assert_match(/\A\h{64}\z/, VisitorAddress.key("203.0.113.7", purpose: PURPOSE))
  end

  test "digest keys a text as written, under the purpose's own secret" do
    assert_equal VisitorAddress.key("203.0.113.7", purpose: PURPOSE), VisitorAddress.digest("203.0.113.7", purpose: PURPOSE)
    assert_not_equal VisitorAddress.key("2001:db8:1:2::a", purpose: PURPOSE), VisitorAddress.digest("2001:db8:1:2::a", purpose: PURPOSE), "not cut to its /64"
    assert_match(/\A\h{64}\z/, VisitorAddress.digest("ann@example.org", purpose: PURPOSE))
  end

  test "two purposes give two keys for one address" do
    assert_not_equal VisitorAddress.key("203.0.113.7", purpose: PURPOSE), VisitorAddress.key("203.0.113.7", purpose: "content_spiel another counter")
    assert_equal VisitorAddress.key("203.0.113.7", purpose: PURPOSE), VisitorAddress.key("203.0.113.7", purpose: PURPOSE)
  end
end
