require "application_system_test_case"

# The page editor's rail (`admin/pages/show`, `.admin-rail-grid`,
# `admin--ui--rail`): where the editor area has 1200px, the page settings
# stand in a 360px rail 28px right of a 900px blocks column, with a Page and a
# Section tab; below that they stand above the blocks at 760px, as one
# column. The editor area is the container, so a folded tree docks the rail
# at a window that would not otherwise. Each rule that overrides a base rule
# while docked (the 900px column over 760px, the forced-open settings over a
# folded `<details>`) is measured at both widths here.
class Admin::EditorRailSystemTest < ApplicationSystemTestCase
  WIDE = 1900
  NARROW = 1400

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @page = create_page(title: "Pricing", published: false)
    @section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
  end

  teardown do
    page.execute_script("try { window.localStorage.removeItem('cs-tree-folded'); window.localStorage.removeItem('cs-tree-width') } catch (error) {}")
  end

  # `[left, top, right, bottom]` of the first element the selector finds.
  def box(selector)
    page.evaluate_script("(() => { const box = document.querySelector(#{selector.to_json}).getBoundingClientRect(); return [ box.left, box.top, box.right, box.bottom ] })()")
  end

  def width_of(selector) = box(selector).then { |edges| edges[2] - edges[0] }

  def docked? = page.evaluate_script("document.getElementById('editor-grid').hasAttribute('data-rail-docked')")

  def assert_docked(docked = true)
    assert_eventually(message: "the rail is #{docked ? "not " : ""}docked") { docked? == docked }
  end

  def keyboard = page.driver.browser.keyboard

  def focus_is_on(selector) = page.evaluate_script("document.activeElement === document.querySelector(#{selector.to_json})")

  PAGE_TAB = "#editor-grid-tab-page".freeze
  SECTION_TAB = "#editor-grid-tab-section".freeze

  test "at a wide window the rail stands right of a 900px blocks column, left-aligned, 28px apart" do
    at_window(WIDE) do
      visit_editor(@page)
      assert_docked

      area = box("#editing")
      blocks = box(".admin-content-blocks")
      rail = box("#editor-grid-panel-page")
      assert_in_delta area[0], blocks[0], 1, "the blocks column starts at the content's left edge"
      assert_in_delta 900, blocks[2] - blocks[0], 1
      assert_in_delta blocks[2] + 28, rail[0], 1, "the rail stands 28px right of the blocks"
      assert_in_delta 360, rail[2] - rail[0], 1
      assert_in_delta blocks[1], box(".admin-rail__tabs")[1], 1, "the rail's tabs and the blocks start at one height"
      assert_selector "#editor-grid [role=tablist] [role=tab]", count: 2
    end
  end

  test "below the threshold the page settings stand above the blocks at 760px and there are no tabs" do
    at_window(NARROW) do
      visit_editor(@page)
      assert_docked(false)

      settings = box("#page-settings")
      blocks = box(".admin-content-blocks")
      assert_in_delta 760, settings[2] - settings[0], 1
      assert_in_delta 760, blocks[2] - blocks[0], 1
      assert_in_delta settings[0], blocks[0], 1
      assert_operator settings[3], :<, blocks[1], "the settings stand above the blocks"
      assert_no_selector "#editor-grid [role=tablist]"
      assert_no_selector "#editor-grid-panel-section"
    end
  end

  test "the document order is header, tabs, settings, blocks" do
    at_window(WIDE) do
      visit_editor(@page)
      assert_docked

      page.execute_script("[ ...document.querySelectorAll('.admin-language-tabs a[href]') ].pop().focus()")
      seen = []
      60.times do
        keyboard.type(:tab)
        where = page.evaluate_script(<<~JS)
          (() => {
            const active = document.activeElement
            if (active.closest(".admin-editor-header")) return "header"
            if (active.closest(".admin-rail__tabs")) return "tabs"
            if (active.closest("#editor-grid-panel-page")) return "settings"
            if (active.closest(".admin-content-blocks")) return "blocks"
            return "other"
          })()
        JS
        seen << where unless seen.last == where
        break if where == "blocks"
      end

      assert_equal %w[tabs settings blocks], seen.drop_while { |where| where == "header" }, "the focus went #{seen.inspect}"
    end
  end

  test "folding the tree at 1600px docks the rail" do
    at_window(1600) do
      visit_editor(@page)
      assert_docked(false)

      find("button[aria-label='Hide page tree']").click
      assert_docked
      # The room left of a 360px rail, up to 900px.
      assert_operator width_of(".admin-content-blocks"), :>, 760
      assert_in_delta 360, width_of("#editor-grid-panel-page"), 1
      assert_in_delta box(".admin-content-blocks")[2] + 28, box("#editor-grid-panel-page")[0], 1

      find("button[aria-label='Show page tree']").click
      assert_docked(false)
      assert_in_delta 760, width_of(".admin-content-blocks"), 1
    end
  end

  test "a translation tab never docks the rail" do
    at_window(WIDE) do
      visit_editor(@page, locale: "de")

      assert_selector "#editor-grid.admin-rail-grid--folded"
      await_frames
      assert_docked(false)
      assert_no_selector "#editor-grid [role=tablist]"
      assert_operator box("#page-settings")[3], :<, box(".admin-content-blocks")[1]
    end
  end

  test "the page settings are one form at every width" do
    at_window(WIDE) do
      visit_editor(@page)
      assert_docked
      assert_selector "#page-settings", count: 1
      assert_selector "#page-settings input[name='base_updated_at']", count: 1, visible: :all
      page.execute_script("document.querySelector('#page-settings form').dataset.probe = 'kept'")

      find("#page-title").send_keys(" plans")
      assert_writes_settled
      assert_eventually(message: "the docked save never landed") { @page.reload.title == "Pricing plans" }

      page.current_window.resize_to(NARROW, 900)
      assert_docked(false)
      assert_selector "#page-settings", count: 1
      assert_selector "#page-settings input[name='base_updated_at']", count: 1, visible: :all
      assert_equal "kept", page.evaluate_script("document.querySelector('#page-settings form').dataset.probe")

      find("#page-title").send_keys(" now")
      assert_writes_settled
      assert_eventually(message: "the save below the threshold never landed") { @page.reload.title == "Pricing plans now" }
      assert_no_selector "[data-save-state=paused]"
      assert_no_text "Changed elsewhere"
    end
  end

  # Whether the title field is drawn: a field in a folded `<details>` has no
  # box, and the docked rule gives it one without opening the element.
  def title_drawn? = page.evaluate_script("(() => { const field = document.getElementById('page-title'); return field.checkVisibility() && field.getBoundingClientRect().height > 0 })()")

  def summary_drawn? = page.evaluate_script("document.querySelector('#page-settings > summary').getBoundingClientRect().height > 0")

  test "the page settings are forced open while docked, and keep the person's disclosure state below" do
    at_window(NARROW) do
      visit_editor(@page)
      assert_docked(false)
      find("#page-settings > summary").click
      assert_equal false, page.evaluate_script("document.getElementById('page-settings').open")
      assert_eventually(message: "the folded settings still draw the title") { !title_drawn? }

      page.current_window.resize_to(WIDE, 900)
      assert_docked
      assert_eventually(message: "the docked settings do not draw the title") { title_drawn? }
      assert_not summary_drawn?, "the summary is drawn in the rail"
      assert_equal false, page.evaluate_script("document.getElementById('page-settings').open"), "the docked rule shows the settings without opening them"

      page.current_window.resize_to(NARROW, 900)
      assert_docked(false)
      assert_eventually(message: "the person's fold is not kept below the threshold") { !title_drawn? }
      assert summary_drawn?, "the summary is not drawn below the threshold"
    end
  end

  test "Page and Section are tabs: arrows move between them, Home and End go to the ends" do
    at_window(WIDE) do
      visit_editor(@page)
      assert_docked
      assert_selector "#{PAGE_TAB}[aria-selected=true][tabindex='0']"
      assert_selector "#{SECTION_TAB}[aria-selected=false][tabindex='-1']"

      page.execute_script("document.querySelector(#{PAGE_TAB.to_json}).focus()")
      keyboard.type(:right)
      assert_selector "#{SECTION_TAB}[aria-selected=true][tabindex='0']"
      assert focus_is_on(SECTION_TAB)
      assert_selector "#editor-grid-panel-section", visible: :visible, text: "Choose a section"
      assert_selector "#page-settings", visible: :hidden

      keyboard.type(:right)
      assert_selector "#{PAGE_TAB}[aria-selected=true]"
      assert focus_is_on(PAGE_TAB)

      keyboard.type(:end)
      assert_selector "#{SECTION_TAB}[aria-selected=true]"
      assert focus_is_on(SECTION_TAB)

      keyboard.type(:home)
      assert_selector "#{PAGE_TAB}[aria-selected=true]"
      assert focus_is_on(PAGE_TAB)
      assert_selector "#page-settings", visible: :visible
    end
  end

  test "closing the Section panel's settings returns to the tab the person last left by hand" do
    at_window(WIDE) do
      visit_editor(@page)
      assert_docked

      find(SECTION_TAB).click
      assert_selector "#{SECTION_TAB}[aria-selected=true]"
      find(PAGE_TAB).click
      assert_selector "#{PAGE_TAB}[aria-selected=true]"

      find("#section-#{@section.id}-words button[data-admin--editor--section-field-param='width']").click
      assert_selector "#editor-grid-panel-section #section-#{@section.id}-settings", visible: :visible
      assert_selector "#{SECTION_TAB}[aria-selected=true]"

      find("#section-#{@section.id}-settings button[data-action='admin--editor--section-settings#close']").click
      assert_selector "#{PAGE_TAB}[aria-selected=true]"
      assert_selector "#page-settings", visible: :visible
    end
  end

  test "a current that names no tab still leaves one tab in the tab order and one panel current" do
    at_window(WIDE) do
      visit_editor(@page)
      assert_docked

      # As the server would draw it with a current naming no tab: no panel
      # current, no tab selected, and the rail connected afresh on it.
      page.execute_script(<<~JS)
        const grid = document.getElementById("editor-grid")
        grid.dataset.controller = "admin--editor--section-choice"
        grid.querySelectorAll("[role=tabpanel]").forEach((panel) => panel.removeAttribute("data-current"))
        grid.querySelectorAll("[role=tab]").forEach((tab) => { tab.setAttribute("aria-selected", "false"); tab.tabIndex = -1 })
        grid.setAttribute("data-admin--ui--rail-current-value", "nope")
      JS
      await_frames
      page.execute_script("document.getElementById('editor-grid').dataset.controller = 'admin--ui--rail admin--editor--section-choice'")

      assert_selector "#editor-grid [role=tab][tabindex='0']", count: 1
      assert_selector "#{PAGE_TAB}[aria-selected=true][tabindex='0']"
      assert_selector "#editor-grid [role=tabpanel][data-current]", count: 1, visible: :all
      assert_selector "#page-settings", visible: :visible
    end
  end
end
