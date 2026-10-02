require "application_system_test_case"

# The page editor's block list (cs-studio spec §5.1/§9): adding a block
# through the picker (a plain form submission, `admin--blocks` itself has no
# hand in it) and drag-reordering existing ones (`admin--blocks#reorder`).
class Admin::BlocksSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @page = create_page(title: "About")
  end

  test "adding a block through the picker shows the card and persists" do
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    # The end-of-list picker (`after_id` absent) is open by default -- no
    # disclosure click needed before its own type buttons are visible.
    # Every button here is a plain `button_to` (`Admin::BlockPickerComponent`'s
    # own comment): Turbo Drive already appends the Turbo Stream `Accept`
    # header to a non-GET form submission on its own, so this is a normal
    # submit, not a fetch this test would otherwise have to wait on by hand.
    press "Rich text"

    assert_selector ".admin-block-card", text: "Rich text"
    assert_equal 1, @page.content_blocks.count
    assert_equal "rich_text", @page.content_blocks.first.block_type

    # Reload the whole editor (a fresh GET, not just trusting the Turbo
    # Stream response) to prove the card is actually persisted, not only
    # reflecting the in-memory DOM this session just built.
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    assert_selector ".admin-block-card", text: "Rich text"
  end

  test "dragging a block's handle reorders the list and persists" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    second = @page.content_blocks.create!(block_type: "post_list", position: 1)
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    assert_selector "#content-blocks-list .admin-block-card:first-child[data-block-id='#{first.id}']"

    # `admin--blocks` drives SortableJS with no `forceFallback` option (see
    # that controller's own source), so a drag here is the browser's native
    # HTML5 drag-and-drop under the hood -- `dragstart`/`dragover`/`drop`
    # events a synthesized mouse sequence (Capybara's `drag_to`) can't
    # reliably trigger in headless Chrome, native DnD being a
    # browser-internal mechanism rather than a sequence of ordinary mouse
    # events. Driving the Stimulus controller's own `reorder()` directly,
    # right after moving the two cards' DOM nodes into the order a real
    # drop would leave them in, exercises the exact same production code
    # (a hand-built `fetch` PATCH, applied via `Turbo.renderStreamMessage`)
    # a drag's own `onEnd` calls -- the brief's own sanctioned fallback for
    # exactly this situation.
    page.execute_script(<<~JS)
      const list = document.getElementById("content-blocks-list")
      const secondCard = list.querySelector('[data-block-id="#{second.id}"]')
      const firstCard = list.querySelector('[data-block-id="#{first.id}"]')
      list.insertBefore(secondCard, firstCard)

      const section = document.querySelector('[data-controller~="admin--blocks"]')
      window.Stimulus.getControllerForElementAndIdentifier(section, "admin--blocks").reorder()
    JS

    # `assert_selector(id, text:, wait:)`, not `within(id) { assert_text }`
    # -- see `test/system/admin/autosave_test.rb`'s own comment for why the
    # two-step form can raise `ElementNotFound` before its own explicit
    # wait gets any say.
    assert_selector "#content-blocks-status", text: "Saved"
    assert_selector "#content-blocks-list .admin-block-card:first-child[data-block-id='#{second.id}']"
    assert_equal [ second, first ], @page.content_blocks.reload.order(:position).to_a
  end
  # Final fix wave I3 / fix round 2: every block write touches the page, so
  # each block request sends the page form's base along and gets it moved
  # forward when it was current -- through Turbo's own submissions (the
  # picker) and a card's autosave alike. Without that, the page form's next
  # save here would read "Changed elsewhere" with nobody else involved.
  test "editing blocks doesn't make the page settings form report a false conflict" do
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    press "Post list"
    assert_selector ".admin-block-card", text: "Post list"
    block = @page.content_blocks.sole

    within("##{ActionView::RecordIdentifier.dom_id(block)}") { find("input[name='block[settings][limit]']").fill_in(with: "4") }
    assert_selector "#block-#{block.id}-save-status", text: /\ASaved \d{2}:\d{2}\z/, wait: 5
    assert_equal 4, block.reload.settings["limit"].to_i

    fill_in "Title", with: "About the Studio"
    assert_selector "#page-save-status", text: /\ASaved \d{2}:\d{2}\z/, wait: 5
    assert_no_text "Changed elsewhere"
    assert_equal "About the Studio", @page.reload.title(locale: :en)
  end
end
