require "application_system_test_case"

# The page tree in a real browser: its drag-to-move (dropping a node under a
# different parent PATCHes `Admin::TreeController#update` and re-renders the
# whole tree from the database), the selected row, what a row shows on hover
# and focus, and its one focus ring.
class Admin::TreeSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @alpha = create_page(title: "Alpha")
    @beta = create_page(title: "Beta")
  end

  # The markers rest clipped (`.admin-tree-row__reveal`, so a screen reader
  # still reads them) and show on the row's hover and while the focus is in
  # it. A Cuprite hover is a real pointer move, so `:hover` applies, and the
  # browser is a mouse device (`blink-settings` in
  # `ApplicationSystemTestCase`), so no coarse pointer shows them at rest.
  test "a row's markers show when the pointer is on it and when it has the focus" do
    with_locales(%w[en de], default: "en") do
      row = create_page(title: "Counted")
      visit_screen "/cs-studio/pages"
      assert page.evaluate_script("matchMedia('(hover: hover)').matches"), "the test browser reports it cannot hover"

      marker = "li[data-page-id='#{row.id}'] > div [data-translation-marker=missing]"
      assert_selector marker, text: "○1", visible: :all
      assert_equal "1px", page.find(marker, visible: :all).evaluate_script("getComputedStyle(this).width")

      page.find("#tree-link-#{row.id}").hover
      await_js "getComputedStyle(document.querySelector(#{marker.to_json})).width !== '1px'", message: "the marker did not show on hover"

      page.find("#tree-link-#{@alpha.id}").hover
      await_js "getComputedStyle(document.querySelector(#{marker.to_json})).width === '1px'", message: "the marker did not hide again"

      page.execute_script("document.querySelector('#tree-link-#{row.id}').focus()")
      await_js "getComputedStyle(document.querySelector(#{marker.to_json})).width !== '1px'", message: "the marker did not show on focus"
    end
  end

  test "dragging a page onto another node reparents it and persists" do
    visit_screen "/cs-studio/pages"

    assert_selector "li[data-page-id='#{@alpha.id}']"
    assert_selector "ul[data-parent-id='#{@beta.id}']"

    # `admin--pages--tree` drives SortableJS the same way `admin--editor--blocks` does (see
    # that test's own comment for why): native HTML5 drag-and-drop, which
    # a driver's synthesized mouse events can't reliably trigger in
    # headless Chrome. Moving Alpha's `<li>` into Beta's own children `<ul>`
    # and then calling the Stimulus controller's own `onDrop` directly --
    # with the same `{item, to, newIndex}` shape SortableJS's `onEnd` hands
    # it -- exercises the exact production path (the hand-built `fetch`
    # PATCH to `Admin::TreeController#update`, applied via
    # `Turbo.renderStreamMessage`) a real drop ends in.
    page.execute_script(<<~JS)
      const item = document.querySelector('li[data-page-id="#{@alpha.id}"]')
      const targetList = document.querySelector('ul[data-parent-id="#{@beta.id}"]')
      targetList.appendChild(item)

      const frame = document.getElementById("tree")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(frame, "admin--pages--tree")
      controller.onDrop({ item: item, to: targetList, newIndex: targetList.children.length - 1 })
    JS

    # The script above already moved Alpha's `<li>` under Beta's by hand
    # (that's what a drop does before `onDrop` runs), so the selector below
    # is satisfied at once and can't be what waits for the PATCH. Waiting
    # on the database is: polling until the move has persisted, or the
    # deadline passes. Asserting straight after the selector raced the
    # PATCH and failed intermittently on slower CI runners.
    assert_selector "ul[data-parent-id='#{@beta.id}'] li[data-page-id='#{@alpha.id}']"
    assert_eventually(wait: Capybara.default_max_wait_time + 8) { @alpha.reload.parent == @beta }
    assert_equal @beta, @alpha.reload.parent
  end

  # Moving the page that is open in the editor is a write of that page: it
  # takes its turn in the queue (never on the wire together with an
  # autosave), and it does not move the settings form's base
  # (`Page::SETTINGS_BASE_IGNORES`), so the next edit is not refused as
  # "Changed elsewhere" against the editor's own move. The toast's Undo is
  # the same request.
  test "moving the page that is open, and undoing it, leaves its editor able to save" do
    visit_editor(@alpha)
    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.__inFlight = 0
      window.__maxInFlight = 0
      window.fetch = async (url, options = {}) => {
        const write = (options.method || "GET").toUpperCase() !== "GET"
        if (write) { window.__inFlight += 1; window.__maxInFlight = Math.max(window.__maxInFlight, window.__inFlight) }
        try {
          if (write) await new Promise((resolve) => setTimeout(resolve, 400))
          return await originalFetch(url, options)
        } finally { if (write) window.__inFlight -= 1 }
      }
    JS

    # An autosave is on the wire as the page is dropped under Beta.
    fill_in "Subtitle", with: "Typed before the move"
    page.execute_script(<<~JS)
      document.activeElement.blur()
      const item = document.querySelector('li[data-page-id="#{@alpha.id}"]')
      const targetList = document.querySelector('ul[data-parent-id="#{@beta.id}"]')
      targetList.appendChild(item)
      const controller = window.Stimulus.getControllerForElementAndIdentifier(document.getElementById("tree"), "admin--pages--tree")
      controller.onDrop({ item: item, to: targetList, newIndex: targetList.children.length - 1 })
    JS
    assert_eventually(wait: 10) { @alpha.reload.parent_id == @beta.id }
    assert_selector "#toasts button", text: "Undo"

    fill_in "Subtitle", with: "Typed after my own move"
    page.execute_script("document.activeElement.blur()")
    assert_eventually { @alpha.reload.subtitle == "Typed after my own move" }
    assert_no_text "CHANGED ELSEWHERE"

    parent_before = Page.find(@beta.id).parent_id
    within("#toasts") { press "Undo" }
    assert_eventually(wait: 10) { @alpha.reload.parent_id == parent_before }
    assert_selector "#toasts", text: "Move undone."

    fill_in "Subtitle", with: "Typed after the Undo"
    page.execute_script("document.activeElement.blur()")
    assert_eventually { @alpha.reload.subtitle == "Typed after the Undo" }
    assert_no_text "CHANGED ELSEWHERE"
    assert_no_selector "#changed-elsewhere"
    assert_equal 1, page.evaluate_script("window.__maxInFlight"), "two writes were on the wire at once"
  end

  # Moving another page than the open one says nothing to the open form: it
  # keeps its base, and keeps saving.
  test "moving another page than the open one leaves the open editor able to save" do
    visit_editor(@beta)
    base = page.evaluate_script("document.getElementById('page-base-updated-at').value")

    page.execute_script(<<~JS)
      const item = document.querySelector('li[data-page-id="#{@alpha.id}"]')
      const targetList = document.querySelector('ul[data-parent-id="#{@beta.id}"]')
      targetList.appendChild(item)
      const controller = window.Stimulus.getControllerForElementAndIdentifier(document.getElementById("tree"), "admin--pages--tree")
      controller.onDrop({ item: item, to: targetList, newIndex: 0 })
    JS
    assert_eventually(wait: 10) { @alpha.reload.parent_id == @beta.id }
    assert_selector "#toasts button", text: "Undo"
    assert_equal base, page.evaluate_script("document.getElementById('page-base-updated-at').value")

    fill_in "Subtitle", with: "Still saving"
    page.execute_script("document.activeElement.blur()")
    assert_eventually { @beta.reload.subtitle == "Still saving" }
    assert_no_text "CHANGED ELSEWHERE"
  end

  # The tree column outlives a frame navigation, and a settings save
  # redraws only the saved page's row. One row is selected, and it is the
  # page that is open: after opening a page from the tree, and after saving it.
  test "opening a page from the tree and saving it leaves that page's row the one selected" do
    visit_editor(@alpha)
    selected = "#tree .admin-tree-row--selected"
    current = "#tree a[aria-current=page]"
    assert_selector "#{selected}#tree-row-#{@alpha.id}", count: 1

    find("#tree-link-#{@beta.id}").click
    assert_selector "#content h1", text: "Beta"
    assert_selector selected, count: 1
    assert_selector "#{selected}#tree-row-#{@beta.id}"
    assert_selector current, count: 1

    fill_in "Title", with: "Beta, renamed"
    page.execute_script("document.activeElement.blur()")
    assert_eventually { @beta.reload.title == "Beta, renamed" }
    assert_selector "#tree-row-#{@beta.id} a[aria-current=page]", text: "Beta, renamed"
    assert_selector selected, count: 1
    assert_selector current, count: 1
    assert_no_selector "#tree-row-#{@alpha.id}.admin-tree-row--selected"
  end

  # A link in the tree pressed with the keyboard keeps the focus while the
  # tree is drawn again for the page it opened.
  test "a page opened from the tree by the keyboard keeps the focus on its link" do
    visit_editor(@alpha)
    page.execute_script("document.querySelector('#tree-link-#{@beta.id}').focus()")
    page.send_keys(:enter)
    assert_selector "#content h1", text: "Beta"
    assert_selector "#tree-row-#{@beta.id}.admin-tree-row--selected"
    assert_eventually { page.evaluate_script("document.activeElement?.closest('#tree-row-#{@beta.id}') != null") }
  end

  # Turbo's snapshot keeps the selection the tree's script marked, and Back
  # to a page opened from the tree shows that page's row as the one selected.
  test "Back to a page opened from the tree selects that page's row" do
    visit_editor(@alpha)
    find("#tree-link-#{@beta.id}").click
    assert_selector "#content h1", text: "Beta"
    find("#tree-link-#{@alpha.id}").click
    assert_selector "#content h1", text: "Alpha"
    assert_selector "#tree .admin-tree-row--selected#tree-row-#{@alpha.id}", count: 1

    page.go_back
    assert_selector "#content h1", text: "Beta"
    assert_selector "#tree .admin-tree-row--selected", count: 1
    assert_selector "#tree-row-#{@beta.id}.admin-tree-row--selected a[aria-current=page]"
    assert_selector "#tree a[aria-current=page]", count: 1
  end

  # One ring, on what has the focus: a Pages row holds several controls, so
  # the row draws no outline and the focused control draws the tree's 2px
  # accent ring inside its own box. Each control is reached by the keyboard
  # from the row's link, so `:focus-visible` applies, with the pointer away
  # from the tree.
  test "a focused control in a Pages row draws one ring, its own, and the row none" do
    Current.set(actor: users(:one)) { create_page(title: "Child", parent: @alpha) }
    visit_screen "/cs-studio/pages"
    page.driver.browser.mouse.move(x: 900, y: 700)
    accent = page.evaluate_script(<<~JS)
      (() => { const probe = document.createElement("span"); probe.style.color = "var(--cs-accent)"; document.body.append(probe); const color = getComputedStyle(probe).color; probe.remove(); return color })()
    JS

    row = "#tree-row-#{@alpha.id}"
    # Each control, and the key that walks to it from the link: the link
    # itself is reached back from the control after it.
    {
      "#tree-link-#{@alpha.id}" => [ :tab, [ :shift, :tab ] ],
      "#{row} > button[aria-label='Move Alpha']" => [ nil, [ :shift, :tab ] ],
      "#{row} a[aria-label='Add a page under Alpha']" => [ nil, :tab ]
    }.each do |control, (first, key)|
      page.execute_script("document.querySelector('#tree-link-#{@alpha.id}').focus()")
      page.driver.browser.keyboard.type(first) if first
      6.times do
        break if page.evaluate_script("document.activeElement.matches(#{control.to_json})")

        page.driver.browser.keyboard.type(key)
      end

      seen = page.evaluate_script(<<~JS, control)
        (() => {
          const ring = (element) => { const style = getComputedStyle(element); return [style.outlineStyle, style.outlineWidth, style.outlineOffset, style.outlineColor] }
          const focused = document.querySelector(arguments[0])
          const node = focused.closest("li[data-tree-node]")
          const ringed = [ node, ...node.querySelectorAll("*") ].filter((element) => element !== focused && getComputedStyle(element).outlineStyle !== "none")
          return { active: document.activeElement === focused, visible: focused.matches(":focus-visible"), own: ring(focused), row: ring(focused.closest("[data-tree-row]")),
                   others: ringed.map((element) => element.id || element.className || element.tagName) }
        })()
      JS
      assert seen["active"], "#{control} has the focus"
      assert seen["visible"], "#{control} has the keyboard's focus"
      assert_equal [ "solid", "2px", "-2px", accent ], seen["own"], "#{control} draws the tree's ring"
      assert_equal "none", seen["row"].first, "the row of #{control} draws no outline"
      assert_empty seen["others"], "nothing else in the row's node draws an outline while #{control} has the focus"
    end
  end
end
