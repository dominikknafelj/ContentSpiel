require "test_helper"

# `Admin::DiagramDrawingsScreen::RowComponent`: one diagram in one language on
# the Draw diagrams list, as the server draws it (the design's states "Not
# drawn yet" and "Last drawing kept"; the run's states are the script's), and
# what it hands the script: the save's address, the language, the base and
# the source, which is a template's text and never an attribute.
class Admin::DiagramDrawingsScreen::RowComponentTest < ViewComponent::TestCase
  include ContentHelper

  EN = BlockTypes::Diagram::SAMPLE_SOURCES.fetch("en")
  TARGET = "data-admin--diagram--draw-all-target".freeze

  setup do
    Current.actor = users(:one)
    @record = create_page(title: "Flows", published: false)
  end
  teardown { Current.reset }

  def diagram(settings = {})
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @record), attributes: { block_type: "diagram" },
      translations: { "en" => { settings: { "source" => EN }.merge(settings) } }, actor: users(:one))
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def row(block, state: :not_drawn, locale: "en", source: EN) = Diagrams::ToDraw::Row.new(block:, page: @record, locale:, state:, source:)

  def draw(block, language_column: true, **row_options)
    render_inline Admin::DiagramDrawingsScreen::RowComponent.new(row: row(block, **row_options), language_column:)
  end

  test "a diagram with no drawing is not drawn yet" do
    draw(diagram)

    assert_selector "li[data-draw-row] .admin-state-chip[data-state-tone='warn']", text: "Not drawn yet"
  end

  test "a drawing of an earlier source is kept" do
    draw(diagram, state: :kept)

    assert_selector ".admin-state-chip[data-state-tone='warn']", text: "Last drawing kept"
  end

  test "the row reads the language's description" do
    draw(diagram("description" => "A draft goes to review."))

    assert_selector "[data-part='text']", text: "A draft goes to review."
    assert_no_selector "[data-part='text'].font-cs-mono"
  end

  test "with no description the row reads the source's first line in mono" do
    draw(diagram)

    assert_selector "[data-part='text'].font-cs-mono", exact_text: EN.lines.first.strip
  end

  test "the source's line skips the blank lines, a BOM and the comments before its keyword" do
    draw(diagram, source: "\uFEFF\n%% note\nflowchart TD\n  A --> B")

    assert_selector "[data-part='text'].font-cs-mono", exact_text: "flowchart TD"
  end

  test "the language column is drawn only beside other languages" do
    block = diagram
    draw(block)
    assert_selector "[data-part='language']", text: "English"

    draw(block, language_column: false)
    assert_no_selector "[data-part='language']"
  end

  test "the row is one link to the block in its page's editor, named by its text, language and state" do
    block = diagram("description" => "A draft goes to review.")
    draw(block)

    link = page.find("a.admin-row-link")
    assert_equal "/#{ContentSpiel::ADMIN_PATH}/pages/#{@record.id}#content_block_#{block.id}", link[:href]
    assert_equal "_top", link["data-turbo-frame"]
    named = link["aria-labelledby"].split.map { |id| page.find("##{id}", visible: :all).text(:all).strip }
    assert_equal [ "A draft goes to review.", "English", "Not drawn yet" ], named
    assert_equal "Open", page.find("##{link["aria-describedby"]}.admin-row-verb[aria-hidden='true']", visible: :all).text(:all).strip
  end

  test "a row in another language links to the editor in that language" do
    block = diagram
    draw(block, locale: "de")

    assert_equal "/#{ContentSpiel::ADMIN_PATH}/pages/#{@record.id}?locale=de#content_block_#{block.id}", page.find("a.admin-row-link")[:href]
  end

  test "the row hands the script the save's address, the language, the base and the source" do
    block = diagram
    source = "flowchart TD\n  A[\"<b>&\"] --> B"
    draw(block, source:)

    item = page.find("li[data-draw-row]")
    assert_equal "row", item[TARGET]
    assert_equal "/#{ContentSpiel::ADMIN_PATH}/diagram-drawings/#{block.id}", item["data-url"]
    assert_equal "en", item["data-locale"]
    assert_equal block.updated_at.iso8601(6), item["data-base"]
    elements = [ item.native, *item.native.css("*") ]
    assert(elements.none? { |node| node.attributes.values.any? { |value| value.value.include?("flowchart") } }, "no attribute carries the source")

    assert page.has_css?("li[data-draw-row] > template[data-part='source']", visible: :all)
    assert_equal source, Nokogiri::HTML5.fragment(rendered_content[%r{<template data-part="source">(.*?)</template>}m, 1]).text
  end

  test "the reason line is drawn empty and hidden, for the script" do
    draw(diagram)

    assert_selector "[data-part='reason'][hidden]", visible: :hidden, text: ""
  end
end
