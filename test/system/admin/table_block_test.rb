require "application_system_test_case"

# The Table block's grid in the page editor (table block spec decisions 3,
# 11 and 12): a table mode of the rich-text editor (`admin--rich-text--editor`
# with `content: "table"`), whose schema is a table of one-paragraph cells
# with the inline marks and nothing else, and whose keys are Claude Design's
# B5. Every test reads the SAVED document back and runs it through
# `RichText::Document#validate` and the block's body rule, so whatever the
# grid can make is something the server accepts.
#
# The grid's controls (`admin--editor--table`, Task 6): the two header
# switches, the warning line, the current row's and column's "⋯" menus and
# "+", "Add row", the delete confirmation, the starting grid of a new Table
# and the read-only grid of someone who does not hold the block.
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
  # ----- The grid's controls (Task 6) -----

  # A table of the given words, the first row headers.
  def words(rows)
    {
      "type" => "doc",
      "content" => [ {
        "type" => "table",
        "content" => rows.each_with_index.map do |row, index|
          { "type" => "tableRow", "content" => row.map do |text|
            paragraph = text.empty? ? { "type" => "paragraph" } : { "type" => "paragraph", "content" => [ { "type" => "text", "text" => text } ] }
            { "type" => index.zero? ? "tableHeader" : "tableCell", "content" => [ paragraph ] }
          end }
        end
      } ]
    }
  end

  def words_block(rows, page: @page)
    block = page.content_blocks.new(block_type: "table", position: page.content_blocks.count)
    block.assign_body(words(rows), locale: :en)
    block.save!
    block
  end

  def card(block) = "#content_block_#{block.id}"

  # A menu's item: the menu's "⋯" pressed, then the item, as a person does.
  # An item is found by its words, an alignment by its name ("Align right":
  # its words are "Right" and the check mark).
  def column_menu(block, item) = pick("#{card(block)} [data-admin--editor--table-target=columnControls]", "Column actions", item)

  def row_menu(block, item) = pick("#{card(block)} [data-admin--editor--table-target=rowControls]", "Row actions", item)

  def pick(controls, menu, item)
    within(controls) do
      find("button[aria-label='#{menu}']").click
      within("[role=menu]") do
        (item.start_with?("Align ") ? find("button[aria-label='#{item}']") : find("button", text: /\A#{Regexp.escape(item)}\z/)).click
      end
    end
  end

  def kinds(document) = rows_of(document).map { |row| row.map { |cell| cell["type"] == "tableHeader" ? "th" : "td" } }

  def aligns(document) = rows_of(document).map { |row| row.map { |cell| cell.dig("attrs", "align") } }

  def stored(block) = block.reload.body(locale: "en")

  test "a new Table starts as a 3 × 3 grid with a header row, and nothing is saved until a cell is typed in" do
    block = @page.content_blocks.create!(block_type: "table", position: 0)
    open_editor

    assert_selector "#{grid_of(block)} tr", count: 3
    assert_selector "#{grid_of(block)} tr:first-child > th", count: 3
    assert_selector "#{grid_of(block)} tr:nth-child(2) > td", count: 3
    assert find("#{card(block)} input[role=switch]", match: :first).checked?, "Header row is on"
    assert_equal({ "type" => "doc", "content" => [] }, JSON.parse(find("#{card(block)} input[name='block[body]']", visible: :all).value), "the field stays empty")
    cell(block, 1, 1).click
    await_frames
    assert_writes_settled
    assert stored(block).blank? || stored(block) == { "type" => "doc", "content" => [] }, "a click is no change: nothing is saved"

    type_text "5 €"
    document = saved(block) { |doc| doc.table? && texts(doc).dig(1, 1) == "5 €" }
    assert_equal [ %w[th th th], %w[td td td], %w[td td td] ], kinds(document)
  end

  test "a column's menu inserts, moves, aligns and deletes; deleting a column with text asks first; the cells show the alignment" do
    block = words_block([ %w[Plan Price], %w[Basic 5] ])
    open_editor

    cell(block, 0, 0).click
    column_menu(block, "Insert right")
    document = saved(block) { |doc| rows_of(doc).first.size == 3 }
    assert_equal [ [ "Plan", "", "Price" ], [ "Basic", "", "5" ] ], texts(document)
    assert_equal [ %w[th th th], %w[td td td] ], kinds(document), "the new column's first cell is a header like its row"

    column_menu(block, "Move right") # the new column, current after the insert
    document = saved(block) { |doc| texts(doc).first == [ "Plan", "Price", "" ] }
    assert_equal [ [ "Plan", "Price", "" ], [ "Basic", "5", "" ] ], texts(document)

    cell(block, 1, 1).click
    column_menu(block, "Align right")
    document = saved(block) { |doc| aligns(doc).all? { |row| row[1] == "right" } }
    assert_equal [ [ nil, "right", nil ], [ nil, "right", nil ] ], aligns(document), "every cell of the column, the header's too, and no other"
    assert_equal %w[right right], [ 0, 1 ].map { |row| cell(block, row, 1).evaluate_script("getComputedStyle(this).textAlign") }, "the grid's cells show it"
    assert_equal "left", cell(block, 1, 0).evaluate_script("getComputedStyle(this).textAlign")
    within("#{card(block)} [data-admin--editor--table-target=columnControls]") do
      find("button[aria-label='Column actions']").click
      assert_selector "[role=menuitemradio][aria-checked=true]", text: "Right"
      assert_selector "[role=menuitemradio][aria-checked=false]", count: 2
      find("button[aria-haspopup=menu]").send_keys(:escape)
    end

    # A row added afterwards takes its column's alignment (Tab in the last cell adds one).
    cell(block, 1, 2).click
    key(:Tab)
    document = saved(block) { |doc| rows_of(doc).size == 3 }
    assert_equal "right", aligns(document)[2][1]

    cell(block, 0, 2).click
    column_menu(block, "Delete column") # no text in it: deleted at once
    assert_no_selector "dialog[open]"
    document = saved(block) { |doc| rows_of(doc).first.size == 2 }
    assert_equal [ %w[Plan Price], %w[Basic 5], [ "", "" ] ], texts(document)

    cell(block, 0, 0).click
    column_menu(block, "Delete column")
    within("dialog[open]") do
      assert_text "Delete this column?"
      press "Cancel"
    end
    assert_no_selector "dialog[open]"
    assert_selector "#{grid_of(block)} tr:first-child > *", count: 2

    column_menu(block, "Delete column")
    within("dialog[open]") { press "Delete column" }
    document = saved(block) { |doc| rows_of(doc).first.size == 1 }
    assert_equal [ [ "Price" ], [ "5" ], [ "" ] ], texts(document)
    assert_equal [ [ "right" ], [ "right" ], [ "right" ] ], aligns(document)
    every_cell_one_paragraph(document)
  end

  test "a row's menu inserts above, moves and deletes, and the header row stays the first row" do
    block = words_block([ %w[Plan Price], %w[Basic 5], %w[Pro 12] ])
    open_editor
    focused = -> { page.evaluate_script("document.activeElement.getAttribute('aria-label')") }

    # The keyboard's way to the controls: Esc leaves the grid to the row's "⋯", Tab goes on to the column's.
    cell(block, 2, 0).click
    key(:Escape)
    assert_eventually(message: -> { "Esc went to #{focused.call.inspect}" }) { focused.call == "Row actions" }
    key(:Tab)
    assert_equal "Column actions", focused.call

    cell(block, 2, 0).click
    row_menu(block, "Move up")
    document = saved(block) { |doc| texts(doc)[1] == %w[Pro 12] }
    assert_equal [ %w[Plan Price], %w[Pro 12], %w[Basic 5] ], texts(document)

    row_menu(block, "Move up") # Pro, now the second row: it becomes the first, and the header
    document = saved(block) { |doc| texts(doc)[0] == %w[Pro 12] }
    assert_equal [ %w[th th], %w[td td], %w[td td] ], kinds(document), "the header row is the first row, whatever moved"

    row_menu(block, "Insert above")
    document = saved(block) { |doc| rows_of(doc).size == 4 }
    assert_equal [ [ "", "" ], %w[Pro 12], %w[Plan Price], %w[Basic 5] ], texts(document)
    assert_equal [ %w[th th], %w[td td], %w[td td], %w[td td] ], kinds(document)

    row_menu(block, "Delete row") # empty: at once
    document = saved(block) { |doc| rows_of(doc).size == 3 }
    cell(block, 2, 0).click
    row_menu(block, "Delete row")
    within("dialog[open]") { press "Delete row" }
    document = saved(block) { |doc| rows_of(doc).size == 2 }
    assert_equal [ %w[Pro 12], %w[Plan Price] ], texts(document)

    press "Add row"
    document = saved(block) { |doc| rows_of(doc).size == 3 }
    assert_equal [ %w[th th], %w[td td], %w[td td] ], kinds(document)
  end

  test "Header row and First column as header turn cells into headers and back, and the site draws th" do
    live = create_page(title: "Live prices")
    block = words_block([ %w[Plan Price], %w[Basic 5], %w[Pro 12] ], page: live)
    publish_changes(live)
    visit "/cs-studio/pages/#{live.id}"
    assert_selector ".ProseMirror"
    await_admin_controllers

    find("#{card(block)} label", text: "Header row").click
    document = saved(block) { |doc| kinds(doc).flatten.uniq == [ "td" ] }
    assert_selector "#{grid_of(block)} th", count: 0

    find("#{card(block)} label", text: "First column as header").click
    document = saved(block) { |doc| kinds(doc).map(&:first).uniq == [ "th" ] }
    assert_equal [ %w[th td], %w[th td], %w[th td] ], kinds(document)

    find("#{card(block)} label", text: "Header row").click
    document = saved(block) { |doc| kinds(doc).first == %w[th th] }
    assert_equal [ %w[th th], %w[th td], %w[th td] ], kinds(document)

    find("#{card(block)} label", text: "First column as header").click
    document = saved(block) { |doc| kinds(doc)[1].first == "td" }
    assert_equal [ %w[th th], %w[td td], %w[td td] ], kinds(document), "the corner stays a header of the row"

    find("#{card(block)} label", text: "First column as header").click
    saved(block) { |doc| kinds(doc)[1].first == "th" }
    assert_writes_settled
    publish_changes(live)
    visit PublicSite::Urls.new.path_for(live, "en")
    assert_selector "table th", count: 4
    assert_equal %w[Plan Price Basic Pro], all("table th").map(&:text)
    assert_selector "table td", count: 2
  end

  test "adding a sixth column shows the warning at once, removing it takes it away" do
    block = words_block([ %w[A B C D E], %w[1 2 3 4 5] ])
    open_editor
    warning = "#{card(block)} [data-admin--editor--table-target=warning]"
    assert_no_selector warning

    cell(block, 0, 0).click
    press "Add a column"
    assert_selector warning, text: "6 columns. On a phone, visitors scroll sideways to read this table.", exact_text: true

    cell(block, 0, 5).click
    column_menu(block, "Delete column")
    assert_no_selector warning
    saved(block) { |doc| rows_of(doc).first.size == 5 }
  end

  test "the editor's edge fade on a five-column grid is on the side that has more, and follows the scroll" do
    block = table_block(columns: 5)
    open_editor
    box = "#{grid_of(block)} .tableWrapper"
    fades = -> { find(box).evaluate_script("[getComputedStyle(this).getPropertyValue('--admin-table-fade-start').trim(), getComputedStyle(this).getPropertyValue('--admin-table-fade-end').trim()]") }

    assert_equal [ "0px", "24px" ], fades.call, "at rest: more to the right, the right edge fades"
    find(box).execute_script("this.scrollLeft = this.scrollWidth")
    assert_eventually(message: -> { "scrolled to the end: the left edge fades, the right does not (#{fades.call})" }) { fades.call == [ "24px", "0px" ] }
  end

  test "a second person sees the grid read-only: no controls, no toolbar, nothing typed" do
    block = words_block([ %w[Plan Price], %w[Basic 5] ])
    open_editor
    cell(block, 1, 1).click
    type_text "0"
    saved(block) { |doc| texts(doc).dig(1, 1) == "50" }
    assert_writes_settled

    using_session(:dana) do
      sign_in_via_form(users(:two))
      visit "/cs-studio/pages/#{@page.id}"
      assert_selector ".ProseMirror"
      await_admin_controllers

      assert_selector "#{card(block)}[data-editing-held=true]"
      assert_selector "#{grid_of(block)}[contenteditable=false]"
      assert_no_selector "#{card(block)} [role=toolbar]"
      assert_no_selector "#{card(block)} [data-controller~='admin--editor--table']"
      assert_no_selector "#{card(block)} input[role=switch]"
      assert_no_selector "button[aria-label='Row actions'], button[aria-label='Column actions'], button[aria-label='Add a column'], button[aria-label='Add a row']", visible: :all
      assert_no_button "Add row"

      cell(block, 0, 0).click
      type_text "ZZZ"
      key(:Tab)
      await_frames
      assert_no_text "ZZZ"
      assert_selector "#{grid_of(block)} tr", count: 2
    end
    assert_equal [ %w[Plan Price], %w[Basic 50] ], texts(block.reload.body_document(locale: :en))
  end

  test "over the hard limit the save is refused with the table's sentence and the grid keeps its text" do
    block = words_block([ Array.new(30) { |n| "H#{n + 1}" }, Array.new(30) { |n| "c#{n + 1}" } ])
    open_editor

    cell(block, 1, 0).click
    type_text "!"
    saved(block) { |doc| texts(doc).dig(1, 0) == "c1!" }
    press "Add a column"

    assert_selector "##{Admin::EditorScreen::BlockCardComponent.error_prefix(block)}-body-errors", text: "A table can have at most 30 columns and 500 rows."
    assert_selector "#{grid_of(block)} tr:first-child > *", count: 31
    assert_selector grid_of(block), text: "c1!"
    assert_equal 30, rows_of(block.reload.body_document(locale: :en)).first.size, "nothing over the limit is stored"
  end

  # ----- A table per language: the translation tab (Task 7) -----
  #
  # Table block spec decisions 8, 9 and 10: a language with no table starts
  # as a copy of the default language's, shown and not written; the state,
  # the reference card and AI are the body's.

  # Translates a table's Markdown cell by cell, from a word list, keeping
  # every pipe and the delimiter row: the shape that comes back is the shape
  # that went out. The system tests' AI provider (`GatedProvider`) prefixes
  # the whole text, which would put a word before the table's first pipe; the
  # app server runs in this process, so it sees this registration too.
  class TableProvider
    NAME = "test/tables".freeze
    WORDS = { "Plan" => "Tarif", "Price" => "Preis", "Basic" => "Einfach", "Starter" => "Anfang", "Pro" => "Profi" }.freeze

    def initialize(api_key:, model:); end

    def translate(texts:, from:, to:, format:) = texts.map { |text| text.gsub(/\b(#{WORDS.keys.join("|")})\b/) { WORDS.fetch(Regexp.last_match(1)) } }

    def test_connection = true
  end

  # Registered once and left registered, as `GatedProvider.install!` is: the
  # app server runs in this process, and resetting the registries
  # (`reloader.prepare!`) under a request still on the wire (an autosave, a
  # live fetch, a presence beat) could answer it from an empty registry. The
  # site's setting is the test's own row, rolled back with it.
  def with_table_provider
    AI::Providers.register(TableProvider::NAME, TableProvider) unless AI::Providers.find(TableProvider::NAME) == TableProvider
    site_settings(:default).update!(ai_provider: TableProvider::NAME, ai_api_key: "sk-test")
    yield
  end

  def body_in(block, locale) = block.reload.body_document(locale: locale)

  def saved_in(block, locale, &condition)
    document = nil
    assert_eventually(wait: 6, message: -> { "the #{locale} document never matched: #{document.to_h.to_json}" }) do
      document = body_in(block, locale)
      condition.call(document)
    end
    assert_empty document.validate, "the grid saved a document the server schema rejects"
    document
  end

  # A Table whose languages are written through the save service, as an
  # editor's saves are, so each translation keeps the source it was made from.
  def translated_table(page, languages)
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "table" },
      translations: languages.transform_values { |document| { body: document } }).record
    assert block.persisted?
    block
  end

  def open_translation(page, locale = "de")
    visit "/cs-studio/pages/#{page.id}?locale=#{locale}"
    assert_selector ".ProseMirror"
    await_admin_controllers
  end

  def right_aligned_prices = words([ %w[Plan Price], %w[Basic 5] ]).tap { |doc| doc["content"][0]["content"].each { |row| row["content"][1]["attrs"] = { "align" => "right" } } }

  test "the copied grid saves nothing until a cell is changed; then the language is Translated and the site shows it" do
    with_locales(%w[en de es], default: "en")
    live = create_page(title: "Live prices", translations: { "de" => { title: "Preise" } })
    block = translated_table(live, "en" => right_aligned_prices)
    publish_changes(live)
    source = body_in(block, :en).to_h

    open_translation(live)
    assert_selector "#{grid_of(block)} tr:first-child > th", count: 2
    assert_equal [ "Plan", "Price", "Basic", "5" ], all("#{grid_of(block)} th, #{grid_of(block)} td").map(&:text)
    assert_equal "right", cell(block, 1, 1).evaluate_script("getComputedStyle(this).textAlign")
    assert_equal({ "type" => "doc", "content" => [] }, JSON.parse(find("#{card(block)} input[name='block[body]']", visible: :all).value), "the field stays empty")
    assert_selector "#{card(block)} [data-original-for='body'][data-translation-state='missing']"
    assert_selector "#{card(block)} [data-translate-slot='body']"
    assert_equal "", find("#{card(block)} input[name='block[caption]']").value.to_s, "the caption is not copied"

    cell(block, 1, 0).click
    await_frames
    assert_writes_settled
    assert_empty Array(body_in(block, :de).to_h["content"]), "a click is no change: nothing is saved"
    assert_equal :missing, block.translation_state("body", "de")

    # Until a change is saved the German page shows the default language's table.
    editor = current_url
    visit PublicSite::Urls.new.path_for(live, "de")
    assert_selector "table td", text: "Basic"
    assert_no_selector "table td", text: "Einfach"
    visit editor
    assert_selector ".ProseMirror"
    await_admin_controllers

    cell(block, 1, 0).click

    key(:End)
    "Basic".length.times { key(:Backspace) }
    type_text "Einfach"
    document = saved_in(block, :de) { |doc| doc.table? && texts(doc).dig(1, 0) == "Einfach" }
    assert_equal [ %w[Plan Price], %w[Einfach 5] ], texts(document), "the copy is saved whole with the change"
    assert_equal aligns(RichText::Document.new(source)), aligns(document), "alignment came with the copy"
    assert_equal [ %w[th th], %w[td td] ], kinds(document)
    assert_equal source, body_in(block, :en).to_h, "the source is untouched"
    assert_equal :current, block.reload.translation_state("body", "de")

    assert_writes_settled
    publish_changes(live)
    visit PublicSite::Urls.new.path_for(live, "de")
    assert_selector "table td", text: "Einfach"
    assert_no_selector "table td", text: "Basic"
  end

  test "a changed source cell makes the table Outdated, the reference card names the cell's words, and Still correct clears it" do
    with_locales(%w[en de es], default: "en")
    block = translated_table(@page, "en" => words([ %w[Plan Price], %w[Basic 5] ]), "de" => words([ %w[Tarif Preis], %w[Einfach 5] ]))
    assert_equal :current, block.translation_state("body", "de")
    assert ContentBlocks::Save.call(block.reload, translations: { "en" => { body: words([ %w[Plan Price], %w[Starter 5] ]) } }).ok?
    assert_equal :outdated, block.reload.translation_state("body", "de")

    open_translation(@page)
    within("#{card(block)} [data-original-for='body']") do
      assert_selector "del", text: "Basic"
      assert_selector "ins", text: "Starter"
      assert_no_selector "ins", text: "Plan"
      click_on "Still correct — mark up to date"
    end

    assert_no_selector "#{card(block)} [data-original-for='body'] ins", wait: 5
    assert_equal :current, block.reload.translation_state("body", "de")
    assert_equal [ %w[Tarif Preis], %w[Einfach 5] ], texts(body_in(block, :de)), "Still correct changes nothing of the table"
  end

  test "Suggest update offers a table of the source's shape and Use puts it in the grid" do
    with_locales(%w[en de es], default: "en")
    with_table_provider do
      block = translated_table(@page, "en" => words([ %w[Plan Price], %w[Basic 5] ]))

      # An empty language: Translate, and Use fills the copied grid.
      open_translation(@page)
      within("#{card(block)} [data-translate-slot='body']") { find(:button, "Translate", exact: true).click }
      box = "#{card(block)} [data-field-name='body'] [id^='translation-suggestion-']"
      assert_selector "#{box} table td", text: "Einfach"
      assert_empty Array(body_in(block, :de).to_h["content"]), "a suggestion saves nothing by itself"
      within(box) { find(:button, "Use", exact: true).click }
      document = saved_in(block, :de) { |doc| doc.table? && texts(doc) == [ %w[Tarif Preis], %w[Einfach 5] ] }
      assert_equal [ %w[th th], %w[td td] ], kinds(document)
      assert_writes_settled

      # This language's own table of another shape, and a changed source.
      assert ContentBlocks::Save.call(block.reload, translations: { "de" => { body: words([ %w[Tarif Preis Extra], %w[Einfach 5 x], %w[Profi 9 y] ]) } }).ok?
      assert ContentBlocks::Save.call(block.reload, translations: { "en" => { body: words([ %w[Plan Price], %w[Starter 5] ]) } }).ok?
      assert_equal :outdated, block.reload.translation_state("body", "de")

      open_translation(@page)
      assert_selector "#{grid_of(block)} tr", count: 3
      within("#{card(block)} [data-original-for='body']") { find(:button, "Suggest update", exact: true).click }
      assert_selector "#{box} table tr", count: 2
      assert_selector "#{box} table td", text: "Anfang"
      assert_selector "#{grid_of(block)} tr", count: 3, wait: 0
      within(box) { find(:button, "Use", exact: true).click }

      assert_selector "#{grid_of(block)} tr", count: 2
      document = saved_in(block, :de) { |doc| texts(doc) == [ %w[Tarif Preis], %w[Anfang 5] ] }
      assert_equal [ %w[th th], %w[td td] ], kinds(document), "Use replaces the table whatever shape it had"
      assert_equal :current, block.reload.translation_state("body", "de")
    end
  end

  test "the translation tab's own grid has all the controls" do
    with_locales(%w[en de es], default: "en")
    block = translated_table(@page, "en" => words([ %w[Plan Price], %w[Basic 5] ]), "de" => words([ %w[Tarif Preis], %w[Einfach 5] ]))

    open_translation(@page)
    assert_selector "#{card(block)} [data-controller~='admin--editor--table']"
    assert_selector "#{card(block)} input[role=switch]", count: 2
    assert_selector "#{card(block)} [role=toolbar]"
    # The source beside it is read-only: a rendered table, not a grid.
    assert_selector "#{card(block)} [data-original-for='body'] table th", text: "Plan"
    assert_no_selector "#{card(block)} [data-original-for='body'] .ProseMirror"

    cell(block, 1, 0).click
    press "Add row"
    row_menu(block, "Insert below")
    column_menu(block, "Insert right")
    document = saved_in(block, :de) { |doc| rows_of(doc).size == 4 && rows_of(doc).first.size == 3 }
    assert_equal [ 3, 3, 3, 3 ], texts(document).map(&:size), "four rows of three columns"
    assert_equal %w[Tarif Preis Einfach 5].sort, texts(document).flatten.reject(&:empty?).sort, "every word kept"
    assert_equal [ %w[Plan Price], %w[Basic 5] ], texts(body_in(block, :en)), "the source keeps its own shape"
  end
end
