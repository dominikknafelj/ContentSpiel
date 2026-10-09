require "application_system_test_case"

class Admin::NotesDrawerSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
  end

  # "Open" is remembered in this browser, and the browser is shared with the
  # tests that follow: every notes system test forgets it again.
  teardown { page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}") }

  def open_editor(query = "")
    visit "/cs-studio/pages/#{@page.id}#{query}"
    await_admin_controllers
  end

  # "New note" is the drawer's header's, and the one in the drawer (the
  # handoff's decision 4): the list's own link, and its empty state's, are
  # not shown there, so it is pressed without saying where.
  def press_new_note
    within("#notes-drawer") { press "New note" }
  end

  def focus_in_drawer? = page.evaluate_script("document.activeElement.closest('#notes-drawer') !== null")

  test "the header button opens the drawer with the focus in it, a note is written, the count follows, Escape closes and gives the focus back" do
    open_editor
    assert_no_selector "#notes-drawer"

    find("#notes-open").click

    assert_selector "#notes-drawer[aria-label='Notes'] #notes-list"
    assert_selector "#notes-open[aria-expanded=true][aria-pressed=true]"
    assert_eventually(message: "the focus never moved into the drawer") { focus_in_drawer? }

    press_new_note
    find("#notes-new textarea[name=body]").send_keys("Is this page ready?")
    within("#notes-new") { press "Add note" }

    # The new thread replaces the list; Back returns to it.
    assert_selector "#notes-drawer [data-notes-view=thread]", text: "Is this page ready?"
    assert_no_selector "#notes-list"
    assert_selector "#notes-open-count", text: "1"
    assert_selector "#notes-open[aria-label='Notes, 1 open']"
    # The thread's first row is the header now (the handoff's decision 11):
    # the count of open threads stands beside "All notes".
    assert_selector "#notes-drawer a[data-note-back]", text: /All notes\s*1/
    assert_equal @page, Notes::Thread.last.subject
    # The form that held the focus is gone with the list: the thread has it,
    # not the page behind the drawer.
    assert_eventually(message: "the focus left the drawer when the note was sent") { focus_in_drawer? }
    find("#notes-drawer a[data-note-back]").click
    assert_selector "#notes-list a[data-note-row]", text: "Is this page ready?"
    assert_selector "#notes-drawer > header", text: "1 OPEN"
    assert_eventually(message: "the focus left the drawer on the way back to the list") { focus_in_drawer? }

    # A real key on a row focused by script. Cuprite's `send_keys` CLICKS an
    # element that is not focused: that followed the row, and Escape then
    # raced the thread's arrival -- when the frame had just replaced the row
    # the focus was on <body> for a moment and the key closed nothing (the
    # one failure of this test in a full run).
    find("#notes-list a[data-note-row]").execute_script("this.focus()")
    page.driver.browser.keyboard.type(:escape)

    assert_no_selector "#notes-drawer"
    assert_selector "#notes-open[aria-expanded=false][aria-pressed=false]"
    assert_equal "notes-open", page.evaluate_script("document.activeElement.id")
  end

  test "the editor stays usable beside the open drawer: it is not modal and has no scrim" do
    open_editor
    find("#notes-open").click
    assert_selector "#notes-list"

    assert_no_selector ".admin-shell__scrim", visible: true
    assert_equal false, page.evaluate_script("document.querySelector('.admin-content-blocks').inert")
    # The drawer starts below the header: the button that opened it is still
    # there to be pressed, and shows that it is.
    assert_operator page.evaluate_script("document.querySelector('#notes-open').getBoundingClientRect().bottom"), :<=,
      page.evaluate_script("document.querySelector('#notes-drawer').getBoundingClientRect().top")
    # Escape belongs to the drawer only while the focus is inside it.
    page.execute_script("document.querySelector('.admin-content-blocks [contenteditable=true]').focus()")
    page.driver.browser.keyboard.type(:escape)
    await_frames
    assert_selector "#notes-drawer #notes-list"
    find("#notes-open").click
    assert_no_selector "#notes-drawer"
    find("#notes-open").click
    assert_selector "#notes-drawer #notes-list"

    find("body").send_keys([ :control, "k" ])
    assert_selector "dialog[open]"
  end

  test "open is remembered for the next editor in this browser without taking the focus, and Close forgets it" do
    other = create_page(title: "Other")
    open_editor
    find("#notes-open").click
    assert_selector "#notes-list"

    visit "/cs-studio/pages/#{other.id}"
    await_admin_controllers
    assert_selector "#notes-drawer #notes-list[data-notes-container='Page-#{other.id}']"
    assert_selector "#notes-open[aria-pressed=true]"
    assert_equal false, focus_in_drawer?

    find("#notes-drawer button[aria-label='Close']").click
    assert_no_selector "#notes-drawer"
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    assert_selector "#notes-open[aria-pressed=false]"
    assert_no_selector "#notes-drawer"
  end

  test "the drawer has one New note, its header's: the list's own link and the empty state's are not shown in it" do
    open_editor
    find("#notes-open").click
    assert_selector "#notes-list .admin-empty-state", text: "No notes yet"
    assert_selector "#notes-drawer button", text: "New note", count: 1
    assert_no_selector "#notes-drawer a[data-note-new-link]"
    assert_selector "#notes-drawer a[data-note-new-link]", visible: :hidden, count: 1

    press_new_note
    find("#notes-new textarea[name=body]").send_keys("First")
    within("#notes-new") { press "Add note" }
    assert_selector "#notes-drawer [data-notes-view=thread]", text: "First"
    find("#notes-drawer a[data-note-back]").click

    assert_selector "#notes-list a[data-note-row]", text: "First"
    assert_selector "#notes-drawer button", text: "New note", count: 1
    assert_no_selector "#notes-drawer a[data-note-new-link]"
    assert_selector "#notes-drawer a[data-note-new-link]", visible: :hidden, count: 1

    # The record's notes page is the same list without a drawer: it keeps its link.
    visit "/cs-studio/notes/page/#{@page.id}"
    assert_selector "#notes-list a[data-note-new-link]", text: "New note"
  end

  # The handoff's decision 3: Resolve stands in the composer's row, to the
  # left of Send, and Reopen takes its place; Pin ends row 2.
  test "Resolve is pressed beside Send and Reopen stands where it was; Notify and Pin are in the two rows above the messages" do
    thread = as(users(:two)) { Notes::Start.call(@block, body: "Look here") }.record
    open_editor("?notes=open&thread=#{thread.id}")
    assert_selector "#note-thread-#{thread.id}"

    boxes = lambda do |*selectors|
      selectors.map { |selector| page.evaluate_script("(() => { const box = document.querySelector(#{selector.to_json}).getBoundingClientRect(); return [ box.left, box.top, box.right, box.bottom ] })()") }
    end
    reply = "#note-thread-#{thread.id}-reply"
    state, send = boxes.call("#{reply} button[data-note-state=resolve]", "#{reply} button[type=submit]:not([form])")
    assert_in_delta 8, send[0] - state[2], 1, "Resolve stands 8px to the left of Send"
    assert_in_delta (state[1] + state[3]) / 2, (send[1] + send[3]) / 2, 2, "on Send's line"
    back, notify, pin, first = boxes.call("a[data-note-back]", "[data-note-actions] form[action$='/follow'] button", "[data-note-actions] button[aria-label=Pin]", "#note-message-#{thread.first_message.id}")
    assert_in_delta (back[1] + back[3]) / 2, (notify[1] + notify[3]) / 2, 3, "Notify me is on Back's row"
    assert_operator pin[1], :>=, back[3], "Pin is on the row below"
    assert_operator pin[3], :<=, first[1] + 1, "and above the messages"
    assert_operator pin[2], :>, notify[0], "at the right end"

    find("#{reply} textarea[name=body]").send_keys("Still typing")
    within(reply) { press "Resolve" }

    assert_selector "#{reply} button[data-note-state=reopen]", text: "Reopen"
    assert_no_selector "#{reply} button[data-note-state=resolve]"
    assert thread.reload.resolved?
    reopen, send = boxes.call("#{reply} button[data-note-state=reopen]", "#{reply} button[type=submit]:not([form])")
    assert_in_delta 8, send[0] - reopen[2], 1, "Reopen stands where Resolve was"
    # What was typed is still the reply's draft.
    assert_equal "Still typing", find("#{reply} textarea[name=body]").value

    within(reply) { press "Reopen" }
    assert_selector "#{reply} button[data-note-state=resolve]"
    assert thread.reload.open?
  end

  # The handoff's decision 11: while a thread is open the drawer's own header
  # is hidden, and row 1 is "← All notes 4", the Notify link and Close.
  test "a thread hides the drawer's header and has Close in its first row; Close there closes the drawer and gives the focus back; All notes brings the header back" do
    thread = as(users(:two)) { Notes::Start.call(@block, body: "Look here") }.record
    as(users(:two)) { Notes::Start.call(@page, body: "And here") }
    open_editor
    find("#notes-open").click
    assert_selector "#notes-drawer > header button", text: "New note"
    assert_selector "#notes-drawer button[aria-label='Close']", count: 1

    find("#note-row-#{thread.id}").click

    assert_selector "#note-thread-#{thread.id}"
    assert_no_selector "#notes-drawer > header"
    assert_no_selector "#notes-drawer button", text: "New note"
    assert_selector "#notes-drawer a[data-note-back]", text: /All notes\s*2/
    # One Close, row 1's: after the Notify link, at the row's right end.
    assert_selector "#notes-drawer button[aria-label='Close']", count: 1
    assert_selector "#note-thread-#{thread.id} button[data-note-close][aria-label='Close']"
    edges = page.evaluate_script("[ 'a[data-note-back]', '[data-note-actions] form[action$=\"follow\"] button', 'button[data-note-close]' ].map((selector) => { const box = document.querySelector('#notes-drawer ' + selector).getBoundingClientRect(); return [ box.left, (box.top + box.bottom) / 2 ] })")
    assert_operator edges[0][0], :<, edges[1][0]
    assert_operator edges[1][0], :<, edges[2][0]
    assert_in_delta edges[0][1], edges[2][1], 4, "Close is not on Back's row"
    # The thread starts where the drawer does: no gap where the header was.
    tops = page.evaluate_script("[ '#notes-drawer', 'a[data-note-back]' ].map((selector) => document.querySelector(selector).getBoundingClientRect().top)")
    assert_operator tops[1] - tops[0], :<, 24

    find("#notes-drawer a[data-note-back]").click
    assert_selector "#notes-list"
    assert_selector "#notes-drawer > header button", text: "New note"
    assert_selector "#notes-drawer > header button[aria-label='Close']"

    find("#note-row-#{thread.id}").click
    assert_selector "#note-thread-#{thread.id}"
    find("#notes-drawer button[data-note-close]").click

    assert_no_selector "#notes-drawer"
    assert_selector "#notes-open[aria-expanded=false][aria-pressed=false]"
    assert_equal "notes-open", page.evaluate_script("document.activeElement.id")
    assert_no_selector "html[data-notes-open]"
  end

  # The handoff's decision 17: below 1024px the sheet's header goes too while
  # a thread is open, and the thread's first row is all there is: "← All
  # notes 4", the Notify link, and "Back to <title>" as a text button on the
  # right, which does what the sheet header's Back does.
  test "below 1024px a thread hides the sheet's header: its first row has All notes, Notify and Back to the page" do
    thread = as(users(:two)) { Notes::Start.call(@block, body: "Look here") }.record
    original = page.current_window.size
    page.current_window.resize_to(900, 800)
    open_editor
    find("#notes-open").click
    assert_selector "#notes-drawer > header button", text: "Back to Pricing"
    find("#note-row-#{thread.id}").click

    assert_selector "#notes-drawer #note-thread-#{thread.id}"
    assert_no_selector "#notes-drawer > header"
    assert_no_selector "#notes-drawer button[aria-label='Close']"
    assert_selector "#notes-drawer button", text: "Back to Pricing", count: 1
    # One row, in this order, the way back at its right end.
    boxes = page.evaluate_script("[ 'a[data-note-back]', '[data-note-actions] form[action$=\"follow\"] button', 'button[data-note-leave]' ].map((selector) => { const box = document.querySelector('#notes-drawer ' + selector).getBoundingClientRect(); return [ box.left, (box.top + box.bottom) / 2, box.right ] })")
    assert_operator boxes[0][0], :<, boxes[1][0]
    assert_operator boxes[1][0], :<, boxes[2][0]
    assert_in_delta boxes[0][1], boxes[1][1], 4, "Notify is not on Back's row"
    assert_in_delta boxes[0][1], boxes[2][1], 4, "Back to the page is not on Back's row"
    # (The sheet's frame is centred and at most 720px wide.)
    frame_right = page.evaluate_script("document.querySelector('#notes-drawer turbo-frame#notes').getBoundingClientRect().right")
    assert_operator frame_right - boxes[2][2], :<, 24
    # The thread starts where the sheet does: no gap where the header was.
    tops = page.evaluate_script("[ '#notes-drawer', 'a[data-note-back]' ].map((selector) => document.querySelector(selector).getBoundingClientRect().top)")
    assert_operator tops[1] - tops[0], :<, 24

    # "All notes" brings the sheet's header back with the list.
    find("#notes-drawer a[data-note-back]").click
    assert_selector "#notes-list"
    assert_selector "#notes-drawer > header button", text: "Back to Pricing"
    assert_selector "#notes-drawer > header button", text: "New note"

    # "Back to <title>" in the row leaves for the editor, the focus on the
    # button that opened the notes, as the sheet header's does.
    find("#note-row-#{thread.id}").click
    assert_selector "#note-thread-#{thread.id}"
    within("#note-thread-#{thread.id}") { press "Back to Pricing" }
    assert_no_selector "#notes-drawer"
    assert_selector "#notes-open[aria-expanded=false][aria-pressed=false]"
    assert_equal "notes-open", page.evaluate_script("document.activeElement.id")
  ensure
    page.current_window.resize_to(*original)
  end

  test "below 1024px leaving a thread for the editor puts the editor back where it was scrolled to" do
    thread = as(users(:two)) { Notes::Start.call(@block, body: "Look here") }.record
    8.times { |index| @page.content_blocks.create!(block_type: "rich_text", position: index + 1) }
    original = page.current_window.size
    page.current_window.resize_to(900, 800)
    open_editor
    page.execute_script("window.scrollTo(0, 300)")
    assert_eventually(message: "the editor did not scroll") { page.evaluate_script("window.scrollY") == 300 }
    find("#notes-open").execute_script("this.click()") # press_by_script: a native click would scroll the button into view and move the page this test measures
    find("#note-row-#{thread.id}").click
    assert_selector "#note-thread-#{thread.id}"

    within("#note-thread-#{thread.id}") { press "Back to Pricing" }

    assert_no_selector "#notes-drawer"
    assert_eventually(message: "the editor is not where it was") { page.evaluate_script("window.scrollY") == 300 }
  ensure
    page.current_window.resize_to(*original)
  end

  # From 1024px the row's own way back to the page is not shown (Close is),
  # and neither is it where there is no drawer at all.
  test "Back to the page stands only in the sheet: not in the drawer from 1024px, not on a record's notes page" do
    thread = as(users(:two)) { Notes::Start.call(@block, body: "Look here") }.record
    open_editor("?notes=open&thread=#{thread.id}")
    assert_selector "#notes-drawer #note-thread-#{thread.id} button[data-note-close]"
    assert_no_selector "#notes-drawer button", text: "Back to Pricing"

    visit "/cs-studio/notes/page/#{@page.id}/threads/#{thread.id}"
    assert_selector "#note-thread-#{thread.id}"
    assert_no_selector "button", text: "Back to Pricing"
    assert_no_selector "button[data-note-close]"
  end

  test "the list is where it was left when a thread is closed again" do
    as(users(:two)) { 30.times { |index| Notes::Start.call(@page, body: "Note #{index}") } }
    open_editor
    find("#notes-open").click
    assert_selector "#notes-list a[data-note-row]", count: 30
    # To the END of the list, so the last row is in view: a native click on a
    # row out of view would scroll to it first, and "where it was left" would
    # no longer be the number read here.
    page.execute_script("const scroller = document.querySelector('#notes-drawer [data-notes-scroller]'); scroller.scrollTop = scroller.scrollHeight")
    at = page.evaluate_script("document.querySelector('#notes-drawer [data-notes-scroller]').scrollTop")
    assert_operator at, :>, 0

    all("#notes-list a[data-note-row]").last.click
    assert_selector "#notes-drawer [data-notes-view=thread]"
    # The thread starts at its own top, not where the list stood.
    assert_eventually(message: "the thread opened scrolled away from its top") { page.evaluate_script("document.querySelector('#notes-drawer [data-notes-scroller]').scrollTop").zero? }
    find("#notes-drawer a[data-note-back]").click

    assert_selector "#notes-list"
    assert_eventually(message: "the list did not come back to where it was") { page.evaluate_script("document.querySelector('#notes-drawer [data-notes-scroller]').scrollTop") == at }
  end

  test "?notes=open with a thread opens the drawer at that thread" do
    thread = as(users(:two)) { Notes::Start.call(@block, body: "Look here") }.record

    open_editor("?notes=open&thread=#{thread.id}")

    assert_selector "#notes-drawer #note-thread-#{thread.id}", text: "Look here"
    assert_eventually(message: "the thread never took the focus") { page.evaluate_script("document.activeElement.id") == "note-thread-#{thread.id}" }
  end

  # Spec §4.1: the focus goes back to the trigger on close. A drawer that no
  # press opened (a link with `?notes=open`) has the header's button for one.
  test "a drawer opened by ?notes=open gives the focus to the header's button when it is closed, by Close and by Escape" do
    open_editor("?notes=open")
    assert_selector "#notes-drawer #notes-list"
    assert_eventually(message: "the focus never moved into the drawer") { focus_in_drawer? }

    find("#notes-drawer button[aria-label='Close']").click
    assert_no_selector "#notes-drawer"
    assert_equal "notes-open", page.evaluate_script("document.activeElement.id")

    open_editor("?notes=open")
    assert_selector "#notes-drawer #notes-list"
    assert_eventually(message: "the focus never moved into the drawer") { focus_in_drawer? }

    page.driver.browser.keyboard.type(:escape)
    assert_no_selector "#notes-drawer"
    assert_equal "notes-open", page.evaluate_script("document.activeElement.id")
  end

  # Below 1024px the notes are a sheet over the whole editor: opened from
  # memory it would hide the page a person has just picked in the tree.
  test "below 1024px a remembered open does not put the sheet over the editor, and ?notes=open still does" do
    original = page.current_window.size
    page.current_window.resize_to(900, 800)
    open_editor
    page.execute_script("window.localStorage.setItem('cs-notes-open', '1')")

    open_editor
    assert_selector "#notes-open[aria-pressed=false]"
    assert_no_selector "#notes-drawer"

    open_editor("?notes=open")
    assert_selector "#notes-drawer #notes-list"
    assert_selector "#notes-open[aria-pressed=true]", visible: :all
  ensure
    page.current_window.resize_to(*original)
  end

  # A first load that failed (the network, a server error) leaves the frame
  # with its `src` and without a view. Stood in for here by emptying the
  # frame while the drawer is shut: its `src` is unchanged, as after a failure.
  test "a frame that did not load is fetched again when the drawer is opened" do
    open_editor
    find("#notes-open").click
    assert_selector "#notes-drawer #notes-list"
    find("#notes-drawer button[aria-label='Close']").click
    assert_no_selector "#notes-drawer"
    page.execute_script("document.querySelector('turbo-frame#notes').replaceChildren()")

    find("#notes-open").click

    assert_selector "#notes-drawer #notes-list"
  end

  test "below 1280px, opening the sidebar drawer closes the notes drawer, and the other way round" do
    original = page.current_window.size
    page.current_window.resize_to(1100, 800)
    open_editor
    find("#notes-open").click
    assert_selector "#notes-drawer"

    find("button[aria-controls=sidebar]").click
    assert_no_selector "#notes-drawer"
    assert_selector "#sidebar[data-open]", visible: :all

    find("#notes-open", visible: :all).execute_script("this.click()") # press_by_script: the shell's scrim covers the header while the sidebar drawer is open
    assert_selector "#notes-drawer"
    assert_no_selector "#sidebar[data-open]", visible: :all
  ensure
    page.current_window.resize_to(*original)
  end

  # Spec §7 "The drawer and the shell's drawers". Below 1024px the notes are a
  # full-screen sheet under the top bar, and the page tree is a drawer too.
  test "below 1024px the notes are a sheet with a way back, and the sheet and the page-tree drawer close each other" do
    original = page.current_window.size
    page.current_window.resize_to(900, 800)
    open_editor
    find("#notes-open").click
    assert_selector "#notes-drawer #notes-list"
    # The sheet fills the width under the top bar; the drawer's × is the
    # 400px drawer's, and here "Back to <title>" stands for it.
    assert_equal [ 0, 48, 900 ], page.evaluate_script("(() => { const box = document.querySelector('#notes-drawer').getBoundingClientRect(); return [ box.left, box.top, box.width ] })()")
    assert_no_selector "#notes-drawer button[aria-label='Close']"

    find("button[aria-controls='tree-column']").click
    assert_no_selector "#notes-drawer"
    assert_selector "#tree-column[data-open]", visible: :all

    find("#notes-open", visible: :all).execute_script("this.click()") # press_by_script: the shell's scrim covers the header while the tree drawer is open
    assert_selector "#notes-drawer #notes-list"
    assert_no_selector "#tree-column[data-open]", visible: :all

    within("#notes-drawer") { press "Back to Pricing" }
    assert_no_selector "#notes-drawer"
    assert_equal "notes-open", page.evaluate_script("document.activeElement.id")
  ensure
    page.current_window.resize_to(*original)
  end

  test "the post editor's drawer takes a note on the post" do
    post = create_post(title: "Hello")
    visit "/cs-studio/posts/#{post.id}"
    await_admin_controllers

    find("#notes-open").click
    assert_selector "#notes-drawer #notes-list[data-notes-container='Post-#{post.id}']"
    press_new_note
    find("#notes-new textarea[name=body]").send_keys("Check the intro")
    within("#notes-new") { press "Add note" }

    assert_selector "#notes-drawer [data-note-thread]", text: "Check the intro"
    assert_equal post, Notes::Thread.last.subject
  end
end
