require "application_system_test_case"

# The Table block's grid in the page editor (table block spec decisions 3,
# 11 and 12): a table mode of the rich-text editor (`admin--rich-text--editor`
# with `content: "table"`), whose schema is a table of one-paragraph cells
# with the inline marks and nothing else, and whose keys are Claude Design's
# B5. Every test reads the SAVED document back and runs it through
# `RichText::Document#validate` and the block's body rule, so whatever the
# grid can make is something the server accepts.
#
# The starting grid of a new block is Task 6's: these tests start from a
# block whose body already holds a grid of empty cells.
class Admin::TableBlockSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Prices", published: false)
    sign_in_via_form(users(:one))
  end

  # A table of `rows` × `columns` empty cells, the first row headers.
  def grid(rows, columns)
    {
      "type" => "doc",
      "content" => [ {
        "type" => "table",
        "content" => Array.new(rows) do |row|
          { "type" => "tableRow", "content" => Array.new(columns) { { "type" => row.zero? ? "tableHeader" : "tableCell", "content" => [ { "type" => "paragraph" } ] } } }
        end
      } ]
    }
  end

  def table_block(rows: 2, columns: 2, position: 0)
    block = @page.content_blocks.new(block_type: "table", position: position)
    block.assign_body(grid(rows, columns), locale: :en)
    block.save!
    block
  end

  def open_editor
    visit "/cs-studio/pages/#{@page.id}"
    assert_selector ".ProseMirror"
    await_admin_controllers
  end

  def grid_of(block) = "#content_block_#{block.id} .ProseMirror"

  # The cell at (row, column), both from zero, as ProseMirror draws it.
  def cell(block, row, column) = find("#{grid_of(block)} tr:nth-child(#{row + 1}) > :nth-child(#{column + 1})")

  def key(*keys) = page.driver.browser.keyboard.type(*keys)

  def type_text(text) = page.driver.browser.keyboard.type(text)

  # A synthetic `paste` with a real `DataTransfer` on the focused editor, as
  # `test/system/admin/rich_text_test.rb` does it.
  def paste(selector, text: nil, html: nil)
    page.execute_script(<<~JS, selector, text, html)
      const data = new DataTransfer()
      if (arguments[1]) data.setData("text/plain", arguments[1])
      if (arguments[2]) data.setData("text/html", arguments[2])
      document.querySelector(arguments[0]).dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }))
    JS
  end

  def saved(record, &condition)
    document = nil
    assert_eventually(wait: 6, message: -> { "the saved document never matched: #{document.to_h.to_json}" }) do
      document = record.reload.body_document(locale: :en)
      condition.call(document)
    end
    assert_empty document.validate, "the grid saved a document the server schema rejects"
    document
  end

  def rows_of(document) = document.to_h.dig("content", 0, "content").map { |row| row["content"] }

  # A cell's text, a hard break read as a line break.
  def text_of(cell)
    cell["content"].sole["content"].to_a.map { |node| node["type"] == "hardBreak" ? "\n" : node["text"] }.join
  end

  def texts(document) = rows_of(document).map { |row| row.map { |cell| text_of(cell) } }

  def every_cell_one_paragraph(document)
    rows_of(document).flatten.each do |cell|
      assert_equal [ "paragraph" ], cell["content"].map { |node| node["type"] }, "a cell holds exactly one paragraph"
    end
  end

  test "typing in the grid, Tab to the next cell and in the last cell adds a row, Enter goes down, Shift+Enter breaks the line; autosave and reload keep it all" do
    block = table_block
    open_editor

    cell(block, 0, 0).click
    type_text "Plan"
    key(:Tab)
    type_text "Price"
    key(:Tab)
    type_text "Basic"
    key([ :Shift, :Enter ])
    type_text "plan"
    key(:Tab)
    type_text "5"
    key(:Tab) # the last cell: a row is added, and the caret is in its first cell
    assert_selector "#{grid_of(block)} tr", count: 3
    type_text "Pro"

    cell(block, 0, 1).click
    key(:End)
    key(:Enter) # to the cell below, at the end of its text, with no paragraph added
    type_text " €"
    key(:Enter)
    type_text "12"
    key(:Escape)
    assert_eventually(message: "Esc leaves the grid") { page.evaluate_script("document.activeElement.closest('.ProseMirror') === null") }

    document = saved(block) { |doc| doc.table? && texts(doc).dig(2, 1) == "12" }
    assert_equal [ [ "Plan", "Price" ], [ "Basic\nplan", "5 €" ], [ "Pro", "12" ] ], texts(document)
    assert_equal %w[tableHeader tableHeader], rows_of(document)[0].map { |cell| cell["type"] }
    assert_equal %w[tableCell tableCell], rows_of(document)[2].map { |cell| cell["type"] }
    every_cell_one_paragraph(document)
    # The editor's own attributes (spans, widths) are not stored: a cell carries an alignment or nothing.
    assert rows_of(document).flatten.all? { |cell| cell.fetch("attrs", {}).keys.difference([ "align" ]).empty? }

    open_editor
    assert_equal [ "Plan", "Price" ], page.all("#{grid_of(block)} tr:first-child > *").map(&:text)
    assert_selector "#{grid_of(block)} tr", count: 3
    assert_selector "#{grid_of(block)} tr:nth-child(2) > :first-child br"
    assert_text "5 €"
  end

  test "a grid emptied of every row saves an empty document" do
    block = table_block
    block.assign_body(grid(2, 2).tap { |doc| doc["content"][0]["content"][0]["content"][0]["content"][0]["content"] = [ { "type" => "text", "text" => "Plan" } ] }, locale: :en)
    block.save!
    open_editor

    cell(block, 0, 0).click
    cell(block, 1, 1).click(:shift) # every cell selected, as a person drags across them
    assert_selector "#{grid_of(block)} .selectedCell", count: 4
    key(:Backspace)
    assert_no_selector "#{grid_of(block)} table"

    saved(block) { |doc| doc.blank? }
    assert_equal({ "type" => "doc", "content" => [] }, block.reload.body(locale: "en"))
  end

  test "bold and a link from the toolbar land in the focused cell" do
    block = table_block
    open_editor

    cell(block, 1, 0).click
    within("#content_block_#{block.id}") { press "Bold" }
    type_text "Basic"
    within("#content_block_#{block.id}") { press "Bold" }

    cell(block, 1, 1).click
    within("#content_block_#{block.id}") { press "Link" }
    within(".admin-rich-text-popover") do
      fill_in "URL or search", with: "https://example.org"
      find_field("URL or search").send_keys(:enter)
    end
    refute_selector ".admin-rich-text-popover"

    document = saved(block) { |doc| doc.table? && rows_of(doc)[1][1]["content"].sole["content"].present? && text_of(rows_of(doc)[1][0]) == "Basic" }
    bold = rows_of(document)[1][0]["content"].sole["content"].sole
    assert_equal [ { "type" => "bold" } ], bold["marks"]
    linked = rows_of(document)[1][1]["content"].sole["content"].sole
    assert_equal [ "link" ], linked["marks"].map { |mark| mark["type"] }
    assert_match %r{\Ahttps://example\.org/?\z}, linked["marks"].first.dig("attrs", "href")
    assert_equal [ "", "" ], rows_of(document)[0].map { |cell| text_of(cell) }, "nothing landed outside the focused cells"
    every_cell_one_paragraph(document)
  end

  test "a five-column grid scrolls sideways inside the card while the editor column keeps its width" do
    narrow = table_block(columns: 2, position: 0)
    wide = table_block(columns: 5, position: 1)
    open_editor

    measure = ->(block) do
      page.evaluate_script(<<~JS, "#content_block_#{block.id}")
        (() => {
          const card = document.querySelector(arguments[0])
          const box = card.querySelector(".ProseMirror .tableWrapper")
          const editor = card.querySelector(".admin-rich-text-editor")
          const cells = [...card.querySelectorAll(".ProseMirror tr:first-child > *")].map((cell) => cell.getBoundingClientRect().width)
          return { editor: editor.getBoundingClientRect().width, client: box.clientWidth, scroll: box.scrollWidth, overflow: getComputedStyle(box).overflowX, cells }
        })()
      JS
    end
    two = measure.call(narrow)
    five = measure.call(wide)

    assert_equal two["editor"], five["editor"], "the wide grid does not widen the editor"
    assert_operator five["editor"], :<=, 760
    assert_equal "auto", five["overflow"]
    assert_operator five["scroll"], :>, five["client"], "five cells of 160px are wider than the column, and scroll in their box"
    assert five["cells"].all? { |width| width >= 160 }, "every cell is at least 160px: #{five["cells"]}"
    assert_equal two["scroll"], two["client"], "two columns fit and do not scroll"
  end

  test "pasting paragraphs, a list and an HTML table into a cell leaves one table with inline text in the cell" do
    block = table_block
    open_editor

    cell(block, 1, 0).click
    paste(grid_of(block), html: "<p>One</p><p><strong>Two</strong></p>", text: "One\nTwo")
    cell(block, 1, 1).click
    paste(grid_of(block), html: "<ul><li>Apple</li><li>Pear</li></ul>", text: "Apple\nPear")
    cell(block, 0, 0).click
    paste(grid_of(block), html: "<table><tr><th>X</th><th>Y</th></tr><tr><td>1</td><td>2</td></tr></table>", text: "X\tY\n1\t2")

    document = saved(block) { |doc| doc.table? && texts(doc).flatten.any? { |text| text.include?("X") } && texts(doc)[1][1].include?("Pear") }
    assert_equal 1, document.to_h["content"].size
    assert_equal "table", document.to_h["content"].sole["type"]
    assert_equal [ 2, 2 ], rows_of(document).map(&:size), "the grid keeps its shape"
    assert_equal "One\nTwo", texts(document)[1][0]
    assert_equal [ { "type" => "bold" } ], rows_of(document)[1][0]["content"].sole["content"].last["marks"]
    assert_equal "Apple\nPear", texts(document)[1][1]
    assert_equal "X\nY\n1\n2", texts(document)[0][0]
    every_cell_one_paragraph(document)
    assert block.reload.valid?, "the body rule accepts it: #{block.errors.full_messages}"
  end

  test "pasting an HTML table into a post body keeps its text and no table" do
    post = create_post(title: "Notes")
    visit "/cs-studio/posts/#{post.id}"
    assert_selector ".ProseMirror"
    await_admin_controllers

    find(".ProseMirror").click
    paste(".ProseMirror", html: "<table><tr><th>Plan</th><th>Price</th></tr><tr><td>Basic</td><td>5</td></tr></table>", text: "Plan\tPrice\nBasic\t5")

    document = saved(post) { |doc| doc.plain_paragraphs.join(" ").include?("Basic5") }
    assert_not document.table?
    types = []
    stack = [ document.to_h ]
    until stack.empty?
      node = stack.pop
      types << node["type"]
      stack.concat(Array(node["content"]))
    end
    assert_empty types & %w[table tableRow tableHeader tableCell]
    # Its words, in order: how they are put into paragraphs is the ordinary
    # editor's parse of cells it has no node for, unchanged by the grid.
    assert_match(/Plan.*Price.*Basic.*5/m, document.plain_paragraphs.join("\n"))
  end
end
