require "application_system_test_case"

# The keyboard of what CS Studio says back: a toast, a save's status line,
# the mail-failed notice and a system check's row, each a test its
# component's contract names (`keyboard:`, `docs/reference/design-system.md`,
# "Component contract"). Each holds a control, and the test reaches it with
# Tab from the words beside it, which it clicks as a person reading the
# screen would, and presses it with the keys.
class Admin::KeyboardFeedbackSystemTest < ApplicationSystemTestCase
  include MailState

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
  end

  test "a toast's action and its Dismiss are Tab stops after its words: Enter on Undo undoes, and Enter on Dismiss closes it" do
    post = Current.set(actor: users(:one)) { create_post(title: "Toasted by keyboard") }
    visit_editor(post)

    open_editor_menu
    press "Move to trash…"
    within("dialog[open]") { press "Move to trash" }
    toast = "#toasts .admin-toast"
    assert_selector toast, text: /trash/i, wait: 10
    assert post.reload.trashed?

    find(toast, text: /trash/i).find("span", match: :first).click
    page.send_keys(:tab)
    assert_equal "Undo", focused_text
    page.send_keys(:enter)
    assert_selector toast, text: "Restored", wait: 10
    assert_not post.reload.trashed?

    restored = find(toast, text: "Restored")
    restored.find("span", text: "Restored").click
    page.send_keys(:tab)
    assert_equal "Dismiss", page.evaluate_script("document.activeElement.getAttribute('aria-label')")
    page.send_keys(:enter)
    assert_no_selector toast, text: "Restored"
  end

  test "a save status's Retry is a Tab stop, and Enter on it sends the save again" do
    page_record = create_page(title: "Retried")
    visit_editor(page_record)
    page.execute_script(<<~JS)
      const controller = window.Stimulus.getControllerForElementAndIdentifier(document.querySelector("form[data-controller~='admin--saving--autosave']"), "admin--saving--autosave")
      controller.constructor.retryDelays = [ 10, 10, 10 ]
      window.__realFetch = window.fetch
      // Only the page's own save fails, until the test lets it through; the claim ahead of it, and every read, take the real fetch.
      window.__offline = true
      window.__failed = 0
      window.fetch = (url, options = {}) => {
        const save = (options.method || "GET").toUpperCase() === "PATCH" && new URL(String(url.url || url), location.href).pathname === #{"/cs-studio/pages/#{page_record.id}".to_json}
        if (!save || !window.__offline) return window.__realFetch(url, options)
        window.__failed += 1
        return Promise.reject(new TypeError("Failed to fetch"))
      }
    JS
    fill_in "Subtitle", with: "Sent again"
    # Back out of the form to the language tabs: every field the focus leaves
    # sends the failed save again, so Retry is waited for only once the focus
    # is past them, and the save and its three retries are spent.
    stop_on("nav[aria-label='Languages'] a", keys: [ :shift, :tab ])
    status = "#page-save-status"
    assert_selector "#{status} button", text: "Retry", wait: 20
    assert_eventually(message: "a save and its three retries never ended") { page.evaluate_script("window.__failed") % 4 == 0 }

    # On back, past the header's controls, to Retry.
    stop_on("#{status} button", keys: [ :shift, :tab ])
    assert_equal "Retry", focused_text
    page.execute_script("window.__offline = false")
    page.send_keys(:enter)
    assert_eventually(message: "Retry never saved the subtitle") { page_record.reload.subtitle == "Sent again" }
    assert_no_selector "#{status} button", text: "Retry"
  end

  test "the mail-failed notice's link is a Tab stop, and Enter on it opens Mail settings" do
    with_mail_state(:failed) do
      visit_screen admin_root_path

      find("h1").click
      stop_on("#mail-failed-notice a")
      assert_equal "Open Mail settings →", focused_text
      page.send_keys(:enter)
      assert_current_path(%r{/cs-studio/settings})
      assert_selector "#mail"
    end
  end

  test "a system check's Copy is the Tab stop after its command, and Enter on it copies the command and says so" do
    visit_screen admin_system_status_path
    page.execute_script("window.__copied = null; Object.defineProperty(navigator, 'clipboard', { value: { writeText: (text) => { window.__copied = text; return Promise.resolve() } }, configurable: true })")

    row = find("li.admin-system-check:has(button[aria-label='Copy command for Site address'])")
    row.find("code").click
    page.send_keys(:tab)
    assert_equal "Copy command for Site address", page.evaluate_script("document.activeElement.getAttribute('aria-label')")
    page.send_keys(:enter)
    within(row) { assert_selector "button", text: "Copied" }
    assert_equal Setup::SystemCheck::SITE_ADDRESS_COMMAND, page.evaluate_script("window.__copied")
  end

  private

  def focused_text = page.evaluate_script("document.activeElement.textContent.trim()")

  # Tab (or `keys`, Shift+Tab) until `selector` holds the focus, from
  # wherever Tab starts now, and fail if it is not reached within `limit`
  # stops.
  def stop_on(selector, keys: :tab, limit: 40)
    limit.times do
      page.send_keys(keys)
      return if page.evaluate_script("document.activeElement.matches(#{selector.to_json})")
    end
    flunk "Tab never reached #{selector}"
  end
end
