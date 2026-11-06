require "application_system_test_case"

class Admin::SectionsRemovingSystemTest < Admin::SectionsSystemTestCase
  test "Remove section, keep blocks turns the tiles into cards in reading order" do
    open_editor
    find("##{ActionView::RecordIdentifier.dom_id(@section)} button[aria-label='Section actions']").click
    press "Remove section, keep blocks"

    assert_no_selector ".admin-section-card"
    assert_equal [ @left.id, @right.id ], page.all("#content-blocks-list > .admin-block-card").map { |card| card["data-block-id"].to_i }
    assert_empty @page.content_blocks.where(block_type: "section")
  end

  # The cards that take the section's place are cards like any other: each
  # autosaves on its own base, and the list's first and last are told so.
  test "a block kept from a removed section is edited as a card, and the list's ends are marked" do
    open_editor
    find("#{section_card} button[aria-label='Section actions']").click
    press "Remove section, keep blocks"
    assert_selector "#content-blocks-list > .admin-block-card", count: 2

    fill_in id: caption(@right), with: "Typed in the card"
    page.execute_script("document.activeElement.blur()")

    assert_selector "#block-#{@right.id}-save-status", text: "SAVED"
    assert_no_text "CHANGED ELSEWHERE"
    assert_equal "Typed in the card", @right.reload.caption
    assert_selector "#{tile(@left)} button[data-move='up'][disabled]", visible: :all
    assert_selector "#{tile(@right)} button[data-move='down'][disabled]", visible: :all
    assert_selector "#{tile(@left)} button[data-move='down']:not([disabled])", visible: :all
  end

  # "Remove section, keep blocks" is the one action of a section that replaces
  # the forms of blocks that STAY: its answer draws a card for each in the
  # section's place. So it runs only on a settled screen (`admin--saving--queue-hold`
  # on its form): a form paused by a 409 holds text that is nowhere else, and
  # the bar over it has promised that it is still there.
  test "Remove section, keep blocks does not run while a form holds text that was refused, and says so" do
    open_editor
    find(face(@left)).click
    travel 1.minute do
      as_unheard(users(:two)) { ContentBlocks::Save.call(@left, translations: { "en" => { caption: "Theirs" } }) }
    end
    fill_in id: caption(@left), with: "Mine, refused"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{@left.id}-save-status", text: "CHANGED ELSEWHERE", wait: 8
    count_writes

    find("#{section_card} button[aria-label='Section actions']").click
    press "Remove section, keep blocks"

    assert_selector "#toasts #toast-queue-hold[role=alert]", text: "Your last change wasn't saved, so this didn't run."
    assert_selector section_card
    assert_equal [ @left.id ], tiles_in(1)
    assert_field caption(@left), with: "Mine, refused"
    assert_selector "#block-#{@left.id}-save-status", text: "CHANGED ELSEWHERE"
    assert_equal @section.id, @left.reload.section_id
    assert_equal "Theirs", @left.caption
    await_frames # a delete sent after all would have called fetch by now: the toast is shown after the drain that would have sent it
    assert_equal [], page.evaluate_script("window.__writes"), "the section's removal was sent"
  end

  # The other half: nothing is unclean, but a save of a form in the section is
  # on the wire and more was typed behind it. The removal waits for the queue
  # to be EMPTY, not for its turn in it -- in its turn it would go before that
  # save's follow-up, and its answer would take the form with the words.
  test "Remove section, keep blocks waits for an edit typed while the block's save was on the wire" do
    open_editor
    find(face(@left)).click
    script_writes("hold")
    fill_in id: caption(@left), with: "First, on the wire"
    page.execute_script("document.activeElement.blur()")
    await_js "typeof window.__release[0] === 'function'"
    page.execute_script(<<~JS)
      const field = document.getElementById(#{caption(@left).to_json})
      field.value = "Second, typed behind it"
      field.dispatchEvent(new Event("input", { bubbles: true }))
    JS

    find("#{section_card} button[aria-label='Section actions']").click
    press "Remove section, keep blocks"
    page.execute_script("window.__release[0]()")

    assert_no_selector ".admin-section-card"
    assert_writes_settled
    assert_equal [ @left.id, @right.id ], cards_in_list
    assert_equal "Second, typed behind it", @left.reload.caption
    assert_field caption(@left), with: "Second, typed behind it"
    assert_nil @left.section_id
    assert_empty @page.content_blocks.where(block_type: "section")
    writes = page.evaluate_script("window.__writes")
    assert_equal 3, writes.size, "the two saves and the removal"
    assert writes.last.end_with?("/content_blocks/#{@section.id}"), "the removal went before the save it had to wait for: #{writes.inspect}"
    assert_no_selector "#toasts #toast-queue-hold"
  end

  test "Delete section and its blocks asks first, naming how many blocks go with it" do
    open_editor
    find("##{ActionView::RecordIdentifier.dom_id(@section)} button[aria-label='Section actions']").click
    press "Delete section and its blocks…"

    assert_selector "dialog[open]", text: "This also deletes the 2 blocks in it."
    within("dialog[open]") { press "Delete section" }

    assert_no_selector ".admin-section-card"
    assert_empty @page.content_blocks.reload
  end

  test "Cancel in the delete dialog deletes nothing, and the dialog counts the blocks as they are after one was deleted" do
    gone = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1)
    gone.update_column(:block_type, "gone/thing")
    open_editor
    find(face(gone)).click
    within(panel(gone)) { press "Delete block…" }
    within("dialog[open]") { press "Delete block" }
    assert_no_selector tile(gone)

    find("#{section_card} button[aria-label='Section actions']").click
    press "Delete section and its blocks…"

    assert_selector "dialog[open]", text: "This also deletes the 2 blocks in it."
    within("dialog[open]") { press "Cancel" }
    assert_no_selector "dialog[open]"
    assert_selector ".admin-section-card"
    assert_equal 3, @page.content_blocks.reload.size
  end

  test "the section's menu moves it among the cards and duplicates it with its blocks" do
    above = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @section.update_column(:position, 1)
    open_editor
    assert_equal [ above.id, @section.id ], page.all("#content-blocks-list > .admin-block-card").map { |card| card["data-block-id"].to_i }

    find("#{section_card} button[aria-label='Section actions']").click
    press "Move up"

    assert_selector "#content-blocks-status", text: "SAVED"
    assert_equal [ @section.id, above.id ], @page.content_blocks.top_level.reorder(:position).ids

    find("#{section_card} button[aria-label='Section actions']").click
    press "Duplicate"

    assert_selector ".admin-section-card", count: 2
    copy = @page.content_blocks.top_level.reorder(:position).second
    assert copy.container?
    assert_selector "##{ActionView::RecordIdentifier.dom_id(copy)} .admin-block-tile", count: 2
    assert_equal 2, copy.section_blocks.size
  end

  test "the section's name collapses it to one line" do
    open_editor
    find("##{ActionView::RecordIdentifier.dom_id(@section)} button[aria-expanded]", text: "Section").click

    assert_no_selector "#section-#{@section.id}-lanes"
    assert_selector "#section-#{@section.id}-summary", text: "2 blocks"
  end

  # Carried from the lane picker's review. The form of a block another tab
  # folded out of its column is open here; the refused add redraws the lanes,
  # and with them what names a column: that form's heading and the header's
  # count. The form itself is never replaced. And the "+" that was pressed is
  # gone with its lane, so the focus goes to the "+" of the last lane there
  # is -- the column the removed ones were folded into -- not to <body>.
  test "a refused add brings the open form's heading and the count up to date, and the focus goes to the last lane's +" do
    @section.update!(settings: @section.settings.merge("layout" => "four"))
    far = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 4, position: 0)
    open_editor
    find(face(far)).click
    assert_selector panel(far), text: "Image · column 4"
    page.execute_script("document.getElementById(#{"block-#{far.id}-panel".to_json}).dataset.mark = 'kept'")
    as_unheard(users(:two)) { assert ContentBlocks::Save.call(ContentBlock.find(@section.id), attributes: { settings: { "layout" => "two" } }).ok? }

    find("#block-picker-#{@section.id}-4 button[aria-haspopup=menu]").click
    within("#block-picker-#{@section.id}-4") { press "Image" }

    assert_selector "#content-blocks-alert", text: "isn't a column of this section"
    assert_selector "#{panel(far)}[data-mark='kept']", text: "Image · column 2"
    assert_selector "#section-#{@section.id}-summary", text: "3 blocks", exact_text: true
    assert_selector "#{face(far)}[aria-expanded='true']"
    assert_eventually(message: "the focus is not on the last lane's +") { focus_is_on("#block-picker-#{@section.id}-2 button[aria-haspopup=menu]") }
  end

  test "a collapsed section is its one header line, and expands to its lanes again" do
    open_editor
    # Inside the card: the "Add block" row has a "Section" button of its own.
    within(tile(@section)) { press "Section" }

    assert_no_selector "#section-#{@section.id}-lanes"
    assert_selector "#{tile(@section)} > div:first-child", text: /Section\s+2 columns.*2 blocks/m

    within(tile(@section)) { press "Section" }

    assert_selector "#section-#{@section.id}-lane-1 > .admin-block-tile"
  end

  test "a page without sections has its cards, no section card and no section controller" do
    plain = create_page(title: "Plain")
    plain.content_blocks.create!(block_type: "rich_text", position: 0)
    visit_editor(plain)

    assert_selector "#content-blocks-list > .admin-block-card", count: 1
    assert_no_selector ".admin-section-card"
    assert_no_selector "[data-controller~='admin--editor--section']"
  end
end
