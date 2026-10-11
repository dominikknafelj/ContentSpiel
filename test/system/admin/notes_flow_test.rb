require "application_system_test_case"
require "support/note_files_helper"

# Notes from one person to another and back (notes spec §8, System), and the
# three places the feature must not disturb: the keyboard, the write queue and
# the leave guard. Each part of the screen has its own file beside this one
# (the drawer, the markers, the composer, files, reactions, live delivery);
# here the parts are used one after the other, the way two people use them.
class Admin::NotesFlowSystemTest < ApplicationSystemTestCase
  include NoteFilesHelper

  LIVE = 8
  FORGET_OPEN = "try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:two).update!(name: "Dana")
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
  end

  # "Open" is remembered in this browser, and the browser is shared with the
  # tests that follow: every notes system test forgets it again.
  teardown { page.execute_script(FORGET_OPEN) }

  def open_editor
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
  end

  def card = "##{ActionView::RecordIdentifier.dom_id(@block)}"

  def new_note_field = find("#notes-new textarea[name=body]")

  def focused?(selector) = page.evaluate_script("document.activeElement === document.querySelector(#{selector.to_json})")

  def focus_in_drawer? = page.evaluate_script("document.activeElement.closest('#notes-drawer') !== null")

  # Presses Tab until the focus is on `selector`: the control is reached the
  # way the keyboard reaches it, and one that Tab never meets fails here.
  def tab_to(selector, limit: 12)
    limit.times do
      page.driver.browser.keyboard.type(:Tab)
      return if focused?(selector)
    end
    flunk "Tab never reached #{selector}; the focus is on #{page.evaluate_script("document.activeElement.outerHTML.slice(0, 160)")}"
  end

  # Does the autosave screen's unload guard ask? (`Admin::AutosaveUnloadSystemTest`
  # says why the decision is tested and not the browser's own prompt.)
  def asks_before_unload?
    page.evaluate_script(<<~JS)
      (() => {
        const event = new Event("beforeunload", { cancelable: true })
        window.dispatchEvent(event)
        return event.defaultPrevented
      })()
    JS
  end

  test "a question on a block reaches a colleague's inbox, is answered, resolved, reopened and pinned" do
    sign_in_via_form(users(:one))
    open_editor
    within(card) do
      find("button[aria-label='Block actions']").click
      press "Add note"
    end
    new_note_field.send_keys("Is this still right, @Dan")
    assert_selector "#notes-new [role=option]", text: "Dana"
    new_note_field.send_keys(:enter, "?")
    within("#notes-new") { press "Add note" }
    assert_selector "#notes-drawer [data-note-thread] [data-note-mention=other]", text: "@Dana"
    thread = Notes::Thread.last
    assert_equal [ @block, @page, [ users(:two).id ] ], [ thread.subject, thread.container, thread.first_message.mentioned_user_ids ]

    using_session(:dana) do
      sign_in_via_form(users(:two))
      visit "/cs-studio"
      await_admin_controllers
      assert_selector "#sidebar-badge-dashboard", text: "1"
      within("turbo-frame#notes-for-you") { press "one mentioned you" }

      messages = "#note-thread-#{thread.id}-messages"
      reply = "#note-thread-#{thread.id}-reply"
      assert_current_path(/\/pages\/#{@page.id}\?notes=open&thread=#{thread.id}\z/)
      assert_selector "#notes-drawer #note-thread-#{thread.id}", text: "Is this still right"
      # The mention is of the reader now, and opening the thread read it.
      assert_selector "#{messages} [data-note-mention=viewer]", text: "@Dana"
      assert_eventually(message: "opening the thread never marked its delivery read") { Notes::Delivery.unread.where(user: users(:two)).none? }

      find("#{reply} textarea[name=body]").send_keys("Yes, checked today")
      within(reply) { press "Reply" }
      assert_selector "#{messages} [data-note-message]", count: 2
      assert_equal "", find("#{reply} textarea[name=body]").value

      within(reply) { press "Resolve" }
      assert_selector "#note-thread-#{thread.id}[data-state=resolved] [data-note-badge=resolved]", text: /resolved by\s+dana/i
      assert_no_selector "#notes-open-count" # nothing open is counted

      within(reply) { press "Reopen" }
      assert_selector "#note-thread-#{thread.id}[data-state=open]"
      assert_selector "#notes-open-count", text: "1"
      # Dana may edit the page, so she may pin (an icon-only control).
      find("#note-thread-#{thread.id} [data-note-actions] button[aria-label='Pin']").click
      assert_selector "#note-thread-#{thread.id} [data-note-badge=pinned]"
      find("#notes-drawer a[data-note-back]").click
      assert_selector "#notes-pinned a#note-row-#{thread.id}"
    ensure
      page.execute_script(FORGET_OPEN)
    end

    assert_equal [ "open", true, 2 ], thread.reload.then { |record| [ record.state, record.pinned, record.messages.count ] }
    assert_equal %w[note.started note.replied note.resolved note.reopened note.pinned],
      Audit::Event.where(subject_type: "ContentBlock", subject_id: @block.id).order(:id).pluck(:action)
    # The asker follows the thread: the reply, the resolve and the reopen
    # were each news for them, on two rows (the first message's row is
    # reused for a change of state).
    assert_equal %w[reopened reply], Notes::Delivery.where(user: users(:one)).pluck(:reason).sort
    # And none of it wrote the block or its page.
    assert_empty Audit::Event.where(action: %w[block.updated page.updated]).pluck(:action)
  end

  test "the drawer by keyboard alone: open, start a note, send it, go back, close" do
    sign_in_via_form(users(:one))
    open_editor
    keyboard = page.driver.browser.keyboard

    # The keys go to whatever has the focus: `send_keys` on an element would
    # click it first, and a click is what this test does without. The
    # header's button is given the focus as Tab would give it.
    page.execute_script("document.getElementById('notes-open').focus()")
    keyboard.type(:Enter)
    assert_selector "#notes-drawer #notes-list"
    assert_eventually(message: "the focus never moved into the drawer") { focus_in_drawer? }

    tab_to("#notes-drawer > header button[data-action='admin--notes--drawer#compose']")
    keyboard.type(:Enter)
    assert_eventually(message: "the new note's field never took the focus") { focused?("#notes-new textarea[name=body]") }
    keyboard.type("A note without a mouse")
    keyboard.type([ :Control, :Enter ])

    assert_selector "#notes-drawer [data-notes-view=thread]", text: "A note without a mouse"
    thread = Notes::Thread.last
    assert_eventually(message: "the thread never took the focus") { focused?("#note-thread-#{thread.id}") }
    tab_to("#notes-drawer a[data-note-back]")
    keyboard.type(:Enter)
    assert_selector "#notes-list a#note-row-#{thread.id}"
    assert_eventually(message: "the focus left the drawer on the way back to the list") { focus_in_drawer? }
    tab_to("#notes-list a#note-row-#{thread.id}", limit: 20)
    keyboard.type(:Escape)

    assert_no_selector "#notes-drawer"
    assert focused?("#notes-open"), "Escape did not give the focus back to the header's button"
    assert_equal 1, Notes::Thread.count
  end

  # Review Focus 4. The block's autosave and the note's form both reach the
  # network through `window.fetch` (the autosave's own `fetch`, and Turbo's
  # for a form submission), so one stand-in sees both: it holds every write
  # until `__release()` and lists them in the order they were sent.
  test "a note sent while an autosave is on the wire goes after it, once, and moves no base" do
    sign_in_via_form(users(:one))
    open_editor
    find("#notes-open").click
    within("#notes-drawer") { press "New note" }
    assert_selector "#notes-new textarea[name=body]"
    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.__held = []
      window.__writes = []
      window.__asked = 0
      window.fetch = (url, options = {}) => {
        const method = (options.method || "GET").toUpperCase()
        if (method === "GET") return originalFetch(url, options)
        window.__writes.push(`${method} ${new URL(String(url.url || url), location.href).pathname}`)
        if (window.__released) return originalFetch(url, options)
        return new Promise((resolve) => { window.__held.push(() => resolve(originalFetch(url, options))) })
      }
      window.__release = () => { window.__released = true; window.__held.forEach((go) => go()) }
      // Turbo asks before it sends: the note's submission was begun.
      document.addEventListener("turbo:before-fetch-request", (event) => {
        if (String(event.detail.fetchOptions.method).toUpperCase() !== "GET") window.__asked += 1
      }, true)
    JS

    find("#{card} .ProseMirror").click
    page.driver.browser.keyboard.type("An edit on its way")
    await_js("window.__held.length === 1", wait: LIVE)
    before = @block.reload.updated_at

    new_note_field.send_keys("Written while saving")
    within("#notes-new") { press "Add note" }
    await_js("window.__asked === 1")
    await_frames
    # Held behind the save by the write queue, not sent beside it: the
    # submission never reached `fetch`.
    block_path = "/cs-studio/pages/#{@page.id}/content_blocks/#{@block.id}"
    assert_equal [ "PATCH #{block_path}" ], page.evaluate_script("window.__writes")
    assert_equal 0, Notes::Thread.count

    page.execute_script("window.__release()")

    assert_selector "#notes-drawer [data-notes-view=thread]", text: "Written while saving"
    assert_writes_settled
    # After the save, and exactly once.
    threads_path = "/cs-studio/notes/page/#{@page.id}/threads"
    assert_equal [ "PATCH #{block_path}", "POST #{threads_path}" ], page.evaluate_script("window.__writes")
    assert_equal 1, Notes::Thread.count
    assert_equal %w[block.updated note.started], Audit::Event.where(action: %w[block.updated note.started]).order(:id).pluck(:action)

    # The save moved the block (it touched its page, whose settings base stays
    # where it was); the note moved neither, and
    # each form's base is what the save made it.
    saved = @block.reload.updated_at
    assert_operator saved, :>, before
    assert_includes @block.body.to_s, "An edit on its way"
    assert_equal saved.iso8601(6), find("#block-#{@block.id}-base-updated-at", visible: :all).value
    assert_equal @page.reload.settings_changed_at.iso8601(6), find("#page-base-updated-at", visible: :all).value
    assert_operator Notes::Thread.last.created_at, :>, saved

    # So the next edit of the same block is saved, not refused as stale.
    find("#{card} .ProseMirror").click
    page.driver.browser.keyboard.type(" and one more")
    assert_eventually(message: "the edit after the note was never saved") { @block.reload.body.to_s.include?("and one more") }
    assert_writes_settled
    assert_no_text "CHANGED ELSEWHERE"
    assert_no_selector "#editor-notice #changed-elsewhere"
    assert_equal 0, Audit::Event.where(action: "access.denied").count
    assert_equal 1, Notes::Thread.count
  end

  # Spec §8, System: "attach an image and a PDF; react".
  test "a note carries an image and a PDF, and takes a reaction" do
    sign_in_via_form(users(:one))
    open_editor
    find("#notes-open").click
    within("#notes-drawer") { press "New note" }
    pdf = Tempfile.new([ "report", ".pdf" ], binmode: true).tap { |file| file.write(PDF); file.close }
    # `set` on the field itself: it is out of sight, and the paperclip opens it.
    find("#notes-new input[type=file]", visible: :all).set([ file_fixture("tiny.png").to_s, pdf.path ])
    assert_selector "#notes-new [data-admin--notes--composer-target=chosen] [data-note-chosen]", count: 2
    new_note_field.send_keys("Two files")
    within("#notes-new") { press "Add note" }

    assert_selector "#notes-drawer [data-note-files] a[data-note-image] img[alt='tiny.png']"
    assert_selector "#notes-drawer [data-note-files] a[data-note-file]", text: /report.*\.pdf/
    note = Notes::Message.last
    note_file_keys
    assert_equal %w[application/pdf image/png], note.files.map(&:content_type).sort
    # Each is read through the notes action, by its attachment's id; no
    # Active Storage address is in the page.
    files_path = %r{\A/cs-studio/notes/page/#{@page.id}/threads/#{note.thread_id}/messages/#{note.id}/files/\d+\z}
    all("#notes-drawer [data-note-files] a").each { |link| assert_match files_path, URI(link[:href]).path }
    assert_no_selector "#notes-drawer [src*='/rails/active_storage'], #notes-drawer [href*='/rails/active_storage']", visible: :all

    # Nobody has reacted: the add control in the meta line shows on hover or
    # focus only, so the way in here is the menu's "React".
    within("#note-message-#{note.id}") do
      find("button[aria-label='Note actions']").click
      press "React"
      find("details[data-reaction-add][open] button[name=emoji][value='👍']").click
    end
    assert_selector "#note-message-#{note.id} [data-note-reactions] button[data-reaction='👍'][data-mine]", text: "1"
    assert_equal [ [ users(:one).id, "👍" ] ], Notes::Reaction.pluck(:user_id, :emoji)
    # A reaction tells nobody and is not in the log.
    assert_equal %w[note.started], Audit::Event.where(subject: @page).where.not(action: %w[page.created page.published]).pluck(:action)
  ensure
    pdf&.unlink
  end

  test "a view-only reader writes a note, replies and resolves, and can neither pin nor change the page" do
    theirs = as(users(:two)) { Notes::Start.call(@block, body: "Is this right?") }.record
    before = [ @page.reload.updated_at, @block.reload.updated_at ]
    sign_in_via_form(users(:reader))
    open_editor
    assert_selector "[data-view-only-hint]"
    assert_selector "#{card} fieldset.admin-view-only[disabled]", visible: :all

    find("#notes-open").click
    within("#notes-drawer") { press "New note" }
    new_note_field.send_keys("From a reader")
    within("#notes-new") { press "Add note" }

    assert_selector "#notes-drawer [data-notes-view=thread]", text: "From a reader"
    assert_equal [ @page, users(:reader).id ], Notes::Thread.last.then { |thread| [ thread.subject, thread.first_message.author_id ] }
    assert_no_selector "#notes-drawer [data-note-actions] button[aria-label='Pin']"

    # Someone else's thread: read, answered and resolved with the read right
    # alone (decision D3); its author's note has no menu to delete it from.
    find("#notes-drawer a[data-note-back]").click
    find("#notes-list a#note-row-#{theirs.id}").click
    reply = "#note-thread-#{theirs.id}-reply"
    find("#{reply} textarea[name=body]").send_keys("Looks right to me")
    within(reply) { press "Reply" }
    assert_selector "#note-thread-#{theirs.id}-messages [data-note-message]", count: 2
    within(reply) { press "Resolve" }
    assert_selector "#note-thread-#{theirs.id}[data-state=resolved]"
    assert_no_selector "#notes-drawer [data-note-actions] button[aria-label='Pin']"
    within("#note-message-#{theirs.first_message.id}") { assert_no_selector "[data-note-delete], [data-note-edit]", visible: :all }

    assert theirs.reload.resolved?
    assert_equal before, [ @page.reload.updated_at, @block.reload.updated_at ]
    assert_equal 0, Audit::Event.where(action: "access.denied").count
  end

  # Spec §7, "Unsent text": the guard is about content. An editor's guard is
  # the unload guard of its autosave forms (a Turbo visit waits for the write
  # queue and asks nothing); the "Leave without saving?" dialog belongs to the
  # explicit-save screens and must not be raised for a note either.
  test "leaving an editor with a half-typed note asks nothing, and an unsaved edit of the page still asks" do
    sign_in_via_form(users(:one))
    open_editor
    find("#notes-open").click
    within("#notes-drawer") { press "New note" }
    new_note_field.send_keys("Half a thought")
    assert_equal "Half a thought", new_note_field.value
    await_frames

    assert_not asks_before_unload?, "a half-typed note was guarded like unsaved content"
    assert_writes_settled # the note's text is nothing the write queue waits for

    # Unsaved content on the same screen does ask, with the note still there.
    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.fetch = (url, options = {}) => {
        if ((options.method || "GET").toUpperCase() === "GET" || window.__released) return originalFetch(url, options)
        return new Promise((resolve) => { window.__release = () => { window.__released = true; resolve(originalFetch(url, options)) } })
      }
    JS
    fill_in "Subtitle", with: "Typed, not saved yet"
    assert asks_before_unload?, "an unsaved edit of the page was not guarded"
    await_js("typeof window.__release === 'function'", wait: LIVE)
    page.execute_script("window.__release()")
    assert_writes_settled
    assert_equal "Typed, not saved yet", @page.reload.subtitle
    assert_not asks_before_unload?, "a saved editor with a half-typed note still asked"

    # A way out through the shell: no dialog, and the note was not sent.
    within(".admin-shell__sidebar") { click_link "Trash" }
    assert_current_path %r{/cs-studio/trash}
    assert_no_selector "dialog#leave-dialog[open]"
    assert_equal 0, Notes::Thread.count

    # The text is the person's draft, back when the field is drawn again.
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    assert_selector "#notes-drawer #notes-list" # open was remembered
    within("#notes-drawer") { press "New note" }
    assert_equal "Half a thought", new_note_field.value
  end
end
