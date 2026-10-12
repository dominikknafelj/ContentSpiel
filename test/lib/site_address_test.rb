require "test_helper"

class SiteAddressTest < ActiveSupport::TestCase
  test "a host is lower-cased and the path and trailing slash are dropped" do
    address = SiteAddress.parse("https://Docs.Example.org/")

    assert address.configured?
    assert_equal "https://docs.example.org", address.origin
    assert_equal "docs.example.org", address.host
    assert address.https?
    assert_nil address.port
  end

  test "a port, a path, a query and a fragment: the port stays, the rest goes" do
    address = SiteAddress.parse("http://localhost:3030/some/path?x=1#y")

    assert_equal "http://localhost:3030", address.origin
    assert_equal 3030, address.port
    assert_not address.https?
  end

  test "the scheme's default port is dropped" do
    address = SiteAddress.parse("https://example.org:443")

    assert_equal "https://example.org", address.origin
    assert_nil address.port
  end

  test "nothing, an empty string and blanks are not configured, and not an error" do
    [ nil, "", "  " ].each do |value|
      address = SiteAddress.parse(value)

      assert_not address.configured?, value.inspect
      assert_nil address.origin
      assert_nil address.host
      assert_nil address.port
      assert_not address.https?
      assert_equal({}, address.url_options)
    end
  end

  test "a value that is not an absolute http(s) address with a host is refused, and the message says what to write" do
    [ "docs.example.org", "ftp://example.org", "https://", "https:///path", "not a url" ].each do |value|
      error = assert_raises(SiteAddress::Invalid, value) { SiteAddress.parse(value) }

      assert_kind_of ArgumentError, error
      assert_includes error.message, "PUBLIC_HOST"
      assert_includes error.message, "https://www.example.org"
    end
  end

  test "url_options carry the host, the protocol and a non-default port" do
    assert_equal({ host: "example.org", protocol: "https", port: 8443 },
                 SiteAddress.parse("https://example.org:8443").url_options)
    assert_equal({ host: "example.org", protocol: "https" },
                 SiteAddress.parse("https://example.org").url_options)
  end

  test "current reads PUBLIC_HOST before SITEMAP_HOST and is memoised until reset" do
    saved = ENV.to_h.slice("PUBLIC_HOST", "SITEMAP_HOST")
    SiteAddress.reset!
    ENV["PUBLIC_HOST"] = "https://public.example.org"
    ENV["SITEMAP_HOST"] = "https://sitemap.example.org"

    assert_equal "https://public.example.org", SiteAddress.current.origin

    ENV["PUBLIC_HOST"] = ""
    assert_equal "https://public.example.org", SiteAddress.current.origin, "memoised"

    SiteAddress.reset!
    assert_equal "https://sitemap.example.org", SiteAddress.current.origin
  ensure
    ENV.delete("PUBLIC_HOST")
    ENV.delete("SITEMAP_HOST")
    saved.each { |key, value| ENV[key] = value }
    SiteAddress.reset!
  end
end
