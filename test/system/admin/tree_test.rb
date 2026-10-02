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
end
