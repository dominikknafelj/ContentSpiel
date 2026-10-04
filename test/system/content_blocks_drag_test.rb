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
