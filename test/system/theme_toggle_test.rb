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
    # Must not be sent through Setup::RedirectConstraint's /cs-studio/setup redirect.
    site_settings(:default).update!(setup_completed_at: Time.current)
    Page.create!(title: "Home", slug: "", published_at: Time.current)
    visit "/"
    initial = current_theme
    other = initial == "dark" ? "light" : "dark"

    within("footer") { click_on(initial == "dark" ? "Light mode" : "Dark mode") }
    assert_equal other, current_theme

    visit "/"
    assert_equal other, current_theme
  end

  # The fade is seen through a spy in place of `document.startViewTransition`:
  # it records what the page says at the moment of the call (the theme, the
  # checked choice, the focused choice) and then runs the callback at once,
  # so no test waits on the animation and nothing reads a frame of it.
  SPY = <<~JS
    window.__vt = []
    document.startViewTransition = (callback) => {
      const checked = document.querySelector("[role=radio][aria-checked=true]")
      window.__vt.push({
        theme: document.documentElement.dataset.theme,
        checked: checked && checked.dataset.themeChoiceParam,
        focused: document.activeElement && document.activeElement.dataset.themeChoiceParam
      })
      callback()
      return { finished: Promise.resolve(), ready: Promise.resolve(), updateCallbackDone: Promise.resolve() }
    }
  JS

  # A spy that holds the callbacks until the test lets them run, in the order
  # of the calls or the reverse, as a transition's callback runs late in a
  # real browser (after the snapshot, and still when a newer one skips it).
  HOLDING_SPY = <<~JS
    window.__vt = []
    window.__held = []
    document.startViewTransition = (callback) => {
      window.__vt.push(document.documentElement.dataset.theme)
      window.__held.push(callback)
      return { finished: Promise.resolve(), ready: Promise.resolve(), updateCallbackDone: Promise.resolve() }
    }
  JS

  test "pressing Dark changes the theme through one view transition, with aria-checked set before it" do
    start_on "light"
    page.execute_script(SPY)

    within(switch) { press "Dark" }

    assert_selector "html[data-theme='dark'][data-theme-choice='dark']"
    calls = page.evaluate_script("window.__vt")
    assert_equal 1, calls.size
    assert_equal({ "theme" => "light", "checked" => "dark", "focused" => "dark" }, calls.first,
      "inside the transition the old theme is still drawn, and Dark is already checked and focused")
    assert_selector "button[role=radio][aria-checked='true']", text: /dark/i
  end

  test "under reduced motion the theme changes with no transition" do
    reduce_motion(true)
    start_on "light"
    page.execute_script(SPY)

    within(switch) { press "Dark" }

    assert_selector "html[data-theme='dark'][data-theme-choice='dark']"
    assert_equal [], page.evaluate_script("window.__vt")
  ensure
    reduce_motion(false)
  end

  test "two presses inside the fade end on the second choice, whichever callback runs last" do
    [ "window.__held.forEach((run) => run())", "window.__held.reverse().forEach((run) => run())" ].each do |flush|
      start_on "dark"
      page.execute_script(HOLDING_SPY)

      within(switch) { press "Dark" }
      within(switch) { press "Light" }
      assert_selector "button[role=radio][aria-checked='true']", text: /light/i
      assert_equal %w[dark dark], page.evaluate_script("window.__vt"), "no callback has run yet"

      page.execute_script(flush)

      assert_selector "html[data-theme='light'][data-theme-choice='light']"
      assert_selector "button[role=radio][aria-checked='true']", text: /light/i
    end
  end

  test "a transition that throws still changes the theme" do
    start_on "light"
    page.execute_script(<<~JS)
      document.startViewTransition = () => { throw new DOMException("hidden", "InvalidStateError") }
    JS

    within(switch) { press "Dark" }

    assert_selector "html[data-theme='dark'][data-theme-choice='dark']"
    assert_selector "button[role=radio][aria-checked='true']", text: /dark/i
  end

  test "the first paint never fades" do
    start_on "dark"
    # On THIS page only (`Browser#evaluate_on_new_document` would stay for every later test).
    script = page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source: SPY)
    visit admin_sign_in_path
    await_js("window.Stimulus && window.Stimulus.controllers.some((controller) => controller.identifier === 'theme')")
    await_frames

    assert_selector "html[data-theme='dark'][data-theme-choice='dark']"
    assert_equal [], page.evaluate_script("window.__vt")
  ensure
    page.driver.browser.page.command("Page.removeScriptToEvaluateOnNewDocument", identifier: script["identifier"]) if script
  end

  test "the public toggle fades too" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    Page.create!(title: "Home", slug: "", published_at: Time.current)
    visit "/"
    initial = current_theme
    other = initial == "dark" ? "light" : "dark"
    page.execute_script(SPY)

    within("footer") { click_on(initial == "dark" ? "Light mode" : "Dark mode") }

    assert_selector "html[data-theme='#{other}']"
    assert_equal [ initial ], page.evaluate_script("window.__vt").map { |call| call["theme"] }
  end

  test "an OS change while the choice is Auto fades, and does nothing under an explicit choice" do
    color_scheme("light")
    start_on "auto"
    assert_selector "html[data-theme='light'][data-theme-choice='auto']"
    page.execute_script(SPY)

    color_scheme("dark")

    assert_selector "html[data-theme='dark'][data-theme-choice='auto']"
    assert_equal [ "light" ], page.evaluate_script("window.__vt").map { |call| call["theme"] }

    within(switch) { press "Light" }
    page.execute_script("window.__vt = []")
    color_scheme("light")
    color_scheme("dark")
    await_frames

    assert_selector "html[data-theme='light'][data-theme-choice='light']"
    assert_equal [], page.evaluate_script("window.__vt")
  ensure
    page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [])
  end

  private
    # The theme stored, and the page drawn under it from its first paint, with
    # no press and so no transition before the test's own.
    def start_on(choice)
      visit admin_sign_in_path
      page.execute_script("localStorage.setItem('cs-theme', arguments[0])", choice)
      visit admin_sign_in_path
      assert_selector "html[data-theme-choice='#{choice}']"
    end

    def current_theme = page.evaluate_script("document.documentElement.dataset.theme")
    def switch = find("[role=radiogroup][aria-label='Theme']")
    def reduce_motion(on) = page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: on ? "reduce" : "" } ])
    def color_scheme(scheme) = page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: scheme } ])
end
