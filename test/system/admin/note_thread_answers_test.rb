require "application_system_test_case"

# What the answer to one of the thread's own buttons does to work in progress
# elsewhere in the thread (notes spec §6.3, "what is typed is never replaced").
# A reaction, Pin, "Notify me", Resolve and a sent reply all answer with the
# whole thread view; drawn as it came, that answer would close an edit form
# open on ANOTHER message and lose its text. It is merged instead, the way a
# live refresh is (`admin--notes-live#answered`): each test types into an
# edit, presses something else, and asserts both that the action took effect
# and that the very same field still holds the text.
class Admin::NoteThreadAnswersSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:two).update!(name: "Dana")
    @page = create_page(title: "Pricing")
    @thread = as(users(:one)) { Notes::Start.call(@page, body: "My first") }.record
    @mine = @thread.first_message
    @theirs = as(users(:two)) { Notes::Reply.call(@thread, body: "Dana's answer") }.record
    as(users(:one)) { Notes::MarkRead.call(thread: @thread) }
    sign_in_via_form(users(:one))
  end

  teardown { page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}") }

  def focused?(selector) = page.evaluate_script("document.activeElement === document.querySelector(#{selector.to_json})")

  def open_in_drawer
    visit "/cs-studio/pages/#{@page.id}?notes=open&thread=#{@thread.id}"
    await_notes_live
    assert_selector "#notes-drawer [data-notes-view=thread]"
    assert_eventually(message: "the thread never took the focus") { focused?("#note-thread-#{@thread.id}") }
  end

  def edit_field(note = @mine) = "#note-message-#{note.id} form[data-note-composer='message-#{note.id}'] textarea[name=body]"

  # Opens the edit form of the viewer's own first message, types into it and
  # keeps the element, to be asked about afterwards.
  def start_editing(note = @mine)
    within("#note-message-#{note.id}") do
      find("button[aria-label='Note actions']").click
      press "Edit"
    end
    find(edit_field(note)).send_keys(", changed")
    page.execute_script("window.__edit = document.querySelector(#{edit_field(note).to_json})")
  end

  def assert_edit_kept(note = @mine)
    assert page.evaluate_script("window.__edit.isConnected && window.__edit === document.querySelector(#{edit_field(note).to_json})"), "the edit form was drawn again"
    assert_equal "My first, changed", find(edit_field(note)).value
  end

  def reply_field = find("#note-thread-#{@thread.id}-reply textarea[name=body]")

  def react_from_menu(note, name)
    within("#note-message-#{note.id}") do
      find("button[aria-label='Note actions']").click
      press "React"
      find("button[aria-label='React with #{name}']").click
    end
  end

  # Holds this tab's next POST whose address contains `part` until `release`:
  # the time between a press and its answer, made as long as a test needs.
  def hold_request(part)
    page.execute_script(<<~JS)
      window.__held = false
      const original = window.fetch
      window.fetch = (...args) => {
        const url = String(args[0].url || args[0])
        const method = String(args[1]?.method || args[0].method || "GET").toUpperCase()
        if (method === "GET" || !url.includes(#{part.to_json}) || window.__held) return original(...args)
        window.__held = true
        return new Promise((resolve) => { window.__release = () => resolve(original(...args)) })
      }
    JS
  end

  def release = page.execute_script("window.__release()")

  # What Turbo's hover prefetch of a link does, as far as anything listening
  # can tell: `turbo:before-fetch-request` with the LINK as its target, a GET,
  # and (when `marked`) the header Turbo sends with a prefetch.
  def prefetch(selector, marked:)
    page.execute_script(<<~JS)
      const link = document.querySelector(#{selector.to_json})
      const headers = #{marked ? '{ "X-Sec-Purpose": "prefetch" }' : "{}"}
      link.dispatchEvent(new CustomEvent("turbo:before-fetch-request", { bubbles: true, cancelable: true,
        detail: { url: new URL(link.href), fetchOptions: { method: "GET", headers }, resume: () => {} } }))
    JS
  end

  # Prefetch is on in CS Studio: a pointer resting on a link fetches it. That
  # request is not the frame's navigation, and must not make the answer that
  # is on its way be drawn over the thread.
  test "a link prefetched while Pin's answer is on its way does not cost the open edit its text" do
    open_in_drawer
    start_editing
    hold_request("/pin")

    find("[data-note-actions] button[aria-label='Pin']").click
    assert_eventually(message: "the pin request was never sent") { page.evaluate_script("window.__held === true && typeof window.__release === 'function'") }
    prefetch("#notes-drawer a[data-note-back]", marked: true)
    prefetch("#note-message-#{@theirs.id} a[data-note-delete]", marked: false)
    release

    assert_selector "[data-note-badge=pinned]"
    assert_predicate @thread.reload, :pinned
    assert_edit_kept
  end

  test "no link in the thread view is prefetched" do
    open_in_drawer

    assert_no_selector "#notes-drawer turbo-frame#notes a[data-turbo-frame=notes]:not([data-turbo-prefetch=false])", visible: :all
    find("#notes-drawer a[data-note-back]").click
    assert_selector "#notes-drawer #notes-list"
    assert_no_selector "#notes-drawer turbo-frame#notes a[data-turbo-frame=notes]:not([data-turbo-prefetch=false])", visible: :all
  end

  test "the focus is not taken out of a field the person moved into while the answer was on its way" do
    open_in_drawer
    start_editing
    hold_request("/pin")

    find("[data-note-actions] button[aria-label='Pin']").click
    assert_eventually(message: "the pin request was never sent") { page.evaluate_script("window.__held === true && typeof window.__release === 'function'") }
    find(edit_field).click
    release

    assert_selector "[data-note-badge=pinned]"
    assert focused?(edit_field), "the focus was taken out of the edit field"
    assert_edit_kept
  end

  test "a reply sent with the button leaves the focus in the emptied reply field" do
    open_in_drawer
    reply_field.send_keys("A new reply")

    within("#note-thread-#{@thread.id}-reply") { press "Reply" }

    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "A new reply"
    assert_equal "", reply_field.value
    assert_eventually(message: "the focus did not go to the reply field") { focused?("#note-thread-#{@thread.id}-reply textarea[name=body]") }
  end

  # Turbo takes the form's data at the press; the answer then replaces the
  # reply part with the empty one and the draft is forgotten. Anything typed
  # in between was in neither -- for as long as a file's upload takes. So
  # while a note is on its way its field is read-only: the text stays in
  # view, and nothing can be typed that would be thrown away.
  test "while a reply is on its way its field is read-only, so nothing typed after Send can be lost" do
    open_in_drawer
    reply_field.send_keys("First thought")
    hold_request("/messages")

    within("#note-thread-#{@thread.id}-reply") { press "Reply" }
    assert_eventually(message: "the reply was never sent") { page.evaluate_script("window.__held === true && typeof window.__release === 'function'") }

    assert reply_field.readonly?, "the field can be typed in while its note is on the wire"
    reply_field.send_keys(" and one more")
    find("#note-thread-#{@thread.id}-reply [data-admin--note-composer-target=emoji] summary").click
    find("#note-thread-#{@thread.id}-reply button[data-emoji='👍']", visible: :all).click
    assert_equal "First thought", reply_field.value
    release

    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "First thought"
    assert_equal "", reply_field.value
    assert_not reply_field.readonly?
    assert_equal "First thought", @thread.messages.order(:id).last.body
  end

  # The same before the request has left at all: a non-GET is held by the
  # write queue while an autosave is out (`autosave/frame_hold.js`), which is
  # before Turbo says `turbo:submit-start`. The hold is played here by a
  # listener that keeps the request back the way the queue does.
  test "the field is read-only from the press, also while the request is still held back before it is sent" do
    open_in_drawer
    reply_field.send_keys("Held back")
    page.execute_script(<<~JS)
      document.addEventListener("turbo:before-fetch-request", (event) => {
        if (window.__paused || String(event.detail.fetchOptions.method).toUpperCase() === "GET" || !event.detail.url.pathname.includes("/messages")) return
        window.__paused = true
        event.preventDefault()
        window.__resume = event.detail.resume
      })
    JS

    within("#note-thread-#{@thread.id}-reply") { press "Reply" }
    assert_eventually(message: "the reply was never held") { page.evaluate_script("window.__paused === true") }

    assert reply_field.readonly?, "the field can be typed in while its note waits to be sent"
    page.execute_script("window.__resume()")

    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "Held back"
    assert_equal "", reply_field.value
    assert_not reply_field.readonly?
  end

  # A refused note is drawn again with its text, to be put right: editable.
  test "a reply that was refused can be typed in again" do
    open_in_drawer
    reply_field.send_keys("For @[999999]")
    within("#note-thread-#{@thread.id}-reply") { press "Reply" }
    assert_selector "#note-thread-#{@thread.id}-reply [role=alert]", text: "Someone you mentioned can't see this page."

    assert_not reply_field.readonly?
    reply_field.send_keys(" or not")
    assert_equal "For @[999999] or not", reply_field.value
  end

  # The thread went a moment ago and this tab has not been told yet (the
  # signal's half second, a cable that is down): the reply's answer is the
  # list. Its text must not go with the thread.
  test "a reply sent to a thread deleted a moment before is kept: the list says the note is gone and holds the text as a new note" do
    open_in_drawer
    reply_field.send_keys("Too late for this one")
    # Deleted with no signal: what a tab sees that has not heard yet.
    Notes::Thread.find(@thread.id).destroy!

    within("#note-thread-#{@thread.id}-reply") { press "Reply" }

    assert_selector "#notes-drawer #notes-list [role=status]", text: "This note is gone: it was deleted, or what it was on was."
    assert_equal "Too late for this one", find("#notes-new textarea[name=body]").value
    assert_equal 0, Notes::Message.count
    # It is the new note's draft from here on: closing the drawer keeps it.
    key = "cs-note-draft:#{users(:one).id}:new-Page-#{@page.id}-"
    assert_eventually(message: "the kept text is not the new note's draft") { page.evaluate_script("JSON.parse(window.sessionStorage.getItem(#{key.to_json}) || '{}').body") == "Too late for this one" }

    within("#notes-new") { press "Add note" }

    assert_selector "#notes-drawer [data-notes-view=thread] [data-note-message]", text: "Too late for this one"
    assert_equal [ "Too late for this one" ], Notes::Message.pluck(:body)
  ensure
    page.execute_script("try { window.sessionStorage.clear() } catch (error) {}")
  end

  # Resolve stands beside Send, and a refusal of it is said there -- in the
  # composer, which the answer otherwise leaves alone, typed text and all.
  test "a refused Resolve says why in the composer and leaves a half-typed reply as it is; resolved after all, the sentence goes" do
    open_in_drawer
    reply_field.send_keys("Half a reply")
    page.execute_script("window.__reply = document.querySelector('#note-thread-#{@thread.id}-reply textarea[name=body]')")
    refusal = ApplicationService::Result.failure(nil, [ "This note is gone: it was deleted, or what it was on was." ])
    original = Notes::Resolve.method(:call)
    Notes::Resolve.define_singleton_method(:call) { |*, **| refusal }

    within("#note-thread-#{@thread.id}-reply") { press "Resolve" }

    assert_selector "#note-thread-#{@thread.id}-reply form[data-note-composer] ul[role=alert]", text: "This note is gone: it was deleted, or what it was on was."
    assert_no_selector "#note-thread-#{@thread.id}-messages [role=alert]"
    assert page.evaluate_script("window.__reply.isConnected && window.__reply.value === 'Half a reply'"), "the reply field was drawn again"

    Notes::Resolve.define_singleton_method(:call, original)
    within("#note-thread-#{@thread.id}-reply") { press "Resolve" }

    assert_selector "#note-thread-#{@thread.id}[data-state=resolved]"
    assert_no_selector "#note-thread-#{@thread.id}-reply form[data-note-composer] ul[role=alert]"
    assert page.evaluate_script("window.__reply.isConnected && window.__reply.value === 'Half a reply'"), "the reply field was drawn again"
  ensure
    Notes::Resolve.define_singleton_method(:call, original) if original
  end

  test "a reaction on another message leaves an open edit and a half-typed reply as they are" do
    open_in_drawer
    start_editing
    reply_field.send_keys("Half a reply")
    page.execute_script("window.__reply = document.querySelector('#note-thread-#{@thread.id}-reply textarea[name=body]')")

    react_from_menu(@theirs, "thumbs up")

    assert_selector "#note-message-#{@theirs.id} button[data-reaction='👍'][data-mine]"
    assert_edit_kept
    assert page.evaluate_script("window.__reply.isConnected && window.__reply.value === 'Half a reply'"), "the reply field was drawn again"
    assert_no_selector "[data-note-new-divider]"
  end

  test "Pin leaves an open edit as it is, and the thread says it is pinned" do
    open_in_drawer
    start_editing

    find("[data-note-actions] button[aria-label='Pin']").click

    assert_selector "[data-note-badge=pinned]"
    assert_selector "[data-note-actions] button[aria-label='Unpin']"
    assert_predicate @thread.reload, :pinned
    assert_edit_kept

    find("[data-note-actions] button[aria-label='Unpin']").click
    assert_no_selector "[data-note-badge=pinned]"
    assert_edit_kept
  end

  test "Stop notifying me leaves an open edit as it is, and the link says what it now does" do
    open_in_drawer
    start_editing

    within("[data-note-actions]") { press "Stop notifying me" }

    assert_selector "[data-note-actions] button", text: "Notify me"
    assert_equal false, Notes::Follow.find_by(thread: @thread, user: users(:one)).following
    assert_edit_kept
  end

  test "Resolve and Reopen leave an open edit on an earlier message as it is" do
    open_in_drawer
    start_editing

    within("#note-thread-#{@thread.id}-reply") { press "Resolve" }

    assert_selector "#note-thread-#{@thread.id}[data-state=resolved] [data-note-badge=resolved]"
    assert_selector "#note-thread-#{@thread.id}-reply button[data-note-state=reopen]"
    assert_predicate @thread.reload, :resolved?
    assert_edit_kept

    within("#note-thread-#{@thread.id}-reply") { press "Reopen" }
    assert_selector "#note-thread-#{@thread.id}[data-state=open] button[data-note-state=resolve]"
    assert_edit_kept
  end

  test "a reply sent while an edit is open above is added, its field is emptied, and the edit is kept" do
    open_in_drawer
    start_editing
    reply_field.send_keys("A new reply")

    within("#note-thread-#{@thread.id}-reply") { press "Reply" }

    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "A new reply"
    assert_no_selector "[data-note-new-divider]"
    assert_edit_kept
    assert_equal "", reply_field.value
    # The draft went with the send: the field is empty when the thread is opened again.
    open_in_drawer
    assert_equal "", reply_field.value
    assert_equal 1, Notes::Message.where(body: "A new reply").count
  end

  test "a reply that is refused says why in its own field, with the text, and the edit above is kept" do
    open_in_drawer
    start_editing
    reply_field.send_keys("For @[999999]")

    within("#note-thread-#{@thread.id}-reply") { press "Reply" }

    assert_selector "#note-thread-#{@thread.id}-reply [role=alert]", text: "Someone you mentioned can't see this page."
    assert_equal "For @[999999]", reply_field.value
    assert_edit_kept
  end

  test "an edit that is refused shows why in its own form with the text; saved, the form gives way to the new text" do
    open_in_drawer
    start_editing
    find(edit_field).send_keys(" for @[999999]")

    within("#note-message-#{@mine.id}") { press "Save" }

    assert_selector "#note-message-#{@mine.id} form[data-note-composer] [role=alert]", text: "Someone you mentioned can't see this page."
    assert_equal "My first, changed for @[999999]", find(edit_field).value

    find(edit_field).set("My first, reworded")
    within("#note-message-#{@mine.id}") { press "Save" }

    assert_no_selector "#note-message-#{@mine.id} form[data-note-composer]"
    assert_selector "#note-message-#{@mine.id}", text: "My first, reworded"
    assert_equal "My first, reworded", @mine.reload.body
  end

  test "on the notes page of a record, outside any drawer, Pin leaves an open edit as it is" do
    visit "/cs-studio/notes/page/#{@page.id}/threads/#{@thread.id}"
    await_admin_controllers
    assert_selector "#note-thread-#{@thread.id}"
    start_editing

    find("[data-note-actions] button[aria-label='Pin']").click

    assert_selector "[data-note-badge=pinned]"
    assert_edit_kept
  end

  test "in the media panel a reaction on another message leaves an open edit as it is" do
    asset = create_media_asset
    @thread = as(users(:one)) { Notes::Start.call(asset, body: "My first") }.record
    @mine = @thread.first_message
    theirs = as(users(:two)) { Notes::Reply.call(@thread, body: "Lighter now") }.record
    visit "/cs-studio/media?selected=#{asset.id}&thread=#{@thread.id}"
    await_notes_live
    assert_selector "#media-notes #note-thread-#{@thread.id}", text: "Lighter now"
    start_editing

    react_from_menu(theirs, "thumbs up")

    assert_selector "#note-message-#{theirs.id} button[data-reaction='👍'][data-mine]"
    assert_edit_kept
  end
end
