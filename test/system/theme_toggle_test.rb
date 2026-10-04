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

  test "the public site's toggle flips the theme and survives a reload" do
    # Must not be sent through Setup::RedirectConstraint's /setup redirect.
    site_settings(:default).update!(setup_completed_at: Time.current)
    Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    visit "/"
    initial = current_theme
    other = initial == "dark" ? "light" : "dark"

    within("footer") { click_on(initial == "dark" ? "Light mode" : "Dark mode") }
    assert_equal other, current_theme

    visit "/"
    assert_equal other, current_theme
  end

  private
    def current_theme = page.evaluate_script("document.documentElement.dataset.theme")
end
