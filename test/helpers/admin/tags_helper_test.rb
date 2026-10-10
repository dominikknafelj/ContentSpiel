require "test_helper"

# The wording of the Tags list's two dialogs, pinned sentence by sentence: one
# whole sentence per shape (no posts, one, many, more than the viewer can see
# in the list's own column in the singular and the plural, and a viewer who may
# not read posts at all, who is told no number). The curly quotes round the
# name are part of the sentence: `admin--tags--dialogs` finds the live name in
# the finished sentence by them.
class Admin::TagsHelperTest < ActionView::TestCase
  Named = Struct.new(:name)
  TAG = Named.new("rails")

  test "titles quote the name" do
    assert_equal "Merge “rails” into…", tag_merge_title(TAG)
    assert_equal "Delete “rails”?", tag_delete_title(TAG)
  end

  test "delete: a viewer who may not read posts is told no number" do
    assert_equal "It is removed from every post that uses it. The posts themselves stay.", tag_delete_text(nil)
  end

  test "delete: no posts, one post, several posts" do
    assert_equal "No posts use it.", tag_delete_text(0)
    assert_equal "It is removed from 1 post. The posts themselves stay.", tag_delete_text(1)
    assert_equal "It is removed from 3 posts. The posts themselves stay.", tag_delete_text(3, 3)
  end

  test "delete: more posts reached than the list shows says where the others are" do
    assert_equal "It is removed from 1 post, which is in the trash or one you can't open. The posts themselves stay.", tag_delete_text(1, 0)
    assert_equal "It is removed from 3 posts, including ones in the trash or that you can't open. The posts themselves stay.", tag_delete_text(3, 2)
    assert_equal "It is removed from 2 posts, including ones in the trash or that you can't open. The posts themselves stay.", tag_delete_text(2, nil)
  end

  test "merge: a viewer who may not read posts is told no number" do
    assert_equal "Its posts get the chosen tag and “rails” is deleted. This can't be undone.", tag_merge_text(TAG, nil)
  end

  test "merge: no posts, one post, several posts" do
    assert_equal "No posts use it, so nothing moves. “rails” is deleted. This can't be undone.", tag_merge_text(TAG, 0)
    assert_equal "Its 1 post gets the chosen tag and “rails” is deleted. This can't be undone.", tag_merge_text(TAG, 1)
    assert_equal "Its 3 posts get the chosen tag and “rails” is deleted. This can't be undone.", tag_merge_text(TAG, 3, 3)
  end

  test "merge: more posts reached than the list shows says where the others are" do
    assert_equal "Its 1 post, which is in the trash or one you can't open, gets the chosen tag and “rails” is deleted. This can't be undone.", tag_merge_text(TAG, 1, 0)
    assert_equal "Its 3 posts, including ones in the trash or that you can't open, get the chosen tag and “rails” is deleted. This can't be undone.", tag_merge_text(TAG, 3, 2)
  end

  test "the Posts column's label" do
    assert_equal "0 posts", tag_posts_label(0)
    assert_equal "1 post", tag_posts_label(1)
    assert_equal "5 posts", tag_posts_label(5)
  end
end
