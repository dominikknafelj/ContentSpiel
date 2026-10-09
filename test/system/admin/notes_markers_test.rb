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
    assert_selector "#notes-drawer [data-note-thread] h3", text: "RICH TEXT"
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

    assert_selector "#notes-group-ContentBlock-#{@inside.id} h4", text: "IMAGE · COLUMN 1"
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

    assert_selector "dialog[open] [data-admin--notes-target=warning]", text: "It has 2 open notes, which are deleted with it."
    within("dialog[open]") { press "Delete block" }

    assert_no_selector marker(@text)
    assert_no_selector "#notes-open-count"
    assert_equal 0, Notes::Thread.count
  end

  test "a section's delete warning counts the notes on its blocks, and a block without notes is deleted without one" do
    as(users(:two)) { Notes::Start.call(@inside, body: "Wrong picture") }
    open_editor

    assert_selector "#delete-section-#{@section.id} [data-admin--notes-target=warning]", visible: :all, text: "It has 1 open note, which is deleted with it."
    assert_selector "#delete-block-#{@text.id} [data-admin--notes-target=warning]", visible: :all, text: ""
  end

  test "a card drawn again by a stream gets its count back" do
    as(users(:two)) { Notes::Start.call(@text, body: "A note") }
    open_editor
    assert_selector "#{marker(@text)} [data-notes-count]", text: "1"

    within("##{ActionView::RecordIdentifier.dom_id(@text)}") do
      find("button[aria-label='Block actions']").click
      press "Duplicate"
    end

    assert_selector ".admin-block-card [data-admin--notes-target=marker]:not([data-has-notes])", visible: :all, minimum: 1 # the copy: no notes
    assert_selector "#{marker(@text)}[data-has-notes] [data-notes-count]", text: "1"
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

  # A tile is moved along its lane in the page, and drawn again by the answer
  # when it leaves the section (`move_streams`): either way its marker reads
  # the count again from the counts the page already holds.
  test "a tile moved within its section and then out of it keeps its count" do
    below = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1)
    as(users(:two)) { Notes::Start.call(@inside, body: "Wrong picture") }
    open_editor
    assert_selector "#{marker(@inside)}[data-has-notes] [data-notes-count]", text: "1"

    within(card(@inside)) do
      find("button[aria-label='Block actions']").click
      press "Move down"
    end
    assert_writes_settled
    assert_equal [ below.id, @inside.id ], @section.section_blocks.reorder(:position).ids
    assert_selector "#{marker(@inside)}[data-has-notes] [data-notes-count]", text: "1"
    assert_selector "#{marker(below)}:not([data-has-notes])", visible: :all

    within(card(@inside)) do
      find("button[aria-label='Block actions']").click
      press "Move out of section"
    end
    assert_selector "#{card(@inside)}.admin-block-card"
    assert_writes_settled
    assert_selector "#{marker(@inside)}[data-has-notes][aria-label='1 open note on Image'] [data-notes-count]", text: "1"
    assert_selector "#notes-open-count", text: "1"
  end

  test "Add note in a tile's menu starts a note on that block, named with its column" do
    open_editor

    within(card(@inside)) do
      find("button[aria-label='Block actions']").click
      press "Add note"
    end

    assert_selector "#notes-drawer #notes-new h3", text: "NEW NOTE ON IMAGE · COLUMN 1"
    find("#notes-new textarea[name=body]").send_keys("Wrong picture")
    within("#notes-new") { press "Add note" }

    assert_selector "#{marker(@inside)}[data-has-notes] [data-notes-count]", text: "1"
    assert_equal @inside, Notes::Thread.last.subject
  end
end
