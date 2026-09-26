require "test_helper"

class PublishableTest < ActiveSupport::TestCase
  test "status follows published_at" do
    assert_equal "draft", Post.new(published_at: nil).status
    assert_equal "scheduled", Post.new(published_at: 1.day.from_now).status
    assert_equal "live", Post.new(published_at: 1.minute.ago).status
    assert_equal "live", Page.new(published_at: 1.minute.ago).status
  end

  test "publish_now! and unpublish! set and clear published_at" do
    post = Post.create!(content_type: :blog, title: "Draft")
    post.publish_now!
    assert post.reload.live?

    post.unpublish!
    assert_equal "draft", post.reload.status
  end

  test "find_by_full_path only includes unpublished pages when asked" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    Page.create!(parent: root, page_type: :standard, title: "Draft")

    assert_nil Page.find_by_full_path("en", "/draft")
    assert_equal "Draft", Page.find_by_full_path("en", "/draft", include_unpublished: true).title
  end

  test "listed_posts includes unpublished posts only when asked" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    block = root.content_blocks.create!(block_type: :post_list, position: 0)
    scheduled = Post.create!(content_type: :blog, title: "Soon", published_at: 1.day.from_now)

    assert_not_includes block.listed_posts, scheduled
    assert_includes block.listed_posts(include_unpublished: true), scheduled
  end
end
