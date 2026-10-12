require "application_system_test_case"

# A theme's own script (theming spec §4): pinned under controllers/theme/,
# registered by the `site` entry point, and so alive on a public page and
# unknown to a page of the product's.
class ThemeScriptTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    root_page
  end

  test "a theme's controller connects on a public page under the theme" do
    with_plain_theme do
      visit "/"

      assert_selector "div.plain-frame[data-controller='theme--hello']"
      await_js(%(document.querySelector("div.plain-frame").dataset.plainHello === "connected"))
    end
  end

  test "the sign-in page registers the site's controllers and not the theme's" do
    visit admin_sign_in_path

    await_js(%(window.Stimulus.router.modulesByIdentifier.has("password-field")))
    await_frames
    assert_equal false, page.evaluate_script(%(window.Stimulus.router.modulesByIdentifier.has("theme--hello")))
  end
end
