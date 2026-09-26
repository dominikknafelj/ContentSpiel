require "application_system_test_case"

class ThemeToggleTest < ApplicationSystemTestCase
  test "the toggle switches to dark and the choice survives a reload" do
    visit new_session_path
    initial = current_theme
    prefers_dark = page.evaluate_script("window.matchMedia('(prefers-color-scheme: dark)').matches")
    assert_equal initial, (prefers_dark ? "dark" : "light")

    other = initial == "dark" ? "light" : "dark"
    click_on(initial == "dark" ? "Light mode" : "Dark mode")
    assert_equal other, current_theme

    visit new_session_path
    assert_equal other, current_theme
    assert_button(other == "dark" ? "Light mode" : "Dark mode")
  end

  private
    def current_theme = page.evaluate_script("document.documentElement.dataset.theme")
end
