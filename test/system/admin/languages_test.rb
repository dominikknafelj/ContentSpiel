require "application_system_test_case"

# Switching the editing language (cs-studio spec §6.2/§9): the language
# switcher navigates the whole content frame to the same record under a
# different `?locale=`, the primary-language original shows read-only, and
# a value typed there saves into that language alone.
class Admin::LanguagesSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @page = create_page(title: "About")
  end

  test "switching language shows the primary original, and a typed value saves only there" do
    visit "/cs-studio/pages/#{@page.id}"

    # `Locales.enabled` for the default fixture (`db/schema.rb`'s own
    # `site_settings.locales` default) is en/de/es -- "Deutsch" (native:
    # true, `Admin::LanguageSwitcherComponent`) is German's own link text.
    # A normal Turbo link, but scripted anyway (`press`) for the same
    # reason `test/system/setup_wizard_test.rb` gives its own clicks.
    within("nav[aria-label='Languages']") { press "Deutsch" }

    # No German title exists yet -- the read-only original beside the
    # (still empty) input is what proves the switch actually landed in the
    # new locale, not just that the page reloaded.
    assert_selector "[data-original-for='title']", text: "About"

    fill_in "Title", with: "Über uns"
    # `assert_selector(id, text:, wait:)`, not `within(id) { assert_text }`
    # -- see `test/system/admin/autosave_test.rb`'s own comment for why the
    # two-step form can raise `ElementNotFound` before its own explicit
    # wait gets any say.
    assert_selector "#page-save-status", text: /\ASaved \d{2}:\d{2}\z/, wait: 5

    @page.reload
    assert_equal "Über uns", @page.title(locale: :de)
    assert_equal "About", @page.title(locale: :en)
  end
end
