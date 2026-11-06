require "application_system_test_case"

# The editor's own modules (`app/javascript/editor/`), imported in the browser
# from the page editor: the project has no JavaScript test runner, and these
# are plain modules the import map resolves, so a system test can call them
# directly against the page's real containers (as `mind_graph_modules_test`
# does for the graph's). The keyboard path is driven through its handle,
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

  # Runs `body` with the module `editor/<name>` as `mod`, and answers what it returns.
  def with_module(name, body)
    page.evaluate_async_script(<<~JS, "editor/#{name}")
      const [specifier, done] = arguments
      import(specifier).then((mod) => done((() => { #{body} })())).catch((error) => done({ error: String(error) }))
    JS
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
      import("sortablejs").then(async ({ default: Sortable }) => {
        const section = document.createElement("section")
        section.setAttribute("data-controller", "admin--editor--blocks")
        section.innerHTML = '<ul data-admin--editor--blocks-target="list"></ul>'
        document.body.append(section)
        const list = section.querySelector("ul")
        // Stimulus connects in a mutation observer's microtask, and `connect` marks the element pending.
        let turns = 0
        while (section.dataset.sortable !== "pending" && turns++ < 1000) await null
        const seenPending = section.dataset.sortable === "pending"
        section.remove()
        await new Promise((resolve) => setTimeout(resolve, 300))
        done({ seenPending, sortable: Sortable.get(list) ? "made" : "none", mark: section.dataset.sortable || null })
      }).catch((error) => done({ error: String(error) }))
    JS

    assert_equal({ "seenPending" => true, "sortable" => "none", "mark" => nil }, result)
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
