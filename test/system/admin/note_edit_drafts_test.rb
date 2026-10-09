require "application_system_test_case"

# Switching edits (the handoff's decision 27). One edit form at a time; the
# text of an edit that is LEFT without saving -- by Edit or Delete on another
# message, by "All notes", by closing the drawer, by a reload -- is kept as a
# local draft (`cs-note-draft:<user id>:message-<id>` in `sessionStorage`),
# put back when that message's Edit is opened again, and said on the message
# ("Unsaved edit") until the edit is saved or cancelled. The note is the
# script's, read from `sessionStorage` for the messages on screen: the server
# is never asked.
class Admin::NoteEditDraftsSystemTest < ApplicationSystemTestCase
  LIVE = 8

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:two).update!(name: "Dana")
    @page = create_page(title: "Pricing")
    @thread = as(users(:one)) { Notes::Start.call(@page, body: "My first") }.record
    @first = @thread.first_message
    @second = as(users(:one)) { Notes::Reply.call(@thread, body: "My second") }.record
    sign_in_via_form(users(:one))
  end

  teardown do
    page.execute_script("try { window.localStorage.removeItem('cs-notes-open'); window.sessionStorage.clear() } catch (error) {}")
  end

  def focused?(selector) = page.evaluate_script("document.activeElement === document.querySelector(#{selector.to_json})")

  def open_thread
    visit "/cs-studio/pages/#{@page.id}?notes=open&thread=#{@thread.id}"
    await_notes_live
    assert_selector "#notes-drawer [data-notes-view=thread]"
    assert_eventually(message: "the thread never took the focus") { focused?("#note-thread-#{@thread.id}") }
  end

  def menu(note, item)
    within("#note-message-#{note.id}") do
      find("button[aria-label='Note actions']").click
      press item
    end
  end

  def field(note) = "#note-message-#{note.id} form[data-note-composer='message-#{note.id}'] textarea[name=body]"

  def unsaved(note) = "#note-message-#{note.id} [data-note-unsaved]"

  def draft(note) = page.evaluate_script("window.sessionStorage.getItem('cs-note-draft:#{users(:one).id}:message-#{note.id}')")

  def edit_and_type(note = @first)
    menu(note, "Edit")
    find(field(note)).send_keys(", changed")
    assert_no_selector unsaved(note) # nothing was left yet
  end

  test "Edit on another message closes the first edit, which says Unsaved edit; reopened, the typed text is back; Cancel forgets it" do
    open_thread
    edit_and_type

    menu(@second, "Edit")

    assert_selector field(@second)
    assert_no_selector field(@first)
    assert_selector "#note-message-#{@first.id}", text: "My first"
    assert_selector unsaved(@first), text: "Unsaved edit"
    assert_no_selector unsaved(@second)
    assert_equal [ "12px" ], [ page.evaluate_script("getComputedStyle(document.querySelector(#{unsaved(@first).to_json})).fontSize") ]

    menu(@first, "Edit")

    assert_equal "My first, changed", find(field(@first)).value
    # In the message's meta line only while the form holds the restored text
    # (the handoff's decision 29): no line above the field, which is for errors.
    assert_selector unsaved(@first), text: "Unsaved edit", count: 1
    assert_no_selector "#note-message-#{@first.id} form[data-note-composer] [data-note-unsaved]", visible: :all
    assert_selector "#note-message-#{@first.id} [data-admin--note-unsaved-target=note]", text: "Unsaved edit"

    within("#note-message-#{@first.id}") { find("a[data-note-cancel]").click }

    assert_no_selector field(@first)
    assert_selector "#note-message-#{@first.id}", text: "My first"
    assert_no_selector unsaved(@first)
    assert_nil draft(@first)
    menu(@first, "Edit")
    assert_equal "My first", find(field(@first)).value
    assert_no_selector unsaved(@first)
    assert_equal "My first", @first.reload.body
  end

  test "an edit left by All notes, by closing the drawer and by a reload is there when its Edit is opened again" do
    open_thread
    edit_and_type

    find("#notes-drawer a[data-note-back]").click
    assert_selector "#notes-drawer #notes-list"
    find("a#note-row-#{@thread.id}").click
    assert_selector unsaved(@first), text: "Unsaved edit"

    find("#notes-drawer button[data-note-close]").click
    assert_no_selector "#notes-drawer [data-notes-view]"
    find("#notes-open").click
    find("a#note-row-#{@thread.id}").click if page.has_selector?("#notes-drawer #notes-list", wait: 2)
    assert_selector unsaved(@first), text: "Unsaved edit"

    open_thread # a reload
    assert_selector unsaved(@first), text: "Unsaved edit"
    menu(@first, "Edit")
    assert_equal "My first, changed", find(field(@first)).value
  end

  test "Delete on another message closes the edit and keeps its text; the note survives a live refresh and this tab's own buttons" do
    open_thread
    edit_and_type

    menu(@second, "Delete")
    assert_selector "#note-message-#{@second.id} [data-note-delete-question]"
    assert_selector unsaved(@first), text: "Unsaved edit"

    as(users(:two)) { assert Notes::Reply.call(@thread, body: "Meanwhile").ok? }
    assert_selector "[data-note-message]", text: "Meanwhile", wait: LIVE
    assert_selector unsaved(@first), text: "Unsaved edit"

    find("[data-note-actions] button[aria-label='Pin']").click
    assert_selector "[data-note-badge=pinned]"
    assert_selector unsaved(@first), text: "Unsaved edit"
  end

  test "a saved edit leaves no draft and no note; typing the saved text back leaves none either" do
    open_thread
    edit_and_type
    assert_not_nil draft(@first)

    within("#note-message-#{@first.id}") { press "Save" }

    assert_selector "#note-message-#{@first.id}", text: "My first, changed"
    assert_no_selector field(@first)
    assert_no_selector unsaved(@first)
    assert_nil draft(@first)
    assert_equal "My first, changed", @first.reload.body

    menu(@second, "Edit")
    find(field(@second)).send_keys("x", :backspace)
    assert_nil draft(@second)
    menu(@first, "Edit")
    assert_no_selector unsaved(@second)
  end

  # A draft older than the message's last save (the author saved a newer text
  # from another tab): it is the author's own text, so it is restored and said
  # like any other -- never silently, and Cancel gives the newer text back.
  test "a draft older than a newer saved text is restored and said, not hidden; Cancel shows the newer text" do
    open_thread
    edit_and_type
    menu(@second, "Edit")
    assert_selector unsaved(@first)
    as(users(:one)) { assert Notes::EditMessage.call(@first, body: "Saved elsewhere").ok? }

    menu(@first, "Edit")

    assert_equal "My first, changed", find(field(@first)).value
    assert_selector unsaved(@first), text: "Unsaved edit", count: 1
    assert_no_selector "#note-message-#{@first.id} form[data-note-composer] [data-note-unsaved]", visible: :all
    within("#note-message-#{@first.id}") { find("a[data-note-cancel]").click }
    assert_selector "#note-message-#{@first.id}", text: "Saved elsewhere"
    assert_no_selector unsaved(@first)
  end

  # An open edit is MOVED into the thread's new messages part by every live
  # refresh and every merged answer to one of the tab's own buttons, and a
  # moved element's controller connects again. It once took the text typed so
  # far as "what the form was drawn with" there: one more keystroke that left
  # the field as it was then removed the draft, and the edit was left with
  # nothing kept and nothing said. The baseline is the saved text the server
  # drew, whatever happens to the element.
  test "an edit whose thread was refreshed by someone's reply is still an unsaved edit: left, its text is kept and said" do
    open_thread
    edit_and_type

    as(users(:two)) { assert Notes::Reply.call(@thread, body: "Meanwhile").ok? }
    assert_selector "[data-note-message]", text: "Meanwhile", wait: LIVE
    assert_equal "My first, changed", find(field(@first)).value
    find(field(@first)).send_keys("x", :backspace)
    assert_not_nil draft(@first), "the draft was dropped although the field still differs from the saved text"

    menu(@second, "Edit")

    assert_selector field(@second)
    assert_selector unsaved(@first), text: "Unsaved edit"
    assert_not_nil draft(@first)
    menu(@first, "Edit")
    assert_equal "My first, changed", find(field(@first)).value
  end

  test "an edit whose thread was redrawn by this tab's own Pin is still an unsaved edit: left, its text is kept and said" do
    open_thread
    edit_and_type

    find("[data-note-actions] button[aria-label='Pin']").click
    assert_selector "[data-note-badge=pinned]"
    assert_equal "My first, changed", find(field(@first)).value
    find(field(@first)).send_keys("x", :backspace)
    assert_not_nil draft(@first), "the draft was dropped although the field still differs from the saved text"

    menu(@second, "Edit")

    assert_selector field(@second)
    assert_selector unsaved(@first), text: "Unsaved edit"
    menu(@first, "Edit")
    assert_equal "My first, changed", find(field(@first)).value
  end

  # Typing the SAVED text back is still what removes an edit's draft, after a
  # refresh as before one.
  test "after a refresh, typing the saved text back into an edit leaves no draft" do
    open_thread
    menu(@first, "Edit")
    find(field(@first)).send_keys("!")
    assert_not_nil draft(@first)

    as(users(:two)) { assert Notes::Reply.call(@thread, body: "Meanwhile").ok? }
    assert_selector "[data-note-message]", text: "Meanwhile", wait: LIVE
    find(field(@first)).send_keys(:backspace)

    assert_nil draft(@first)
  end
end
