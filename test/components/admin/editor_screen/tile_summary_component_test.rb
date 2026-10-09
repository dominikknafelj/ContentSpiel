require "test_helper"

# The one line on a block's tile (sections spec §4.2), and what marks a tile
# that needs attention. What the line is comes from the type's definition.
class Admin::EditorScreen::TileSummaryComponentTest < ViewComponent::TestCase
  include ContentHelper
  include TestTypes

  # `@site_page`, not `@page`: `render_inline` keeps its Capybara node in `@page`.
  setup do
    @site_page = create_page(title: "Tile summary")
    @section = @site_page.content_blocks.create!(block_type: "section", position: 0)
  end

  def block(type, **attributes) = @site_page.content_blocks.create!(block_type: type, section: @section, section_column: 1, position: 0, **attributes)

  def render_summary(block, **options)
    render_inline Admin::EditorScreen::TileSummaryComponent.new(block: block, locale: "en", **options)
  end

  def attention = "[role='img'][aria-label='Needs attention']"

  # The line itself, without the mark and the thumbnail beside it.
  def line = ".admin-block-tile__summary > span:last-child"

  test "it is the element the save answer replaces" do
    text = block("rich_text")
    render_summary(text)

    assert_equal "block-#{text.id}-tile-summary", Admin::EditorScreen::TileSummaryComponent.dom_id(text)
    assert_selector "span#block-#{text.id}-tile-summary.admin-block-tile__summary"
  end

  test "a text is the start of its first paragraph, cut at eighty characters" do
    render_summary block("rich_text", body: rich_doc("#{"word " * 30}\n\nSecond paragraph"))

    text = page.find(line).text
    assert_equal 80, text.length
    assert text.start_with?("word word"), text
    assert text.end_with?("..."), text
    assert_no_text "Second paragraph"
    assert_no_selector attention
  end

  test "a text with nothing in it says so and needs no attention" do
    render_summary block("rich_text")

    assert_selector ".admin-block-tile__summary", text: "Empty text"
    assert_no_selector attention
  end

  test "a text is read in the language being edited" do
    text = block("rich_text", body: rich_doc("English text"))

    render_inline Admin::EditorScreen::TileSummaryComponent.new(block: text, locale: "de")

    assert_selector ".admin-block-tile__summary", text: "Empty text"
  end

  test "an image is its file name beside a small thumbnail" do
    render_summary block("image", media_asset: create_media_asset)

    assert_selector ".admin-block-tile__summary", text: "tiny.png"
    assert_selector ".admin-block-tile__summary img[alt=''][src]"
    assert_no_selector attention
  end

  test "an image block without an image needs attention" do
    render_summary block("image")

    assert_selector ".admin-block-tile__summary", text: "No image chosen"
    assert_selector attention
    assert_no_selector "img"
  end

  test "a post list is its filter: the content type's label or all posts, then the tag" do
    render_summary block("post_list")
    assert_selector line, text: "All posts", exact_text: true

    render_summary block("post_list", settings: { "content_type" => "blog", "tag" => "rails" })
    assert_selector line, text: "#{ContentTypes.find("blog").label} · tag rails", exact_text: true
    assert_no_selector attention
  end

  test "a type that is no longer registered says so and needs attention" do
    gone = block("rich_text")
    gone.update_column(:block_type, "gone/thing")

    render_summary gone.reload

    assert_selector ".admin-block-tile__summary", text: "Unavailable type — gone/thing"
    assert_selector attention
  end

  test "a type with no image, no body and no listing has no line, and still a line's height" do
    with_test_types do
      render_summary block("test/quote", translated_settings: { "en" => { "text" => "Hello" } })

      assert_selector line, text: "", exact_text: true
      assert_selector ".admin-block-tile__summary[class~='min-h-[1lh]']"
      assert_no_selector attention
    end
  end

  test "an invalid save is added to the line and needs attention" do
    render_summary block("post_list", settings: { "tag" => "rails" }), invalid: true

    assert_selector ".admin-block-tile__summary", text: "All posts · tag rails · Needs fixing"
    assert_selector attention
  end
end
