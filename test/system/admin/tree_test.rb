require "application_system_test_case"

# The page tree's own drag-to-move (cs-studio spec §4.2/§9): dropping a node
# under a different parent PATCHes `Admin::TreeController#update` and
# re-renders the whole tree from the database.
class Admin::TreeSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @alpha = create_page(title: "Alpha")
    @beta = create_page(title: "Beta")
  end

  test "dragging a page onto another node reparents it and persists" do
    visit "/cs-studio/pages"
    await_admin_controllers

    assert_selector "li[data-page-id='#{@alpha.id}']"
    assert_selector "ul[data-parent-id='#{@beta.id}']"

    # `admin--tree` drives SortableJS the same way `admin--blocks` does (see
    # that test's own comment for why): native HTML5 drag-and-drop, which
    # a driver's synthesized mouse events can't reliably trigger in
    # headless Chrome. Moving Alpha's `<li>` into Beta's own children `<ul>`
    # and then calling the Stimulus controller's own `onDrop` directly --
    # with the same `{item, to, newIndex}` shape SortableJS's `onEnd` hands
    # it -- exercises the exact production path (the hand-built `fetch`
    # PATCH to `Admin::TreeController#update`, applied via
    # `Turbo.renderStreamMessage`) a real drop ends in.
    page.execute_script(<<~JS)
      const item = document.querySelector('li[data-page-id="#{@alpha.id}"]')
      const targetList = document.querySelector('ul[data-parent-id="#{@beta.id}"]')
      targetList.appendChild(item)

      const frame = document.getElementById("tree")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(frame, "admin--tree")
      controller.onDrop({ item: item, to: targetList, newIndex: targetList.children.length - 1 })
    JS

    # The script above already moved Alpha's `<li>` under Beta's by hand
    # (that's what a drop does before `onDrop` runs), so the selector below
    # is satisfied at once and can't be what waits for the PATCH. Waiting
    # on the database is: polling until the move has persisted, or the
    # deadline passes. Asserting straight after the selector raced the
    # PATCH and failed intermittently on slower CI runners.
    assert_selector "ul[data-parent-id='#{@beta.id}'] li[data-page-id='#{@alpha.id}']"
    deadline = Capybara.default_max_wait_time.seconds.from_now + 8.seconds
    sleep 0.05 until @alpha.reload.parent == @beta || Time.current > deadline
    assert_equal @beta, @alpha.reload.parent
  end

  # Final fix wave 1 (reviews A I1 / B I1): moving the page that is open in
  # the editor moves its `updated_at`, which its settings form holds as its
  # autosave base. The move used to go around the save queue and tell the form
  # nothing: the next edit was refused as "Changed elsewhere" -- against the
  # editor's own move -- and the form was dead until Reload. Now the move takes
  # its turn in the queue (never on the wire together with an autosave), sends
  # the form's base, and writes the new one back. The toast's Undo is the same
  # request and has to do the same.
  test "moving the page that is open, and undoing it, leaves its editor able to save" do
    visit "/cs-studio/pages/#{@alpha.id}"
    await_admin_controllers
    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.__inFlight = 0
      window.__maxInFlight = 0
      window.fetch = async (url, options = {}) => {
        const write = (options.method || "GET").toUpperCase() !== "GET"
        if (write) { window.__inFlight += 1; window.__maxInFlight = Math.max(window.__maxInFlight, window.__inFlight) }
        try {
          if (write) await new Promise((resolve) => setTimeout(resolve, 400))
          return await originalFetch(url, options)
        } finally { if (write) window.__inFlight -= 1 }
      }
    JS

    # An autosave is on the wire as the page is dropped under Beta.
    fill_in "Subtitle", with: "Typed before the move"
    page.execute_script(<<~JS)
      document.activeElement.blur()
      const item = document.querySelector('li[data-page-id="#{@alpha.id}"]')
      const targetList = document.querySelector('ul[data-parent-id="#{@beta.id}"]')
      targetList.appendChild(item)
      const controller = window.Stimulus.getControllerForElementAndIdentifier(document.getElementById("tree"), "admin--tree")
      controller.onDrop({ item: item, to: targetList, newIndex: targetList.children.length - 1 })
    JS
    assert_eventually(wait: 10) { @alpha.reload.parent_id == @beta.id }
    assert_selector "#toasts button", text: "Undo"

    fill_in "Subtitle", with: "Typed after my own move"
    page.execute_script("document.activeElement.blur()")
    assert_eventually { @alpha.reload.subtitle == "Typed after my own move" }
    assert_no_text "CHANGED ELSEWHERE"

    parent_before = Page.find(@beta.id).parent_id
    within("#toasts") { press "Undo" }
    assert_eventually(wait: 10) { @alpha.reload.parent_id == parent_before }
    assert_selector "#toasts", text: "Move undone."

    fill_in "Subtitle", with: "Typed after the Undo"
    page.execute_script("document.activeElement.blur()")
    assert_eventually { @alpha.reload.subtitle == "Typed after the Undo" }
    assert_no_text "CHANGED ELSEWHERE"
    assert_no_selector "#changed-elsewhere"
    assert_equal 1, page.evaluate_script("window.__maxInFlight"), "two writes were on the wire at once"
  end

  # Moving another page than the open one sends no base: the open form keeps
  # its own, and keeps saving.
  test "moving another page than the open one leaves the open editor able to save" do
    visit "/cs-studio/pages/#{@beta.id}"
    await_admin_controllers
    base = page.evaluate_script("document.getElementById('page-base-updated-at').value")

    page.execute_script(<<~JS)
      const item = document.querySelector('li[data-page-id="#{@alpha.id}"]')
      const targetList = document.querySelector('ul[data-parent-id="#{@beta.id}"]')
      targetList.appendChild(item)
      const controller = window.Stimulus.getControllerForElementAndIdentifier(document.getElementById("tree"), "admin--tree")
      controller.onDrop({ item: item, to: targetList, newIndex: 0 })
    JS
    assert_eventually(wait: 10) { @alpha.reload.parent_id == @beta.id }
    assert_selector "#toasts button", text: "Undo"
    assert_equal base, page.evaluate_script("document.getElementById('page-base-updated-at').value")

    fill_in "Subtitle", with: "Still saving"
    page.execute_script("document.activeElement.blur()")
    assert_eventually { @beta.reload.subtitle == "Still saving" }
    assert_no_text "CHANGED ELSEWHERE"
  end
end
