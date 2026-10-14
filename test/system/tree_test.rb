require "application_system_test_case"

# The page tree's keyboard drag path and Undo in a real browser (cs-studio
# design pass, Task 11): Space picks a row up, the arrows move it, Space drops
# it through the same request a mouse drop makes, and the "Moved" toast's Undo
# puts it back through the same service.
class TreeSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    Current.set(actor: users(:one)) do
      @alpha = create_page(title: "Alpha")
      @beta = create_page(title: "Beta")
      @gamma = create_page(title: "Gamma")
    end
  end

  def children_titles
    root_page.reload.children.order(:position).map { |page| page.title }
  end

  # A row's drag handle. It stands in the row's gutter and is shown only on
  # hover or focus (`Admin::PagesScreen::TreeNodeComponent`); a test never
  # waits for what only a hover reveals, so it is found whatever it shows.
  def handle(title) = find("button[aria-label='Move #{title}']", visible: :all)

  # The top-level pages in the order the tree shows them, read off their
  # handles (the homepage has none, nor does any row's "+" link).
  def tree_order
    page.all("#tree .admin-tree-node__handle", visible: :all).map { |handle| handle["aria-label"].delete_prefix("Move ") }
  end

  test "Space, ArrowDown, Space moves a page down; Undo puts it back" do
    sign_in_via_form(users(:one))
    visit admin_pages_path
    await_admin_controllers

    handle("Alpha").send_keys(:space)
    assert_selector "[data-admin--pages--tree-target=announcer]", text: /Picked up Alpha. Position 1 of 3/, visible: :all
    handle("Alpha").send_keys(:down)
    assert_selector "[data-admin--pages--tree-target=announcer]", text: /Position 2 of 3/, visible: :all
    handle("Alpha").send_keys(:space)

    assert_selector "#toasts .admin-toast[data-kind=undo]", text: /Moved .Alpha./, wait: 10
    assert_equal %w[Beta Alpha Gamma], children_titles

    visit admin_pages_path
    assert_equal %w[Beta Alpha Gamma], tree_order

    # Undo posts the toast's own button. Make a second move so there is a
    # fresh toast on this page load, then undo it.
    await_admin_controllers
    handle("Gamma").send_keys(:space, :up, :space)
    assert_selector "#toasts .admin-toast[data-kind=undo]", text: /Moved .Gamma./, wait: 10
    assert_equal %w[Beta Gamma Alpha], children_titles

    within("#toasts") { press "Undo" }
    assert_selector "#toasts .admin-toast", text: /Move undone/, wait: 10
    assert_equal %w[Beta Alpha Gamma], children_titles
  end

  # The mouse path. Both Sortables run with `forceFallback` (Firefox can't
  # start a native HTML5 drag from the `<button>` handle), so the drag is
  # ordinary pointer events and a real browser test can drive it -- by hand
  # rather than with `drag_to`, which presses, jumps and releases in one go:
  # SortableJS only notices what is under the pointer on its own 50 ms tick,
  # so the pointer has to travel in steps and rest before the release.
  test "dragging a page by its handle with the mouse moves it, and a clone follows the pointer" do
    sign_in_via_form(users(:one))
    visit admin_pages_path
    await_admin_controllers

    centre = lambda do |label|
      page.evaluate_script(<<~JS, label)
        (() => { const r = document.querySelector(`button[aria-label='${arguments[0]}']`).getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2] })()
      JS
    end
    from_x, from_y = centre.call("Move Alpha")
    _, gamma_y = centre.call("Move Gamma")
    to_y = gamma_y + 8

    mouse = drag_pointer(from_x, from_y, to_y)

    # Mid-drag: the lifted clone hangs off <body>, the dashed slot is in the tree.
    assert_selector "body > .admin-drag-fallback", text: "Alpha"
    assert_selector "#tree li.admin-drag-ghost"
    await_drag_slot "#tree li.admin-drag-ghost", at: :last
    mouse.up

    assert_selector "#toasts .admin-toast[data-kind=undo]", text: /Moved .Alpha./, wait: 10
    assert_no_selector ".admin-drag-fallback"
    assert_equal %w[Beta Gamma Alpha], children_titles
    assert_equal %w[Beta Gamma Alpha], tree_order
  end

  # The handle is nothing at rest (`opacity-0`, which Cuprite counts as not
  # visible) and shows while it has the focus. Reached as a keyboard reaches
  # it -- it is the control before its row's link -- and with the pointer far
  # from the row, so no hover is what shows it; found WITHOUT `visible: :all`.
  test "a row's handle is not shown at rest, and Shift+Tab from the row's link shows it: Space then picks the row up" do
    sign_in_via_form(users(:one))
    visit admin_pages_path
    await_admin_controllers
    page.driver.browser.mouse.move(x: 900, y: 700)
    assert_no_selector "button[aria-label='Move Alpha']"
    assert_selector "button[aria-label='Move Alpha']", visible: :all

    page.execute_script("document.querySelector('#tree a[title=Alpha]').focus()")
    page.driver.browser.keyboard.type([ :shift, :tab ])

    assert_selector "button[aria-label='Move Alpha']"
    assert_equal "Move Alpha", page.evaluate_script("document.activeElement.getAttribute('aria-label')")
    assert_no_selector "button[aria-label='Move Beta']"

    page.driver.browser.keyboard.type(:space)
    assert_selector "[data-admin--pages--tree-target=announcer]", text: /Picked up Alpha/, visible: :all
    assert_selector "button[aria-label='Move Alpha']"
    page.driver.browser.keyboard.type(:escape)
  end

  test "Escape puts a picked page back without saving" do
    sign_in_via_form(users(:one))
    visit admin_pages_path
    await_admin_controllers

    handle("Alpha").send_keys(:space, :down, :escape)
    assert_selector "[data-admin--pages--tree-target=announcer]", text: /Cancelled/, visible: :all
    assert_equal %w[Alpha Beta Gamma], tree_order
    assert_no_selector "#toasts .admin-toast"
    assert_equal %w[Alpha Beta Gamma], children_titles
  end

  test "ArrowRight nests a page under the one above and ArrowLeft moves it out again" do
    sign_in_via_form(users(:one))
    visit admin_pages_path
    await_admin_controllers

    handle("Beta").send_keys(:space, :right, :space)
    assert_selector "#toasts .admin-toast[data-kind=undo]", text: /Moved .Beta./, wait: 10
    assert_equal @alpha, @beta.reload.parent
  end

  test "ArrowLeft moves a nested page out one level, after its old parent" do
    Current.set(actor: users(:one)) { @child = create_page(title: "Child", parent: @alpha) }
    sign_in_via_form(users(:one))
    visit admin_pages_path
    await_admin_controllers

    handle("Child").send_keys(:space, :left, :space)
    assert_selector "#toasts .admin-toast[data-kind=undo]", text: /Moved .Child./, wait: 10
    assert_equal root_page, @child.reload.parent
    assert_equal %w[Alpha Child Beta Gamma], children_titles
  end

  test "a picked page is put back when focus leaves its handle" do
    sign_in_via_form(users(:one))
    visit admin_pages_path
    await_admin_controllers

    handle("Alpha").send_keys(:space, :down)
    assert_selector "[data-admin--pages--tree-target=announcer]", text: /Position 2 of 3/, visible: :all
    handle("Gamma").send_keys(:space)
    assert_selector "[data-admin--pages--tree-target=announcer]", text: /Picked up Gamma/, visible: :all
    assert_equal %w[Alpha Beta Gamma], tree_order
    assert_equal %w[Alpha Beta Gamma], children_titles
  end
end
