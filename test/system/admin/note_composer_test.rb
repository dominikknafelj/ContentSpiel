require "application_system_test_case"
require "support/note_files_helper"

# The composer on its own (notes spec §4.2), on the notes page of a record --
# the same frame the drawer shows.
class Admin::NoteComposerSystemTest < ApplicationSystemTestCase
  include NoteFilesHelper # erases what the files test stores

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:two).update!(name: "Dana Example")
    sign_in_via_form(users(:one))
    @page = create_page(title: "Pricing")
  end

  # The list with the field for a new note on the page: what "New note" opens.
  def open_notes
    visit "/cs-studio/notes/page/#{@page.id}?compose=Page-#{@page.id}"
    await_admin_controllers
  end

  def field = find("#notes-new textarea[name=body]")

  test "the picker opens on @, the keyboard picks a person, and Ctrl+Enter sends the note with a mention" do
    open_notes
    field.send_keys("Ask @dan")

    assert_selector "#notes-new [role=listbox] [role=option]", text: "Dana Example"
    field.send_keys(:down, :enter)
    assert_equal "Ask @Dana Example ", field.value

    field.send_keys("first", [ :control, :enter ])

    assert_selector "[data-note-thread] [data-note-mention]", text: "@Dana Example"
    assert_equal [ users(:two).id ], Notes::Message.last.mentioned_user_ids
    open_notes
    assert_equal "", field.value
  end

  test "Enter adds a line and sends nothing; Escape closes the picker and keeps the text" do
    open_notes
    field.send_keys("One", :enter, "Two @da")
    assert_selector "#notes-new [role=listbox] [role=option]"

    field.send_keys(:escape)

    assert_no_selector "#notes-new [role=listbox] [role=option]"
    assert_equal "One\nTwo @da", field.value
    assert_equal 0, Notes::Thread.count
  end

  test "unsent text comes back after leaving the screen, and is gone once sent" do
    open_notes
    field.send_keys("Half a thought")
    visit "/cs-studio"
    open_notes

    assert_equal "Half a thought", field.value

    within("#notes-new") { press "Add note" }
    assert_selector "[data-note-thread]", text: "Half a thought"
    open_notes
    assert_equal "", field.value
  end

  test "an emoji from the popover goes in at the caret" do
    open_notes
    field.send_keys("Good")
    find("#notes-new [data-admin--notes--composer-target=emoji] summary").click
    find("#notes-new button[data-emoji='👍']").click

    assert_equal "Good👍", field.value
  end

  test "two quick presses of Ctrl+Enter, the second a held key, make one note" do
    open_notes
    field.send_keys("Once")
    # Both in one script task: nothing of the first submit has come back yet.
    page.execute_script(<<~JS)
      const field = document.querySelector("#notes-new textarea[name=body]")
      const press = (repeat) => field.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", ctrlKey: true, repeat, bubbles: true, cancelable: true }))
      press(false); press(false); press(true)
    JS

    assert_selector "[data-note-thread]", text: "Once"
    assert_writes_settled
    assert_equal [ 1, 1 ], [ Notes::Thread.count, Notes::Message.count ]
  end

  test "a draft is stored under the signed-in person's id" do
    open_notes
    field.send_keys("Mine alone")

    key = "cs-note-draft:#{users(:one).id}:new-Page-#{@page.id}-"
    assert_eventually { page.evaluate_script("Object.keys(window.sessionStorage).filter((name) => name.startsWith('cs-note-draft:'))") == [ key ] }

    # Another person on the same tab reads another key: nothing is put back.
    page.execute_script("window.sessionStorage.setItem(arguments[0], JSON.stringify({ body: 'Someone else', names: {} }))", "cs-note-draft:424242:new-Page-#{@page.id}-")
    page.execute_script("window.sessionStorage.removeItem(arguments[0])", key)
    open_notes
    assert_equal "", field.value
  end

  # `sessionStorage` belongs to the tab, not to the session: without this the
  # last person's unsent note text and the names of the files they chose
  # stayed readable in the tab, under their id, until it was closed.
  def draft_keys = page.evaluate_script("Object.keys(window.sessionStorage).filter((name) => name.startsWith('cs-note-draft:'))")

  test "signing out removes every note draft from the tab, and the next person finds none" do
    open_notes
    field.send_keys("Not for the next person")
    assert_eventually { draft_keys == [ "cs-note-draft:#{users(:one).id}:new-Page-#{@page.id}-" ] }

    press "Sign out"
    assert_selector "input[name=email_address]"
    assert_empty draft_keys

    sign_in_via_form(users(:two))
    open_notes
    assert_empty draft_keys
    assert_equal "", field.value
  end

  # A session that ended without the button (it expired, it was ended from
  # another tab): the next page a different person loads here clears what is
  # not theirs, and leaves their own.
  test "a page loaded for another person removes the drafts that are not theirs and keeps their own" do
    open_notes
    field.send_keys("Mine alone")
    own = "cs-note-draft:#{users(:one).id}:new-Page-#{@page.id}-"
    assert_eventually { draft_keys == [ own ] }
    page.execute_script("window.sessionStorage.setItem('cs-note-draft:424242:thread-7', JSON.stringify({ body: 'Someone else', names: {}, files: [ 'secret.pdf' ] }))")
    page.execute_script("window.sessionStorage.setItem('unrelated', 'kept')")

    open_notes

    assert_equal [ own ], draft_keys
    assert_equal "Mine alone", field.value
    assert_equal "kept", page.evaluate_script("window.sessionStorage.getItem('unrelated')")
  ensure
    page.execute_script("try { window.sessionStorage.removeItem('unrelated') } catch (error) {}")
  end

  test "the submit is disabled while the field is empty" do
    open_notes
    assert_selector "#notes-new button[type=submit][disabled]", text: "Add note"

    field.send_keys("x")
    assert_selector "#notes-new button[type=submit]:not([disabled])", text: "Add note"

    field.send_keys(:backspace)
    assert_selector "#notes-new button[type=submit][disabled]", text: "Add note"
  end

  # The message's "⋯" menu asks the server for the thread with that message's
  # form or question in place (`Admin::NotesScreen::MessageComponent`).
  test "a note is edited from its menu, with its mention kept, and deleted after the question" do
    thread = Notes::Start.call(@page, body: "Ask @[#{users(:two).id}] first", actor: users(:one)).record
    reply = Notes::Reply.call(thread, body: "Second thoughts", actor: users(:one)).record
    visit "/cs-studio/notes/page/#{@page.id}/threads/#{thread.id}"
    await_admin_controllers

    within("#note-message-#{thread.first_message.id}") do
      find("button[aria-label='Note actions']").click
      find("[role=menu] a", text: "Edit").click
    end
    edit = find("#note-message-#{thread.first_message.id} textarea[name=body]")
    assert_equal "Ask @Dana Example first", edit.value
    edit.send_keys(", please")
    within("#note-message-#{thread.first_message.id}") { press "Save" }

    assert_selector "#note-message-#{thread.first_message.id} [data-note-mention]", text: "@Dana Example"
    assert_no_selector "#note-message-#{thread.first_message.id} textarea"
    assert_equal "Ask @[#{users(:two).id}] first, please", thread.first_message.reload.body

    within("#note-message-#{reply.id}") do
      find("button[aria-label='Note actions']").click
      find("[role=menu] a", text: "Delete").click
    end
    within("#note-message-#{reply.id} [data-note-delete-question]") { press "Delete" }

    assert_no_selector "#note-message-#{reply.id}"
    assert_selector "#note-message-#{thread.first_message.id}"
    assert_not Notes::Message.exists?(reply.id)
  end

  test "the at-sign button opens the picker like a typed @, on its first row" do
    open_notes
    field.send_keys("Ask")
    find("#notes-new [data-note-toolbar] button[data-action='admin--notes--composer#mention']").click

    assert_equal "Ask @", field.value
    assert_selector "#notes-new [role=listbox] [role=option]", maximum: 6
    assert_selector "#notes-new [role=listbox] [role=option][aria-selected=true]", count: 1
  end

  test "chosen files are listed above the field with their size, one can be removed, and the note is sent with the rest" do
    open_notes
    # `set` on the field itself: `attach_file` called on an element looks for a file field INSIDE it.
    find("#notes-new input[type=file]", visible: :all).set([ file_fixture("tiny.png").to_s, file_fixture("small.gif").to_s ])

    assert_selector "#notes-new [data-admin--notes--composer-target=chosen] li", count: 2
    assert_selector "#notes-new [data-admin--notes--composer-target=chosen] li", text: /tiny\.png\s*PNG · 1 KB/
    # The remove button is an icon; its name is its `aria-label`, which `press` does not read.
    find("#notes-new [data-admin--notes--composer-target=chosen] button[aria-label='Remove small.gif']").click
    assert_selector "#notes-new [data-admin--notes--composer-target=chosen] li", count: 1

    field.send_keys("With a file")
    within("#notes-new") { press "Add note" }

    assert_selector "[data-note-thread] [data-note-files] img[alt='tiny.png']"
    assert_equal [ "tiny.png" ], Notes::Message.last.files.map { |file| file.filename.to_s }
  end
end
