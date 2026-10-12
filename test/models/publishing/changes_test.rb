require "test_helper"

class Publishing::ChangesTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing", published: false)
    @first = add("First")
    @second = add("Second")
    @third = add("Third")
    assert Pages::Save.call(@page, attributes: { published: true }).ok?
  end

  def add(text, **attributes)
    ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }.merge(attributes),
      translations: (text ? { "en" => { body: rich_doc(text) } } : {})).record
  end

  def changes = Publishing::Changes.of(@page.reload)
  def kinds = changes.blocks.map { |entry| [ entry.kind, entry.block.id ] }

  test "nothing changed is none, with the baseline it was compared with" do
    assert changes.none?
    assert_equal 1, changes.version.number
    assert_empty changes.locales
  end

  test "typed and typed back is none, though the mark is set" do
    assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok?
    assert Pages::Save.call(@page, translations: { "en" => { title: "Pricing" } }).ok?

    assert @page.reload.unpublished_changes?
    assert changes.none?
  end

  test "a field of the record is named, with the language it changed in" do
    assert Pages::Save.call(@page, attributes: { page_type: "landing" }, translations: { "de" => { title: "Preise" }, "en" => { subtitle: "Plans" } }).ok?

    assert_equal %w[page_type subtitle title], changes.fields.sort
    assert_equal %w[de en], changes.locales
    assert_empty changes.blocks
  end

  test "a changed block, an added one and a removed one are each named once, the removed one as the copy had it" do
    assert ContentBlocks::Save.call(@first, translations: { "de" => { body: rich_doc("Erstens") } }).ok?
    added = add("Fourth")
    assert ContentBlocks::Destroy.call(@second).ok?

    assert_equal [ [ :changed, @first.id ], [ :added, added.id ], [ :removed, @second.id ] ], kinds
    removed = changes.blocks.last.block
    assert removed.readonly?
    assert_equal "Second", removed.body_document(locale: "en").to_markdown.strip
    assert_equal %w[de en], changes.locales
  end

  test "a block that changed places is moved, and the ones it passed are not" do
    assert ContentBlocks::Reorder.call(@page, [ @third.id, @first.id, @second.id ]).ok?

    assert_equal [ [ :moved, @third.id ] ], kinds
  end

  test "a block put into a section is moved, and the new section is added" do
    section = add(nil, block_type: "section", settings: { "layout" => "two" })
    assert ContentBlocks::Reorder.call(@page, [ @second.id ], section: section.id, column: 2, moved_from: { @second.id => { section_id: nil, column: nil } }).ok?

    assert_equal [ [ :moved, @second.id ], [ :added, section.id ] ].sort_by(&:last), kinds.sort_by(&:last)
  end

  test "a block changed and moved is changed" do
    assert ContentBlocks::Save.call(@third, translations: { "en" => { body: rich_doc("Third, edited") } }).ok?
    assert ContentBlocks::Reorder.call(@page, [ @third.id, @first.id, @second.id ]).ok?

    assert_equal [ [ :changed, @third.id ] ], kinds
  end

  test "a post's text, fields and tags are named; a renamed tag is a change of its tags" do
    post = create_post(title: "Hello", tags: %w[ruby])
    assert Posts::Save.call(post, attributes: { tag_names: %w[ruby rails] }, translations: { "en" => { body: rich_doc("Body") } }).ok?

    assert_equal %w[body tags], Publishing::Changes.of(post.reload).fields.sort

    publish_changes(post)
    Tag.find_by!(name: "ruby").update!(name: "rubies")
    assert_equal %w[tags], Publishing::Changes.of(post.reload).fields
  end

  test "a record's bookkeeping is not a change: confirming a translation moves no field" do
    assert Pages::Save.call(@page, translations: { "de" => { title: "Preise" } }).ok?
    publish_changes(@page)
    @page.update_columns(translation_sources: { "title" => { "de" => "en" } }) # version: none (a test writes bookkeeping the way a translation confirmation does) # changes: none (a test writes translation bookkeeping)

    assert changes.none?
  end

  test "a record with no copy has nothing to compare with: none, and no version" do
    bare = create_page(title: "Bare", published: false)

    result = Publishing::Changes.of(bare)

    assert result.none?
    assert_nil result.version
  end

  test "the comparison costs the same statements for 3 blocks as for 13" do
    few = capture_sql { changes.blocks }.size
    10.times { |index| add("More #{index}") }

    assert_equal few, capture_sql { changes.blocks }.size
  end

  test "it takes no lock and writes nothing: a view of a page may ask" do
    assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok?
    statements = capture_sql { Publishing::Changes.of(@page.reload).fields }

    assert_empty statements.grep(/FOR UPDATE|\A\s*(INSERT|UPDATE|DELETE)/i)
  end

  def listing_page(title)
    page = create_page(title: title, published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    page
  end

  test "nothing differs, nothing is taken away: lost_addresses is empty, and Changes.of itself reads no address and has no such answer" do
    assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok?
    result = nil
    statements = capture_sql { result = Publishing::Changes.of(@page.reload); result.fields }
    assert_empty statements.grep(/public_paths|FOR UPDATE/), "Changes.of reads no address and takes no lock"
    assert_not_respond_to result, :lost_addresses

    assert_empty Publishing::Changes.lost_addresses(@page), "a title takes nothing away"
    assert_empty Publishing::Changes.lost_addresses(create_page(title: "Same"))
    assert_empty Publishing::Changes.lost_addresses(create_page(title: "Draft", published: false))
  end

  # `test/integration/public_drafts_test.rb`: "removing a page's list block and
  # publishing drops a live post to no address". Named beforehand, as data, by
  # a call of its own that nothing makes on a GET.
  test "removing a page's list block names the live posts a publish would leave without an address" do
    blog = listing_page("Blog")
    topic = listing_page("Topic")
    create_page(title: "Hello", parent: topic)
    post = create_post(title: "Hello")
    assert ContentBlocks::Destroy.call(blog.content_blocks.sole).ok?

    expected = %w[de en es].map { |locale| { record_type: "Post", record_id: post.id, locale: locale, path: "/blog/hello" } }
    assert_equal expected, Publishing::Changes.lost_addresses(blog.reload).sort_by { |row| row[:locale] }
    assert_equal "/blog/hello", PublicSite::Urls.new.path_for(post, "en"), "asking moved nothing"
    assert_equal 1, Publishing::Version.of(blog).count, "and kept no copy"
    assert_empty Publishing::Changes.lost_addresses(topic.reload)
  end
end
