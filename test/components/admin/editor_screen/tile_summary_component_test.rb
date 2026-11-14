require "test_helper"

# The one line on a block's tile (sections spec §4.2), and what marks a tile
# that needs attention. What the line is comes from the type's definition.
class Admin::EditorScreen::TileSummaryComponentTest < ViewComponent::TestCase
  include ContentHelper
  include TestTypes
  include LogCapture
  include ThemeTestHelper

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

  # A type's summary line as the tile draws it when the type's preview has
  # nothing to show (a blank one, or none): the preview is answered nil for
  # the length of the block, and the registries are built again after it.
  def summary_only(*types)
    types.each { |type| BlockTypes.fetch(type).preview(->(block, locale:) { nil }) }
    yield
  ensure
    Rails.application.reloader.prepare!
  end

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

  # A built-in's summary is the CMS's own code: a fault in it fails loudly,
  # in the tests first.
  test "a built-in's summary that answers a part of no known kind raises and names the kinds" do
    BlockTypes.fetch("code").summary(->(block, locale:) { [ [ :bold, "x" ] ] })
    error = assert_raises(ArgumentError) { render_summary block("code") }
    assert_includes error.message, "text, word, mono, hint"
  ensure
    Rails.application.reloader.prepare!
  end

  # An outside type's summary is a gem's code, and a fault
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

  # The preview (`ContentModel::Preview`, the type's `preview`): a heading
  # over a few lines of text, drawn in place of the summary line, under the
  # one id a save's answer replaces.
  def heading_row = ".admin-block-tile__summary > .admin-block-tile__heading"
  def heading = "#{heading_row} > .admin-block-tile__title"
  def text = ".admin-block-tile__summary > .admin-block-tile__text"

  test "a rich-text tile shows its first heading and two or three lines of its text" do
    shown = block("rich_text", body: rich_doc("## Opening hours\n\nWe open at nine.\n\n- And close at five."))
    render_summary shown

    assert_selector "span##{Admin::EditorScreen::TileSummaryComponent.dom_id(shown)}.admin-block-tile__summary"
    assert_selector "#{heading}.block.truncate.text-base.font-semibold.text-ink", exact_text: "Opening hours"
    assert_selector "#{text}.line-clamp-3.text-sm.text-dim", exact_text: "We open at nine. And close at five."
    assert_no_selector "#{text}.font-cs-mono"
    assert_no_selector ".admin-block-tile__summary > span.truncate", text: "We open"
    assert_no_selector attention
  end

  test "a rich text with no heading first shows its text alone, its opening words included" do
    render_summary block("rich_text", body: rich_doc("Opening words.\n\n## Later heading\n\nMore."))

    assert_no_selector heading
    assert_selector text, exact_text: "Opening words. More."
  end

  test "a code tile shows its file name and its first lines in the mono look" do
    render_summary block("code", settings: { "language" => "yaml", "filename" => "config/deploy.yml", "code" => "service: site\nimage: site\nservers:\n  - 1.2.3.4" })

    assert_selector heading, exact_text: "config/deploy.yml"
    assert_no_selector "#{heading}.font-cs-mono"
    assert_selector "#{text}.font-cs-mono.line-clamp-3.whitespace-pre-wrap", text: "service: site\nimage: site\nservers:", normalize_ws: false
    assert_no_text "1.2.3.4"

    render_summary block("code", settings: { "language" => "ruby", "code" => "class Post\nend" })
    assert_selector heading, exact_text: "Ruby"
    assert_selector "#{text}.font-cs-mono", text: "class Post"
  end

  test "a type with no preview keeps its summary line" do
    render_summary block("post_list", settings: { "tag" => "rails" })

    assert_nil BlockTypes.fetch(:post_list).preview
    assert_selector line, exact_text: "All posts · tag rails"
    assert_no_selector heading
    assert_no_selector text
  end

  test "a preview that looks like markup is drawn as text" do
    body = { "type" => "doc", "content" => [
      { "type" => "heading", "attrs" => { "level" => 2 }, "content" => [ { "type" => "text", "text" => "<i>Head</i>" } ] },
      { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "<script>alert(1)</script> & <b>bold</b>" } ] }
    ] }
    render_summary block("rich_text", body: body)

    assert_no_selector "script, b, i", visible: :all
    assert_text "<script>"
    assert_selector heading, exact_text: "<i>Head</i>"
    assert_selector text, exact_text: "<script>alert(1)</script> & <b>bold</b>"
  end

  test "a long preview is cut at PREVIEW_LENGTH and clamped to three lines" do
    render_summary block("rich_text", body: rich_doc("## #{"Heading " * 20}\n\n#{"word " * 100}"))

    drawn = page.find(text).text
    assert_equal ContentModel::BlockTypeDefinition::PREVIEW_LENGTH, drawn.length
    assert drawn.end_with?("…"), drawn
    assert_selector "#{text}.line-clamp-3"
    assert_equal ContentModel::BlockTypeDefinition::SUMMARY_LENGTH, page.find(heading).text.length
    assert_selector "#{heading}.truncate"
  end

  test "an empty rich-text block keeps today's empty line, not an empty heading" do
    render_summary block("rich_text", body: rich_doc("## \n\n"))

    assert_selector line, exact_text: "Empty text"
    assert_no_selector heading
    assert_no_selector text
  end

  # A preview is the block's own content. A heading that only falls back
  # (a Note's kind word, a Code block's language) is not: with no title or
  # file name and no text, the tile says Empty on its summary line.
  test "an empty Note shows its summary's Empty, not its kind's word alone" do
    render_summary block("note", settings: { "kind" => "tip" })

    assert_no_selector heading_row
    assert_equal "Tip · Empty", page.find(line).text
    assert_selector "#{line} > span.text-meta", exact_text: "Empty"
  end

  test "an empty Code block with a language shows Empty, not the language alone" do
    render_summary block("code", settings: { "language" => "ruby" })

    assert_no_selector heading_row
    assert_equal "Empty", page.find(line).text

    render_summary block("code", settings: { "language" => "ruby", "filename" => "app.rb" })
    assert_selector heading, exact_text: "app.rb"
    assert_no_selector text
  end

  test "a refused save says Needs fixing under the preview" do
    render_summary block("rich_text", body: rich_doc("## Head\n\nWords")), invalid: true

    assert_selector heading, exact_text: "Head"
    assert_selector ".admin-block-tile__summary > :last-child", exact_text: "Needs fixing"
    assert_selector attention
  end

  test "a card with a title and an image shows the thumbnail beside its heading" do
    pictured = block("card", media_asset_id: create_media_asset(filename: "tiny.png").id)
    pictured.assign_settings({ "title" => "Our services", "text" => "What we do" }, locale: "en")
    pictured.save!
    render_summary pictured

    assert_selector "#{heading_row} img", count: 1
    assert_selector "#{heading_row} > :last-child#{heading.delete_prefix(heading_row + " > ")}", exact_text: "Our services"
    assert_selector text, exact_text: "What we do"
  end

  # Review focus 3: an outside type's `preview` is a gem's code. One that
  # raises, or answers something that is not a Preview, would be a 500 on
  # every editor page holding a block of the type; its tile draws the
  # summary line instead, and the log and the error reporter hear it once
  # per registration, by the type and the error's class, never its message.
  test "a type whose preview raises draws its summary line and logs once" do
    reports = []
    subscriber = Rails.error.subscribe(Class.new { define_method(:report) { |error, context:, **| reports << [ error.class, context[:block_type] ] } }.new)
    with_test_types do
      BlockTypes.fetch("test/quote").summary(->(block, locale:) { [ [ :text, "Quoted" ] ] })
      quote = block("test/quote", settings: { "text" => "Private words" })
      BlockTypes.fetch("test/quote").preview(->(block, locale:) { raise "no #{block.settings_object.text}" })
      log = capture_log([ Rails ]) do
        2.times do
          render_summary quote
          assert_equal "Quoted", page.find(line).text
          assert_no_selector heading
        end
      end
      assert_equal 1, log.scan("test/quote").size, log
      assert_includes log, "RuntimeError"
      assert_not_includes log, "Private words"
      assert_equal [ [ RuntimeError, "test/quote" ] ], reports
    end

    with_test_types do
      BlockTypes.fetch("test/quote").preview(->(block, locale:) { "a string, not a Preview" })
      log = capture_log([ Rails ]) { render_summary block("test/quote", settings: { "text" => "Q" }) }
      assert_no_selector heading
      assert_selector line
      assert_includes log, "ArgumentError"
      assert_equal ArgumentError, reports.last.first
    end
  ensure
    Rails.error.unsubscribe(subscriber) if subscriber
  end

  test "a table, a note and a card show their previews: a caption, a title or a kind's word over their words" do
    table = block("table", caption: "Plans")
    table.assign_body(rich_doc("| Plan | Price |\n| --- | --- |\n| A | 1 |", tables: true), locale: :en)
    table.save!
    render_summary table
    assert_selector heading, exact_text: "Plans"
    assert_selector text, exact_text: "Plan · Price"

    note = block("note", settings: { "kind" => "tip" })
    note.assign_body(rich_doc("First words of the note."), locale: :en)
    note.save!
    render_summary note
    assert_selector heading, exact_text: "Tip"
    assert_selector text, exact_text: "First words of the note."

    note.assign_settings({ "title" => "Before you publish" }, locale: "en")
    note.save!
    render_summary note
    assert_selector heading, exact_text: "Before you publish"

    card = block("card")
    card.assign_settings({ "title" => "Our services", "text" => "What we do" }, locale: "en")
    card.save!
    render_summary card
    assert_selector heading, exact_text: "Our services"
    assert_selector text, exact_text: "What we do"
  end

  test "a built-in's preview that answers something other than a Preview raises" do
    BlockTypes.fetch("code").preview(->(block, locale:) { "text" })
    assert_raises(ArgumentError) { render_summary block("code") }
  ensure
    Rails.application.reloader.prepare!
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

  test "an image's thumbnail is never the original" do
    asset = create_media_asset
    asset.update_columns(width: 1600, height: 1200, preview: nil, renditions: {}) # version: none (a test's own state)

    render_summary block("image", media_asset: asset.reload)

    assert_selector "[data-image-empty]"
    assert_no_match %r{/blobs/}, rendered_content
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
    summary_only("code") do
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
  end

  test "a code block's line that looks like markup is text, and a refused save says so after it" do
    summary_only("code") do
      render_summary block("code", settings: { "language" => "html", "code" => "<b>bold</b> & <script>x</script>" }), invalid: true

      assert_equal "HTML · <b>bold</b> & <script>x</script> · Needs fixing", page.find(line).text
      assert_no_selector "#{line} b, #{line} script", visible: :all
      assert_selector attention

      render_summary block("code"), invalid: true
      assert_equal "Empty · Needs fixing", page.find(line).text
    end
  end

  # The line is the type's summary now, and each kind of
  # part it answers is text on the tile, the file name's plain part as much
  # as the code's monospace one.
  test "a code block's file name that looks like markup is text on the type's summary path" do
    summary_only("code") do
      assert BlockTypes.fetch(:code).summary, "the Code type answers its own line"
      render_summary block("code", settings: { "filename" => "<i>x</i> & <script>y</script>.erb", "code" => "a" })

      assert_equal "<i>x</i> & <script>y</script>.erb", page.find(line).text
      assert_no_selector "#{line} i, #{line} script", visible: :all
    end
  end

  # A language can be stored around the services (the select refuses it),
  # and the summary asks `CodeHighlight.label`, which knows only the list.
  test "a code block whose stored language is not on the list reads as plain text: its first line alone" do
    summary_only("code") do
      code = block("code", settings: { "code" => "x = 1\ny = 2" })
      code.update_columns(settings: code.settings.merge("language" => "xojo")) # version: none (a test)
      render_summary code.reload
      assert_equal "x = 1", page.find(line).text
      assert_selector "#{line} > span.font-cs-mono", exact_text: "x = 1"
      assert_no_selector attention
    end
  end

  # Note block spec, "CS Studio": the kind's word or the editor's title,
  # " · " and the start of the text; an empty text says "Empty" in the meta
  # colour. Plan ruling 6: the tile only. The kind's icon is not a part of
  # the line: the tile draws it before the line (plan ruling 12,
  # block_tile_component_test.rb), and the summary draws none.
  test "a table's tile reads Table · 3 × 3 · and its first header words" do
    summary_only("table") do
      table = block("table")
      table.assign_body(rich_doc("| Plan | Price | Storage |\n| --- | --- | --- |\n| A | 1 | 2 |\n| B | 3 | 4 |", tables: true), locale: :en)
      table.save!
      render_summary table

      assert_text "Table · 3 × 3 · Plan Price Storage"

      blank_head = block("table")
      blank_head.assign_body(rich_doc("| | |\n| --- | --- |\n| A | 1 |", tables: true), locale: :en)
      blank_head.save!
      render_summary blank_head
      assert_text "Table · 2 × 2 · A 1"

      empty = block("table")
      render_summary empty
      assert_text "Empty table"
    end
  end

  test "a card is its icon's label and its title; an empty one says Empty" do
    summary_only("card") do
      with_choices_theme do
        card = block("card", settings: { "icon" => "brush" })
        card.assign_settings({ "title" => "Our services" }, locale: "en")
        card.save!
        render_summary card
        assert_equal "Design · Our services", page.find(line).text

        titled = block("card")
        titled.assign_settings({ "title" => "No icon here" }, locale: "en")
        titled.save!
        render_summary titled
        assert_equal "No icon here", page.find(line).text

        retired = block("card")
        retired.update_columns(settings: { "icon" => "retired" }) # version: none (a test's row, written around the services) # changes: none (a test's row)
        render_summary retired
        assert_equal "Empty", page.find(line).text
        assert_selector "#{line} > span.text-meta", exact_text: "Empty"
      end

      render_summary block("card")
      assert_equal "Empty", page.find(line).text
    end
  end

  test "a note is its word or its title and the start of its text; one without text says Empty" do
    summary_only("note") do
      note = block("note", settings: { "kind" => "tip" })
      note.assign_body(rich_doc("First words of the note.\n\nA second paragraph."), locale: :en)
      note.save!
      render_summary note
      assert_no_selector ".admin-block-tile__summary svg", visible: :all
      assert_equal "Tip · First words of the note.", page.find(line).text

      note.assign_settings({ "title" => "Before you publish" }, locale: "en")
      note.save!
      render_summary note
      assert_equal "Before you publish · First words of the note.", page.find(line).text

      empty = block("note")
      render_summary empty
      assert_equal "Note · Empty", page.find(line).text
      assert_selector "#{line} > span.text-meta", exact_text: "Empty"
    end
  end

  test "a note's title that looks like markup is text on its tile, and an unknown kind reads as a Note" do
    summary_only("note") do
      note = block("note", settings: { "kind" => "tip" })
      note.assign_settings({ "title" => "<i>x</i> & <script>y</script>" }, locale: "en")
      note.save!
      note.update_columns(settings: { "kind" => "gone" }) # version: none (a test writes a kind around the services)
      render_summary note.reload

      assert_equal "<i>x</i> & <script>y</script> · Empty", page.find(line).text
      assert_no_selector "#{line} i, #{line} script", visible: :all
    end
  end

  test "a note whose kind is not on the list says Note on its tile" do
    summary_only("note") do
      note = block("note", settings: { "kind" => "tip" })
      note.update_columns(settings: { "kind" => "gone" }) # version: none (a test writes a kind around the services)
      render_summary note.reload

      assert_equal "Note · Empty", page.find(line).text
    end
  end

  test "a card's image is optional: no mark without one, its words as they were, the image's title when it has none" do
    summary_only("card") do
      render_summary block("card")
      assert_no_selector attention
      assert_selector line, text: "Empty"

      asset = create_media_asset(filename: "tiny.png")
      asset.update!(title: "Harbour photo")
      pictured = block("card", media_asset_id: asset.id)
      render_summary pictured
      assert_no_selector attention
      assert_equal "Harbour photo", page.find(line).text
      assert_selector ".admin-block-tile__summary img", count: 1

      pictured.assign_settings({ "title" => "Our services" }, locale: "en")
      pictured.save!
      render_summary pictured
      assert_equal "Our services", page.find(line).text
    end
  end

  test "a card linked to a page counts as linked for the image's alt, and the tile never prints the reference" do
    summary_only("card") do
      asset = create_media_asset(filename: "tiny.png")
      asset.update!(title: "Harbour photo", alt: "")
      target = create_page(title: "Our services")

      linked = block("card", media_asset_id: asset.id, settings: { "link" => "cs:page/#{target.id}" })
      render_summary linked
      assert_selector "#{line} .text-meta", exact_text: "Image link has no alt text"

      linked.assign_settings({ "title" => "Card words" }, locale: "en")
      linked.save!
      render_summary linked
      assert_equal "Card words", page.find(line).text
    end
  end

  test "a card whose image is its only link and has no alt says so; words, an alt or no link say nothing of it" do
    summary_only("card") do
      asset = create_media_asset(filename: "tiny.png")
      asset.update!(title: "Harbour photo", alt: "")
      hint = "#{line} .text-meta"

      linked = block("card", media_asset_id: asset.id, settings: { "link" => "/about" })
      render_summary linked
      assert_selector hint, exact_text: "Image link has no alt text"

      linked.update!(alt: "My words")
      render_summary linked
      assert_equal "Harbour photo", page.find(line).text
      # The English override is what a German visitor reads too while nothing nearer exists: named, so no hint.
      render_summary linked, locale: "de"
      assert_no_selector hint

      linked.update!(alt: nil)
      linked.assign_settings({ "text" => "Words" }, locale: "en")
      linked.save!
      render_summary linked
      assert_no_selector hint

      render_summary block("card", media_asset_id: asset.id)
      assert_no_selector hint
      render_summary block("card", settings: { "link" => "/about" })
      assert_no_selector "#{line} .text-meta", text: "alt"
    end
  end

  test "an image block without an image is still marked: it is all the block is" do
    render_summary block("image")
    assert_selector attention
  end

  # -- The Diagram block's tile: a small picture of its stored drawing beside
  # its line (label · first line in mono, then the hints in the meta colour)
  # and the description's opening words. --

  DIAGRAM_SOURCE = "flowchart LR\n  A --> B\n  B --> C\n  C --> D".freeze

  # The sample's cleaned drawing, marked as drawn from `from`'s digest.
  def diagram_drawing(from = DIAGRAM_SOURCE) = { "svg" => BlockTypes::Diagram.sample_drawing("en")["svg"], "from" => Diagrams::Drawing.digest(from) }

  def diagram(translations) = block("diagram", translated_settings: translations)

  def diagram_line(block) = "##{Admin::EditorScreen::TileSummaryComponent.part_ids(block)[1]}"
  def diagram_words(block) = "##{Admin::EditorScreen::TileSummaryComponent.text_id(block)}"
  def picture = ".admin-block-tile__picture"

  test "the tile reads Flowchart · A --> B, Empty with no source, and the two hints" do
    drawn = diagram("en" => { "source" => DIAGRAM_SOURCE, "drawing" => diagram_drawing, "description" => "Four boxes in a row, each pointing to the next." })
    render_summary drawn
    assert_selector diagram_line(drawn), exact_text: "Flowchart · A --> B"
    assert_selector "#{diagram_line(drawn)} .font-cs-mono", exact_text: "A --> B"
    assert_no_selector "#{diagram_line(drawn)} .text-meta"
    assert_selector diagram_words(drawn), exact_text: "Four boxes in a row, each pointing to the next."
    assert_selector picture

    empty = diagram({})
    render_summary empty
    assert_selector "#{diagram_line(empty)} .text-meta", exact_text: "Empty"
    assert_no_selector picture
    assert_no_selector diagram_words(empty)

    undescribed = diagram("en" => { "source" => DIAGRAM_SOURCE, "drawing" => diagram_drawing })
    render_summary undescribed
    assert_selector diagram_line(undescribed), exact_text: "Flowchart · A --> B · No description"
    assert_selector "#{diagram_line(undescribed)} .text-meta", exact_text: "No description"
    assert_no_selector ".text-danger, .text-danger-ink"

    kept = diagram("en" => { "source" => "#{DIAGRAM_SOURCE}\n  D --> A", "drawing" => diagram_drawing, "description" => "Boxes." })
    render_summary kept
    assert_selector diagram_line(kept), exact_text: "Flowchart · A --> B · Last drawing kept"
    assert_selector "#{diagram_line(kept)} .text-meta", exact_text: "Last drawing kept"
    assert_selector "#{picture} svg", count: 1, visible: :all
    assert_no_selector ".text-danger, .text-danger-ink, [class*='opacity']"

    undrawn = diagram("en" => { "source" => DIAGRAM_SOURCE, "description" => "Boxes." })
    render_summary undrawn
    assert_selector diagram_line(undrawn), exact_text: "Flowchart · A --> B · Not drawn yet"
    assert_selector "#{diagram_line(undrawn)} .text-meta", exact_text: "Not drawn yet"
    assert_no_selector picture
    assert_selector "#{diagram_words(undrawn)} .font-cs-mono", text: "flowchart LR\n  A --> B\n  B --> C", normalize_ws: false
    assert_no_text "C --> D"
  end

  # The picture follows the site's fallback: a language with no source of its
  # own shows the default language's source and drawing, named by that
  # language's description unless it has one of its own.
  test "a language with no source of its own shows the default language's line, picture and description" do
    fallback = diagram("en" => { "source" => DIAGRAM_SOURCE, "drawing" => diagram_drawing, "description" => "Boxes." })
    render_summary fallback, locale: "de"
    assert_selector diagram_line(fallback), exact_text: "Flowchart · A --> B"
    assert_selector diagram_words(fallback), exact_text: "Boxes."
    assert_selector picture

    own = diagram("en" => { "source" => DIAGRAM_SOURCE, "drawing" => diagram_drawing, "description" => "Boxes." },
                  "de" => { "source" => "sequenceDiagram\n  Alice ->> Bob: Hallo", "description" => "Eine Nachricht." })
    render_summary own, locale: "de"
    assert_selector diagram_line(own), exact_text: "Sequence · Alice ->> Bob: Hallo · Not drawn yet"
    # A language with a source of its own never shows another language's drawing.
    assert_no_selector picture
  end

  test "the sample's tile reads its type and its first drawing line, past its accessibility lines" do
    sample = diagram("en" => { "source" => BlockTypes::Diagram::SAMPLE_SOURCES["en"].strip, "drawing" => BlockTypes::Diagram.sample_drawing("en"), "description" => "A flow." })
    render_summary sample
    assert_selector diagram_line(sample), exact_text: "Flowchart · A[Draft] --> B{Review}"
  end

  # One tile reads its drawing once: the hints, the picture and its markup
  # share one parse.
  test "a tile parses its drawing once" do
    drawn = diagram("en" => { "source" => DIAGRAM_SOURCE, "drawing" => diagram_drawing, "description" => "Boxes." })
    parses = 0
    read = Diagrams::Drawing.method(:read)
    with_singleton_override(Diagrams::Drawing, :read, ->(svg) { parses += 1; read.call(svg) }) { render_summary drawn }
    assert_selector picture
    assert_equal 1, parses
  end

  test "the tile's picture is the stored drawing with tile ids, no title and no script" do
    drawn = diagram("en" => { "source" => DIAGRAM_SOURCE, "drawing" => diagram_drawing, "description" => "Boxes <b>in</b> a row." })
    render_summary drawn

    box = page.find(picture, visible: :all)
    assert_equal "true", box["aria-hidden"]
    assert_selector "#{picture} > .content-block--diagram[aria-hidden='true'] > svg[role='img']", visible: :all
    prefix = "diagram-tile-#{drawn.id}-en-"
    ids = page.all("#{picture} [id]", visible: :all).map { |element| element["id"] }
    assert_operator ids.size, :>, 1
    assert ids.all? { |id| id.start_with?(prefix) }, ids.reject { |id| id.start_with?(prefix) }.inspect
    assert_includes ids, "#{prefix}d-1"
    # No title: hidden from a screen reader, the picture needs no name, and a
    # title would be a tooltip over the tile's face.
    assert_no_selector "#{picture} title", visible: :all
    assert_no_selector "#{picture} [aria-labelledby]", visible: :all
    html = page.native.to_html
    assert_no_match(/<script|\son\w+=|href=|<b>in/i, html)

    gone = diagram("en" => { "source" => DIAGRAM_SOURCE, "drawing" => { "svg" => "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1 1'><script/></svg>", "from" => Diagrams::Drawing.digest(DIAGRAM_SOURCE) }, "description" => "Boxes." })
    render_summary gone
    assert_no_selector picture, visible: :all
    assert_selector diagram_line(gone), exact_text: "Flowchart · A --> B · Not drawn yet"
  end

  test "a diagram tile that was refused says Needs fixing after its line" do
    drawn = diagram("en" => { "source" => DIAGRAM_SOURCE, "drawing" => diagram_drawing, "description" => "Boxes." })
    render_summary drawn, invalid: true
    assert_selector diagram_line(drawn), exact_text: "Flowchart · A --> B · Needs fixing"
    assert_selector attention
  end
end
