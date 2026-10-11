require "test_helper"

class Publishing::SnapshotTest < ActiveSupport::TestCase
  # JSON keeps a time to the millisecond, so the two timestamps are left out
  # of the column-for-column comparisons below; nothing public reads them.
  TIMES = %w[created_at updated_at].freeze

  test "a page rebuilt from its copy is read-only, keeps the row's address columns and has the copy's fields and blocks" do
    page = create_page(title: "Pricing", published: false, translations: { "de" => { title: "Preise" } })
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: rich_doc("Hello") }, "de" => { body: rich_doc("Hallo") } }).record
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    version = Publishing.current(page)
    was = block.reload.attributes.deep_dup # the block is saved again below, in place

    assert Pages::Save.call(page, translations: { "en" => { title: "Prices", slug: "prices" } }).ok?
    assert ContentBlocks::Save.call(block, translations: { "en" => { body: rich_doc("Changed") } }).ok?

    view = Publishing::Snapshot.rebuild(version, page.reload)

    assert view.persisted?
    assert view.readonly?
    assert_equal page.id, view.id
    assert_equal page.parent_id, view.parent_id
    assert_equal "prices", Mobility.with_locale(:en) { view.slug }, "the slug is not in a copy: it is the row's"
    assert_equal "Pricing", Mobility.with_locale(:en) { view.title }
    assert_equal "Preise", Mobility.with_locale(:de) { view.title }
    assert_equal version, view.published_version
    assert view.association(:content_blocks).loaded?
    copy = view.content_blocks.to_a.sole
    assert copy.readonly?
    assert_equal was.except(*TIMES), copy.attributes.except(*TIMES)
    assert_same view, copy.owner
    assert_equal "Hallo", copy.body_document(locale: "de").to_markdown.strip
    assert_raises(ActiveRecord::ReadOnlyRecord) { view.update!(position: 9) }
    assert_raises(ActiveRecord::ReadOnlyRecord) { copy.update!(position: 9) }
    assert_equal "Prices", Mobility.with_locale(:en) { page.reload.title }, "rebuilding wrote nothing"
  end

  test "a page type and a hero image come back as the copy had them" do
    asset = create_media_asset
    page = Pages::Save.call(attributes: { parent: root_page, published: true, page_type: "landing", hero_media_asset_id: asset.id },
      translations: { "en" => { title: "Landing", hero_alt: "A room" } }).record
    version = Publishing.current(page)
    assert Pages::Save.call(page, attributes: { page_type: "standard", hero_media_asset_id: nil }).ok?

    view = Publishing::Snapshot.rebuild(version, page.reload)

    assert view.landing?
    assert_equal asset, view.hero_media_asset
    assert_equal({ "en" => "A room" }, view.read_attribute(:hero_alt))
  end

  test "a post rebuilt from its copy has the copy's text, fields and tags, and the row's slug and time" do
    post = create_post(title: "Hello", tags: %w[ruby])
    assert Posts::Save.call(post, translations: { "en" => { excerpt: "Short", body: rich_doc("Body") } }).ok?
    version = Publishing::Version.take!(post.reload)

    assert Posts::Save.call(post, attributes: { tag_names: %w[rails] }, translations: { "en" => { title: "Changed", body: rich_doc("Other") } }).ok?

    view = Publishing::Snapshot.rebuild(version, post.reload)

    assert view.readonly?
    assert_equal "Hello", Mobility.with_locale(:en) { view.title }
    assert_equal "Short", Mobility.with_locale(:en) { view.excerpt }
    assert_equal "Body", view.body_document(locale: "en").to_markdown.strip
    assert_equal %w[ruby], view.tags.map(&:name)
    assert view.association(:tags).loaded?
    assert_equal post.published_at, view.published_at
    assert_equal post.read_attribute(:slug), view.read_attribute(:slug)
  end

  test "without blocks a rebuilt page has its fields and no loaded blocks" do
    page = create_page(title: "Menu entry")

    view = Publishing::Snapshot.rebuild(Publishing.current(page), page, with_blocks: false)

    assert_equal "Menu entry", Mobility.with_locale(:en) { view.title }
    assert_not view.association(:content_blocks).loaded?
  end

  test "a list block's copy names the tag its filter meant by id, and a block rebuilt from it answers that id whatever the tag is called now" do
    tag = Tag.create!(name: "ruby")
    page = create_page(title: "Blog", published: false)
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page),
      attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => "ruby" } }).record
    assert_equal tag.id, block.listed_tag_id
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    version = Publishing.current(page)
    assert version.lists_posts
    tag.update!(name: "rubies")

    copy = Publishing::Snapshot.blocks_from(version, page).sole

    assert_equal tag.id, copy.listed_tag_id
    assert_nil block.reload.listed_tag_id, "the row asks by name, and no tag has that name now"
  end

  test "a column a copy does not know keeps the table's default, and a key the table does not know is ignored" do
    page = create_page(title: "Old copy")
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" })
    version = Publishing::Version.take!(page.reload)
    old = version.blocks.first.except("translated_settings").merge("a_column_since_removed" => 1)
    Publishing::Version.where(id: version.id).update_all(blocks: [ old ])

    copy = Publishing::Snapshot.blocks_from(version.reload, page).sole

    assert_equal({}, copy.translated_settings)
  end
end
