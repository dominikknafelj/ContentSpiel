require "application_system_test_case"

# Independent of the machine's colour-scheme preference: reads what the OS
# prefers, checks the page followed it, then flips and reloads.
class ThemeToggleTest < ApplicationSystemTestCase
  setup do
    User.destroy_all
    site_settings(:default).update!(setup_completed_at: nil)
  end

  test "the wizard's toggle flips the theme, scopes color-scheme, and survives a reload" do
    visit setup_step_path("token")
    prefers_dark = page.evaluate_script("window.matchMedia('(prefers-color-scheme: dark)').matches")
    initial = prefers_dark ? "dark" : "light"
    assert_equal initial, current_theme

    other = initial == "dark" ? "light" : "dark"
    click_on(initial == "dark" ? "Light mode" : "Dark mode")
    assert_equal other, current_theme
    assert_equal other, page.evaluate_script("getComputedStyle(document.body).colorScheme")

    visit setup_step_path("token")
    assert_equal other, current_theme
  end

  private
    def current_theme = page.evaluate_script("document.documentElement.dataset.theme")
end
