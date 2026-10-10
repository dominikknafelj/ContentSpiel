require "application_system_test_case"

# Reactions on a note (notes spec D10, handoff "Reaction chip"), in the
# editor's drawer: a chip per emoji that toggles the viewer's own, the set to
# add from under each message, and what another person's reaction does to a
# thread that is open (a live refresh: `Admin::NotesLiveSystemTest` has the
# rules; here are the chips' own).
class Admin::NoteReactionsSystemTest < ApplicationSystemTestCase
  LIVE = 8

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:two).update!(name: "Dana")
    @page = create_page(title: "Pricing")
    @thread = as(users(:two)) { Notes::Start.call(@page, body: "Shipped") }.record
    @note = @thread.first_message
    sign_in_via_form(users(:one))
  end

  # "Open" is remembered in this browser, and the browser is shared with the
  # tests that follow: every notes system test forgets it again.
  teardown { page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}") }

  def open_thread
    visit "/cs-studio/pages/#{@page.id}?notes=open&thread=#{@thread.id}"
    await_notes_live
    assert_selector "#notes-drawer [data-notes-view=thread]"
    assert_eventually(message: "the thread never took the focus") { focused?("#note-thread-#{@thread.id}") }
  end

  def focused?(selector) = page.evaluate_script("document.activeElement === document.querySelector(#{selector.to_json})")

  def chips(note = @note) = "#note-message-#{note.id} [data-note-reactions]"

  # The emoji set of a message, wherever its control stands: at the end of the
  # chip row, or in the meta line of a message nobody reacted to.
  def set(note = @note) = "#note-message-#{note.id} details[data-reaction-add]"

  def add_chip(note = @note) = find("#{set(note)} > summary[aria-label='Add a reaction']", visible: :all)

  def emoji(name, note = @note) = find("#{set(note)} button[aria-label='React with #{name}']")

  def rect(selector) = page.evaluate_script("(({ top, bottom }) => ({ top, bottom }))(document.querySelector(#{selector.to_json}).getBoundingClientRect())")

  def reply_field = find("#note-thread-#{@thread.id}-reply textarea[name=body]")

  def react_as_dana(emoji, note = @note) = as(users(:two)) { Notes::React.call(note, emoji: emoji, on: true) }.tap { |result| assert result.ok?, result.errors.inspect }

  # Counts the GETs this tab makes for a thread from here on: a live refresh
  # is one; a reaction the tab sends is a POST, whose redirect the browser
  # follows by itself.
  def watch_thread_fetches
    page.execute_script(<<~JS)
      window.__threadFetches = 0
      const original = window.fetch
      window.fetch = (...args) => {
        const url = String(args[0].url || args[0])
        const method = String(args[1]?.method || args[0].method || "GET").toUpperCase()
        if (method === "GET" && url.includes("/threads/")) window.__threadFetches += 1
        return original(...args)
      }
    JS
  end

  test "an emoji from the set becomes my chip, a press takes it back, and the focus stays on the reaction" do
    open_thread
    reply_field.send_keys("Half a thought")

    # Nobody has reacted: no row under the message, and the control in its meta line.
    assert_no_selector chips, visible: :all
    assert_selector "#note-message-#{@note.id} > div:first-child > details[data-reaction-add=meta]", visible: :all
    bare = rect("#note-message-#{@note.id}")
    add_chip.click
    assert_selector "#{set}[open] button[name=emoji]", count: Notes::EMOJI.size
    emoji("thumbs up").click

    assert_selector "#{chips} button[data-reaction='👍'][data-mine][aria-pressed=true][title='#{Notes.name_of(users(:one))}']", text: /👍\s*1/
    assert_no_selector "#{set}[open]"
    assert_eventually(message: "the focus did not go to the new chip") { focused?("#{chips} button[data-reaction='👍']") }
    # After the first reaction the add chip stands at the end of the chip row, on show; the meta line has none.
    assert_selector "#{chips} > details[data-reaction-add=row]:last-child > summary", visible: :visible
    assert_no_selector "#note-message-#{@note.id} details[data-reaction-add=meta]", visible: :all
    assert_operator rect("#note-message-#{@note.id}")["bottom"] - rect("#note-message-#{@note.id}")["top"], :>, bare["bottom"] - bare["top"]
    assert_equal [ [ users(:one).id, "👍" ] ], @note.reactions.pluck(:user_id, :emoji)
    # What was being typed in the reply is there after the answer (its draft).
    assert_equal "Half a thought", reply_field.value

    find("#{chips} button[data-reaction='👍']").click

    # The last reaction took the row with it: the message is as tall as it was, and the focus is on the meta-line control.
    assert_no_selector chips, visible: :all
    assert_eventually(message: "the focus did not go to the add control") { focused?("#note-message-#{@note.id} details[data-reaction-add=meta] > summary") }
    assert_selector "#{set} > summary", visible: :visible # on show while the focus is in its message
    assert_in_delta bare["bottom"] - bare["top"], rect("#note-message-#{@note.id}")["bottom"] - rect("#note-message-#{@note.id}")["top"], 0.5
    assert_empty @note.reactions.reload
    assert_equal "Half a thought", reply_field.value
  end

  test "the keyboard alone reacts: Enter opens the set, Escape closes it and the drawer stays, Tab reaches an emoji, Enter gives it" do
    open_thread
    # The keys go to whatever has the focus (`send_keys` on an element would
    # click it first, and a click is what this test does without).
    keyboard = page.driver.browser.keyboard
    page.execute_script("document.querySelector(#{"#{set} > summary".to_json}).focus()")

    keyboard.type(:Enter)
    assert_selector "#{set}[open]"
    keyboard.type(:Tab)
    assert_eventually(message: "Tab did not reach the first emoji") { focused?("#{set} button[name=emoji]") }
    keyboard.type(:Escape)
    assert_no_selector "#{set}[open]", visible: :all
    assert focused?("#{set} > summary"), "Escape did not give the focus back to the add chip"
    assert_selector "#notes-drawer [data-notes-view=thread]" # the key was the set's, not the drawer's

    keyboard.type(:Enter)
    assert_selector "#{set}[open]"
    keyboard.type(:Tab)
    assert_eventually(message: "Tab did not reach the first emoji") { focused?("#{set} button[name=emoji]") }
    keyboard.type(:Enter)

    assert_selector "#{chips} button[data-reaction='#{Notes::EMOJI.first}'][data-mine]"
    assert_eventually(message: "the focus did not go to the new chip") { focused?("#{chips} button[data-reaction]") }
  end

  test "someone else's reaction arrives in the open thread, mine joins it, and my own is not fetched again" do
    open_thread
    reply_field.send_keys("Half a thought")
    page.execute_script("window.__reply = document.querySelector('#note-thread-#{@thread.id}-reply textarea[name=body]')")

    react_as_dana("🎉")

    assert_selector "#{chips} button[data-reaction='🎉'][title='Dana']:not([data-mine])", text: /🎉\s*1/, wait: LIVE
    assert page.evaluate_script("window.__reply.isConnected && window.__reply.value === 'Half a thought'"), "the reply field was replaced by the refresh"
    # A reaction is no news for an inbox: no toast, no badge.
    assert_no_selector "#toasts .admin-toast"
    assert_equal 0, Notes::Delivery.count

    watch_thread_fetches
    find("#{chips} button[data-reaction='🎉']").click

    assert_selector "#{chips} button[data-reaction='🎉'][data-mine][title='Dana, #{Notes.name_of(users(:one))}']", text: /🎉\s*2/
    sleep 0.8 # sleep: the coalescing window (500 ms) must have passed before "the thread was not fetched" means anything
    assert_equal 0, page.evaluate_script("window.__threadFetches") # no GET: the answer to the tab's own POST drew the chip
  end

  test "the set that is open under a message is still open after a live refresh, and still works" do
    open_thread
    add_chip.click
    assert_selector "#{set}[open]"

    react_as_dana("🎉")

    assert_selector "#{chips} button[data-reaction='🎉']", wait: LIVE
    assert_selector "#{set}[open]"
    emoji("eyes").click
    assert_selector "#{chips} button[data-reaction='👀'][data-mine]"
    assert_no_selector "#{set}[open]", visible: :all
  end

  test "a message with its delete question open keeps the question and gets the new chips" do
    open_thread
    find("#note-message-#{@note.id} button[aria-label='Note actions']").click
    find("#note-message-#{@note.id} a[data-note-delete]").click
    assert_selector "#note-message-#{@note.id} [data-note-delete-question]"
    page.execute_script("window.__asked = document.querySelector('#note-message-#{@note.id}')")

    react_as_dana("🎉")

    assert_selector "#{chips} button[data-reaction='🎉']", wait: LIVE
    assert page.evaluate_script("window.__asked.isConnected && window.__asked.querySelector('[data-note-delete-question]') !== null"), "the question was replaced"
  end

  test "a reaction on a message folded into Show more leaves that message on screen" do
    replies = as(users(:two)) { Array.new(4) { |index| Notes::Reply.call(@thread, body: "Reply #{index}").record } }
    open_thread
    find("details[data-note-fold] > summary").click

    add_chip(replies.first).click
    emoji("check mark", replies.first).click

    assert_selector "details[data-note-fold][open] #{chips(replies.first)} button[data-reaction='✅'][data-mine]"
  end

  test "a press outside the set closes it; React in the menu opens it with the focus on the first emoji" do
    open_thread
    add_chip.click
    assert_selector "#{set}[open]"

    find("#note-thread-#{@thread.id}-messages h3").click
    assert_no_selector "#{set}[open]", visible: :all

    within("#note-message-#{@note.id}") do
      find("button[aria-label='Note actions']").click
      press "React"
    end
    assert_selector "#{set}[open]"
    assert_no_selector "#note-message-#{@note.id} [role=menu]" # the menu closed behind it
    assert focused?("#{set} button[name=emoji]"), "the focus did not go to the first emoji"
    emoji("party popper").click
    assert_selector "#{chips} button[data-reaction='🎉'][data-mine][aria-label='party popper, 1 reaction, yours']"
  end

  # The handoff's decision 22: above the chip, below only when there is no
  # room above inside the thread's scroll area, and never over row 1.
  test "the set opens above its chip, and below it where row 1 leaves no room above" do
    last = as(users(:two)) { Array.new(2) { |index| Notes::Reply.call(@thread, body: "Reply #{index}\nwith\nseveral\nlines").record } }.last
    open_thread
    panel = ->(note) { "#{set(note)} form[data-admin--notes--reactions-target=panel]" }

    add_chip(last).click
    assert_selector "#{set(last)}[open]:not([data-side])"
    assert_operator rect(panel.call(last))["bottom"], :<=, rect("#{set(last)} > summary")["top"]
    assert_operator rect(panel.call(last))["top"], :>=, rect("#notes-drawer a[data-note-back]")["bottom"]

    add_chip.click # the first message, right under the thread's two rows
    assert_selector "#{set}[open][data-side=below]"
    assert_no_selector "#{set(last)}[open]", visible: :all # one set at a time
    assert_operator rect(panel.call(@note))["top"], :>=, rect("#{set} > summary")["bottom"]
    emoji("rocket").click
    assert_selector "#{chips} button[data-reaction='🚀'][data-mine]"
  end

  test "while a message is being edited its chips stay under the form and cannot be pressed" do
    mine = as(users(:one)) { Notes::Reply.call(@thread, body: "My own") }.record
    react_as_dana("🎉", mine)
    open_thread
    within("#note-message-#{mine.id}") do
      find("button[aria-label='Note actions']").click
      press "Edit"
    end

    assert_selector "#note-message-#{mine.id} form[data-note-composer] ~ [data-note-reactions=disabled] button[data-reaction='🎉'][disabled]"
    assert_selector "#{chips(mine)} button[data-reaction-add][disabled]"
    assert_equal "0.5", page.evaluate_script("getComputedStyle(document.querySelector(#{chips(mine).to_json})).opacity")
    assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector(#{chips(mine).to_json})).pointerEvents")

    # A reaction that arrives meanwhile is counted on the disabled chips; the form is not touched.
    find("#note-message-#{mine.id} form[data-note-composer] textarea[name=body]").send_keys(", changed")
    page.execute_script("window.__edit = document.querySelector('#note-message-#{mine.id} form[data-note-composer] textarea[name=body]')")
    as(users(:reader)) { assert Notes::React.call(mine, emoji: "🎉", on: true).ok? }
    as(users(:reader)) { assert Notes::React.call(mine, emoji: "👀", on: true).ok? }

    assert_selector "#{chips(mine)}[data-note-reactions=disabled] button[data-reaction='🎉'][disabled]", text: /🎉\s*2/, wait: LIVE
    assert_selector "#{chips(mine)} button[data-reaction='👀'][disabled]", text: /👀\s*1/
    assert_selector "#{chips(mine)} button[data-reaction-add][disabled]"
    assert_no_selector "#note-message-#{mine.id} details[data-reaction-add]", visible: :all
    assert_no_selector "#{chips(mine)} button:not([disabled])"
    assert_equal "0.5", page.evaluate_script("getComputedStyle(document.querySelector(#{chips(mine).to_json})).opacity")
    assert page.evaluate_script("window.__edit.isConnected && window.__edit.value === 'My own, changed'"), "the edit form was touched"

    within("#note-message-#{mine.id}") { find("a[data-note-cancel]").click }
    assert_selector "#{chips(mine)} button[data-reaction='🎉']:not([disabled])"
  end

  test "resolving a thread turns its chips read-only and takes the add chips away; reopened, they are back" do
    react_as_dana("🎉")
    open_thread
    assert_selector "#{chips} button[data-reaction='🎉']"

    within("#note-thread-#{@thread.id}-reply") { press "Resolve" }

    assert_selector "#{chips} span[data-reaction='🎉'][role=img]", text: /🎉\s*1/
    assert_no_selector "#note-thread-#{@thread.id} [data-note-reactions] button", visible: :all
    assert_no_selector "#note-thread-#{@thread.id} [data-reaction-add]", visible: :all
    assert_no_selector "#note-thread-#{@thread.id} [data-note-react]", visible: :all

    within("#note-thread-#{@thread.id}-reply") { press "Reopen" }
    assert_selector "#{chips} button[data-reaction='🎉']"
    assert_selector "#{set}", visible: :all
  end
end
