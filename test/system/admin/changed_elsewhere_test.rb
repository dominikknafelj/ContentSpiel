require "application_system_test_case"

# "Changed elsewhere" (design pass round 2, handoff §10 B19): a save sent
# from a stale form is REFUSED, the explanation bar names who changed the
# page, the editor's text stays in the field, the form stops sending, and
# Reload discards the text for the newer version. System-level because the
# pause ("no further request") and Reload are only observable in a browser.
class Admin::ChangedElsewhereSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @page = create_page(title: "About")
  end

  test "a stale autosave is refused, explained and final; Reload shows the newer version" do
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    # Someone else saves the page behind this browser's back. (The bar only
    # names changes more than a second past the base: an event is written a
    # few milliseconds after the save whose `updated_at` became the base.)
    sleep 1.2
    as(users(:two), channel: :admin) { Pages::Save.call(@page, translations: { "en" => { subtitle: "The other editor's text" } }) }

    fill_in "Subtitle", with: "My text"

    assert_selector "#page-save-status", text: "● CHANGED ELSEWHERE", wait: 5
    assert_selector "#editor-notice #changed-elsewhere[role=alert]", text: /Changed by two@example\.com .+Your text is still here/m
    assert_equal "The other editor's text", @page.reload.subtitle
    assert_equal "My text", find_field("Subtitle").value

    # Final: more typing sends nothing (past the 1000ms debounce, plus a
    # margin -- an absence needs the wait itself).
    fill_in "Subtitle", with: "My text, edited again"
    sleep 2
    assert_equal "The other editor's text", @page.reload.subtitle
    assert_equal "My text, edited again", find_field("Subtitle").value

    click_link "Reload"

    assert_field "Subtitle", with: "The other editor's text"
    assert_no_selector "#changed-elsewhere"
    assert_no_selector "#page-save-status", text: "CHANGED ELSEWHERE"
  end

  # The editor's own forms must never make each other stale (autosave queue,
  # `autosave/queue.js`): fill the page settings form and two block forms
  # inside one debounce window so all three save on the same tick, then edit
  # the page settings again. Deterministic, no AI. A `fetch` wrapper counts
  # the writes in flight at once: it must never exceed one.
  test "page and block forms saving on the same tick never make the page form stale, and never overlap" do
    blocks = 2.times.map { |i| @page.content_blocks.create!(block_type: :image, position: i) }
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.__inFlight = 0
      window.__maxInFlight = 0
      window.fetch = async (url, options = {}) => {
        const write = (options.method || "GET").toUpperCase() !== "GET"
        if (write) { window.__inFlight += 1; window.__maxInFlight = Math.max(window.__maxInFlight, window.__inFlight) }
        try { return await originalFetch(url, options) } finally { if (write) window.__inFlight -= 1 }
      }
    JS

    fill_in "Subtitle", with: "First"
    blocks.each_with_index { |block, i| fill_in id: "block-#{block.id}-caption", with: "Caption #{i}" }

    assert_selector "#page-save-status", text: /SAVED( TO SITE)? \d{2}:\d{2}\z/, wait: 8
    blocks.each { |block| assert_selector "#block-#{block.id}-save-status", text: /SAVED( TO SITE)? \d{2}:\d{2}\z/, wait: 8 }

    fill_in "Subtitle", with: "Second"
    assert_eventually { @page.reload.subtitle == "Second" }
    assert_no_text "CHANGED ELSEWHERE"
    assert_equal 1, page.evaluate_script("window.__maxInFlight"), "two writes were on the wire at once"
  end

  # Add and Delete block are plain Turbo form submissions that also touch the
  # page: they take their turn in the same queue and write the page base back.
  test "adding and deleting blocks leaves the page settings form able to save" do
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    press "Rich text"
    assert_selector ".admin-block-card", count: 1, wait: 5

    fill_in "Subtitle", with: "After add"
    assert_eventually { @page.reload.subtitle == "After add" }
    assert_no_text "CHANGED ELSEWHERE"
  end

  # A held Turbo submission that is aborted (a double press: the second
  # submission cancels the first) must give its queue slot back at once, not
  # after the 30 s safety limit -- or every save on the screen stalls.
  test "a double-pressed Add block does not stall the autosaves behind it" do
    block = @page.content_blocks.create!(block_type: :image, position: 0)
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    fill_in id: "block-#{block.id}-caption", with: "Saving as the next button is pressed"
    # One tick: blur (the caption save is queued and goes out), then two
    # submissions of the picker button. The first is held behind the save, the
    # second makes Turbo abort the first.
    page.execute_script(<<~JS)
      document.activeElement.blur()
      const button = Array.from(document.querySelectorAll("button")).find((b) => b.textContent.trim() === "Rich text")
      button.click()
      button.click()
    JS

    fill_in "Subtitle", with: "Saved promptly"
    assert_eventually(wait: 6) { @page.reload.subtitle == "Saved promptly" }
    assert_no_text "CHANGED ELSEWHERE"
  end

  # Publish waits for the queue: an edit still queued behind another form's
  # request is saved first, and the action then runs on the fresh state.
  test "pressing Publish right after typing saves the typed value and publishes, with no conflict" do
    draft = create_page(title: "Draft", published: false)
    block = draft.content_blocks.create!(block_type: :image, position: 0)
    visit "/cs-studio/pages/#{draft.id}"
    await_admin_controllers

    fill_in id: "block-#{block.id}-caption", with: "A caption"
    fill_in "Subtitle", with: "Typed just before Publish"
    press "Publish"

    assert_eventually { draft.reload.published_at.present? }
    assert_equal "Typed just before Publish", draft.subtitle
    assert_equal "A caption", block.reload.caption
    assert_no_text "CHANGED ELSEWHERE"
  end

  # Nothing that replaces the page starts until the queue is empty
  # (`autosave/queue.js`, "THE RULE"). The wrapper below slows every PATCH so a
  # save is reliably still in flight when the next thing happens.
  SLOW_PATCHES = <<~JS
    const originalFetch = window.fetch
    window.fetch = async (url, options = {}) => {
      if ((options.method || "GET").toUpperCase() === "PATCH") await new Promise((resolve) => setTimeout(resolve, 1200))
      return originalFetch(url, options)
    }
  JS

  # A: an edit made while the SAME form's save is on the wire is a follow-up
  # that waits behind it; Publish must wait for that follow-up too.
  test "an edit typed while the same form's save is in flight is saved before Publish runs" do
    draft = create_page(title: "Draft", published: false)
    visit "/cs-studio/pages/#{draft.id}"
    await_admin_controllers
    page.execute_script(SLOW_PATCHES)

    fill_in "Subtitle", with: "first"
    page.execute_script("document.activeElement.blur()") # the save for "first" goes out, and is slow
    fill_in "Subtitle", with: "second, typed while that save is in flight"
    press "Publish"

    assert_eventually(wait: 15) { draft.reload.published_at.present? }
    assert_equal "second, typed while that save is in flight", draft.subtitle
    assert_no_text "CHANGED ELSEWHERE"
  end

  # B: a plain visit waits for every queued edit instead of dropping it.
  test "following a sidebar link right after typing in two forms saves both edits" do
    block = @page.content_blocks.create!(block_type: :image, position: 0)
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    page.execute_script(SLOW_PATCHES)

    fill_in "Subtitle", with: "Page edit"
    fill_in id: "block-#{block.id}-caption", with: "Block edit" # blurs Subtitle: its (slow) save is now in flight
    page.execute_script("document.activeElement.blur()")       # the caption's save is queued behind it, unsent
    page.execute_script(<<~JS)
      Array.from(document.querySelectorAll("a")).find((a) => a.textContent.trim() === "Dashboard").click()
    JS

    assert_eventually(wait: 15) { @page.reload.subtitle == "Page edit" && block.reload.caption == "Block edit" }
    assert_current_path(/cs-studio\/?\z/, wait: 15)
  end

  # C: a flushed save that was refused stops the action, and says so.
  test "Publish does not run when the save it waited for was refused, and says why" do
    draft = create_page(title: "Draft", published: false)
    visit "/cs-studio/pages/#{draft.id}"
    await_admin_controllers

    fill_in "Title", with: ""
    press "Publish"

    assert_text "Your last change wasn't saved, so this didn't run.", wait: 10
    assert_nil draft.reload.published_at
    assert_equal "Draft", draft.title
    assert_button "Publish"
  end
end
