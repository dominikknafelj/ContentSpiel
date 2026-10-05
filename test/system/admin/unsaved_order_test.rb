require "application_system_test_case"

# A drop that was not saved must not look saved, and whatever answers a drop
# is rendered only when it is the Turbo Stream the endpoint sends
# (`autosave/order_request.js`): a block reorder (`admin--blocks`) and a page
# tree move (`admin--tree`) both put the dragged thing back where it was and
# raise an error toast when the request fails, is answered by something else,
# or is redirected to sign-in -- whose page used to be appended to the
# document as if it were a stream.
#
# Every path that ends in the request is covered once between the two
# controllers: the keyboard (Space, arrow, Space), the card menu, and the
# mouse.
class Admin::UnsavedOrderSystemTest < ApplicationSystemTestCase
  FAILED = "Couldn't save the new order. Check your connection and try again.".freeze
  SIGNED_OUT = "Signed out — sign in again to keep saving".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    Current.set(actor: users(:one)) do
      @alpha = create_page(title: "Alpha")
      @beta = create_page(title: "Beta")
      @gamma = create_page(title: "Gamma")
      @first = @alpha.content_blocks.create!(block_type: "post_list", position: 0)
      @second = @alpha.content_blocks.create!(block_type: "post_list", position: 1)
      @third = @alpha.content_blocks.create!(block_type: "post_list", position: 2)
    end
    sign_in_via_form(users(:one))
  end

  # --- Block reorder ----------------------------------------------------------

  test "a block reorder that never reaches the server puts the card back and says so" do
    open_editor
    fail_writes_with "Promise.reject(new TypeError('Failed to fetch'))"

    find("#{card(@third)} .admin-block-card__handle").send_keys(:space, :up, :space)

    assert_selector "#toasts .admin-toast[role=alert]", text: FAILED, wait: 10
    assert_order_eventually(block_ids) { blocks_on_screen }
    assert_equal block_ids, @alpha.content_blocks.reload.order(:position).ids
    assert_selector "#{card(@third)} button[data-move='down'][disabled]", visible: :all
    assert_no_selector "#toasts .admin-toast[data-kind=undo]"

    # Dropping again while it still fails replaces the toast, never stacks it.
    find("#{card(@first)} .admin-block-card__handle").send_keys(:space, :down, :space)
    assert_eventually { page.evaluate_script("window.__writes") == 2 }
    assert_order_eventually(block_ids) { blocks_on_screen }
    assert_selector "#toasts .admin-toast", text: FAILED, count: 1
  end

  test "an answer that is no Turbo Stream is not rendered: the card goes back and the toast shows" do
    open_editor
    fail_writes_with "new Response('<h1>Internal error</h1>', { status: 500, headers: { 'Content-Type': 'text/html' } })"

    find("#{card(@first)} button[aria-label='Block actions']").click
    within(card(@first)) { press "Move down" }

    assert_selector "#toasts .admin-toast[role=alert]", text: FAILED, wait: 10
    assert_order_eventually(block_ids) { blocks_on_screen }
    assert_selector "#{card(@first)} button[data-move='up'][disabled]", visible: :all
    assert_no_text "Internal error"
  end

  # The mouse path, by hand (see test/system/content_blocks_drag_test.rb).
  test "a block dragged after the session ended goes back, and the sign-in page is not put into the document" do
    open_editor
    Session.delete_all

    centre = lambda do |selector|
      page.evaluate_script("(() => { const r = document.querySelector(arguments[0]).getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2] })()", selector)
    end
    page.execute_script("document.querySelector(arguments[0]).scrollIntoView({ block: 'center' })", card(@second))
    from_x, from_y = centre.call("#{card(@third)} .admin-block-card__handle")
    _, first_y = centre.call("#{card(@first)} .admin-block-card__handle")
    to_y = first_y - 4
    mouse = page.driver.browser.mouse
    mouse.move(x: from_x, y: from_y)
    mouse.down
    6.times do |step|
      mouse.move(x: from_x, y: from_y + ((to_y - from_y) * (step + 1) / 6.0))
      sleep 0.08
    end
    assert_selector "body > .admin-drag-fallback"
    sleep 0.2
    mouse.up

    assert_selector "#toasts .admin-toast[role=alert]", text: SIGNED_OUT, wait: 10
    assert_order_eventually(block_ids) { blocks_on_screen }
    assert_no_selector "input[type=password]", visible: :all
    assert_no_selector "form[action$='/sign-in']", visible: :all
    assert_selector "header.admin-editor-header", count: 1
    assert_equal block_ids, @alpha.content_blocks.reload.order(:position).ids
  end

  # The endpoint's own refusal IS a stream (the status line, the reason): it
  # is rendered -- and the order it refused is not left on screen either.
  test "a reorder the server refuses shows its reason and puts the card back" do
    open_editor
    # Deleted behind this browser's back: the order it sends names a block
    # the page no longer has.
    @second.destroy!

    find("#{card(@first)} button[aria-label='Block actions']").click
    within(card(@first)) { press "Move down" }

    assert_selector "#content-blocks-status", text: /COULDN.T SAVE/i, wait: 10
    assert_order_eventually(block_ids) { blocks_on_screen }
    assert_no_selector "#toast-order-error"
  end

  # --- Tree move --------------------------------------------------------------

  test "a tree move that never reaches the server puts the page back and says so" do
    open_editor
    fail_writes_with "Promise.reject(new TypeError('Failed to fetch'))"

    find("button[aria-label='Move Alpha']").send_keys(:space, :down, :space)

    assert_selector "#toasts .admin-toast[role=alert]", text: FAILED, wait: 10
    assert_order_eventually(%w[Alpha Beta Gamma]) { tree_order }
    assert_equal %w[Alpha Beta Gamma], children_titles
    assert_no_selector "#tree [data-picked]"
  end

  test "a page nested by keyboard goes back to its own level when the move fails" do
    open_editor
    fail_writes_with "new Response('Bad gateway', { status: 502, headers: { 'Content-Type': 'text/plain' } })"

    find("button[aria-label='Move Beta']").send_keys(:space, :right, :space)

    assert_selector "#toasts .admin-toast[role=alert]", text: FAILED, wait: 10
    assert_order_eventually(%w[Alpha Beta Gamma]) { tree_order }
    assert_no_selector "ul[data-parent-id='#{@alpha.id}'] li[data-page-id='#{@beta.id}']"
    assert_equal root_page.id, @beta.reload.parent_id
  end

  # The mouse path, by hand (see test/system/tree_test.rb).
  test "a page dragged after the session ended goes back, and the sign-in page is not put into the document" do
    open_editor
    Session.delete_all

    centre = lambda do |label|
      page.evaluate_script(<<~JS, label)
        (() => { const r = document.querySelector(`button[aria-label='${arguments[0]}']`).getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2] })()
      JS
    end
    from_x, from_y = centre.call("Move Alpha")
    _, gamma_y = centre.call("Move Gamma")
    to_y = gamma_y + 8
    mouse = page.driver.browser.mouse
    mouse.move(x: from_x, y: from_y)
    mouse.down
    6.times do |step|
      mouse.move(x: from_x, y: from_y + ((to_y - from_y) * (step + 1) / 6.0))
      sleep 0.08
    end
    assert_selector "#tree li.admin-drag-ghost"
    sleep 0.2
    mouse.up

    assert_selector "#toasts .admin-toast[role=alert]", text: SIGNED_OUT, wait: 10
    assert_order_eventually(%w[Alpha Beta Gamma]) { tree_order }
    assert_no_selector "input[type=password]", visible: :all
    assert_no_selector "form[action$='/sign-in']", visible: :all
    assert_selector "#tree", count: 1
    assert_equal %w[Alpha Beta Gamma], children_titles
  end

  private

  def open_editor
    visit admin_page_path(@alpha)
    await_admin_controllers
  end

  # Every write this page sends from now on is answered with `outcome` (a JS
  # expression) instead of going out; `window.__writes` counts them.
  def fail_writes_with(outcome)
    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.__writes = 0
      window.fetch = (url, options = {}) => {
        if ((options.method || "GET").toUpperCase() === "GET") return originalFetch(url, options)
        window.__writes += 1
        return #{outcome}
      }
    JS
  end

  def card(block) = "##{ActionView::RecordIdentifier.dom_id(block)}"

  def block_ids = [ @first.id, @second.id, @third.id ]

  def blocks_on_screen = page.all("#content-blocks-list > [data-block-id]").map { |card| card["data-block-id"].to_i }

  # A card or row goes back where it was only once the refused answer has been
  # judged -- a moment after the toast, and after the request was merely
  # counted -- so the order on screen is waited for, never read once.
  def assert_order_eventually(expected)
    seen = nil
    assert_eventually(message: -> { "the order never read #{expected.inspect} (last seen #{seen.inspect})" }) do
      seen = yield
      seen == expected
    end
  end

  def tree_order
    page.all("#tree .admin-tree-node__handle").map { |handle| handle["aria-label"].delete_prefix("Move ") }
  end

  def children_titles = root_page.reload.children.order(:position).map(&:title)
end
