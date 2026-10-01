require "application_system_test_case"

# The trash in a real browser (trash spec §7, §9): every confirm is
# `Admin::ConfirmDialogComponent`'s native `<dialog>` (never a browser
# `confirm()`), Restore is a one-click POST, and a "Move to trash" flash
# carries an Undo button that restores in one click.
class Admin::TrashSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    Current.set(actor: users(:one)) do
      @section = create_page(title: "Section")
      @child = create_page(title: "Child", parent: @section)
      @asset = create_media_asset
    end
  end

  test "trash a page with its subpage, see it gone, restore it" do
    sign_in_via_form(users(:one))
    visit admin_page_path(@section)
    await_admin_controllers

    press "Move to trash"
    within("dialog#delete-page-#{@section.id}[open]") { press "Move to trash" }
    # A longer wait than Capybara's default: the first page move of a run
    # (branch flagged, subtree's URLs and listed posts resynced, redirect to
    # the shell) can outlast it on a cold test server.
    assert_selector "[role=status]", text: "Moved “Section” and 1 subpage to the trash", wait: 10
    # The page tree (`li[data-page-id]`) no longer lists either page.
    assert_no_selector "li[data-page-id='#{@section.id}']"
    assert_no_selector "li[data-page-id='#{@child.id}']"

    visit "/section"
    assert_text "Page not found"
    visit "/section/child"
    assert_text "Page not found"

    visit admin_trash_path
    within("#trash-page-#{@section.id}") do
      assert_text "+1 subpage"
      press "Restore"
    end
    assert_selector "[role=status]", text: "Restored “Section”"
    assert_not @child.reload.trashed?

    visit "/section/child"
    assert_selector "h1", text: "Child"
  end

  test "Undo from the flash" do
    sign_in_via_form(users(:one))
    visit admin_page_path(@child)
    await_admin_controllers

    press "Move to trash"
    within("dialog#delete-page-#{@child.id}[open]") { press "Move to trash" }
    assert_selector "[role=status]", text: "Moved “Child” to the trash", wait: 10
    assert @child.reload.trashed?

    press "Undo"
    assert_selector "[role=status]", text: "Restored “Child”"
    assert_not @child.reload.trashed?
  end

  test "purge an unused image and empty the trash" do
    Current.set(actor: users(:one)) do
      assert Trash::Move.call(@asset).ok?
      assert Trash::Move.call(create_post(title: "Old post")).ok?
    end
    sign_in_via_form(users(:one))
    visit admin_trash_path

    within("#trash-media-#{@asset.id}") { press "Delete permanently" }
    within("dialog#purge-media-#{@asset.id}[open]") { press "Delete permanently" }
    assert_selector "[role=status]", text: "permanently"
    assert_not Media::Asset.exists?(@asset.id)

    press "Empty trash"
    within("dialog[open]") { press "Empty trash" }
    assert_selector "[role=status]", text: "Emptied the trash: 1 deleted permanently"
    assert_equal 0, Post.trashed.count
    assert_text(/the trash is empty/i)
  end

  test "deleting permanently confirms in a dialog; restoring is one click" do
    Current.set(actor: users(:one)) do
      @gone = create_post(title: "Gone post")
      @back = create_post(title: "Back post")
      [ @gone, @back ].each { |post| Trash::Move.call(post) }
    end
    sign_in_via_form(users(:one))
    visit admin_trash_path

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
