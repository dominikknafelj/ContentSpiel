require "application_system_test_case"

# The trash in a real browser (trash spec §7, §9): every confirm is
# `Admin::Ui::ConfirmDialogComponent`'s native `<dialog>` (never a browser
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

    open_editor_menu
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
      assert_text "Includes 1 subpage: Child"
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

    open_editor_menu
    press "Move to trash"
    within("dialog#delete-page-#{@child.id}[open]") { press "Move to trash" }
    # The redirect goes through /pages to Home's editor; wait for that landing
    # (not just any status text) before reaching for the toast's button.
    assert_current_path(admin_page_path(root_page), wait: 10)
    assert_selector "#toasts .admin-toast", text: "Moved “Child” to the trash", wait: 10
    assert @child.reload.trashed?

    within("#toasts") { press "Undo" }
    assert_selector "[role=status]", text: "Restored “Child”", wait: 10
    assert_not @child.reload.trashed?
  end

  test "purge an unused image and empty the trash" do
    Current.set(actor: users(:one)) do
      assert Trash::Move.call(@asset).ok?
      assert Trash::Move.call(create_post(title: "Old post")).ok?
    end
    sign_in_via_form(users(:one))
    visit admin_trash_path

    within("#trash-media-#{@asset.id}") { press "Delete now…" }
    within("dialog#purge-media-#{@asset.id}[open]") { press "Delete permanently" }
    assert_selector "[role=status]", text: "permanently"
    assert_not Media::Asset.exists?(@asset.id)

    press "Empty trash…"
    within("dialog[open]") do
      assert_text "This deletes 1 post for good. It can't be undone."
      press "Empty trash"
    end
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

    within("#trash-post-#{@gone.id}") { press "Delete now…" }
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

  test "tabs carry their counts, and a page whose parent is in the trash restores under a chosen one" do
    Current.set(actor: users(:one)) do
      Trash::Move.call(create_post(title: "Gone post"))
      Trash::Move.call(@child)
      Trash::Move.call(@section.reload)
    end
    elsewhere = Current.set(actor: users(:one)) { create_page(title: "Elsewhere") }
    sign_in_via_form(users(:one))
    visit admin_trash_path

    assert_selector "nav[aria-label='Filter by type']", text: /All\s+3/
    assert_selector "nav[aria-label='Filter by type']", text: /Pages\s+2/
    click_tab "Posts"
    assert_selector "#trash-post-#{Post.trashed.first.id}"
    assert_no_selector "tr[id^=trash-page-]"
    click_tab "Pages"
    assert_selector "tr[id^=trash-page-]", count: 2

    within("#trash-page-#{@child.id}") do
      select "Elsewhere", from: "Restore under"
      press "Restore"
    end
    assert_selector "[role=status]", text: "Restored “Child”", wait: 10
    assert_equal elsewhere, @child.reload.parent
    assert_selector "nav[aria-label='Filter by type'] a[aria-current=page]", text: "Pages"
    assert_selector "nav[aria-label='Filter by type']", text: /Pages\s+1/
  end

  private

  # A tab is a link into the `content` frame, so the tests here that go on to
  # read the new rows wait for the whole navigation (`click_frame_link`, which
  # says why). A form pressed before it is over is held by the write queue and
  # sent afterwards -- `promotion_hold_test.rb` presses Restore straight after a
  # raw tab click to prove that.
  def click_tab(label)
    click_frame_link { within("nav[aria-label='Filter by type']") { click_link label } }
    assert_selector "nav[aria-label='Filter by type'] a[aria-current=page]", text: label
  end
end
