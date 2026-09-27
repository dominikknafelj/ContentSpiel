require "test_helper"

class ThemeHelperTest < ActionView::TestCase
  # `language_links` calls `public_urls`, defined on PagesController (not a
  # helper module) via `helper_method` -- ActionView::TestCase's view context
  # never gets a controller's helper_method delegates, only app/helpers
  # modules, so this test stands in with its own instance, the same
  # `PublicSite::Urls.new` PagesController's own definition builds, just
  # without a request to read a host from (nothing here asserts on an
  # absolute URL).
  include PagesHelper

  def public_urls
    @public_urls ||= PublicSite::Urls.new
  end

  # Fix round 1 (review of 221fba9): `language_links` regressed to English
  # names ("German") when it switched from `SetupHelper::LANGUAGE_NAMES`
  # (native names) to `Locales.name(code)` (English by default). The
  # `<details>` switcher markup (app/views/layouts/public/_language_switcher
  # .html.erb) only renders `link.name` once there are more than three
  # enabled locales -- this app is pinned to exactly three
  # (config/application.rb) -- so an integration test can't reach this text;
  # a direct helper test is the only way to pin it.
  test "language_links names each locale natively, not in English" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    page = Page.create!(parent: root, page_type: :standard, title_en: "About", title_de: "Über",
      published_at: Time.current)

    links = language_links(page)

    assert_equal "English", links.find { |link| link.code == "en" }.name
    assert_equal "Deutsch", links.find { |link| link.code == "de" }.name, "not the English name 'German'"
    assert_equal "Español", links.find { |link| link.code == "es" }.name, "not the English name 'Spanish'"
  end
end
