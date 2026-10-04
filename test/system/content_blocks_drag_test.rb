require "application_system_test_case"

# The block list's keyboard drag path and Undo in a real browser (cs-studio
# design pass, Task 11): Space picks a card up, the arrows move it, Space drops
# it through the request a drag makes, and the toast's Undo restores the order
# (and the list on screen).
class ContentBlocksDragSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    Current.set(actor: users(:one)) do
      @page = create_page(title: "About")
      @first = @page.content_blocks.create!(block_type: "post_list", position: 0)
      @second = @page.content_blocks.create!(block_type: "post_list", position: 1)
      @third = @page.content_blocks.create!(block_type: "post_list", position: 2)
    end
  end

  def card(block) = "##{ActionView::RecordIdentifier.dom_id(block)}"

  def order_on_screen = page.all("#content-blocks-list > [data-block-id]").map { |card| card["data-block-id"].to_i }

  test "Space, ArrowUp, Space moves a block up; Undo restores the order" do
    sign_in_via_form(users(:one))
    visit admin_page_path(@page)
    await_admin_controllers

    handle = "#{card(@second)} .admin-block-card__handle"
    find(handle).send_keys(:space)
    assert_selector "[data-admin--blocks-target=announcer]", text: /Picked up .* Position 2 of 3/, visible: :all
    find(handle).send_keys(:up)
    assert_selector "[data-admin--blocks-target=announcer]", text: /Position 1 of 3/, visible: :all
    find(handle).send_keys(:space)

    assert_selector "#toasts .admin-toast[data-kind=undo]", text: /order changed/i, wait: 10
    assert_equal [ @second, @first, @third ], @page.content_blocks.reload.to_a

    visit admin_page_path(@page)
    assert_equal [ @second.id, @first.id, @third.id ], order_on_screen

    # A fresh toast on this load: move the last one up, then undo it.
    await_admin_controllers
    find("#{card(@third)} .admin-block-card__handle").send_keys(:space, :up, :space)
    assert_selector "#toasts .admin-toast[data-kind=undo]", wait: 10
    assert_equal [ @second, @third, @first ], @page.content_blocks.reload.to_a

    within("#toasts") { press "Undo" }
    assert_selector "#toasts .admin-toast", text: /Order restored/, wait: 10
    assert_equal [ @second, @first, @third ], @page.content_blocks.reload.to_a
    assert_equal [ @second.id, @first.id, @third.id ], order_on_screen
  end

  # The mouse path, driven by hand for the reason test/system/tree_test.rb
  # gives. The clone that follows the pointer is a deep copy of the card and
  # must be a picture only: no controller, target or id of its own
  # (`admin--blocks#makeCloneInert`).
  test "dragging a card by its handle with the mouse reorders, and the clone is inert" do
    sign_in_via_form(users(:one))
    visit admin_page_path(@page)
    await_admin_controllers

    centre = lambda do |selector|
      page.evaluate_script("(() => { const r = document.querySelector(arguments[0]).getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2] })()", selector)
    end
    # The pointer works in viewport coordinates: bring the list into view first.
    page.execute_script("document.querySelector(arguments[0]).scrollIntoView({ block: 'center' })", card(@second))
    from_x, from_y = centre.call("#{card(@third)} .admin-block-card__handle")
    _, first_y = centre.call("#{card(@first)} .admin-block-card__handle")
    to_y = first_y - 4
    assert_operator from_y, :<, page.evaluate_script("window.innerHeight"), "the dragged handle is on screen"
    assert_operator to_y, :>, 0, "and so is where it is going"

    mouse = page.driver.browser.mouse
    mouse.move(x: from_x, y: from_y)
    mouse.down
    6.times do |step|
      mouse.move(x: from_x, y: from_y + ((to_y - from_y) * (step + 1) / 6.0))
      sleep 0.08
    end

    assert_selector "body > .admin-drag-fallback"
    assert_no_selector "body > .admin-drag-fallback[id], body > .admin-drag-fallback [id]", visible: :all
    assert_no_selector "body > .admin-drag-fallback [data-controller], body > .admin-drag-fallback[data-admin--blocks-target]", visible: :all
    assert_selector "#content-blocks-list > [data-block-id]", count: 3
    sleep 0.2
    mouse.up

    assert_selector "#toasts .admin-toast[data-kind=undo]", text: /order changed/i, wait: 10
    assert_no_selector ".admin-drag-fallback"
    assert_equal [ @third, @first, @second ], @page.content_blocks.reload.to_a
    assert_equal [ @third.id, @first.id, @second.id ], order_on_screen
  end

  test "Escape puts a picked block back without saving" do
    sign_in_via_form(users(:one))
    visit admin_page_path(@page)
    await_admin_controllers

    find("#{card(@first)} .admin-block-card__handle").send_keys(:space, :down, :escape)
    assert_selector "[data-admin--blocks-target=announcer]", text: /Cancelled/, visible: :all
    assert_equal [ @first.id, @second.id, @third.id ], order_on_screen
    assert_no_selector "#toasts .admin-toast"
    assert_equal [ @first, @second, @third ], @page.content_blocks.reload.to_a
  end

  test "Move up in the card menu reorders too" do
    sign_in_via_form(users(:one))
    visit admin_page_path(@page)
    await_admin_controllers

    find("#{card(@second)} summary[aria-label='Block actions']").click
    within(card(@second)) { press "Move up" }
    assert_selector "#toasts .admin-toast[data-kind=undo]", wait: 10
    assert_equal [ @second, @first, @third ], @page.content_blocks.reload.to_a
  end
end
