require "test_helper"

class Locales::EnableDisableTest < ActiveSupport::TestCase
  setup do
    @about = create_page(title: "About")
  end

  test "enabling a language gives every page and post a URL in it" do
    post = create_post(title: "Hello")
    assert Locales::Enable.call("fr", actor: nil).ok?
    assert_equal "/about", @about.full_path("fr")
    assert_includes Locales.enabled, "fr"
    assert_equal "hello", post.reload.slug(locale: :fr)
  end

  test "disable then enable restores the same URLs" do
    Mobility.with_locale(:de) { @about.update!(slug: "ueber-uns") }
    assert Locales::Disable.call("de", actor: nil).ok?
    assert_nil @about.full_path("de")

    assert Locales::Enable.call("de", actor: nil).ok?
    assert_equal "/ueber-uns", @about.full_path("de")
  end

  # Enabling a language only *adds* URLs (spec §9.2): the old address of a
  # renamed page must keep 301ing afterwards.
  test "a redirect survives enabling a language" do
    Mobility.with_locale(:en) { @about.update!(slug: "about-me") }
    assert PublicPath.redirects.exists?(record: @about, locale: "en", path: "/about")

    assert Locales::Enable.call("fr", actor: nil).ok?

    assert PublicPath.redirects.exists?(record: @about, locale: "en", path: "/about")
    assert_equal "/about-me", @about.full_path("en")
    assert @about.full_path("fr").present?
  end

  test "the default language can't be disabled and unknown codes fail" do
    assert_not Locales::Disable.call(Locales.default, actor: nil).ok?
    assert_not Locales::Enable.call("xx", actor: nil).ok?
  end
end

# Covers the public route side of enabling/disabling (spec §4.4): the locale
# route constraint reads `Locales.enabled?` per request, so flipping the
# setting takes effect on the very next request with no deploy and no
# restart. A disabled locale's prefix isn't just "the page 404s" -- the
# router itself refuses to match `:locale` against it, so the request falls
# through to the unprefixed catch-all, which then 404s for an entirely
# different reason (no such unprefixed page). Kept as its own integration
# test, not folded into the service test above, because it needs a real
# request/response cycle rather than calling the service directly.
class Locales::EnableDisableRoutingTest < ActionDispatch::IntegrationTest
  test "a disabled locale's prefix 404s; enabling it makes the same URL 200" do
    create_page(title: "About")

    get "/fr/about"
    assert_response :not_found

    assert Locales::Enable.call("fr", actor: nil).ok?
    get "/fr/about"
    assert_response :success

    assert Locales::Disable.call("fr", actor: nil).ok?
    get "/fr/about"
    assert_response :not_found
  end
end
