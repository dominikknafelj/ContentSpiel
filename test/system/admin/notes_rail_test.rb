require "application_system_test_case"

# The editors' notes as the rail's Notes tab (`editor.rail.tabs`,
# `Admin::NotesScreen::RailPanelComponent`, `admin--notes--drawer` on the
# rail's events): at 1900px the rail docks and the notes are its Notes tab;
# at 1100px they are a 400px slide-over over the canvas; at 600px a
# full-screen sheet with a way back. One element at every width, so a note
# being typed keeps its text and its focus across all of it. Only a browser
# can show any of this: the assertions compare boxes and computed styles.
class Admin::NotesRailSystemTest < ApplicationSystemTestCase
  WIDE = 1900
  MID = 1100
  PHONE = 600

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @page = create_page(title: "Pricing", published: false)
    @block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: rich_doc("Hello **there**") } }).record
  end

  # "Open" is remembered in this browser, and the browser is shared with the
  # tests that follow: every notes system test forgets it again.
  teardown { page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}") }

  NOTES_TAB = "#editor-grid-tab-notes".freeze
  NOTES_PANEL = "#editor-grid-panel-notes".freeze
  PAGE_TAB = "#editor-grid-tab-page".freeze
  SECTION_TAB = "#editor-grid-tab-section".freeze

  def open_editor(query = "")
    visit "/cs-studio/pages/#{@page.id}#{query}"
    await_admin_controllers
  end

  # `[left, top, right, bottom]` of the first element the selector finds.
  def box(selector)
    page.evaluate_script("(() => { const box = document.querySelector(#{selector.to_json}).getBoundingClientRect(); return [ box.left, box.top, box.right, box.bottom ] })()")
  end

  def docked? = page.evaluate_script("document.getElementById('editor-grid').hasAttribute('data-rail-docked')")

  def assert_docked(docked = true)
    assert_eventually(message: "the rail is #{docked ? "not " : ""}docked") { docked? == docked }
  end

  def keyboard = page.driver.browser.keyboard

  def active_id = page.evaluate_script("document.activeElement.id")

  def focus_in_notes? = page.evaluate_script("document.activeElement.closest('#notes-drawer') !== null")

  def computed(selector, property) = page.evaluate_script("getComputedStyle(document.querySelector(#{selector.to_json})).#{property}")

  # The window less the scrollbar's gutter, which CS Studio keeps.
  def room = page.evaluate_script("document.documentElement.getBoundingClientRect().width").round

  # Pressed, and the slide-over's slide in (200ms) run out, so its box is
  # where it stays.
  def open_notes
    find("#notes-open").click
    assert_selector "#notes-drawer #notes-list"
    await_js("document.getElementById('notes-drawer').getAnimations().length === 0", message: "the notes are still sliding in")
  end

  # Where the blocks column stands, and how tall it is: docked it starts at
  # the grid's top and is as tall as its own content (`align-self: start`),
  # so a taller rail does not stretch it.
  def blocks_place = box(".admin-content-blocks").map(&:round)

  def assert_notes_tab_current
    assert_selector "#{NOTES_TAB}[aria-selected=true]"
    assert_selector "#{NOTES_PANEL}[data-current]"
  end

  [ WIDE, MID ].each do |width|
    test "at #{width}px the header's Notes button opens the Notes tab and nothing else on the page moves" do
      at_window(width) do
        open_editor
        assert_docked(width == WIDE)
        blocks = box(".admin-content-blocks")
        place = blocks_place

        open_notes

        assert_selector "#{NOTES_PANEL}[data-current]"
        assert_selector "#notes-open[aria-pressed=true][aria-expanded=true]"
        assert_eventually(message: "the focus never moved into the notes") { focus_in_notes? }
        assert_equal place, blocks_place, "the blocks column moved"
        if width == WIDE
          assert_selector "#{NOTES_TAB}[aria-selected=true]"
          assert_operator box("#notes-drawer")[0], :>=, blocks[2] + 27, "the notes stand in the rail, right of the blocks"
        end
      end
    end
  end

  test "a block's marker opens the Notes tab at that block's group" do
    as(users(:two)) { Notes::Start.call(@block, body: "Is this right?") }
    at_window(WIDE) do
      open_editor
      assert_docked

      find("#notes-marker-ContentBlock-#{@block.id}").click

      assert_notes_tab_current
      assert_selector "#notes-drawer [data-notes-group='ContentBlock-#{@block.id}']", text: "Is this right?"
      assert_eventually(message: "the focus is not at the block's group") do
        page.evaluate_script("document.activeElement.matches(\"[data-notes-group='ContentBlock-#{@block.id}']\")")
      end
    end
  end

  # The rail's own rule (`admin--ui--rail#conceal`): back to the tab the
  # person last left, not to the first tab.
  test "closing the notes returns to the tab that was current" do
    at_window(WIDE) do
      open_editor
      assert_docked
      find(SECTION_TAB).click
      assert_selector "#{SECTION_TAB}[aria-selected=true]"

      open_notes
      assert_notes_tab_current
      find("#notes-drawer button[aria-label='Close']").click

      assert_selector "#{SECTION_TAB}[aria-selected=true]"
      assert_selector "#editor-grid-panel-section[data-current]"
      assert_no_selector "#notes-drawer"
      assert_equal "notes-open", active_id
      assert_selector "#notes-open[aria-pressed=false]"
    end
  end

  test "Notes is a tab among the rail's own: arrows reach it" do
    at_window(WIDE) do
      open_editor
      assert_docked
      find(PAGE_TAB).execute_script("this.focus()")

      keyboard.type(:right)
      keyboard.type(:right)

      assert_equal "editor-grid-tab-notes", active_id
      assert_notes_tab_current
      # Chosen by a key, the notes load as for a press of the tab, and the
      # focus stays on the tab.
      assert_selector "#notes-drawer #notes-list"
      assert_equal "editor-grid-tab-notes", active_id
      assert_current_path "/cs-studio/pages/#{@page.id}?notes=open"

      keyboard.type(:home)
      assert_equal "editor-grid-tab-page", active_id
      assert_selector "#editor-grid-panel-page[data-current]"
      assert_no_selector "#notes-drawer"
      assert_current_path "/cs-studio/pages/#{@page.id}"
      keyboard.type(:end)
      assert_equal "editor-grid-tab-notes", active_id
      assert_notes_tab_current
    end
  end

  # The cascade: the slide-over is the base rule, and the rail's container
  # query makes the same element the Notes tab's content where it docks.
  test "below the threshold the notes are a 400px panel over the canvas at elevation 3, not modal" do
    5.times { |n| ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }, translations: { "en" => { body: rich_doc("Block #{n}") } }) }
    at_window(MID) do
      open_editor
      assert_docked(false)
      place = blocks_place
      header = box(".admin-editor-header")

      open_notes

      drawer = box("#notes-drawer")
      assert_equal [ room - 400, room ], [ drawer[0], drawer[2] ].map(&:round), "the panel is the window's last 400px"
      assert_in_delta header[3], drawer[1], 1, "it starts under the editor's header"
      assert_in_delta 900, drawer[3], 1, "and reaches the window's bottom edge"
      assert_equal "fixed", computed("#notes-drawer", "position")
      page.execute_script("const probe = document.createElement('div'); probe.id = 'shadow-probe'; probe.style.boxShadow = 'var(--cs-shadow-3)'; document.body.append(probe)")
      assert_equal computed("#shadow-probe", "boxShadow"), computed("#notes-drawer", "boxShadow")
      page.execute_script("const probe = document.createElement('div'); probe.id = 'ground-probe'; probe.style.background = 'var(--cs-popover)'; document.body.append(probe)")
      assert_equal computed("#ground-probe", "backgroundColor"), computed("#notes-drawer", "backgroundColor")
      assert_equal 0, page.evaluate_script("document.querySelectorAll('[inert]').length"), "nothing is made inert"
      assert_no_selector ".admin-shell__scrim"
      assert_equal place, blocks_place, "the blocks column moved"
      # The page scrolls under it.
      page.execute_script("window.scrollTo(0, 300)")
      assert_eventually(message: "the page did not scroll under the notes") { page.evaluate_script("window.scrollY") > 0 }
      assert_equal drawer.map(&:round), box("#notes-drawer").map(&:round), "the panel scrolled with the page"
    end

    page.execute_script("window.localStorage.removeItem('cs-notes-open')")
    at_window(WIDE) do
      open_editor
      assert_docked
      open_notes
      assert_equal "sticky", computed(NOTES_PANEL, "position"), "docked, the notes stick with their panel"
      assert_equal "static", computed("#notes-drawer", "position")
      assert_equal "none", computed("#notes-drawer", "boxShadow")
      rail = box(NOTES_PANEL)
      drawer = box("#notes-drawer")
      assert_in_delta rail[0], drawer[0], 1
      assert_in_delta rail[2], drawer[2], 1, "docked, the notes are the panel's width"
    end
  end

  # Whether a press at the middle of the element reaches it.
  def pressable?(selector)
    page.evaluate_script(<<~JS)
      (() => {
        const element = document.querySelector(#{selector.to_json})
        const box = element.getBoundingClientRect()
        const hit = document.elementFromPoint((box.left + box.right) / 2, (box.top + box.bottom) / 2)
        return Boolean(hit) && (hit === element || element.contains(hit))
      })()
    JS
  end

  # The slide-over starts under the editor's header, so the header's actions
  # stay in reach: the Notes button closes what it opened. A translation tab
  # never docks the rail, so there it is the slide-over at a wide window too.
  { "at #{MID}px" => [ MID, "" ], "on a translation tab at #{WIDE}px" => [ WIDE, "?locale=de" ] }.each do |where, (width, query)|
    test "#{where} the header's Publish and Notes stay pressable while the slide-over is open, and Notes closes it" do
      with_locales(%w[en de], default: "en")
      at_window(width) do
        open_editor(query)
        assert_docked(false)
        open_notes

        assert pressable?("#notes-open"), "the slide-over covers the header's Notes button"
        publish = within(".admin-editor-header") { find_button("Publish", match: :first) }
        assert page.evaluate_script(<<~JS, publish), "the slide-over covers Publish"
          (() => {
            const button = arguments[0]
            const box = button.getBoundingClientRect()
            const hit = document.elementFromPoint((box.left + box.right) / 2, (box.top + box.bottom) / 2)
            return hit === button || button.contains(hit)
          })()
        JS

        find("#notes-open").click
        assert_no_selector "#notes-drawer"
        assert_equal "notes-open", active_id
      end
    end
  end

  # The header's ⋯ menu drops from the header's right end into the
  # slide-over's place. The header paints above the slide-over, so its menu
  # is over the notes and its items can be pressed.
  { "at #{MID}px" => [ MID, "" ], "on a translation tab at #{WIDE}px" => [ WIDE, "?locale=de" ] }.each do |where, (width, query)|
    test "#{where} the header's ⋯ menu opens above the slide-over" do
      with_locales(%w[en de], default: "en")
      at_window(width) do
        open_editor(query)
        assert_docked(false)
        open_notes

        within(".admin-editor-header") { find("button[aria-label='More actions']").click }
        assert_selector ".admin-editor-header [role=menu]", visible: :visible
        # The rows a record offers depend on its state; four more stand for a
        # record that offers more, so the menu reaches below the header.
        page.execute_script(<<~JS)
          const menu = document.querySelector(".admin-editor-header [role=menu]")
          const row = menu.lastElementChild
          for (let n = 0; n < 4; n++) menu.append(row.cloneNode(true))
        JS
        last = page.all(".admin-editor-header [role=menu] a, .admin-editor-header [role=menu] button").last
        drawer = box("#notes-drawer")
        item = page.evaluate_script("(() => { const box = arguments[0].getBoundingClientRect(); return [ box.left, box.top, box.right, box.bottom ] })()", last)
        assert_operator item[2], :>, drawer[0] + 8, "the premise: the menu reaches over the slide-over"
        assert_operator item[1], :>, drawer[1], "the premise: the menu's last row is below the header"
        assert page.evaluate_script(<<~JS, last), "the slide-over covers the header's menu"
          (() => {
            const item = arguments[0]
            const box = item.getBoundingClientRect()
            const hit = document.elementFromPoint(Math.max(box.left, #{drawer[0]}) + 4, (box.top + box.bottom) / 2)
            return hit === item || item.contains(hit)
          })()
        JS
      end
    end
  end

  test "Escape closes the slide-over only while the focus is inside, and the focus goes back to the opener" do
    at_window(MID) do
      open_editor
      open_notes
      assert_eventually(message: "the focus never moved into the notes") { focus_in_notes? }

      page.execute_script("document.querySelector('.admin-content-blocks [contenteditable=true]').focus()")
      keyboard.type(:escape)
      await_frames
      assert_selector "#notes-drawer #notes-list"
      assert_selector "#{NOTES_PANEL}[data-current]"

      find("#notes-drawer").execute_script("this.focus()")
      keyboard.type(:escape)
      assert_no_selector "#notes-drawer"
      assert_equal "notes-open", active_id
    end
  end

  test "under 640px the notes are a full-screen sheet with a way back" do
    at_window(PHONE) do
      open_editor
      open_notes

      drawer = box("#notes-drawer")
      assert_equal [ 0, room ], [ drawer[0], drawer[2] ].map(&:round), "the sheet is the window's width"
      assert_in_delta 48, drawer[1], 1
      assert_not pressable?("#notes-open"), "the sheet lies over the editor's header"
      assert_selector "#notes-drawer button", text: "Back to Pricing"
      assert_no_selector "#notes-drawer button[aria-label='Close']"

      within("#notes-drawer") { press "Back to Pricing" }
      assert_no_selector "#notes-drawer"
      assert_equal "notes-open", active_id
    end
  end

  test "a remembered open opens the Notes tab on the next editor at a wide window, and opens nothing at a narrow one" do
    at_window(WIDE) do
      open_editor
      open_notes
      open_editor
      assert_notes_tab_current
      assert_selector "#notes-drawer #notes-list"
      assert_not focus_in_notes?, "notes opened from memory take no focus"
    end

    at_window(MID) do
      open_editor
      assert_no_selector "#notes-drawer"
      assert_selector "#editor-grid-panel-page[data-current]"
      assert_current_path "/cs-studio/pages/#{@page.id}"
    end
  end

  test "?notes=open&thread= opens the thread in the tab, and the address follows the tab" do
    thread = as(users(:two)) { Notes::Start.call(@page, body: "About the prices") }.record
    at_window(WIDE) do
      open_editor("?notes=open&thread=#{thread.id}")
      assert_notes_tab_current
      assert_selector "#notes-drawer [data-notes-view=thread]", text: "About the prices"
      assert_current_path "/cs-studio/pages/#{@page.id}?notes=open&thread=#{thread.id}"

      find(PAGE_TAB).click
      assert_selector "#editor-grid-panel-page[data-current]"
      assert_current_path "/cs-studio/pages/#{@page.id}"

      find(NOTES_TAB).click
      assert_notes_tab_current
      assert_current_path "/cs-studio/pages/#{@page.id}?notes=open&thread=#{thread.id}"
    end
  end

  test "a live note arriving while another tab is current fills the Notes tab's count" do
    at_window(WIDE) do
      open_editor
      await_notes_live
      assert_selector "#editor-grid-panel-page[data-current]"
      assert_selector "#{NOTES_TAB} .text-count", visible: :hidden

      using_session(:dana) do
        sign_in_via_form(users(:two))
        visit "/cs-studio/notes/page/#{@page.id}?compose=Page-#{@page.id}"
        await_admin_controllers
        find("#notes-new textarea[name=body]").send_keys("Look at the prices")
        within("#notes-new") { press "Add note" }
        assert_selector "[data-note-thread]"
      end

      assert_selector "#{NOTES_TAB} .text-count", text: "1", wait: 10
      assert_selector "#notes-open-count", text: "1"
      assert_selector "#editor-grid-panel-page[data-current]"
    end
  end

  # A note that arrived while another tab was current marks the list stale
  # (`admin--notes--live`, counts only); pressing the Notes tab is an opening
  # like the header's button, and an opening fetches what is stale.
  test "a note that arrived while another tab was current is in the list when the Notes tab is pressed" do
    at_window(WIDE) do
      open_editor
      await_notes_live
      open_notes
      assert_selector "#notes-drawer #notes-list"
      find(PAGE_TAB).click
      assert_selector "#editor-grid-panel-page[data-current]"

      using_session(:dana) do
        sign_in_via_form(users(:two))
        visit "/cs-studio/notes/page/#{@page.id}?compose=Page-#{@page.id}"
        await_admin_controllers
        find("#notes-new textarea[name=body]").send_keys("Look at the prices")
        within("#notes-new") { press "Add note" }
        assert_selector "[data-note-thread]"
      end

      assert_selector "#{NOTES_TAB} .text-count", text: "1", wait: 10
      assert_no_selector "#notes-drawer #notes-list", text: "Look at the prices", visible: :all

      find(NOTES_TAB).click

      assert_notes_tab_current
      assert_selector "#notes-drawer #notes-list", text: "Look at the prices"
    end
  end

  test "the tree never folds for the notes: opening them at 1280px leaves the tree a column" do
    at_window(1280) do
      open_editor
      tree = box("#tree-column")
      assert_operator tree[2], :<=, box(".admin-shell__main")[0] + 1, "the premise: the tree is a column"

      open_notes

      assert_equal tree.map(&:round), box("#tree-column").map(&:round)
      assert_no_selector ".admin-shell__scrim"
      assert_no_selector ".admin-editor-header button[aria-controls='tree-column']", visible: :all
    end
  end

  # One element at every width (the panel is never moved, cloned or drawn
  # again), so what is typed and where the caret is survive the rail
  # undocking under it and a tab switch.
  test "a note being typed keeps its text and its focus when the rail undocks, and its text across a tab switch" do
    at_window(WIDE) do
      open_editor
      assert_docked
      open_notes
      within("#notes-drawer") { press "New note" }
      field = "#notes-new textarea[name=body]"
      find(field).send_keys("Half a thought")
      page.execute_script("window.__field = document.querySelector(#{field.to_json})")
      assert_equal true, page.evaluate_script("document.activeElement === window.__field")

      page.current_window.resize_to(MID, 900)
      assert_docked(false)

      assert_equal true, page.evaluate_script("window.__field.isConnected && document.querySelector(#{field.to_json}) === window.__field"), "the field was replaced"
      assert_equal true, page.evaluate_script("document.activeElement === window.__field"), "the field lost the focus"
      assert_equal "Half a thought", find(field).value
      assert_equal "fixed", computed("#notes-drawer", "position")

      page.current_window.resize_to(WIDE, 900)
      assert_docked
      find(PAGE_TAB).click
      find(NOTES_TAB).click
      assert_equal true, page.evaluate_script("document.querySelector(#{field.to_json}) === window.__field")
      assert_equal "Half a thought", find(field).value
    end
  end

  # A save's answer draws the tab's contents again
  # (`Admin::Answers::RailTabStreams`) with its number hidden, and reads no
  # counts: the script fills it. The tab's button stays, so a tab the
  # keyboard reached keeps the focus as the answer lands, never losing it
  # for a moment (Turbo would give a replaced element's id the focus back,
  # after a blur and on another element).
  test "a save draws the Notes tab's contents again, its number stays, and a focused tab keeps the focus" do
    as(users(:two)) { Notes::Start.call(@page, body: "One") }
    at_window(WIDE) do
      open_editor
      assert_docked
      assert_selector "#{NOTES_TAB} .text-count", text: "1"
      page.execute_script("document.querySelector(#{NOTES_TAB.to_json} + ' .text-count').dataset.probe = 'old'")

      find(PAGE_TAB).execute_script("this.focus()")
      keyboard.type(:right)
      keyboard.type(:right)
      assert_equal "editor-grid-tab-notes", active_id
      assert_selector "#notes-drawer #notes-list"
      page.execute_script("window.__tab = document.activeElement; window.__blurs = 0; window.__tab.addEventListener('blur', () => window.__blurs++)")
      # A change the autosave sends while the focus stays on the tab.
      find_field("Title", visible: :all).execute_script("this.value = 'Pricing and more'; this.dispatchEvent(new Event('input', { bubbles: true }))")
      assert_eventually(message: "the title was not saved") { @page.reload.title == "Pricing and more" }
      assert_writes_settled

      assert_eventually(message: "the save did not draw the tab's contents again") { page.evaluate_script("document.querySelector(#{NOTES_TAB.to_json} + ' .text-count').dataset.probe") != "old" }
      assert_selector "#{NOTES_TAB} .text-count", text: "1"
      assert_equal [ true, 0 ], page.evaluate_script("[ document.activeElement === window.__tab, window.__blurs ]"), "the answer took the focus off the tab"
      assert_notes_tab_current
    end
  end

  # What answers a press at a point inside both the element's box and the
  # slide-over's: the browser's own hit test, not a reading of the stylesheet.
  def covered_by_notes?(selector)
    page.evaluate_script(<<~JS)
      (() => {
        const under = document.querySelector(#{selector.to_json}).getBoundingClientRect()
        const notes = document.getElementById("notes-drawer").getBoundingClientRect()
        const left = Math.max(under.left, notes.left), right = Math.min(under.right, notes.right)
        const top = Math.max(under.top, notes.top), bottom = Math.min(under.bottom, notes.bottom, window.innerHeight)
        if (left >= right || top >= bottom) return "the two boxes do not meet"
        return document.elementFromPoint((left + right) / 2, (top + bottom) / 2)?.closest("#notes-drawer") !== null
      })()
    JS
  end

  # The canvas is a stacking context of its own (`.admin-rail__main`), so
  # whatever it raises, at whatever layer, stays under the slide-over.
  test "the slide-over covers a rich-text popover and an open table strip in the canvas" do
    table = @page.content_blocks.new(block_type: "table", position: 1)
    table.assign_body({ "type" => "doc", "content" => [ { "type" => "table", "content" => Array.new(2) do |row|
      { "type" => "tableRow", "content" => Array.new(4) { { "type" => row.zero? ? "tableHeader" : "tableCell", "content" => [ { "type" => "paragraph" } ] } } }
    end } ] }, locale: :en)
    table.save!

    at_window(MID) do
      open_editor
      assert_docked(false)

      within("#content_block_#{@block.id}") do
        find(".ProseMirror").execute_script("this.focus(); const range = document.createRange(); range.selectNodeContents(this); getSelection().removeAllRanges(); getSelection().addRange(range)")
        # ProseMirror reads the DOM selection a frame or two later.
        page.evaluate_async_script("const done = arguments[0]; requestAnimationFrame(() => requestAnimationFrame(() => setTimeout(() => done(true), 50)))")
        press "Link"
      end
      assert_selector ".admin-rich-text-popover"

      open_notes
      assert_selector ".admin-rich-text-popover"
      assert_equal true, covered_by_notes?(".admin-rich-text-popover"), "the rich-text popover stands over the slide-over"

      # The last column's letter stands under the slide-over, where no
      # pointer reaches it: the script's press opens its menu.
      open_entry = "#content_block_#{table.id} .admin-table-strip-entry:has([aria-expanded=true])"
      find("#content_block_#{table.id} button[aria-label='Column D actions']").execute_script("this.scrollIntoView({ block: 'center' }); this.click()")
      assert_selector "#{open_entry} [role=menu]"
      assert_equal true, covered_by_notes?(open_entry), "the open strip entry stands over the slide-over"
      assert_equal true, covered_by_notes?("#{open_entry} [role=menu]"), "the strip's menu stands over the slide-over"
    end
  end

  # A rail panel other than the notes' is a context of its own at `raised`
  # (`.admin-rail__panel`), so the post's settings, outside the canvas,
  # raise their popovers under the slide-over too.
  test "the slide-over covers the post settings' tag suggestions" do
    Tag.create!(name: "rails")
    post = create_post(title: "Chips", published: false)
    at_window(MID) do
      visit_editor(post)
      assert_docked(false)
      open_notes

      find("#post-tag_names").execute_script("this.scrollIntoView({ block: 'center' }); this.focus()")
      keyboard.type("ra")
      assert_selector "#post-tag_names-listbox [role=option]", text: "rails"
      assert_selector "#notes-drawer #notes-list"
      assert_equal true, covered_by_notes?("#post-tag_names-listbox"), "the tag suggestions stand over the slide-over"
    end
  end

  test "a post's tabs stand in the rail above its panels, after its main column in the document" do
    post = create_post(title: "Hello", published: false)
    at_window(WIDE) do
      visit_editor(post)
      assert_docked

      tabs = box("#editor-grid [role=tablist]")
      panel = box("#editor-grid-panel-post")
      assert_operator tabs[3], :<=, panel[1] + 1, "the tabs stand above the panels"
      assert_in_delta panel[0], tabs[0], 1, "in the rail's column"
      order = page.evaluate_script(<<~JS)
        [ ".admin-post-main", "#editor-grid-panel-post", "#editor-grid [role=tablist]", "#editor-grid-panel-notes" ]
          .map((selector) => document.querySelector(selector))
          .every((element, index, all) => index === 0 || (all[index - 1].compareDocumentPosition(element) & Node.DOCUMENT_POSITION_FOLLOWING))
      JS
      assert order, "the document reads main column, settings, tabs, notes"

      open_notes
      assert_notes_tab_current
      assert_selector "#editor-grid-panel-post:not([data-current])", visible: :hidden
    end
  end
end
