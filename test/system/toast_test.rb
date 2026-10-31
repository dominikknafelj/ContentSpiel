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

    open_editor_menu
    press "Move to trash…"
    within("dialog[open]") { press "Move to trash" }
    assert_selector "#toasts .admin-toast", text: /trash/i, wait: 10
    assert @post.reload.trashed?

    # The delete form targets `_top`: one whole-page visit, the toast in
    # `#toasts` from the start (and the sidebar's Trash badge with it).
    assert_selector "nav[aria-label='Modules'] a", text: /Trash\s*1/
    within("#toasts") { press "Undo" }
    assert_selector "#toasts .admin-toast", text: "Restored", wait: 10
    assert_not @post.reload.trashed?

    visit admin_posts_path
    assert_text "Toasted post"
  end

  # Turbo keeps a snapshot of every page it leaves and shows it again on
  # Back. A toast that was on screen at that moment must not come back with
  # it: its Undo may be long past (or already used), and an error it reported
  # may have been fixed since.
  test "going Back to a page never brings its toast back" do
    sign_in_via_form(users(:one))
    visit admin_post_path(@post)
    await_admin_controllers

    open_editor_menu
    press "Move to trash…"
    within("dialog[open]") { press "Move to trash" }
    assert_selector "#toasts .admin-toast[data-kind=undo]", wait: 10
    assert_current_path admin_posts_path

    # Leave while the toast is still up, so it is in the cached snapshot.
    within("nav[aria-label='Modules']") { click_link "Tags" }
    assert_selector "h1", text: "Tags"
    assert_no_selector "#toasts .admin-toast"

    page.go_back
    assert_selector "h1", text: "Posts"
    assert_current_path admin_posts_path
    assert_no_selector "#toasts .admin-toast"
    assert_selector "#toasts", visible: :all
  end
end
