require "application_system_test_case"

# The promotion hold (`app/javascript/autosave/queue.js`, "THE PROMOTION
# HOLD"). A link into `#content` is a frame navigation that Turbo promotes to
# a page visit once the frame has rendered, and that visit's start stops any
# form submission Turbo's session is running: the POST is done on the server,
# its answer (the redirect, the toast) dropped. From the frame's GET going out
# until the promoted visit has completed, a non-GET submission is therefore
# held and submitted afterwards.
class Admin::PromotionHoldSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    Current.set(actor: users(:one)) do
      @page = create_page(title: "Section")
      @post = create_post(title: "A post")
      Trash::Move.call(@page)
      Trash::Move.call(@post)
    end
    sign_in_via_form(users(:one))
    visit admin_trash_path
    await_admin_controllers
    assert_selector "#trash-page-#{@page.id}"
  end

  test "Restore pressed straight after a tab click, with no wait for the promoted visit, shows its answer" do
    # A raw click, not `click_tab`: nothing waits for `turbo:load` here.
    within("nav[aria-label='Filter by type']") { click_link "Pages" }
    within("#trash-page-#{@page.id}") { press "Restore" }

    assert_selector "[role=status]", text: "Restored “Section”", wait: 10
    assert_no_selector "#trash-page-#{@page.id}"
    assert_not @page.reload.trashed?
  end

  test "Restore pressed while the tab's frame is still being fetched is sent once, after the visit, and its answer rendered" do
    hold_frame_fetches
    count_writes
    # In one script: the press lands on the list that is still showing, with
    # the frame's request on its way.
    page.execute_script(<<~JS, @page.id)
      document.querySelector("nav[aria-label='Filter by type'] a[href*='type=page']").click()
      const button = Array.from(document.querySelectorAll(`#trash-page-${arguments[0]} button`)).find((b) => b.textContent.trim() === "Restore")
      button.click()
      button.click()
    JS
    assert_equal 0, writes, "the held submission was sent during the frame fetch"
    release_frame

    assert_selector "[role=status]", text: "Restored “Section”", wait: 10
    assert_no_selector "#trash-page-#{@page.id}"
    assert_equal 1, writes
    assert_no_selector "#toasts [role=alert]", text: "That didn't go through — the screen changed. Try again."
    assert_selector "nav[aria-label='Filter by type'] a[aria-current=page]", text: "Pages"
    assert_not @page.reload.trashed?
  end

  test "a form whose screen the navigation replaced, with no counterpart on the new one, is dropped unsent" do
    hold_frame_fetches
    count_writes
    # The Posts tab has no row for the page.
    page.execute_script(<<~JS, @page.id)
      document.querySelector("nav[aria-label='Filter by type'] a[href*='type=post']").click()
      Array.from(document.querySelectorAll(`#trash-page-${arguments[0]} button`)).find((b) => b.textContent.trim() === "Restore").click()
    JS

    release_frame
    await_turbo_load

    assert_selector "nav[aria-label='Filter by type'] a[aria-current=page]", text: "Posts"
    assert_selector "#trash-post-#{@post.id}"
    assert_equal 0, writes
    # The button had shown it was taken: the editor is told it wasn't sent.
    assert_selector "#toasts [role=alert]", text: "That didn't go through — the screen changed. Try again.", count: 1
    assert_no_selector "[role=status]", text: "Restored"
    assert @page.reload.trashed?
  end

  test "a dialog's Cancel during a frame fetch closes at once" do
    within("#trash-page-#{@page.id}") { press "Delete now…" }
    assert_selector "dialog[open]"
    hold_frame_fetches
    page.execute_script("document.querySelector(\"nav[aria-label='Filter by type'] a[href*='type=page']\").click()")

    # The frame is still on its way (the test has not let it go): Cancel
    # closes all the same.
    within("dialog[open]") { press "Cancel" }
    assert_no_selector "dialog[open]", wait: 2
    release_frame
    assert_selector "nav[aria-label='Filter by type'] a[aria-current=page]", text: "Pages", wait: 5
    assert @page.reload.trashed?
  end

  # Sign out is a real navigation (`data-turbo="false"`), which no Turbo
  # visit can stop: it is never held, and signs out at once.
  test "Sign out pressed during a frame fetch signs out" do
    hold_frame_fetches
    page.execute_script(<<~JS)
      document.querySelector("nav[aria-label='Filter by type'] a[href*='type=page']").click()
      Array.from(document.querySelectorAll("button")).find((b) => b.textContent.trim() === "Sign out").click()
    JS

    assert_field "Email", wait: 10
    assert_current_path admin_sign_in_path
    assert_equal 0, users(:one).sessions.count
  end

  test "a refused frame form is promoted to nothing, and the next navigator-level submission is not held" do
    visit admin_account_password_path
    await_admin_controllers
    fill_in "Current password", with: "not the password"
    fill_in "New password", with: "a-long-enough-password"
    fill_in "Confirm new password", with: "a-long-enough-password"
    # A `_top` form is submitted the moment the 422 has been rendered into the
    # frame -- where a promoted render would hold it until `turbo:load`.
    page.execute_script(<<~JS)
      document.addEventListener("turbo:frame-render", () => {
        const form = document.createElement("form")
        form.method = "post"
        form.action = "/cs-studio/account/profile"
        form.dataset.turboFrame = "_top"
        form.innerHTML = '<input type="hidden" name="_method" value="patch"><input type="hidden" name="name" value="Not held">'
        document.body.append(form)
        form.requestSubmit()
        window.__heldAfterRefusal = form.hasAttribute("aria-busy")
      }, { once: true })
    JS
    within("#password-form") { press "Change password" }

    assert_text "Name saved.", wait: 5
    assert_equal false, page.evaluate_script("window.__heldAfterRefusal")
    assert_equal "Not held", users(:one).reload.name
  end

  # -- Round 2 (re-review N1, N2, N4, N5, N7) ---------------------------------

  # N1a. Only what `Navigator#stop()` would abort is held. The block picker's
  # buttons are frame-level forms (inside `#content`, no `_top`): held, then
  # stood in for by "the first form with that action", Image became Rich text.
  test "a frame-level form is never held: Image pressed while the page's own tree row loads adds exactly one Image block" do
    about = Current.set(actor: users(:one)) { create_page(title: "About") }
    visit "/cs-studio/pages/#{about.id}"
    await_admin_controllers
    hold_frame_fetches
    page.execute_script(<<~JS, about.id)
      document.querySelector(`li[data-page-id='${arguments[0]}'] a[href*='/pages/${arguments[0]}']`).click()
      const button = Array.from(document.querySelectorAll(".admin-block-picker button")).find((b) => b.textContent.trim() === "Image")
      button.click()
      window.__pickerHeld = button.form.hasAttribute("aria-busy") || button.disabled
    JS

    # Sent at once, with the frame still on its way.
    assert_eventually(message: "no block was added") { about.content_blocks.reload.count >= 1 }
    release_frame
    await_turbo_load
    assert_equal [ "image" ], about.content_blocks.reload.pluck(:block_type)
    assert_equal false, page.evaluate_script("window.__pickerHeld")
    assert_selector ".admin-block-card", count: 1, wait: 5
  end

  # N1b. A `_top` form whose screen was replaced is dropped unless it opted in.
  # The posts list's two bulk forms post to one URL and differ only in a
  # hidden field: the confirmed Move to trash was stood in for by Publish.
  test "a replaced form that did not opt in is dropped: a confirmed bulk Move to trash sends nothing after the list re-renders" do
    draft = Current.set(actor: users(:one)) { create_post(title: "A draft", published: false) }
    visit admin_posts_path
    await_admin_controllers
    find("#select-post-#{draft.id}").click
    within("[data-admin--bulk-select-target=bar]") { press "Move to trash" }
    assert_selector "dialog#bulk-trash-dialog[open]"
    hold_frame_fetches
    count_writes
    page.execute_script(<<~JS)
      const link = document.createElement("a")
      link.href = "/cs-studio/posts?again=1"
      link.textContent = "again"
      document.querySelector("turbo-frame#content").append(link)
      link.click()
      Array.from(document.querySelectorAll("dialog#bulk-trash-dialog button")).find((b) => b.textContent.trim() === "Move to trash").click()
    JS

    release_frame
    await_turbo_load

    assert_current_path(/again=1/, wait: 5)
    assert_selector "tr#post_#{draft.id}"
    assert_equal 0, writes, "a form was submitted in the dropped one's place"
    assert_selector "#toasts [role=alert]", text: "That didn't go through — the screen changed. Try again.", count: 1
    assert_not draft.reload.trashed?
    assert_not draft.live?
  end

  test "an ambiguous stand-in is dropped: two forms with the same action and payload, nothing sent" do
    hold_frame_fetches
    count_writes
    page.execute_script(<<~JS, @page.id)
      document.addEventListener("turbo:frame-render", () => {
        const form = Array.from(document.querySelectorAll(`#trash-page-${arguments[0]} form`)).find((f) => f.textContent.trim() === "Restore")
        document.querySelector("turbo-frame#content").append(form.cloneNode(true))
      }, { once: true })
      document.querySelector("nav[aria-label='Filter by type'] a[href*='type=page']").click()
      Array.from(document.querySelectorAll(`#trash-page-${arguments[0]} button`)).find((b) => b.textContent.trim() === "Restore").click()
    JS

    release_frame
    await_turbo_load

    assert_selector "nav[aria-label='Filter by type'] a[aria-current=page]", text: "Pages"
    assert_equal 0, writes
    assert_selector "#toasts [role=alert]", text: "That didn't go through — the screen changed. Try again.", count: 1
    assert @page.reload.trashed?
  end

  # N2. Backing out of the dialog takes the press back.
  test "Delete pressed in a confirm dialog during a frame fetch and then cancelled deletes nothing" do
    within("#trash-page-#{@page.id}") { press "Delete now…" }
    assert_selector "dialog[open]"
    hold_frame_fetches
    count_writes
    page.execute_script(<<~JS)
      document.querySelector("nav[aria-label='Filter by type'] a[href*='type=page']").click()
      const confirm = Array.from(document.querySelectorAll("dialog[open] button")).find((b) => b.textContent.trim() === "Delete permanently")
      confirm.click()
      window.__busyWhileHeld = confirm.disabled && confirm.getAttribute("aria-busy") === "true" && confirm.querySelector(".admin-spinner") !== null
    JS
    within("dialog[open]") { press "Cancel" }
    assert_no_selector "dialog[open]", wait: 2
    release_frame
    await_turbo_load

    assert_selector "nav[aria-label='Filter by type'] a[aria-current=page]", text: "Pages", wait: 5
    assert_equal 0, writes
    assert Page.exists?(@page.id)
    assert_selector "#trash-page-#{@page.id}"
    # Taken back by the editor: nothing to be told about.
    assert_no_selector "#toasts [role=alert]", text: "That didn't go through — the screen changed. Try again."
    # N4: the press was visibly taken while it waited.
    assert_equal true, page.evaluate_script("window.__busyWhileHeld")
  end

  test "Delete pressed in a confirm dialog during a frame fetch and left alone deletes once" do
    within("#trash-page-#{@page.id}") { press "Delete now…" }
    assert_selector "dialog[open]"
    hold_frame_fetches
    count_writes
    page.execute_script(<<~JS)
      document.querySelector("nav[aria-label='Filter by type'] a[href*='type=page']").click()
      Array.from(document.querySelectorAll("dialog[open] button")).find((b) => b.textContent.trim() === "Delete permanently").click()
    JS
    assert_equal 0, writes
    release_frame

    # The record first, then the screen: the row is also absent for an instant
    # while the frame swaps it, before the held delete has even been sent --
    # asserting "no row" first passed there and then found no write yet.
    assert_eventually(wait: 10, message: "the confirmed delete was never sent") { !Page.exists?(@page.id) }
    assert_no_selector "#trash-page-#{@page.id}", wait: 10
    assert_equal 1, writes
    assert_no_selector "#toasts [role=alert]", text: "That didn't go through — the screen changed. Try again."
  end

  # The two early ends of the fetch window.
  test "a frame fetch that fails releases what was held" do
    hold_frame_fetches(outcome: "fail")
    count_writes
    page.execute_script(<<~JS, @page.id)
      document.querySelector("nav[aria-label='Filter by type'] a[href*='type=post']").click()
      Array.from(document.querySelectorAll(`#trash-page-${arguments[0]} button`)).find((b) => b.textContent.trim() === "Restore").click()
    JS
    assert_equal 0, writes
    release_frame

    assert_selector "[role=status]", text: "Restored “Section”", wait: 10
    assert_equal 1, writes
    assert_not @page.reload.trashed?
    # Turbo rethrows the failed fetch of the frame navigation, unhandled; that
    # is the failure this test provokes.
    expect_js_error(/TypeError: Failed to fetch/)
  end

  test "a frame answer without the frame releases what was held" do
    hold_frame_fetches(outcome: "no_frame")
    count_writes
    page.execute_script(<<~JS, @page.id)
      document.querySelector("nav[aria-label='Filter by type'] a[href*='type=post']").click()
      Array.from(document.querySelectorAll(`#trash-page-${arguments[0]} button`)).find((b) => b.textContent.trim() === "Restore").click()
    JS
    assert_equal 0, writes
    release_frame

    assert_selector "[role=status]", text: "Restored “Section”", wait: 10
    assert_equal 1, writes
    assert_not @page.reload.trashed?
    # Turbo throws on an answer without the frame it asked for; that is the
    # answer this test provokes.
    expect_js_error(/did not contain the expected <turbo-frame id="content">/)
  end

  # Round 3: a non-opted `_top` form inside `#content` whose screen is
  # replaced while it is held is dropped -- and says so.
  test "Publish pressed while the editor's own row reloads is dropped with a toast, and nothing is published" do
    draft = Current.set(actor: users(:one)) { create_page(title: "Draft page", published: false) }
    visit "/cs-studio/pages/#{draft.id}"
    await_admin_controllers
    hold_frame_fetches
    count_writes
    page.execute_script(<<~JS, draft.id)
      document.querySelector(`li[data-page-id='${arguments[0]}'] a[href*='/pages/${arguments[0]}']`).click()
      Array.from(document.querySelectorAll(".admin-editor-header button")).find((b) => b.textContent.trim() === "Publish").click()
    JS
    assert_no_selector "#toasts [role=alert]", text: "That didn't go through — the screen changed. Try again."
    release_frame
    await_turbo_load

    assert_selector "#toasts [role=alert]", text: "That didn't go through — the screen changed. Try again.", count: 1
    assert_equal 0, writes
    assert_not draft.reload.live?
    # The new header's button is a working one.
    assert_selector ".admin-editor-header button:not([disabled])", text: "Publish"
  end

  # `admin--queue-hold` drains first and submits again itself: with both
  # holds in the way the action still runs exactly once. The press is made in
  # the NEW content, between its render and the promoted visit's end -- the
  # header a re-render replaced is gone, and a press on it is dropped.
  test "with the queue's own hold in the way too, Publish pressed straight after the frame render runs once" do
    draft = Current.set(actor: users(:one)) { create_page(title: "Draft page", published: false) }
    visit "/cs-studio/pages/#{draft.id}"
    await_admin_controllers
    page.execute_script(<<~JS, draft.id)
      window.__publishes = 0
      const counted = window.fetch
      window.fetch = (url, options = {}) => {
        if ((options.method || "GET").toUpperCase() !== "GET" && String(url).includes("publish")) window.__publishes += 1
        return counted(url, options)
      }
      document.addEventListener("turbo:frame-render", () => {
        // After the new content's controllers have connected, before `turbo:load`.
        queueMicrotask(() => {
          const subtitle = Array.from(document.querySelectorAll("#content input")).find((input) => /subtitle/.test(input.name))
          subtitle.value = "Typed just before publishing"
          subtitle.dispatchEvent(new Event("input", { bubbles: true }))
          const publish = Array.from(document.querySelectorAll(".admin-editor-header button")).find((b) => b.textContent.trim() === "Publish")
          publish.click()
          window.__publishHeld = publish.form.hasAttribute("aria-busy")
        })
      }, { once: true })
      document.querySelector(`li[data-page-id='${arguments[0]}'] a[href*='/pages/${arguments[0]}']`).click()
    JS

    assert_eventually(wait: 12, message: "the page was never published") { draft.reload.live? }
    # The redirect's page has arrived: nothing more can be sent from the old one.
    assert_selector ".admin-editor-header", text: /live|View on site/i, wait: 10
    assert_equal true, page.evaluate_script("window.__publishHeld")
    assert_equal 1, page.evaluate_script("window.__publishes")
    assert_equal "Typed just before publishing", draft.reload.subtitle
  end

  private

  # Every `#content` frame GET waits until the test lets it go
  # (`release_frame`), so nothing a test asserts in between races a timer.
  # Then it is answered for real, or fails ("fail"), or is answered with a
  # document that has no such frame ("no_frame").
  def hold_frame_fetches(outcome: "answer")
    page.execute_script(<<~JS, outcome)
      const real = window.fetch
      const outcome = arguments[0]
      window.__frameGate = new Promise((resolve) => { window.__releaseFrame = resolve })
      window.__loads = 0
      document.addEventListener("turbo:load", () => { window.__loads += 1 })
      window.fetch = async (url, options = {}) => {
        const headers = new Headers(options.headers || {})
        if (headers.get("Turbo-Frame") !== "content" || (options.method || "GET").toUpperCase() !== "GET") return real(url, options)
        await window.__frameGate
        if (outcome === "fail") throw new TypeError("Failed to fetch")
        if (outcome === "no_frame") {
          const response = new Response("<html><head></head><body><p>No frame here</p></body></html>", { status: 200, headers: { "Content-Type": "text/html; charset=utf-8" } })
          Object.defineProperty(response, "url", { value: String(url) })
          return response
        }
        return real(url, options)
      }
    JS
  end

  def release_frame = page.execute_script("window.__releaseFrame()")

  # The promoted visit is over; the hold has released or dropped what it held
  # (its own `turbo:load` listener was added first and has run).
  def await_turbo_load
    assert_eventually(message: "the promoted visit never finished (no turbo:load)") { page.evaluate_script("window.__loads > 0") }
  end

  def writes = page.evaluate_script("window.__writes")

  def count_writes
    page.execute_script(<<~JS)
      window.__writes = 0
      const counted = window.fetch
      window.fetch = (url, options = {}) => {
        if ((options.method || "GET").toUpperCase() !== "GET") window.__writes += 1
        return counted(url, options)
      }
    JS
  end
end
