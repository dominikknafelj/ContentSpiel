require "test_helper"

# `Blocks::TableComponent` (table block spec, "The public side"): a focusable
# scroll region named by the caption or by the word "Table", and a table whose
# header row, header column and alignments are what the body says.
class Blocks::TableComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  GRID = "| Plan | Price |\n| --- | ---: |\n| Basic | 5 |\n| Pro | 12 |".freeze

  def table_block(markdown = GRID, caption: nil, locale: :en)
    block = root_page.content_blocks.new(block_type: :table, position: 0)
    block.assign_body(rich_doc(markdown, tables: true), locale: locale) if markdown
    block.caption = caption if caption
    block.save!
    block
  end

  def draw(block) = render_inline(Blocks::TableComponent.new(block: block, page: root_page))

  test "a header row draws thead and th scope=col" do
    draw(table_block)

    assert_selector "thead th[scope=col]", count: 2
    assert_selector "thead th[scope=col]", text: "Plan"
    assert_selector "tbody tr", count: 2
    assert_selector "tbody td", count: 4
    assert_no_selector "th[scope=row]"
  end

  test "a header column draws th scope=row" do
    block = table_block
    document = block.body_document(locale: :en).to_h
    document["content"][0]["content"].each_with_index do |row, index|
      row["content"][0]["type"] = "tableHeader" unless index.zero?
    end
    block.assign_body(document, locale: :en)
    block.save!
    draw(block)

    assert_selector "tbody th[scope=row]", count: 2
    assert_selector "tbody td", count: 2
  end

  test "both, and neither" do
    draw(table_block("| a | b |\n| --- | --- |\n| c | d |").tap { |b| b.update!(body: b.body) })
    assert_selector "thead", count: 1

    block = table_block
    document = block.body_document(locale: :en).to_h
    document["content"][0]["content"].each { |row| row["content"].each { |cell| cell["type"] = "tableCell" } }
    block.assign_body(document, locale: :en)
    block.save!
    draw(block)

    assert_no_selector "thead"
    assert_no_selector "th"
    assert_selector "tbody tr", count: 3
  end

  test "each alignment is a class on its cells" do
    draw(table_block("| a | b | c |\n| :-- | :-: | --: |\n| 1 | 2 | 3 |\n| 4 | 5 | 6 |"))

    assert_selector "th.align-left", count: 1
    assert_selector "th.align-center", count: 1
    assert_selector "th.align-right", count: 1
    assert_selector "td.align-left", count: 2
    assert_selector "td.align-center", count: 2
    assert_selector "td.align-right", count: 2
  end

  test "a caption names the scroll box; without one the box is named Table" do
    block = table_block(caption: "Plans compared")
    draw(block)

    assert_selector "div.table-scroll[tabindex='0'][role='region'][aria-labelledby='table-#{block.id}-caption']", count: 1
    assert_selector "table > caption#table-#{block.id}-caption", text: "Plans compared"
    assert_no_selector "div.table-scroll[aria-label]"

    draw(table_block)
    assert_selector "div.table-scroll[role='region'][aria-label='Table']"
    assert_no_selector "caption"
  end

  test "text that looks like markup is text" do
    block = table_block
    document = block.body_document(locale: :en).to_h
    document["content"][0]["content"][1]["content"][0]["content"][0]["content"] = [ { "type" => "text", "text" => "<script>x</script>" } ]
    block.assign_body(document, locale: :en)
    block.save!
    draw(block)

    assert_no_selector "script", visible: :all
    assert_includes rendered_content, "&lt;script&gt;"
  end

  test "a long unbroken word is in the cell" do
    word = "x" * 300
    draw(table_block("| a | b |\n| --- | --- |\n| #{word} | d |"))

    assert_selector "td", text: word
  end

  test "an empty table draws nothing" do
    draw(table_block(nil))
    assert_no_selector ".content-block--table"

    draw(table_block("| |  |\n| --- | --- |\n| | |"))
    assert_no_selector ".content-block--table"
  end

  test "a language without a table draws the default language's" do
    block = table_block
    I18n.with_locale(:de) { draw(block) }

    assert_selector "thead th", text: "Plan"
  end
end
