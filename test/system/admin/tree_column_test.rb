require "application_system_test_case"

# The page tree's column is as wide as the person made it (Claude Design,
# 2026-10-13: T1 the divider, T3 the tree beside the notes column). Only a
# browser can show any of it: every assertion compares a box with a width
# the test itself set, a pixel of tolerance and no measured time.
#
# THE ARITHMETIC the tests lean on. The modules sidebar is a 240px column
# from 1280px; the tree is 272px until someone chooses, never under 220px or
# over 480px, and never so wide that the editor column has less than 640px;
# the notes column is 400px. So at the suite's own 1400px window the divider
# goes all the way to 480px (1400 - 240 - 640 = 520), at 1280px it stops at
# 400px, and beside the notes the default tree fits from 1552px
# (240 + 272 + 400 + 640).
#
# WHO WROTE THE WIDTH. `admin--shell--tree-width` never reads `localStorage`:
# it works from the custom property on <html>. So a width found on <html>
# right after a load, when the test put it into the storage itself, can only
# be the layout's head script's doing -- which runs before the first paint,
# and is why the page does not jump.
class Admin::TreeColumnSystemTest < ApplicationSystemTestCase
  WIDTH_KEY = "cs-tree-width".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    # Three levels, so there is a row whose indent matters; drafts, whose
    # header has Notes.
    @docs = create_page(title: "Documentation", published: false)
    @guides = create_page(title: "Guides and tutorials", parent: @docs, published: false)
    @install = create_page(title: "Installing on a server of your own", parent: @guides, published: false)
  end

  # Both are remembered in this browser, and the browser is shared with the
  # tests that follow: the notes drawer's "open" (as every notes system test
  # does) and the tree's width.
  teardown do
    page.execute_script("try { window.localStorage.removeItem('cs-notes-open'); window.localStorage.removeItem('#{WIDTH_KEY}') } catch (error) {}")
  end

  # A test that resizes the window puts the size back, because the browser
  # is shared.
  def at_width(width)
    original = page.current_window.size
    page.current_window.resize_to(width, 900)
    yield
  ensure
    page.current_window.resize_to(*original)
  end

  def open_editor(record = @docs, query = "")
    visit "/cs-studio/pages/#{record.id}#{query}"
    await_admin_controllers
  end

  # `[left, top, right, bottom]` of the first element the selector finds.
  def box(selector)
    page.evaluate_script("(() => { const box = document.querySelector(#{selector.to_json}).getBoundingClientRect(); return [ box.left, box.top, box.right, box.bottom ] })()")
  end

  def tree_width = box("#tree-column").then { |tree| tree[2] - tree[0] }

  # The property on <html>: what was chosen ("" while nobody chose).
  def chosen = page.evaluate_script("document.documentElement.style.getPropertyValue('--admin-tree-width')")

  def stored = page.evaluate_script("window.localStorage.getItem('#{WIDTH_KEY}')")

  def fits? = page.evaluate_script("document.documentElement.hasAttribute('data-tree-fits')")

  def window_width = page.evaluate_script("window.innerWidth")

  # Found by its class: `role=separator` is also a line in a menu.
  def on_divider? = page.evaluate_script("document.activeElement.classList.contains('admin-tree-divider')")

  def divider = find(".admin-tree-divider", visible: :all)

  def value(name) = divider["aria-value#{name}"].to_i

  # The column is `width` wide, the editor starts where it ends, and the
  # separator says so.
  def assert_tree(width, sidebar: 240)
    assert_eventually(message: -> { "the tree column is #{tree_width}px wide, not #{width}px" }) { (tree_width - width).abs <= 1 }
    assert_in_delta sidebar + width, box(".admin-shell__main")[0], 1, "the editor starts where the tree ends"
    assert_equal width, value(:now)
  end

  # The keyboard's own way to the divider: Tab from the tree's last control.
  # (A focus given by script is not always a keyboard's focus to the browser,
  # and the tooltip shows for a keyboard's only.)
  def focus_divider
    page.execute_script("(() => { const all = document.querySelectorAll('#tree a[href], #tree button'); all[all.length - 1].focus() })()")
    keys(:tab)
    assert_eventually(message: "Tab from the tree's last control did not reach the divider") { on_divider? }
  end

  def keys(*pressed) = page.driver.browser.keyboard.type(*pressed)

  # Presses on the divider and walks the pointer until the column would be
  # `width` wide; the caller asserts what it expects mid-drag and releases.
  def drag_divider(to:)
    edge = box("#tree-column")[2]
    mouse = page.driver.browser.mouse
    mouse.move(x: edge, y: 400)
    mouse.down
    mouse.move(x: edge + (to - tree_width), y: 420, steps: 5)
    mouse
  end

  def open_notes
    find("#notes-open").click
    assert_selector "#notes-drawer #notes-list"
  end

  def close_notes
    find("#notes-drawer button[aria-label='Close']").click
    assert_no_selector "#notes-drawer"
  end

  test "dragging the divider resizes the tree and the editor as it goes, and the release remembers the width" do
    open_editor
    assert_tree 272
    assert_equal "", chosen
    main_before = box(".admin-shell__main")

    mouse = drag_divider(to: 372)

    # Mid-drag: the column already has the width, the editor has given it up,
    # and the document says a pointer is at work.
    assert_tree 372
    main = box(".admin-shell__main")
    assert_in_delta main_before[2], main[2], 1, "the editor's right edge stays"
    assert_in_delta (main_before[2] - main_before[0]) - 100, main[2] - main[0], 1, "the editor is 100px narrower"
    assert page.evaluate_script("document.documentElement.hasAttribute('data-tree-resizing')")
    assert_selector ".admin-tree-divider[data-dragging]", visible: :all
    assert_nil stored, "nothing is remembered before the release"

    mouse.up

    assert_eventually(message: "the release did not remember the width") { stored == "372" }
    assert_equal "372px", chosen
    assert_not page.evaluate_script("document.documentElement.hasAttribute('data-tree-resizing')")
    assert_no_selector ".admin-tree-divider[data-dragging]", visible: :all
    assert_tree 372
  end

  test "minimum and maximum hold under the pointer: 220px and 480px, however far it is dragged, and the grid draws what the separator says" do
    open_editor

    mouse = drag_divider(to: 20)
    assert_tree 220
    mouse.up
    assert_eventually { stored == "220" }
    assert_equal 220, value(:min)

    mouse = drag_divider(to: 900)
    assert_tree 480
    mouse.up
    assert_eventually { stored == "480" }
    assert_equal 480, value(:max)
    assert_operator window_width - box(".admin-shell__main")[0], :>=, 640, "the editor keeps its 640px"
  end

  test "the keyboard: arrows step 16px and with Shift 64px, Home and End go to the limits and stop there, Enter resets" do
    open_editor
    focus_divider

    keys(:right)
    assert_tree 288
    assert_eventually { stored == "288" }
    keys([ :shift, :right ])
    assert_tree 352
    keys(:left)
    assert_tree 336
    keys([ :shift, :left ])
    assert_tree 272

    keys(:home)
    assert_tree 220
    keys(:left)
    assert_tree 220
    keys([ :shift, :left ])
    assert_tree 220

    keys(:end)
    assert_tree 480
    keys(:right)
    assert_tree 480
    assert_eventually { stored == "480" }

    keys(:enter)
    assert_tree 272
    assert_equal "", chosen, "a reset leaves the column to the stylesheet's own default"
    assert_nil stored
    assert on_divider?, "the focus stayed on the divider throughout"
  end

  test "on keyboard focus the shared tooltip names the current width, and follows it" do
    open_editor
    assert_no_selector ".admin-tree-divider [data-tooltip]"

    focus_divider
    assert_selector ".admin-tree-divider [data-tooltip]", text: "Tree width 272px. Arrow keys to resize."
    # It hangs near the top of the window, not under the page-high divider.
    tip = box(".admin-tree-divider [data-tooltip]")
    assert_operator tip[1], :<, 200
    assert_operator tip[0], :>=, 0

    keys(:right)
    assert_selector ".admin-tree-divider [data-tooltip]", text: "Tree width 288px. Arrow keys to resize."
  end

  test "a double click on the divider resets the width to the default" do
    open_editor
    focus_divider
    keys([ :shift, :right ])
    assert_tree 336

    edge = box("#tree-column")[2]
    mouse = page.driver.browser.mouse
    mouse.move(x: edge, y: 400)
    mouse.down.up
    mouse.down(count: 2).up(count: 2)

    assert_tree 272
    assert_equal "", chosen
    assert_nil stored
    assert_not page.evaluate_script("document.documentElement.hasAttribute('data-tree-resizing')")
  end

  test "the maximum is what leaves the editor 640px: 400px at a 1280px window, and a wider choice is kept for a wider window" do
    open_editor
    focus_divider
    keys(:end)
    assert_tree 480

    at_width(1280) do
      # Shown narrower, chosen as it was: the grid's own clamp, and the
      # separator's values follow on the resize.
      assert_eventually(message: -> { "the separator's maximum is #{value(:max)}" }) { value(:max) == 400 }
      assert_tree 400
      assert_equal "480px", chosen
      assert_in_delta 640, window_width - box(".admin-shell__main")[0], 1, "the editor column has exactly its 640px"

      # A step from what is SHOWN, and End is where it already is.
      keys(:left)
      assert_tree 384
      keys(:end)
      assert_tree 400
    end

    # 1024px to 1279px: the sidebar is a drawer and takes no room.
    at_width(1100) do
      assert_eventually { value(:max) == 460 }
      keys(:end)
      assert_tree 460, sidebar: 0
      assert_in_delta 640, window_width - box(".admin-shell__main")[0], 1
    end
  end

  test "the width survives a reload: the head script lays the page out at it, on a screen with a tree and on one without" do
    open_editor
    focus_divider
    keys([ :shift, :right ], :right)
    assert_tree 352
    assert_eventually { stored == "352" }

    open_editor
    assert_equal "352px", chosen
    assert_tree 352

    # No tree, no divider, no script of the tree's: only the head script can
    # have said this, and it says it for the Pages screen a visit leads to.
    visit "/cs-studio/posts"
    assert_selector "h1", text: "Posts"
    assert_no_selector ".admin-tree-divider", visible: :all
    assert_equal "352px", chosen
  end

  test "what is stored but is nobody's choice sets nothing: junk, too narrow, too wide" do
    open_editor
    %w[wide 100 9999].each do |junk|
      page.execute_script("window.localStorage.setItem('#{WIDTH_KEY}', #{junk.to_json})")
      open_editor
      assert_equal "", chosen, "#{junk.inspect} was taken for a width"
      assert_tree 272
    end
  end

  test "the width survives a Turbo visit and Back, and a page picked in the tree" do
    open_editor
    focus_divider
    keys([ :shift, :right ])
    assert_tree 336

    click_frame_link { within("#tree") { click_link "Guides and tutorials" } }
    assert_current_path "/cs-studio/pages/#{@guides.id}"
    assert_tree 336

    within("nav[aria-label='Modules']") { click_link "Posts" }
    assert_selector "h1", text: "Posts"
    assert_equal "336px", chosen

    page.go_back
    assert_selector "#tree-column .admin-tree-divider", visible: :all
    await_admin_controllers
    assert_tree 336
    assert_equal 480, value(:max)
    assert_not page.evaluate_script("document.documentElement.hasAttribute('data-tree-resizing')")
    assert_no_selector ".admin-tree-divider[data-dragging], .admin-tree-divider[data-hover]", visible: :all
  end

  # Private windows and blocked site data: reading `localStorage` throws.
  test "where localStorage is refused the page works at the default width, the divider still resizes, and nothing is an error" do
    script = page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument",
      source: "Object.defineProperty(window, 'localStorage', { get() { throw new DOMException('refused', 'SecurityError') } })")
    open_editor
    assert page.evaluate_script("(() => { try { window.localStorage; return false } catch (error) { return true } })()"), "the stub is not in place"
    assert_equal "", chosen
    assert_tree 272

    focus_divider
    keys(:right)
    assert_tree 288
    # The document holds the choice for as long as it lives.
    click_frame_link { within("#tree") { click_link "Guides and tutorials" } }
    assert_tree 288

    open_editor
    assert_equal "", chosen
    assert_tree 272
  ensure
    page.driver.browser.page.command("Page.removeScriptToEvaluateOnNewDocument", identifier: script["identifier"]) if script
    # The teardown reads the storage of whatever page is open: one without the stub.
    visit "/cs-studio/posts"
  end

  # T3. 240 + 272 + 400 + 640 = 1552.
  test "at 1600px the tree stays a column beside the editor and the open notes, and its divider stops at the width that keeps the editor 640px" do
    at_width(1600) do
      open_editor
      assert fits?
      open_notes

      assert_tree 272
      assert_no_selector "button[aria-controls='tree-column']"
      drawer = box("#notes-drawer")
      assert_equal [ 1200, 1600 ], [ drawer[0], drawer[2] ].map(&:round), "the notes are the window's last 400px"
      assert_operator drawer[0] - box(".admin-shell__main")[0], :>=, 640, "the editor keeps 640px between the tree and the notes"

      # 1600 - 240 - 400 - 640 = 320.
      assert_eventually(message: -> { "the separator's maximum is #{value(:max)}" }) { value(:max) == 320 }
      focus_divider
      keys(:end)
      assert_tree 320
      assert_in_delta 640, drawer[0] - box(".admin-shell__main")[0], 1
      mouse = drag_divider(to: 480)
      assert_tree 320
      mouse.up
      assert fits?, "a drag beside the notes never folds the tree"
      assert_selector "#tree-column"

      # Without the notes the divider goes on to the maximum.
      close_notes
      assert_eventually(message: -> { "the separator's maximum is #{value(:max)}" }) { value(:max) == 480 }
      assert_tree 320
    end
  end

  test "at 1440px the tree folds while the notes are open, the header's Pages button shows it at its width, and closing the notes brings the column back at that width" do
    at_width(1440) do
      open_editor
      focus_divider
      keys(:right, :right)
      assert_tree 304
      assert_not fits?
      tree_button = ".admin-editor-header button[aria-controls='tree-column']"
      assert_no_selector tree_button

      open_notes

      assert_no_selector "#tree-column"
      assert_no_selector ".admin-tree-divider"
      assert_selector "#{tree_button}[aria-expanded=false]", text: "Pages"
      assert_in_delta 240, box(".admin-shell__main")[0], 1, "the editor starts beside the sidebar"

      # The folded tree is the drawer it always was, at the chosen width and
      # with no divider.
      find(tree_button).click
      assert_selector "#tree-column[data-open]"
      tree = box("#tree-column")
      assert_equal [ 240, 544 ], [ tree[0], tree[2] ].map(&:round)
      assert_no_selector ".admin-tree-divider"
      keys(:escape)
      assert_no_selector "#tree-column"

      close_notes
      assert_selector "#tree-column"
      assert_no_selector tree_button
      assert_equal "304px", chosen, "Studio did not narrow the tree to make it fit"
      assert_tree 304
    end
  end

  test "the fold follows the chosen width and the window: a wider tree folds at 1600px, and a window widened and narrowed again unfolds and folds" do
    at_width(1600) do
      open_editor
      focus_divider
      keys([ :shift, :right ], [ :shift, :right ])
      assert_tree 400
      # 240 + 400 + 400 + 640 = 1680.
      assert_not fits?

      open_notes
      assert_no_selector "#tree-column"
      assert_selector ".admin-editor-header button[aria-controls='tree-column']"

      page.current_window.resize_to(1700, 900)
      assert_selector "#tree-column"
      assert_no_selector ".admin-editor-header button[aria-controls='tree-column']"
      assert_tree 400

      page.current_window.resize_to(1600, 900)
      assert_no_selector "#tree-column"
      assert_equal "400px", chosen
    end
  end

  test "a reload with the notes open lays the page out as it will be: the tree beside them where it fits, folded where it does not" do
    at_width(1600) do
      open_editor(@docs, "?notes=open")
      assert_selector "#notes-drawer #notes-list"
      assert fits?
      assert_tree 272
      assert_no_selector "button[aria-controls='tree-column']"
    end

    at_width(1440) do
      open_editor(@docs, "?notes=open")
      assert_selector "#notes-drawer #notes-list"
      assert_not fits?
      assert_no_selector "#tree-column"
      assert_selector ".admin-editor-header button[aria-controls='tree-column']"
    end
  end

  test "below 1024px there is no divider, and the tree's drawer keeps its fixed width whatever was chosen" do
    open_editor
    focus_divider
    keys(:end)
    assert_tree 480

    at_width(900) do
      open_editor
      assert_no_selector ".admin-tree-divider"
      assert_equal "480px", chosen

      find("button[aria-controls='tree-column']").click
      assert_selector "#tree-column[data-open]"
      assert_eventually(message: -> { "the drawer is #{tree_width}px wide" }) { (tree_width - 272).abs <= 1 }
      assert_no_selector ".admin-tree-divider"
    end
  end
end
