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
    slow_frame_fetches(600)
    count_writes
    # In one script: the press lands on the list that is still showing, with
    # the frame's request on its way.
    page.execute_script(<<~JS, @page.id)
      document.querySelector("nav[aria-label='Filter by type'] a[href*='type=page']").click()
      const button = Array.from(document.querySelectorAll(`#trash-page-${arguments[0]} button`)).find((b) => b.textContent.trim() === "Restore")
      button.click()
      button.click()
    JS
    assert_equal 0, page.evaluate_script("window.__writes"), "the held submission was sent during the frame fetch"

    assert_selector "[role=status]", text: "Restored “Section”", wait: 10
    assert_no_selector "#trash-page-#{@page.id}"
    assert_equal 1, page.evaluate_script("window.__writes")
    assert_selector "nav[aria-label='Filter by type'] a[aria-current=page]", text: "Pages"
    assert_not @page.reload.trashed?
  end

  test "a form whose screen the navigation replaced, with no counterpart on the new one, is dropped unsent" do
    slow_frame_fetches(400)
    count_writes
    # The Posts tab has no row for the page.
    page.execute_script(<<~JS, @page.id)
      document.querySelector("nav[aria-label='Filter by type'] a[href*='type=post']").click()
      Array.from(document.querySelectorAll(`#trash-page-${arguments[0]} button`)).find((b) => b.textContent.trim() === "Restore").click()
    JS

    assert_selector "nav[aria-label='Filter by type'] a[aria-current=page]", text: "Posts"
    assert_selector "#trash-post-#{@post.id}"
    sleep 0.7
    assert_equal 0, page.evaluate_script("window.__writes")
    assert_no_selector "[role=status]", text: "Restored"
    assert @page.reload.trashed?
  end

  test "a dialog's Cancel during a frame fetch closes at once" do
    within("#trash-page-#{@page.id}") { press "Delete now…" }
    assert_selector "dialog[open]"
    slow_frame_fetches(1500)
    page.execute_script("document.querySelector(\"nav[aria-label='Filter by type'] a[href*='type=page']\").click()")

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    within("dialog[open]") { press "Cancel" }
    assert_no_selector "dialog[open]", wait: 1
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1.2, "Cancel waited for the frame"
    assert_selector "nav[aria-label='Filter by type'] a[aria-current=page]", text: "Pages", wait: 5
    assert @page.reload.trashed?
  end

  test "Sign out pressed during a frame fetch signs out" do
    slow_frame_fetches(600)
    page.execute_script(<<~JS)
      document.querySelector("nav[aria-label='Filter by type'] a[href*='type=page']").click()
      Array.from(document.querySelectorAll("button")).find((b) => b.textContent.trim() === "Sign out").click()
    JS

    assert_field "Email", wait: 10
    assert_current_path admin_sign_in_path
    assert_equal 0, users(:one).sessions.count
  end

  test "a refused frame form is promoted to nothing, and the next press is not held" do
    visit admin_account_password_path
    await_admin_controllers
    fill_in "Current password", with: "not the password"
    fill_in "New password", with: "a-long-enough-password"
    fill_in "Confirm new password", with: "a-long-enough-password"
    # Sign out is pressed the moment the 422 has been rendered into the frame
    # -- where a promoted render would hold it until `turbo:load`.
    page.execute_script(<<~JS)
      document.addEventListener("turbo:frame-render", () => {
        const button = Array.from(document.querySelectorAll("button")).find((b) => b.textContent.trim() === "Sign out")
        button.click()
        window.__heldAfterRefusal = button.form.hasAttribute("aria-busy")
      }, { once: true })
    JS
    within("#password-form") { press "Change password" }

    # Not held: it went straight on, to the leave guard of the refused form.
    assert_selector "dialog#leave-dialog[open]", wait: 5
    assert_equal false, page.evaluate_script("window.__heldAfterRefusal")
    within("dialog#leave-dialog") { press "Discard changes" }
    assert_field "Email", wait: 5
    assert_current_path admin_sign_in_path
    assert_equal 0, users(:one).sessions.count
  end

  private

  # Every `#content` frame GET answers `ms` late.
  def slow_frame_fetches(ms)
    page.execute_script(<<~JS, ms)
      const real = window.fetch
      window.fetch = async (url, options = {}) => {
        const headers = new Headers(options.headers || {})
        if (headers.get("Turbo-Frame") === "content" && (options.method || "GET").toUpperCase() === "GET") await new Promise((resolve) => setTimeout(resolve, arguments[0]))
        return real(url, options)
      }
    JS
  end

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
