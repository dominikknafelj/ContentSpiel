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
    assert_equal "Plain words here again", entry.after
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
    assert_equal "New", entry.after
  end
end
