require "application_system_test_case"

# The page tree in a real browser: its drag-to-move (dropping a node under a
# different parent PATCHes `Admin::TreeController#update` and re-renders the
# whole tree from the database), the selected row, what a row shows on hover
# and focus, its one focus ring, and its folds: a disclosure folds a branch,
# the open set keeps it in the cookie `cs_tree_open`, the server draws it
# from the first paint, and the path to the open page is always drawn open.
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

  def disclosure(record) = find("#tree-row-#{record.id} > .admin-tree-row__disclosure", visible: :all)

  def children_hidden?(record) = page.evaluate_script("document.getElementById('tree-children-#{record.id}').hidden")

  # The open set as the browser holds it, its entries in order.
  def open_set = page.evaluate_script("document.cookie").to_s[/(?:^|; )cs_tree_open=([^;]*)/, 1].to_s.split(".")

  def make_branch
    Current.set(actor: users(:one)) do
      @child = create_page(title: "Child", parent: @alpha)
      @grandchild = create_page(title: "Grandchild", parent: @child)
    end
  end

  test "a row's disclosure folds and unfolds its branch by mouse and by keyboard" do
    make_branch
    visit_editor(@child)
    assert_equal "true", disclosure(@alpha)["aria-expanded"]
    assert_selector "#tree-row-#{@child.id}"

    disclosure(@alpha).click
    assert_selector "#tree-row-#{@alpha.id} > .admin-tree-row__disclosure[aria-expanded=false][aria-label='Unfold Alpha']"
    assert children_hidden?(@alpha)
    assert_no_selector "#tree-row-#{@child.id}"
    assert_includes open_set, "-#{@alpha.id}", "a fold of a branch open by default is stored"

    # Tab from the row's handle, the control before it.
    page.execute_script("document.querySelector('#tree-row-#{@alpha.id} .admin-tree-node__handle').focus()")
    page.driver.browser.keyboard.type(:tab)
    assert page.evaluate_script("document.activeElement.matches('#tree-row-#{@alpha.id} > .admin-tree-row__disclosure')"), "Tab reaches the disclosure"

    page.driver.browser.keyboard.type(:enter)
    assert_selector "#tree-row-#{@alpha.id} > .admin-tree-row__disclosure[aria-expanded=true][aria-label='Fold Alpha']"
    assert_not children_hidden?(@alpha)
    assert_selector "#tree-row-#{@child.id}"
    assert_not_includes open_set, "-#{@alpha.id}"

    page.driver.browser.keyboard.type(:space)
    assert_selector "#tree-row-#{@alpha.id} > .admin-tree-row__disclosure[aria-expanded=false][aria-label='Unfold Alpha']"
    assert children_hidden?(@alpha)
  end

  # The server draws a fold from the cookie: after a reload and after a
  # Turbo visit, the first `turbo:load` finds the branch folded, and no
  # script ever changed the list's `hidden`.
  test "a fold is kept across a reload and a Turbo visit, drawn folded from the first paint" do
    visit_screen "/cs-studio/pages"
    root = root_page
    disclosure(root).click
    assert children_hidden?(root)
    assert_equal [ "-#{root.id}" ], open_set

    spy = page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
      (() => {
        window.__changes = []
        window.__loads = []
        new MutationObserver((records) => records.forEach((record) => {
          if (record.target.id === "tree-children-#{root.id}") window.__changes.push(record.target.hidden)
        })).observe(document, { subtree: true, attributes: true, attributeFilter: ["hidden"] })
        document.addEventListener("turbo:load", () => window.__loads.push(document.getElementById("tree-children-#{root.id}")?.hidden ?? null))
      })()
    JS
    page.refresh
    await_admin_controllers
    assert_eventually { page.evaluate_script("window.__loads.length") >= 1 }
    assert_equal true, page.evaluate_script("window.__loads[0]"), "the first turbo:load found the branch open"
    assert_equal [], page.evaluate_script("window.__changes"), "a script changed the folded list's hidden"
    assert_equal "false", disclosure(root)["aria-expanded"]

    page.execute_script("window.__loads = []; Turbo.visit('/cs-studio')")
    assert_current_path "/cs-studio"
    page.execute_script("Turbo.visit('/cs-studio/pages')")
    assert_selector "#tree-children-#{root.id}", visible: :all
    await_admin_controllers
    assert_equal true, page.evaluate_script("window.__loads.at(-1)")
    assert_equal [], page.evaluate_script("window.__changes")
    assert children_hidden?(root)
  ensure
    page.driver.browser.page.command("Page.removeScriptToEvaluateOnNewDocument", identifier: spy["identifier"]) if spy
  end

  # The cookie's path is the admin path, so a visitor's page never sees it.
  test "after a fold a public page's document.cookie lacks the open set" do
    visit_screen "/cs-studio/pages"
    disclosure(root_page).click
    assert_equal [ "-#{root_page.id}" ], open_set
    assert_includes page.evaluate_script("document.cookie"), "cs_tree_open="

    visit "/"
    assert_not_includes page.evaluate_script("document.cookie").to_s, "cs_tree_open"
  end

  test "a full load of a page under a folded ancestor draws its path open and its row selected, and the fold is forgotten" do
    make_branch
    visit_editor(@grandchild)
    disclosure(@alpha).click
    assert_no_selector "#tree-row-#{@grandchild.id}"
    assert_includes open_set, "-#{@alpha.id}"

    page.refresh
    await_admin_controllers
    assert_selector "#tree-row-#{@grandchild.id}.admin-tree-row--selected a[aria-current=page]"
    assert_not children_hidden?(@alpha)
    assert_not children_hidden?(@child)
    assert_selector "li[data-page-id='#{@alpha.id}'][data-tree-on-path]"
    assert_not_includes open_set, "-#{@alpha.id}", "the fold on the open page's path is forgotten"
  end

  test "Alt+click opens the whole branch" do
    make_branch
    Current.set(actor: users(:one)) { create_page(title: "Great-grandchild", parent: @grandchild) }
    visit_screen "/cs-studio/pages"
    assert children_hidden?(@alpha)
    assert children_hidden?(@child)

    disclosure(@alpha).click(:alt)
    assert_selector "#tree-row-#{@grandchild.id}"
    [ @alpha, @child, @grandchild ].each do |record|
      assert_not children_hidden?(record), "#{record.title}'s branch is open"
      assert_includes open_set, record.id.to_s, "#{record.title}'s open is stored"
    end
    assert_selector "li[data-page-id='#{@child.id}'] > [data-tree-row] > .admin-tree-row__disclosure[aria-expanded=true][aria-label='Fold Child']"
  end

  # Below 1024px the tree is a drawer that scrolls on its own, so the
  # selected row is scrolled into view inside it: the column moves, the
  # window does not. The drawer is shut, so its controls are pressed by
  # script.
  test "Back to a page whose branch was folded opens its path and selects its row, scrolled into the column" do
    Current.set(actor: users(:one)) do
      30.times { |index| create_page(title: format("Filler %02d", index)) }
      @deep = create_page(title: "Deep")
      @target = create_page(title: "Target", parent: @deep)
    end
    at_window(900, height: 500) do
      visit_editor(@target)
      assert_operator page.evaluate_script("document.getElementById('tree-column').scrollTop"), :>, 0, "the selected row was not scrolled into the column"

      disclosure(@deep).execute_script("this.click()")
      assert children_hidden?(@deep)
      find("#tree-link-#{@alpha.id}", visible: :all).execute_script("this.click()")
      assert_selector "#content h1", text: "Alpha"
      await_admin_controllers
      assert children_hidden?(@deep)
      window_before = page.evaluate_script("window.scrollY")

      page.go_back
      assert_selector "#content h1", text: "Target"
      assert_selector "#tree-row-#{@target.id}.admin-tree-row--selected a[aria-current=page]", visible: :all
      assert_selector "#tree .admin-tree-row--selected", count: 1, visible: :all
      assert_eventually { !children_hidden?(@deep) }
      assert_eventually(message: "the column was not scrolled to the selected row") { page.evaluate_script("document.getElementById('tree-column').scrollTop") > 0 }
      assert_equal window_before, page.evaluate_script("window.scrollY"), "the window was scrolled"
      in_view = page.evaluate_script(<<~JS)
        (() => { const column = document.getElementById("tree-column").getBoundingClientRect(); const row = document.getElementById("tree-row-#{@target.id}").getBoundingClientRect(); return row.top >= column.top && row.bottom <= column.bottom })()
      JS
      assert in_view, "the selected row is inside the column's view"
    end
  end

  # A FOLDED PARENT UNDER A DRAGGED ROW opens after a moment
  # (`admin--pages--tree`'s `OPEN_ON_HOVER_MS`), so a page can be dropped
  # among children the fold hid. The drag is Cuprite's mouse in steps, as in
  # `tree_test.rb`'s mouse drag: SortableJS samples the pointer on a timer of
  # its own. Alpha holds one leaf, Child, and is folded by default on Pages.
  def handle_centre(record)
    page.evaluate_script(<<~JS)
      (() => { const r = document.querySelector("#tree-row-#{record.id} .admin-tree-node__handle").getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2] })()
    JS
  end

  def row_middle(record)
    page.evaluate_script("(() => { const r = document.getElementById('tree-row-#{record.id}').getBoundingClientRect(); return r.top + r.height / 2 })()")
  end

  # Beta, lifted by its handle, rests on Alpha's row until Alpha opens, then
  # is let go among Alpha's children, beside Child: wherever SortableJS puts
  # the slot in Alpha's list, as long as it is Alpha's own (Child's empty
  # list is a drop target too).
  def drag_beta_into_folded_alpha
    Current.set(actor: users(:one)) { @child = create_page(title: "Child", parent: @alpha) }
    visit_screen "/cs-studio/pages"
    assert children_hidden?(@alpha), "Alpha is folded by default"

    from_x, from_y = handle_centre(@beta)
    start_y = row_middle(@alpha)
    mouse = drag_pointer(from_x, from_y, start_y)
    assert_eventually(wait: 3, message: "the folded parent under the dragged row did not open") { !children_hidden?(@alpha) }
    assert_selector "li[data-page-id='#{@alpha.id}'].admin-tree-drop-target"

    # Onto Child's row, one step in: the pointer leaves the gutter for the
    # row itself, so it is over Alpha's list.
    child_x, child_y = handle_centre(@child)
    3.times do |step|
      mouse.move(x: from_x + ((child_x + 40 - from_x) * (step + 1) / 3.0), y: start_y + ((child_y - start_y) * (step + 1) / 3.0))
      sleep 0.08 # sleep: SortableJS samples the pointer on a 50 ms timer of its own; the pointer rests one tick plus margin per step
    end
    # The pointer rests on Child, stirred between its row's two halves,
    # until SortableJS's own timer has put the slot in Alpha's list. Child is
    # found again at each step: the slot may pass the opened Alpha, which
    # moves its branch by a row.
    slot_in_alpha = "document.querySelector('#tree-children-#{@alpha.id} > li.admin-drag-ghost') !== null"
    25.times do |step|
      break if page.evaluate_script(slot_in_alpha)

      child_x, child_y = handle_centre(@child)
      mouse.move(x: child_x + 40, y: child_y + (step.even? ? -4 : 4))
      sleep 0.08 # sleep: SortableJS samples the pointer on a 50 ms timer of its own
    end
    await_js slot_in_alpha, message: "the slot never reached Alpha's list"
    mouse.up
  end

  test "dragging a page over a folded parent opens it after a moment, and the page drops among its children" do
    drag_beta_into_folded_alpha

    assert_eventually(wait: 10) { @beta.reload.parent_id == @alpha.id }
    assert_equal [ @beta.id, @child.id ].sort, Page.where(parent_id: @alpha.id).pluck(:id).sort
    assert_selector "#toasts .admin-toast[data-kind=undo]", text: /Moved .Beta./, wait: 10
    assert_selector "#tree-children-#{@alpha.id} > li[data-page-id='#{@beta.id}']"
    assert_no_selector ".admin-tree-drop-target"
  end

  # The move's answer redraws the tree from the open set, and the moved
  # page's new parent is in it, so the page is shown where it went.
  test "a page dropped into a parent that hovering opened is shown there after the tree is redrawn" do
    drag_beta_into_folded_alpha

    assert_selector "#toasts .admin-toast[data-kind=undo]", text: /Moved .Beta./, wait: 10
    assert_selector "#tree-row-#{@alpha.id} > .admin-tree-row__disclosure[aria-expanded=true]"
    assert_selector "#tree-row-#{@beta.id}"
    assert_includes open_set, @alpha.id.to_s
  end

  test "a drag that leaves a folded parent before the moment does not open it" do
    Current.set(actor: users(:one)) { @child = create_page(title: "Child", parent: @alpha) }
    visit_screen "/cs-studio/pages"
    from_x, from_y = handle_centre(@beta)
    alpha_y = row_middle(@alpha)
    away_y = from_y + 60

    mouse = page.driver.browser.mouse
    mouse.move(x: from_x, y: from_y)
    mouse.down
    [ (from_y + alpha_y) / 2, alpha_y, (alpha_y + away_y) / 2, away_y ].each do |y|
      mouse.move(x: from_x, y: y)
      sleep 0.06 # sleep: SortableJS samples the pointer on a 50 ms timer of its own; the pointer passes Alpha's row in well under the moment
    end
    sleep 0.9 # sleep: longer than the moment (600 ms) after the pointer left Alpha's row, so a timer that was not cancelled would have opened it
    assert children_hidden?(@alpha), "a parent the pointer left before the moment was opened"
    assert_no_selector ".admin-tree-drop-target"
    mouse.up

    assert children_hidden?(@alpha)
    assert_not_includes open_set, @alpha.id.to_s
  end

  # The pointer travels through `ys` in steps quicker than the moment.
  def sweep(mouse, x, ys)
    ys.each do |y|
      mouse.move(x: x, y: y)
      sleep 0.06 # sleep: SortableJS samples the pointer on a 50 ms timer of its own; the pointer passes a row in well under the moment
    end
  end

  # Only the pointer resting on a folded row opens it: the slot beside it,
  # below as the drag starts and above once the pointer has crossed the
  # row's far quarter, is not the row.
  test "a slot resting beside a folded parent does not open it" do
    Current.set(actor: users(:one)) { @child = create_page(title: "Child", parent: @alpha) }
    visit_screen "/cs-studio/pages"
    from_x, from_y = handle_centre(@beta)
    alpha_top = page.evaluate_script("document.getElementById('tree-row-#{@alpha.id}').getBoundingClientRect().top")

    mouse = page.driver.browser.mouse
    mouse.move(x: from_x, y: from_y)
    mouse.down
    sweep(mouse, from_x, [ from_y - 2, from_y - 4 ])
    sleep 0.9 # sleep: longer than the moment (600 ms), the slot resting below Alpha
    assert children_hidden?(@alpha), "the slot below a folded parent opened it"

    sweep(mouse, from_x, [ alpha_top + 21, alpha_top + 14, alpha_top + 7, alpha_top + 3 ])
    assert_eventually(wait: 2, message: "the slot did not pass Alpha") do
      page.evaluate_script("document.querySelector('li.admin-drag-ghost')?.nextElementSibling?.dataset.pageId") == @alpha.id.to_s
    end
    sleep 0.9 # sleep: longer than the moment (600 ms), the slot resting above Alpha
    assert children_hidden?(@alpha), "the slot above a folded parent opened it"
    assert_no_selector ".admin-tree-drop-target"
    mouse.up

    assert_eventually(wait: 10) { root_page.children.order(:position).first == @beta }
    assert children_hidden?(@alpha)
    assert_not_includes open_set, @alpha.id.to_s
  end

  # Gamma passes Alpha's middle on its way up and comes back down to rest
  # on Beta, a leaf whose empty list is a drop target of its own: Alpha
  # stays folded.
  test "a drag across an empty leaf list after passing a folded parent does not open it" do
    Current.set(actor: users(:one)) do
      @child = create_page(title: "Child", parent: @alpha)
      @gamma = create_page(title: "Gamma")
    end
    visit_screen "/cs-studio/pages"
    from_x, from_y = handle_centre(@gamma)
    alpha_y = row_middle(@alpha)
    beta_y = row_middle(@beta)

    mouse = page.driver.browser.mouse
    mouse.move(x: from_x, y: from_y)
    mouse.down
    sweep(mouse, from_x, [ from_y - 4, beta_y, alpha_y + 10, alpha_y ])
    # Down to just under Beta's row, where its empty list takes the slot,
    # and on the slot there.
    beta_bottom = page.evaluate_script("document.getElementById('tree-row-#{@beta.id}').getBoundingClientRect().bottom")
    sweep(mouse, from_x, [ alpha_y + 14, beta_bottom - 4, beta_bottom + 4, beta_bottom + 6 ])
    sleep 0.9 # sleep: longer than the moment (600 ms) after the pointer left Alpha's row
    assert children_hidden?(@alpha), "a folded parent the pointer passed was opened"
    assert_no_selector ".admin-tree-drop-target"
    mouse.up

    assert children_hidden?(@alpha)
    assert_not_includes open_set, @alpha.id.to_s
  end

  # A folded parent says how many pages it hides, at rest; open, the count
  # rests out of sight like the row's other markers.
  test "a folded parent shows its subpage count at rest" do
    make_branch
    visit_screen "/cs-studio/pages"
    page.driver.browser.mouse.move(x: 900, y: 700)
    count = "#tree-row-#{@alpha.id} [data-child-count]"
    # At rest the count is clipped out of the row's flow (`__reveal`), shown
    # it stands in it.
    shown = -> { page.evaluate_script("(() => { const style = getComputedStyle(document.querySelector(#{count.to_json})); return style.position === 'static' && style.clipPath === 'none' })()") }

    assert_selector count, text: "1"
    assert shown.call, "a folded parent's count is not shown at rest"

    disclosure(@alpha).click
    page.driver.browser.mouse.move(x: 900, y: 700)
    assert_selector "#tree-row-#{@alpha.id} > .admin-tree-row__disclosure[aria-expanded=true]"
    page.execute_script("document.activeElement.blur()")
    assert_eventually(message: "an open parent's count still shows at rest") { !shown.call }
    assert_operator page.evaluate_script("document.querySelector(#{count.to_json}).getBoundingClientRect().width"), :<=, 1, "a clipped count takes no width"
    page.find("#tree-link-#{@alpha.id}").hover
    assert_eventually { shown.call }
    assert_operator page.evaluate_script("document.querySelector(#{count.to_json}).getBoundingClientRect().width"), :>=, 14, "a shown count keeps a figure's width"
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
