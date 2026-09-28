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
    visit "/cs-studio"

    assert_selector "li[data-page-id='#{@alpha.id}']"
    assert_selector "ul[data-parent-id='#{@beta.id}']"

    # `admin--tree` drives SortableJS the same way `admin--blocks` does (see
    # that test's own comment for why): native HTML5 drag-and-drop, which
    # headless Chrome's WebDriver can't reliably synthesize via a mouse
    # action sequence. Moving Alpha's `<li>` into Beta's own children `<ul>`
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

    # The tree's own re-render lands async (the `fetch` above), so this is
    # what actually waits for it -- Capybara polls until Alpha's `<li>`
    # shows up nested under Beta's, or times out.
    assert_selector "ul[data-parent-id='#{@beta.id}'] li[data-page-id='#{@alpha.id}']"
    assert_equal @beta, @alpha.reload.parent
  end
end
