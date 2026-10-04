require "test_helper"

# `Tags::Merge` (round 3 design pass, D20): a new write service, so the tests
# cover the whole contract -- every carrier (trashed ones too) ends up with the
# target exactly once, the source is gone, listing blocks that named it follow
# it, derived URLs are resynced, and every refusal leaves nothing behind.
class Tags::MergeTest < ActiveSupport::TestCase
  def tag(name) = Tag.find_by!(name: name)

  def tag_names(post) = post.reload.tags.map(&:name).sort

  def listing_block(page, tag:, content_type: "blog")
    ContentBlocks::Save.call(page.content_blocks.build,
      attributes: { block_type: "post_list", settings: { content_type: content_type, tag: tag }.compact }).record
  end

  test "every carrier of the source gets the target exactly once and the source is gone" do
    only_a = create_post(title: "Only A", tags: [ "a" ])
    only_b = create_post(title: "Only B", tags: [ "b" ])
    both = create_post(title: "Both", tags: [ "a", "b" ])
    trashed = create_post(title: "Trashed", tags: [ "a" ])
    assert Trash::Move.call(trashed).ok?
    source, into = tag("a"), tag("b")

    result = Tags::Merge.call(source, into: into)

    assert result.ok?, result.errors.to_sentence
    assert_equal into, result.record
    assert_not Tag.exists?(source.id)
    [ only_a, only_b, both, trashed ].each { |post| assert_equal %w[b], tag_names(post) }
    assert_equal 4, PostTag.where(tag_id: into.id).count
    assert_equal 0, PostTag.group(:post_id, :tag_id).having("COUNT(*) > 1").count.size, "no duplicated join row"
    assert_equal 0, PostTag.where(tag_id: source.id).count
  end

  test "a post that carried only the target is not touched; every carrier of the source is, trashed ones included" do
    only_a = create_post(title: "Only A", tags: [ "a" ])
    only_b = create_post(title: "Only B", tags: [ "b" ])
    both = create_post(title: "Both", tags: [ "a", "b" ])
    trashed = create_post(title: "Trashed", tags: [ "a" ])
    assert Trash::Move.call(trashed).ok?
    posts = [ only_a, only_b, both, trashed ]
    posts.each { |post| post.update_columns(updated_at: 1.day.ago) }
    before = posts.to_h { |post| [ post.id, post.reload.updated_at ] }

    assert Tags::Merge.call(tag("a"), into: tag("b")).ok?

    assert_equal before[only_b.id], only_b.reload.updated_at
    [ only_a, both, trashed ].each { |post| assert_operator post.reload.updated_at, :>, before[post.id] }
  end

  test "a tag with no posts merges: the source is deleted and nothing else changes" do
    Tag.create!(name: "empty")
    keep = create_post(title: "Keep", tags: [ "b" ])
    keep.update_columns(updated_at: 1.day.ago)
    before = keep.reload.updated_at

    result = Tags::Merge.call(tag("empty"), into: tag("b"))

    assert result.ok?
    assert_not Tag.exists?(name: "empty")
    assert_equal before, keep.reload.updated_at
    assert_equal 0, Audit::Event.find_by!(action: "tag.merged").metadata["posts"]
  end

  test "a listing block that names the source, in any case, is pointed at the target and lists the merged posts" do
    listing = create_page(title: "Listing")
    exact = listing_block(listing, tag: "a")
    cased = listing_block(listing, tag: " A ", content_type: nil)
    other_page = create_page(title: "Other")
    unrelated = listing_block(other_page, tag: "zzz")
    already = listing_block(other_page, tag: "b")
    untagged = listing_block(other_page, tag: nil)
    trashed_page = create_page(title: "Gone")
    on_trashed = listing_block(trashed_page, tag: "a")
    assert Trash::Move.call(trashed_page).ok?
    only_a = create_post(title: "Only A", tags: [ "a" ])
    only_b = create_post(title: "Only B", tags: [ "b" ])
    assert_equal [ only_a ], exact.reload.listed_posts.to_a

    assert Tags::Merge.call(tag("a"), into: tag("b")).ok?

    assert_equal "b", exact.reload.settings["tag"]
    assert_equal "b", cased.reload.settings["tag"]
    assert_equal "b", on_trashed.reload.settings["tag"], "a block on a trashed page follows too"
    assert_equal "zzz", unrelated.reload.settings["tag"], "a block naming no tag of ours is left alone"
    assert_equal "b", already.reload.settings["tag"]
    assert_nil untagged.reload.settings["tag"]
    assert_equal [ only_a, only_b ].sort_by(&:id), exact.listed_posts.sort_by(&:id)
    # Two blocks on one page now list the same posts twice; that is correct, they are not deduplicated.
    assert_equal 2, listing.content_blocks.reload.count
    assert_equal exact.settings["tag"], cased.settings["tag"]
  end

  test "block rows keep their other settings" do
    listing = create_page(title: "Listing")
    block = ContentBlocks::Save.call(listing.content_blocks.build,
      attributes: { block_type: "post_list", settings: { content_type: "blog", tag: "a", limit: 3 } }).record
    create_post(title: "Only A", tags: [ "a" ])

    assert Tags::Merge.call(tag("a"), into: Tag.create!(name: "b")).ok?

    assert_equal({ "content_type" => "blog", "tag" => "b", "limit" => 3 }, block.reload.settings)
  end

  test "the listing pages and the carriers' public paths are resynced" do
    for_a = create_page(title: "A posts")
    for_b = create_page(title: "B posts")
    listing_block(for_a, tag: "a")
    listing_block(for_b, tag: "b")
    only_a = create_post(title: "Only A", tags: [ "a" ])
    only_b = create_post(title: "Only B", tags: [ "b" ])
    assert_equal "/a-posts/only-a", only_a.full_path("en")
    assert_equal "/b-posts/only-b", only_b.full_path("en")

    assert Tags::Merge.call(tag("a"), into: tag("b")).ok?

    # Both listings now filter by "b" and list both posts; each post's canonical
    # page is the better-ranked of the two (tree order), the same for both.
    assert_equal only_a.reload.full_path("en").split("/").second, only_b.reload.full_path("en").split("/").second
    assert only_a.full_path("en").present?
  end

  test "a carrier that no listing showed before gets its URL from the target's listing" do
    listing = create_page(title: "B posts")
    listing_block(listing, tag: "b")
    only_a = create_post(title: "Only A", tags: [ "a" ])
    Tag.create!(name: "b")
    assert_nil only_a.full_path("en")

    assert Tags::Merge.call(tag("a"), into: tag("b")).ok?

    assert_equal "/b-posts/only-a", only_a.reload.full_path("en")
  end

  test "pages that hold blocks for the source are touched, so an open page form goes stale" do
    listing = create_page(title: "Listing")
    listing_block(listing, tag: "a")
    untouched = create_page(title: "Untouched")
    listing_block(untouched, tag: "zzz")
    Tag.create!(name: "a")
    [ listing, untouched ].each { |page| page.update_columns(updated_at: 1.day.ago) }
    before = untouched.reload.updated_at
    listing_before = listing.reload.updated_at
    Tag.create!(name: "b")

    assert Tags::Merge.call(tag("a"), into: tag("b")).ok?

    assert_operator listing.reload.updated_at, :>, listing_before
    assert_equal before, untouched.reload.updated_at
  end

  test "records exactly one tag.merged event on the target, counting trashed carriers" do
    create_post(title: "One", tags: [ "a" ])
    create_post(title: "Two", tags: [ "a", "b" ])
    create_post(title: "Three", tags: [ "a" ]).then { |post| assert Trash::Move.call(post).ok? }
    create_post(title: "Four", tags: [ "b" ])
    source, into = tag("a"), tag("b")
    events_before = Audit::Event.count

    assert as_owner { Tags::Merge.call(source, into: into) }.ok?

    assert_equal events_before + 1, Audit::Event.count, "one event, none per post"
    event = Audit::Event.find_by!(action: "tag.merged")
    assert_equal into, event.subject
    assert_equal({ "merged" => "a", "posts" => 3 }, event.metadata)
    assert_equal into.id, event.snapshot["id"]
    assert_equal "b", event.snapshot["name"]
    assert_equal users(:one).id, event.user_id
  end

  test "the target cannot be the source" do
    source = Tag.create!(name: "a")
    post = create_post(title: "Hi", tags: [ "a" ])

    result = as_owner { Tags::Merge.call(source, into: source) }

    assert_not result.ok?
    assert_not result.denied?
    assert Tag.exists?(source.id)
    assert_equal %w[a], tag_names(post)
    assert_empty Audit::Event.where(action: "tag.merged")

    same_row = as_owner { Tags::Merge.call(source, into: Tag.find(source.id)) }
    assert_not same_row.ok?
  end

  test "a missing target is a plain failure" do
    source = Tag.create!(name: "a")

    result = as_owner { Tags::Merge.call(source, into: nil) }

    assert_not result.ok?
    assert Tag.exists?(source.id)
  end

  test "a target deleted since it was loaded is a plain failure that leaves the source alone" do
    source = Tag.create!(name: "a")
    into = Tag.create!(name: "b")
    post = create_post(title: "Hi", tags: [ "a" ])
    Tag.where(id: into.id).delete_all

    result = as_owner { Tags::Merge.call(source, into: into) }

    assert_not result.ok?
    assert_not result.denied?
    assert Tag.exists?(source.id)
    assert_equal %w[a], tag_names(post)
    assert_empty Audit::Event.where(action: "tag.merged")
  end

  test "a source deleted since it was loaded is a plain failure" do
    source = Tag.create!(name: "a")
    into = Tag.create!(name: "b")
    Tag.where(id: source.id).delete_all

    result = as_owner { Tags::Merge.call(source, into: into) }

    assert_not result.ok?
    assert Tag.exists?(into.id)
  end

  test "merging A into B and then B into A: the second finds A gone and fails cleanly" do
    a = Tag.create!(name: "a")
    b = Tag.create!(name: "b")
    post = create_post(title: "Hi", tags: [ "a" ])

    assert as_owner { Tags::Merge.call(a, into: b) }.ok?
    again = as_owner { Tags::Merge.call(b, into: a) }

    assert_not again.ok?
    assert_equal %w[b], tag_names(post)
    assert_equal 1, Audit::Event.where(action: "tag.merged").count
  end

  test "merging B onward into a third tag carries everything along" do
    a = Tag.create!(name: "a")
    b = Tag.create!(name: "b")
    c = Tag.create!(name: "c")
    post = create_post(title: "Hi", tags: [ "a" ])

    assert as_owner { Tags::Merge.call(a, into: b) }.ok?
    assert as_owner { Tags::Merge.call(b, into: c) }.ok?

    assert_equal %w[c], tag_names(post)
    assert_equal [ 1, 1 ], Audit::Event.where(action: "tag.merged").order(:id).map { |event| event.metadata["posts"] }
  end

  test "without tags.manage the merge is refused with one access.denied and nothing changes" do
    source = Tag.create!(name: "a")
    into = Tag.create!(name: "b")
    post = create_post(title: "Hi", tags: [ "a" ])

    result = as(users(:reader)) { Tags::Merge.call(source, into: into) }

    assert result.denied?
    assert_equal 1, Audit::Event.where(action: "access.denied").count
    assert_empty Audit::Event.where(action: "tag.merged")
    assert Tag.exists?(source.id)
    assert_equal %w[a], tag_names(post)
  end

  test "the trusted nil actor works on the console and system channels" do
    %i[console system].each do |channel|
      source = Tag.create!(name: "src-#{channel}")
      into = Tag.create!(name: "dst-#{channel}")

      result = as(nil, channel: channel) { Tags::Merge.call(source, into: into) }

      assert result.ok?, "#{channel}: #{result.errors.to_sentence}"
    end
  end

  test "a nil actor on the admin channel is denied" do
    source = Tag.create!(name: "a")
    result = as(nil, channel: :admin) { Tags::Merge.call(source, into: Tag.create!(name: "b")) }
    assert result.denied?
    assert Tag.exists?(source.id)
  end

  test "a failure part-way leaves nothing half-merged" do
    listing = create_page(title: "Listing")
    block = listing_block(listing, tag: "a")
    post = create_post(title: "Hi", tags: [ "a" ])
    post.update_columns(updated_at: 1.day.ago)
    before = post.reload.updated_at
    source, into = tag("a"), Tag.create!(name: "b")

    assert_raises(RuntimeError) do
      with_singleton_override(Audit, :record, ->(*, **) { raise "boom" }) { as_owner { Tags::Merge.call(source, into: into) } }
    end

    assert Tag.exists?(source.id)
    assert_equal %w[a], tag_names(post)
    assert_equal before, post.reload.updated_at
    assert_equal "a", block.reload.settings["tag"]
    assert_equal 0, PostTag.where(tag_id: into.id).count
  end
end
