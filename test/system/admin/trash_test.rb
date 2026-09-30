require "application_system_test_case"

# The Trash screen in a real browser (trash spec §7): Delete permanently
# confirms through `Admin::ConfirmDialogComponent`'s native `<dialog>`
# (never a browser `confirm()`), and Restore is a one-click POST.
class Admin::TrashSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    Current.set(actor: users(:one)) do
      @gone = create_post(title: "Gone post")
      @back = create_post(title: "Back post")
      [ @gone, @back ].each { |post| Trash::Move.call(post) }
    end
  end

  test "deleting permanently confirms in a dialog; restoring is one click" do
    sign_in_via_form(users(:one))
    visit "/cs-studio/trash"

    within("#trash-post-#{@gone.id}") { press "Delete permanently" }
    within("dialog#purge-post-#{@gone.id}[open]") do
      assert_text "This can't be undone."
      press "Delete permanently"
    end
    assert_selector "[role=status]", text: "Deleted “Gone post” permanently"
    assert_not Post.exists?(@gone.id)

    within("#trash-post-#{@back.id}") { press "Restore" }
    assert_selector "[role=status]", text: "Restored “Back post”"
    assert_not @back.reload.trashed?
  end
end
