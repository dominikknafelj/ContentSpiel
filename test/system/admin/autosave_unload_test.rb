require "application_system_test_case"

# Closing the tab, or reloading it, on an autosave screen (`saving/queue_core.js`,
# "THE UNLOAD GUARD"): the browser asks first exactly when leaving would lose
# something -- an edit not yet sent or not yet answered, or text a refused save
# left only in the page -- and never on a screen that has nothing to lose.
#
# The browser's own "Leave site?" dialog can't be observed reliably through
# the driver, so what is tested is the decision: a `beforeunload` event
# dispatched in the page, and whether the guard called `preventDefault()` on
# it (which is what makes a real unload ask).
class Admin::AutosaveUnloadSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @page = create_page(title: "About")
  end

  test "an untouched editor does not ask, a typed edit asks until it is saved, and then it does not" do
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    assert_not asks_before_unload?, "a clean editor asked before unloading"

    # Each write is held for a moment, so "typed but not yet saved" is a
    # state the test can stand in: inside the debounce first, then on the
    # wire -- both are text only this page has.
    # Only the page's own save is held; every other request (the editor's
    # live parts, the claim that goes ahead of the save) takes the real fetch.
    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.__saves = []
      window.fetch = async (url, options = {}) => {
        const path = new URL(String(url.url || url), location.href).pathname
        const save = (options.method || "GET").toUpperCase() === "PATCH" && path === #{"/cs-studio/pages/#{@page.id}".to_json}
        if (save) { window.__saves.push(path); await new Promise((resolve) => setTimeout(resolve, 1500)) }
        return originalFetch(url, options)
      }
    JS
    fill_in "Subtitle", with: "Typed, not sent yet"
    assert asks_before_unload?, "an edit inside its debounce was not guarded"

    assert_selector "#page-save-status", text: "SAVING", wait: 5
    assert asks_before_unload?, "an edit on its way to the server was not guarded"

    assert_selector "#page-save-status", text: /SAVED( TO SITE)? \d{2}:\d{2}/, wait: 10
    assert_equal "Typed, not sent yet", @page.reload.subtitle
    assert_not asks_before_unload?, "a saved editor still asked before unloading"
    assert_equal [ "/cs-studio/pages/#{@page.id}" ], page.evaluate_script("window.__saves"), "the one save this test held"
  end

  test "an editor paused by Changed elsewhere asks: its text exists only in the page" do
    # The other editor's change lands more than the bar's one-second tolerance past the base the form loads.
    backdate(@page, by: 5.seconds)
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    as_unheard(users(:two)) { Pages::Save.call(@page, translations: { "en" => { subtitle: "The other editor's text" } }) }

    fill_in "Subtitle", with: "My text"
    assert_selector "#page-save-status", text: "● CHANGED ELSEWHERE", wait: 5
    assert asks_before_unload?, "a refused save's text was not guarded"

    # Reload is how that text is given up on purpose: the page that comes in
    # is clean again.
    click_link "Reload"
    assert_field "Subtitle", with: "The other editor's text"
    await_admin_controllers
    assert_not asks_before_unload?, "a reloaded editor still asked before unloading"
  end

  test "an editor whose save was given up on asks, and a screen without autosave forms never does" do
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    page.execute_script(<<~JS)
      const controller = window.Stimulus.getControllerForElementAndIdentifier(document.querySelector("form[data-controller~='admin--saving--autosave']"), "admin--saving--autosave")
      controller.constructor.retryDelays = [ 10, 10, 10 ]
      const originalFetch = window.fetch
      // Only the page's own save fails; the claim ahead of it, and every read, take the real fetch.
      window.__failed = 0
      window.fetch = (url, options = {}) => {
        const save = (options.method || "GET").toUpperCase() === "PATCH" && new URL(String(url.url || url), location.href).pathname === #{"/cs-studio/pages/#{@page.id}".to_json}
        if (!save) return originalFetch(url, options)
        window.__failed += 1
        return Promise.reject(new TypeError("Failed to fetch"))
      }
    JS
    fill_in "Subtitle", with: "Never arrives"
    assert_selector "#page-save-status button", text: "Retry", wait: 10
    assert asks_before_unload?, "an unsaved edit after a failed save was not guarded"
    assert_equal 4, page.evaluate_script("window.__failed"), "the save and its three retries"

    # The Trash screen has no autosave form at all: the guard is not even
    # listening there (it is removed with the last form). Reached by a Turbo
    # visit, so this is the same document the unsaved form was in.
    #
    # Wait for the Trash screen itself, not for the word "Trash": the sidebar
    # link on the editor already says it, and the visit is held until the
    # write queue has given up on the failed form (`drained()`), so for that
    # long this is still the editor, which rightly asks.
    within(".admin-shell__sidebar") { click_link "Trash" }
    assert_current_path %r{/cs-studio/trash}
    assert_no_selector "form[data-controller~='admin--saving--autosave']"
    assert_not asks_before_unload?, "a screen with no autosave form asked before unloading"
  end

  private

  def asks_before_unload?
    page.evaluate_script(<<~JS)
      (() => {
        const event = new Event("beforeunload", { cancelable: true })
        window.dispatchEvent(event)
        return event.defaultPrevented
      })()
    JS
  end
end
