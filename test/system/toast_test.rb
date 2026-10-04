require "application_system_test_case"

# Toasts in a real browser (cs-studio design pass, Task 8): a "Move to
# trash" redirect carries its flash into the layout's `#toasts` region as an
# undo toast, and its Undo button posts the restore straight back.
class ToastSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    Current.set(actor: users(:one)) { @post = create_post(title: "Toasted post") }
  end

  test "moving a post to the trash toasts an Undo that brings it back" do
    sign_in_via_form(users(:one))
    visit admin_post_path(@post)
    await_admin_controllers

    press "Move to trash"
    within("dialog[open]") { press "Move to trash" }
    assert_selector "#toasts .admin-toast", text: /trash/i, wait: 10
    assert @post.reload.trashed?

    # The delete answered inside the content frame, whose `advance` then
    # promotes the frame's URL to a Turbo visit of its own. A click that
    # lands while that visit is still in flight is swallowed by it, so wait
    # it out (a person never clicks that fast; Capybara does).
    sleep 1
    within("#toasts") { press "Undo" }
    assert_selector "#toasts .admin-toast", text: "Restored", wait: 10
    assert_not @post.reload.trashed?

    visit admin_posts_path
    assert_text "Toasted post"
  end
end
