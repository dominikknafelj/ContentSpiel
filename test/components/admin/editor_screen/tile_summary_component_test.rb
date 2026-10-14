require "test_helper"

# The one line on a block's tile (sections spec §4.2), and what marks a tile
# that needs attention. What the line is comes from the type's definition.
class Admin::EditorScreen::TileSummaryComponentTest < ViewComponent::TestCase
  include ContentHelper
  include TestTypes
  include LogCapture

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

  # Block types spec, decision 8: a type's tile line is data its definition
  # answers, drawn here; its words are CS Studio's, under the type's own
  # scope (a slash in the name read as a dot). Parts of one look stand as
  # one: the line's markup is what it was when the tile wrote them itself.
  test "a type's summary is drawn part by part: text and words plain, code in the monospace face, a hint in the meta colour" do
    I18n.backend.store_translations(:en, admin: { components: { editor_screen: { tile_summary: { types: { test: { quote: { by: "by %{who}", none: "Nothing yet" } } } } } } })
    with_test_types do
      BlockTypes.fetch("test/quote").summary(->(block, locale:) { [ [ :word, :by, { who: "Ada" } ], [ :text, " · " ], [ :mono, "q = 1" ] ] })
      render_summary block("test/quote", settings: { "text" => "Q" })
      assert_equal "by Ada · q = 1", page.find(line).text
      assert_selector "#{line} > span.font-cs-mono", exact_text: "q = 1", count: 1
      assert_equal "by Ada · ", Nokogiri::HTML5.fragment(rendered_content).at_css(line).children.first.text, "the plain parts are one text, as before"

      BlockTypes.fetch("test/quote").summary(->(block, locale:) { [ [ :hint, :none ] ] })
      render_summary block("test/quote", settings: { "text" => "Q" })
      assert_selector "#{line} > span.text-meta", exact_text: "Nothing yet"
    end
  ensure
    I18n.reload!
  end

  # Task 8 review M1: a part is text. A run of one part is not joined, so
  # an `html_safe` string a type hands over would reach the template still
  # marked safe and be drawn as markup, unless the tile makes it plain.
  test "a part marked html_safe is drawn as text, alone in its run and joined with others" do
    with_test_types do
      [ [ [ :text, "<b>bold</b>".html_safe ] ], [ [ :text, "<b>a</b>".html_safe ], [ :text, "<i>b</i>".html_safe ], [ :mono, "<u>c</u>".html_safe ] ] ].each do |answer|
        BlockTypes.fetch("test/quote").summary(->(_block, locale:) { answer })
        render_summary block("test/quote", settings: { "text" => "Q" })
        assert_no_selector "#{line} b, #{line} i, #{line} u"
        assert_includes page.find(line).text, "<"
      end
    end
  end

  # A built-in's summary is the CMS's own code: a fault in it fails loudly,
  # in the tests first.
  test "a built-in's summary that answers a part of no known kind raises and names the kinds" do
    BlockTypes.fetch("code").summary(->(block, locale:) { [ [ :bold, "x" ] ] })
    error = assert_raises(ArgumentError) { render_summary block("code") }
    assert_includes error.message, "text, word, mono, hint"
  ensure
    Rails.application.reloader.prepare!
  end

  # Task 4 review M2: an outside type's summary is a gem's code, and a fault
  # in it was a 500 on every editor page that holds a block of the type. Its
  # tile shows the type's label instead, and the log says it once per
  # registration, naming the type and the error's class, never the block's
  # content or the error's message, which can quote it.
  test "an outside type's summary that raises or answers an unknown kind draws the type's label, and is logged once without the content" do
    with_test_types do
      quote = block("test/quote", settings: { "text" => "Private words" })
      BlockTypes.fetch("test/quote").summary(->(block, locale:) { raise "no #{block.settings_object.text}" })
      log = capture_log([ Rails ]) do
        2.times do
          render_summary quote
          assert_equal "Quote", page.find(line).text
        end
      end
      assert_equal 1, log.scan("test/quote").size, log
      assert_includes log, "RuntimeError"
      assert_not_includes log, "Private words"

      BlockTypes.fetch("test/quote").summary(->(block, locale:) { [ [ :bold, block.settings_object.text ] ] })
      log = capture_log([ Rails ]) { render_summary quote }
      assert_equal "Quote", page.find(line).text
      assert_empty log, "said once for the type's registration"
    end

    with_test_types do
      BlockTypes.fetch("test/quote").summary(->(block, locale:) { [ [ :bold, block.settings_object.text ] ] })
      log = capture_log([ Rails ]) { render_summary block("test/quote", settings: { "text" => "Private words" }) }
      assert_equal "Quote", page.find(line).text
      assert_includes log, "test/quote"
      assert_includes log, "ArgumentError"
      assert_not_includes log, "Private words"
    end
  end

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

  test "a post list naming a content type that is no longer registered reads as its stored name" do
    retired = block("post_list", settings: { "content_type" => "blog", "tag" => "old" })
    retired.update_column(:settings, { "content_type" => "retired", "tag" => "old" }) # version: none (a test stores a type the registry no longer holds)
    render_summary retired.reload
    assert_selector line, text: "retired · tag old", exact_text: true
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

  # Design answer C7.
  test "a code block is its file name; else its language and its first line of code, or the line alone for plain text; and an empty one says Empty" do
    render_summary block("code", settings: { "language" => "yaml", "filename" => "config/deploy.yml", "code" => "service: site" })
    assert_equal "config/deploy.yml", page.find(line).text
    assert_no_selector "#{line} span", visible: :all

    render_summary block("code", settings: { "language" => "ruby", "code" => "    class Post < ApplicationRecord\nend" })
    assert_equal "Ruby · class Post < ApplicationRecord", page.find(line).text
    assert_selector "#{line}.truncate > span.font-cs-mono", exact_text: "class Post < ApplicationRecord", count: 1
    assert_equal "Ruby · ", Nokogiri::HTML5.fragment(rendered_content).at_css(line).children.first.text, "the language is in the tile's own face, straight in the line"

    render_summary block("code", settings: { "code" => "    first line\nsecond line" })
    assert_equal "first line", page.find(line).text
    assert_selector "#{line} > span.font-cs-mono", exact_text: "first line"

    render_summary block("code", settings: { "code" => "x" * 200 })
    assert_equal 80, page.find(line).text.length
    assert_selector "#{line}.truncate", count: 1

    render_summary block("code")
    assert_selector "#{line} > span.text-meta", exact_text: "Empty"
    assert_equal "Empty", page.find(line).text
    assert_no_selector attention
    assert_no_selector "img"

    render_summary block("code", settings: { "language" => "ruby" })
    assert_equal "Empty", page.find(line).text, "a language chosen for code that is not there yet is still an empty block"
  end

  test "a code block's line that looks like markup is text, and a refused save says so after it" do
    render_summary block("code", settings: { "language" => "html", "code" => "<b>bold</b> & <script>x</script>" }), invalid: true

    assert_equal "HTML · <b>bold</b> & <script>x</script> · Needs fixing", page.find(line).text
    assert_no_selector "#{line} b, #{line} script", visible: :all
    assert_selector attention

    render_summary block("code"), invalid: true
    assert_equal "Empty · Needs fixing", page.find(line).text
  end

  # Task 4 review M5: the line is the type's summary now, and each kind of
  # part it answers is text on the tile, the file name's plain part as much
  # as the code's monospace one.
  test "a code block's file name that looks like markup is text on the type's summary path" do
    assert BlockTypes.fetch(:code).summary, "the Code type answers its own line"
    render_summary block("code", settings: { "filename" => "<i>x</i> & <script>y</script>.erb", "code" => "a" })

    assert_equal "<i>x</i> & <script>y</script>.erb", page.find(line).text
    assert_no_selector "#{line} i, #{line} script", visible: :all
  end

  # A language can be stored around the services (the select refuses it),
  # and the summary asks `CodeHighlight.label`, which knows only the list.
  test "a code block whose stored language is not on the list reads as plain text: its first line alone" do
    code = block("code", settings: { "code" => "x = 1\ny = 2" })
    code.update_columns(settings: code.settings.merge("language" => "xojo")) # version: none (a test)
    render_summary code.reload
    assert_equal "x = 1", page.find(line).text
    assert_selector "#{line} > span.font-cs-mono", exact_text: "x = 1"
    assert_no_selector attention
  end
end
