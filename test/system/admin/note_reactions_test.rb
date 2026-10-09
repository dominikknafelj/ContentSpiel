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

  def reply_field = find("#note-thread-#{@thread.id}-reply textarea[name=body]")

  def react_as_dana(emoji, note = @note) = as(users(:two)) { Notes::React.call(note, emoji: emoji) }.tap { |result| assert result.ok?, result.errors.inspect }

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

    find("#{chips} summary[aria-label='Add a reaction']").click
    assert_selector "#{chips} details[data-reaction-add][open] button[name=emoji]", count: Notes::EMOJI.size
    find("#{chips} button[aria-label='React with 👍']").click

    assert_selector "#{chips} button[data-reaction='👍'][data-mine][aria-pressed=true][title='#{users(:one).display_name}']", text: /👍\s*1/
    assert_no_selector "#{chips} details[open]"
    assert_eventually(message: "the focus did not go to the new chip") { focused?("#{chips} button[data-reaction='👍']") }
    assert_equal [ [ users(:one).id, "👍" ] ], @note.reactions.pluck(:user_id, :emoji)
    # What was being typed in the reply is there after the answer (its draft).
    assert_equal "Half a thought", reply_field.value

    find("#{chips} button[data-reaction='👍']").click

    assert_no_selector "#{chips} button[data-reaction]"
    assert_eventually(message: "the focus did not go to the add chip") { focused?("#{chips} summary") }
    assert_empty @note.reactions.reload
    assert_equal "Half a thought", reply_field.value
  end

  test "the keyboard alone reacts: Enter opens the set, Tab reaches an emoji, Enter gives it" do
    open_thread
    # The keys go to whatever has the focus (`send_keys` on an element would
    # click it first, and a click is what this test does without).
    keyboard = page.driver.browser.keyboard
    page.execute_script("document.querySelector(#{"#{chips} summary".to_json}).focus()")

    keyboard.type(:Enter)
    assert_selector "#{chips} details[open]"
    keyboard.type(:Tab)
    assert_eventually(message: "Tab did not reach the first emoji") { focused?("#{chips} button[name=emoji]") }
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

    assert_selector "#{chips} button[data-reaction='🎉'][data-mine][title='Dana, #{users(:one).display_name}']", text: /🎉\s*2/
    sleep 0.8 # sleep: the coalescing window (500 ms) must have passed before "the thread was not fetched" means anything
    assert_equal 0, page.evaluate_script("window.__threadFetches") # no GET: the answer to the tab's own POST drew the chip
  end

  test "the set that is open under a message is still open after a live refresh, and still works" do
    open_thread
    find("#{chips} summary").click
    assert_selector "#{chips} details[open]"

    react_as_dana("🎉")

    assert_selector "#{chips} button[data-reaction='🎉']", wait: LIVE
    assert_selector "#{chips} details[data-reaction-add][open]"
    find("#{chips} button[aria-label='React with 👀']").click
    assert_selector "#{chips} button[data-reaction='👀'][data-mine]"
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

    find("#{chips(replies.first)} summary").click
    find("#{chips(replies.first)} button[aria-label='React with ✅']").click

    assert_selector "details[data-note-fold][open] #{chips(replies.first)} button[data-reaction='✅'][data-mine]"
  end
end
