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

  # Counts the writes on the wire and keeps every write's answer status. It
  # lives on `window`, which a Turbo render keeps, so it still reports after
  # the page was replaced.
  WATCH_WRITES = <<~JS
    const watchedFetch = window.fetch
    window.__inFlight = 0
    window.__statuses = []
    window.__renders = 0
    window.fetch = async (url, options = {}) => {
      const write = (options.method || "GET").toUpperCase() !== "GET"
      if (write) window.__inFlight += 1
      try {
        const response = await watchedFetch(url, options)
        if (write) window.__statuses.push(response.status)
        return response
      } finally {
        if (write) window.__inFlight -= 1
      }
    }
    document.addEventListener("turbo:render", () => { window.__renders += 1 })
  JS

  # Publish waits for the queue: an edit still queued behind another form's
  # request is saved first, and the action then runs on the fresh state.
  #
  # It is also the regression test for a false "Changed elsewhere" (fix round
  # 4): the Subtitle field keeps focus through Publish, and as Turbo replaces
  # the page the outgoing field gets a `focusout` -- right AFTER
  # `turbo:before-render`. That used to queue one more save of the old form,
  # on the base Publish had just moved, counted as the NEW page's: a 409 whose
  # bar was drawn into the new document. Nothing may be sent at all here (the
  # form has nothing unsaved), so the test waits for the new page and for the
  # wire to be quiet, then looks at every write's status -- not just at the
  # text a few milliseconds after the redirect, which only caught it one run
  # in six.
  test "pressing Publish right after typing saves the typed value and publishes, with no conflict" do
    draft = create_page(title: "Draft", published: false)
    block = draft.content_blocks.create!(block_type: :image, position: 0)
    visit "/cs-studio/pages/#{draft.id}"
    await_admin_controllers
    page.execute_script(WATCH_WRITES)

    fill_in id: "block-#{block.id}-caption", with: "A caption"
    fill_in "Subtitle", with: "Typed just before Publish"
    assert_equal "page-subtitle", page.evaluate_script("document.activeElement.id"), "the field must still hold focus when Publish is pressed"
    press "Publish"

    assert_eventually { draft.reload.published_at.present? }
    assert_eventually { page.evaluate_script("window.__renders > 0 && window.__inFlight === 0") }
    sleep 0.5 # a stream answer is drawn on the next frame
    assert_equal "Typed just before Publish", draft.subtitle
    assert_equal "A caption", block.reload.caption
    assert_not_includes page.evaluate_script("window.__statuses"), 409, "a save was refused as stale"
    assert_no_text "CHANGED ELSEWHERE"
    assert_no_selector "#changed-elsewhere"
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

  # The rule holds for a Turbo FRAME navigation inside `#content` too (final
  # fix wave 1, review B I2): the page tree's links, the header's breadcrumb
  # and its menu's Activity link render the frame BEFORE any
  # `turbo:before-visit`, so the drain hangs on `turbo:before-frame-render`.
  #
  # Scenario A: an edit typed while the same form's save is in flight, then a
  # tree link. The follow-up used to be skipped (the form had left the
  # document when its first save was answered) -- "second" was lost silently.
  # The frame's page is also fetched ONCE (review B M1): the promoted visit
  # used to be intercepted by the still-busy queue and issued again.
  test "an edit typed while a save is in flight is saved before a tree link replaces the editor, which loads once" do
    other = create_page(title: "Other")
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    page.execute_script(SLOW_PATCHES)
    page.execute_script(<<~JS)
      const countedFetch = window.fetch
      window.__gets = []
      window.fetch = (url, options = {}) => {
        if ((options.method || "GET").toUpperCase() === "GET") window.__gets.push(new URL(String(url.url || url), location.href).pathname)
        return countedFetch(url, options)
      }
    JS

    fill_in "Subtitle", with: "first"
    page.execute_script("document.activeElement.blur()") # the save for "first" goes out, and is slow
    fill_in "Subtitle", with: "second, typed while that save is in flight"
    find("li[data-page-id='#{other.id}'] a", text: "Other").click

    assert_field "Title", with: "Other", wait: 15
    assert_eventually(wait: 10) { @page.reload.subtitle == "second, typed while that save is in flight" }
    sleep 1 # a second fetch of the page would have gone out by now
    assert_equal 1, page.evaluate_script("window.__gets").count("/cs-studio/pages/#{other.id}"), "the tree link's page was fetched more than once"
    assert_no_text "CHANGED ELSEWHERE"

    # The editor that came in saves on its own base.
    await_admin_controllers
    fill_in "Subtitle", with: "Typed on the next page"
    assert_eventually { other.reload.subtitle == "Typed on the next page" }
    assert_no_text "CHANGED ELSEWHERE"
  end

  # Scenario B: a value written by code with focus outside the form ("Use
  # all"), then a frame link inside the 1 s debounce -- no `focusout` ever
  # sends it, and the form's disconnect used to clear the timer. Through the
  # header's breadcrumb, which is a frame link like the tree's.
  test "a debounced edit is saved before a breadcrumb link replaces the editor" do
    child = create_page(title: "Child", parent: @page)
    visit "/cs-studio/pages/#{child.id}"
    await_admin_controllers

    page.execute_script(<<~JS)
      const field = document.getElementById("page-subtitle")
      field.value = "Set like Use all"
      field.dispatchEvent(new Event("input", { bubbles: true }))
      Array.from(document.querySelectorAll("nav[aria-label=Breadcrumb] a")).find((a) => a.textContent.trim() === "About").click()
    JS

    assert_field "Title", with: "About", wait: 15
    assert_eventually { child.reload.subtitle == "Set like Use all" }
    assert_no_text "CHANGED ELSEWHERE"
  end

  # ...and through a tree link.
  test "a debounced edit is saved before a tree link replaces the editor" do
    other = create_page(title: "Other")
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    page.execute_script(<<~JS)
      const field = document.getElementById("page-subtitle")
      field.value = "Set like Use all"
      field.dispatchEvent(new Event("input", { bubbles: true }))
      document.querySelector('li[data-page-id="#{other.id}"] a').click()
    JS

    assert_field "Title", with: "Other", wait: 15
    assert_eventually { @page.reload.subtitle == "Set like Use all" }
  end

  # A form belongs to the document it was rendered into, and that document is
  # replaced only when the body (or the `#content` frame's content) really is
  # (final fix wave 1). Turbo fires `turbo:before-render` a SECOND time, for a
  # visit that renders nothing, after a redirected visit (the sidebar's Pages
  # link answers with a redirect to Home's editor) and after a frame
  # navigation is promoted to a visit (a tree link). Counting those as page
  # changes left the editor that had just come in a generation behind for
  # good: every answer was thrown away as "stale", so the status line stuck on
  # "SAVING…", no base was ever written back, and the second edit was refused
  # (409) without a word.
  test "an editor reached through the sidebar's redirected Pages link shows its saves and keeps saving" do
    visit admin_root_path
    await_admin_controllers
    within("nav[aria-label='Modules']") { click_link "Pages" }
    assert_field "Title", with: root_page.title, wait: 10
    await_admin_controllers

    assert_saves_twice(root_page)
  end

  test "an editor reached through a tree link shows its saves and keeps saving" do
    other = create_page(title: "Other")
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    find("li[data-page-id='#{other.id}'] a", text: "Other").click
    assert_field "Title", with: "Other", wait: 10
    await_admin_controllers

    assert_saves_twice(other)
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

  # A save belongs to the page its form was rendered on (fix round 4). Back
  # is a restoration visit: nothing drains first, and the outgoing field's
  # `focusout` queues its save as the page is torn down. That save is still
  # sent -- here it is refused, the record having changed elsewhere -- but its
  # answer must not be drawn into the page that comes back, which has a status
  # line and a notice slot with the very same ids.
  test "a save sent as its page is left with Back draws nothing into the page that comes back" do
    other = create_page(title: "Other", parent: @page)
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    page.execute_script(WATCH_WRITES)
    page.execute_script("Turbo.visit(#{"/cs-studio/pages/#{other.id}".to_json})")
    assert_field "Title", with: "Other"
    await_admin_controllers

    as(users(:two), channel: :admin) { Pages::Save.call(other, translations: { "en" => { subtitle: "The other editor's text" } }) }
    fill_in "Subtitle", with: "Typed, then Back"
    page.go_back

    assert_field "Title", with: "About"
    assert_eventually { page.evaluate_script("window.__statuses.includes(409) && window.__inFlight === 0") }
    sleep 0.5 # a stream answer is drawn on the next frame
    assert_no_text "CHANGED ELSEWHERE"
    assert_no_selector "#changed-elsewhere"
    assert_equal "The other editor's text", other.reload.subtitle
  end

  # The drain is bounded as a whole (fix round 4): a save that never answers
  # holds a visit for `DRAIN_LIMIT_MS` (10 s), not for as long as it hangs.
  test "a save that never answers holds a sidebar link for the drain's limit, no longer" do
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.fetch = (url, options = {}) =>
        (options.method || "GET").toUpperCase() === "PATCH" ? new Promise(() => {}) : originalFetch(url, options)
    JS

    fill_in "Subtitle", with: "Never answered"
    page.execute_script("document.activeElement.blur()")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    page.execute_script(<<~JS)
      Array.from(document.querySelectorAll("a")).find((a) => a.textContent.trim() === "Dashboard").click()
    JS

    assert_current_path(/cs-studio\/?\z/, wait: 14)
    waited = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_operator waited, :>, 8, "the visit did not wait for the save at all"
    assert_operator waited, :<, 14
  end

  # After a save was given up on, nothing is "about to be sent" any more, even
  # when an edit was typed during the backoff: a visit leaves at once instead
  # of waiting out the drain for a save nobody is going to send.
  test "after a save was given up on, a sidebar link leaves at once" do
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    page.execute_script(<<~JS)
      const form = document.getElementById("page-subtitle").closest("form")
      window.Stimulus.getControllerForElementAndIdentifier(form, "admin--autosave").constructor.retryDelays = [ 2000, 100, 100 ]
      const originalFetch = window.fetch
      window.fetch = (url, options = {}) =>
        (options.method || "GET").toUpperCase() === "PATCH" ? Promise.reject(new TypeError("offline")) : originalFetch(url, options)
    JS

    fill_in "Subtitle", with: "first"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#page-save-status", text: "NOT SAVED · RETRYING…"
    fill_in "Subtitle", with: "second, typed during the backoff"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#page-save-status button", text: "Retry", wait: 8

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    page.execute_script(<<~JS)
      Array.from(document.querySelectorAll("a")).find((a) => a.textContent.trim() === "Dashboard").click()
    JS
    assert_current_path(/cs-studio\/?\z/, wait: 14)
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 4, "the visit waited for a save that was given up on"
  end

  # The refusal is an error toast, and a modal dialog is drawn above the
  # toasts: the dialog the action was confirmed in closes, so the sentence can
  # be read.
  test "Move to trash does not run when the save it waited for was refused: its dialog closes and says why" do
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    fill_in "Title", with: ""
    open_editor_menu
    press "Move to trash"
    within("dialog#delete-page-#{@page.id}[open]") { press "Move to trash" }

    assert_text "Your last change wasn't saved, so this didn't run.", wait: 10
    assert_no_selector "dialog[open]"
    assert_not @page.reload.trashed?
    assert_equal "About", @page.title
  end

  # The redirect that answers a header action is not held by the queue, even
  # when an edit landed while the action was on its way: held, it was fetched
  # a second time, and the flash -- here the Undo toast -- was spent on the
  # first.
  test "an edit landing while Move to trash is on its way does not cost the Undo toast" do
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    open_editor_menu
    press "Move to trash"
    assert_selector "dialog#delete-page-#{@page.id}[open]"
    # One tick: the confirmed submission goes out, then an edit starts its
    # debounce -- still outstanding when the redirect is answered.
    page.execute_script(<<~JS)
      document.querySelector("dialog[open] form[method=post] button[type=submit]").click()
      const field = document.getElementById("page-subtitle")
      field.value = "Typed as the page left"
      field.dispatchEvent(new Event("input", { bubbles: true }))
    JS

    # /pages answers with a second redirect, to Home's editor; the flash is
    # kept across that hop, so the Undo toast is still there.
    assert_current_path(admin_page_path(root_page), wait: 10)
    assert_selector "#toasts button", text: "Undo"
    assert @page.reload.trashed?

    # ...and spent exactly once: the next navigation shows no toast.
    visit admin_root_path
    assert_no_selector "#toasts .admin-toast"
  end

  private

  # Two saves in a row from the page settings form: the first has to draw its
  # answer (the status line), the second is only accepted when the first
  # answer's base was written back.
  def assert_saves_twice(record)
    fill_in "Subtitle", with: "one"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#page-save-status", text: /SAVED( TO SITE)? \d{2}:\d{2}\z/, wait: 8
    fill_in "Subtitle", with: "two"
    page.execute_script("document.activeElement.blur()")
    assert_eventually { record.reload.subtitle == "two" }
    assert_selector "#page-save-status", text: /SAVED( TO SITE)? \d{2}:\d{2}\z/, wait: 8
    assert_no_text "CHANGED ELSEWHERE"
  end
end
