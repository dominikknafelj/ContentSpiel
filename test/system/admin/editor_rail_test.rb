require "application_system_test_case"

# The editors' rail (`admin/pages/show` and `Admin::EditorScreen::PostFormComponent`,
# `.admin-rail-grid`, `admin--ui--rail`): where the editor area has 1200px, the
# page settings stand in a 360px rail 28px right of a 900px blocks column, with
# a Page and a Section tab, and a post's settings in the same rail beside its
# title, address and body, under the one heading Post; below that the page
# settings stand above the blocks and a post's settings below its main
# column, at 760px, as one column. The editor area is the container, so a
# folded tree docks the rail at a window that would not otherwise. Each rule that overrides a base rule
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
      # Page and Section, then the registered Notes tab (`editor.rail.tabs`).
      assert_equal %w[editor-grid-tab-page editor-grid-tab-section editor-grid-tab-notes], all("#editor-grid [role=tablist] [role=tab]").map { |tab| tab[:id] }
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
      assert_in_delta 900, main[2] - main[0], 1
      assert_in_delta main[2] + 28, rail[0], 1, "the rail stands 28px right of the main column"
      assert_in_delta 360, rail[2] - rail[0], 1
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
end
