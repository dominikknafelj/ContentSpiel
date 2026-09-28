require "application_system_test_case"

# Independent of the machine's colour-scheme preference: reads what the OS
# prefers, checks the page followed it, then flips and reloads.
class ThemeToggleTest < ApplicationSystemTestCase
  setup do
    # `delete_all`, not `destroy_all` -- see `SetupTestHelper#start_fresh_
    # install`'s own comment (Task 8's `User#ensure_not_last_owner`).
    User.delete_all
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

  test "the public site's toggle flips the theme and survives a reload" do
    # The shared `setup` block above clears setup_completed_at for the wizard
    # test above; the public site is a different concern and must not be sent
    # through Setup::RedirectConstraint's /setup redirect.
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
