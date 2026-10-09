require "application_system_test_case"

# The explicit-save footer and the Leave dialog in a real browser (cs-studio
# design pass, Task 11; round 3, Task 1): the footer is always there with Save
# and Cancel, counts changed fields against what was loaded, keeps Save
# disabled while an existing record has nothing to save, and leaving with
# changes asks first -- by a sidebar link (a Turbo visit), by a link inside
# the content frame (a frame navigation) and by the browser's Back. The
# footer's own Cancel is the one way out that never asks.
class SaveBarSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @owner = users(:one)
    @target = users(:two)
  end

  # The edit screen reached the way an editor reaches it: by the list's Edit
  # link, a frame navigation that adds a history entry -- so Back from it stays
  # inside the document. It waits for the visit that navigation is promoted to
  # (`click_frame_link`): a test pressing Back before Turbo has finished
  # arriving is racing Turbo itself, whose late promoted visit cancels the
  # restoration.
  def open_edit_from_the_list
    visit admin_users_path
    await_admin_controllers
    click_frame_link { within("##{ActionView::RecordIdentifier.dom_id(@target)}") { click_link @target.email_address } }
    assert_current_path edit_admin_user_path(@target)
    assert_selector ".admin-save-bar", text: /No unsaved changes/i
  end

  test "the footer is always there, counts changes, disables Save when nothing changed, and guards leaving" do
    sign_in_via_form(@owner)
    visit edit_admin_user_path(@target)
    await_admin_controllers

    # An existing record with nothing changed: Save and Cancel are on screen,
    # Save can't be pressed, and the footer says why.
    assert_selector ".admin-save-bar", text: /No unsaved changes/i
    assert_selector ".admin-save-bar a", text: "Cancel"
    assert_selector ".admin-save-bar button[type=submit][disabled]", text: "Save"

    original = find_field("Name").value
    fill_in "Name", with: "#{original}x"
    assert_selector ".admin-save-bar", text: /1 unsaved change/i
    assert_selector ".admin-save-bar button[type=submit]:not([disabled])", text: "Save"

    fill_in "Name", with: original
    assert_selector ".admin-save-bar", text: /No unsaved changes/i
    assert_selector ".admin-save-bar button[type=submit][disabled]"

    fill_in "Name", with: "Typed again"
    assert_selector ".admin-save-bar", text: /1 unsaved change/i

    within("nav[aria-label='Modules']") { click_link "Posts" }
    assert_selector "dialog#leave-dialog[open]"
    within("dialog#leave-dialog") do
      assert_text "Leave without saving?"
      assert_text "You have 1 unsaved change on this screen."
      press "Keep editing"
    end
    assert_no_selector "dialog#leave-dialog[open]"
    assert_current_path edit_admin_user_path(@target)
    assert_equal "Typed again", find_field("Name").value

    within("nav[aria-label='Modules']") { click_link "Posts" }
    assert_selector "dialog#leave-dialog[open]"
    within("dialog#leave-dialog") { press "Discard changes" }
    assert_current_path admin_posts_path
  end

  # "Keep editing" is where focus lands, so Enter by reflex keeps the text.
  test "the Leave dialog puts focus on Keep editing" do
    sign_in_via_form(@owner)
    visit edit_admin_user_path(@target)
    await_admin_controllers
    fill_in "Name", with: "Focus"
    within("nav[aria-label='Modules']") { click_link "Posts" }
    assert_selector "dialog#leave-dialog[open]"
    assert_equal "Keep editing", page.evaluate_script("document.activeElement.textContent.trim()")
  end

  # A link inside `#content` is a Turbo FRAME navigation: no
  # `turbo:before-visit` until the frame has already been replaced. The
  # edit-user screen's own Activity link breaks out to `_top`; here it is put
  # back into the frame, which is what any link in the content area is unless
  # it says otherwise.
  test "a link inside the content frame asks first, and works again after Keep editing" do
    sign_in_via_form(@owner)
    visit edit_admin_user_path(@target)
    await_admin_controllers
    page.execute_script("Array.from(document.querySelectorAll('#content a')).find((a) => a.textContent.trim() === 'Activity').removeAttribute('data-turbo-frame')")

    fill_in "Name", with: "Typed in the frame"
    click_link "Activity"
    assert_selector "dialog#leave-dialog[open]"
    within("dialog#leave-dialog") { press "Keep editing" }
    assert_no_selector "dialog#leave-dialog[open]"
    assert_current_path edit_admin_user_path(@target)
    assert_equal "Typed in the frame", find_field("Name").value
    # Nothing was left half-started: the frame isn't busy and has not been
    # pointed anywhere.
    assert_no_selector "turbo-frame#content[busy]"
    assert_no_selector "turbo-frame#content[src]"

    click_link "Activity"
    assert_selector "dialog#leave-dialog[open]"
    within("dialog#leave-dialog") { press "Discard changes" }
    assert_no_selector "dialog#leave-dialog[open]"
    assert_current_path admin_audit_events_path, ignore_query: true
    assert_no_field "Name"
  end

  # Back is a restoration visit, which fires no `turbo:before-visit`.
  #
  # This is also the test that says so when a Turbo upgrade breaks the guard
  # (`turbo-rails` is pinned in the Gemfile for that reason). It rests on three
  # Turbo internals -- `history.state.turbo.restorationIndex`,
  # `Turbo.session.history.currentIndex` and `Turbo.session.history.onPopState`
  # -- and with any one of them gone the guard stands back and the first
  # "dialog is open" below fails (each was taken away in turn to check).
  test "Back with a typed change asks first; Keep editing leaves the URL and the form as they were" do
    sign_in_via_form(@owner)
    open_edit_from_the_list

    fill_in "Name", with: "Typed before Back"
    page.execute_script("history.back()")
    assert_selector "dialog#leave-dialog[open]"
    within("dialog#leave-dialog") { press "Keep editing" }
    assert_no_selector "dialog#leave-dialog[open]"
    assert_current_path edit_admin_user_path(@target)
    assert_equal "Typed before Back", find_field("Name").value

    # The history is as it was: Back still leads to the list, once asked.
    page.execute_script("history.back()")
    assert_selector "dialog#leave-dialog[open]"
    within("dialog#leave-dialog") { press "Discard changes" }
    assert_current_path admin_users_path
    assert_no_field "Name"
    assert_no_selector "dialog#leave-dialog[open]"
  end

  # A screen opened by a link in the content frame is rendered first, and only
  # then does Turbo propose the visit that navigation is promoted to -- to the
  # screen's own URL (`turbo:frame-render` on `#content`, then
  # `turbo:before-visit`). A change made in between once made the guard take
  # the promoted visit for a way out and ask about the screen that had just
  # opened. The real gap is a few milliseconds wide, so the two events are
  # replayed here by hand, with the change already typed: the visit that
  # follows the frame's render is let through, once -- the same visit again is
  # a way out like any other.
  # Being replayed, it would still pass if Turbo stopped sending these two
  # events in this order: on a Turbo upgrade, check that by hand as well
  # (`FrameController#proposeVisitIfNavigatedWithAction`).
  test "the visit a frame navigation is promoted to is let through, once" do
    sign_in_via_form(@owner)
    open_edit_from_the_list
    fill_in "Name", with: "Typed at once"
    assert_selector ".admin-save-bar", text: /1 unsaved change/i

    propose = <<~JS
      (() => {
        const frame = document.getElementById("content")
        if (arguments[0]) frame.dispatchEvent(new CustomEvent("turbo:frame-render", { bubbles: true }))
        const visit = new CustomEvent("turbo:before-visit", { bubbles: true, cancelable: true, detail: { url: frame.src } })
        document.dispatchEvent(visit)
        return visit.defaultPrevented
      })()
    JS
    assert_equal false, page.evaluate_script(propose, true), "the promoted visit was stopped"
    assert_no_selector "dialog#leave-dialog[open]"

    assert_equal true, page.evaluate_script(propose, false), "a later visit to the same URL was not asked about"
    assert_selector "dialog#leave-dialog[open]"
    within("dialog#leave-dialog") { press "Keep editing" }
    assert_equal "Typed at once", find_field("Name").value
  end

  # `to - from`, the other way and by more than one entry.
  test "Forward with a typed change asks first, and Discard goes forward" do
    sign_in_via_form(@owner)
    open_edit_from_the_list
    within("nav[aria-label='Modules']") { click_link "Posts" }
    assert_current_path admin_posts_path
    assert_no_field "Name"
    page.execute_script("history.back()")
    assert_current_path edit_admin_user_path(@target)
    assert_selector ".admin-save-bar", text: /No unsaved changes/i
    await_admin_controllers

    fill_in "Name", with: "Typed before Forward"
    page.execute_script("history.forward()")
    assert_selector "dialog#leave-dialog[open]"
    within("dialog#leave-dialog") { press "Keep editing" }
    assert_no_selector "dialog#leave-dialog[open]"
    assert_current_path edit_admin_user_path(@target)
    assert_equal "Typed before Forward", find_field("Name").value

    page.execute_script("history.forward()")
    assert_selector "dialog#leave-dialog[open]"
    within("dialog#leave-dialog") { press "Discard changes" }
    assert_current_path admin_posts_path
    assert_no_field "Name"
  end

  test "Back by two entries asks first, and Discard goes back by two" do
    sign_in_via_form(@owner)
    visit admin_groups_path
    await_admin_controllers
    click_frame_link { within("nav[aria-label='Modules']") { click_link "Users" } }
    assert_current_path admin_users_path
    click_frame_link { within("##{ActionView::RecordIdentifier.dom_id(@target)}") { click_link @target.email_address } }
    assert_current_path edit_admin_user_path(@target)
    assert_selector ".admin-save-bar", text: /No unsaved changes/i

    fill_in "Name", with: "Typed before going back two"
    page.execute_script("history.go(-2)")
    assert_selector "dialog#leave-dialog[open]"
    within("dialog#leave-dialog") { press "Keep editing" }
    assert_no_selector "dialog#leave-dialog[open]"
    assert_current_path edit_admin_user_path(@target)
    assert_equal "Typed before going back two", find_field("Name").value

    page.execute_script("history.go(-2)")
    assert_selector "dialog#leave-dialog[open]"
    within("dialog#leave-dialog") { press "Discard changes" }
    assert_current_path admin_groups_path
    assert_no_field "Name"
  end

  # A dialog's `close` event is dispatched a task after it closes, so the one
  # from "Keep editing" can arrive when the dialog is already open again. It
  # once disarmed that second opening's Discard, which then did nothing.
  # Replayed by hand: a `close` event while the dialog is open.
  test "a close event left over from an earlier opening doesn't disarm Discard" do
    sign_in_via_form(@owner)
    open_edit_from_the_list
    fill_in "Name", with: "Typed"
    page.execute_script("history.back()")
    assert_selector "dialog#leave-dialog[open]"
    page.execute_script("document.getElementById('leave-dialog').dispatchEvent(new Event('close'))")
    within("dialog#leave-dialog") { press "Discard changes" }
    assert_current_path admin_users_path
    assert_no_field "Name"
  end

  # A `popstate` for the entry the form is already on (the guard's own undo
  # arriving too late to be recognised; a fragment entry of the same page):
  # nothing is being left, so nobody asks -- and Turbo must not answer it with
  # a restoration visit, which would fetch the form again over the typed text.
  test "a popstate for the entry the form is on neither asks nor reloads the form" do
    sign_in_via_form(@owner)
    open_edit_from_the_list
    fill_in "Name", with: "Typed"
    page.execute_script(<<~JS)
      document.getElementById("user-form").dataset.sameForm = "yes"
      document.addEventListener("turbo:visit", () => { window.restorationStarted = true })
      window.dispatchEvent(new PopStateEvent("popstate", { state: history.state }))
    JS
    await_frames # the popstate listeners have run; a restoration visit would have started `turbo:visit` by now
    assert_no_selector "dialog#leave-dialog[open]"
    assert_nil page.evaluate_script("window.restorationStarted")
    assert_selector "#user-form[data-same-form=yes]"
    assert_equal "Typed", find_field("Name").value
  end

  # The error summary's links are `#field` links inside the content frame, and
  # the summary only exists after a refused save -- when the form is unsaved.
  # Turbo takes such a link for a frame navigation (it compares the absolute
  # `href`), so the guard asked "Leave without saving?", and Discard fetched
  # the form again without the typed values or the errors. It is a jump within
  # the page: nobody asks, nothing is fetched -- and no history entry is made.
  # (Left to the browser, the jump added a `#field` entry Turbo knew nothing
  # of; Back to it after a successful save showed the users LIST under the
  # form's URL.)
  test "an error summary's link moves focus to its field without asking and without a history entry" do
    sign_in_via_form(@owner)
    visit admin_users_path
    await_admin_controllers
    click_frame_link "New user"
    assert_current_path new_admin_user_path
    await_admin_controllers

    fill_in "Email address", with: @target.email_address
    fill_in "Password", with: "a much Longer passw0rd"
    fill_in "Confirm password", with: "a much Longer passw0rd"
    press "Create user"
    assert_selector ".admin-error-summary a[href='#user_email_address']", wait: 10
    await_admin_controllers
    entries = page.evaluate_script("history.length")
    page.execute_script("document.getElementById('user-form').dataset.sameForm = 'yes'")

    find(".admin-error-summary a[href='#user_email_address']").click
    assert_eventually(message: "focus never reached the field") { page.evaluate_script("document.activeElement.id") == "user_email_address" }
    assert_equal "", page.evaluate_script("location.hash")
    assert_equal entries, page.evaluate_script("history.length")
    assert_no_selector "dialog#leave-dialog[open]"
    assert_selector "#user-form[data-same-form=yes]"
    assert_selector ".admin-error-summary"
    assert_equal @target.email_address, find_field("Email address").value

    # Saved after all, then Back: the form's URL shows the form.
    fill_in "Email address", with: "someone.new@example.com"
    fill_in "Password", with: "a much Longer passw0rd"
    fill_in "Confirm password", with: "a much Longer passw0rd"
    # The answer redirects inside the frame and is promoted to a visit like a
    # link's: Back is pressed only once that visit is over (`turbo:load`), not
    # after a guessed pause.
    click_frame_link { press "Create user" }
    assert_text "User created"
    assert_selector "h1", text: "someone.new@example.com"
    page.execute_script("history.back()")
    assert_current_path new_admin_user_path
    assert_equal "", page.evaluate_script("location.hash")
    assert_field "Email address"
    assert_selector ".admin-save-bar button[type=submit]", text: "Create user"
  end

  # The same on a form with nothing unsaved: focus moves, the history doesn't,
  # so a change typed afterwards and Back ask about leaving for the PREVIOUS
  # screen, one step away as ever. A target that can't take focus is made able
  # to (`tabindex="-1"`, as a skip link's target is).
  test "a fragment link on a clean form adds no history entry, and Back still leaves for the previous screen" do
    sign_in_via_form(@owner)
    open_edit_from_the_list
    page.execute_script(<<~JS)
      document.getElementById("user-form").insertAdjacentHTML("beforebegin",
        '<a id="jump-field" href="#user_email_address">To the email</a> <a id="jump-text" href="#user_name_help">To the help</a>')
    JS
    entries = page.evaluate_script("history.length")

    find("#jump-text").click
    assert_eventually(message: "focus never reached the paragraph") { page.evaluate_script("document.activeElement.id") == "user_name_help" }
    find("#jump-field").click
    assert_eventually(message: "focus never reached the field") { page.evaluate_script("document.activeElement.id") == "user_email_address" }
    assert_equal "", page.evaluate_script("location.hash")
    assert_equal entries, page.evaluate_script("history.length")
    assert_no_selector "dialog#leave-dialog[open]"
    assert_selector ".admin-save-bar", text: /No unsaved changes/i

    fill_in "Name", with: "Typed after the jump"
    page.execute_script("history.back()")
    assert_selector "dialog#leave-dialog[open]"
    within("dialog#leave-dialog") { press "Discard changes" }
    assert_current_path admin_users_path
    assert_no_field "Name"
  end

  # Deferred g1-g3: the keyboard follows such a link the same way, and a link
  # whose target isn't on the screen (or whose hash can't be decoded) is still
  # no navigation -- nothing is fetched, nothing asked, no history entry.
  test "Enter on a fragment link jumps too, and a missing or malformed target goes nowhere" do
    sign_in_via_form(@owner)
    open_edit_from_the_list
    page.execute_script(<<~JS)
      document.getElementById("user-form").insertAdjacentHTML("beforebegin",
        '<a id="jump-field" href="#user_email_address">To the email</a> <a id="jump-nowhere" href="#no_such_field">Nowhere</a> <a id="jump-broken" href="#%E0%A4%A">Broken</a>')
      document.getElementById("user-form").dataset.sameForm = "yes"
    JS
    fill_in "Name", with: "Typed before the jumps"
    entries = page.evaluate_script("history.length")

    page.execute_script("document.getElementById('jump-field').focus()")
    page.driver.browser.keyboard.type(:Enter)
    assert_eventually(message: "focus never reached the field") { page.evaluate_script("document.activeElement.id") == "user_email_address" }

    # A `#content` frame navigation (the wrong behaviour) starts with this event, within microtasks of the click.
    page.execute_script('document.addEventListener("turbo:before-fetch-request", () => { window.__fetched = true })')
    [ "#jump-nowhere", "#jump-broken" ].each do |link|
      find(link).click
      await_frames
      assert_nil page.evaluate_script("window.__fetched"), "#{link}, a link to a missing or malformed fragment, fetched something"
    end
    assert_no_selector "dialog#leave-dialog[open]"
    assert_selector "#user-form[data-same-form=yes]"
    assert_equal "Typed before the jumps", find_field("Name").value
    assert_equal entries, page.evaluate_script("history.length")
    assert_equal "", page.evaluate_script("location.hash")
  end

  test "Back with nothing typed just goes back" do
    sign_in_via_form(@owner)
    open_edit_from_the_list

    page.execute_script("history.back()")
    assert_current_path admin_users_path
    assert_no_field "Name"
    assert_no_selector "dialog#leave-dialog[open]"
  end

  test "the footer's Cancel leaves without asking" do
    sign_in_via_form(@owner)
    visit edit_admin_user_path(@target)
    await_admin_controllers
    fill_in "Name", with: "Thrown away"
    assert_selector ".admin-save-bar", text: /1 unsaved change/i

    within(".admin-save-bar") { click_link "Cancel" }
    assert_current_path admin_users_path
    assert_no_selector "dialog#leave-dialog[open]"
    assert_not_equal "Thrown away", @target.reload.name
  end

  # Rows that share one `name` (a list of links, `…[][name]`) are separate
  # controls, and a hidden input is part of the form's state only when it says
  # so (`data-save-bar-track`: a chip, a row order). No screen has either yet,
  # so the controls are added to the edit-user form and the form re-inserted,
  # which reconnects the controller with them in its baseline.
  test "repeated names count per row, a tracked hidden input counts, and the dialog names the count" do
    sign_in_via_form(@owner)
    visit edit_admin_user_path(@target)
    await_admin_controllers
    page.execute_script(<<~JS)
      const form = document.getElementById("user-form")
      form.insertAdjacentHTML("afterbegin", `
        <input id="row-1" name="extra[links][][name]" value="one">
        <input id="row-2" name="extra[links][][name]" value="two">
        <input id="tracked" type="hidden" name="extra[order]" value="1,2" data-save-bar-track>
        <input id="untracked" type="hidden" name="extra[token]" value="a">`)
      const parent = form.parentNode, next = form.nextSibling
      form.remove()
      parent.insertBefore(form, next)
    JS
    await_admin_controllers
    assert_selector ".admin-save-bar", text: /No unsaved changes/i

    fill_in "row-1", with: "uno"
    assert_selector ".admin-save-bar", text: /1 unsaved change\b/i
    fill_in "row-2", with: "dos"
    assert_selector ".admin-save-bar", text: /2 unsaved changes/i

    set_hidden = "const f = document.getElementById(arguments[0]); f.value = arguments[1]; f.dispatchEvent(new Event('input', { bubbles: true }))"
    page.execute_script(set_hidden, "untracked", "b")
    assert_selector ".admin-save-bar", text: /2 unsaved changes/i
    page.execute_script(set_hidden, "tracked", "2,1")
    assert_selector ".admin-save-bar", text: /3 unsaved changes/i

    within("nav[aria-label='Modules']") { click_link "Posts" }
    assert_selector "dialog#leave-dialog[open]"
    within("dialog#leave-dialog") { assert_text "You have 3 unsaved changes on this screen." }
  end

  # A failed save re-renders the form (the controller reconnects with the typed
  # values as its baseline): the bar and the leave guard must survive that.
  test "a new user form can be submitted from the start and stays unsaved after a 422" do
    sign_in_via_form(@owner)
    visit new_admin_user_path
    await_admin_controllers

    # Reachable before any typing, without the leave guard armed yet.
    # (Create user itself waits for a long enough password: the password
    # field governs that button, not the footer.)
    assert_selector ".admin-save-bar button[type=submit]", text: "Create user"
    assert_selector ".admin-save-bar a", text: "Cancel"
    assert_no_selector ".admin-save-bar", text: /unsaved/i
    within("nav[aria-label='Modules']") { click_link "Posts" }
    assert_current_path admin_posts_path
    assert_no_selector "dialog#leave-dialog[open]"

    visit new_admin_user_path
    await_admin_controllers
    fill_in "Email address", with: @target.email_address
    fill_in "Password", with: "a much Longer passw0rd"
    fill_in "Confirm password", with: "a much Longer passw0rd"
    press "Create user"

    assert_selector "[role=alert], .admin-error-summary, [aria-invalid=true]", wait: 10
    assert_selector ".admin-save-bar", text: /unsaved/i
    assert_selector ".admin-save-bar button[type=submit]", text: "Create user"
    within("nav[aria-label='Modules']") { click_link "Posts" }
    assert_selector "dialog#leave-dialog[open]"
    # Nothing differs from the re-rendered form, so there is no number to name.
    within("dialog#leave-dialog") { assert_text "You have unsaved changes on this screen." }
  end

  # Reached through the Groups LIST, i.e. a Turbo *frame* navigation: the
  # form's `admin--save-bar` then connects (and takes its baseline) before the
  # nested `admin--branch-picker` has ticked and disabled the boxes a chosen
  # branch implies. The baseline has to describe what would be submitted --
  # a disabled box and an unticked one are both simply absent -- or the
  # untouched form counts one change and the sidebar asks "Leave without
  # saving?". Every other test here uses a direct `visit`, where the order
  # happens to come out right, which is how this once slipped through.
  test "a group with a branch grant, opened from the list, has nothing unsaved" do
    about = create_page(title: "About")
    create_page(title: "Team", parent: about)
    group = AccessControl::Group.create!(name: "About editors")
    group.grants.create!(permission: "pages.edit", scope: { "page_ids" => [ about.id ] })

    sign_in_via_form(@owner)
    visit admin_groups_path
    await_admin_controllers
    within("##{ActionView::RecordIdentifier.dom_id(group)}") { click_link "About editors" }

    assert_field "Name", with: "About editors"
    assert_selector "[data-permission='pages.edit'] input[type=checkbox][disabled]", visible: :all
    assert_selector ".admin-save-bar", text: /No unsaved changes/i
    assert_selector ".admin-save-bar button[type=submit][disabled]", text: "Save"

    within("nav[aria-label='Modules']") { click_link "Posts" }
    assert_current_path admin_posts_path
    assert_no_selector "dialog#leave-dialog[open]"
  end

  # The footer belongs to its form: it sits in the form's own column, right
  # under the fields (not across the whole content area, where its buttons
  # ended up far from the form), Save first; the count is sans 13px, not mono
  # capitals; and the Save button reads "Save user" (round 3 Task 12).
  test "the footer sits in the form's column under the fields, Save first, in sans type" do
    sign_in_via_form(@owner)
    visit edit_admin_user_path(@target)
    await_admin_controllers
    fill_in "Name", with: "In the column"
    assert_selector ".admin-save-bar", text: /1 unsaved change/i

    geometry = page.evaluate_script(<<~JS)
      (() => {
        const bar = document.querySelector(".admin-save-bar")
        const rect = bar.getBoundingClientRect()
        const form = document.getElementById("user-form").getBoundingClientRect()
        const save = bar.querySelector("button[type=submit]").getBoundingClientRect()
        const cancel = bar.querySelector("a").getBoundingClientRect()
        const count = getComputedStyle(bar.querySelector("[data-admin--save-bar-target=count]"))
        return { barLeft: rect.left, barRight: rect.right, formLeft: form.left, formRight: form.right,
                 saveLeft: save.left, cancelLeft: cancel.left,
                 font: count.fontFamily, size: count.fontSize, transform: count.textTransform,
                 borderTop: getComputedStyle(bar).borderTopWidth }
      })()
    JS
    assert_in_delta geometry["formLeft"], geometry["barLeft"], 1
    assert_operator geometry["barRight"], :<=, geometry["formRight"] + 1
    assert_in_delta geometry["barLeft"], geometry["saveLeft"], 1
    assert_operator geometry["saveLeft"], :<, geometry["cancelLeft"]
    assert_equal "13px", geometry["size"]
    assert_equal "none", geometry["transform"]
    assert_no_match(/mono/i, geometry["font"])
    assert_equal "1px", geometry["borderTop"]
    assert_selector ".admin-save-bar button[type=submit]", text: /\ASave user\z/
  end

  test "the two account forms each keep their own footer and share one Leave prompt" do
    sign_in_via_form(@owner)
    visit admin_account_path
    await_admin_controllers

    assert_selector ".admin-save-bar", count: 2
    assert_selector ".admin-save-bar button[type=submit][disabled]", text: /\ASave\z/

    fill_in "Your name", with: "Someone New"
    assert_selector ".admin-save-bar button[type=submit]:not([disabled])", text: /\ASave\z/
    # The current password alone is not a change (a password manager fills it
    # in on load): only what would be saved counts.
    fill_in "Current password", with: "whatever"
    assert_selector "#password-form .admin-save-bar", text: "No unsaved changes"
    fill_in "New password", with: "a-new-long-password"

    # One under each form, never covering each other.
    rects = page.evaluate_script("Array.from(document.querySelectorAll('.admin-save-bar')).map((b) => { const r = b.getBoundingClientRect(); return [r.top, r.bottom] })")
    first, second = rects.sort_by(&:first)
    assert_operator first.last, :<=, second.first + 1

    within("nav[aria-label='Modules']") { click_link "Posts" }
    assert_selector "dialog#leave-dialog[open]"
    assert_selector "dialog[open]", count: 1
    # The count is the page's, not one form's.
    within("dialog#leave-dialog") do
      assert_text "You have 2 unsaved changes on this screen."
      press "Discard changes"
    end
    assert_current_path admin_posts_path
  end

  test "saving one account form is not blocked by the other being pristine" do
    sign_in_via_form(@owner)
    visit admin_account_path
    await_admin_controllers

    fill_in "Your name", with: "Saved Name"
    press "Save"
    assert_no_selector "dialog#leave-dialog[open]"
    # (The old subtitle, "Signed in as <name>.", used to show the saved name;
    # the new one doesn't, so the toast is the visible proof.)
    assert_text "Settings saved", wait: 10
    assert_equal "Saved Name", @owner.reload.name
    # The answer is a stream that keeps the screen and replaces the sidebar's
    # account block; the field shows what was saved, and its footer is clean.
    assert_equal "Saved Name", find_field("Your name").value
    assert_selector "span[title='Saved Name']", text: "Saved Name", wait: 5
  end
  # Final wave B, ledger C-I1: neither Save may throw away what the other
  # form holds.
  test "Save on the profile form keeps what the password form holds, and asks nothing" do
    sign_in_via_form(@owner)
    visit admin_account_path
    await_admin_controllers

    fill_in "Current password", with: "password"
    fill_in "New password", with: "a-new-long-password"
    fill_in "Your name", with: "Kept Both"
    within("#profile-form") { press "Save" }

    assert_text "Settings saved", wait: 10
    assert_no_selector "dialog#leave-dialog[open]"
    assert_equal "Kept Both", @owner.reload.name
    assert_selector "#account-identity span[title='Kept Both']"
    assert_equal "a-new-long-password", find_field("New password").value
    assert_equal "password", find_field("Current password").value
    # The name form took what it saved as its baseline: clean, Save disabled,
    # and typing the old value back is a change again.
    assert_selector "#profile-form .admin-save-bar", text: "No unsaved changes"
    assert_selector "#profile-form button[type=submit][disabled]", text: /\ASave\z/
    assert_selector "#password-form .admin-save-bar", text: "1 unsaved change"
    fill_in "Your name", with: "Kept Both, again"
    assert_selector "#profile-form .admin-save-bar", text: "1 unsaved change"
  end

  test "Change password is locked while the name is unsaved, and unlocks when it is saved" do
    sign_in_via_form(@owner)
    visit admin_account_path
    await_admin_controllers

    fill_in "Current password", with: "password"
    fill_in "New password", with: "a-new-long-password"
    fill_in "Confirm new password", with: "a-new-long-password"
    assert_selector "#password-form button[type=submit]:not([disabled])", text: "Change password"

    fill_in "Your name", with: "Typed Name"
    assert_selector "#password-form button[type=submit][disabled]", text: "Change password"
    assert_selector "#password-form .admin-save-bar [role=status]", text: "Save or cancel your changes first."
    # Enter in a field submits past a disabled button: refused all the same.
    find_field("Confirm new password").send_keys(:enter)
    assert_no_selector "[role=status]", text: "Password changed", wait: 1
    assert @owner.reload.authenticate("password")
    assert_equal "Typed Name", find_field("Your name").value
    # Typing more of the password does not unlock it.
    fill_in "New password", with: "a-new-long-password!"
    assert_selector "#password-form button[type=submit][disabled]", text: "Change password"
    fill_in "New password", with: "a-new-long-password"

    within("#profile-form") { press "Save" }
    assert_text "Settings saved", wait: 10
    assert_selector "#password-form button[type=submit]:not([disabled])", text: "Change password"
    assert_no_selector "#password-form .admin-save-bar [role=status]", text: "Save or cancel"

    within("#password-form") { press "Change password" }
    assert_text "Password changed. Your other sessions were signed out.", wait: 10
    assert @owner.reload.authenticate("a-new-long-password")
    assert_equal "Typed Name", find_field("Your name").value
  end
end
