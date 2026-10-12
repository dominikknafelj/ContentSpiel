require "test_helper"

class Publishing::ListingTest < ActiveSupport::TestCase
  def list_block(page, **settings)
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: settings.stringify_keys }).record
  end

  def published_block(**settings)
    page = create_page(title: "Listing", published: false)
    list_block(page, **settings)
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    Publishing.published(page).content_blocks.to_a.sole
  end

  def titles(posts) = posts.map { |post| Mobility.with_locale(:en) { post.title } }

  test "a list holds the published posts of its type, newest first, as published, and no draft, trashed or scheduled one" do
    older = create_post(title: "Older")
    older.update_columns(published_at: 2.days.ago)
    newer = create_post(title: "Newer")
    create_post(title: "Draft", published: false)
    scheduled = create_post(title: "Scheduled", published: false)
    assert Posts::Save.call(scheduled, attributes: { published_at: 1.day.from_now }).ok?
    assert Trash::Move.call(create_post(title: "Trashed")).ok?
    create_post(title: "Résumé", content_type: "resume_entry")
    assert Posts::Save.call(newer, translations: { "en" => { title: "Typed" } }).ok?

    posts = Publishing::Listing.posts(published_block(content_type: "blog"))

    assert_equal %w[Newer Older], titles(posts)
    assert posts.all?(&:readonly?)
  end

  test "a tag filter is judged by each post's tags as published" do
    kept = create_post(title: "Kept", tags: %w[ruby])
    added = create_post(title: "Tagged since")
    block = published_block(content_type: "blog", tag: "ruby")
    assert Posts::Save.call(kept, attributes: { tag_names: [] }).ok?
    assert Posts::Save.call(added, attributes: { tag_names: %w[ruby] }).ok?

    assert_equal %w[Kept], titles(Publishing::Listing.posts(block))
    assert Publishing::Listing.lists?(block, Publishing.published(kept.reload))
    assert_not Publishing::Listing.lists?(block, Publishing.published(added.reload))

    publish_changes(kept)
    publish_changes(added)

    assert_equal [ "Tagged since" ], titles(Publishing::Listing.posts(block))
  end

  test "a tag renamed after both copies were taken drops no post from the list" do
    create_post(title: "Carrier", tags: %w[ruby])
    block = published_block(content_type: "blog", tag: "ruby")

    Tag.find_by!(name: "ruby").update!(name: "rubies")

    assert_equal %w[Carrier], titles(Publishing::Listing.posts(block))
  end

  test "a filter that named no tag when the copy was taken lists nothing" do
    create_post(title: "Carrier", tags: %w[ruby])

    assert_empty Publishing::Listing.posts(published_block(content_type: "blog", tag: "nothing-has-this"))
  end

  test "the limit is the block's, applied to the newest" do
    3.times { |index| create_post(title: "Post #{index}").update_columns(published_at: index.days.ago) }

    assert_equal [ "Post 0", "Post 1" ], titles(Publishing::Listing.posts(published_block(content_type: "blog"), limit: 2))
  end

  test "a post with no copy is listed by its rows, and so is a block of a page with no copy" do
    bare = create_post(title: "Bare", published: false, tags: %w[ruby])
    bare.update_columns(published_at: 1.hour.ago)
    page = create_page(title: "Bare page", published: false)
    row_block = list_block(page, content_type: "blog", tag: "ruby")

    assert_equal %w[Bare], titles(Publishing::Listing.posts(row_block))
    assert Publishing::Listing.lists?(row_block, bare.reload)
  end

  test "a list costs the same statements for 2 posts as for 12" do
    block = published_block(content_type: "blog")
    2.times { |index| create_post(title: "Post #{index}") }
    few = capture_sql { Publishing::Listing.posts(block) }.size
    10.times { |index| create_post(title: "More #{index}") }

    assert_equal few, capture_sql { Publishing::Listing.posts(block) }.size
  end
end
