require "test_helper"

class TableBodyTest < ActiveSupport::TestCase
  def text(value, *marks) = { "type" => "text", "text" => value, "marks" => marks }.compact
  def cell(value, header: false, align: nil)
    node = { "type" => header ? "tableHeader" : "tableCell", "content" => [ { "type" => "paragraph", "content" => (value.empty? ? [] : [ text(value) ]) } ] }
    node["attrs"] = { "align" => align } if align
    node
  end

  def body(rows) = TableBody.new(RichText::Document.new("type" => "doc", "content" => [ { "type" => "table", "content" => rows.map { |cells| { "type" => "tableRow", "content" => cells } } } ]))
  def grid(columns, rows, value: "x") = body(Array.new(rows) { Array.new(columns) { cell(value) } })

  test "rows, cells, header row and header column are read from the document" do
    table = body([
      [ cell("Name", header: true), cell("Price", header: true, align: "right") ],
      [ cell("Tea", header: true), cell("3", align: "right") ]
    ])
    assert_equal [ 2, 2 ], table.shape
    assert_equal 2, table.column_count
    assert_equal 2, table.row_count
    assert_predicate table, :header_row?
    assert_predicate table, :header_column?
    first, second = table.rows.first
    assert_equal [ true, nil, "Name" ], [ first.header, first.align, first.text ]
    assert_equal [ true, "right", "Price" ], [ second.header, second.align, second.text ]
    assert_equal [ text("Name") ], first.nodes

    plain = body([ [ cell("a"), cell("b") ] ])
    assert_not plain.header_row?
    assert_not plain.header_column?
    assert_not body([ [ cell("H", header: true), cell("x") ] ]).header_row?
    assert_not body([ [ cell("H", header: true) ], [ cell("x") ] ]).header_column?
  end

  test "warnings start at 6 columns and at 40 rows, and not below" do
    assert_equal [], grid(5, 39).warnings
    assert_equal [ [ :columns, 6 ] ], grid(6, 39).warnings
    assert_equal [ [ :rows, 40 ] ], grid(5, 40).warnings
    assert_equal [ [ :columns, 7 ], [ :rows, 41 ] ], grid(7, 41).warnings
  end

  test "limit errors: 31 columns or 501 rows is :size, a 2,001-character cell is :cell, exactly the limits are fine" do
    assert_equal [], grid(30, 1).limit_errors
    assert_equal [], grid(1, 500).limit_errors
    assert_equal [ :size ], grid(31, 1).limit_errors
    assert_equal [ :size ], grid(1, 501).limit_errors
    assert_equal [], grid(1, 1, value: "a" * 2_000).limit_errors
    assert_equal [ :cell ], grid(1, 1, value: "a" * 2_001).limit_errors
    assert_equal [ :size, :cell ], grid(31, 1, value: "a" * 2_001).limit_errors
  end

  test "a table whose every cell is blank is blank" do
    assert_predicate body([ [ cell(""), cell("  ") ] ]), :blank?
    assert_not body([ [ cell(""), cell("x") ] ]).blank?
  end

  test "ragged rows are reported, and a document that is no table reads as an empty one" do
    assert_predicate body([ [ cell("a"), cell("b") ], [ cell("c") ] ]), :ragged?
    assert_not grid(2, 2).ragged?
    empty = TableBody.new(RichText::Document.empty)
    assert_equal [ 0, 0 ], empty.shape
    assert_predicate empty, :blank?
    assert_equal [], empty.limit_errors
    assert_equal [], TableBody.new(RichText::Document.new("type" => "doc", "content" => [ 1, { "type" => "table", "content" => [ nil, { "type" => "tableRow", "content" => [ "x" ] } ] } ])).rows.flatten
  end
end
