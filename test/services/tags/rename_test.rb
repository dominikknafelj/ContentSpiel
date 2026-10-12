require "test_helper"

class Tags::RenameTest < ActiveSupport::TestCase
  test "renaming a tag moves posts listed through a tag-filtered block" do
    listing = create_page(title: "Rails posts")
    ContentBlocks::Save.call(listing.content_blocks.build, attributes: { block_type: "post_list", settings: { content_type: "blog", tag: "rails" } })
    post = create_post(title: "Hi", tags: [ "rails" ])
    follow_rows! # the service's own sync, which acts on the rows: with copies nothing moves until they are published
    assert_equal "/rails-posts/hi", post.full_path("en")

    result = Tags::Rename.call(Tag.find_by!(name: "rails"), name: "ruby")
    assert result.ok?
    assert_nil post.reload.full_path("en")
  end

  # A rename to the very same name changes nothing and records no event, so
  # it must not make every open form of the carrying posts stale either.
  test "a rename to the same name leaves the carrying posts' updated_at alone; a real rename moves it" do
    tag = Tag.create!(name: "rails")
    post = create_post(title: "Hi", tags: [ "rails" ])
    post.update_columns(updated_at: 1.day.ago)
    before = post.reload.updated_at

    assert Tags::Rename.call(tag, name: " Rails ").ok?
    assert_equal before, post.reload.updated_at

    assert Tags::Rename.call(tag.reload, name: "ruby").ok?
    assert_operator post.reload.updated_at, :>, before
  end

  test "renaming to a taken name fails" do
    Tag.create!(name: "a"); b = Tag.create!(name: "b")
    assert_not Tags::Rename.call(b, name: " A ").ok?
  end

  test "strips and downcases the new name" do
    tag = Tag.create!(name: "rails")
    result = Tags::Rename.call(tag, name: "  Ruby On Rails  ")
    assert result.ok?
    assert_equal "ruby on rails", tag.reload.name
  end

  # A block with no content type filter (only a tag) is "every content
  # type" (BlockTypes::PostList's own reading, mirrored by
  # `PublicSite::Paths.posts_listed_by`) -- renaming the tag it
  # filters by has to resync every post, not just one type, since the block
  # itself never named one to narrow that down to.
  test "renaming a tag filtered by an untyped listing resyncs every content type" do
    listing = create_page(title: "Rails posts")
    ContentBlocks::Save.call(listing.content_blocks.build, attributes: { block_type: "post_list", settings: { tag: "rails" } })
    post = create_post(title: "Hi", content_type: "blog", tags: [ "rails" ])
    follow_rows! # the service's own sync, which acts on the rows: with copies nothing moves until they are published
    assert_equal "/rails-posts/hi", post.full_path("en")

    result = Tags::Rename.call(Tag.find_by!(name: "rails"), name: "ruby")
    assert result.ok?
    assert_nil post.reload.full_path("en")
  end

  # The new name can also be the one a block already filters by (a rename
  # that merges two tags' listing exposure) -- resync has to consider both
  # the old and the new name, not just the one being vacated.
  test "renaming a tag onto a name a listing already filters by resyncs those posts too" do
    listing = create_page(title: "Ruby posts")
    ContentBlocks::Save.call(listing.content_blocks.build, attributes: { block_type: "post_list", settings: { content_type: "blog", tag: "ruby" } })
    post = create_post(title: "Hi", tags: [ "rails" ])
    follow_rows! # the service's own sync, which acts on the rows: with copies nothing moves until they are published
    assert_nil post.full_path("en")

    result = Tags::Rename.call(Tag.find_by!(name: "rails"), name: "ruby")
    assert result.ok?
    assert_equal "/ruby-posts/hi", post.reload.full_path("en")
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

  test "renaming a tag marks the live posts that carry it and the live page whose list names it, and the site shows them as before" do
    page, live, draft = live_list_and_carriers
    tag_ids = Publishing.current(live).tag_ids
    shown = listed(page)
    assert_equal [ live.id ], shown

    assert Tags::Rename.call(Tag.find_by!(name: "rails"), name: "ruby").ok?

    assert marked?(live)
    assert_not marked?(draft), "a draft has no copy to differ from"
    assert marked?(page), "its rows name a tag that has another name now"
    assert_equal tag_ids, Publishing.current(live).tag_ids
    assert_equal shown, listed(page)
  end

  test "a rename to the same name marks nothing" do
    _page, live, = live_list_and_carriers

    assert Tags::Rename.call(Tag.find_by!(name: "rails"), name: " Rails ").ok?

    assert_not marked?(live)
  end
end
