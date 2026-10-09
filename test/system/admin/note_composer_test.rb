require "application_system_test_case"

# The composer on its own (notes spec §4.2), on the notes page of a record --
# the same frame the drawer shows.
class Admin::NoteComposerSystemTest < ApplicationSystemTestCase
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
    find("#notes-new [data-admin--note-composer-target=emoji] summary").click
    find("#notes-new button[data-emoji='👍']").click

    assert_equal "Good👍", field.value
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
    find("#notes-new [data-note-toolbar] button[data-action='admin--note-composer#mention']").click

    assert_equal "Ask @", field.value
    assert_selector "#notes-new [role=listbox] [role=option]", maximum: 6
    assert_selector "#notes-new [role=listbox] [role=option][aria-selected=true]", count: 1
  end
end
