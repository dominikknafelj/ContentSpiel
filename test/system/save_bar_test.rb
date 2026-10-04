require "application_system_test_case"

# The explicit-save bar and the Leave dialog in a real browser (cs-studio
# design pass, Task 11): the bar counts changed fields against what was
# loaded, and leaving the screen with changes asks first.
class SaveBarSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @owner = users(:one)
    @target = users(:two)
  end

  test "the bar counts changes, drops back to hidden, and guards leaving" do
    sign_in_via_form(@owner)
    visit edit_admin_user_path(@target)
    await_admin_controllers

    assert_no_selector ".admin-save-bar"

    original = find_field("Name").value
    fill_in "Name", with: "#{original}x"
    assert_selector ".admin-save-bar", text: /1 unsaved change/i

    fill_in "Name", with: original
    assert_no_selector ".admin-save-bar"

    fill_in "Name", with: "Typed again"
    assert_selector ".admin-save-bar"

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
  test "a new user form shows its Save from the start and keeps the bar after a 422" do
    sign_in_via_form(@owner)
    visit new_admin_user_path
    await_admin_controllers

    # Reachable before any typing, without the leave guard armed yet.
    assert_selector ".admin-save-bar", text: /Create user/
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
    assert_no_selector ".admin-save-bar"

    within("nav[aria-label='Modules']") { click_link "Posts" }
    assert_current_path admin_posts_path
    assert_no_selector "dialog#leave-dialog[open]"
  end

  test "the two account forms share one Leave prompt and stack their bars" do
    sign_in_via_form(@owner)
    visit admin_account_password_path
    await_admin_controllers

    fill_in "Your name", with: "Someone New"
    assert_selector ".admin-save-bar", count: 1
    fill_in "Current password", with: "whatever"
    assert_selector ".admin-save-bar", count: 2

    # Stacked, not covering each other.
    rects = page.evaluate_script("Array.from(document.querySelectorAll('.admin-save-bar')).filter((b) => !b.hidden).map((b) => { const r = b.getBoundingClientRect(); return [r.top, r.bottom] })")
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
