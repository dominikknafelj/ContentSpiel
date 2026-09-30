require "test_helper"

class TrashableTest < ActiveSupport::TestCase
  test "kept and trashed partition pages, posts and assets" do
    page = create_page(title: "Kept page")
    gone = create_page(title: "Gone page")
    gone.update_columns(trashed_at: Time.current)
    post = create_post(title: "Kept post")
    trashed_post = create_post(title: "Gone post")
    trashed_post.update_columns(trashed_at: Time.current)
    asset = create_media_asset
    trashed_asset = create_media_asset
    trashed_asset.update_columns(trashed_at: Time.current)

    assert_includes Page.kept, page
    assert_not_includes Page.kept, gone
    assert_equal [ gone ], Page.trashed.to_a
    assert_equal [ trashed_post ], Post.trashed.to_a
    assert_includes Post.kept, post
    assert_equal [ trashed_asset ], Media::Asset.trashed.to_a
    assert_includes Media::Asset.kept, asset
    assert gone.reload.trashed?
    assert_not page.trashed?
  end

  test "trashed_by is nullified when the user is deleted" do
    post = create_post(title: "Orphaned")
    user = users(:reader)
    post.update_columns(trashed_at: Time.current, trashed_by_id: user.id)
    user.sessions.delete_all
    User.where(id: user.id).delete_all

    assert_nil post.reload.trashed_by_id
  end

  test "trash_root is nullified when the root page row is removed" do
    root = create_page(title: "Root")
    child = create_page(title: "Child", parent: root)
    child.update_columns(trashed_at: Time.current, trash_root_id: root.id)
    child.update_columns(parent_id: Page.find_by(parent_id: nil).id)
    PageHierarchy.where(descendant_id: root.id).or(PageHierarchy.where(ancestor_id: root.id)).delete_all
    Page.where(id: root.id).delete_all

    assert_nil child.reload.trash_root_id
  end
end
