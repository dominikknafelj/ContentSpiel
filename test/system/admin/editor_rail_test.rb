require "application_system_test_case"

# The editors' rail (`admin/pages/show` and `Admin::EditorScreen::PostFormComponent`,
# `.admin-rail-grid`, `admin--ui--rail`): where the editor area has 1200px, the
# page settings stand in a 360px rail 28px right of a blocks column that takes
# the rest, up to 1680px for the whole (`--cs-content-max`, centred past it), with
# a Page and a Section tab, and a post's settings in the same rail beside its
# title, address and body, under the one heading Post; below that the page
# settings stand above the blocks and a post's settings below its main
# column, at 760px, as one column. The editor area is the container, so a
# folded tree docks the rail at a window that would not otherwise. Each rule that overrides a base rule
# while docked (the grown column over 760px, the forced-open settings over a
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
    page.execute_script("try { window.localStorage.removeItem('cs-tree-folded'); window.localStorage.removeItem('cs-tree-width'); window.localStorage.removeItem('cs-notes-open') } catch (error) {}")
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

  test "at a wide window the rail stands right of a blocks column that takes the rest, left-aligned, 28px apart" do
    at_window(WIDE) do
      visit_editor(@page)
      assert_docked

      area = box("#editing")
      blocks = box(".admin-content-blocks")
      rail = box("#editor-grid-panel-page")
      assert_in_delta area[0], blocks[0], 1, "the blocks column starts at the content's left edge"
      assert_in_delta blocks[2] + 28, rail[0], 1, "the rail stands 28px right of the blocks"
      assert_in_delta 360, rail[2] - rail[0], 1
      assert_operator area[2] - area[0], :<, 1680, "the window leaves the editor less than the content max"
      assert_in_delta area[2], rail[2], 1, "the blocks column takes what the rail leaves"
      assert_in_delta blocks[1], box(".admin-rail__tabs")[1], 1, "the rail's tabs and the blocks start at one height"
      # Page and Section, then the registered Notes tab (`editor.rail.tabs`).
      assert_equal %w[editor-grid-tab-page editor-grid-tab-section editor-grid-tab-notes], all("#editor-grid [role=tablist] [role=tab]").map { |tab| tab[:id] }
    end
  end

  # The figures of the one rule for spare width. The page editor with the
  # tree folded: the
  # editor area is the window less the sidebar (240), the strip (44), the
  # scrollbar's gutter and `<main>`'s padding (48), so a window of 1600px of
  # content is 1600 + 347 wide. Running text keeps its measure (72ch, about
  # 650px in Archivo at 16px), the Code field the code measure (100ch), and
  # an image field and a table take the column.
  def content_window(content) = content + 240 + 44 + 48 + page.evaluate_script("Math.round(window.innerWidth - document.documentElement.getBoundingClientRect().width)")

  def wide_blocks
    @text = @page.content_blocks.create!(block_type: "rich_text", position: 1)
    @code = @page.content_blocks.create!(block_type: "code", position: 2)
    @table = @page.content_blocks.create!(block_type: "table", position: 3)
    @image = @page.content_blocks.create!(block_type: "image", position: 4)
  end

  def fold_tree = page.execute_script("window.localStorage.setItem('cs-tree-folded', '1')")

  def in_block(block, selector) = "[data-block-id='#{block.id}'] #{selector}"

  test "at a 1600px content width the blocks column is 1212px, a rich-text box about 650px and a table the column's width" do
    wide_blocks
    visit_editor(@page)
    fold_tree
    at_window(content_window(1600)) do
      visit_editor(@page)
      assert_docked

      area = box("#editing")
      assert_in_delta 1600, area[2] - area[0], 1
      assert_in_delta 1212, width_of(".admin-content-blocks"), 1
      assert_in_delta box(".admin-content-blocks")[2] + 28, box("#editor-grid-panel-page")[0], 1
      assert_in_delta 360, width_of("#editor-grid-panel-page"), 1

      card = box("[data-block-id='#{@text.id}']")
      assert_in_delta 1212, card[2] - card[0], 1, "a block card takes the column"
      text = width_of(in_block(@text, ".admin-rich-text-box"))
      assert_in_delta 650, text, 30, "a rich-text box keeps the text measure"
      assert_in_delta text, width_of(in_block(@text, ".admin-column > p")), 1, "its label takes the same cap"
      code = width_of(in_block(@code, ".admin-code-input"))
      assert_operator code, :>, text + 200, "the Code field is wider than running text"
      assert_operator code, :<, 1000, "and keeps the code measure"
      inner = card[2] - card[0] - 24
      assert_in_delta inner, width_of(in_block(@table, ".admin-rich-text-box")), 2, "a table takes the column"
      assert_in_delta inner, width_of(in_block(@image, "[data-controller~='admin--media--field']")), 2, "an image field takes the column"
      section = box(".admin-section-card")
      assert_in_delta 1212, section[2] - section[0], 1, "a section's frame takes the column"
    end
  end

  test "at a 2400px content width the editor stops at the content max, centred" do
    wide_blocks
    visit_editor(@page)
    fold_tree
    at_window(content_window(2400)) do
      visit_editor(@page)
      assert_docked

      area = box("#editing")
      grid = box("#editor-grid")
      assert_in_delta 2400, area[2] - area[0], 1
      assert_in_delta 1680, grid[2] - grid[0], 1, "the composition stops at the content max"
      assert_in_delta grid[0] - area[0], area[2] - grid[2], 1, "the spare width is split evenly either side"
      row = box(".admin-editor-header > div:first-child")
      assert_in_delta grid[0], row[0], 1, "the header row starts with the composition"
      assert_in_delta grid[2], row[2], 1, "and stops with it, so Publish stands over the rail's right edge"
      assert_operator box(".admin-editor-header")[2] - box(".admin-editor-header")[0], :>, 2400, "the header's own line keeps the window's width"
      assert_in_delta 1292, width_of(".admin-content-blocks"), 1
      assert_in_delta grid[2], box("#editor-grid-panel-page")[2], 1, "the rail ends the composition"
      assert_in_delta 650, width_of(in_block(@text, ".admin-rich-text-box")), 30, "running text keeps its measure"
      assert_in_delta 1292 - 24, width_of(in_block(@table, ".admin-rich-text-box")), 2, "a table takes the column"
    end
  end

  # The docked rail stays in view down a long page. Its ground is
  # the grid's `::before`, measured through its computed height.
  def ground_height = page.evaluate_script("parseFloat(getComputedStyle(document.getElementById('editor-grid'), '::before').height)")

  def header_bottom = box(".admin-editor-header")[3]

  def long_page(count = 30)
    count.times { |index| @page.content_blocks.create!(block_type: "rich_text", position: index + 1) }
  end

  def scroll_to_end = page.execute_script("window.scrollTo(0, document.documentElement.scrollHeight)")

  # Whether the element is drawn where it stands: the point at its centre
  # hits it, or something inside it, and is inside the window.
  def hit?(selector)
    page.evaluate_script(<<~JS)
      (() => {
        const element = document.querySelector(#{selector.to_json})
        const box = element.getBoundingClientRect()
        const x = box.left + box.width / 2, y = box.top + box.height / 2
        if (y < 0 || y > window.innerHeight) return false
        const top = document.elementFromPoint(x, y)
        return element === top || element.contains(top)
      })()
    JS
  end

  test "scrolled to the last block of a long page, the rail's tabs and its panel are in view under the header and its ground is no taller than they are" do
    long_page
    at_window(WIDE) do
      visit_editor(@page)
      assert_docked
      scroll_to_end
      assert_eventually(message: "the page did not scroll") { page.evaluate_script("window.scrollY") > 1000 }

      tabs = box(".admin-rail__tabs")
      panel = box("#editor-grid-panel-page")
      assert_in_delta header_bottom + 24, tabs[1], 1, "the tabs stick under the editor's header, the header's gap below it"
      assert_in_delta tabs[3], panel[1], 1, "the panel sticks under the tabs"
      assert_operator panel[3], :<=, page.evaluate_script("window.innerHeight"), "the panel ends inside the window"
      assert_operator ground_height, :<=, (panel[3] - tabs[1]) + 1, "the ground is no taller than the tabs and the panel"
      assert hit?("#editor-grid-tab-page"), "the Page tab can be pressed down the page"
      assert_operator box(".admin-content-blocks")[3] - box(".admin-content-blocks")[1], :>, ground_height * 2, "the blocks column is far taller than the rail"
    end
  end

  test "a panel taller than the window scrolls inside the rail" do
    at_window(WIDE, height: 520) do
      visit_editor(@page)
      assert_docked
      panel = "#editor-grid-panel-page"
      sizes = page.evaluate_script("(() => { const panel = document.querySelector(#{panel.to_json}); return [panel.scrollHeight, panel.clientHeight] })()")
      assert_operator sizes[0], :>, sizes[1], "the Page panel is taller than the room under the tabs"
      assert_in_delta 520 - 22, box(panel)[3], 1, "before the page scrolls the panel ends --cs-sp-4 above the window's bottom"
      page.execute_script("document.querySelector(#{panel.to_json}).scrollTop = 10000")
      assert_operator page.evaluate_script("document.querySelector(#{panel.to_json}).scrollTop"), :>, 0, "the panel scrolls inside itself"
      assert_equal 0, page.evaluate_script("window.scrollY"), "and the page does not move"
    end
  end

  # A menu inside a panel that scrolls is drawn over what is below it, not
  # cut at the panel's edge: the section's layout menu, opened in the
  # Section panel, whose settings are shorter than the menu.
  def layout_menu(where) = "#{where} [data-controller~='admin--ui--menu']"

  def open_layout_menu(menu)
    find("#section-#{@section.id}-words button[data-admin--editor--section-field-param='layout']").click
    find("#{menu} button[aria-haspopup]").click
    assert_selector "#{menu} [data-admin--ui--menu-target=panel]", visible: :visible
  end

  # The gap between a menu and its button, as the menu's own classes draw it.
  def menu_gap(menu) = box("#{menu} [data-admin--ui--menu-target=panel]")[1] - box("#{menu} button[aria-haspopup]")[3]

  test "a menu in a scrolling rail panel opens whole, over what is below the panel" do
    outside = nil
    at_window(NARROW) do
      visit_editor(@page)
      assert_docked(false)
      open_layout_menu(layout_menu("#section-#{@section.id}-settings"))
      outside = menu_gap(layout_menu("#section-#{@section.id}-settings"))
    end
    at_window(WIDE, height: 600) do
      visit_editor(@page)
      assert_docked
      menu = layout_menu("#editor-grid-panel-section")
      open_layout_menu(menu)
      items = "#{menu} [data-admin--ui--menu-target=panel] [role=menuitem]"
      assert_operator box(items.sub("[role=menuitem]", ""))[3], :>, box("#editor-grid-panel-section")[3], "the menu reaches past the panel's bottom"
      page.execute_script("document.querySelectorAll(#{items.to_json}).forEach((item, index, all) => { if (index === all.length - 1) item.id = 'last-layout' })")
      assert hit?("#last-layout"), "the menu's last item is drawn over what is below the panel"
      menu_box = box("#{menu} [data-admin--ui--menu-target=panel]")
      button_box = box("#{menu} button[aria-haspopup]")
      assert_in_delta outside, menu_box[1] - button_box[3], 1, "the menu hangs as far under its button as it does outside a panel"
      assert_in_delta button_box[0], menu_box[0], 1, "at its button's left edge"
      page.execute_script("document.querySelector('#editor-grid-panel-section').scrollTop = 30")
      assert_in_delta outside, menu_gap(menu), 1, "and follows it as the panel scrolls"
      find("#{menu} button[aria-haspopup]").click
      assert_no_selector "#{menu} [data-admin--ui--menu-target=panel]", visible: :visible
      assert_equal "", page.evaluate_script("document.querySelector(#{(menu + " [data-admin--ui--menu-target=panel]").to_json}).style.position"), "closed, the menu is the absolute box its classes draw"
    end
  end

  # A window so short that the Section panel scrolls, and that the layout
  # menu has no room under its button: it hangs above it.
  test "a floated menu closes when its anchor scrolls out of the panel" do
    at_window(WIDE, height: 360) do
      visit_editor(@page)
      assert_docked
      panel = "#editor-grid-panel-section"
      menu = layout_menu(panel)
      open_layout_menu(menu)
      assert page.evaluate_script("document.querySelector(#{(menu + " [data-admin--ui--menu-target=panel]").to_json}).contains(document.activeElement)"), "the focus is in the menu"
      assert_in_delta box(menu)[1] - 4, box("#{menu} [data-admin--ui--menu-target=panel]")[3], 1, "with no room below, the menu hangs above it, its own margin away"
      assert_operator page.evaluate_script("(() => { const p = document.querySelector('#{panel}'); return p.scrollHeight - p.clientHeight })()"), :>, 40, "the Section panel scrolls"
      page.execute_script("document.querySelector('#{panel}').scrollTop = 10000")
      assert_no_selector "#{menu} [data-admin--ui--menu-target=panel]", visible: :visible
      assert_equal "false", find("#{menu} button[aria-haspopup]", visible: :all)["aria-expanded"]
      assert page.evaluate_script("document.activeElement === document.querySelector(#{(menu + " button[aria-haspopup]").to_json})"), "the focus is back on the menu's button"
      assert_equal "", page.evaluate_script("document.querySelector(#{(menu + " [data-admin--ui--menu-target=panel]").to_json}).style.position")
    end
  end

  # A tall window, so the Post panel is shorter than the room it may take
  # and its last field, Related posts, stands near its bottom edge, with the
  # window below.
  test "the related posts' suggestions in a scrolling post panel open whole" do
    %w[Alpha Beta Gamma Delta Epsilon].each { |name| create_post(title: "Linked #{name}") }
    at_window(WIDE, height: 1400) do
      open_post
      assert_docked
      assert_equal "auto", page.evaluate_script("getComputedStyle(document.querySelector('#{POST_PANEL}')).overflowY")
      field = find("#post-related_post_ids")
      field.send_keys("Linked")
      listbox = "#post-related_post_ids-listbox"
      assert_selector "#{listbox} [role=option]", minimum: 5
      assert_operator box(listbox)[3], :>, box(POST_PANEL)[3], "the suggestions reach past the panel's bottom"
      assert_operator box(listbox)[3], :<, 1400, "and stay inside the window"
      page.execute_script("document.querySelectorAll('#{listbox} [role=option]').forEach((option, index, all) => { if (index === all.length - 1) option.id = 'last-suggestion' })")
      assert hit?("#last-suggestion"), "the last suggestion is drawn over what is below the panel"
      wrapper = page.evaluate_script("(() => { const box = document.querySelector('#{listbox}').parentElement.getBoundingClientRect(); return [box.left, box.bottom, box.width] })()")
      assert_in_delta wrapper[0], box(listbox)[0], 1, "under the field, at its left edge"
      assert_in_delta wrapper[2], box(listbox)[2] - box(listbox)[0], 1, "as wide as the field"
      field.send_keys(:escape)
      assert_no_selector listbox, visible: :visible
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
      # The room left of a 360px rail.
      assert_operator width_of(".admin-content-blocks"), :>, 760
      assert_in_delta box("#editing")[2], box("#editor-grid-panel-page")[2], 1, "the rail ends at the editor's right edge"
      assert_in_delta 360, width_of("#editor-grid-panel-page"), 1
      assert_in_delta box(".admin-content-blocks")[2] + 28, box("#editor-grid-panel-page")[0], 1

      find("button[aria-label='Show page tree']").click
      assert_docked(false)
      assert_in_delta 760, width_of(".admin-content-blocks"), 1
    end
  end

  test "a translation tab docks the rail at 1200px of the editor" do
    with_locales(%w[en de], default: "en")
    visit_editor(@page)
    fold_tree
    at_window(content_window(1199)) do
      visit_editor(@page, locale: "de")
      await_frames
      assert_docked(false)
      assert_no_selector "#editor-grid [role=tablist]"
      assert_operator box("#page-settings")[3], :<, box(".admin-content-blocks")[1]
    end
    at_window(content_window(1200)) do
      visit_editor(@page, locale: "de")
      assert_docked
      assert_in_delta 1200, width_of("#editing"), 1
      assert_in_delta 812, width_of(".admin-content-blocks"), 1
      assert_in_delta 360, width_of("#editor-grid-panel-page"), 1
      assert_in_delta box(".admin-content-blocks")[2] + 28, box("#editor-grid-panel-page")[0], 1
      # A translation tab draws no section's settings, so it has no Section tab.
      assert_equal %w[editor-grid-tab-page editor-grid-tab-notes], all("#editor-grid [role=tablist] [role=tab]").map { |tab| tab[:id] }
    end
  end

  # The Page tab is the settings form's translated fields, each a pair: in
  # the 360px rail the pair stacks, the original first, its Translate box
  # under the field.
  test "on a translation tab the Page tab holds the settings' pairs, the original first" do
    with_locales(%w[en de], default: "en")
    Mobility.with_locale(:en) { @page.update!(subtitle: "Plans for every team") }
    at_window(WIDE) do
      visit_editor(@page, locale: "de")
      assert_docked
      panel = "#editor-grid-panel-page"
      assert_selector "#{panel} #page-settings form.admin-translation-form"
      %w[title subtitle].each do |name|
        original = box("#{panel} [data-original-for='#{name}']")
        field = box("#{panel} [data-field-name='#{name}'] .admin-translation-pair > div:first-child")
        assert_operator original[3], :<=, field[1] + 1, "#{name}: the original stands above the field"
        assert_in_delta original[0], field[0], 1, "#{name}: one column"
      end
      assert_selector "#{panel} [data-original-for='title'] details[open]"
      assert_operator box("#{panel} [data-field-name='title'] [data-translate-slot]")[1], :>=, box("#{panel} [data-field-name='title'] .admin-translation-pair > div:first-child input")[3], "the Translate box stands under the field"
    end
  end

  # A docked post's form is `display: contents`, so no pair container: the
  # Post tab's pairs stack in the rail, and the main column's sit side by
  # side from 1212px of the editor (824px of the column). Typing saves, and
  # the save's answer leaves both columns drawn.
  test "on a translation tab a post's pairs stack in the rail and sit side by side in the main column, and a save keeps both drawn" do
    with_locales(%w[en de], default: "en")
    @post = create_post(title: "Notes", published: false)
    Mobility.with_locale(:en) { @post.update!(excerpt: "A short summary") }
    at_window(WIDE) do
      visit_editor(@post, locale: "de")
      assert_docked
      assert_operator width_of("#editing"), :>=, 1212, "the premise: the main column is 824px or more"

      excerpt_original = box("#{POST_PANEL} [data-original-for='excerpt']")
      excerpt_field = box("#{POST_PANEL} [data-field-name='excerpt'] .admin-translation-pair > div:first-child")
      assert_operator excerpt_original[3], :<=, excerpt_field[1] + 1, "in the rail the original stands above the field"
      title_original = box("#{POST_MAIN} [data-original-for='title']")
      title_field = box("#{POST_MAIN} [data-field-name='title'] .admin-translation-pair > div:first-child")
      assert_in_delta title_field[1], title_original[1], 4, "in the main column the field and its original share a row"
      assert_operator title_field[2], :<, title_original[0], "the field on the left"

      find("#post-excerpt").send_keys("Kurz")
      assert_writes_settled
      assert_eventually(message: "the excerpt was not saved") { Mobility.with_locale(:de) { @post.reload.excerpt } == "Kurz" }
      assert_operator box("#post-title")[3] - box("#post-title")[1], :>, 20, "the main column is still drawn after the save's answer"
      assert_operator box("#post-excerpt")[3] - box("#post-excerpt")[1], :>, 20, "the rail is still drawn after the save's answer"
    end
    at_window(content_window(1211) - 44) do
      visit_editor(@post, locale: "de")
      assert_docked
      assert_in_delta 1211, width_of("#editing"), 1
      title_original = box("#{POST_MAIN} [data-original-for='title']")
      title_field = box("#{POST_MAIN} [data-field-name='title'] .admin-translation-pair > div:first-child")
      assert_operator title_original[3], :<=, title_field[1] + 1, "below 1212px of the editor the main column's pair stacks"
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

  NOTES_TAB = "#editor-grid-tab-notes".freeze

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

      # The Notes tab is the last of them, and Right from it goes round to Page.
      keyboard.type(:right)
      assert_selector "#{NOTES_TAB}[aria-selected=true]"
      assert focus_is_on(NOTES_TAB)
      keyboard.type(:right)
      assert_selector "#{PAGE_TAB}[aria-selected=true]"
      assert focus_is_on(PAGE_TAB)

      keyboard.type(:end)
      assert_selector "#{NOTES_TAB}[aria-selected=true]"
      assert focus_is_on(NOTES_TAB)

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

  # The post editor. Its settings panel and its main column are both inside
  # `form#post-form`, which is `display: contents` while docked.
  POST_PANEL = "#editor-grid-panel-post".freeze
  POST_MAIN = ".admin-post-main".freeze

  def open_post(**options)
    @post = create_post(title: "Notes", published: false, **options)
    visit_editor(@post)
  end

  # Which column each `input` and `change` that reaches `form#post-form` came
  # from: "rail", "main" or "other", in order.
  def listen_to_post_form
    page.execute_script(<<~JS)
      window.__formEvents = []
      const form = document.getElementById("post-form")
      const where = (target) => target.closest(#{POST_PANEL.to_json}) ? "rail" : (target.closest(#{POST_MAIN.to_json}) ? "main" : "other")
      for (const type of [ "input", "change" ]) form.addEventListener(type, (event) => window.__formEvents.push(where(event.target)))
    JS
  end

  def form_events = page.evaluate_script("window.__formEvents")

  def post_body_text = @post.reload.body_document(locale: "en").to_h.to_json

  # The post form's node in Chrome's accessibility tree: `[role, ignored]`.
  def post_form_ax
    browser = page.driver.browser.page
    root = browser.command("DOM.getDocument", depth: 0).dig("root", "nodeId")
    form = browser.command("DOM.querySelector", nodeId: root, selector: "#post-form")["nodeId"]
    node = browser.command("Accessibility.getPartialAXTree", nodeId: form, fetchRelatives: false)["nodes"].first
    [ node.dig("role", "value"), node["ignored"] ]
  end

  test "a post's settings stand in the rail at a wide window, and the post form is still one form" do
    at_window(WIDE) do
      open_post
      assert_docked

      assert_selector "form#post-form", count: 1
      assert_selector "#editor-grid [data-controller~='admin--saving--autosave']", count: 1
      assert_selector "#post-form[data-controller~='admin--saving--autosave'][data-editing-unit][data-editing-subject=record]"
      assert_selector "#post-form #{POST_PANEL} #post-tag_names"
      assert_selector "#post-form #{POST_MAIN} [data-field-name='body'] .ProseMirror"
      assert_selector "#post-form input[name='base_updated_at']", count: 1, visible: :all
      assert_equal "contents", page.evaluate_script("getComputedStyle(document.getElementById('post-form')).display")
      assert_equal [ "form", false ], post_form_ax, "the form keeps its role while it generates no box"
      assert_selector "#editor-grid [role=tablist] #editor-grid-tab-post[role=tab]", text: "Post"

      area = box("#editing")
      main = box(POST_MAIN)
      rail = box(POST_PANEL)
      assert_in_delta area[0], main[0], 1, "the main column starts at the content's left edge"
      assert_in_delta main[2] + 28, rail[0], 1, "the rail stands 28px right of the main column"
      assert_in_delta 360, rail[2] - rail[0], 1
      assert_in_delta area[2], rail[2], 1, "the main column takes what the rail leaves"
      assert_in_delta main[1], box(".admin-rail__tabs")[1], 1, "the rail's tabs and the main column start at one height"

      listen_to_post_form
      find("#post-tag_names").send_keys("alpha", :enter)
      assert_selector "#post-form li[data-chip-value='alpha']"
      assert_writes_settled
      assert_eventually(message: "the tag added in the rail was not saved") { @post.reload.tags.map(&:name) == [ "alpha" ] }

      find("#{POST_MAIN} [data-field-name='body'] .ProseMirror").click
      find("#{POST_MAIN} [data-field-name='body'] .ProseMirror").send_keys("Body text")
      assert_writes_settled
      assert_eventually(message: "the body edit was not saved") { post_body_text.include?("Body text") }

      assert_includes form_events, "rail", "no input from the rail reached the form"
      assert_includes form_events, "main", "no input from the main column reached the form"
      assert_no_selector "[data-save-state=paused]"
      assert_no_text "Changed elsewhere"
    end
  end

  # Where the focus goes from the last language tab, Tab by Tab, until it
  # has been in the post's settings: "header", "main", "settings" or "other",
  # each once in a row.
  def post_focus_path
    page.execute_script("[ ...document.querySelectorAll('.admin-language-tabs a[href]') ].pop().focus()")
    seen = []
    80.times do
      keyboard.type(:tab)
      where = page.evaluate_script(<<~JS)
        (() => {
          const active = document.activeElement
          if (active.closest(".admin-editor-header")) return "header"
          if (active.closest(#{POST_PANEL.to_json})) return "settings"
          if (active.closest(#{POST_MAIN.to_json})) return "main"
          return "other"
        })()
      JS
      seen << where unless seen.last == where
      break if where == "settings"
    end
    seen.drop_while { |where| where == "header" }
  end

  test "below the threshold a post reads title, address, body, then its settings" do
    at_window(NARROW) do
      open_post
      assert_docked(false)

      assert_equal true, page.evaluate_script("Boolean(document.querySelector(#{POST_MAIN.to_json}).compareDocumentPosition(document.querySelector(#{POST_PANEL.to_json})) & Node.DOCUMENT_POSITION_FOLLOWING)"),
        "the main column comes before the settings in the document"
      form = box("#post-form")
      assert_in_delta 760, form[2] - form[0], 1
      assert_operator box(POST_MAIN)[3], :<=, box(POST_PANEL)[1], "the main column stands above the settings"
      assert_operator box("#post-title")[1], :<, box("#post-slug")[1]
      assert_operator box("#post-slug")[1], :<, box("#{POST_MAIN} [data-field-name='body']")[1]
      assert_no_selector "#editor-grid-tab-post", visible: :visible
      assert_not_equal "contents", page.evaluate_script("getComputedStyle(document.getElementById('post-form')).display")

      path = post_focus_path
      assert_equal %w[main settings], path, "the focus went #{path.inspect}"
    end
  end

  test "at a wide window the focus goes from a post's main column to its settings in the rail" do
    at_window(WIDE) do
      open_post
      assert_docked

      path = post_focus_path
      assert_equal %w[main settings], path, "the focus went #{path.inspect}"
    end
  end

  # The post rail's other tab, the Notes tab (`editor.rail.tabs`), outside the
  # post form; chosen, so the Post panel is not current.
  def choose_the_notes_tab
    find("#editor-grid-tab-notes").click
    assert_selector "#editor-grid-panel-notes[data-current] #notes-list"
    assert_selector POST_PANEL, visible: :hidden
  end

  def colleague_saves_excerpt(text)
    as(users(:two), channel: :admin) { assert Posts::Save.call(@post.reload, translations: { "en" => { excerpt: text } }).ok? }
  end

  test "a post form replaced by a live merge keeps the tab that was current" do
    at_window(WIDE) do
      open_post
      await_notes_live
      assert_docked
      choose_the_notes_tab
      page.execute_script("document.getElementById('post-form').dataset.probe = 'old'")
      listen_merged

      colleague_saves_excerpt("A colleague's excerpt")
      await_js("window.__merged.includes('record')", wait: 8)
      assert_eventually(message: "the form was not replaced") { page.evaluate_script("document.getElementById('post-form').dataset.probe") != "old" }
      assert_equal "A colleague's excerpt", find_field(id: "post-excerpt", visible: :all).value

      assert_selector "#editor-grid [role=tabpanel][data-current]", count: 1, visible: :all
      assert_selector "#editor-grid-panel-notes[data-current]"
      assert_selector "#editor-grid-tab-notes[aria-selected=true]"
      assert_selector "#{POST_PANEL}:not([data-current])", visible: :hidden
    end
  end

  # An edit in each column that no timer will send: the form holds unsaved text.
  def type_unsent_in_both_columns
    page.execute_script("const a = window.Stimulus.getControllerForElementAndIdentifier(document.getElementById('post-form'), 'admin--saving--autosave'); a.saveNow = () => {}")
    find("#post-excerpt").send_keys("Mine in the rail")
    find("#post-title").send_keys(" mine")
    page.execute_script("const a = window.Stimulus.getControllerForElementAndIdentifier(document.getElementById('post-form'), 'admin--saving--autosave'); clearTimeout(a.timer); a.timer = null")
    assert_equal false, page.evaluate_script("Stimulus.getControllerForElementAndIdentifier(document.getElementById('post-form'), 'admin--saving--autosave').unchanged()"), "the form should hold an unsent edit"
  end

  test "a live merge keeps a post form that holds unsaved text in either column, with the text and the current tab" do
    at_window(WIDE) do
      open_post
      await_notes_live
      assert_docked
      page.execute_script("window.__form = document.getElementById('post-form')")
      type_unsent_in_both_columns
      listen_merged

      as(users(:two), channel: :admin) { assert Posts::Save.call(@post.reload, attributes: { tag_names: [ "theirs" ] }).ok? }
      await_js("window.__merged.includes('record')", wait: 8)
      await_frames

      assert_equal true, page.evaluate_script("window.__form === document.getElementById('post-form')"), "the form with unsaved text was replaced"
      assert_equal "Mine in the rail", find_field(id: "post-excerpt").value
      assert_equal "Notes mine", find_field(id: "post-title").value
      assert_selector "#{POST_PANEL}[data-current]"
    end
  end

  # The body's Link popover, with its search answering, hangs past the canvas
  # over the settings that follow it below the threshold, on either tab:
  # each of its rows that stands over the
  # Excerpt field is the topmost element at its centre, so it is drawn over
  # the field and a click on it reaches it.
  def assert_link_popover_over_the_post_settings
    5.times { |index| create_page(title: "About #{index}", translations: { de: { title: "About #{index}" }, es: { title: "About #{index}" } }) }
    find("#{POST_MAIN} .ProseMirror[contenteditable=true]").click
    keyboard.type("see this")
    page.execute_script("document.execCommand('selectAll')")
    within(POST_MAIN) { press "Link" }
    within("#{POST_MAIN} .admin-rich-text-popover") do
      fill_in "URL or search", with: "abo"
      assert_selector "[role=option]", count: 5
    end
    covered = page.evaluate_script(<<~JS)
      (() => {
        const popover = document.querySelector(#{"#{POST_MAIN} .admin-rich-text-popover".to_json})
        const excerpt = document.getElementById("post-excerpt").getBoundingClientRect()
        const rows = Array.from(popover.querySelectorAll("[role=option], button"))
          .filter((row) => { const box = row.getBoundingClientRect(); return box.top > excerpt.top && box.bottom < excerpt.bottom })
        if (rows.length === 0) return "no row stands over the Excerpt field"
        return rows.filter((row) => {
          const box = row.getBoundingClientRect()
          const hit = document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2)
          return !(row === hit || row.contains(hit))
        }).map((row) => row.textContent.trim())
      })()
    JS
    assert_equal [], covered, "the Link popover's rows are drawn under the post settings"
  end

  test "below the threshold the body's Link popover stands over the post settings that follow it" do
    at_window(1100) do
      open_post
      assert_docked(false)
      assert_link_popover_over_the_post_settings
    end
  end

  test "below the threshold on a translation tab the body's Link popover stands over the post settings that follow it" do
    at_window(1100) do
      @post = create_post(title: "Notes", published: false)
      visit_editor(@post, locale: "de")
      assert_docked(false)
      assert_link_popover_over_the_post_settings
    end
  end
end
