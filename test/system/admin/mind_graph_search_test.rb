require "application_system_test_case"

class Admin::MindGraphSearchSystemTest < Admin::MindGraphSystemTestCase
  test "Focus opens that node's neighbourhood, the depth switch widens it, and Back returns" do
    a, b, c = %w[Alpha Beta Gamma].map { |title| create_post(title: title) }
    PostRelation.create!(post: a, related_post: b)
    PostRelation.create!(post: b, related_post: c)
    visit admin_mind_graph_path
    await_graph

    click_node(a)
    click_frame_link { within("[data-mind-graph-card]") { click_link "Focus" } }

    assert_selector "[data-mind-graph-focus]", text: "Around “Alpha”"
    await_graph
    assert_equal "2", graph["data-nodes"]
    # `data-settled` is written before the frame that writes `data-labelled`.
    assert await_js("(document.querySelector(#{GRAPH.to_json}).dataset.labelled || '').split(',').includes('#{nid(a)}')"), "the focus is always labelled"

    click_frame_link { within("[data-mind-graph-focus]") { click_link "2" } }
    await_graph
    assert_equal "3", graph["data-nodes"]

    page.go_back
    await_graph
    assert_equal "2", graph["data-nodes"]

    click_frame_link { within("[data-mind-graph-focus]") { click_link "Whole graph" } }
    assert_no_selector "[data-mind-graph-focus]"
    await_graph
    assert_equal "3", graph["data-nodes"]
  end


  # The column's find field narrows the list's tree, as the Pages tree's
  # does: the matches and the items above them stay, the matched words are
  # marked, and the canvas draws what it drew. While it narrows, the last
  # line offers the whole site.
  test "the find field narrows the list to the matches and their paths, and the graph is left as it is" do
    docs = create_page(title: "Docs")
    guide = create_page(title: "Guide", parent: docs)
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))
    open_branches(docs)
    visit_screen admin_mind_graph_path
    await_graph
    drawn = graph["data-nodes"]
    assert_selector SEARCH_SITE, visible: :hidden

    find(FIND).fill_in(with: "gui")

    within(LIST) do
      assert_selector "[role=treeitem][data-node-id='#{nid(guide)}'] > .admin-tree-row mark", text: "Gui"
      assert_selector "[role=treeitem][data-node-id='#{nid(docs)}']"
      assert_selector "[role=treeitem][data-node-id='#{nid(root_page)}']"
      assert_no_selector "[role=treeitem][data-node-id='#{nid(a)}']"
      assert_no_selector "[role=treeitem][data-tree-group='posts']"
    end
    assert_selector "#{SEARCH_SITE} button", text: "Search the whole site for “gui”"
    assert_selector "#tree-column [role=status]", text: "1 match"
    assert_equal drawn, graph["data-nodes"], "the find narrows the list, never the graph"
    assert_equal "", graph["data-selected"].to_s

    find(FIND).send_keys(:escape)

    assert_selector "#{LIST} [role=treeitem][data-node-id='#{nid(a)}']"
    assert_no_selector "#{LIST} mark"
    assert_selector SEARCH_SITE, visible: :hidden
  end

  test "the whole site's search finds a post the graph does not draw and opens its neighbourhood" do
    a = create_post(title: "Connected")
    PostRelation.create!(post: a, related_post: create_post(title: "Also connected"))
    alone = create_post(title: "Hidden gem")
    visit_screen admin_mind_graph_path
    await_graph
    assert_nil screen_position(alone)

    search_whole_site("hidden")
    click_frame_link { within(RESULTS) { click_link "Hidden gem" } }

    assert_selector "[data-mind-graph-focus]", text: "Around “Hidden gem”"
    await_graph
    assert_equal "1", graph["data-nodes"]
    assert_equal "", find(FIND).value, "a result is a visit of its own, whose column is drawn afresh"
  end

  # The results stand in the list's place: Back first, then their heading,
  # then a group each for pages, posts and tags, each row a link on the
  # tree row's geometry. Back and Escape give the tree back with the query
  # in the field and the focus on the last line.
  test "the whole site's results group pages, posts and tags, show a page's path, say when nothing matches, and Back and Escape return to the list with the query kept" do
    docs = create_page(title: "Ruby docs")
    create_post(title: "Ruby notes", tags: [ "ruby" ])
    create_post(title: "Other", tags: [ "ruby" ])
    visit_screen admin_mind_graph_path
    await_graph
    tree_row = page.evaluate_script("document.querySelector(#{"#{LIST} [role=treeitem][data-node-id] > .admin-tree-row".to_json}).getBoundingClientRect().height")

    search_whole_site("ruby")

    within(RESULTS) do
      assert_equal [ "div>button", "h2" ], page.evaluate_script("Array.from(document.querySelector(#{RESULTS.to_json}).children).slice(0, 2).map((child) => child.tagName === 'DIV' ? `div>${child.firstElementChild?.tagName.toLowerCase()}` : child.tagName.toLowerCase())")
      assert_selector "button[data-mind-graph-back]", exact_text: "Back to the list"
      assert_selector "h2", exact_text: "Whole site: “ruby”"
      assert_equal %w[PAGES POSTS TAGS], all("[data-search-group] > h3").map { |heading| heading.text.upcase }
      # A group's heading is the tree's: its kind's chip in the mark box.
      assert_selector "[data-search-group] > h3 > .admin-tree-row__mark > span[aria-hidden=true]", count: 3
      assert_selector "[data-search-group] ul[role=list][aria-labelledby]", count: 3
      path = PublicPath.current.where(record: docs).pick(:path)
      assert_selector "[data-search-group=page] a.admin-tree-row", text: "Ruby docs"
      assert_selector "[data-search-group=page] a span.text-small.text-meta", exact_text: path
      assert_no_match(/mono/i, find("[data-search-group=page] a span.text-small", exact_text: path).evaluate_script("getComputedStyle(this).fontFamily"), "a page's path is not drawn in mono")
      assert_selector "[data-search-group=post] a.admin-tree-row", text: "Ruby notes"
      assert_selector "[data-search-group=tag] a.admin-tree-row", exact_text: "ruby"
      # Each row's mark is decoration: the page glyph, the type's dot, the square.
      assert_selector "a > .admin-tree-row__mark > [aria-hidden='true']", count: 3
      assert_no_selector "[role=treeitem], [role=tree]"
    end
    post_row = page.evaluate_script("document.querySelector(#{"#{RESULTS} [data-search-group=post] a".to_json}).getBoundingClientRect().height")
    assert_in_delta tree_row, post_row, 0.5, "a result's row is not the tree's row"
    assert_no_selector "#{LIST} [role=tree]", visible: :visible
    assert_no_selector "#{LIST} input[data-mind-graph-unlisted]", visible: :visible
    assert_selector SEARCH_SITE, visible: :hidden
    assert page.evaluate_script("document.activeElement.matches('[data-mind-graph-back]')"), "Back does not have the focus"

    click_button "Back to the list"

    assert_selector "#{LIST} [role=tree]"
    assert_no_selector RESULTS, visible: :visible
    assert_equal "ruby", find(FIND).value
    assert page.evaluate_script("document.activeElement === document.querySelector(#{"#{SEARCH_SITE} button".to_json})"), "the focus is not on the last line"

    page.driver.browser.keyboard.type(:Enter)
    assert_selector "#{RESULTS} [data-search-group=post]"
    page.driver.browser.keyboard.type(:Escape)

    assert_selector "#{LIST} [role=tree]"
    assert_no_selector RESULTS, visible: :visible
    assert_equal "ruby", find(FIND).value
    assert page.evaluate_script("document.activeElement === document.querySelector(#{"#{SEARCH_SITE} button".to_json})"), "Escape left the focus elsewhere"

    # Typing while the results show gives the tree back under the new text.
    search_whole_site("ruby")
    assert_selector "#{RESULTS} [data-search-group=post]"
    find(FIND).send_keys("x")
    assert_no_selector RESULTS, visible: :visible
    assert_selector "#{SEARCH_SITE} button", text: "Search the whole site for “rubyx”"

    search_whole_site("zzzz")
    within(RESULTS) do
      assert_selector "p", exact_text: "No page, post or tag matches.", count: 1
      assert_no_selector "[data-search-group]"
    end

    # A page's result opens the page's local view, the page labelled first.
    search_whole_site("ruby")
    click_frame_link { find("#{RESULTS} [data-search-group=page] a").click }
    assert_current_path admin_mind_graph_path(page: docs.id)
    assert_selector "[data-mind-graph-focus]", text: "Around the page “Ruby docs”"
    await_graph
    assert_equal nid(docs), graph["data-labelled"].split(",").first, "the focus is labelled first"
  end

  test "a failed whole-site search says so and the graph keeps working" do
    create_post(title: "Hidden gem")
    visit_screen admin_mind_graph_path
    await_graph
    page.execute_script(<<~JS)
      const original = window.fetch
      window.realFetch ??= original
      window.fetch = (url, options) => String(url).includes("/mind_graph/search") ? Promise.reject(new TypeError("Failed to fetch")) : original(url, options)
    JS

    search_whole_site("hidden")

    assert_selector "#{RESULTS} p[role=alert].text-danger-ink", exact_text: "Search failed — check your connection."
    assert_equal "ready", graph["data-state"]
    click_button "Back to the list"
    # A lone post with no connection draws nothing: the list says so again.
    assert_selector "#{LIST} [data-mind-graph-rows]", text: "Nothing is drawn yet."
  end

  test "the results are text: a title with markup is not inserted as markup" do
    create_post(title: "<img src=x onerror=alert(1)> gem")
    visit_screen admin_mind_graph_path
    await_graph

    search_whole_site("gem")

    assert_selector "#{RESULTS} a", text: "<img src=x onerror=alert(1)> gem"
    assert_no_selector "#{RESULTS} img", visible: :all
  end

  test "leaving the screen aborts a whole-site search still in flight" do
    create_post(title: "Hidden gem")
    visit_screen admin_mind_graph_path
    await_graph
    # An answer that never comes, so the request is still open when we leave.
    page.execute_script(<<~JS)
      window.searchSignals = []
      const original = window.fetch
      window.realFetch ??= original
      window.fetch = (url, options) => {
        if (!String(url).includes("/mind_graph/search")) return original(url, options)
        window.searchSignals.push(options.signal)
        return new Promise((_, reject) => options.signal.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError"))))
      }
    JS
    search_whole_site("hid")
    assert_eventually(wait: 3, message: "the search request was never sent") { page.evaluate_script("window.searchSignals.length") == 1 }
    assert_selector "#{LIST} [data-mind-graph-rows][aria-busy=true]"

    # Left through a real link (the sidebar's Posts), a Turbo visit: the window,
    # and the signals recorded in it, outlive it.
    click_frame_link { within("nav[aria-label='Modules']") { click_link "Posts" } }

    assert page.evaluate_script("window.searchSignals.every((signal) => signal.aborted)"), "the request was left open after the screen was left"
  end

  # The query is the person's and outlives the graph's own navigations: a
  # Focus, a depth and Whole graph are frame navigations, whose new tree the
  # find narrows by it again, with its count and the last line. A visit of
  # the whole page, and Back to the graph from there, starts empty.
  test "the query is kept across Focus, a depth and Whole graph, and Back narrows the tree it restores; leaving the screen empties the field" do
    a, b, c = %w[Alpha Beta Gamma].map { |title| create_post(title: title) }
    PostRelation.create!(post: a, related_post: b)
    PostRelation.create!(post: b, related_post: c)
    match = "#{LIST} [role=treeitem][data-node-id='#{nid(a)}'][data-filter-match]"
    narrowed = lambda do |message|
      assert_equal "alp", find(FIND).value, "#{message}: the field lost its query"
      assert_selector match
      assert_no_selector "#{LIST} [role=treeitem][data-node-id='#{nid(b)}']"
      assert_selector "#tree-column [role=status]", text: "1 match"
      assert_selector "#{SEARCH_SITE} button", text: "Search the whole site for “alp”"
    end
    visit_screen admin_mind_graph_path
    await_graph
    find(FIND).fill_in(with: "alp")
    assert_selector match

    click_node(a)
    click_frame_link { within("[data-mind-graph-card]") { click_link "Focus" } }
    assert_selector "[data-mind-graph-focus]", text: "Around “Alpha”"
    await_graph
    narrowed.call("after Focus")

    click_frame_link { within("[data-mind-graph-focus]") { click_link "2" } }
    await_graph
    assert_equal "3", graph["data-nodes"]
    narrowed.call("after a depth")

    click_frame_link { within("[data-mind-graph-focus]") { click_link "Whole graph" } }
    assert_no_selector "[data-mind-graph-focus]"
    await_graph
    narrowed.call("after Whole graph")

    page.go_back
    assert_selector "[data-mind-graph-focus]"
    await_graph
    narrowed.call("after Back")

    click_frame_link { within("nav[aria-label='Modules']") { click_link "Posts" } }
    page.go_back
    await_graph
    assert_equal "", find(FIND).value
    assert_selector "#{LIST} [role=treeitem][data-node-id='#{nid(b)}']"
    assert_no_selector "#{LIST} [data-filter-match]"
    assert_selector SEARCH_SITE, visible: :hidden
  end

  # The find's Down and Enter act on a tree a person can see: while the
  # whole site's results stand in its place they do nothing.
  test "while the whole site's results show, Down and Enter in the find field leave the hidden tree alone" do
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))
    visit_screen admin_mind_graph_path
    await_graph

    search_whole_site("alpha")
    assert_selector "#{RESULTS} [data-search-group=post]"
    find(FIND).send_keys(:down)
    assert page.evaluate_script("document.activeElement === document.querySelector(#{FIND.to_json})"), "Down moved the focus into the hidden tree"
    find(FIND).send_keys(:enter)

    assert_equal "", graph["data-selected"].to_s, "Enter pressed a row of the hidden tree"
    assert_no_selector "[data-mind-graph-card]", visible: :visible
    assert_selector "#{RESULTS} [data-search-group=post]"
  end
end
