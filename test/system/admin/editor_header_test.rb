require "application_system_test_case"

# The editor header in a real browser (design pass round 2, Task 4): one
# primary action, the ⋯ menu's keyboard behaviour, and publish / unpublish
# refreshing the whole screen (the tree included) because their forms leave
# the content frame.
class EditorHeaderSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    Current.set(actor: users(:one)) { @draft = create_page(title: "Draft idea", published: false) }
  end

  test "publish from the one primary button, then unpublish from the menu" do
    sign_in_via_form(users(:one))
    visit admin_page_path(@draft)
    await_admin_controllers

    header = "header.admin-editor-header"
    assert_selector "#{header} .admin-status-chip[data-status=draft]"
    assert_selector "#{header} button.bg-accent", count: 1
    assert_selector "#{header} button.bg-accent", text: "Publish"

    # The tree shows the draft's chip before publishing.
    assert_selector "li[data-page-id='#{@draft.id}'] .admin-status-chip[data-status=draft]", wait: 5

    # Keyboard: focus the ⋯ button, Enter opens the menu on its first item,
    # ArrowDown reaches "Schedule…" (after Activity), Escape closes it and
    # hands focus back to the button.
    page.execute_script("document.querySelector(\"#{header} button[aria-label='More actions']\").focus()")
    page.driver.browser.keyboard.type(:Enter)
    assert_selector "#{header} [role=menu]"
    assert_equal "Activity", page.evaluate_script("document.activeElement.textContent.trim()")
    page.driver.browser.keyboard.type(:Down)
    assert_equal "Schedule…", page.evaluate_script("document.activeElement.textContent.trim()")
    page.driver.browser.keyboard.type(:Escape)
    assert_no_selector "#{header} [role=menu]"
    assert_equal "More actions", page.evaluate_script("document.activeElement.getAttribute('aria-label')")

    find("#{header} button.bg-accent", text: "Publish").click

    # The publish form targets `_top`: a full visit, so everything re-renders.
    assert_selector "#{header} .admin-status-chip[data-status=live]", wait: 10
    assert_no_selector "#{header} button.bg-accent"
    assert_selector "#{header} [role=status]", text: "This page is live. Changes appear on the site as soon as they’re saved."
    assert_no_selector "li[data-page-id='#{@draft.id}'] .admin-status-chip[data-status=draft]"
    assert @draft.reload.live?

    await_admin_controllers
    open_editor_menu
    press "Unpublish"
    within("dialog#unpublish-page-#{@draft.id}[open]") do
      assert_text "Unpublish this page?"
      press "Unpublish"
    end

    assert_selector "#{header} .admin-status-chip[data-status=draft]", wait: 10
    assert_selector "#{header} button.bg-accent", text: "Publish"
    assert_not @draft.reload.live?
  end

  def set_schedule_value(dialog_id, value)
    page.execute_script(<<~JS)
      const input = document.querySelector("##{dialog_id} input[name=published_at]")
      input.value = "#{value}"
      input.dispatchEvent(new Event("input", { bubbles: true }))
    JS
  end

  test "Schedule… opens the dialog with focus in the date field; a past time reopens it with its message; a future time schedules; Edit schedule offers Remove" do
    sign_in_via_form(users(:one))
    visit admin_page_path(@draft)
    await_admin_controllers
    dialog = "dialog#schedule-page-#{@draft.id}"

    assert_no_selector "#{dialog}[open]"
    open_editor_menu
    press "Schedule…"
    assert_selector "#{dialog}[open]"
    assert_selector "#{dialog}[open] h2", text: "Schedule publishing"
    assert_equal "published_at", page.evaluate_script("document.activeElement.getAttribute('name')")
    assert_no_selector "#{dialog} button", text: "Remove schedule"

    # A past time: the browser must not block the submit (`novalidate`), the
    # server refuses, and the editor comes back with the dialog open.
    set_schedule_value("schedule-page-#{@draft.id}", "2020-01-01T09:00")
    within("#{dialog}[open]") { press "Schedule" }
    assert_selector "#{dialog}[open] [role=alert]", text: "Pick a time in the future.", wait: 10
    assert_no_selector "#toasts .admin-toast"
    assert_nil @draft.reload.published_at

    # Back/forward restores the page from Turbo's cache: the dialog does not reopen.
    within("#{dialog}[open]") { press "Cancel" }
    assert_no_selector "#{dialog}[open]"

    set_schedule_value("schedule-page-#{@draft.id}", (Time.current + 5.days).strftime("%Y-%m-%dT%H:%M"))
    page.execute_script("document.querySelector('#{dialog}').showModal()")
    within("#{dialog}[open]") { press "Schedule" }
    assert_selector "header.admin-editor-header .admin-status-chip[data-status=scheduled]", wait: 10
    assert_no_selector "#{dialog}[open]"
    assert_equal "scheduled", @draft.reload.status

    await_admin_controllers
    find("header.admin-editor-header button", text: "Edit schedule").click
    assert_selector "#{dialog}[open]"
    assert_selector "#{dialog}[open] button", text: "Remove schedule"
    within("#{dialog}[open]") { press "Remove schedule" }
    assert_selector "header.admin-editor-header .admin-status-chip[data-status=draft]", wait: 10
    assert_nil @draft.reload.published_at
  end

  test "a refused schedule's dialog is not reopened when Back restores the page from the cache" do
    sign_in_via_form(users(:one))
    visit admin_page_path(@draft)
    await_admin_controllers
    dialog = "dialog#schedule-page-#{@draft.id}"

    open_editor_menu
    press "Schedule…"
    set_schedule_value("schedule-page-#{@draft.id}", "2020-01-01T09:00")
    within("#{dialog}[open]") { press "Schedule" }
    assert_selector "#{dialog}[open] [role=alert]", wait: 10
    within("#{dialog}[open]") { press "Cancel" }

    visit admin_pages_path
    assert_current_path admin_pages_path
    page.go_back
    assert_selector "header.admin-editor-header", wait: 10
    assert_no_selector "#{dialog}[open]"
  end

  test "the menu skips a disabled item: ArrowDown wraps past the homepage's disabled Move to trash" do
    sign_in_via_form(users(:one))
    visit admin_page_path(root_page)
    await_admin_controllers
    header = "header.admin-editor-header"
    assert_selector "#{header} [role=menu] button[disabled]", text: "Move to trash", visible: :all

    page.execute_script("document.querySelector(\"#{header} button[aria-label='More actions']\").focus()")
    page.driver.browser.keyboard.type(:Enter)
    assert_selector "#{header} [role=menu]"
    enabled = page.evaluate_script("Array.from(document.querySelectorAll(\"#{header} [role=menu] a, #{header} [role=menu] button:not(:disabled)\")).map((e) => e.textContent.trim())")
    assert_operator enabled.size, :>=, 2
    assert_equal enabled.first, page.evaluate_script("document.activeElement.textContent.trim()")

    # Down through every enabled item, then once more: it wraps to the first
    # (it used to stay stuck on the last, whose neighbour is the disabled one).
    (enabled.size - 1).times { page.driver.browser.keyboard.type(:Down) }
    assert_equal enabled.last, page.evaluate_script("document.activeElement.textContent.trim()")
    page.driver.browser.keyboard.type(:Down)
    assert_equal enabled.first, page.evaluate_script("document.activeElement.textContent.trim()")
    page.driver.browser.keyboard.type(:Up)
    assert_equal enabled.last, page.evaluate_script("document.activeElement.textContent.trim()")
  end
end
