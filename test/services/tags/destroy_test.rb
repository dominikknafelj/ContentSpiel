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

  def marked?(record) = record.class.where(id: record.id).pick(:unpublished_changes_at).present?

  # A live page whose list filters by the tag, a live post and a draft that
  # carry it, and the page's list as the site shows it.
  def live_list_and_carriers(tag_name = "rails")
    Tag.find_or_create_by!(name: tag_name) # the page's copy records the tag's id: it must exist when the page is published
    page = create_page(title: "Rails posts #{tag_name}", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => tag_name } })
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    live = create_post(title: "Live carrier #{tag_name}", tags: [ tag_name ])
    draft = create_post(title: "Draft carrier #{tag_name}", tags: [ tag_name ], published: false)
    [ page, live, draft ]
  end

  def listed(page) = Publishing::Listing.posts(Publishing.published(page).content_blocks.to_a.sole).map(&:id)

  test "deleting a tag marks the live posts that carry it and the live page whose list names it, and the site shows them as before" do
    page, live, draft = live_list_and_carriers
    tag_ids = Publishing.current(live).tag_ids
    shown = listed(page)

    assert Tags::Destroy.call(Tag.find_by!(name: "rails")).ok?

    assert marked?(live)
    assert_not marked?(draft)
    assert marked?(page)
    assert_equal tag_ids, Publishing.current(live).tag_ids
    assert_equal shown, listed(page)
  end
end
