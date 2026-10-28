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

  test "an empty body is valid" do
    with_table_type do |type|
      assert_predicate block(type, RichText::Document.empty.to_h), :valid?
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
