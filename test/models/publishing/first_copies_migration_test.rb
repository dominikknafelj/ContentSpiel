require "test_helper"
require Rails.root.join("db/migrate/20261011120000_create_published_versions")

# The migration makes the first copies by logic frozen in its own file. While
# `Publishing::Snapshot.of` still has the same shape the two must agree; when
# this test fails because the shape of a copy changed on purpose, the change
# needs a SUCCESSOR migration (a copy taken by the old one is still right for
# the day it ran), and this comparison is then narrowed, not the migration
# edited.
class FirstCopiesMigrationTest < ActiveSupport::TestCase
  def migrate = CreatePublishedVersions.new.take_first_copies

  def add_block(page, **attributes)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }.merge(attributes))
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  # Both ways for the same record: the migration's, then (after removing its
  # copy) the application's. Only the times differ.
  def both_ways(record)
    Publishing::Version.where(record_type: record.class.polymorphic_name, record_id: record.id).delete_all # version: none (the test retakes the copy)
    assert_equal 1, migrate
    frozen = Publishing::Version.of(record).sole
    Publishing::Version.where(id: frozen.id).delete_all # version: none (the test retakes the copy)
    app = Publishing::Version.take!(record.reload)
    [ frozen, app ]
  end

  def assert_same_copy(frozen, app)
    assert_equal app.number, frozen.number
    assert_equal app.snapshot, frozen.snapshot
    assert_equal app.blocks, frozen.blocks
    assert_equal app.lists_posts, frozen.lists_posts
    assert_equal app.tag_ids, frozen.tag_ids
  end

  test "the migration's copy of a page is the application's: sections, columns, a list block with its tag, a landing page with its hero" do
    tag = Tag.create!(name: "ruby")
    asset = create_media_asset
    page = Pages::Save.call(attributes: { parent: root_page, published: true, page_type: "landing", hero_media_asset_id: asset.id },
      translations: { "en" => { title: "Landing", subtitle: "Be quick", hero_alt: "A room" }, "de" => { title: "Landung", slug: "landung" } }).record
    add_block(page, translations: { "en" => { body: rich_doc("Hello") }, "de" => { body: rich_doc("Hallo") } })
    add_block(page, block_type: "image", media_asset_id: asset.id, translations: { "en" => { caption: "Cap", alt: "Alt" } })
    add_block(page, block_type: "post_list", settings: { "content_type" => "blog", "tag" => "Ruby" })
    section = add_block(page, block_type: "section", settings: { "layout" => "two" })
    add_block(page, section_id: section.id, section_column: 2)
    add_block(page, section_id: section.id, section_column: 1)
    add_block(page)
    assert_equal tag.id, page.content_blocks.find_by(block_type: "post_list").listed_tag_id

    frozen, app = both_ways(page)

    assert_same_copy(frozen, app)
    assert frozen.lists_posts
    assert_equal "landing", frozen.snapshot.dig("fields", "page_type")
  end

  test "the migration's copy of a post is the application's, with its tags and its type's fields" do
    post = create_post(title: "Role", content_type: "resume_entry", tags: %w[ruby rails])
    assert Posts::Save.call(post, attributes: { fields: { company: "Example Co", role_type: "ic" } },
      translations: { "en" => { excerpt: "Short", body: rich_doc("Body") } }).ok?

    frozen, app = both_ways(post)

    assert_same_copy(frozen, app)
    assert_equal 2, frozen.tag_ids.size
  end

  test "it gives every published and scheduled record its first copy, leaves a draft without one and a copied record alone, and a second run finds nothing" do
    live = create_page(title: "Live", published: false)
    scheduled = create_post(title: "Scheduled", published: false)
    draft = create_page(title: "Draft", published: false)
    copied = create_page(title: "Has one")
    block = add_block(live)
    live.update_columns(published_at: 1.day.ago) # version: none (a record published before the table existed)
    scheduled.update_columns(published_at: 1.day.from_now) # version: none (a record scheduled before the table existed)

    assert_equal 2, migrate

    assert_equal [ block.id ], Publishing.current(live).blocks.map { |row| row["id"] }
    assert_equal Publishing::Version.of(scheduled).sole, Publishing.current(scheduled)
    assert_not copied?(draft)
    assert_equal 1, Publishing::Version.of(copied).count
    assert_equal 0, migrate, "a second run finds nothing to do"
  end
end
