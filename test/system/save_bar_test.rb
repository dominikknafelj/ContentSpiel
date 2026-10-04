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
end
