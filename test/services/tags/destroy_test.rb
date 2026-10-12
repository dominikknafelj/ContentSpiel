require "test_helper"

class Tags::DestroyTest < ActiveSupport::TestCase
  test "removes the tag and the join rows, and resyncs a tag-filtered listing's paths" do
    listing = create_page(title: "Rails posts")
    ContentBlocks::Save.call(listing.content_blocks.build, attributes: { block_type: "post_list", settings: { content_type: "blog", tag: "rails" } })
    post = create_post(title: "Hi", tags: [ "rails" ])
    follow_rows! # the service's own sync, which acts on the rows: with copies nothing moves until they are published
    assert_equal "/rails-posts/hi", post.full_path("en")

    tag = Tag.find_by!(name: "rails")
    result = Tags::Destroy.call(tag)

    assert result.ok?
    assert_not Tag.exists?(tag.id)
    assert_empty post.reload.tags
    assert_nil post.full_path("en")
  end

  test "deleting an unused tag succeeds" do
    tag = Tag.create!(name: "unused")
    assert Tags::Destroy.call(tag).ok?
    assert_not Tag.exists?(tag.id)
  end
end
