require "test_helper"

class Admin::LanguageSwitcherComponentTest < ViewComponent::TestCase
  # Enabled locales in the default SiteSetting fixture (test/fixtures/site_settings.yml):
  # en (default), de, es.

  test "lists every enabled locale by its native name, linked to the given url" do
    render_inline Admin::LanguageSwitcherComponent.new(current: "en", url: ->(code) { "/cs-studio/pages/1?locale=#{code}" })

    assert_selector "a[href='/cs-studio/pages/1?locale=de']", text: "Deutsch"
    assert_selector "a[href='/cs-studio/pages/1?locale=es']", text: "Español"
  end

  test "the current language is not a link" do
    render_inline Admin::LanguageSwitcherComponent.new(current: "en", url: ->(code) { "/x?locale=#{code}" })

    refute_selector "a", text: "English"
    assert_text "English"
  end

  test "missing codes get a dot marked with the missing-fields title" do
    render_inline Admin::LanguageSwitcherComponent.new(current: "en", missing: [ "de" ], url: ->(code) { "/x?locale=#{code}" })

    assert_selector "[title='Missing required fields']"
  end

  test "no dot when nothing is missing" do
    render_inline Admin::LanguageSwitcherComponent.new(current: "en", url: ->(code) { "/x?locale=#{code}" })

    refute_selector "[title='Missing required fields']"
  end
end
