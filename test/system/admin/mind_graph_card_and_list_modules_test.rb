require "application_system_test_case"

# The card and the node list modules: `card` and `node_list`.
class Admin::MindGraphCardAndListModulesSystemTest < Admin::MindGraphModulesSystemTestCase
  # The parts the card and the list clone, imported beside the module under
  # test as `p`, and their template in the page as the view renders it.
  PARTS = { p: "mind_graph/parts" }.freeze
  # The tree row's classes, as the view hands them to the list.
  TREE_CLASSES = Admin::Ui::TreeItemComponent::CLASSES.to_json

  setup do
    page.execute_script("document.body.insertAdjacentHTML('beforeend', arguments[0])", ApplicationController.render(Admin::MindGraphScreen::PartsComponent.new, layout: false))
  end

  # The selection card, asked directly with plain nodes: no
  # layout, no canvas and no request (a node with no open notes fetches
  # none). Each message is its key's last segments with its values, so a
  # test reads which sentence was asked for and with what.
  CARD_SCRIPT = <<~JS.freeze
    (() => {
      const container = document.createElement("aside")
      document.body.append(container)
      const text = { t: (key, values = {}) => `${key.split(".").slice(2).join(".")}(${Object.values(values).join(",")})`, locale: () => "en" }
      const urls = { postFocus: "/g?post=__ID__", tagFocus: "/g?tag=__ID__", tagPosts: "/posts?tag=__NAME__", postNotes: "/notes/post/__ID__/threads", pageFocus: "/g?page=__ID__", pageNotes: "/notes/page/__ID__/threads" }
      const parts = p.readParts(document.body)
      const card = m.createCard(container, { text, number: (value) => new Intl.NumberFormat("en").format(value), urls, typeLabels: { blog: "Blog" }, dotClasses: Array(12).fill("dot"), buttonClasses: { primary: "primary", secondary: "secondary" }, parts, onClose() {}, onPin() {}, onChange() {} })
      // The card top to bottom: each child as what it is and what it says.
      const part = (child) => child.matches("[data-mind-graph-card-notes]") ? [ "notes", child.dataset.notesType, child.dataset.notesId, child.querySelector("textarea").getAttribute("aria-label") ]
        : child.matches("[data-mind-graph-card-close]") ? [ "close" ]
        : child.matches("[data-chip-row]") ? [ "chips", child.dataset.status ]
        : child.tagName === "H2" ? [ "title", child.textContent ]
        : child.querySelector("a, button") ? [ "actions", ...Array.from(child.querySelectorAll("a, button"), (control) => [ control.tagName, control.textContent, control.getAttribute("href") ?? "-", control.className ]) ]
        : child.tagName === "P" ? [ "counts", ...Array.from(child.children, (item) => [ item.textContent, item.getAttribute("aria-hidden") ?? "-" ]) ]
        : [ "heading", ...Array.from(child.children, (item) => item.tagName === "CANVAS" ? [ "mark", item.dataset.mark, item.dataset.markOf ?? "-", item.getAttribute("aria-hidden") ] : item.matches(".admin-status-chip") ? [ "chip", item.dataset.status ] : [ "words", item.textContent, item.getAttribute("aria-hidden") ?? "-" ]) ]
      const read = () => Array.from(container.children, part)
      // Where the state stands and what it is made of: each chip by the part
      // it is a clone of (`same`), so a chip drawn or altered by hand reads
      // as "not <part>"; the state's name from the single chip's
      // `data-status`, or the chip row's.
      const same = (element, name) => element.isEqualNode(parts.part(name)) ? name : `not ${name}`
      const piece = (item) => item.matches("[data-unpublished-changes]") ? same(item, "unpublished") : item.matches(".admin-status-chip") ? same(item, `status-${item.dataset.status}`) : [ "words", item.className, item.textContent ]
      const chip = () => {
        const first = container.firstElementChild
        const single = first.querySelector(":scope > .admin-status-chip")
        const row = container.querySelector(":scope > [data-chip-row]")
        return { first: single ? [ piece(single), single.dataset.status ] : "-",
                 row: row ? [ row.dataset.status, row.getAttribute("aria-hidden"), row.previousElementSibling === first, ...Array.from(row.children, piece) ] : "-",
                 heard: first.querySelector(".sr-only")?.textContent ?? "-",
                 chips: container.querySelectorAll(".admin-status-chip, [data-unpublished-changes]").length }
      }
      return { container, card, read, chip, parts }
    })()
  JS

  LIST_SCRIPT = <<~JS.freeze
    (() => {
      const container = document.createElement("div")
      const calls = []
      const text = { t: (key, values = {}) => `${key.split(".").slice(-2).join(".")}(${Object.values(values).join(",")})`, locale: () => "en" }
      const parts = p.readParts(document.body)
      const list = m.createList(container, { text, treeClasses: #{TREE_CLASSES}, dotClasses: Array(12).fill("dot"), typeLabels: { blog: "Blog" }, retryClass: "retry", parts, onSelect: (id) => calls.push([ "select", id ]), onHover: () => {},
                                             onAdd: (row) => calls.push([ "add", row.id ]), onUnlisted: (on) => calls.push([ "unlisted", on ]) })
      // A row's level: how many of the tree's children lists it stands in.
      const level = (item) => { let found = 0; for (let list = item.closest("[data-tree-children]"); list; list = list.parentElement.closest("[data-tree-children]")) found += 1; return found }
      const read = () => Array.from(container.querySelectorAll("h2, button")).map((item) => item.tagName === "H2" ? item.textContent : [ item.querySelector(".admin-tree-row__title").textContent, item.lastChild.textContent, level(item), item.getAttribute("aria-label") ])
      return { container, calls, list, read, parts }
    })()
  JS

  # A page's card: "path, status pill, '4 child
  # pages · lists 112 posts', Open page / Focus / Pin; the notes list under
  # the title as on post cards".
  test "card: a page's card is its path and state, its title, its two counts, its notes, then Open page, Focus and Pin, and Home's is the same" do
    result = js_module("mind_graph/card", <<~JS, also: PARTS)
      (() => {
        const { container, card, read } = #{CARD_SCRIPT}
        const page = { id: "page-7", kind: "page", title: "<b>Blog</b>", path: "/blog/<i>x</i>", depth: 1, home: false, status: "live", changes: null, url: "/cs-studio/pages/7?locale=de", degree: 3, child_count: 4, listed_count: 112, open_notes: 0 }
        card.show(page)
        const blog = read()
        const named = [ container.getAttribute("aria-labelledby"), container.querySelector("h2").id, container.hidden, container.querySelectorAll("b, i").length ]
        const marked = Array.from(container.querySelectorAll("canvas[data-mark]"), (canvas) => canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height).data.some((value) => value > 0))
        let followed = null
        container.querySelector("a[data-mind-graph-card-open]").addEventListener("click", (event) => { event.preventDefault(); followed = event.currentTarget.getAttribute("href") })
        card.open()
        card.show({ ...page, id: "page-1", title: "Home", path: "/", depth: 0, home: true, child_count: 1, listed_count: 1, url: "/cs-studio/pages/1" })
        const home = read()
        card.show({ ...page, id: "page-9", title: "Stray", path: null, child_count: 0, listed_count: 0, status: "retired?" })
        const stray = read()
        card.show(page, { pinned: true, pinnable: false })
        const pin = [ container.querySelector("[data-mind-graph-card-pin]").textContent, container.querySelector("[data-mind-graph-card-pin]").hidden ]
        card.hide()
        const hidden = [ container.hidden, container.childElementCount ]
        // A kind with no card (a pill, or one a later build adds): nothing is shown and nothing throws.
        const cardless = [ "more", "constructor", undefined ].map((kind) => { try { return [ card.show({ id: "x-1", kind, title: "X" }), container.hidden, container.childElementCount ] } catch (error) { return String(error) } })
        card.show(page)
        const over = [ card.show({ id: "more-type-a", kind: "more", title: "+2 more" }), container.querySelector("h2").textContent, container.hidden ]
        card.hide()
        container.remove()
        return { blog, named, marked, followed, home, stray, pin, hidden, cardless, over }
      })()
    JS

    assert_equal [ [ "heading", [ "mark", "page", "-", "true" ], [ "words", "/blog/<i>x</i>", "-" ], [ "chip", "live" ] ],
                   [ "title", "<b>Blog</b>" ],
                   [ "counts", [ "card.child_pages(4,4)", "-" ], [ "·", "true" ], [ "card.lists_posts(112,112)", "-" ] ],
                   [ "notes", "page", "7", "card.notes.label_page()" ],
                   [ "actions", [ "A", "card.open_page()", "/cs-studio/pages/7?locale=de", "primary" ], [ "A", "card.focus()", "/g?page=7", "secondary" ], [ "BUTTON", "card.pin()", "-", "secondary" ] ],
                   [ "close" ] ], result["blog"]
    assert_equal [ "mind-graph-card-title", "mind-graph-card-title", false, 0 ], result["named"], "the card is named by its title, and a title and a path are text"
    assert_equal [ true ], result["marked"], "the page's mark is the renderer's drawing, painted once the card is in the document"
    assert_equal "/cs-studio/pages/7?locale=de", result["followed"], "Enter on a selected page presses Open page: the address is the one the server built"
    assert_equal [ [ "words", "/", "-" ], [ "counts", [ "card.child_pages(1,1)", "-" ], [ "·", "true" ], [ "card.lists_posts(1,1)", "-" ] ], [ "notes", "page", "1", "card.notes.label_page()" ] ],
                 [ result["home"][0][2], result["home"][2], result["home"][3] ], "Home's card is a page's card"
    assert_equal [ "heading", [ "mark", "page", "-", "true" ], [ "words", "", "-" ] ], result["stray"][0], "a page with no address has none written, and a status the chip does not know has no chip"
    assert_equal [ "counts", [ "card.child_pages(0,0)", "-" ], [ "·", "true" ], [ "card.lists_posts(0,0)", "-" ] ], result["stray"][2]
    assert_equal [ [ "card.unpin()", true ], [ true, 0 ] ], result.values_at("pin", "hidden")
    assert_equal [ [ false, true, 0 ] ] * 3, result["cardless"], "a kind without a card is answered false: no card, no error, also for a name every object has"
    assert_equal [ false, "<b>Blog</b>", false ], result["over"], "and the card that is open stays as it is"
  end

  # A record in one state has the shared status chip beside what it is. A
  # live record with more to say has a row of its own under the first, for
  # the eye only: the Live chip, then the unpublished chip or the scheduled
  # change's words with the server's day (`change_on`), as the editor's
  # header says it. A screen reader is given the key's words in one sentence.
  test "card: the chip is the shared status chip in each of the five states, the second state as the editor's header says it, and in the key's words for a screen reader" do
    states = { draft: { status: "draft" }, scheduled: { status: "scheduled" }, live: { status: "live", changes: nil },
               live_with_changes: { status: "live", changes: "unpublished" }, live_change_scheduled: { status: "live", changes: "scheduled", change_at: "2026-10-14T09:00:00Z", change_on: "14 Oct" },
               draft_with_changes: { status: "draft", changes: "unpublished" }, unknown: { status: "archived" } }
    result = js_module("mind_graph/card", <<~JS, also: PARTS)
      (() => {
        const { container, card, chip } = #{CARD_SCRIPT}
        const states = #{states.to_json}
        const of = (base) => Object.fromEntries(Object.entries(states).map(([ name, state ]) => { card.show({ ...base, ...state }); return [ name, chip() ] }))
        const result = { page: of({ id: "page-7", kind: "page", title: "Blog", path: "/blog", url: "/p", child_count: 0, listed_count: 0, open_notes: 0 }),
                         post: of({ id: "post-7", kind: "post", title: "Post", type: "blog", colour_index: 1, url: "/p", related_count: 0, tag_count: 0, open_notes: 0 }) }
        container.remove()
        return result
      })()
    JS

    %w[page post].each do |kind|
      chips = result[kind]
      %w[draft scheduled live].each do |state|
        assert_equal({ "first" => [ "status-#{state}", state ], "row" => "-", "heard" => "-", "chips" => 1 }, chips[state], "#{kind}: #{state} is the shared chip beside what the node is")
      end
      assert_equal({ "first" => "-", "row" => [ "live_with_changes", "true", true, "status-live", "unpublished" ], "heard" => "card.status.live_with_changes()", "chips" => 2 },
                   chips["live_with_changes"], "#{kind}: the Live chip and the unpublished chip, in a row of their own")
      assert_equal({ "first" => "-", "row" => [ "live_change_scheduled", "true", true, "status-live", [ "words", "min-w-0 text-xs text-dim", "card.status.change_scheduled(14 Oct)" ] ],
                     "heard" => "card.status.live_change_scheduled(14 Oct)", "chips" => 1 }, chips["live_change_scheduled"], "#{kind}: the Live chip and the change's words with the server's day")
      assert_equal({ "first" => [ "status-draft", "draft" ], "row" => "-", "heard" => "-", "chips" => 1 }, chips["draft_with_changes"], "#{kind}: only a live record has a second state")
      assert_equal({ "first" => "-", "row" => "-", "heard" => "-", "chips" => 0 }, chips["unknown"], "#{kind}: a status the chip does not know gets no chip")
    end
  end

  test "card: Close is the shared icon button, named Close, last in the card" do
    result = js_module("mind_graph/card", <<~JS, also: PARTS)
      (() => {
        const container = document.createElement("aside")
        document.body.append(container)
        let closed = 0
        const parts = p.readParts(document.body)
        const card = m.createCard(container, { text: { t: (key) => key, locale: () => "en" }, urls: { tagPosts: "/posts?tag=__NAME__", tagFocus: "/g?tag=__ID__" }, typeLabels: {}, dotClasses: [], buttonClasses: { primary: "primary", secondary: "secondary" }, parts,
                                               onClose: () => { closed += 1 }, onPin() {}, onChange() {} })
        card.show({ id: "tag-3", kind: "tag", title: "a", count: 1, degree: 1 })
        const close = container.lastElementChild
        const seen = [ close.isEqualNode(parts.part("close")), close.tagName, close.type, close.getAttribute("aria-label"), container.querySelectorAll("[data-mind-graph-card-close]").length ]
        close.click()
        card.hide()
        container.remove()
        return { seen, closed }
      })()
    JS

    assert_equal [ true, "BUTTON", "button", "Close", 1 ], result["seen"], "Close is the part as the server drew it, the card's last child"
    assert_equal 1, result["closed"], "a press on it is the card's onClose"
  end

  test "parts: a part the page does not hold is an error, not an empty card" do
    result = js_module("mind_graph/parts", <<~JS)
      (() => {
        const error = (call) => { try { call(); return "no error" } catch (thrown) { return [ thrown.constructor.name, thrown.message ] } }
        const parts = m.readParts(document.body)
        const close = [ parts.part("close"), parts.part("close") ]
        return { unknown: error(() => parts.part("status-archived")), none: error(() => m.readParts(document.createElement("div")).part("close")),
                 fresh: [ close[0] === close[1], close[0].isEqualNode(close[1]), close[0].isConnected ],
                 names: #{Admin::MindGraphScreen::PartsComponent::NAMES.to_json}.map((name) => parts.part(name).parentNode === null) }
      })()
    JS

    assert_equal [ "Error", "mind graph: no part named status-archived" ], result["unknown"]
    assert_equal [ "Error", "mind graph: no part named close" ], result["none"], "a page without the template is the same error"
    assert_equal [ false, true, false ], result["fresh"], "each call answers a clone of its own, in no document"
    assert_equal [ true ] * Admin::MindGraphScreen::PartsComponent::NAMES.size, result["names"]
  end

  # A post type a page lists: what
  # it is, its name, how many posts of it the viewer reads, and Pin. No link:
  # the pages that list it are its neighbours on the canvas.
  test "card: a post type's card is its hub's mark, its name and how many posts it has, with Pin and no link, for a retired type and All posts too" do
    result = js_module("mind_graph/card", <<~JS, also: PARTS)
      (() => {
        const { container, card, read } = #{CARD_SCRIPT}
        const cards = [ { id: "type-blog", kind: "type", name: "blog", title: "Blog", colour_index: 3, count: 112, degree: 2 },
                        { id: "type-talk", kind: "type", name: "talk", title: "talk (retired)", colour_index: null, count: 1, degree: 1 },
                        { id: "all-posts", kind: "type", name: null, title: "All posts", colour_index: null, count: 2040, degree: 4 },
                        { id: "type-new", kind: "type", name: "new", title: "New", colour_index: 8, degree: 1 } ].map((node) => { card.show(node); return read() })
        container.remove()
        return cards
      })()
    JS

    blog, retired, all, countless = result
    assert_equal [ [ "heading", [ "mark", "type", "3", "true" ], [ "words", "card.post_type()", "-" ] ], [ "title", "Blog" ], [ "counts", [ "card.tag_posts(112,112)", "-" ] ],
                   [ "actions", [ "BUTTON", "card.pin()", "-", "secondary" ] ], [ "close" ] ], blog
    assert_equal [ [ "heading", [ "mark", "type", "retired", "true" ], [ "words", "card.post_type()", "-" ] ], [ "title", "talk (retired)" ], [ "counts", [ "card.tag_posts(1,1)", "-" ] ] ], retired.first(3)
    assert_equal [ [ "heading", [ "mark", "type", "all-posts", "true" ], [ "words", "card.post_type()", "-" ] ], [ "title", "All posts" ], [ "counts", [ "card.tag_posts(2040,2,040)", "-" ] ] ], all.first(3)
    assert_equal [ "counts", [ "card.tag_posts(0,0)", "-" ] ], countless[2]
    assert_includes all[2].flatten, "card.tag_posts(2040,2,040)", "a figure is grouped as the messages' language groups it; the number itself only chooses the plural"
  end

  # A post's card and a tag's, and the added post's, whose counts the page
  # does not know.
  test "card: a post's card keeps its order and its notes' type, an added post's leaves the counts out, and a tag's has no notes" do
    result = js_module("mind_graph/card", <<~JS, also: PARTS)
      (() => {
        const { container, card, read } = #{CARD_SCRIPT}
        const post = { id: "post-12", kind: "post", title: "Twelve", type: "blog", colour_index: 1, status: "live", changes: null, url: "/cs-studio/posts/12", related_count: 3, tag_count: 2, open_notes: 0 }
        const cards = [ post, { ...post, related_count: null, tag_count: null }, { id: "tag-3", kind: "tag", title: "a b&c", count: 2, degree: 2 } ].map((node) => { card.show(node); return read() })
        container.remove()
        return cards
      })()
    JS

    post, added, tag = result
    assert_equal [ [ "heading", [ "words", "", "true" ], [ "words", "Blog", "-" ], [ "chip", "live" ] ], [ "title", "Twelve" ],
                   [ "counts", [ "card.related(3,3)", "-" ], [ "·", "true" ], [ "card.tags(2,2)", "-" ] ], [ "notes", "post", "12", "card.notes.label()" ],
                   [ "actions", [ "A", "card.open_post()", "/cs-studio/posts/12", "primary" ], [ "A", "card.focus()", "/g?post=12", "secondary" ], [ "BUTTON", "card.pin()", "-", "secondary" ] ], [ "close" ] ], post
    assert_equal %w[heading title notes actions close], added.map(&:first), "a post added from the list says nothing of counts nobody counted"
    assert_equal [ [ "heading", [ "words", "", "true" ], [ "words", "card.tag()", "-" ] ], [ "title", "a b&c" ], [ "counts", [ "card.tag_posts(2,2)", "-" ] ],
                   [ "actions", [ "A", "card.show_tagged()", "/posts?tag=a%20b%26c", "primary" ], [ "A", "card.focus()", "/g?tag=3", "secondary" ], [ "BUTTON", "card.pin()", "-", "secondary" ] ], [ "close" ] ], tag
  end

  test "list: four groups: Pages first, in tree order a step per level, then posts and tags by their connections, then the post types as the data has them" do
    rows = js_module("mind_graph/node_list", <<~JS, also: PARTS)
      (() => {
        const { container, list, read, parts } = #{LIST_SCRIPT}
        list.render([ { id: "post-1", kind: "post", title: "Post", degree: 1, colour_index: 1 }, { id: "tag-1", kind: "tag", title: "tag", degree: 2 },
                      { id: "page-3", kind: "page", title: "Child", degree: 9, depth: 2, order: 2, parent: "page-2" }, { id: "page-1", kind: "page", title: "Home", degree: 1, depth: 0, order: 0, parent: null, home: true },
                      { id: "page-2", kind: "page", title: "Docs", degree: 2, depth: 1, order: 1, parent: "page-1" }, { id: "page-9", kind: "page", title: "Stray", degree: 0, depth: 1, order: 3, parent: null },
                      { id: "type-blog", kind: "type", title: "Blog", degree: 4, count: 112, colour_index: 1 }, { id: "type-talk", kind: "type", title: "Talk", degree: 9, count: 1, colour_index: 8 },
                      { id: "type-gone", kind: "type", title: "gone (retired)", degree: 1, count: 0, colour_index: null }, { id: "all-posts", kind: "type", title: "All posts", degree: 1, count: 2040, colour_index: null },
                      { id: "more-type-blog", kind: "more", title: "+3 more", degree: 1, count: 3, target: "type-blog", of: "Blog" } ])
        const same = (element, names) => names.find((name) => element.isEqualNode(parts.part(name))) ?? "not a part"
        // The mark box's content: a glyph by the part it is a clone of, else the element.
        const markOf = (button) => {
          const mark = button.querySelector(":scope > .admin-tree-row__mark").firstElementChild
          if (!mark) return [ "empty" ]
          if (mark.tagName.toLowerCase() === "svg") return [ "glyph", same(mark, [ "tree-home-mark", "tree-page-mark" ]) ]
          return [ mark.tagName, mark.dataset.mark ?? mark.className.split(" ").pop(), mark.dataset.markOf ?? "-", mark.getAttribute("aria-hidden") ?? "-" ]
        }
        // The disclosure box: the part (drawn open), empty, or none on a flat row.
        const boxOf = (row) => {
          const box = row.querySelector(":scope > .admin-tree-row__disclosure")
          if (!box) return row.classList.contains("admin-tree-row--flat") ? "flat" : "none"
          return box.childElementCount ? same(box, [ "tree-disclosure" ]) : "empty"
        }
        list.mark("page-2")
        const marked = Array.from(container.querySelectorAll("button"), (button) => [ button.classList.contains("admin-tree-row--selected"), button.getAttribute("aria-current") ?? "-" ]).filter(([ selected, current ]) => selected || current !== "-")
        list.mark("post-1")
        const moved = [ list.row("page-2").className, list.row("post-1").className ]
        list.mark(null)
        // Where a page's row stands in the document: the row of the item its list is in, or "top". (No null: the driver drops one from an array.)
        const under = (id) => list.row(id).closest("ul").parentElement.closest("li")?.querySelector("button").dataset.nodeId ?? "top"
        return { rows: read(), marks: Array.from(container.querySelectorAll("button"), markOf), boxes: Array.from(container.querySelectorAll("h2, button"), boxOf),
                 marked, moved, cleared: container.querySelectorAll(".admin-tree-row--selected, [aria-current]").length,
                 classes: [ container.querySelector("[data-mind-graph-rows]").classList.contains("admin-tree"), Array.from(container.querySelectorAll("[data-tree-children]"), (list) => list.className) ],
                 under: [ "page-1", "page-2", "page-3", "page-9" ].map(under),
                 lists: Array.from(container.querySelectorAll("section"), (section) => [ section.querySelector("h2").textContent, section.querySelector("ul").getAttribute("aria-labelledby") === section.querySelector("h2").id, section.querySelector("ul").getAttribute("role") ]),
                 checkbox: [ container.firstElementChild.tagName, container.querySelector("label input").type, container.querySelector("label").textContent ] }
      })()
    JS

    assert_equal [ "list.pages(4)", [ "Home", "1", 0, "list.select_page(Home,1)" ], [ "Docs", "2", 1, "list.select_page(Docs,2)" ],
                   [ "Child", "9", 2, "list.select_page(Child,9)" ], [ "Stray", "0", 0, "list.select_page(Stray,0)" ],
                   "list.posts(1)", [ "Post", "1", 0, "list.select_post(Post,1)" ], "list.tags(1)", [ "tag", "2", 0, "list.select_tag(tag,2)" ],
                   "list.types(4)", [ "Blog", "112", 0, "list.select_type(Blog,112)" ], [ "+3 more", "+3 more", 1, "list.more_row(3,3,Blog,+3 more)" ], [ "Talk", "1", 0, "list.select_type(Talk,1)" ],
                   [ "gone (retired)", "0", 0, "list.select_type(gone (retired),0)" ], [ "All posts", "2040", 0, "list.select_type(All posts,2040)" ] ], rows["rows"],
      "a page steps once per level under its parent, and one whose parent is not in the data stands after the tree at the top; a post type's number is its POSTS, not its connections, and the rows keep the data's order; a pill's row is the child of what it hangs off and is no post type: the group still counts four"
    assert_equal [ "top", "page-1", "page-2", "top" ], rows["under"], "the tree is the document's: a page's row is in a list inside its parent's item, and one with no parent here at the top"
    assert_equal [ [ "glyph", "tree-home-mark" ], [ "glyph", "tree-page-mark" ], [ "glyph", "tree-page-mark" ], [ "glyph", "tree-page-mark" ], [ "SPAN", "dot", "-", "true" ], [ "SPAN", "bg-surface", "-", "true" ] ] +
                 [ [ "CANVAS", "type", "1", "true" ], [ "empty" ], [ "CANVAS", "type", "8", "true" ], [ "CANVAS", "type", "retired", "true" ], [ "CANVAS", "type", "all-posts", "true" ] ], rows["marks"],
      "a page's mark is the tree's glyph, Home's the house; a post type's is the renderer's canvas, each hub saying which it is; a post's dot and a tag's square are CS Studio's own; a pill's box is empty"
    assert_equal %w[tree-disclosure tree-disclosure tree-disclosure empty empty tree-disclosure flat tree-disclosure flat tree-disclosure tree-disclosure flat flat flat flat], rows["boxes"],
      "each heading, a page with children here and a hub a pill hangs off draw the disclosure part; a leaf page keeps its box empty; a post, a tag, a type and a pill are flat"
    assert_equal [ [ [ true, "true" ] ], [ "admin-tree-row", "admin-tree-row admin-tree-row--flat admin-tree-row--selected" ], 0 ], rows.values_at("marked", "moved", "cleared"),
      "the marked row takes the tree's selected class with aria-current, one at a time, and none is left with the mark cleared"
    assert_equal [ true, [ "admin-tree__children" ] * 3 ], rows["classes"], "the rows' region is the tree, and a parent's children stand in the tree's children list"
    assert_equal [ [ "list.pages(4)", true, "list" ], [ "list.posts(1)", true, "list" ], [ "list.tags(1)", true, "list" ], [ "list.types(4)", true, "list" ] ], rows["lists"], "each group is a list named by its heading"
    assert_equal [ "LABEL", "checkbox", "list.unlisted()" ], rows["checkbox"]
  end

  # The list shows a record's state by the posts list's own rule: the status
  # chip unless the record is live, then the unpublished chip when its mark
  # is set (`unpublished`, `Publishing::State#changes?`). A live record with
  # a change scheduled carries the unpublished chip only when it is marked
  # too. Every chip is a clone of its part, hidden from a screen reader, and
  # the row's name says each chip's own word after the title.
  test "list: each group's heading carries its kind's icon chip, and a row the posts list's chips by its rule, hidden from a screen reader and said in its name" do
    result = js_module("mind_graph/node_list", <<~JS, also: PARTS)
      (() => {
        const { container, list, parts } = #{LIST_SCRIPT}
        const page = { kind: "page", degree: 1, depth: 1, parent: "page-1", changes: null, unpublished: false }
        const post = { kind: "post", degree: 1, colour_index: 1, changes: null, unpublished: false }
        list.render([ { ...page, id: "page-1", title: "Home", depth: 0, order: 0, parent: null, status: "live" },
                      { ...page, id: "page-2", title: "Draft", order: 1, status: "draft" },
                      { ...page, id: "page-3", title: "Changed", order: 2, status: "live", changes: "unpublished", unpublished: true },
                      { ...post, id: "post-1", title: "Soon", degree: 6, status: "scheduled" },
                      { ...post, id: "post-2", title: "Soon changed", degree: 5, status: "scheduled", unpublished: true },
                      { ...post, id: "post-3", title: "Live", degree: 4, status: "live" },
                      { ...post, id: "post-4", title: "Later", degree: 3, status: "live", changes: "scheduled" },
                      { ...post, id: "post-5", title: "Later changed", degree: 2, status: "live", changes: "scheduled", unpublished: true },
                      { id: "tag-1", kind: "tag", title: "tag", degree: 2 }, { id: "type-blog", kind: "type", title: "Blog", degree: 4, count: 3, colour_index: 1 },
                      { id: "more-type-blog", kind: "more", title: "+3 more", degree: 1, count: 3, target: "type-blog", of: "Blog" } ])
        const same = (element, name) => element.isEqualNode(parts.part(name)) ? name : `not ${name}`
        const icons = [ "icon-page", "icon-post", "icon-tag", "icon-type" ]
        const chipOf = (heading) => heading.querySelector(":scope > .admin-tree-row__mark").firstElementChild
        const headings = Array.from(container.querySelectorAll("section > h2"), (heading, index) => [ heading.textContent, same(chipOf(heading), icons[index]), chipOf(heading).getAttribute("aria-hidden") ])
        // A heading is a row of the tree: the disclosure part, the chip in the mark box, the words with the figure in the count style.
        const row = container.querySelector("section > h2")
        const look = [ row.className, same(row.firstElementChild, "tree-disclosure"), row.querySelector(".admin-tree-row__title > .text-label").firstChild.textContent,
                       row.querySelector(".admin-tree-row__title > .text-label > .text-count").textContent, Array.from(container.querySelectorAll("section"), (section) => section.className) ]
        const rows = Array.from(container.querySelectorAll("button[data-node-id]"), (button) => {
          const chips = Array.from(button.querySelectorAll(".admin-status-chip, [data-unpublished-changes]"))
          const held = chips[0]?.parentElement
          return [ button.dataset.nodeId, chips.map((chip) => same(chip, chip.matches("[data-unpublished-changes]") ? "unpublished" : `status-${chip.dataset.status}`)),
                   held ? [ held.getAttribute("aria-hidden"), held.previousElementSibling.classList.contains("admin-tree-row__title") ] : "-", button.getAttribute("aria-label") ]
        })
        return { headings, look, rows }
      })()
    JS

    assert_equal [ [ "list.pages(3)", "icon-page", "true" ], [ "list.posts(5)", "icon-post", "true" ], [ "list.tags(1)", "icon-tag", "true" ], [ "list.types(1)", "icon-type", "true" ] ], result["headings"],
      "each group's heading has its kind's icon chip in the mark box, and its words are the heading's whole text"
    assert_equal [ "admin-tree-row", "tree-disclosure", "list.pages(", "3", [ "not-first:mt-3" ] * 4 ], result["look"],
      "a heading is the tree's row with the disclosure part, its figure cut out of its words into the count style, and each group but the first stands 12px below the one before"
    hidden = [ "true", true ]
    assert_equal [ [ "page-1", [], "-", "list.select_page(Home,1)" ],
                   [ "page-2", %w[status-draft], hidden, "list.select_page(list.stated(Draft,labels.draft()),1)" ],
                   [ "page-3", %w[unpublished], hidden, "list.select_page(list.stated(Changed,unpublished_chip.label()),1)" ],
                   [ "post-1", %w[status-scheduled], hidden, "list.select_post(list.stated(Soon,labels.scheduled()),6)" ],
                   [ "post-2", %w[status-scheduled unpublished], hidden, "list.select_post(list.stated(list.stated(Soon changed,labels.scheduled()),unpublished_chip.label()),5)" ],
                   [ "post-3", [], "-", "list.select_post(Live,4)" ],
                   [ "post-4", [], "-", "list.select_post(Later,3)" ],
                   [ "post-5", %w[unpublished], hidden, "list.select_post(list.stated(Later changed,unpublished_chip.label()),2)" ],
                   [ "tag-1", [], "-", "list.select_tag(tag,2)" ], [ "type-blog", [], "-", "list.select_type(Blog,3)" ],
                   [ "more-type-blog", [], "-", "list.more_row(3,3,Blog,+3 more)" ] ], result["rows"],
      "the posts list's chips after the title, hidden, each word said after the title in the name; a live row, a scheduled change without the mark, a tag, a type and a pill have none"
  end

  # The name as a screen reader hears it, in the locale file's own words.
  test "list: a row's name says its state in the chips' own words" do
    words = { "mind_graph.script.list.stated" => "%{title}, %{state}", "mind_graph.script.list.select_post" => I18n.t("admin.mind_graph.script.list.select_post.other"),
              "mind_graph.script.list.add_post" => I18n.t("admin.mind_graph.script.list.add_post"), "mind_graph.script.list.not_in_view" => I18n.t("admin.mind_graph.script.list.not_in_view"),
              "components.ui.status_chip.labels.draft" => I18n.t("admin.components.ui.status_chip.labels.draft"),
              "components.ui.status_chip.labels.scheduled" => I18n.t("admin.components.ui.status_chip.labels.scheduled"),
              "components.ui.unpublished_chip.label" => I18n.t("admin.components.ui.unpublished_chip.label") }
    result = js_module("mind_graph/node_list", <<~JS, also: PARTS)
      (() => {
        const words = #{words.to_json}
        const text = { t: (key, values = {}) => Object.entries(values).reduce((said, [ name, value ]) => said.split(`%{${name}}`).join(value), words[key] ?? `missing ${key}`), locale: () => "en" }
        const container = document.createElement("div")
        const list = m.createList(container, { text, treeClasses: #{TREE_CLASSES}, dotClasses: Array(12).fill("dot"), typeLabels: { blog: "Blog" }, parts: p.readParts(document.body), unlisted: false, onSelect() {}, onHover() {}, onAdd() {}, onUnlisted() {} })
        const post = { kind: "post", degree: 2, colour_index: 1, type: "blog", changes: null }
        list.showRows({ heading: "Posts", rows: [ { ...post, id: "post-1", title: "Alpha", status: "draft", unpublished: false }, { ...post, id: "post-2", title: "Beta", status: "scheduled", unpublished: true },
                                                  { ...post, id: "post-3", title: "Gamma", status: "live", changes: "unpublished", unpublished: true } ], inView: (id) => id !== "post-3" })
        return Array.from(container.querySelectorAll("button[data-node-id]"), (button) => button.getAttribute("aria-label"))
      })()
    JS

    assert_equal [ "Alpha, Draft: post, 2 connections. Shows it in the graph.", "Beta, Scheduled, Unpublished changes: post, 2 connections. Shows it in the graph.",
                   "Gamma, Unpublished changes, blog post, not in view. Activate to add it to the graph." ], result
  end

  test "list: a row that is not in view is named with its type and asks to be added, one in view selects, and the checkbox reports its change" do
    result = js_module("mind_graph/node_list", <<~JS, also: PARTS)
      (() => {
        const { container, calls, list, read } = #{LIST_SCRIPT}
        document.body.append(container) // a checkbox outside the document changes without saying so
        list.showRows({ heading: "Posts · 3", rows: [ { id: "post-1", title: "Drawn", degree: 3, colour_index: 1, type: "blog" }, { id: "post-2", title: "<b>Absent</b>", degree: 0, colour_index: 1, type: "blog" },
                                                      { id: "post-3", title: "Old", degree: 0, colour_index: null, type: "<i>Gone</i>" } ],
                        inView: (id) => id === "post-1", link: { href: "/posts?type=blog", label: "Open in Posts" } })
        const rows = read()
        const absent = Array.from(container.querySelectorAll("button[data-not-in-view]"), (button) => button.dataset.nodeId)
        container.querySelectorAll("button").forEach((button) => button.click())
        const box = container.querySelector("input[type=checkbox]")
        box.click()
        const link = container.querySelector("a[data-mind-graph-posts-link]")
        const result = { rows, calls, absent, link: [ link.getAttribute("href"), link.textContent ], markup: container.querySelectorAll("b, i").length, checked: box.checked, label: box.closest("label").textContent }
        container.remove()
        return result
      })()
    JS

    assert_equal [ "Posts · 3", [ "Drawn", "3", 0, "list.select_post(Drawn,3)" ], [ "<b>Absent</b>", "list.not_in_view()", 0, "list.add_post(<b>Absent</b>,blog)" ],
                   [ "Old", "list.not_in_view()", 0, "list.add_retired_post(Old,<i>gone</i>)" ] ], result["rows"],
      "the type's label in lower case, and for a retired type its stored name in lower case in its own sentence: never a bare 'post'"
    assert_equal %w[post-2 post-3], result["absent"]
    assert_equal [ [ "select", "post-1" ], [ "add", "post-2" ], [ "add", "post-3" ], [ "unlisted", true ] ], result["calls"]
    assert_equal [ [ "/posts?type=blog", "Open in Posts" ], 0, true, "list.unlisted()" ], result.values_at("link", "markup", "checked", "label")
  end

  # A row is offered as one that adds only while there is a graph to add to:
  # while the graph is being read, or after its read failed, a row that is
  # not in view says so and no more, and a press on it does nothing.
  test "list: without a graph a row that is not in view is named without the add, is marked as doing nothing and asks for nothing, and drawn again with a graph it adds" do
    result = js_module("mind_graph/node_list", <<~JS, also: PARTS)
      (() => {
        const { container, calls, list } = #{LIST_SCRIPT}
        document.body.append(container)
        const rows = [ { id: "post-2", title: "Absent", degree: 0, colour_index: 1, type: "blog" }, { id: "post-3", title: "Old", degree: 0, colour_index: null, type: "Gone" } ]
        const read = () => Array.from(container.querySelectorAll("button[data-node-id]"), (button) => [ button.getAttribute("aria-label"), button.hasAttribute("data-not-in-view"), button.getAttribute("aria-disabled") ?? "-", button.lastChild.textContent ])
        list.showRows({ heading: "Posts · 2", rows, inView: () => false, addable: false })
        const without = read()
        container.querySelectorAll("button[data-node-id]").forEach((button) => button.click())
        const pressed = calls.slice()
        list.showRows({ heading: "Posts · 2", rows, inView: () => false })
        const withGraph = read()
        container.querySelectorAll("button[data-node-id]").forEach((button) => button.click())
        container.remove()
        return { without, pressed, withGraph, calls }
      })()
    JS

    assert_equal [ [ "list.absent_post(Absent,blog)", true, "true", "list.not_in_view()" ], [ "list.absent_retired_post(Old,gone)", true, "true", "list.not_in_view()" ] ], result["without"]
    assert_equal [], result["pressed"], "a press asks the app for nothing: not to add, not to select"
    assert_equal [ [ "list.add_post(Absent,blog)", true, "-", "list.not_in_view()" ], [ "list.add_retired_post(Old,gone)", true, "-", "list.not_in_view()" ] ], result["withGraph"]
    assert_equal [ [ "add", "post-2" ], [ "add", "post-3" ] ], result["calls"]
  end

  # The error line is in the list, with a small button.
  test "list: a failed read says so in the list with Try again, and pressing it asks again" do
    result = js_module("mind_graph/node_list", <<~JS, also: PARTS)
      (() => {
        const { container, list } = #{LIST_SCRIPT}
        document.body.append(container)
        let asked = 0
        list.fail("The list couldn't be loaded.", { label: "Try again", onRetry: () => { asked += 1 }, focus: true })
        const button = container.querySelector("[role=alert] button[data-mind-graph-retry]")
        const said = [ container.querySelector("[role=alert] p").textContent, button.textContent, button.type, button.className, document.activeElement === button, container.querySelectorAll("button[data-node-id]").length ]
        button.click()
        button.click()
        const checkbox = Boolean(container.querySelector("input[type=checkbox]"))
        // The rows the retry brought: the button that had the focus is gone, and the first row takes it.
        list.showRows({ heading: "Posts", rows: [ { id: "post-1", title: "One", degree: 0, type: "blog" } ], inView: () => false })
        const focused = document.activeElement?.dataset.nodeId
        container.remove()
        return { said, asked, checkbox, focused }
      })()
    JS

    assert_equal [ "The list couldn't be loaded.", "Try again", "button", "retry", true, 0 ], result["said"]
    assert_equal [ 2, true, "post-1" ], result.values_at("asked", "checkbox", "focused"), "the checkbox above the rows is still there, and the focus goes to the first row once there is one"
  end

  # The keyboard is never left on nothing: the rows are replaced whenever
  # what is in view changes, and a person may be on one of them.
  test "list: rows drawn again keep the focus on the row of the same node, else on the first row, else on the checkbox, and take none from elsewhere" do
    result = js_module("mind_graph/node_list", <<~JS, also: PARTS)
      (() => {
        const { container, list } = #{LIST_SCRIPT}
        document.body.append(container)
        const posts = [ { id: "post-1", title: "One", degree: 0, type: "blog" }, { id: "post-2", title: "Two", degree: 0, type: "blog" } ]
        const focused = () => document.activeElement === document.body ? "body" : document.activeElement.dataset.nodeId ?? document.activeElement.type
        const seen = []
        list.showRows({ heading: "Posts", rows: posts, inView: () => false })
        seen.push(focused())                                   // nobody was in the list: nothing takes the focus
        list.row("post-2").focus()
        const before = list.row("post-2")
        list.showRows({ heading: "Posts", rows: posts, inView: () => true })
        seen.push([ focused(), list.row("post-2") !== before ]) // the same node's NEW row
        list.showRows({ heading: "Posts", rows: posts.slice(0, 1), inView: () => true })
        seen.push(focused())                                   // its row is gone: the first row
        list.showRows({ heading: "Posts", rows: [], inView: () => true })
        seen.push(focused())                                   // no row at all: the checkbox
        list.render([ { id: "tag-1", kind: "tag", title: "tag", degree: 2 } ])
        seen.push(focused())                                   // the checkbox is not part of the rows: it keeps the focus
        container.remove()
        return seen
      })()
    JS

    assert_equal [ "body", [ "post-2", true ], "post-1", "checkbox", "checkbox" ], result
  end

  # A viewer who reads no page is told every post is unlisted (the server
  # counts by the pages THEY read), so the filter is not offered to them.
  test "list: without the unlisted read there is no checkbox, and the rows are all there is" do
    result = js_module("mind_graph/node_list", <<~JS, also: PARTS)
      (() => {
        const container = document.createElement("div")
        const text = { t: (key) => key, locale: () => "en" }
        const list = m.createList(container, { text, treeClasses: #{TREE_CLASSES}, dotClasses: [], parts: p.readParts(document.body), unlisted: false, onSelect() {}, onHover() {}, onAdd() {}, onUnlisted() {} })
        list.render([ { id: "tag-1", kind: "tag", title: "tag", degree: 2 } ])
        list.setUnlisted(true)
        return [ container.querySelectorAll("input, label").length, container.querySelectorAll("button[data-node-id]").length ]
      })()
    JS

    assert_equal [ 0, 1 ], result
  end

  # A keyboard or screen-reader user reaches a
  # pill's rows. Each pill has a row in the list, in the pill's own words,
  # under the row of what it hangs off; activating it asks the app for the
  # pill's rows, as a press on the pill does.
  test "list: each pill has a row after the row of what it hangs off, in the pill's own words and named whole, pressing it asks for its rows, and one whose hub has no row stands after the posts" do
    result = js_module("mind_graph/node_list", <<~JS, also: PARTS)
      (() => {
        const container = document.createElement("div")
        const calls = []
        const text = { t: (key, values = {}) => `${key.split(".").slice(-2).join(".")}(${Object.values(values).join(",")})`, locale: () => "en" }
        const list = m.createList(container, { text, treeClasses: #{TREE_CLASSES}, dotClasses: Array(12).fill("dot"), parts: p.readParts(document.body), number: (value) => "n" + value, onSelect: (id) => calls.push([ "select", id ]), onHover: (id) => calls.push([ "hover", id ]),
                                               onAdd() {}, onUnlisted() {}, onMore: (id) => calls.push([ "more", id ]), onBack() {} })
        document.body.append(container)
        const order = () => Array.from(container.querySelectorAll("h2, button[data-node-id]"), (item) => item.tagName === "H2" ? item.textContent : item.dataset.nodeId)
        const nodes = [ { id: "page-1", kind: "page", title: "Blog", degree: 1, depth: 0, order: 0, parent: null }, { id: "post-1", kind: "post", title: "Post", degree: 1, colour_index: 1 },
                        { id: "tag-5", kind: "tag", title: "<b>pill</b>", degree: 6 }, { id: "tag-6", kind: "tag", title: "other", degree: 9 },
                        { id: "type-blog", kind: "type", title: "Blog post", degree: 2, count: 30, colour_index: 1 }, { id: "all-posts", kind: "type", title: "All posts", degree: 1, count: 40, colour_index: null },
                        { id: "more-tag-5", kind: "more", title: "+1 more", count: 1, target: "tag-5", of: "<b>pill</b>" },
                        { id: "more-type-blog", kind: "more", title: "+1,980 more", count: 1980, target: "type-blog", of: "Blog post" } ]
        list.render(nodes)
        const all = order()
        const pill = list.row("more-type-blog")
        const row = [ pill.tagName, pill.type, pill.textContent, pill.getAttribute("aria-label"), pill.hasAttribute("data-more"), pill.hasAttribute("data-not-in-view"), pill.querySelectorAll("b").length,
                      list.row("more-tag-5").getAttribute("aria-label"), container.querySelectorAll("b").length ]
        pill.dispatchEvent(new PointerEvent("pointerover", { bubbles: true }))
        pill.click()
        list.row("type-blog").click()
        // "Post types" is switched off: the hub has no row, the pill is still drawn.
        list.render(nodes.filter((node) => node.kind !== "type"))
        const hubless = order()
        list.render(nodes.filter((node) => node.kind === "more" || node.kind === "page"))
        const postless = order()
        container.remove()
        return { all, row, calls, hubless, postless }
      })()
    JS

    assert_equal [ "list.pages(1)", "page-1", "list.posts(1)", "post-1", "list.tags(2)", "tag-6", "tag-5", "more-tag-5", "list.types(2)", "type-blog", "more-type-blog", "all-posts" ], result["all"],
      "a pill's row follows the row of the hub or the tag it hangs off, and is counted in no heading"
    assert_equal [ "BUTTON", "button", "+1,980 more", "list.more_row(1980,n1980,Blog post,+1,980 more)", true, false, 0, "list.more_row(1,n1,<b>pill</b>,+1 more)", 0 ], result["row"],
      "its visible words are the pill's own, its name says how many posts of what, and a tag's name in it is text"
    assert_equal [ [ "hover", "more-type-blog" ], [ "more", "more-type-blog" ], [ "select", "type-blog" ] ], result["calls"], "hovering it lights the pill, pressing it asks for its rows and selects nothing"
    assert_equal [ "list.pages(1)", "page-1", "list.posts(1)", "post-1", "more-type-blog", "list.tags(2)", "tag-6", "tag-5", "more-tag-5" ], result["hubless"], "a pill whose hub has no row stands at the end of the posts"
    assert_equal [ "list.pages(1)", "page-1", "more-tag-5", "more-type-blog" ], result["postless"], "and with no post drawn either, after the groups: never without a row"
  end

  # A pill's rows stand under a heading that
  # names them, with "Back to the list" on screen; Escape pressed in the rows
  # goes back too; and a pill's read that failed offers the same way back
  # beside "Try again". The rows of "Not listed on any page" have neither:
  # their checkbox is the way back.
  test "list: a pill's rows have a heading with Back to the list, Escape in the rows goes back, a failed read of a pill offers the way back, and the unlisted rows have none" do
    result = js_module("mind_graph/node_list", <<~JS, also: PARTS)
      (() => {
        const container = document.createElement("div")
        const calls = []
        const text = { t: (key) => key.split(".").slice(-2).join("."), locale: () => "en" }
        const list = m.createList(container, { text, treeClasses: #{TREE_CLASSES}, dotClasses: Array(12).fill("dot"), typeLabels: { blog: "Blog" }, retryClass: "retry", parts: p.readParts(document.body), onSelect() {}, onHover() {}, onAdd() {}, onUnlisted() {}, onMore() {} })
        document.body.append(container)
        const back = { label: "Back to the list", onBack: () => calls.push("back") }
        const rows = [ { id: "post-1", title: "One", degree: 0, type: "blog" }, { id: "post-2", title: "Two", degree: 0, type: "blog" } ]
        const key = (target, more = {}) => target.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true, ...more }))
        const stops = () => Array.from(container.querySelectorAll("h2, button, a"), (item) => item.tagName === "H2" ? item.textContent : item.dataset.nodeId ?? item.textContent)

        list.showRows({ heading: "More from Blog · 2", rows, inView: () => false, link: { href: "/posts", label: "Open in Posts" }, back })
        const pill = stops()
        const button = container.querySelector("button[data-mind-graph-back]")
        const control = [ button.type, button.textContent, container.querySelector("section").contains(button), button.compareDocumentPosition(list.row("post-1")) & Node.DOCUMENT_POSITION_FOLLOWING ? "before the rows" : "after" ]
        button.click()
        const unhandled = key(list.row("post-2"))
        key(list.row("post-1"), { ctrlKey: true })
        key(container.querySelector("input[type=checkbox]"))

        list.showRows({ heading: "Posts · 2", rows, inView: () => false })
        const unlisted = stops()
        const kept = key(list.row("post-1"))

        list.row("post-1").focus()
        list.fail("The list couldn't be loaded.", { label: "Try again", onRetry: () => calls.push("retry"), back })
        const failed = [ stops(), document.activeElement?.textContent ]
        key(container.querySelector("[data-mind-graph-retry]"))
        container.querySelector("[role=alert] button[data-mind-graph-back]").click()
        list.fail("The list couldn't be loaded.", { label: "Try again", onRetry() {} })
        const plain = stops()
        list.render([ { id: "tag-1", kind: "tag", title: "tag", degree: 2 } ])
        const groups = key(list.row("tag-1"))
        container.remove()
        return { pill, control, unhandled, unlisted, kept, failed, plain, groups, calls }
      })()
    JS

    assert_equal [ "More from Blog · 2", "Back to the list", "post-1", "post-2", "Open in Posts" ], result["pill"], "the heading, the way back, the rows, then the way to Posts"
    assert_equal [ "button", "Back to the list", true, "before the rows" ], result["control"]
    assert_equal [ "Posts · 2", "post-1", "post-2" ], result["unlisted"], "the rows of the checkbox's filter have no such button"
    assert_equal [ [ "Try again", "Back to the list" ], "Try again" ], result["failed"], "the error line keeps a way back, and the focus that was in the rows is on Try again, not on nothing"
    assert_equal [ "Try again" ], result["plain"], "a failed read of the unlisted posts has Try again alone: its checkbox is the way back"
    assert_equal %w[back back back back], result["calls"], "the button, Escape in a pill's rows, Escape on the error line of a pill's read, and the button there; never Escape with a modifier, on the checkbox, in the unlisted rows or in the groups"
    assert_equal [ false, true, true ], result.values_at("unhandled", "kept", "groups"), "Escape is taken (prevented) only where it goes back"
  end
end
