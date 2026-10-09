require "application_system_test_case"

# The notes drawer as a COLUMN (handoff, "Decisions after the build started",
# decision 1): from 1024px it stands to the right of the content and below
# the editor's sticky header, takes its room from the content column, and the
# page tree folds into the "Pages ▾" drawer while it is open. Only a browser
# can show any of this: every assertion here compares boxes.
class Admin::NotesColumnSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    with_locales(%w[en de], default: "en")
    sign_in_via_form(users(:one))
    # A draft: its header has all three of Notes, Preview and Publish.
    @page = create_page(title: "Pricing", published: false)
    @block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: rich_doc("Hello **there**") } }).record
  end

  # "Open" is remembered in this browser, and the browser is shared with the
  # tests that follow: every notes system test forgets it again.
  teardown { page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}") }

  def at_width(width)
    original = page.current_window.size
    page.current_window.resize_to(width, 900)
    yield
  ensure
    page.current_window.resize_to(*original)
  end

  def open_editor(query = "")
    visit "/cs-studio/pages/#{@page.id}#{query}"
    await_admin_controllers
  end

  def open_notes
    find("#notes-open").click
    assert_selector "#notes-drawer #notes-list"
  end

  # `[left, top, right, bottom]` of the first element the selector finds.
  def box(selector)
    page.evaluate_script("(() => { const box = document.querySelector(#{selector.to_json}).getBoundingClientRect(); return [ box.left, box.top, box.right, box.bottom ] })()")
  end

  def box_of(element)
    page.evaluate_script("(() => { const box = arguments[0].getBoundingClientRect(); return [ box.left, box.top, box.right, box.bottom ] })()", element)
  end

  def overlap?(one, other) = one[0] < other[2] && other[0] < one[2] && one[1] < other[3] && other[1] < one[3]

  [ 1024, 1280, 1440 ].each do |width|
    test "at #{width}px the open drawer is a 400px column below the header, and nothing of the header or the content is under it" do
      at_width(width) do
        open_editor
        header_before = box(".admin-editor-header")
        open_notes

        drawer = box("#notes-drawer")
        header = box(".admin-editor-header")
        assert_equal [ width - 400, width ], [ drawer[0], drawer[2] ].map(&:round), "the drawer is the window's last 400px"
        assert_in_delta header[3], drawer[1], 1, "the drawer starts where the header ends"
        assert_in_delta 900, drawer[3], 1, "and reaches the window's bottom edge"
        # The header spans the content and the drawer, and opening the notes
        # did not change its height.
        assert_in_delta width, header[2], 1
        assert_in_delta header_before[3] - header_before[1], header[3] - header[1], 1, "the header kept its height"
        assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('#notes-drawer')).boxShadow")

        # (a) The action row is one line, and its controls are clear of the drawer.
        actions = within(".admin-editor-header") { [ find("#notes-open"), find_link("Preview"), find_button("Publish") ] }.map { |control| box_of(control) }
        assert_equal 1, actions.map { |one| ((one[1] + one[3]) / 2).round(-1) }.uniq.size, "Notes, Preview and Publish share a line (#{actions})"
        actions.each do |one|
          assert_operator one[2], :<=, width
          assert_not overlap?(one, drawer), "a header control is under the drawer (#{one} against #{drawer})"
        end

        # (b) Nothing of the content column is under the drawer.
        assert_operator box(".admin-content-blocks")[2], :<=, drawer[0]
        assert_operator box("#content_block_#{@block.id}")[2], :<=, drawer[0]

        # (e) A top-level block's menu opens inside the content column.
        find("#content_block_#{@block.id} button[aria-label='Block actions']").click
        menu = box("#content_block_#{@block.id} [role=menu]")
        assert_operator menu[0], :>=, box(".admin-content-blocks")[0]
        assert_operator menu[2], :<=, drawer[0], "the block's menu reaches under the drawer"
        find("#content_block_#{@block.id} button[aria-label='Block actions']").click

        # Closing gives the room back.
        find("#notes-drawer button[aria-label='Close']").click
        assert_no_selector "#notes-drawer"
        assert_operator box(".admin-content-blocks")[2], :>, width - 400
      end
    end
  end

  # (c) The 768-1023px pattern, at a width where the tree is otherwise a
  # column: the same element, button and drawer.
  test "at 1024px the page tree folds into the Pages drawer while the notes are open, opens from it beside them, and is a column again when they close" do
    at_width(1024) do
      open_editor
      assert_operator box("#tree-column")[2], :<=, box(".admin-shell__main")[0] + 1, "the premise: the tree is a column at 1024px"
      assert_no_selector "button[aria-controls='tree-column']"

      open_notes
      assert_no_selector "#tree-column"
      assert_selector "button[aria-controls='tree-column'][aria-expanded=false]", text: "Pages"
      assert_in_delta 0, box(".admin-shell__main")[0], 1, "the content column starts at the window's edge"

      # The tree opens as a drawer and the notes stay: it is a drawer because
      # they are open.
      find("button[aria-controls='tree-column']").click
      assert_selector "#tree-column[data-open]"
      assert_selector ".admin-shell__scrim"
      assert_selector "#notes-drawer #notes-list"
      find(".admin-shell__scrim").click
      assert_no_selector "#tree-column"
      assert_no_selector ".admin-shell__scrim"

      find("#notes-drawer button[aria-label='Close']").click
      assert_no_selector "#notes-drawer"
      assert_selector "#tree-column"
      assert_no_selector "button[aria-controls='tree-column']"
      assert_operator box("#tree-column")[2], :<=, box(".admin-shell__main")[0] + 1
    end
  end

  # (d) The pair's breakpoint is its form's width, so the column narrowing the
  # content is all it takes.
  test "a translation pair stacks, the original first, when the notes column leaves its form under 880px" do
    at_width(1700) do
      open_editor("?locale=de")
      assert_selector "[data-block-id='#{@block.id}'] .ProseMirror"
      form = "[data-block-id='#{@block.id}'] form.admin-translation-form"
      original = "[data-block-id='#{@block.id}'] [data-original-for='body']"
      field = "[data-block-id='#{@block.id}'] .admin-rich-text"
      assert_operator page.evaluate_script("document.querySelector(#{form.to_json}).clientWidth"), :>=, 880, "the premise: side by side without the notes"
      assert_in_delta box(original)[1], box(field)[1], 40

      open_notes

      assert_operator page.evaluate_script("document.querySelector(#{form.to_json}).clientWidth"), :<, 880
      assert_operator box(original)[3], :<=, box(field)[1] + 1, "the original should sit above the field when stacked"
      # Still usable: the field takes text.
      find("#{field} .ProseMirror").click
      find("#{field} .ProseMirror").send_keys("Hallo")
      assert_selector "#{field} .ProseMirror", text: "Hallo"
      assert_writes_settled
    end
  end

  test "a remembered open lays the next editor out with the column, and a window under 1024px keeps the sheet" do
    at_width(1280) do
      open_editor
      open_notes
      open_editor
      assert_selector "#notes-drawer #notes-list"
      assert_selector "html[data-notes-open]"
      assert_operator box(".admin-content-blocks")[2], :<=, box("#notes-drawer")[0]

      page.current_window.resize_to(900, 900)
      open_editor
      # Remembered, and not opened by itself below 1024px: no room is kept.
      assert_no_selector "#notes-drawer"
      assert_no_selector "html[data-notes-open]"
      assert_operator box(".admin-content-blocks")[2], :>, 800
    end
  end
end
