require "test_helper"

class Publishing::TextDiffTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing", published: false)
    @block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: rich_doc("Plain words here") } }).record
    assert Pages::Save.call(@page, attributes: { published: true }).ok?
    @version = Publishing.baseline(@page.reload)
  end

  def changes = Publishing::Changes.between(@page.reload, from: @version, to: :working)
  def edit_body(markdown) = assert(ContentBlocks::Save.call(@block, translations: { "en" => { body: rich_doc(markdown) } }).ok?)
  def words(segments, kind) = segments.select { |k, _| k == kind }.map(&:last).join.strip

  test "a title change in one language diffs words in that language only" do
    assert Pages::Save.call(@page, translations: { "de" => { title: "Alt" } }).ok?
    publish_changes(@page)
    @version = Publishing.baseline(@page.reload)
    assert Pages::Save.call(@page, translations: { "de" => { title: "Neu" } }).ok?

    overview = changes
    german = Publishing::TextDiff.field(overview, "title", locale: :de).result
    assert_equal "Alt", words(german.segments, :delete)
    assert_equal "Neu", words(german.segments, :insert)
    assert_not Publishing::TextDiff.field(overview, "title", locale: :en).result.changed?
  end

  test "a rich-text body is compared as its Markdown" do
    edit_body("Plain words here again")
    overview = changes
    entry = Publishing::TextDiff.block(overview, overview.blocks.first, locale: :en)
    assert_equal "again", words(entry.result.segments, :insert)
    assert_equal [ "Plain words here again" ], entry.after.map(&:shown)
  end

  test "a body that only became bold is formatting only" do
    edit_body("**Plain words here**")
    overview = changes
    entry = Publishing::TextDiff.block(overview, overview.blocks.first, locale: :en)
    assert entry.result.formatting_only?
  end

  test "a body past the word limit says too long" do
    edit_body((%w[word] * 4001).join(" "))
    overview = changes
    entry = Publishing::TextDiff.block(overview, overview.blocks.first, locale: :en)
    assert entry.result.too_long
  end

  test "an added block has no before" do
    added = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: rich_doc("New") } }).record
    overview = changes
    change = overview.blocks.find { |entry| entry.block.id == added.id }
    entry = Publishing::TextDiff.block(overview, change, locale: :en)

    assert_equal :added, change.kind
    assert_nil entry.before
    assert_nil entry.result
    assert_equal [ :body ], entry.after.map(&:label)
    assert_equal "New", entry.after.first.shown
  end

  test "settings are named by their schema label and diffed as values, never with the label in the words" do
    note = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "note", settings: { "title" => "Heads up" } },
      translations: { "en" => { body: rich_doc("Careful") } }).record
    assert Pages::Save.call(@page, attributes: { published: true }).ok?
    publish_changes(@page)
    @version = Publishing.baseline(@page.reload)
    result = ContentBlocks::Save.call(note, attributes: { settings: { "title" => "Heads down" } })
    assert result.ok?, result.errors.to_sentence

    overview = changes
    entry = Publishing::TextDiff.block(overview, overview.blocks.first, locale: :en)

    assert_includes entry.after.map(&:label), "Title"
    assert_equal "Heads down", entry.after.find { |part| part.label == "Title" }.shown
    assert_equal "down", words(entry.result.segments, :insert)
    assert_equal "up", words(entry.result.segments, :delete)
    assert entry.result.segments.none? { |_kind, text| text.include?("Title") }
  end

  test "caption and alt are parts named by key and diffed by their values" do
    image = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "image" },
      translations: { "en" => { caption: "A cap", alt: "An alt" } }).record
    publish_changes(@page)
    @version = Publishing.baseline(@page.reload)
    assert ContentBlocks::Save.call(image, translations: { "en" => { caption: "A new cap" } }).ok?

    overview = changes
    entry = Publishing::TextDiff.block(overview, overview.blocks.first, locale: :en)

    assert_equal [ :caption, :alt ], entry.after.map(&:label)
    assert_equal [ "A new cap", "An alt" ], entry.after.map(&:shown)
    assert_equal "new", words(entry.result.segments, :insert)
    assert_empty words(entry.result.segments, :delete)
  end

  test "a structured value is named as changed and has no words" do
    parts = Publishing::TextDiff.block_parts({ "block_type" => "rich_text", "settings" => {}, "body" => nil }, :en)
    assert_empty parts
    was = [ Publishing::TextDiff::Part.new(label: "Rows", shown: nil, compared: [ { "a" => 1 } ]) ]
    now = [ Publishing::TextDiff::Part.new(label: "Rows", shown: nil, compared: [ { "a" => 2 } ]) ]

    assert_equal [ "Rows" ], Publishing::TextDiff.opaque_changes(was, now)
    assert_empty Publishing::TextDiff.opaque_changes(was, was)
    assert Publishing::TextDiff.text_part("Tags", [ "a", "b" ]).then { |part| part.shown == "a, b" }
    assert Publishing::TextDiff.text_part("Rows", { "a" => 1 }).opaque?
  end

  test "a removed block has no after" do
    assert ContentBlocks::Destroy.call(@block).ok?
    overview = changes
    change = overview.blocks.first
    entry = Publishing::TextDiff.block(overview, change, locale: :en)

    assert_equal :removed, change.kind
    assert_nil entry.after
    assert_nil entry.result
    assert_equal "Plain words here", entry.before.first.shown
  end

  test "a post's tags are compared as their names, in alphabetical order" do
    post = create_post(title: "Post", tags: %w[zebra apple])
    version = Publishing.baseline(post.reload)
    assert Posts::Save.call(post, attributes: { tag_names: %w[zebra apple mango] }).ok?

    entry = Publishing::TextDiff.field(Publishing::Changes.between(post.reload, from: version, to: :working), "tags", locale: :en)
    assert_equal "Tags", entry.label
    assert_equal [ "apple, zebra" ], entry.before.map(&:shown)
    assert_equal [ "apple, mango, zebra" ], entry.after.map(&:shown)
    assert_equal "mango,", words(entry.result.segments, :insert)
  end

  test "a field with no words, a hero image, is named as changed and diffs nothing" do
    image = create_media_asset
    assert Pages::Save.call(@page, attributes: { hero_media_asset_id: image.id }).ok?

    entry = Publishing::TextDiff.field(changes, "hero_media_asset_id", locale: :en)
    assert_equal [ "Hero image" ], entry.opaque
    assert_not entry.result.changed?
    assert entry.after.sole.opaque?
  end
end
