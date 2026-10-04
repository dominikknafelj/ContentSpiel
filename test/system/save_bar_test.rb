require "application_system_test_case"

# The explicit-save footer and the Leave dialog in a real browser (cs-studio
# design pass, Task 11): the footer is always there with Save and Cancel,
# counts changed fields against what was loaded, keeps Save disabled while an
# existing record has nothing to save, and leaving with changes asks first.
class SaveBarSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @owner = users(:one)
    @target = users(:two)
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
    within("dialog#leave-dialog") { press "Stay" }
    assert_no_selector "dialog#leave-dialog[open]"
    assert_current_path edit_admin_user_path(@target)
    assert_equal "Typed again", find_field("Name").value

    within("nav[aria-label='Modules']") { click_link "Posts" }
    assert_selector "dialog#leave-dialog[open]"
    within("dialog#leave-dialog") { press "Leave" }
    assert_current_path admin_posts_path
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
    within("##{ActionView::RecordIdentifier.dom_id(group)}") { click_link "Edit" }

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
  # capitals; and the Save button reads "Save".
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
    assert_selector ".admin-save-bar button[type=submit]", text: /\ASave\z/
  end

  test "the two account forms each keep their own footer and share one Leave prompt" do
    sign_in_via_form(@owner)
    visit admin_account_password_path
    await_admin_controllers

    assert_selector ".admin-save-bar", count: 2
    assert_selector ".admin-save-bar button[type=submit][disabled]", text: "Save name"

    fill_in "Your name", with: "Someone New"
    assert_selector ".admin-save-bar button[type=submit]:not([disabled])", text: "Save name"
    fill_in "Current password", with: "whatever"

    # One under each form, never covering each other.
    rects = page.evaluate_script("Array.from(document.querySelectorAll('.admin-save-bar')).map((b) => { const r = b.getBoundingClientRect(); return [r.top, r.bottom] })")
    first, second = rects.sort_by(&:first)
    assert_operator first.last, :<=, second.first + 1

    within("nav[aria-label='Modules']") { click_link "Posts" }
    assert_selector "dialog#leave-dialog[open]"
    assert_selector "dialog[open]", count: 1
    within("dialog#leave-dialog") { press "Leave" }
    assert_current_path admin_posts_path
  end

  test "saving one account form is not blocked by the other being pristine" do
    sign_in_via_form(@owner)
    visit admin_account_password_path
    await_admin_controllers

    fill_in "Your name", with: "Saved Name"
    press "Save name"
    assert_no_selector "dialog#leave-dialog[open]"
    assert_text "Saved Name", wait: 10
    assert_equal "Saved Name", @owner.reload.name
  end
end
