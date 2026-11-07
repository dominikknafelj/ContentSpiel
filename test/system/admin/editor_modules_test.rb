require "application_system_test_case"

# The editor's own modules (`app/javascript/editor/`), and the merge core
# (`app/javascript/live/keep_merge.js`) that both `editing/merge` and
# `notes/merge` draw an answer with, imported in the browser from the page
# editor: the project has no JavaScript test runner, and these
# are plain modules the import map resolves, so a system test can call them
# directly against the page's real containers (as `mind_graph_*_modules_test.rb`
# do for the graph's). The keyboard path is driven through its handle,
# because what it is asked for is what a screen reader hears.
class Admin::EditorModulesSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @page = create_page(title: "Landing")
    @first = @page.content_blocks.create!(block_type: "post_list", position: 0)
    @second = @page.content_blocks.create!(block_type: "post_list", position: 1)
    @section = @page.content_blocks.create!(block_type: "section", position: 2, settings: { "layout" => "two" })
    @left = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 1, position: 0)
    @right = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 2, position: 0)
    @narrow = @page.content_blocks.create!(block_type: "section", position: 3, settings: { "layout" => "one" })
    @only = @page.content_blocks.create!(block_type: "image", section: @narrow, section_column: 1, position: 0)
    visit_editor(@page)
  end

  def lane(column, section = @section) = "section-#{section.id}-lane-#{column}"
  def card(block) = "##{ActionView::RecordIdentifier.dom_id(block)}"

  # Runs `body` with the module `editor/<name>` (or the full specifier given,
  # such as "live/keep_merge") as `mod`, and answers what it returns.
  def with_module(name, body)
    page.evaluate_async_script(<<~JS, name.include?("/") ? name : "editor/#{name}")
      const [specifier, done] = arguments
      import(specifier).then((mod) => done((() => { #{body} })())).catch((error) => done({ error: String(error) }))
    JS
  end

  # The core's cases build their own containers from markup (`build`), and
  # answer the ids in order afterwards (`ids`) and which elements are the
  # ones they were.
  KEEP_MERGE_SETUP = <<~JS
    const build = (html) => { const box = document.createElement("div"); box.innerHTML = html; return box }
    const ids = (box) => Array.from(box.children).map((child) => child.id)
  JS

  test "keepMerge keeps a kept element the same element in the answer's place" do
    result = with_module("live/keep_merge", <<~JS)
      #{KEEP_MERGE_SETUP}
      const box = build('<p id="a">old a</p><p id="k">typed</p><p id="b">old b</p>')
      document.body.append(box)
      const [ a, k, b ] = box.children
      const answer = Array.from(build('<p id="b">new b</p><p id="k">answer k</p><p id="a">new a</p><p id="c">new c</p>').children)
      const { orphans } = mod.keepMerge(box, answer, { kept: new Set([ k ]) })
      const out = { order: ids(box), same: box.querySelector("#k") === k, text: k.textContent, replaced: box.querySelector("#a") !== a && box.querySelector("#b") !== b, a: box.querySelector("#a").textContent, orphans: orphans.length }
      box.remove()
      return out
    JS

    assert_nil result["error"]
    assert_equal %w[b k a c], result["order"]
    assert_equal true, result["same"]
    assert_equal "typed", result["text"]
    assert_equal true, result["replaced"]
    assert_equal "new a", result["a"]
    assert_equal 0, result["orphans"]
  end

  test "keepMerge leaves an orphan after its preceding sibling, or before place()" do
    result = with_module("live/keep_merge", <<~JS)
      #{KEEP_MERGE_SETUP}
      const run = (html, answerHtml, options = {}) => {
        const box = build(html)
        document.body.append(box)
        const k = box.querySelector("#k")
        const { orphans } = mod.keepMerge(box, Array.from(build(answerHtml).children), { kept: new Set([ k ]), ...options })
        const out = { order: ids(box), orphan: orphans.length === 1 && orphans[0] === k, connected: k.isConnected }
        box.remove()
        return out
      }
      return {
        after: run('<p id="a"></p><p id="k"></p><p id="b"></p>', '<p id="b"></p><p id="a"></p><p id="c"></p>'),
        first: run('<p id="k"></p><p id="a"></p>', '<p id="z"></p><p id="a"></p>'),
        placed: run('<p id="a"></p><p id="k"></p>', '<p id="a"></p><p id="h" hidden></p><p id="c"></p>', { place: (orphan, fresh) => fresh[2] }),
        end: run('<p id="k"></p><p id="a"></p>', '<p id="a"></p><p id="c"></p>', { place: () => null })
      }
    JS

    assert_nil result["error"]
    assert_equal({ "order" => %w[b a k c], "orphan" => true, "connected" => true }, result["after"])
    assert_equal({ "order" => %w[k z a], "orphan" => true, "connected" => true }, result["first"])
    assert_equal({ "order" => %w[a h k c], "orphan" => true, "connected" => true }, result["placed"])
    assert_equal({ "order" => %w[a c k], "orphan" => true, "connected" => true }, result["end"])
  end

  test "keepMerge reconciles inside an element that holds a kept one" do
    result = with_module("live/keep_merge", <<~JS)
      #{KEEP_MERGE_SETUP}
      const box = build('<div id="s" data-look="old"><p id="h">old head</p><p id="k">typed</p></div><div id="t"><p id="u">old</p></div>')
      document.body.append(box)
      const s = box.querySelector("#s"), k = box.querySelector("#k"), t = box.querySelector("#t")
      const answer = Array.from(build('<div id="s" data-look="new"><p id="k">answer k</p><p id="h">new head</p><p id="n">new</p></div><div id="t"><p id="u">new</p></div>').children)
      const synced = []
      const { orphans } = mod.keepMerge(box, answer, {
        kept: new Set([ k ]),
        within: (element) => element.contains(k) && element !== k,
        sync: (live, twin) => { synced.push(live.id); live.setAttribute("data-look", twin.getAttribute("data-look")) }
      })
      const out = {
        order: ids(box), inside: ids(s), sameSection: box.querySelector("#s") === s, sameKept: s.querySelector("#k") === k,
        look: s.getAttribute("data-look"), head: s.querySelector("#h").textContent, synced,
        replacedOther: box.querySelector("#t") !== t, orphans: orphans.length
      }
      box.remove()
      return out
    JS

    assert_nil result["error"]
    assert_equal %w[s t], result["order"]
    assert_equal %w[k h n], result["inside"]
    assert_equal true, result["sameSection"]
    assert_equal true, result["sameKept"]
    assert_equal "new", result["look"]
    assert_equal "new head", result["head"]
    assert_equal %w[s], result["synced"]
    assert_equal true, result["replacedOther"]
    assert_equal 0, result["orphans"]
  end

  test "keepMerge takes the first of two elements of one id on screen as the one matched" do
    result = with_module("live/keep_merge", <<~JS)
      #{KEEP_MERGE_SETUP}
      const box = build('<p id="a">1</p><p id="a">2</p><p id="b">old b</p>')
      document.body.append(box)
      const [ first, second ] = box.children
      mod.keepMerge(box, Array.from(build('<p id="b">new b</p><p id="a">answer</p>').children), { kept: new Set([ first, second ]) })
      const out = { texts: Array.from(box.children).map((child) => child.textContent), firstAfterB: box.children[1] === first }
      box.remove()
      return out
    JS

    assert_nil result["error"]
    assert_equal [ "new b", "1", "2" ], result["texts"]
    assert_equal true, result["firstAfterB"]
  end

  # A malformed answer: its first copy of an id is the twin, as on screen,
  # and the second is dropped, never reconciled into the same element again.
  test "keepMerge matches the first of two copies of one id in the answer" do
    result = with_module("live/keep_merge", <<~JS)
      #{KEEP_MERGE_SETUP}
      const box = build('<div id="s"><p id="k">typed</p></div><p id="z">old z</p>')
      document.body.append(box)
      const s = box.querySelector("#s"), k = box.querySelector("#k")
      const answer = Array.from(build('<div id="s" data-copy="1"><p id="k">a</p><p id="n1">first</p></div><p id="z">z</p><div id="s" data-copy="2"><p id="k">b</p><p id="n2">second</p></div>').children)
      const synced = []
      mod.keepMerge(box, answer, {
        kept: new Set([ k ]),
        within: (element) => element.contains(k) && element !== k,
        sync: (live, twin) => { synced.push(twin.getAttribute("data-copy")); live.setAttribute("data-copy", twin.getAttribute("data-copy")) }
      })
      const out = { order: ids(box), inside: ids(s), same: box.querySelector("#s") === s, copy: s.getAttribute("data-copy"), synced, kept: s.querySelector("#k") === k }
      box.remove()
      return out
    JS

    assert_nil result["error"]
    assert_equal %w[s z], result["order"]
    assert_equal %w[k n1], result["inside"]
    assert_equal true, result["same"]
    assert_equal true, result["kept"]
    assert_equal "1", result["copy"]
    assert_equal %w[1], result["synced"]
  end

  test "keepMerge moves the kept element without the focus when two swap" do
    result = with_module("live/keep_merge", <<~JS)
      #{KEEP_MERGE_SETUP}
      const run = (focused) => {
        const box = build('<div id="one"><input id="one-field"></div><div id="two"><input id="two-field"></div>')
        document.body.append(box)
        const one = box.querySelector("#one"), two = box.querySelector("#two")
        const field = box.querySelector(`#${focused}-field`)
        field.focus()
        const taken = []
        const observer = new MutationObserver((records) => records.forEach((record) => record.removedNodes.forEach((node) => taken.push(node.id))))
        observer.observe(box, { childList: true })
        mod.keepMerge(box, Array.from(build('<div id="two"></div><div id="one"></div>').children), { kept: new Set([ one, two ]) })
        observer.takeRecords().forEach((record) => record.removedNodes.forEach((node) => taken.push(node.id)))
        observer.disconnect()
        const out = { order: ids(box), focus: document.activeElement === field, taken, same: box.querySelector("#one") === one && box.querySelector("#two") === two }
        box.remove()
        return out
      }
      return { one: run("one"), two: run("two") }
    JS

    assert_nil result["error"]
    assert_equal({ "order" => %w[two one], "focus" => true, "taken" => %w[two], "same" => true }, result["one"])
    assert_equal({ "order" => %w[two one], "focus" => true, "taken" => %w[one], "same" => true }, result["two"])
  end

  test "itemsOf counts only an element that stands for a block, and placeOf names the section and its column, or neither" do
    result = with_module("containers", <<~JS)
      const list = document.getElementById("content-blocks-list")
      const lane = document.getElementById(#{lane(2).to_json})
      list.append(document.createElement("div"))
      return {
        list: mod.itemsOf(list).map((item) => Number(item.dataset.blockId)),
        lane: mod.itemsOf(lane).map((item) => Number(item.dataset.blockId)),
        listPlace: mod.placeOf(list),
        lanePlace: mod.placeOf(lane)
      }
    JS

    assert_nil result["error"]
    assert_equal [ @first.id, @second.id, @section.id, @narrow.id ], result["list"]
    assert_equal [ @right.id ], result["lane"]
    assert_equal({ "section_id" => nil, "column" => nil }, result["listPlace"])
    assert_equal({ "section_id" => @section.id.to_s, "column" => "2" }, result["lanePlace"])
  end

  test "refreshMoveState disables the ends of each container and Move to column… in a one-column section" do
    result = with_module("containers", <<~JS)
      const list = document.getElementById("content-blocks-list")
      const lanes = Array.from(document.querySelectorAll('[data-admin--editor--blocks-target="lane"]'))
      const own = (id, move) => Array.from(document.querySelectorAll(`[data-block-id="${id}"] [data-move="${move}"]`))
        .find((button) => button.closest("[data-block-id]").dataset.blockId === String(id))
      for (const button of document.querySelectorAll("[data-move]")) button.disabled = false
      mod.refreshMoveState([ list, ...lanes ], lanes)
      const state = (id, move) => own(id, move)?.disabled ?? null
      return {
        first: [ state(#{@first.id}, "up"), state(#{@first.id}, "down"), state(#{@first.id}, "into") ],
        last: [ state(#{@narrow.id}, "up"), state(#{@narrow.id}, "down") ],
        wide: [ state(#{@left.id}, "up"), state(#{@left.id}, "down"), state(#{@left.id}, "column") ],
        narrow: state(#{@only.id}, "column")
      }
    JS

    assert_nil result["error"]
    assert_equal [ true, false, false ], result["first"]
    assert_equal [ false, true ], result["last"]
    assert_equal [ true, true, false ], result["wide"]
    assert_equal true, result["narrow"]
  end

  test "a closed lane accepts nothing, and no lane accepts a section" do
    result = with_module("containers", <<~JS)
      const lane = document.getElementById(#{lane(1).to_json})
      const other = document.getElementById(#{lane(2).to_json})
      const tile = document.querySelector('.admin-block-tile[data-block-id="#{@right.id}"]')
      const section = document.querySelector('.admin-block-card[data-block-id="#{@narrow.id}"]')
      const open = [ mod.isClosed(lane), mod.accepts(lane, tile), mod.accepts(lane, section) ]
      other.setAttribute("data-no-drop", "")
      return { open, closed: [ mod.isClosed(other), mod.accepts(other, tile) ] }
    JS

    assert_nil result["error"]
    assert_equal [ false, true, false ], result["open"]
    assert_equal [ true, false ], result["closed"]
  end

  test "besideSection lets the list sort past a section only from above or below its lanes" do
    result = with_module("containers", <<~JS)
      const section = document.createElement("div")
      section.setAttribute("data-container", "")
      const lanes = document.createElement("div")
      lanes.setAttribute("data-admin--editor--section-target", "lanes")
      let rect = { top: 100, bottom: 200, height: 100 }
      lanes.getBoundingClientRect = () => rect
      section.append(lanes)
      const card = document.createElement("div")
      const otherSection = document.createElement("div")
      otherSection.setAttribute("data-container", "")
      const ask = (dragged, related, y, willInsertAfter) => mod.besideSection({ dragged, related, willInsertAfter }, { clientY: y })
      const answers = {
        header: [ ask(card, section, 90, false), ask(card, section, 90, true) ],
        lanes: [ ask(card, section, 150, false), ask(card, section, 150, true) ],
        below: [ ask(card, section, 210, false), ask(card, section, 210, true) ],
        sectionOverSection: ask(otherSection, section, 150, true),
        overPlainCard: ask(section, card, 150, true)
      }
      rect = { top: 100, bottom: 100, height: 0 }
      answers.collapsed = ask(card, section, 150, true)
      return answers
    JS

    assert_nil result["error"]
    assert_equal [ true, false ], result["header"]
    assert_equal [ false, false ], result["lanes"]
    assert_equal [ false, true ], result["below"]
    assert_equal true, result["sectionOverSection"]
    assert_equal true, result["overPlainCard"]
    assert_equal true, result["collapsed"]
  end

  # The Sortables are made after `import("sortablejs")` resolves, which is
  # after `connect`. A list that left the document in between (a Turbo visit,
  # a replaced section) must get none, and the late resolve must throw
  # nothing: the teardown fails this test on any JavaScript error.
  test "a controller disconnected before SortableJS arrives creates no Sortable and throws nothing" do
    result = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import("sortablejs").then(async (module) => {
        const Sortable = module.default
        let arrive
        window.contentSpielSortableLoader = () => new Promise((resolve) => { arrive = () => resolve(module) })
        const section = document.createElement("section")
        section.setAttribute("data-controller", "admin--editor--blocks")
        section.innerHTML = '<ul data-admin--editor--blocks-target="list"></ul>'
        document.body.append(section)
        const list = section.querySelector("ul")
        // Stimulus connects in a mutation observer's microtask, and `connect` marks the element pending.
        while (section.dataset.sortable !== "pending") await new Promise((resolve) => setTimeout(resolve, 5))
        section.remove()
        delete window.contentSpielSortableLoader
        arrive()
        await new Promise((resolve) => setTimeout(resolve, 100))
        done({ seenPending: true, sortable: Sortable.get(list) ? "made" : "none", mark: section.dataset.sortable || null })
      }).catch((error) => done({ error: String(error) }))
    JS

    assert_equal({ "seenPending" => true, "sortable" => "none", "mark" => nil }, result)
  end

  # The editor's rail takes a section's settings region out of its card. Its
  # layout menu, its Close and Escape are its own controller's, so they work
  # wherever the region stands; the card finds the region by its id.
  test "a section's settings region works outside its card: layout, Close and Escape" do
    region = "#section-#{@narrow.id}-settings"
    word = "#section-#{@narrow.id}-words button[data-admin--editor--section-field-param='layout']"
    layout_button = "#{region} button[aria-label='Layout']"
    focused = ->(selector) { page.evaluate_script("document.activeElement === document.querySelector(#{selector.to_json})") }
    page.execute_script("document.body.append(document.querySelector(#{region.to_json}))")

    find(word, text: "1 column").click
    assert_selector "body > #{region}", visible: :visible
    assert_eventually(message: "the focus is not on the Layout button of the region") { focused.call(layout_button) }

    find(layout_button).click
    find("#{region} [role=menuitem][data-admin--editor--section-settings-layout-param='two']").click

    assert_selector "#section-#{@narrow.id}-form #block-#{@narrow.id}-save-status", text: "SAVED"
    assert_selector word, text: "2 columns"
    assert_writes_settled
    assert_equal "two", @narrow.reload.settings["layout"]
    assert_eventually(message: "the focus is not on the Layout button the answer brought") { focused.call(layout_button) }

    page.driver.browser.keyboard.type(:escape)

    assert_selector region, visible: :hidden
    assert_selector "#{word}[aria-expanded='false']", text: "2 columns"
    assert_eventually(message: "the focus did not go back to the word") { focused.call(word) }

    # Its Close button closes it too, and gives the focus to the word.
    find(word).click
    assert_selector region, visible: :visible
    find("#{region} button[data-action='admin--editor--section-settings#close']").click
    assert_selector region, visible: :hidden
    assert_eventually(message: "Close did not give the focus to the word") { focused.call(word) }
  end

  # The region remembers the menu a pick was made in (`pickedIn`) on its own
  # controller, whose instance a move keeps: a region moved back under its
  # head while the layout's save is on the wire still gives the focus to the
  # menu the answer brings.
  test "a layout's answer gives the focus to the new menu after the region moved between the pick and the answer" do
    region = "#section-#{@narrow.id}-settings"
    layout_button = "#{region} button[aria-label='Layout']"
    page.execute_script("document.body.append(document.querySelector(#{region.to_json}))")
    find("#section-#{@narrow.id}-words button[data-admin--editor--section-field-param='layout']").click
    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.fetch = (url, options = {}) => {
        if ((options.method || "GET").toUpperCase() !== "PATCH") return originalFetch(url, options)
        return new Promise((resolve) => { window.__releaseSave = () => resolve(originalFetch(url, options)) })
      }
    JS

    find(layout_button).click
    find("#{region} [role=menuitem][data-admin--editor--section-settings-layout-param='two']").click
    await_js "typeof window.__releaseSave === 'function'", message: "the layout's save was never sent"
    page.execute_script(<<~JS)
      const card = document.querySelector(#{card(@narrow).to_json})
      card.querySelector(":scope > [data-editing-announcer]").after(document.querySelector(#{region.to_json}))
      document.activeElement?.blur()
      window.__releaseSave()
    JS

    assert_selector "#{card(@narrow)} > #{region} #block-#{@narrow.id}-save-status", text: "SAVED"
    assert_writes_settled
    assert_eventually(message: "the focus is not on the Layout button the answer brought") do
      page.evaluate_script("document.activeElement === document.querySelector(#{layout_button.to_json})")
    end
  end

  # A hold's `reveal` opens a hidden region to show its frozen form, through
  # the card's `showSettings`, and finds the card by the region's section,
  # not by where the region stands.
  test "a hold's reveal opens a section's settings region that stands outside its card" do
    region = "#section-#{@narrow.id}-settings"
    hold = "[data-controller~='admin--editing--hold']"
    page.execute_script("document.querySelector(#{hold.to_json}).append(document.querySelector(#{region.to_json}))")
    assert_selector "#{hold} > #{region}", visible: :hidden

    page.execute_script("window.Stimulus.getControllerForElementAndIdentifier(document.querySelector(#{hold.to_json}), 'admin--editing--hold').reveal(#{Editing.key(@narrow).to_json})")

    assert_selector "#{hold} > #{region}", visible: :visible
    assert_no_selector "#section-#{@narrow.id}-words button[aria-expanded='false']"
  end

  test "the keyboard path's sentences are the locale's words" do
    announcer = "[data-admin--editor--blocks-target=announcer]"
    announced = -> { page.evaluate_script("document.querySelector(#{announcer.to_json}).textContent") }
    title = ->(block) { page.evaluate_script("document.querySelector(#{"#{card(block)} [data-action$='admin--editor--blocks#toggle']".to_json}).textContent.trim()") }
    words = ->(key, **vars) { I18n.t("admin.components.editor_screen.block_moves.#{key}", **vars) }
    position = ->(at) { words.call(:position, position: at, count: 4) }
    handle = "#{card(@second)} .admin-block-card__handle"

    find(handle).send_keys(:space)
    assert_equal words.call(:picked_up, block: title.call(@second), position: position.call(2)), announced.call
    find(handle).send_keys(:up)
    assert_equal position.call(1), announced.call
    find(handle).send_keys(:space)
    assert_equal words.call(:dropped, block: title.call(@second), position: position.call(1)), announced.call
    assert_selector "#toasts .admin-toast[data-kind=undo]", wait: 10

    other = "#{card(@first)} .admin-block-card__handle"
    find(other).send_keys(:space, :down, :escape)
    assert_equal words.call(:cancelled, block: title.call(@first)), announced.call
  end
end
