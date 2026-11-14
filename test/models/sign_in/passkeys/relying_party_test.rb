require "test_helper"

# Where a passkey belongs: the relying party's id is what a browser
# binds a credential to, so it is decided once: from ADMIN_HOST when CS
# Studio has an address of its own, from PUBLIC_HOST when the site has one,
# and from the request otherwise.
class SignIn::Passkeys::RelyingPartyTest < ActiveSupport::TestCase
  def party(request_origin: "http://www.example.com")
    SignIn::Passkeys::RelyingParty.for(request_origin: request_origin, name: "Site")
  end

  test "the id is the registrable domain of PUBLIC_HOST and the origin the address" do
    with_site_address("https://www.example.org") do
      relying_party = party(request_origin: "https://www.example.org")
      assert_equal "example.org", relying_party.id
      assert_equal [ "https://www.example.org" ], relying_party.allowed_origins
      assert_equal "Site", relying_party.name
    end

    with_site_address("https://foo.github.io") do
      assert_equal "foo.github.io", party.id, "a private suffix's own name is its registrable domain"
      assert_equal [ "https://foo.github.io" ], party.allowed_origins, "the address, never the request's origin"
    end

    with_site_address("http://localhost:3000") do
      assert_equal "localhost", party.id
      assert_equal [ "http://localhost:3000" ], party.allowed_origins
    end
  end

  test "with no address the request's host is the id, and an IP host has no relying party" do
    with_site_address(nil) do
      relying_party = party(request_origin: "http://www.example.com")
      assert_equal "www.example.com", relying_party.id, "the request's host itself, not its registrable domain"
      assert_equal [ "http://www.example.com" ], relying_party.allowed_origins

      assert_equal "localhost", party(request_origin: "http://localhost:3000").id
      assert_equal [ "http://localhost:3000" ], party(request_origin: "http://localhost:3000").allowed_origins

      assert_nil party(request_origin: "http://127.0.0.1:3000")
      assert_nil party(request_origin: "http://[::1]:3000")
      assert_nil party(request_origin: nil)
      assert_nil party(request_origin: "not an origin")
    end

    with_site_address("http://192.168.1.20") do
      assert_nil party(request_origin: "http://192.168.1.20")
    end
  end

  test "with an admin host in another domain the id and origin are the admin host's" do
    with_site_address("https://docs.example.org") do
      with_admin_address("https://studio.example.internal") do
        relying_party = party(request_origin: "https://studio.example.internal")
        assert_equal "example.internal", relying_party.id
        assert_equal [ "https://studio.example.internal" ], relying_party.allowed_origins
      end

      with_admin_address("https://cms") do
        assert_equal "cms", party(request_origin: "https://cms").id, "a host with no registrable domain is its own id"
        assert_equal [ "https://cms" ], party(request_origin: "https://cms").allowed_origins
      end
    end
  end

  test "with an admin host in the public host's domain the id is shared and the origin the admin host's" do
    with_site_address("https://www.example.org") do
      with_admin_address("https://studio.example.org:8443") do
        relying_party = party(request_origin: "https://studio.example.org:8443")
        assert_equal "example.org", relying_party.id
        assert_equal [ "https://studio.example.org:8443" ], relying_party.allowed_origins
      end
    end
  end

  test "an admin host at an IP address has no relying party" do
    with_site_address("https://www.example.org") do
      with_admin_address("https://10.0.0.5") do
        assert_nil party(request_origin: "https://10.0.0.5")
      end
    end
  end
end
