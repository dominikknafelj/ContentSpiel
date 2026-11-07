require "application_system_test_case"

# The data modules: `graph_data` and `summary`.
class Admin::MindGraphDataModulesSystemTest < Admin::MindGraphModulesSystemTestCase
  GRAPH_DATA = <<~JS.freeze
    (() => {
      const nodes = [ { kind: "page", home: true, depth: 0, degree: 2 }, { kind: "page", depth: 1, degree: 2 }, { kind: "post", degree: 2 }, { kind: "post", degree: 2 },
                      { kind: "tag", degree: 2 }, { kind: "type", degree: 1 }, { kind: "more", degree: 1 } ]
      const edges = [ { kind: "tree", source: 1, target: 0 }, { kind: "lists", source: 1, target: 5 }, { kind: "brings", source: 5, target: 6 },
                      { kind: "related", source: 2, target: 3 }, { kind: "tag", source: 2, target: 4 }, { kind: "tag", source: 3, target: 4 }, { kind: "brings", source: 5, target: 2 } ]
      const all = { nodes: [ "page", "post", "tag", "type" ], lines: [ "tree", "lists", "related", "tag" ] }
      const shown = (off) => {
        const on = { nodes: new Set(all.nodes.filter((name) => !off.includes(name))), lines: new Set(all.lines.filter((name) => !off.includes(`line-${name}`))) }
        const result = m.visible({ nodes, edges, on })
        return [ result.visibleNodes, result.visibleEdges ]
      }
      const labelled = m.visible({ nodes, edges, on: { nodes: new Set([ "page", "post", "type" ]), lines: new Set(all.lines) } })
      return { everything: shown([]), noRelated: shown([ "line-related" ]), noTagLines: shown([ "line-tag" ]), noLists: shown([ "line-lists" ]), noTree: shown([ "line-tree" ]), noTags: shown([ "tag" ]),
               noTypes: shown([ "type" ]), noPages: shown([ "page" ]), noPosts: shown([ "post" ]), nothing: shown(all.nodes), noLines: shown(all.lines.map((name) => `line-${name}`)),
               order: labelled.order, free: Array.from(labelled.free), counts: m.counts(nodes, edges), toggles: [ m.NODE_TOGGLES, m.LINE_TOGGLES ] }
    })()
  JS

  # THE WHOLE MATRIX: every combination of the four kinds and the four kinds
  # of line, 256 of them, each held to the rule in the test's own words
  # (worked out in the page, in one call; the answer is the combinations
  # that broke a rule, with which). The site has every kind of node and of
  # line, a pill and both of a hub's faint lines, and Home.
  MATRIX = <<~JS.freeze
    (() => {
      const nodes = [ { id: "page-1", kind: "page", home: true, depth: 0 }, { id: "page-2", kind: "page", depth: 1 }, { id: "post-1", kind: "post" }, { id: "post-2", kind: "post" },
                      { id: "tag-1", kind: "tag" }, { id: "type-blog", kind: "type" }, { id: "more-type-blog", kind: "more" } ]
      const edges = [ { kind: "tree", source: 1, target: 0 }, { kind: "lists", source: 1, target: 5 }, { kind: "lists", source: 1, target: 4 }, { kind: "brings", source: 5, target: 6 },
                      { kind: "related", source: 2, target: 3 }, { kind: "tag", source: 2, target: 4 }, { kind: "tag", source: 3, target: 4 }, { kind: "brings", source: 5, target: 2 } ]
      const kinds = [ "page", "post", "tag", "type" ], lines = [ "tree", "lists", "related", "tag" ]
      const toggle = (node) => (node.kind === "more" ? "post" : node.kind)
      const lineToggle = (edge) => (edge.kind === "brings" ? "lists" : edge.kind)
      const held = JSON.stringify(m.counts(nodes, edges))
      const before = JSON.stringify([ nodes, edges ])
      const broken = []
      let combinations = 0
      for (let bits = 0; bits < 256; bits += 1) {
        combinations += 1
        const on = { nodes: new Set(kinds.filter((_, index) => bits & (1 << index))), lines: new Set(lines.filter((_, index) => bits & (16 << index))) }
        const shown = m.visible({ nodes, edges, on })
        const said = (what) => broken.push([ bits, what ])
        const drawn = new Set(shown.visibleNodes)
        nodes.forEach((node, index) => { if (drawn.has(index) !== on.nodes.has(toggle(node))) said(`node ${node.id}`) })
        edges.forEach((edge, index) => {
          const expected = on.lines.has(lineToggle(edge)) && on.nodes.has(toggle(nodes[edge.source])) && on.nodes.has(toggle(nodes[edge.target]))
          if (shown.visibleEdges.includes(index) !== expected) said(`edge ${index}`)
        })
        if (shown.visibleEdges.some((index) => !drawn.has(edges[index].source) || !drawn.has(edges[index].target))) said("a line to a hidden node")
        if (JSON.stringify(m.counts(nodes, edges)) !== held) said("the counts moved")
        if (JSON.stringify([ nodes, edges ]) !== before) said("the data was changed")
        if (m.anchorOf({ pages: nodes.filter((node) => node.kind === "page") }) !== "page-1") said("the anchor")
        if (drawn.has(0) !== on.nodes.has("page")) said("Home")
        if (shown.order.some((index) => !drawn.has(index)) || Array.from(shown.free).some((index) => !drawn.has(index))) said("a label for a hidden node")
        if (shown.order.includes(6)) said("the pill has a label")
      }
      return { combinations, broken }
    })()
  JS

  WHOLE = { shown: 13, total: 13 }.freeze

  test "graph data: the payload becomes nodes of five kinds, All posts, more and a retired type named by the page's own words" do
    nodes = js_module("mind_graph/graph_data", <<~JS)
      m.nodesOf({ nodes: [ { id: "post-1", title: "P" } ], tags: [ { id: "tag-1", name: "t" } ], pages: [ { id: "page-1", title: "Home", home: true } ],
                  types: [ { id: "all-posts", label: null, colour_index: null }, { id: "type-blog", label: "Blog", colour_index: 1 }, { id: "type-gone/thing", label: "gone/thing", colour_index: null } ],
                  more: [ { id: "more-type-blog", count: 3, page: "page-1", target: "type-blog" }, { id: "more-tag-1", count: 1980, page: "page-1", target: "tag-1" } ] },
                { allPosts: "All posts", more: (count) => `+${count} more`, retired: (name) => `${name} (retired)` }).map((node) => [ node.id, node.kind, node.title ])
    JS

    assert_equal [ [ "page-1", "page", "Home" ], [ "post-1", "post", "P" ], [ "tag-1", "tag", "t" ], [ "all-posts", "type", "All posts" ],
                   [ "type-blog", "type", "Blog" ], [ "type-gone/thing", "type", "gone/thing (retired)" ], [ "more-type-blog", "more", "+3 more" ], [ "more-tag-1", "more", "+1980 more" ] ], nodes,
      "a pill per target; the figure's separator is the caller's (`more`), which the app gives it"
    assert_equal [ "post-1" ], js_module("mind_graph/graph_data", 'm.nodesOf({ nodes: [ { id: "post-1", title: "P" } ], tags: [], edges: [] }, {}).map((node) => node.id)'),
      "a payload without pages, types or more is the graph of posts and tags"
  end

  test "graph data: labels go to Home, then top-level pages and type nodes, then hubs, a page ahead of a post with as many links" do
    order = js_module("mind_graph/graph_data", <<~JS)
      (() => {
        const nodes = [ { kind: "post", degree: 9 }, { kind: "page", depth: 2, degree: 3 }, { kind: "post", degree: 3 }, { kind: "type", degree: 1 },
                        { kind: "page", depth: 1, degree: 1 }, { kind: "page", depth: 0, home: true, degree: 0 }, { kind: "tag", degree: 4 }, { kind: "more", degree: 1 } ]
        const all = nodes.map((_, index) => index)
        return { order: m.orderOf(nodes, all), free: Array.from(m.freeOf(nodes, all)).sort(), some: m.orderOf(nodes, [ 2, 1 ]) }
      })()
    JS

    assert_equal [ 5, 4, 3, 0, 6, 1, 2 ], order["order"], "Home; the top-level page ahead of the type by its bonus; then by links, the page of three ahead of the post of three; the pill has its words in it and is never labelled"
    assert_equal [ 3, 4, 5 ], order["free"]
    assert_equal [ 1, 2 ], order["some"]
  end

  # Which node the layout holds at the centre: Home in the whole graph, the
  # focus in a local view, where Home, if it
  # is drawn, is a page like any other.
  test "graph data: the anchor is Home in the whole graph and the focus in a local view, of whatever kind" do
    anchors = js_module("mind_graph/graph_data", <<~JS)
      (() => {
        const pages = [ { id: "page-2", home: false }, { id: "page-1", home: true } ]
        const whole = { nodes: [], tags: [], pages }
        return [ m.anchorOf(whole), m.anchorOf({ nodes: [], tags: [], pages: [ pages[0] ] }), m.anchorOf({ nodes: [], tags: [] }),
                 m.anchorOf({ ...whole, focus: { node_id: "page-2" } }), m.anchorOf({ ...whole, focus: { node_id: "post-9" } }), m.anchorOf({ ...whole, focus: { node_id: "tag-3" } }),
                 m.anchorOf({ ...whole, focus: { node_id: "page-1" } }) ].map((id) => id ?? "none")
      })()
    JS

    assert_equal %w[page-1 none none page-2 post-9 tag-3 page-1], anchors
  end

  test "graph data: a line switched off hides only the lines, and a kind switched off hides its nodes and every line that touches one" do
    shown = js_module("mind_graph/graph_data", GRAPH_DATA)

    assert_equal [ (0..6).to_a, (0..6).to_a ], shown["everything"]
    assert_equal [ (0..6).to_a, [ 0, 1, 2, 4, 5, 6 ] ], shown["noRelated"], "every node stays"
    assert_equal [ (0..6).to_a, [ 0, 1, 2, 3, 6 ] ], shown["noTagLines"], "the tag stays, without its lines"
    assert_equal [ (0..6).to_a, [ 0, 3, 4, 5 ] ], shown["noLists"], "a hub's faint lines to its posts and to the pill go with Lists: they have no toggle of their own"
    assert_equal [ (0..6).to_a, [ 1, 2, 3, 4, 5, 6 ] ], shown["noTree"], "Home stays, without its line"
    assert_equal [ [ 0, 1, 2, 3, 5, 6 ], [ 0, 1, 2, 3, 6 ] ], shown["noTags"]
    assert_equal [ [ 0, 1, 2, 3, 4, 6 ], [ 0, 3, 4, 5 ] ], shown["noTypes"], "the type, the lists line that points at it and its faint lines; the pill stays, loose"
    assert_equal [ [ 2, 3, 4, 5, 6 ], [ 2, 3, 4, 5, 6 ] ], shown["noPages"]
    assert_equal [ [ 0, 1, 4, 5 ], [ 0, 1 ] ], shown["noPosts"], "more goes with the posts"
    assert_equal [ [], [] ], shown["nothing"]
    assert_equal [ (0..6).to_a, [] ], shown["noLines"], "with every line off every node is still there"
  end

  test "graph data: over every combination of the four kinds and the four kinds of line a hidden kind's nodes and lines are gone, a line needs both its ends and its own kind, the counts and the anchor stay" do
    result = js_module("mind_graph/graph_data", MATRIX)

    assert_equal 256, result["combinations"]
    assert_equal [], result["broken"].first(5), "#{result["broken"].size} combinations broke a rule (bits: page, post, tag, type, then tree, lists, related, tag)"
  end

  test "graph data: what is shown comes with the order of its labels and the free set, and the pill has no label" do
    shown = js_module("mind_graph/graph_data", GRAPH_DATA)

    assert_equal [ 0, 1, 5, 2, 3 ], shown["order"], "Home, the top-level page and the type, then the posts; no tag (it is off) and no pill"
    assert_equal [ 0, 1, 5 ], shown["free"].sort
  end

  test "graph data: the counts are what the response holds, whatever is switched off, and a hub's faint lines are no Lists lines" do
    data = js_module("mind_graph/graph_data", GRAPH_DATA)

    assert_equal({ "nodes" => { "page" => 2, "post" => 2, "tag" => 1, "type" => 1 }, "lines" => { "tree" => 1, "lists" => 1, "related" => 1, "tag" => 2 } }, data["counts"])
    assert_equal [ Admin::MindGraphScreen::LegendComponent::NODES.map(&:to_s), Admin::MindGraphScreen::LegendComponent::LINES.map(&:to_s) ], data["toggles"],
      "the script's toggles are the legend's, in its order"
  end

  test "summary: the whole graph says its counts by type, its connections and Showing everything, in the designer's words" do
    whole, small, pair, capped = summaries(
      { nodes: node_set(pages: 9, types: 3, posts: 13, tags: 4), lines: 27, data: WHOLE },
      { nodes: node_set(pages: 1, types: 1, posts: 1, tags: 1), lines: 1, data: WHOLE },
      { nodes: node_set(posts: 2040, tags: 2), lines: 0, data: { shown: 2040, total: 2040 } },
      { nodes: node_set(pages: 212, posts: 2000, tags: 64), lines: 3000, data: { shown: 2000, total: 2040 } }
    )

    assert_equal "Mind graph: 9 pages, 3 post types, 13 posts and 4 tags, 27 connections. Showing everything.", whole
    assert_equal "Mind graph: 1 page, 1 post type, 1 post and 1 tag, 1 connection. Showing everything.", small, "each count in its singular"
    assert_equal "Mind graph: 2,040 posts and 2 tags, 0 connections. Showing everything.", pair, "a kind with nothing in view is left out, and a figure is grouped"
    assert_equal "Mind graph: 212 pages, 2,000 posts and 64 tags, 3,000 connections. Showing the 2,000 best-connected of 2,040 posts.", capped
    assert_not_includes capped, "Showing everything", "never at the cap (H5)"
  end

  test "summary: a local view names its focus and depth, a page that lists more says N of M posts and how many more are in the list" do
    focus = { focus: { kind: "page", node_id: "page-1", title: "Blog", depth: 2 }, shown: 20, total: 20 }
    blog, pills, one, alone, post = summaries(
      { nodes: node_set(pages: 7, types: 1, posts: 20, more: [ 92 ], focus: { listed_count: 112 }), lines: 30, data: focus },
      { nodes: node_set(pages: 7, types: 1, posts: 20, tags: 1, more: [ 60, 32 ], focus: { listed_count: 112 }), lines: 30, data: focus },
      { nodes: node_set(pages: 1, types: 1, posts: 20, more: [ 1 ], focus: { listed_count: 21 }), lines: 30, data: focus },
      { nodes: node_set(pages: 1, focus: { listed_count: 0 }), lines: 0, data: { focus: { kind: "page", node_id: "page-1", title: "About", depth: 1 }, shown: 0, total: 0 } },
      { nodes: node_set(posts: 3, tags: 1), lines: 3, data: { focus: { kind: "post", node_id: "post-9", title: "Small sites", depth: 1 }, shown: 3, total: 3 } }
    )

    assert_equal "Mind graph around Blog, depth 2: 7 pages, 1 post type and 20 of 112 posts. 92 more are in the list.", blog
    assert_equal "Mind graph around Blog, depth 2: 7 pages, 1 post type, 20 of 112 posts and 1 tag. 92 more are in the list.", pills, "every pill in view counts together"
    assert_equal "Mind graph around Blog, depth 2: 1 page, 1 post type and 20 of 21 posts. 1 more is in the list.", one
    assert_equal "Mind graph around About, depth 1: 1 page.", alone, "depth 1 around a page draws no post, and is not nothing"
    assert_equal "Mind graph around Small sites, depth 1: 3 posts and 1 tag.", post
    [ blog, pills, one, alone, post ].each { |summary| assert_no_match(/Showing|nearest/, summary, "a local view names no cap and never says everything") }
  end

  test "summary: what is switched off is named after the scope, kinds then lines, and with nothing in view it says why" do
    nodes = node_set(pages: 2, types: 1, posts: 3, tags: 1)
    without = ->(kinds) { nodes.each_index.reject { |index| kinds.include?(nodes[index][:kind]) } }
    tags, lines, both, all, none, pills = summaries(
      { nodes: nodes, visible: without.call(%w[tag]), lines: 3, data: WHOLE, off: { nodes: %w[tag], lines: [] } },
      { nodes: nodes, lines: 3, data: WHOLE, off: { nodes: [], lines: %w[tag] } },
      { nodes: nodes, visible: without.call(%w[page type]), lines: 1, data: WHOLE, off: { nodes: %w[page type], lines: %w[tree lists related] } },
      { nodes: nodes, visible: [], lines: 0, data: WHOLE, off: { nodes: %w[page post tag type], lines: %w[tag] } },
      { nodes: [], lines: 0, data: { shown: 0, total: 0 }, off: { nodes: %w[tag], lines: [] } },
      { nodes: node_set(pages: 2, types: 1, posts: 20, more: [ 92 ], focus: { listed_count: 112 }), visible: [ 0, 1, 22 ], lines: 2, off: { nodes: %w[post], lines: [] },
        data: { focus: { kind: "page", node_id: "page-1", title: "Blog", depth: 2 }, shown: 20, total: 20 } }
    )

    assert_equal "Mind graph: 2 pages, 1 post type and 3 posts, 3 connections. Showing everything. Tags hidden.", tags, "both, in that order: everything means no cap, not no filters"
    assert_equal "Mind graph: 2 pages, 1 post type, 3 posts and 1 tag, 3 connections. Showing everything. Shares-a-tag lines hidden.", lines
    assert_equal "Mind graph: 3 posts and 1 tag, 1 connection. Showing everything. Pages hidden. Post types hidden. Tree lines hidden. Lists lines hidden. Related lines hidden.", both
    assert_equal "Mind graph: nothing to show. All types are hidden.", all, "every kind is off: that is said once, and no line is named"
    assert_equal "Mind graph: nothing to show. No pages, posts or tags yet.", none, "nothing to draw: no toggle is named"
    assert_equal "Mind graph around Blog, depth 2: 2 pages and 1 post type. Posts hidden.", pills, "the pill goes with the posts: neither N of M nor more is said"
  end

  # of THEIRS. And the one case neither of the two sentences is
  # true of: nothing is drawn because no post has a connection. The summary
  # then says what the notice over the canvas says, in the notice's words,
  # so a screen reader does not hear "No pages, posts or tags yet." beside
  # "2 posts have no connections yet.".
  test "summary: with every toggle a viewer has switched off all types are hidden, and unconnected posts are not no posts" do
    posts = node_set(posts: 3, tags: 1)
    two_off, one_off, three_of_three, isolated, one_isolated, empty = summaries(
      { nodes: posts, visible: [], lines: 0, data: WHOLE, off: { nodes: %w[post tag], lines: [] }, toggles: 2 },
      { nodes: posts, visible: [ 3 ], lines: 0, data: WHOLE, off: { nodes: %w[post], lines: [] }, toggles: 2 },
      { nodes: node_set(pages: 2, tags: 1, types: 1), visible: [], lines: 0, data: WHOLE, off: { nodes: %w[page tag type], lines: %w[tree] }, toggles: 3 },
      { nodes: [], lines: 0, data: { shown: 0, total: 0, isolated: 2 } },
      { nodes: [], lines: 0, data: { shown: 0, total: 0, isolated: 1 }, off: { nodes: %w[tag], lines: [] } },
      { nodes: [], lines: 0, data: { shown: 0, total: 0, isolated: 0 } }
    )

    assert_equal "Mind graph: nothing to show. All types are hidden.", two_off
    assert_equal "Mind graph: 1 tag, 0 connections. Showing everything. Posts hidden.", one_off, "one of two is not all"
    assert_equal "Mind graph: nothing to show. All types are hidden.", three_of_three
    assert_equal "Mind graph: nothing to show. 2 posts have no connections yet.", isolated
    assert_equal "Mind graph: nothing to show. 1 post has no connections yet.", one_isolated
    assert_equal "Mind graph: nothing to show. No pages, posts or tags yet.", empty
  end

  test "summary: the view the 3,000-line rule opened says where it is and what the site holds, and no other view does" do
    home = { focus: { kind: "page", node_id: "page-1", title: "Home", depth: 1 }, shown: 0, total: 0, site: { pages: 212, posts: 2040, tags: 64 } }
    opened, plain, bare, tagless = summaries(
      { nodes: node_set(pages: 6, types: 2), lines: 7, data: home, around_home: true },
      { nodes: node_set(pages: 6, types: 2), lines: 7, data: home },
      { nodes: node_set(pages: 6, types: 2), lines: 7, data: home.except(:site), around_home: true },
      { nodes: node_set(pages: 6, types: 2), lines: 7, data: home.merge(site: { pages: 1, posts: 2040, tags: 0 }), around_home: true, off: { nodes: %w[tag], lines: [] } }
    )

    assert_equal "Mind graph around Home, depth 1: 6 pages and 2 post types. Showing the area around Home. The site has 212 pages, 2,040 posts and 64 tags.", opened
    assert_equal "Mind graph around Home, depth 1: 6 pages and 2 post types.", plain
    assert_equal plain, bare, "without the site's counts nothing is said of the site"
    assert_equal "Mind graph around Home, depth 1: 6 pages and 2 post types. Showing the area around Home. The site has 1 page and 2,040 posts. Tags hidden.", tagless
  end

  # AFTER A ROW IS ADDED THE FIGURES ARE TRUE. One source: what the
  # page holds. The pill's count falls by one for each of its posts that is
  # drawn, the pill goes at none, and the canvas's name, which reads the
  # pills in view, follows; a post no page lists that was counted as "not
  # shown" is not counted so any more.
  test "graph data: a post added from the list is counted where it was counted before: its pill's figure falls and the pill goes at none, the summary follows, and an unconnected post is no longer one that isn't shown" do
    focus = { kind: "page", node_id: "page-1", title: "Blog", depth: 2 }
    result = page.evaluate_async_script(<<~JS, focus)
      const [ focus, done ] = arguments
      Promise.all([ import("mind_graph/graph_data"), import("mind_graph/summary") ]).then(([ data, { summaryOf } ]) => {
        const text = { t: (key, values = {}) => `${key.split(".").pop()}(${Object.values(values).join(" ")})` }
        const nodes = [ { id: "page-1", kind: "page", listed_count: 23 }, ...Array.from({ length: 20 }, (_, index) => ({ id: `post-${index}`, kind: "post" })), { id: "type-a", kind: "type" }, { id: "tag-9", kind: "tag" },
                        { id: "more-type-a", kind: "more", count: 2, target: "type-a" }, { id: "more-tag-9", kind: "more", count: 1, target: "tag-9" } ]
        const local = { focus, shown: 20, total: 20 }
        const all = { nodes: new Set(data.NODE_TOGGLES), lines: new Set(data.LINE_TOGGLES) }
        const seen = []
        const look = () => {
          const { visibleNodes } = data.visible({ nodes, edges: [], on: all })
          seen.push([ nodes.filter((node) => node.kind === "more").map((pill) => pill.count), visibleNodes.map((index) => nodes[index].id).filter((id) => id.startsWith("more")),
                      summaryOf({ nodes, visibleNodes, lines: 0, data: local, off: { nodes: [], lines: [] }, toggles: 4 }, { text, number: String }) ])
        }
        const add = (row) => { const pill = data.countAdded(nodes, local, row); if (pill >= 0) nodes.push({ id: row.id, kind: "post" }); return pill }
        look()
        const pills = [ add({ id: "post-20", via: "type-a" }) ]
        look()
        pills.push(add({ id: "post-21", via: "type-a" }))
        look()
        pills.push(add({ id: "post-22", via: "tag-9" }))
        look()
        // No pill is left for that target, or the row names none: nothing to count down.
        pills.push(data.countAdded(nodes, local, { id: "post-23", via: "type-a" }), data.countAdded(nodes, local, { id: "post-24", via: "type-zzz" }), data.countAdded(nodes, local, { id: "post-25" }))

        // "N other posts have no connections yet and aren't shown." (the whole graph).
        // "N other posts have no connections yet and aren't shown." (the whole graph). A row of
        // "Not listed on any page" says whether its post is one of them (`unconnected`).
        const lone = (id) => ({ id, unconnected: true })
        const whole = { shown: 5, total: 5, isolated: 2 }
        const capped = { shown: 2000, total: 2040, isolated: 3 }
        const around = { focus, shown: 5, total: 5 }
        const isolated = [ data.countAdded([], whole, lone("post-1")), whole.isolated, data.countAdded([], whole, lone("post-2")), whole.isolated, data.countAdded([], whole, lone("post-3")), whole.isolated,
                           data.countAdded([], capped, { id: "post-4", unconnected: false }), capped.isolated, data.countAdded([], capped, { id: "post-5" }), capped.isolated,
                           data.countAdded([], capped, lone("post-6")), capped.isolated, data.countAdded([], around, lone("post-7")), around.isolated ?? "none" ]
        // "Showing the 2,000 best-connected of 2,040 posts.": a connected post the cut left out is one more shown.
        const cut = { shown: 2000, total: 2040, isolated: 3 }
        const uncut = { shown: 5, total: 5, isolated: 0 }
        const nearby = { focus, shown: 20, total: 40 }
        const shown = [ [ cut, { id: "post-1", unconnected: false } ], [ cut, lone("post-2") ], [ cut, { id: "post-3" } ], [ uncut, { id: "post-4", unconnected: false } ], [ nearby, { id: "post-5", unconnected: false } ] ]
          .map(([ held, row ]) => { data.countAdded([], held, row); return [ held.shown, held.isolated ?? "none" ] })
        // "N of M posts" is of the posts the page lists: one added from "Not listed on any page" is counted beside them.
        const listing = [ { id: "page-1", kind: "page", listed_count: 112 }, ...Array.from({ length: 20 }, (_, index) => ({ id: `post-${index}`, kind: "post", listed: true })), { id: "more-type-a", kind: "more", count: 92, target: "type-a" } ]
        const named = () => summaryOf({ nodes: listing, visibleNodes: listing.map((_, index) => index), lines: 0, data: { focus, shown: 20, total: 20 }, off: { nodes: [], lines: [] }, toggles: 4 }, { text, number: String })
        const before = named()
        // A post the view itself draws that no page lists (a related post) is counted as it was.
        listing[1].listed = false
        const drawn = named()
        listing[1].listed = true
        listing.push({ id: "post-900", kind: "post", listed: false, added: true })
        const beside = named()
        done({ seen, pills, isolated, shown, before, beside, drawn })
      }).catch((error) => done({ error: String(error) }))
    JS
    flunk result["error"] if result["error"]

    assert_equal [ [ [ 2, 1 ], %w[more-type-a more-tag-9], "more(3)" ],
                   [ [ 1, 1 ], %w[more-type-a more-tag-9], "more(2)" ],
                   [ [ 0, 1 ], %w[more-tag-9], "more(1)" ],
                   [ [ 0, 0 ], [], "" ] ], result["seen"].map { |counts, pills, summary| [ counts, pills, summary[/more\((\d+) \d+\)/].to_s.sub(/ \d+/, "") ] },
      "each pill counts what is still behind it, one that reaches none is not in view, and the summary says the sum of the pills in view"
    assert_equal [ "posts_of(20 20 23)", "posts_of(21 21 23)", "posts_of(22 22 23)", "posts(23 23 0)" ], result["seen"].map { |_counts, _pills, summary| summary[/posts(?:_of)?\([\d ]+\)/] },
      "N of M: N is the posts drawn, M what the page lists; with every pill gone the page lists no more than is drawn and the plain count is said"
    assert_equal [ 23, 23, 24, -1, -1, -1 ], result["pills"], "which pill was counted down (its index), and none for a row with no pill to count"
    assert_equal [ [ 2001, 3 ], [ 2001, 2 ], [ 2001, 2 ], [ 5, 0 ], [ 20, "none" ] ], result["shown"],
      "at the cap a connected post that is added is one more of those shown, and an unconnected one, and a row that says nothing, are not; with nothing cut, and in a local view, the figure stays"
    assert_match(/posts_of\(20 20 112\)/, result["before"])
    assert_no_match(/ posts\(/, result["before"].sub(/\Alocal\(/, ""), "with every post listed there is no second count")
    assert_match(/posts_of\(20 20 112\).*posts\(1 1\)/, result["beside"], "20 of 112 and 92 more still add up to 112: the unlisted post is counted beside them, and is counted")
    assert_match(/more\(92 92\)/, result["beside"])
    assert_equal result["before"], result["drawn"], "only a post the person added is counted apart: the sentence does not change where nothing was added"
    assert_equal [ -1, 1, -1, 0, -1, 0, -1, 3, -1, 3, -1, 2, -1, "none" ], result["isolated"],
      "a row that says its post has no connection takes one from those that aren't shown, never below none; one the cap cut, and one that says nothing, take none; at the cap an unconnected one still does; a local view counts none"
  end

  # A tick the worker posted before it took `add` is two numbers
  # short. The page keeps the place it gave the new node until the worker
  # answers for it: no node is ever without a position.
  test "graph data: positions that are short of the page's nodes keep the places the page holds for the rest, and whole ones are taken as they are" do
    result = js_module("mind_graph/graph_data", <<~JS)
      (() => {
        const held = Float32Array.from([ 1, 2, 3, 4, 30, 40 ])
        const short = Float32Array.from([ 10, 20, 11, 21 ])
        const whole = Float32Array.from([ 5, 6, 7, 8, 9, 10 ])
        const merged = m.placedFor(short, held, 3)
        const taken = m.placedFor(whole, held, 3)
        return { merged: Array.from(merged), finite: Array.from(merged).every(Number.isFinite), length: merged.length, same: taken === whole, none: Array.from(m.placedFor(new Float32Array(0), new Float32Array(0), 0)),
                 first: Array.from(m.placedFor(short, new Float32Array(0), 3)) }
      })()
    JS

    assert_equal [ [ 10, 20, 11, 21, 30, 40 ], true, 6, true, [] ], result.values_at("merged", "finite", "length", "same", "none"), "the worker's places for the nodes it knows, the page's own for the one it has not taken yet"
    assert_equal [ 10, 20, 11, 21, 0, 0 ], result["first"], "and where the page holds no place either, the centre: a number, never nothing"
  end
end
