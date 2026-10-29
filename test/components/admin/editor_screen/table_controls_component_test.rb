require "test_helper"

# What stands around a Table's grid in its card (table block spec decisions 4,
# 7 and 13): the switches, the warning line, the row's and the column's menus
# and "+", "Add row", and the delete confirmations outside the form. What they
# DO is the browser's (`test/system/admin/table_block_test.rb`); here, what
# the server draws and where it draws nothing.
class Admin::EditorScreen::TableControlsComponentTest < ViewComponent::TestCase
  include ContentHelper

  A = "tab-aaaaaaaa".freeze
  B = "tab-bbbbbbbb".freeze

  # A grid of `rows` × `columns` cells, the first row headers, one word in
  # the first cell.
  def grid(rows, columns, header_row: true, header_column: false)
    {
      "type" => "doc",
      "content" => [ {
        "type" => "table",
        "content" => Array.new(rows) do |row|
          { "type" => "tableRow", "content" => Array.new(columns) do |column|
            header = (header_row && row.zero?) || (header_column && column.zero?)
            paragraph = row.zero? && column.zero? ? { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Plan" } ] } : { "type" => "paragraph" }
            { "type" => header ? "tableHeader" : "tableCell", "content" => [ paragraph ] }
          end }
        end
      } ]
    }
  end

  def table_block(document = nil)
    @prices ||= create_page(title: "Prices")
    block = @prices.content_blocks.new(block_type: "table", position: @prices.content_blocks.count)
    block.assign_body(document, locale: :en) if document
    block.save!
    block
  end

  def render_card(block, viewer: users(:one), tab: A)
    as_viewer(viewer, tab: tab) { render_inline Admin::EditorScreen::BlockCardComponent.new(page: @prices, block: block, locale: "en") }
  end

  def warning = page.find("[data-admin--editor--table-target=warning]", visible: :all)

  test "the warning is drawn from 6 columns and from 40 rows, both in one alert, and not below" do
    {
      [ 39, 5 ] => nil,
      [ 3, 6 ] => "6 columns. On a phone, visitors scroll sideways to read this table.",
      [ 40, 3 ] => "40 rows. A long table is easier to read split into several.",
      [ 45, 7 ] => "7 columns. On a phone, visitors scroll sideways to read this table. 45 rows. A long table is easier to read split into several."
    }.each do |(rows, columns), sentence|
      render_inline Admin::EditorScreen::TableControlsComponent.new(block: table_block(grid(rows, columns)), document: RichText::Document.new(grid(rows, columns)))

      assert_selector "[aria-live=polite] > p", count: 1, visible: :all
      if sentence
        assert_equal sentence, warning.text(:all), "#{columns} × #{rows}"
        assert_not warning.matches_selector?("[hidden]", visible: :all), "#{columns} × #{rows} is warned of"
        assert_selector "p.border-warn.bg-warn-tint.text-warn-ink.text-sm", text: sentence
      else
        assert warning.matches_selector?("[hidden]", visible: :all), "#{columns} × #{rows} is not warned of"
        assert_equal "", warning.text(:all)
      end
    end
  end

  test "the script's warning words are the server's: both sentences in its messages, with the thresholds" do
    render_inline Admin::EditorScreen::TableControlsComponent.new(block: table_block(grid(2, 2)), document: RichText::Document.new(grid(2, 2)))

    root = page.find("[data-controller='admin--editor--table']", visible: :all)
    messages = JSON.parse(root["data-messages"])
    assert_equal "%{count} columns. On a phone, visitors scroll sideways to read this table.", messages.dig("components.editor_screen.table_controls.warning.columns", "other")
    assert_equal "%{count} rows. A long table is easier to read split into several.", messages.dig("components.editor_screen.table_controls.warning.rows", "other")
    assert_equal [ "6", "40" ], [ root["data-admin--editor--table-warn-columns-value"], root["data-admin--editor--table-warn-rows-value"] ]
  end

  test "the switches say what the cells are: header row, first column, both and neither" do
    { [ true, false ] => [ true, false ], [ false, true ] => [ false, true ], [ true, true ] => [ true, true ], [ false, false ] => [ false, false ] }.each do |(row, column), expected|
      document = grid(3, 3, header_row: row, header_column: column)
      render_inline Admin::EditorScreen::TableControlsComponent.new(block: table_block(document), document: RichText::Document.new(document))

      assert_equal expected, [ page.find_field("Header row").checked?, page.find_field("First column as header").checked? ], "row #{row}, column #{column}"
      assert_selector "input[type=checkbox][role=switch].cs-toggle:not([name])", count: 2
    end
  end

  test "a new Table shows the 3 × 3 starting grid with Header row on, and its field stays empty" do
    block = table_block
    render_card(block)

    editor = page.find("[data-controller~='admin--rich-text--editor']", visible: :all)
    assert_equal TableBody.starting_document, JSON.parse(editor["data-admin--rich-text--editor-starting-content-value"])
    assert_equal({ "type" => "doc", "content" => [] }, JSON.parse(page.find("input[name='block[body]']", visible: :all).value))
    starting = TableBody.new(TableBody.starting_document)
    assert_equal [ 3, 3 ], starting.shape
    assert starting.header_row?
    assert_not starting.header_column?
    assert page.find_field("Header row").checked?
    assert_not page.find_field("First column as header").checked?
    assert warning.matches_selector?("[hidden]", visible: :all)
  end

  test "a table that has a grid starts from nothing else" do
    block = table_block(grid(2, 2))
    render_card(block)

    assert_no_selector "[data-admin--rich-text--editor-starting-content-value]", visible: :all
  end

  test "the menus, the two + and Add row are drawn for someone who may change the table, the dialogs outside the form" do
    block = table_block(grid(2, 2))
    render_card(block)

    assert_selector "form [data-controller='admin--editor--table'] [data-controller~='admin--rich-text--editor']", visible: :all
    assert_selector "button[aria-haspopup=menu][aria-label='Row actions']", visible: :all
    assert_selector "button[aria-haspopup=menu][aria-label='Column actions']", visible: :all
    row_items = page.all("[data-admin--editor--table-target=rowControls] [role=menu] button", visible: :all).map { |item| item.text(:all) }
    assert_equal [ "Insert above", "Insert below", "Move up", "Move down", "Delete row" ], row_items
    column_items = page.all("[data-admin--editor--table-target=columnControls] [role=menu] button", visible: :all).map { |item| item["aria-label"] || item.text(:all) }
    assert_equal [ "Insert left", "Insert right", "Move left", "Move right", "Align left", "Align centre", "Align right", "Delete column" ], column_items
    assert_selector "button[aria-label='Add a column'][hidden]", visible: :all
    assert_selector "button[aria-label='Add a row'][hidden]", visible: :all
    assert_selector "button", text: "Add row"

    Admin::EditorScreen::TableDeleteDialogsComponent::KINDS.each do |kind|
      id = Admin::EditorScreen::TableDeleteDialogsComponent.dialog_id(block, kind)
      assert_selector "dialog##{id}", visible: :all
      assert_no_selector "form dialog##{id}", visible: :all
      assert_selector "dialog##{id} form[method=dialog] button[type=submit][value=delete]", visible: :all
    end
  end

  test "the controls are not drawn in a held form, nor for a reader: the grid alone, read-only" do
    block = table_block(grid(7, 7))
    dana = users(:two)
    reserve(block, @prices, dana, B)

    render_card(block)

    assert_selector "fieldset.admin-held [data-controller~='admin--rich-text--editor'][data-admin--rich-text--editor-read-only-value=true]", visible: :all
    assert_no_selector "[data-controller~='admin--editor--table']", visible: :all
    assert_no_selector "[data-action*='admin--editor--table']", visible: :all
    assert_no_selector "input[role=switch]", visible: :all
    assert_no_selector "[aria-label='Row actions'], [aria-label='Column actions'], [aria-label='Add a column'], [aria-label='Add a row']", visible: :all
    assert_no_button "Add row", visible: :all
    assert_no_selector "dialog[id*='table-delete']", visible: :all
    assert_no_selector "[data-admin--rich-text--editor-starting-content-value]", visible: :all
  end

  test "a reader's card, and a new Table's for a reader, has no controls and starts from no grid" do
    [ table_block(grid(2, 2)), table_block ].each do |block|
      as_viewer(users(:one), tab: A) { render_inline Admin::EditorScreen::BlockCardComponent.new(page: @prices, block: block, locale: "en", editable: false) }

      assert_selector "fieldset[disabled] [data-controller~='admin--rich-text--editor']", visible: :all
      assert_no_selector "[data-controller~='admin--editor--table'], input[role=switch]", visible: :all
      assert_no_selector "[data-admin--rich-text--editor-starting-content-value]", visible: :all
    end
  end
end
