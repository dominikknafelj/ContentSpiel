require "test_helper"

class Publishing::VersionTest < ActiveSupport::TestCase
  def add_block(page, **attributes)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }.merge(attributes))
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  test "the first publish of a page takes copy number 1 from its rows, with its blocks in reading order and exactly the fields a copy holds" do
    page = create_page(title: "Pricing", published: false)
    section = add_block(page, block_type: "section", settings: { "layout" => "two" })
    inner = add_block(page, section_id: section.id, section_column: 2)
    last = add_block(page)
    assert_empty Publishing::Version.of(page)

    assert Pages::Save.call(page, attributes: { published: true }).ok?

    version = Publishing::Version.of(page).sole
    assert_equal 1, version.number
    assert_equal [ section.id, inner.id, last.id ], version.blocks.map { |block| block["id"] }
    assert_equal({ "en" => "Pricing" }, version.snapshot.dig("fields", "title"))
    assert_equal Publishing::CONTENT.fetch("Page").sort, version.snapshot.fetch("fields").keys.sort
    assert_not version.lists_posts
    assert_operator version.live_at, :<=, Time.current
  end

  test "a page created published has a copy from the start" do
    page = create_page(title: "Born live")

    assert_equal 1, Publishing::Version.of(page).count
  end

  test "scheduling a draft takes its copy at once, current from that moment whatever time it is scheduled for" do
    post = create_post(title: "Later", published: false)

    assert Posts::Save.call(post, attributes: { published_at: 3.days.from_now }).ok?

    version = Publishing::Version.of(post).sole
    assert_operator version.live_at, :<=, Time.current
    assert_equal version, Publishing.current(post)
    assert_nil Publishing.pending(post)
  end

  test "a post's copy holds its tags by id and name, and tag_ids is those ids sorted" do
    post = create_post(title: "Tagged", tags: %w[ruby rails])
    ids = post.tags.order(:id).pluck(:id)

    version = Publishing.current(post)

    assert_equal ids, version.tag_ids
    assert_equal ids, version.snapshot.fetch("tags").map { |tag| tag["id"] }
    assert_equal %w[rails ruby], version.snapshot.fetch("tags").map { |tag| tag["name"] }.sort
    assert_equal Publishing::CONTENT.fetch("Post").sort, version.snapshot.fetch("fields").keys.sort
  end

  test "saving a published record again, and pressing Publish on a live one, take no copy" do
    page = create_page(title: "One")

    assert Pages::Save.call(page, translations: { "en" => { title: "Two" } }).ok?
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    assert Pages::Save.call(page, attributes: { published_at: 2.days.from_now }).ok?

    assert_equal [ 1 ], Publishing::Version.of(page).pluck(:number)
    assert_equal({ "en" => "One" }, Publishing.current(page).snapshot.dig("fields", "title"))
  end

  test "a save that fails takes no copy" do
    page = create_page(title: "Draft", published: false)

    result = Pages::Save.call(page, attributes: { published: true }, translations: { "en" => { title: "" } })

    assert_not result.ok?
    assert_empty Publishing::Version.of(page)
  end

  test "a copy taken while one is pending replaces it, and what was replaced never becomes current" do
    page = create_page(title: "One")
    first = Publishing.current(page)
    pending = Publishing::Version.take!(page, live_at: 2.days.from_now)
    assert_equal pending, Publishing.pending(page)

    replacement = Publishing::Version.take!(page, live_at: 1.day.from_now)

    assert_equal 3, replacement.number, "a replaced copy's number is not given out again"
    assert_not Publishing::Version.exists?(pending.id)
    assert_equal [ 1, 3 ], Publishing::Version.of(page).order(:number).pluck(:number)
    assert_equal first, Publishing.current(page)
    assert_equal replacement, Publishing.current(page, now: 36.hours.from_now)
    assert_equal replacement, Publishing.current(page, now: 3.days.from_now)
    assert_equal replacement, Publishing.baseline(page)
  end

  test "a copy taken now while one is pending replaces it too" do
    page = create_page(title: "One")
    Publishing::Version.take!(page, live_at: 2.days.from_now)

    now_copy = Publishing::Version.take!(page)

    assert_nil Publishing.pending(page)
    assert_equal now_copy, Publishing.current(page)
  end

  test "a live_at in the past is the moment the copy is taken" do
    page = create_page(title: "One")
    before = Time.current

    version = Publishing::Version.take!(page, live_at: 1.year.ago)

    assert_operator version.live_at, :>=, before
  end

  test "unpublishing and publishing again takes a new copy from the rows as they are then" do
    page = create_page(title: "One")
    assert Pages::Save.call(page, attributes: { published: false }).ok?
    assert Pages::Save.call(page, translations: { "en" => { title: "Two" } }).ok?
    assert_equal 1, Publishing::Version.of(page).count, "an unpublished record keeps its copies and takes none"

    assert Pages::Save.call(page, attributes: { published: true }).ok?

    assert_equal [ 1, 2 ], Publishing::Version.of(page).order(:number).pluck(:number)
    assert_equal({ "en" => "Two" }, Publishing.current(page).snapshot.dig("fields", "title"))
  end

  test "a copy is never updated" do
    version = Publishing.current(create_page(title: "One"))

    assert_raises(ActiveRecord::ReadOnlyRecord) { version.update!(number: 9) }
  end

  test "a record deleted for good takes its copies with it" do
    page = create_page(title: "Gone")
    assert Publishing.copied?(page)

    delete_for_good(page)

    assert_empty Publishing::Version.where(record_type: "Page", record_id: page.id)
  end

  test "the migration gives every published and scheduled record its first copy, from the rows as they are, and leaves a draft without one" do
    live = create_page(title: "Live", published: false)
    scheduled = create_post(title: "Scheduled", published: false)
    draft = create_page(title: "Draft", published: false)
    copied = create_page(title: "Has one")
    block = ContentBlocks::Save.call(ContentBlock.new(owner: live), attributes: { block_type: "rich_text" }).record
    live.update_columns(published_at: 1.day.ago)        # as a record published before this table existed
    scheduled.update_columns(published_at: 1.day.from_now)

    assert_equal 2, Publishing::Version.take_first_copies!

    assert_equal [ block.id ], Publishing.current(live).blocks.map { |row| row["id"] }
    assert_equal Publishing::Version.of(scheduled).sole, Publishing.current(scheduled)
    assert_not Publishing.copied?(draft)
    assert_equal 1, Publishing::Version.of(copied).count
    assert_equal 0, Publishing::Version.take_first_copies!, "a second run finds nothing to do"
  end
end
