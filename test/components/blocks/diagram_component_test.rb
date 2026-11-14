require "test_helper"

# `Blocks::DiagramComponent` (Diagram block spec §6): the drawing as an image
# named by the description, its ids its own, the source and the drawing
# falling back together, and nothing at all without a drawing that passes on
# read or without a description.
class Blocks::DiagramComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper
  include LogCapture

  SAMPLE = BlockTypes.fetch(:diagram).sample.translations

  def drawing(locale) = SAMPLE.fetch(locale)[:drawing]
  def source(locale) = SAMPLE.fetch(locale)[:source]

  # A saved block whose translated settings are exactly these, per language.
  def block_with(translations, caption: nil)
    block = root_page.content_blocks.create!(block_type: "diagram", position: root_page.content_blocks.count)
    block.update_columns(translated_settings: translations, caption: caption ? { "en" => caption } : {})
    block.reload
  end

  def render_in(locale, block)
    I18n.with_locale(locale) { render_inline Blocks::DiagramComponent.new(block: block, page: root_page) }
  end

  def english = { "source" => source("en"), "drawing" => drawing("en"), "description" => "A draft goes to review." }

  # The test environment's cache is the null store, so every read cleans
  # again; these tests read through a real one.
  def with_memory_cache
    was = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = was
  end

  BROKEN = %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><script>alert("secret words")</script></svg>)

  test "the figure holds an svg with role img, labelled by the description's title, sized from its viewBox, over its caption" do
    block = block_with({ "en" => english }, caption: "How a page is published")
    render_in(:en, block)

    svg = page.find("figure.content-block.content-block--diagram > .content-block--diagram__scroll > svg")
    title_id = "diagram-#{block.id}-en-title"
    assert_equal "img", svg[:role]
    assert_equal title_id, svg["aria-labelledby"]
    assert_equal "A draft goes to review.", page.find("svg > title##{title_id}", visible: :all).text(:all)
    view_box = Diagrams::Drawing.new(drawing("en"))
    assert_equal [ view_box.width, view_box.height ].map { |value| format("%.3f", value).sub(/\.?0+\z/, "") }, [ svg[:width], svg[:height] ]
    assert_equal "diagram-#{block.id}-en-d-2", svg["aria-describedby"], "Mermaid's accDescr describes it"
    assert_selector "figure > figcaption", text: "How a page is published"
  end

  test "a figure without a caption has no figcaption" do
    render_in(:en, block_with({ "en" => english }))

    assert_selector "figure svg"
    assert_no_selector "figcaption"
  end

  test "nothing is drawn with no drawing, with no description, or with a drawing that fails on read, and the failure is logged once with no content" do
    [
      english.except("drawing"),
      english.except("description"),
      english.merge("drawing" => { "svg" => %(<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>), "from" => "x" }),
      english.merge("drawing" => { "svg" => "not xml", "from" => "x" })
    ].each do |values|
      render_in(:en, block_with({ "en" => values }))
      assert_empty rendered_content.strip, values.keys.inspect
    end

    with_memory_cache do
      block = block_with({ "en" => english.merge("drawing" => { "svg" => BROKEN, "from" => "x" }) })
      log = capture_log { 3.times { render_in(:en, block) } }

      assert_empty rendered_content.strip
      assert_equal 1, log.scan("Blocks::DiagramComponent").size, "once, not once per visitor: #{log}"
      assert_match(/block #{block.id}\b.*\belement\b/, log, "the block and the reason")
      assert_no_match(/secret words|script|alert/, log, "never the content")
    end
  end

  test "the read is cached by the stored drawing, the block, the language and the revision, and a cached read parses nothing" do
    block = block_with({ "en" => english })
    stored = drawing("en")["svg"]

    with_memory_cache do
      render_in(:en, block)
      first = rendered_content
      key = [ "diagram", Digest::SHA256.hexdigest(stored), block.id, "en", Diagrams::Drawing::REVISION ]
      assert_equal key, Blocks::DiagramComponent.cache_key(stored, block_id: block.id, locale: :en)
      assert Rails.cache.exist?(key), "the read is in the cache under its key"

      parsing = ->(*) { raise "a cached read parsed the drawing" }
      with_singleton_override(Diagrams::Drawing, :read, parsing) do
        with_singleton_override(Diagrams::Drawing, :clean, parsing) do
          render_in(:en, block)
          assert_equal first, rendered_content, "the second read is the cache's"

          block.update_columns(translated_settings: { "en" => english.merge("description" => "Reviewed, then published.") })
          render_in(:en, block.reload)
          assert_equal "Reviewed, then published.", page.find("svg > title", visible: :all).text(:all), "the title is the description as it is now, never a cached one"
        end
      end
    end
  end

  test "the drawing keeps its natural size, scales down to three fifths of it and then scrolls in its own box, which is a keyboard stop named by the description" do
    block = block_with({ "en" => english })
    render_in(:en, block)

    width = Diagrams::Drawing.new(drawing("en")).width
    svg = page.find(".content-block--diagram__scroll > svg")
    assert_equal "--diagram-min-width: #{format("%.3f", width * 0.6).sub(/\.?0+\z/, "")}px", svg[:style]
    box = page.find(".content-block--diagram__scroll")
    assert_equal "0", box[:tabindex]
    assert_equal "group", box[:role]
    assert_equal "A draft goes to review.", box["aria-label"]
  end

  test "a language without its own source shows the default's drawing, with its own description or else the drawing's language's" do
    block = block_with({ "en" => english, "de" => { "description" => "Ein Entwurf geht zur Prüfung." } })
    render_in(:de, block)
    assert_equal "Ein Entwurf geht zur Prüfung.", page.find("svg > title", visible: :all).text(:all)
    assert_includes rendered_content, "Draft"

    render_in(:es, block)
    assert_equal "A draft goes to review.", page.find("svg > title", visible: :all).text(:all)
    assert_equal "diagram-#{block.id}-es-title", page.find("svg")["aria-labelledby"]
  end

  test "a description from further down the chain never names a drawing: Spanish on the English drawing, with none in English and one in German, draws nothing" do
    block = block_with({ "en" => english.except("description"), "de" => { "description" => "Ein Entwurf geht zur Prüfung." } })
    render_in(:es, block)

    assert_empty rendered_content.strip
  end

  test "a language with its own source and no description draws nothing, whatever the default's description" do
    block = block_with({ "en" => english, "de" => { "source" => source("de"), "drawing" => drawing("de") } })
    render_in(:de, block)

    assert_empty rendered_content.strip
  end

  test "a language with its own source shows only its own drawing, never the default's" do
    own = block_with({ "en" => english, "de" => { "source" => source("de"), "drawing" => drawing("de"), "description" => "Ein Entwurf." } })
    render_in(:de, own)
    assert_includes rendered_content, "Entwurf"
    assert_not_includes rendered_content, "Draft"

    undrawn = block_with({ "en" => english, "de" => { "source" => source("de"), "description" => "Ein Entwurf." } })
    render_in(:de, undrawn)
    assert_empty rendered_content.strip, "a German source with no drawing of its own draws nothing"
  end

  test "two diagram blocks of the same drawing on one page share no id" do
    first, second = 2.times.map { block_with({ "en" => english }) }
    ids = [ first, second ].map do |block|
      render_in(:en, block)
      page.all("[id]", visible: :all).map { |element| element[:id] }
    end

    assert ids.all?(&:any?)
    assert_empty ids.first & ids.last
  end

  test "text in the description that looks like markup is text" do
    render_in(:en, block_with({ "en" => english.merge("description" => "<b>bold</b> & <script>x</script>") }))

    assert_no_selector "b, script", visible: :all
    assert_equal "<b>bold</b> & <script>x</script>", page.find("svg > title", visible: :all).text(:all)
  end

  test "the component and its template mark nothing safe, and only Diagrams::Drawing parses SVG" do
    %w[app/components/blocks/diagram_component.rb app/components/blocks/diagram_component.html.erb].each do |path|
      assert_no_match(/html_safe|\braw\b|safe_join|<%==|SafeBuffer|escape:\s*false|Nokogiri|Loofah/, Rails.root.join(path).read, path)
    end
    parsing = Dir[Rails.root.join("app/**/*.rb")].select { |path| (text = File.read(path)).match?(/Nokogiri::XML\b/) && text.match?(/diagram/i) }
    assert_equal [ Rails.root.join("app/values/diagrams/drawing.rb").to_s ], parsing, "the one file of the Diagram block that parses a drawing"
  end
end
