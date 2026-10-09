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

  # "New note" in the drawer's own header. The empty list offers one too (the
  # shared empty state's action), so the button is asked for where it is.
  def press_new_note
    within("#notes-drawer > header") { press "New note" }
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
    assert_selector "#notes-drawer > header", text: "1 OPEN"
    assert_equal @page, Notes::Thread.last.subject
    # The form that held the focus is gone with the list: the thread has it,
    # not the page behind the drawer.
    assert_eventually(message: "the focus left the drawer when the note was sent") { focus_in_drawer? }
    find("#notes-drawer a[data-note-back]").click
    assert_selector "#notes-list a[data-note-row]", text: "Is this page ready?"
    assert_eventually(message: "the focus left the drawer on the way back to the list") { focus_in_drawer? }

    find("#notes-list a[data-note-row]").send_keys(:escape)

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
    # The header keeps its actions clear of the drawer: the button that
    # opened it is still there to be pressed, and shows that it is.
    assert_operator page.evaluate_script("document.querySelector('#notes-open').getBoundingClientRect().right"), :<=,
      page.evaluate_script("document.querySelector('#notes-drawer').getBoundingClientRect().left")
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
