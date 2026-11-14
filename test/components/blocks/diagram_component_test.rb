require "test_helper"

# `Blocks::DiagramComponent` (Diagram block spec §6): the drawing as an image
# named by the description, its ids its own, the source and the drawing
# falling back together, and nothing at all without a drawing that passes on
# read or without a description.
class Blocks::DiagramComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

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

  test "nothing is drawn with no drawing, with no description, or with a drawing that fails on read" do
    [
      english.except("drawing"),
      english.except("description"),
      english.merge("drawing" => { "svg" => %(<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>), "from" => "x" }),
      english.merge("drawing" => { "svg" => "not xml", "from" => "x" })
    ].each do |values|
      render_in(:en, block_with({ "en" => values }))
      assert_empty rendered_content.strip, values.keys.inspect
    end
  end

  test "a language without its own source shows the default's drawing, with its own description or else the default's" do
    block = block_with({ "en" => english, "de" => { "description" => "Ein Entwurf geht zur Prüfung." } })
    render_in(:de, block)
    assert_equal "Ein Entwurf geht zur Prüfung.", page.find("svg > title", visible: :all).text(:all)
    assert_includes rendered_content, "Draft"

    render_in(:es, block)
    assert_equal "A draft goes to review.", page.find("svg > title", visible: :all).text(:all)
    assert_equal "diagram-#{block.id}-es-title", page.find("svg")["aria-labelledby"]
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
end
