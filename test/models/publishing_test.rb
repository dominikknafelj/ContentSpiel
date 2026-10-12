require "test_helper"

class PublishingTest < ActiveSupport::TestCase
  test "the content columns of a record or of its class" do
    page = create_page(title: "One")

    assert_equal Publishing::CONTENT.fetch("Page"), Publishing.content_columns(page)
    assert_equal Publishing::CONTENT.fetch("Post"), Publishing.content_columns(Post)
  end

  test "current, baseline, pending and copied? follow the copies of a record" do
    page = create_page(title: "One")
    first = Publishing.current(page)
    assert Publishing.copied?(page)
    assert_equal first, Publishing.baseline(page)

    later = Publishing::Version.take!(page, live_at: 2.days.from_now)

    assert_equal first, Publishing.current(page)
    assert_equal later, Publishing.pending(page)
    assert_equal later, Publishing.baseline(page)
    assert_not Publishing.copied?(create_page(title: "Draft", published: false))
  end

  test "published is the copy for a live record, the record itself for a draft and for one with no copy" do
    live = create_page(title: "Live")
    draft = create_page(title: "Draft", published: false)
    bare = create_page(title: "Bare", published: false)
    bare.update_columns(published_at: 1.day.ago)
    bare.reload
    assert Pages::Save.call(live, translations: { "en" => { title: "Typed" } }).ok?

    view = Publishing.published(live.reload)

    assert_equal "Live", Mobility.with_locale(:en) { view.title }
    assert view.readonly?
    assert view.association(:content_blocks).loaded?
    assert_same draft, Publishing.published(draft)
    assert_same bare, Publishing.published(bare)
    assert_nil bare.published_version
  end

  test "a record unpublished again uses none of the copies it kept" do
    page = create_page(title: "Once live")
    assert Pages::Save.call(page, attributes: { published: false }, translations: { "en" => { title: "Draft again" } }).ok?

    assert_same page, Publishing.published(page)
  end

  test "published_all keeps the order, mixes pages and posts, costs one query per type and loads no blocks" do
    pages = [ create_page(title: "B"), create_page(title: "A"), create_page(title: "Draft", published: false) ]
    post = create_post(title: "Post")
    pages.first(2).each { |page| assert Pages::Save.call(page, translations: { "en" => { title: "typed" } }).ok? }
    records = (pages + [ post ]).map(&:reload)

    statements = capture_sql { @views = Publishing.published_all(records) }

    assert_equal %w[B A Draft Post], @views.map { |view| Mobility.with_locale(:en) { view.title } }
    assert_equal 2, statements.size, statements.join("\n")
    assert_not @views.first.association(:content_blocks).loaded?
    assert_raises(ActiveModel::MissingAttributeError) { @views.first.published_version.blocks }
  end

  test "what is published is judged at the time asked: a pending copy is not it before its time and is after" do
    page = create_page(title: "Now")
    assert Pages::Save.call(page, translations: { "en" => { title: "Later" } }).ok?
    Publishing::Version.transaction { Publishing::Version.take!(page.reload, live_at: 2.days.from_now) }

    assert_equal "Now", Mobility.with_locale(:en) { Publishing.published(page).title }
    assert_equal "Later", Mobility.with_locale(:en) { Publishing.published(page, now: 3.days.from_now).title }
  end

  # A new column on one of the three tables must be decided: in the copy, left
  # on the rows with a reason, or never stored. Not "forgotten", not twice.
  { "Page" => Page, "Post" => Post, "ContentBlock" => ContentBlock }.each do |name, model|
    test "every column of #{model.table_name} is in exactly one of the copy, the rows and never stored" do
      lists = { "CONTENT" => Publishing::CONTENT.fetch(name), "ROWS" => Publishing::ROWS.fetch(name).keys,
                "NEVER_STORED" => Publishing::NEVER_STORED.fetch(name).keys }
      placed = lists.values.flatten

      assert_empty model.column_names - placed, "#{model.table_name} has columns in none of Publishing::CONTENT, ROWS and NEVER_STORED: decide where each goes"
      assert_empty placed - model.column_names, "Publishing names columns #{model.table_name} does not have"
      assert_equal placed.uniq.sort, placed.sort, "a column of #{model.table_name} is in two lists: #{placed.tally.select { |_, n| n > 1 }.keys}"
      assert Publishing::ROWS.fetch(name).values.all?(&:present?), "every column left on the rows needs its reason"
    end
  end

  # -- the mark (drafts spec §4.4) ---------------------------------------------

  def marked?(record) = record.class.where(id: record.id).pick(:unpublished_changes_at).present?

  test "a content column saved on a published or scheduled record sets the mark; on a draft, and for what is not in a copy, it does not" do
    live = create_page(title: "Live")
    scheduled = create_post(title: "Scheduled", published: false)
    assert Posts::Save.call(scheduled, attributes: { published_at: 2.days.from_now }).ok?
    draft = create_page(title: "Draft", published: false)
    assert_not marked?(live), "a first publication left a mark"
    assert_not marked?(scheduled)

    assert Pages::Save.call(live, translations: { "en" => { slug: "another-address" } }).ok?
    assert Pages::Save.call(live, attributes: { published_at: 1.hour.ago }).ok?
    assert_not marked?(live), "a slug or a publication time is immediate: no change is waiting"

    assert Pages::Save.call(live, translations: { "en" => { title: "Typed" } }).ok?
    assert Posts::Save.call(scheduled, translations: { "en" => { excerpt: "Typed" } }).ok?
    assert Pages::Save.call(draft, translations: { "en" => { title: "Typed" } }).ok?

    assert marked?(live)
    assert marked?(scheduled)
    assert_not marked?(draft)
    assert live.reload.unpublished_changes?
  end

  test "a block added, saved, moved, duplicated and deleted each mark its live page, and leave the page's settings base alone" do
    page = create_page(title: "Blocks")
    base = page.reload.settings_changed_at
    writes = {
      "add" => -> { @block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }).record },
      "save" => -> { ContentBlocks::Save.call(@block, translations: { "en" => { body: rich_doc("Text") } }) },
      "duplicate" => -> { @copy = ContentBlocks::Duplicate.call(@block).record },
      "move" => -> { ContentBlocks::Reorder.call(page, [ @copy.id, @block.id ]) },
      "delete" => -> { ContentBlocks::Destroy.call(@copy) }
    }

    writes.each do |name, write|
      Publishing.clear_changes(page)
      write.call
      assert marked?(page), "#{name} left no mark"
    end
    assert_equal base, page.reload.settings_changed_at
  end

  test "a post's tags mark it, also in a save that changes nothing else and in one that changes only its slug besides" do
    post = create_post(title: "Tagged", tags: %w[ruby])

    assert Posts::Save.call(post, attributes: { tag_names: %w[rails] }).ok?
    assert marked?(post)

    Publishing.clear_changes(post)
    assert Posts::Save.call(post, attributes: { tag_names: %w[ruby] }, translations: { "en" => { slug: "moved" } }).ok?
    assert marked?(post)
  end

  test "taking a copy clears the mark, and an unpublished record shows none whatever it kept" do
    page = create_page(title: "One")
    assert Pages::Save.call(page, translations: { "en" => { title: "Two" } }).ok?
    publish_changes(page)
    assert_not marked?(page)

    assert Pages::Save.call(page, translations: { "en" => { title: "Three" } }).ok?
    assert Pages::Save.call(page, attributes: { published: false }).ok?
    assert_not page.reload.unpublished_changes?
  end

  test "a publish that is refused leaves the mark where it was" do
    blog = create_page(title: "Blog", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    assert Pages::Save.call(blog, attributes: { published: true }).ok?
    post = create_post(title: "Hello")
    topic = create_page(title: "Topic", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: topic), attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => "x" } })
    create_page(title: "Hello", parent: topic)
    assert Posts::Save.call(post, attributes: { tag_names: %w[x] }).ok?
    assert marked?(post)
    assert Pages::Save.call(topic, attributes: { published: true }).ok?

    refused = Publishing::PublishChanges.call(post.reload)

    assert_not refused.ok?
    assert marked?(post), "the mark outlives a publish that was rolled back"
    assert_equal 1, Publishing::Version.of(post).count
  end

  test "the mark is no audited field and no change to a page's settings base" do
    post = create_post(title: "Audited")
    assert Posts::Save.call(post, translations: { "en" => { title: "Changed" } }).ok?

    assert_not Audit::Event.where(action: "post.updated", subject: post).last.field_changes.key?("unpublished_changes_at")
    assert_includes Page::SETTINGS_BASE_IGNORES, "unpublished_changes_at"
  end

  test "the mark moves nothing a stale check reads and does not move the public content version" do
    page = create_page(title: "Stale")
    page.reload
    updated, base = page.updated_at, page.settings_changed_at
    version = PublicSite::Version.current

    Publishing.note_change(page)

    assert marked?(page)
    page.reload
    assert_equal [ updated, base ], [ page.updated_at, page.settings_changed_at ]
    assert_equal version, PublicSite::Version.current
  end

  test "note_change marks the published and scheduled records of a relation and no draft" do
    live = create_post(title: "Live")
    draft = create_post(title: "Draft", published: false)

    Publishing.note_change(Post.where(id: [ live.id, draft.id ]))

    assert marked?(live)
    assert_not marked?(draft)
  end

  test "every column of pages and posts has a place, the mark included" do
    assert_includes Publishing::ROWS.fetch("Page"), "unpublished_changes_at"
    assert_includes Publishing::ROWS.fetch("Post"), "unpublished_changes_at"
  end

  test "a change of a live post's related posts alone sets no mark: they are in no copy; it still moves updated_at, so an open form goes stale" do
    post = create_post(title: "Has relations")
    other = create_post(title: "Related")
    before = post.reload.updated_at

    assert Posts::Save.call(post, attributes: { related_post_ids: [ other.id ] }).ok?

    assert_not marked?(post), "related posts are public at once and in no copy"
    assert_operator post.reload.updated_at, :>, before
    assert Publishing::Changes.of(post).none?

    assert Posts::Save.call(post, attributes: { related_post_ids: [], tag_names: %w[fresh] }).ok?
    assert marked?(post), "tags in the same save are a change"
  end

  # The mark is decided by the ROW (`published_at IS NOT NULL` in the UPDATE),
  # not by the object a request loaded before a colleague published.
  test "a write whose object was loaded before a colleague's publish still marks, and one loaded before an unpublish does not" do
    page = create_page(title: "Race", published: false)
    stale = Page.find(page.id)
    assert Pages::Save.call(Page.find(page.id), attributes: { published: true }).ok?
    assert_not marked?(page)

    assert ContentBlocks::Save.call(ContentBlock.new(owner: stale), attributes: { block_type: "rich_text" }).ok?
    assert marked?(page), "a block added through a page object that still believed it a draft"

    Publishing.clear_changes(page)
    assert Pages::Save.call(Page.find(page.id).tap { |row| row.published_at = nil; row.clear_attribute_changes([ :published_at ]) }, translations: { "en" => { subtitle: "Typed" } }).ok?
    assert marked?(page), "settings saved through such an object"

    live = Page.find(page.id)
    assert Pages::Save.call(Page.find(page.id), attributes: { published: false }).ok?
    Publishing.clear_changes(page)
    Pages::Save.call(live, translations: { "en" => { subtitle: "Again" } }) # saved or refused, the row says draft
    assert_not marked?(page), "a draft by its row has no mark whatever the object believed"
  end
end
