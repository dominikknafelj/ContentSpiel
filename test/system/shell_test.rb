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

  # The scrim is un-hidden by `admin--drawer`, which knows nothing about
  # widths; widening the window with the drawer open turns the drawer back
  # into the ordinary sidebar, and the scrim must not stay over the page.
  test "a drawer left open across a resize to desktop width leaves no scrim over the page" do
    sign_in_via_form users(:one)
    page.driver.resize(1100, 900)
    await_admin_controllers
    find("button[aria-label='Open navigation']").click
    assert_selector "#sidebar[data-open]"
    assert_selector ".admin-shell__scrim", visible: true

    page.driver.resize(1400, 900)
    assert_no_selector ".admin-shell__scrim", visible: true
    within("#content") { assert_selector "h1" }
    # Nothing covers the content: a link in it takes a real click.
    assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('.admin-shell__scrim')).display")
  ensure
    page.driver.resize(1400, 1400)
  end

  test "at desktop width there is no top bar and the sidebar stays put" do
    sign_in_via_form users(:one)
    assert_no_selector ".admin-top-bar"
    assert_selector "#sidebar nav[aria-label='Modules']"
  end

  # Round 1 departure, dark and light: the sidebar's background ran only to the
  # viewport's bottom. Its grid cell now stretches the whole page and paints the
  # chrome background; the nav inside stays pinned to the viewport.
  %w[light dark].each do |theme|
    test "the sidebar background fills the page and the nav stays pinned on a long page (#{theme})" do
      sign_in_via_form users(:one)
      await_admin_controllers
      page.execute_script("document.documentElement.dataset.theme = '#{theme}'; document.querySelector('main').style.minHeight = '3000px'")
      page.execute_script("window.scrollTo(0, 1500)")

      metrics = page.evaluate_script(<<~JS)
        (() => {
          const cell = document.querySelector(".admin-shell__sidebar").getBoundingClientRect()
          const nav = document.querySelector("nav[aria-label=Modules]").getBoundingClientRect()
          return { cellHeight: cell.height, navTop: nav.top, navHeight: nav.height, viewport: window.innerHeight,
                   cellBackground: getComputedStyle(document.querySelector(".admin-shell__sidebar")).backgroundColor,
                   chrome: (() => { const p = document.createElement("div"); p.style.background = "var(--cs-chrome)"; document.body.appendChild(p); const c = getComputedStyle(p).backgroundColor; p.remove(); return c })() }
        })()
      JS
      assert_operator metrics["cellHeight"], :>=, 3000
      assert_in_delta 0, metrics["navTop"], 1
      assert_in_delta metrics["viewport"], metrics["navHeight"], 1
      assert_equal metrics["chrome"], metrics["cellBackground"]
    end
  end
end
