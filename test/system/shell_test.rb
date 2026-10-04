require "application_system_test_case"

class ShellTest < ApplicationSystemTestCase
  test "under 1280 the sidebar is a drawer behind the top bar" do
    sign_in_via_form users(:one)
    page.driver.resize(1100, 900)
    assert_selector ".admin-top-bar"
    assert_no_selector "#sidebar[data-open]"
    find("button[aria-label='Open navigation']").click
    assert_selector "#sidebar[data-open]"
    assert_selector "button[aria-label='Open navigation'][aria-expanded=true]"
    find("body").send_keys(:escape)
    assert_no_selector "#sidebar[data-open]"
    find("button[aria-label='Open navigation']").click
    within("#sidebar") { click_link "Posts" }
    assert_selector "h1", text: "Posts"
    assert_no_selector "#sidebar[data-open]"
  ensure
    page.driver.resize(1400, 1400)
  end

  test "at desktop width there is no top bar and the sidebar stays put" do
    sign_in_via_form users(:one)
    assert_no_selector ".admin-top-bar"
    assert_selector "#sidebar nav[aria-label='Modules']"
  end
end
