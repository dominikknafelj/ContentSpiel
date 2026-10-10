require "application_system_test_case"

# Who can read a page can write notes on it (notes spec D3), and for a viewer
# who can't edit it the way in is the block's "⋯" menu, whose only item is
# "Add note" (the handoff's decision 6). The add-note control beside a
# block's name is at rest for nobody.
class Admin::NotesViewOnlySystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    @text = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @section = @page.content_blocks.create!(block_type: "section", position: 1, settings: { "layout" => "two" })
    @inside = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 1, position: 0)
    sign_in_via_form(users(:reader))
  end

  # "Open" is remembered in this browser, which the tests that follow share.
  teardown { page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}") }

  def card(block) = "##{ActionView::RecordIdentifier.dom_id(block)}"

  def marker(block) = "#notes-marker-ContentBlock-#{block.id}"

  test "a read-only viewer starts a note from a block's menu, whose only item is Add note, and sees it" do
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    assert_selector "[data-view-only-hint]"
    # Nothing at rest: the control beside the name is not shown.
    assert_selector "#{marker(@text)}:not([data-has-notes])", visible: :all
    assert_equal "0", find(marker(@text), visible: :all).evaluate_script("getComputedStyle(this).opacity")

    within(card(@text)) do
      find("button[aria-label='Block actions']").click
      assert_equal [ "Add note" ], all("[role=menu] button").map(&:text)
      press "Add note"
    end

    assert_selector "#notes-drawer #notes-new h3", text: "NEW NOTE ON RICH TEXT"
    find("#notes-new textarea[name=body]").send_keys("Is this the new price?")
    within("#notes-new") { press "Add note" }

    assert_selector "#notes-drawer [data-note-thread]", text: "Is this the new price?"
    assert_selector "#{marker(@text)}[data-has-notes] [data-notes-count]", text: "1"
    assert_selector "#notes-open-count", text: "1"
    thread = Notes::Thread.last
    assert_equal [ @text, users(:reader).id ], [ thread.subject, thread.first_message.author_id ]
    # The page itself was not written.
    assert_no_selector ".admin-toast", text: /saved/i
  end

  test "a read-only viewer's tile in a section has the same menu, and its control is not shown at rest either" do
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    assert_equal "0", find(marker(@inside), visible: :all).evaluate_script("getComputedStyle(this).opacity")

    within(card(@inside)) do
      find("button[aria-label='Block actions']").click
      assert_equal [ "Add note" ], all("[role=menu] button").map(&:text)
      press "Add note"
    end

    assert_selector "#notes-drawer #notes-new textarea[name=body]"
    find("#notes-new textarea[name=body]").send_keys("Wrong picture")
    within("#notes-new") { press "Add note" }
    assert_selector "#{marker(@inside)}[data-has-notes] [data-notes-count]", text: "1"
    assert_equal @inside, Notes::Thread.last.subject
  end
end
