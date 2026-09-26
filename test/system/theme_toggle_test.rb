require "application_system_test_case"

class ThemeToggleTest < ApplicationSystemTestCase
  test "the toggle switches to dark and the choice survives a reload" do
    visit new_session_path
    assert_equal "light", current_theme

    click_on "Dark mode"
    assert_equal "dark", current_theme

    visit new_session_path
    assert_equal "dark", current_theme
    assert_button "Light mode"
  end

  private
    def current_theme = page.evaluate_script("document.documentElement.dataset.theme")
end
