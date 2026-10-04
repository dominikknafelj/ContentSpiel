require "test_helper"
require "capybara/cuprite"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Cuprite drives headless Chrome over the DevTools protocol (via Ferrum),
  # dispatching clicks and key events straight to the page with
  # `Input.dispatch*Event`. It replaced Selenium (PR #30): WebDriver's
  # keyboard actions intermittently never reached a fully rendered, focused
  # page on CI -- one unrelated system test per run, never locally -- and a
  # handshake that waited for native input couldn't make them arrive.
  #
  # `js_errors: false`: with `true`, any uncaught exception or unhandled
  # rejection in the page fails the test, and Turbo itself produces a
  # harmless one -- a `<turbo-frame>` disconnected mid-load (e.g. by a
  # back-navigation's snapshot render) cancels its fetch and the resulting
  # `AbortError` escapes Turbo unhandled. That flaked the API-token test's
  # `go_back` about every other run. Tests assert on what the page shows and
  # saves instead, which is where a broken controller shows up anyway.
  # `no-sandbox` because GitHub's runners (and most containers) can't give
  # Chrome its user-namespace sandbox.
  driven_by :cuprite, screen_size: [ 1400, 1400 ], options: {
    headless: true,
    js_errors: false,
    process_timeout: 30,
    timeout: 15,
    browser_options: { "no-sandbox" => nil }
  }

  # Signs in through the real sign-in form (cs-studio spec §3/§9). `Session
  # TestHelper#sign_in_as` -- what every integration test uses -- only ever
  # sets cookies on the test process's own internal Rack::Test session; a
  # system test's browser is a *separate* HTTP client Cuprite drives, so
  # cookies set that way never reach it. Signing in has to happen the way a
  # real editor would: an actual POST the browser itself sends.
  def sign_in_via_form(user, password: "password")
    visit admin_sign_in_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: password
    press "Sign in"

    # `press`'s own click fires a real (async) browser form submission --
    # sign-in redirects to CS Studio's own shell, so waiting for its
    # "Modules" nav (rather than just returning immediately) is what makes
    # sure the session cookie the redirect sets has actually landed before
    # a caller's next `visit` fires. Without this, a caller moving straight
    # on to its own `visit` could race the still-in-flight sign-in POST,
    # navigate away before its `Set-Cookie` response ever arrives, and land
    # right back on the sign-in page, unauthenticated.
    assert_selector "nav[aria-label='Modules']"
  end

  # Opens the editor header's ⋯ menu (Activity, Schedule…, Unpublish, Move to
  # trash live in it), waiting until its panel is shown.
  def open_editor_menu
    find("header.admin-editor-header button[aria-label='More actions']").click
    assert_selector "header.admin-editor-header [role=menu]"
  end

  # Clicks through JavaScript (`element.click()`) instead of a native click.
  # Under Selenium this first worked around headless Chrome intermittently
  # dropping native WebDriver clicks made right after a page load. It stays
  # under Cuprite: a scripted click fires just the `click` these tests mean
  # to exercise. Tests that are *about* a real pointer click natively (the
  # mind graph, and the related-posts picker -- a native click there once
  # lost the pick, because the autosave its mousedown started grew the
  # empty save-status line and moved the button out from under the
  # mouseup; `Admin::SaveStatusComponent` now reserves that line).
  def press(label)
    find(:link_or_button, label).execute_script("this.click()")
  end

  # A rich-text editor's Insert menu item (Page link, Image, YouTube,
  # Divider): opens the menu, then presses the item -- which is only
  # *visible* (so findable) while the menu is open, which is part of what
  # this checks. `within:` scopes to one editor's toolbar when a page has
  # several.
  def press_insert(label, within: "[role=toolbar]")
    find("#{within} button[aria-haspopup=menu]", match: :first).execute_script("this.click()")
    find("#{within} [role=menu] button", text: label, match: :first).execute_script("this.click()")
  end

  # CS Studio's Stimulus controllers (`controllers/admin/*`) are registered
  # by the `admin` entry point (app/javascript/admin.js) through one dynamic
  # `import()` each, so they connect a moment *after* the page has loaded,
  # even though they're modulepreloaded. A test that types right after
  # `visit` can race them -- before `admin--autosave` is connected its
  # `input` events go nowhere. So this waits until every `admin--*`
  # controller named on the page is connected.
  #
  # Cuprite needs no further wait before typing: its key events go to the
  # page through CDP rather than through a WebDriver input queue, so there
  # is no separate "accepting native input" state to wait for (Selenium
  # needed an `await_native_input` handshake here, which is what flaked).
  def await_admin_controllers
    page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      const ready = () => {
        const app = window.Stimulus
        if (!app) return false
        return Array.from(document.querySelectorAll("[data-controller*='admin--']")).every((element) =>
          element.getAttribute("data-controller").split(" ").filter((name) => name.startsWith("admin--"))
            .every((name) => app.getControllerForElementAndIdentifier(element, name)))
      }
      const poll = () => (ready() ? done(true) : setTimeout(poll, 20))
      poll()
    JS
  end
end
