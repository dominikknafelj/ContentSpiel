require "application_system_test_case"

class ThemeToggleTest < ApplicationSystemTestCase
  test "light, dark and auto each apply, survive a reload, and mark the chosen button" do
    visit admin_sign_in_path
    within("[role=radiogroup][aria-label='Theme']") { press "Dark" }
    assert_selector "html[data-theme='dark'][data-theme-choice='dark']"
    assert_selector "button[role=radio][aria-checked='true']", text: /dark/i

    visit admin_sign_in_path
    assert_selector "html[data-theme='dark'][data-theme-choice='dark']"

    within("[role=radiogroup][aria-label='Theme']") { press "Light" }
    assert_selector "html[data-theme='light'][data-theme-choice='light']"

    within("[role=radiogroup][aria-label='Theme']") { press "Auto" }
    assert_selector "html[data-theme-choice='auto']"
    assert_equal "auto", page.evaluate_script("localStorage.getItem('cs-theme')")
  end

  test "a junk stored value falls back to auto instead of breaking the page" do
    visit admin_sign_in_path
    page.execute_script("localStorage.setItem('cs-theme', 'blue')")
    visit admin_sign_in_path
    assert_selector "html[data-theme-choice='auto']"
    assert_selector "button[role=radio][aria-checked='true']", text: /auto/i
  end
end
