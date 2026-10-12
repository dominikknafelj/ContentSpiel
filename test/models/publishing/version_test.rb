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
    assert_equal %w[hero_alt hero_media_asset_id meta_description meta_title page_type subtitle title translation_original_changed_at translation_sources],
      version.snapshot.fetch("fields").keys.sort
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
    assert_equal %w[body excerpt metadata title translated_metadata translation_original_changed_at translation_sources],
      version.snapshot.fetch("fields").keys.sort
  end

  def shown_tags(version) = version.reload.snapshot.fetch("tags").map { |tag| tag.values_at("id", "name") }

  # A hand test found the merged-away tag's NAME on the public post and in
  # the lists after a merge: only `tag_ids` had been repointed.
  test "a merge rewrites what a post's copy shows of the merged tag: the kept tag's id and name in its place, the others where they were" do
    post = create_post(title: "Tagged", tags: %w[rails other])
    rails, other = Tag.find_by!(name: "rails"), Tag.find_by!(name: "other")
    ruby = Tag.create!(name: "ruby") # the newest id, so "in its place" is not "in id order"
    copy = Publishing.current(post)
    assert_equal [ [ rails.id, "rails" ], [ other.id, "other" ] ], shown_tags(copy)

    assert Tags::Merge.call(rails, into: ruby).ok?

    assert_equal [ [ ruby.id, "ruby" ], [ other.id, "other" ] ], shown_tags(copy)
    assert_equal [ other.id, ruby.id ], copy.reload.tag_ids
    assert_equal %w[ruby other], Publishing.published(post.reload).tags.map(&:name), "and that is what a rebuilt post carries"
  end

  test "a merge removes the merged tag from a copy that already carried the kept one, which stays once, where and as it was" do
    post = create_post(title: "Both", tags: %w[first rails ruby last])
    ids = %w[first rails ruby last].index_with { |name| Tag.find_by!(name: name).id }
    copy = Publishing.current(post)

    assert Tags::Merge.call(Tag.find(ids["rails"]), into: Tag.find(ids["ruby"])).ok?

    assert_equal [ [ ids["first"], "first" ], [ ids["ruby"], "ruby" ], [ ids["last"], "last" ] ], shown_tags(copy)
    assert_equal ids.values_at("first", "ruby", "last").sort, copy.reload.tag_ids
  end

  test "a merge rewrites the pending copy and the older ones as it does the one in force" do
    post = create_post(title: "Scheduled", tags: %w[rails])
    ruby = Tag.create!(name: "ruby")
    first = Publishing.current(post)
    assert Posts::Save.call(post, translations: { "en" => { excerpt: "Now" } }).ok?
    publish_changes(post)
    assert Posts::Save.call(post, translations: { "en" => { excerpt: "Later" } }).ok?
    publish_changes(post, at: 2.days.from_now)
    copies = [ first, Publishing.current(post), Publishing.pending(post) ]
    assert_equal 3, copies.map(&:id).uniq.size

    assert Tags::Merge.call(Tag.find_by!(name: "rails"), into: ruby).ok?

    copies.each do |copy|
      assert_equal [ [ ruby.id, "ruby" ] ], shown_tags(copy), "copy #{copy.number}"
      assert_equal [ ruby.id ], copy.reload.tag_ids
    end
  end

  test "a copy that carried neither tag is not written by a merge" do
    post = create_post(title: "Bystander", tags: %w[other])
    create_post(title: "Carrier", tags: %w[rails])
    copy = Publishing.current(post)

    statements = capture_sql { assert Tags::Merge.call(Tag.find_by!(name: "rails"), into: Tag.create!(name: "ruby")).ok? }

    assert_equal 1, statements.count { |sql| sql.match?(/\AUPDATE "published_versions"/) }, "one statement, for the one copy that held the tag"
    assert_equal [ [ Tag.find_by!(name: "other").id, "other" ] ], shown_tags(copy)
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
    assert copied?(page)

    delete_for_good(page)

    assert_empty Publishing::Version.where(record_type: "Page", record_id: page.id)
  end

  test "a post deleted for good takes its copies with it" do
    post = create_post(title: "Gone")
    assert copied?(post)

    delete_for_good(post)

    assert_empty Publishing::Version.where(record_type: "Post", record_id: post.id)
  end

  test "a copy of a live record moves the public content version, and one of a scheduled record does not" do
    live = create_page(title: "Live")
    scheduled = create_post(title: "Later", published: false)
    assert Posts::Save.call(scheduled, attributes: { published_at: 3.days.from_now }).ok?

    assert Pages::Save.call(live, translations: { "en" => { title: "Changed" } }).ok? # Task 6: a publish with nothing changed takes no copy
    assert Posts::Save.call(scheduled, translations: { "en" => { title: "Changed" } }).ok?
    before = PublicSite::Version.current
    publish_changes(live)
    assert_operator PublicSite::Version.current, :>, before, "a copy of a live record must move the version"

    before = PublicSite::Version.current
    publish_changes(scheduled)
    assert_equal before, PublicSite::Version.current
  end

  test "a copy is taken from the row as it is, not from the object the caller loaded earlier" do
    page = create_page(title: "Old", published: false)
    stale = Page.find(page.id)
    Page.find(page.id).update_columns(title: { "en" => "A colleague's title" }) # version: none (the test plays a colleague's committed save)

    version = Publishing::Version.take!(stale)

    assert_equal({ "en" => "A colleague's title" }, version.snapshot.dig("fields", "title"))
    assert_equal "Old", Mobility.with_locale(:en) { stale.title }, "the caller's object is not changed under it"
  end

  test "the first statement of a copy locks the record's row, then nothing is read before it" do
    page = create_page(title: "Locked")
    post = create_post(title: "Locked too")

    [ page, post ].each do |record|
      statements = capture_sql { Publishing::Version.transaction { Publishing::Version.take!(record) } }
      first = statements.reject { |sql| sql.match?(/\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE)/i) }.first
      table = record.class.table_name

      assert_match(/FROM "#{table}" WHERE "#{table}"\."id" = \$1 LIMIT \$2 FOR UPDATE/, first, record.class.name)
    end
  end

  test "the current copy of one record is one statement, and of fifty records is one statement" do
    pages = Array.new(3) { |index| create_page(title: "Page #{index}") }
    later = Publishing::Version.take!(pages.first, live_at: 2.days.from_now)
    stand_ins = Array.new(47) { |index| Post.new(id: 9_000_000 + index) }

    one_answer = nil
    one = capture_sql { one_answer = Publishing.current(pages.first) }
    assert_equal Publishing::Version.of(pages.first).order(:number).first, one_answer
    batch = nil
    statements = capture_sql { batch = Publishing::Version.current_for(pages + stand_ins) }

    assert_equal 1, one.size
    assert_equal 1, statements.size
    assert_equal pages.map { |page| [ "Page", page.id ] }.sort, batch.keys.sort
    assert_equal Publishing::Version.of(pages.first).order(:number).first, batch[[ "Page", pages.first.id ]]
    assert_equal later, Publishing::Version.current_for(pages, now: 3.days.from_now)[[ "Page", pages.first.id ]]
    assert_empty Publishing::Version.current_for([])
  end
end
