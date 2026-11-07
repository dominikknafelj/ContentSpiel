require "application_system_test_case"

# The page tree folds to a strip and back ("Hide page tree" in the tree's
# head, "Show page tree" on the strip), and the fold is remembered in this
# browser, laid out before the first paint as the width is
# (`admin/shared/_tree_head`). The strip is 44px at a 16px root font; the
# chosen width is kept while folded, so the column comes back at it.
#
# Below 1024px the tree is a drawer and the fold means nothing there: the
# drawer is the ordinary one, and the fold is back when the window is wide
# again (the attribute on <html> stays; only the stylesheet asks it, from
# 1024px).
class Admin::TreeFoldSystemTest < ApplicationSystemTestCase
  FOLD_KEY = "cs-tree-folded".freeze
  WIDTH_KEY = "cs-tree-width".freeze
  STRIP = 44
  HIDE = "button[aria-label='Hide page tree']".freeze
  SHOW = "button[aria-label='Show page tree']".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @docs = create_page(title: "Documentation", published: false)
    @guides = create_page(title: "Guides and tutorials", parent: @docs, published: false)
  end

  # The fold, the width and the notes drawer's "open" are remembered in this browser, which the tests
  # that follow share.
  teardown do
    page.execute_script("try { window.localStorage.removeItem('#{FOLD_KEY}'); window.localStorage.removeItem('#{WIDTH_KEY}'); window.localStorage.removeItem('cs-notes-open') } catch (error) {}")
  end

  def open_editor(record = @docs) = visit_editor(record)

  # `[left, top, right, bottom]` of the first element the selector finds.
  def box(selector)
    page.evaluate_script("(() => { const box = document.querySelector(#{selector.to_json}).getBoundingClientRect(); return [ box.left, box.top, box.right, box.bottom ] })()")
  end

  def width_of(selector) = box(selector).then { |edges| edges[2] - edges[0] }

  def tree_width = width_of("#tree-column")

  def folded? = page.evaluate_script("document.documentElement.hasAttribute('data-tree-folded')")

  def focused_label = page.evaluate_script("document.activeElement?.getAttribute('aria-label')")

  # A drawer moves the focus to its first control that is drawn: in the tree's
  # drawer that is "+ New page", never the strip's button, which comes first
  # in the column but is not drawn in a drawer, and never <body>.
  def assert_focus_on_new_page
    assert_eventually(message: -> { "the focus is on #{page.evaluate_script("document.activeElement.outerHTML.slice(0, 120)")}" }) do
      page.evaluate_script("(() => { const active = document.activeElement; return active.matches('#tree-column #tree a[href]') && active.textContent.trim() === '+ New page' })()")
    end
  end

  def assert_tree(width)
    assert_eventually(message: -> { "the tree column is #{tree_width}px wide, not #{width}px" }) { (tree_width - width).abs <= 1 }
  end

  # A drag of the divider until the column is `width` wide, with the moves a
  # real mouse sends (`button: "left"`; see `tree_column_test.rb`,
  # `move_pressed`).
  def drag_tree(to:)
    edge = box("#tree-column")[2]
    mouse = page.driver.browser.mouse
    mouse.move(x: edge, y: 400)
    mouse.down
    target = edge + (to - tree_width)
    5.times do |step|
      page.driver.browser.page.command("Input.dispatchMouseEvent", type: "mouseMoved", x: edge + ((target - edge) * (step + 1) / 5.0), y: 420, button: "left", buttons: 1)
    end
    mouse.up
  end

  test "Hide page tree folds the column to a strip, the editor widens, and Show page tree brings it back at its chosen width" do
    at_window(1600) do
      open_editor
      drag_tree(to: 320)
      assert_tree 320
      editor = width_of(".admin-shell__main")

      find(HIDE).click
      assert_tree STRIP
      assert folded?
      assert_in_delta editor + 320 - STRIP, width_of(".admin-shell__main"), 1, "the editor takes the room the tree gave up"
      assert_no_selector "#tree"
      assert_no_selector ".admin-tree-divider"
      assert_eventually(message: -> { "the focus is on #{focused_label.inspect}" }) { focused_label == "Show page tree" }
      assert_equal "320px", page.evaluate_script("document.documentElement.style.getPropertyValue('--admin-tree-width')"), "the fold keeps the chosen width"

      find(SHOW).click
      assert_tree 320
      assert_not folded?
      assert_in_delta editor, width_of(".admin-shell__main"), 1
      assert_selector "#tree", text: "Documentation"
      assert_eventually(message: -> { "the focus is on #{focused_label.inspect}" }) { focused_label == "Hide page tree" }
      assert_nil page.evaluate_script("window.localStorage.getItem('#{FOLD_KEY}')"), "unfolding forgets the fold"
    end
  end

  # A visit from ⌘K keeps <html>, so the fold is there; a new document only
  # has it from the head script, and the probe reads it at
  # DOMContentLoaded, before any controller has connected.
  test "a fold is remembered: the next screen is laid out folded from the first paint" do
    at_window(1600) do
      open_editor
      find(HIDE).click
      assert_tree STRIP
      assert_equal "1", page.evaluate_script("window.localStorage.getItem('#{FOLD_KEY}')")

      find("body").send_keys([ :control, "k" ])
      assert_selector "dialog#command-palette[open]"
      find("dialog#command-palette input").set("Guides and")
      assert_selector "#jump-results [role=option][aria-selected=true]", text: @guides.title
      find("dialog#command-palette input").send_keys(:enter)
      assert_current_path "/cs-studio/pages/#{@guides.id}"
      await_admin_controllers
      assert folded?
      assert_tree STRIP

      script = page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
        document.addEventListener("DOMContentLoaded", () => {
          const column = document.getElementById("tree-column")
          window.__atFirstPaint = { folded: document.documentElement.hasAttribute("data-tree-folded"), width: column && column.getBoundingClientRect().width }
        })
      JS
      begin
        open_editor
        probe = page.evaluate_script("window.__atFirstPaint")
        assert_equal true, probe["folded"], "the head script did not fold the column before the first paint"
        assert_in_delta STRIP, probe["width"], 1, "the column was not the strip at DOMContentLoaded"
      ensure
        page.driver.browser.page.command("Page.removeScriptToEvaluateOnNewDocument", identifier: script["identifier"])
      end
    end
  end

  test "a folded tree is the ordinary drawer under 1024px, and folded again at 1600px" do
    at_window(1600) do
      open_editor
      find(HIDE).click
      assert_tree STRIP

      at_window(900) do
        assert_no_selector SHOW
        assert_no_selector HIDE
        find("button[aria-controls='tree-column'][data-admin--shell--drawer-target=trigger]", text: "Pages").click
        assert_selector "#tree-column[data-open]"
        assert_focus_on_new_page
        assert_tree 272
        within("#tree-column") { assert_selector "#tree a", text: "Documentation" }
        assert_no_selector SHOW
        assert folded?, "the fold is kept for a wide window"
        page.driver.browser.keyboard.type(:escape)
        assert_no_selector "#tree-column"
      end

      assert_tree STRIP
      assert_selector SHOW
      assert_no_selector "#tree"
    end
  end

  test "the fold buttons say what they control" do
    at_window(1600) do
      open_editor
      assert_selector "#{HIDE}[aria-controls='tree-column'][aria-expanded='true']"
      assert_selector "#{SHOW}[aria-controls='tree-column']", visible: :all
      assert_no_selector SHOW

      find(HIDE).click
      assert_selector "#{SHOW}[aria-controls='tree-column'][aria-expanded='false']"
      assert_selector "#{HIDE}[aria-controls='tree-column'][aria-expanded='false']", visible: :all

      find(SHOW).click
      assert_selector "#{HIDE}[aria-expanded='true']"
      assert_selector "#{SHOW}[aria-expanded='true']", visible: :all
    end
  end

  # The notes stand in the editor's rail or over the canvas, never beside the
  # tree, so opening them changes nothing of the fold.
  test "a folded tree stays the strip when the notes open, at a docked and at a narrower window" do
    at_window(1600) do
      open_editor
      find(HIDE).click
      assert_tree STRIP

      find("#notes-open").click
      assert_selector "#notes-drawer #notes-list"
      assert_tree STRIP
      assert_selector SHOW

      at_window(1060) do
        assert_tree STRIP
        assert_selector "#notes-drawer #notes-list"
        assert_selector SHOW
        assert_no_selector ".admin-shell__scrim"
      end
    end
  ensure
    page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}")
  end
end
