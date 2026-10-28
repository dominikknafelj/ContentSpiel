require "test_helper"

# GFM tables in the Markdown converter (table block spec, decision 10): read as
# a `table` node only with `tables: true`, written always.
class RichText::MarkdownTableTest < ActiveSupport::TestCase
  def para(*nodes) = { "type" => "paragraph", "content" => nodes }
  def text(string, *marks) = { "type" => "text", "text" => string }.tap { |node| node["marks"] = marks.map { |mark| { "type" => mark } } if marks.any? }

  def cell(type, nodes, align = nil)
    { "type" => type, "content" => [ para(*nodes) ] }.tap { |node| node["attrs"] = { "align" => align } if align }
  end

  def table(*rows) = RichText::Document.new("type" => "doc", "content" => [ { "type" => "table", "content" => rows.map { |cells| { "type" => "tableRow", "content" => cells } } } ])

  def load_tables(markdown) = RichText::Document.from_markdown(markdown, tables: true)

  test "a table with a header row, alignment, bold and a link dumps to GFM and loads back to the same document with tables: true" do
    link = { "type" => "link", "attrs" => { "href" => "https://example.com/" } }
    document = table(
      [ cell("tableHeader", [ text("Name") ], "left"), cell("tableHeader", [ text("Qty") ], "center"), cell("tableHeader", [ text("Price") ], "right"), cell("tableHeader", [ text("Note") ]) ],
      [ cell("tableCell", [ text("Flour", "bold") ], "left"), cell("tableCell", [ text("2") ], "center"), cell("tableCell", [ text("1.50") ], "right"), cell("tableCell", [ text("see "), { "type" => "text", "text" => "shop", "marks" => [ link ] } ]) ])

    markdown = document.to_markdown
    assert_equal [ "| Name | Qty | Price | Note |", "| :--- | :---: | ---: | --- |" ], markdown.lines.first(2).map(&:chomp)

    loaded, warnings = load_tables(markdown)
    assert_empty warnings
    assert_equal document.to_h, loaded.to_h
    assert_empty loaded.validate
  end

  test "cell text with a pipe, a backslash and a line break comes back unchanged" do
    document = table(
      [ cell("tableHeader", [ text("a|b") ]), cell("tableHeader", [ text("c\\d") ]) ],
      [ cell("tableCell", [ text("x"), { "type" => "hardBreak" }, text("y|z") ]), cell("tableCell", [ text("p|q", "code") ]) ])

    markdown = document.to_markdown
    assert_equal 3, markdown.lines.size, "a hard break must not break the row's line"
    assert_includes markdown, "<br>"

    loaded, warnings = load_tables(markdown)
    assert_empty warnings
    assert_equal document.to_h, loaded.to_h
  end

  test "a hand-written <br>, <br/> and <br /> in a cell are hard breaks, and nowhere else" do
    loaded, = load_tables("| a<br>b | c<br/>d | e<br />f |\n| - | - | - |\n| x | y | z |\n")
    breaks = loaded.to_h["content"].first["content"].first["content"].map { |header| header["content"].first["content"].map { |node| node["type"] } }
    assert_equal [ %w[text hardBreak text] ] * 3, breaks

    outside, warnings = RichText::Document.from_markdown("a<br>b\n", tables: true)
    assert_equal [ %w[text] ], outside.to_h["content"].map { |block| block["content"].map { |node| node["type"] } }
    assert warnings.any? { |warning| warning.include?("HTML") }
  end

  test "a GFM table with a short row loads padded to the header's width" do
    loaded, = load_tables("| a | b | c |\n| --- | :-: | --: |\n| 1 |\n| 2 | 3 | 4 |\n")
    assert_equal [ 3, 3 ], [ 1, 2 ].map { |index| loaded.to_h["content"].first["content"][index]["content"].size }
    padded = loaded.to_h["content"].first["content"][1]["content"]
    assert_equal [ [ nil ], [ "center" ], [ "right" ] ], padded.map { |cell| [ cell.dig("attrs", "align") ] }
    assert_equal [], padded.last["content"].first["content"]
    assert_equal [ 3, 3 ], TableBody.new(loaded).shape
  end

  test "without tables: true a GFM table still degrades to one paragraph per row, with the warning" do
    document, warnings = RichText::Document.from_markdown("| a | b |\n| - | - |\n| 1 | 2 |\n")
    assert_equal [ "paragraph" ] * 2, document.to_h["content"].map { |block| block["type"] }
    assert_includes warnings, "degraded a table to one paragraph per row"
  end

  test "a table without a header row is written with its first row as the header" do
    document = table([ cell("tableCell", [ text("a") ]) ], [ cell("tableCell", [ text("b") ]) ])
    loaded, = load_tables(document.to_markdown)
    assert_equal %w[tableHeader tableCell], loaded.to_h["content"].first["content"].map { |row| row["content"].first["type"] }
    assert_equal TableBody.new(document).shape, TableBody.new(loaded).shape
  end
end
