require "application_system_test_case"

class Admin::NotesMarkersSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @page = create_page(title: "Pricing")
    @text = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @section = @page.content_blocks.create!(block_type: "section", position: 1, settings: { "layout" => "two" })
    @inside = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 1, position: 0)
  end

  # "Open" is remembered in this browser, which the tests that follow share.
  teardown { page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}") }

  def open_editor
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
  end

  # The drawer's small headings are drawn in capitals (`uppercase`), and that
  # is the text a browser test reads.
  def marker(block) = "#notes-marker-ContentBlock-#{block.id}"

  # A block's card in the list, or its tile in a section: both have the block's `dom_id`.
  def card(block) = "##{ActionView::RecordIdentifier.dom_id(block)}"

  test "a block without notes shows no marker at rest; Add note in its menu starts one, and then the marker is a pill with the count" do
    open_editor
    assert_selector "#{marker(@text)}:not([data-has-notes])", visible: :all
    assert_equal "0", find(marker(@text), visible: :all).evaluate_script("getComputedStyle(this).opacity")

    within("##{ActionView::RecordIdentifier.dom_id(@text)}") do
      find("button[aria-label='Block actions']").click
      press "Add note"
    end

    assert_selector "#notes-drawer #notes-new h3", text: "NEW NOTE ON RICH TEXT"
    assert_eventually(message: "the new note's field never took the focus") { page.evaluate_script("document.activeElement.name") == "body" }
    find("#notes-new textarea[name=body]").send_keys("Shorter, please")
    within("#notes-new") { press "Add note" }

    assert_selector "#{marker(@text)}[data-has-notes] [data-notes-count]", text: "1"
    assert_selector "#notes-open-count", text: "1"
    assert_selector "#notes-drawer [data-note-thread]", text: "Shorter, please"
    assert_selector "#notes-drawer [data-note-thread] h3 [data-note-subject-type]", text: "RICH TEXT"
    assert_equal "1", find(marker(@text)).evaluate_script("getComputedStyle(this).opacity")
    assert_equal @text, Notes::Thread.last.subject
  end

  test "the marker of a block without notes appears when the keyboard reaches it, and starts a note" do
    open_editor
    page.execute_script("document.querySelector(arguments[0]).focus()", marker(@text))

    assert_eventually(message: "the focused marker stayed invisible") { find(marker(@text), visible: :all).evaluate_script("getComputedStyle(this).opacity") == "1" }
    find(marker(@text), visible: :all).send_keys(:enter)

    assert_selector "#notes-drawer #notes-new h3", text: "NEW NOTE ON RICH TEXT"
  end

  test "a marker with notes opens the drawer at that block's group; a tile in a section has its own" do
    as(users(:two)) { Notes::Start.call(@inside, body: "Wrong picture") }
    open_editor

    assert_selector "#{marker(@inside)}[data-has-notes][aria-label='1 open note on Image']"
    find(marker(@inside)).click

    assert_selector "#notes-group-ContentBlock-#{@inside.id} h4 [data-note-subject-type]", text: "SECTION › COLUMN 1 · IMAGE"
    assert_eventually(message: "the group never took the focus") { page.evaluate_script("document.activeElement.id") == "notes-group-ContentBlock-#{@inside.id}" }
  end

  test "with text selected in a block's rich text, its marker starts a note that quotes it" do
    open_editor
    find("##{ActionView::RecordIdentifier.dom_id(@text)} [contenteditable=true]").send_keys("The plan costs 49 euros a month.")
    assert_writes_settled
    page.execute_script(<<~JS, ActionView::RecordIdentifier.dom_id(@text))
      const paragraph = document.querySelector(`#${arguments[0]} [contenteditable=true] p`)
      const range = document.createRange()
      range.selectNodeContents(paragraph)
      const selection = document.getSelection()
      selection.removeAllRanges()
      selection.addRange(range)
    JS

    assert_selector "#{marker(@text)}[data-has-notes] [data-notes-selection]", text: "Note on selection"
    find(marker(@text)).click

    assert_selector "#notes-new blockquote", text: "The plan costs 49 euros a month."
    find("#notes-new textarea[name=body]").send_keys("Is that still the price?")
    within("#notes-new") { press "Add note" }

    assert_selector "[data-note-thread] blockquote", text: "The plan costs 49 euros a month."
    assert_equal "The plan costs 49 euros a month.", Notes::Thread.last.quote
    assert_writes_settled
    assert_equal 0, Audit::Event.where(action: "access.denied").count
  end

  test "deleting a block with open notes warns first, and the count goes with the block" do
    as(users(:two)) { 2.times { Notes::Start.call(@text, body: "A note") } }
    open_editor
    assert_selector "#notes-open-count", text: "2"

    within("##{ActionView::RecordIdentifier.dom_id(@text)}") do
      find("button[aria-label='Block actions']").click
      press "Delete block…"
    end

    assert_selector "dialog[open] [data-admin--notes-target=warning]", text: "This block has 2 open notes. They will be deleted with it."
    within("dialog[open]") { press "Delete block" }

    assert_no_selector marker(@text)
    assert_no_selector "#notes-open-count"
    assert_equal 0, Notes::Thread.count
  end

  test "a section's delete warning counts the notes on its blocks, and a block without notes is deleted without one" do
    as(users(:two)) { Notes::Start.call(@inside, body: "Wrong picture") }
    open_editor

    # The section's own sentence (the handoff's decision 7), not the block's.
    assert_selector "#delete-section-#{@section.id} [data-admin--notes-target=warning]", visible: :all, text: "This section and its blocks have 1 open note. It will be deleted too."
    assert_selector "#delete-block-#{@inside.id} [data-admin--notes-target=warning]", visible: :all, text: "This block has 1 open note. It will be deleted with it."
    assert_selector "#delete-block-#{@text.id} [data-admin--notes-target=warning]", visible: :all, text: ""
    # An empty warning takes no room in the dialog: the box that holds it alone
    # is not laid out, while the section's, which also holds a sentence, is.
    holder_display = ->(dialog) { page.evaluate_script("getComputedStyle(document.querySelector('##{dialog} [data-admin--notes-target=warning]').parentElement).display") }
    assert_equal "none", holder_display.call("delete-block-#{@text.id}")
    assert_equal "block", holder_display.call("delete-section-#{@section.id}")
    assert_equal "block", holder_display.call("delete-block-#{@inside.id}")
  end

  # The handoff's decision 7. The number is the section's own open notes and
  # its blocks' together.
  test "a section's delete warning adds its own open notes to its blocks', in the plural, and is gone when none is left" do
    second = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 2, position: 0)
    as(users(:two)) do
      Notes::Start.call(@section, body: "Is this band needed?")
      Notes::Start.call(@inside, body: "Wrong picture")
      Notes::Start.call(second, body: "Too long")
    end
    open_editor
    warning = "#delete-section-#{@section.id} [data-admin--notes-target=warning]"

    assert_selector warning, visible: :all, text: "This section and its blocks have 3 open notes. They will be deleted too."

    within(card(@section)) do
      find("button[aria-label='Section actions']").click
      press "Delete section and its blocks…"
    end
    assert_selector "dialog[open] [data-admin--notes-target=warning][data-notes-warning=section]", text: "This section and its blocks have 3 open notes. They will be deleted too."
    within("dialog[open]") { press "Delete section" }

    assert_no_selector card(@section)
    assert_no_selector "#notes-open-count"
    assert_equal 0, Notes::Thread.count
  end

  # Duplicate streams the copy's card in after its source and redraws nothing
  # else: the copy's own marker is filled as it connects (empty: a copy has no
  # notes), and the source keeps its count.
  test "a duplicate's card is drawn with an empty marker of its own, and the source keeps its count" do
    as(users(:two)) { Notes::Start.call(@text, body: "A note") }
    open_editor
    assert_selector "#{marker(@text)}[data-has-notes] [data-notes-count]", text: "1"

    within(card(@text)) do
      find("button[aria-label='Block actions']").click
      press "Duplicate"
    end

    assert_eventually(message: "the copy was never made") { @page.content_blocks.where(block_type: "rich_text").count == 2 }
    copy = @page.content_blocks.where(block_type: "rich_text").where.not(id: @text.id).sole
    assert_selector "#{card(copy)}.admin-block-card #{marker(copy)}[aria-label='Add a note on Rich text']:not([data-has-notes])", visible: :all
    assert_selector "#{marker(@text)}[data-has-notes] [data-notes-count]", text: "1"
    assert_selector "#notes-open-count", text: "1"
  end

  test "the block whose thread is open is marked, and unmarked when the drawer shows the list again" do
    thread = as(users(:two)) { Notes::Start.call(@text, body: "About this block") }.record
    open_editor
    find(marker(@text)).click
    find("#note-row-#{thread.id}").click

    assert_selector "##{ActionView::RecordIdentifier.dom_id(@text)}[data-notes-active]"
    find("#notes-drawer a[data-note-back]").click
    assert_selector "#notes-list"
    assert_no_selector "[data-notes-active]"
  end

  # The drawer's Escape is its own only while the focus is inside it: a
  # dialog opened from a block beside the open drawer closes alone. The block
  # is the tile in the section's first column, whose menu the drawer does not
  # cover.
  test "Escape in a block's delete dialog closes the dialog and leaves the open drawer open" do
    open_editor
    find("#notes-open").click
    assert_selector "#notes-drawer #notes-list"

    within(card(@inside)) do
      find("button[aria-label='Block actions']").click
      press "Delete block…"
    end
    assert_selector "#delete-block-#{@inside.id}[open]"
    assert_eventually(message: "the dialog never took the focus") { page.evaluate_script("document.activeElement.closest('dialog[open]') !== null") }

    page.driver.browser.keyboard.type(:escape)

    assert_no_selector "dialog[open]"
    assert_selector "#notes-drawer #notes-list"
    assert_selector "#notes-open[aria-pressed=true]"
    assert ContentBlock.exists?(@inside.id)
  end

  # What a move redraws. Along its lane a tile is moved in the page, the same
  # element in a new place, and nothing is drawn again. Out of its section it
  # is REPLACED by the answer (`move_streams`: a card where the tile was), and
  # the card's marker is a new element the server drew without a number: it
  # shows the count only because `admin--notes` fills a marker that connects.
  # The old marker is tagged before each move, so "the count is there" is
  # asked of the element that was drawn again and of no other.
  test "a tile with a count that a move replaces by a card shows its count on the new card" do
    below = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1)
    as(users(:two)) { Notes::Start.call(@inside, body: "Wrong picture") }
    open_editor
    assert_selector "#{marker(@inside)}[data-has-notes] [data-notes-count]", text: "1"
    page.execute_script("document.querySelector(arguments[0]).setAttribute('data-test-drawn-before', '')", marker(@inside))

    within(card(@inside)) do
      find("button[aria-label='Block actions']").click
      press "Move down"
    end
    assert_writes_settled
    assert_equal [ below.id, @inside.id ], @section.section_blocks.reorder(:position).ids
    # Moved, not redrawn: the tagged element, still counting.
    assert_selector "#{card(below)} + #{card(@inside)} #{marker(@inside)}[data-test-drawn-before][data-has-notes] [data-notes-count]", text: "1"
    assert_selector "#{marker(below)}:not([data-has-notes])", visible: :all

    within(card(@inside)) do
      find("button[aria-label='Block actions']").click
      press "Move out of section"
    end
    assert_selector "#{card(@inside)}.admin-block-card #{marker(@inside)}:not([data-test-drawn-before])", visible: :all
    assert_no_selector "[data-test-drawn-before]", visible: :all
    assert_selector "#{card(@inside)}.admin-block-card #{marker(@inside)}:not([data-test-drawn-before])[data-has-notes][aria-label='1 open note on Image'] [data-notes-count]", text: "1"
    assert_selector "#notes-open-count", text: "1"
    assert_writes_settled
  end

  # Where the focus goes when the drawer closes (spec §4.1: back to the
  # trigger). "Add note" in a menu is hidden again with its menu, so the
  # focus goes to what stands for it on the block and can be seen: the
  # block's marker when it shows, or else its "⋯" button. Never <body>.
  test "after Add note from a block's menu, closing the drawer gives the focus to that block's marker or menu button" do
    open_editor
    on_block = <<~JS
      (() => {
        const active = document.activeElement
        const block = document.querySelector(arguments[0])
        return block.contains(active) && (active.id === arguments[1] || active.getAttribute("aria-label") === "Block actions")
      })()
    JS
    focus_on_block = -> { page.evaluate_script(on_block, card(@text), marker(@text).delete_prefix("#")) }

    within(card(@text)) do
      find("button[aria-label='Block actions']").click
      press "Add note"
    end
    assert_selector "#notes-drawer #notes-new textarea[name=body]"
    within("#notes-drawer > header") { find("button[aria-label='Close']").click }
    assert_no_selector "#notes-drawer"
    assert_eventually(message: "closing with the button left the focus off the block") { focus_on_block.call }

    within(card(@text)) do
      find("button[aria-label='Block actions']").click
      press "Add note"
    end
    assert_eventually(message: "the new note's field never took the focus") { page.evaluate_script("document.activeElement.name") == "body" }
    find("#notes-new textarea[name=body]").send_keys(:escape)
    assert_no_selector "#notes-drawer"
    assert_eventually(message: "closing with Escape left the focus off the block") { focus_on_block.call }
  end

  # A press on a marker that never became a click (the pointer was dragged
  # off it) must not leave its selection behind to be quoted by the next
  # note on that block.
  test "a selection held by a press that did not become a click is not quoted by a later Add note" do
    open_editor
    find("#{card(@text)} [contenteditable=true]").send_keys("The plan costs 49 euros a month.")
    assert_writes_settled
    page.execute_script(<<~JS, ActionView::RecordIdentifier.dom_id(@text))
      const range = document.createRange()
      range.selectNodeContents(document.querySelector(`#${arguments[0]} [contenteditable=true] p`))
      document.getSelection().removeAllRanges()
      document.getSelection().addRange(range)
    JS
    assert_selector "#{marker(@text)}[data-has-notes] [data-notes-selection]", text: "Note on selection"
    # The press alone, with no click after it, then the selection given up: a
    # script, because a real press on the marker always ends in a click.
    page.execute_script(<<~JS, marker(@text))
      document.querySelector(arguments[0]).dispatchEvent(new MouseEvent("mousedown", { bubbles: true, cancelable: true }))
      document.getSelection().removeAllRanges()
    JS
    assert_selector "#{marker(@text)}:not([data-has-notes])", visible: :all

    within(card(@text)) do
      find("button[aria-label='Block actions']").click
      press "Add note"
    end

    assert_selector "#notes-drawer #notes-new h3", text: "NEW NOTE ON RICH TEXT"
    assert_no_selector "#notes-new blockquote"
  end

  test "Add note in a tile's menu starts a note on that block, named with its column" do
    open_editor

    within(card(@inside)) do
      find("button[aria-label='Block actions']").click
      press "Add note"
    end

    assert_selector "#notes-drawer #notes-new h3", text: "NEW NOTE ON SECTION › COLUMN 1 · IMAGE"
    find("#notes-new textarea[name=body]").send_keys("Wrong picture")
    within("#notes-new") { press "Add note" }

    assert_selector "#{marker(@inside)}[data-has-notes] [data-notes-count]", text: "1"
    assert_equal @inside, Notes::Thread.last.subject
  end
end
