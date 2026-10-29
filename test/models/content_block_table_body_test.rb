require "test_helper"

# Where a table may be (table block spec, decision 2): in the body of a block
# type that declares `body_content :table`, as exactly one table, and in no
# other body.
class ContentBlockTableBodyTest < ActiveSupport::TestCase
  def setup
    @page = create_page(title: "Tables")
  end

  def text(value) = { "type" => "text", "text" => value }
  def paragraph(value = "x") = { "type" => "paragraph", "content" => [ text(value) ] }
  def cell(value = "x") = { "type" => "tableCell", "content" => [ paragraph(value) ] }
  def row(*cells) = { "type" => "tableRow", "content" => cells }
  def table(*rows) = { "type" => "table", "content" => rows }
  def doc(*nodes) = { "type" => "doc", "content" => nodes }
  def grid(columns, rows, value: "x") = table(*Array.new(rows) { row(*Array.new(columns) { cell(value) }) })

  def block(type, body)
    block = ContentBlock.new(owner: @page, position: 0, block_type: type)
    block.assign_body(body, locale: "en")
    block
  end

  def with_table_type
    BlockTypes.register "test_table" do |t|
      t.label "Table"
      t.uses :body
      t.body_content :table
      t.component TestQuoteComponent
      TestTypes.declare(t)
    end
    yield "test_table"
  ensure
    Rails.application.reloader.prepare!
  end

  test "a table body holding exactly one table is valid; a table followed by a paragraph is refused; a paragraph alone is refused" do
    with_table_type do |type|
      assert_predicate block(type, doc(grid(2, 2))), :valid?

      beside = block(type, doc(grid(2, 2), paragraph))
      assert_not_predicate beside, :valid?
      assert_match(/exactly one table/, beside.errors[:body].to_sentence)

      alone = block(type, doc(paragraph))
      assert_not_predicate alone, :valid?
      assert_match(/\A\(en\) /, alone.errors[:body].first)
    end
  end

  test "a cell holding a struck text is refused, and bold, italic, code and links are fine" do
    struck = { "type" => "text", "text" => "old", "marks" => [ { "type" => "strike" } ] }
    kept = %w[bold italic code].map { |m| { "type" => "text", "text" => "k", "marks" => [ { "type" => m } ] } }
    with_table_type do |type|
      bad = block(type, doc(table(row({ "type" => "tableCell", "content" => [ { "type" => "paragraph", "content" => [ struck ] } ] }))))
      assert_not_predicate bad, :valid?
      assert_match(/\A\(en\) a table cell allows only .*strike/, bad.errors[:body].first)

      ok = block(type, doc(table(row({ "type" => "tableCell", "content" => [ { "type" => "paragraph", "content" => kept } ] }))))
      assert_predicate ok, :valid?, ok.errors.full_messages.to_sentence
    end
  end

  test "an empty body is valid" do
    with_table_type do |type|
      assert_predicate block(type, RichText::Document.empty.to_h), :valid?
    end
  end

  # A blank body skipped the shape checks once: a blank table beside an empty
  # paragraph, or a ragged table of empty cells, was saved and the grid could
  # not load it. Blank is still one table of equal rows, or nothing.
  test "a blank body of the wrong shape is refused: a blank table beside an empty paragraph, a ragged table of empty cells, an empty paragraph alone" do
    empty_paragraph = { "type" => "paragraph" }
    empty_cell = { "type" => "tableCell", "content" => [ empty_paragraph ] }
    with_table_type do |type|
      beside = block(type, doc(table(row(empty_cell, empty_cell)), empty_paragraph))
      assert_not_predicate beside, :valid?
      assert_match(/exactly one table/, beside.errors[:body].to_sentence)

      ragged = block(type, doc(table(row(empty_cell, empty_cell), row(empty_cell))))
      assert_not_predicate ragged, :valid?
      assert_match(/same number of cells/, ragged.errors[:body].to_sentence)

      alone = block(type, doc(empty_paragraph))
      assert_not_predicate alone, :valid?
      assert_match(/exactly one table/, alone.errors[:body].to_sentence)

      blank_grid = block(type, doc(table(row(empty_cell, empty_cell), row(empty_cell, empty_cell))))
      assert_predicate blank_grid, :valid?, blank_grid.errors.full_messages.to_sentence
    end
  end

  test "rows of different lengths are refused" do
    with_table_type do |type|
      ragged = block(type, doc(table(row(cell, cell), row(cell))))
      assert_not_predicate ragged, :valid?
      assert_match(/same number of cells/, ragged.errors[:body].to_sentence)
    end
  end

  test "a text block's, a note's and a post's body with a table in it is refused" do
    body = doc(grid(2, 2))
    %w[rich_text note].each do |type|
      record = block(type, body)
      assert_not_predicate record, :valid?, type
      assert_match(/only in a Table block/, record.errors[:body].to_sentence)
    end

    post = Post.new(content_type: "blog")
    post.assign_body(body, locale: "en")
    assert_not_predicate post, :valid?
    assert_match(/only in a Table block/, post.errors[:body].to_sentence)
  end

  test "over the hard limit the save is refused with the table's sentence and no language prefix" do
    with_table_type do |type|
      wide = block(type, doc(grid(31, 1)))
      assert_not_predicate wide, :valid?
      assert_includes wide.errors[:body], "A table can have at most 30 columns and 500 rows."

      long = block(type, doc(grid(1, 1, value: "a" * 2_001)))
      assert_not_predicate long, :valid?
      assert_includes long.errors[:body], "A cell can have at most 2,000 characters."

      assert_predicate block(type, doc(grid(30, 1, value: "a" * 2_000))), :valid?
    end
  end
end
