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
end
