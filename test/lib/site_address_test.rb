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
    [ "docs.example.org", "ftp://example.org", "https://", "https:///path", "not a url", "https://." ].each do |value|
      error = assert_raises(SiteAddress::Invalid, value) { SiteAddress.parse(value) }

      assert_kind_of ArgumentError, error
      assert_equal "PUBLIC_HOST must be the site's address with its scheme, for example https://www.example.org", error.message
    end
  end

  test "the message names the variable the value came from and never repeats the value" do
    error = assert_raises(SiteAddress::Invalid) { SiteAddress.parse("nonsense", source: "SITEMAP_HOST") }

    assert_equal "SITEMAP_HOST must be the site's address with its scheme, for example https://www.example.org", error.message

    [ "https://user:hunter2@", "https://user:hunter2@exa mple.org", "https://user:hunter2@host.example:99999" ].each do |value|
      error = assert_raises(SiteAddress::Invalid, value) { SiteAddress.parse(value) }

      assert_no_match(/hunter2|user:|@|exa mple|host\.example/, error.message, value)
    end
  end

  test "an address with user info is refused, also an otherwise good one and an empty one" do
    [ "https://user:hunter2@host.example/", "https://user@host.example", "https://@host.example" ].each do |value|
      error = assert_raises(SiteAddress::Invalid, value) { SiteAddress.parse(value) }

      assert_no_match(/hunter2/, error.message)
    end
    assert_equal "https://host.example", SiteAddress.parse("https://host.example/@someone").origin, "an @ in the path is no user info"
  end

  test "a port outside 1..65535 is refused, and the ends of the range are not" do
    [ "https://a.example:0", "https://a.example:65536", "https://a.example:99999" ].each do |value|
      assert_raises(SiteAddress::Invalid, value) { SiteAddress.parse(value) }
    end
    assert_equal 1, SiteAddress.parse("https://a.example:1").port
    assert_equal 65_535, SiteAddress.parse("https://a.example:65535").port
  end

  test "whitespace or a control character inside the value is refused, and the message stays one line" do
    [ "https://exa mple.org", "https://a.example\nhttps://b.example", "https://a.example\tb", "https://a.exa\u0000mple", "https://a.example\e[31m" ].each do |value|
      error = assert_raises(SiteAddress::Invalid, value.inspect) { SiteAddress.parse(value) }

      assert_equal 1, error.message.lines.size
    end
    assert_equal "https://a.example", SiteAddress.parse("  https://a.example\n").origin, "blanks around the value are not part of it"
  end

  test "a trailing dot of the host is dropped" do
    address = SiteAddress.parse("https://a.example.:8443/")

    assert_equal "a.example", address.host
    assert_equal "https://a.example:8443", address.origin
  end

  test "an IPv6 literal is accepted, lower-cased and keeps its brackets" do
    address = SiteAddress.parse("http://[2001:DB8::1]:3000")

    assert_equal "[2001:db8::1]", address.host
    assert_equal "http://[2001:db8::1]:3000", address.origin
    assert_equal "https://[::1]", SiteAddress.parse("https://[::1]").origin
  end

  test "an upper-case scheme is accepted and lower-cased, and its default port still dropped" do
    address = SiteAddress.parse("HTTPS://Host.Example:443/")

    assert address.https?
    assert_equal "https://host.example", address.origin
    assert_equal({ host: "host.example", protocol: "https" }, address.url_options)
  end

  test "a host that is not ASCII is refused with the same message: nothing is converted" do
    error = assert_raises(SiteAddress::Invalid) { SiteAddress.parse("https://münchen.example") }

    assert_equal "PUBLIC_HOST must be the site's address with its scheme, for example https://www.example.org", error.message
    assert_equal "https://xn--mnchen-3ya.example", SiteAddress.parse("https://xn--mnchen-3ya.example").origin
  end

  test "url_options carry the host, the protocol and a non-default port" do
    assert_equal({ host: "example.org", protocol: "https", port: 8443 },
                 SiteAddress.parse("https://example.org:8443").url_options)
    assert_equal({ host: "example.org", protocol: "https" },
                 SiteAddress.parse("https://example.org").url_options)
  end

  test "url_options of an http address say http, so its links are not https ones" do
    assert_equal({ host: "example.org", protocol: "http" }, SiteAddress.parse("http://example.org").url_options)
    assert_equal({ host: "localhost", protocol: "http", port: 3030 }, SiteAddress.parse("http://localhost:3030").url_options)
  end

  test "an address cannot be changed once it is parsed" do
    assert SiteAddress.parse("https://example.org").frozen?
    assert SiteAddress.parse(nil).frozen?
  end

  test "current reads PUBLIC_HOST before SITEMAP_HOST and is memoised until reset" do
    with_site_address("https://public.example.org") do
      ENV["SITEMAP_HOST"] = "https://sitemap.example.org"

      assert_equal "https://public.example.org", SiteAddress.current.origin

      ENV["PUBLIC_HOST"] = "https://changed.example.org"
      assert_equal "https://public.example.org", SiteAddress.current.origin, "memoised"

      SiteAddress.reset!
      assert_equal "https://changed.example.org", SiteAddress.current.origin
    end
  end

  test "a PUBLIC_HOST that is set but blank falls through to SITEMAP_HOST" do
    [ "", "   " ].each do |blank|
      with_site_address(blank) do
        ENV["SITEMAP_HOST"] = "https://sitemap.example.org"
        SiteAddress.reset!

        assert_equal "https://sitemap.example.org", SiteAddress.current.origin, blank.inspect
      end
    end
  end

  test "with neither variable there is no address, and that is not an error" do
    with_site_address(nil) { assert_not SiteAddress.current.configured? }
  end

  test "current's refusal names the variable that held the value" do
    with_site_address("nonsense") do
      error = assert_raises(SiteAddress::Invalid) { SiteAddress.current }
      assert_equal "PUBLIC_HOST must be the site's address with its scheme, for example https://www.example.org", error.message
    end

    with_site_address(nil) do
      ENV["SITEMAP_HOST"] = "nonsense"
      SiteAddress.reset!

      error = assert_raises(SiteAddress::Invalid) { SiteAddress.current }
      assert_equal "SITEMAP_HOST must be the site's address with its scheme, for example https://www.example.org", error.message
    end
  end

  test "with_site_address puts both variables and the memo back, also when the block raises" do
    with_site_address("https://outer.example.org") do
      ENV["SITEMAP_HOST"] = "https://outer-sitemap.example.org"

      assert_raises(RuntimeError) do
        with_site_address("https://inner.example.org") do
          assert_equal "https://inner.example.org", SiteAddress.current.origin
          assert_nil ENV["SITEMAP_HOST"]
          raise "stop"
        end
      end

      assert_equal "https://outer.example.org", ENV["PUBLIC_HOST"]
      assert_equal "https://outer-sitemap.example.org", ENV["SITEMAP_HOST"]
      assert_equal "https://outer.example.org", SiteAddress.current.origin
    end
  end
end
