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

  test "search finds a post the global view does not draw and opens its neighbourhood" do
    a = create_post(title: "Connected")
    PostRelation.create!(post: a, related_post: create_post(title: "Also connected"))
    alone = create_post(title: "Hidden gem")
    visit admin_mind_graph_path
    await_graph
    assert_nil screen_position(alone)

    fill_in "Find a page, post or tag", with: "hidden"
    click_frame_link { within("[data-mind-graph-results]") { click_link "Hidden gem" } }

    assert_selector "[data-mind-graph-focus]", text: "Around “Hidden gem”"
    await_graph
    assert_equal "1", graph["data-nodes"]
  end

  test "search lists tags too, says when nothing matches, and Escape closes the list" do
    2.times { |i| create_post(title: "P#{i}", tags: [ "ruby" ]) }
    visit admin_mind_graph_path
    await_graph

    fill_in "Find a page, post or tag", with: "rub"
    within("[data-mind-graph-results]") do
      # A row's text is its label; its kind is the heading of its group.
      assert_selector "[data-search-group=tag] a", exact_text: "ruby"
      assert_equal [ "TAGS" ], all("[data-search-group] > p").map { |heading| heading.text.upcase }
    end

    assert_selector "[data-mind-graph-status]", text: "1 result", visible: :all

    fill_in "Find a page, post or tag", with: "zzzz"
    assert_selector "[data-mind-graph-results]", text: "No page, post or tag matches."
    assert_selector "[data-mind-graph-status]", text: "No page, post or tag matches.", visible: :all

    find_field("Find a page, post or tag").send_keys(:escape)
    assert_no_selector "[data-mind-graph-results]", visible: :visible
  end

  test "a result is reached by Tab and opened with Enter" do
    create_post(title: "Hidden gem")
    visit admin_mind_graph_path
    await_graph

    field = find_field("Find a page, post or tag")
    field.fill_in with: "hidden"
    assert_selector "[data-mind-graph-results] a", text: "Hidden gem"
    click_frame_link { field.send_keys(:tab, :enter) }

    assert_selector "[data-mind-graph-focus]", text: "Around “Hidden gem”"
  end

  test "a failed search says so and the graph keeps working" do
    create_post(title: "Hidden gem")
    visit admin_mind_graph_path
    await_graph
    page.execute_script(<<~JS)
      const original = window.fetch
      window.realFetch ??= original
      window.fetch = (url, options) => String(url).includes("/mind_graph/search") ? Promise.reject(new TypeError("Failed to fetch")) : original(url, options)
    JS

    fill_in "Find a page, post or tag", with: "hidden"

    assert_selector "[data-mind-graph-results]", text: "Search failed — check your connection."
    assert_selector "[data-mind-graph-status][role=status]", text: "Search failed — check your connection.", visible: :all
    assert_equal "ready", graph["data-state"]
  end

  test "earlier rows are gone as soon as the text changes" do
    create_post(title: "Hidden gem")
    create_post(title: "Zebra")
    visit admin_mind_graph_path
    await_graph
    field = find_field("Find a page, post or tag")
    field.fill_in with: "hidden"
    assert_selector "[data-mind-graph-results] a", text: "Hidden gem"
    # Hold the next answer back, so what is on screen meanwhile is the point.
    page.execute_script("const original = window.fetch; window.realFetch ??= original; window.fetch = (url, options) => String(url).includes('/mind_graph/search') ? new Promise(() => {}) : original(url, options)")

    field.send_keys("x")

    assert_no_selector "[data-mind-graph-results] a", visible: :all
  end

  test "Tabbing past the last result closes the list" do
    create_post(title: "Hidden gem")
    visit admin_mind_graph_path
    await_graph
    field = find_field("Find a page, post or tag")
    field.fill_in with: "hidden"
    assert_selector "[data-mind-graph-results] a", text: "Hidden gem"

    field.send_keys(:tab, :tab)

    assert_no_selector "[data-mind-graph-results]", visible: :visible
    assert_equal "", find("[data-mind-graph-status]", visible: :all).text(:all)
  end

  test "the results are text: a title with markup is not inserted as markup" do
    create_post(title: "<img src=x onerror=alert(1)> gem")
    visit admin_mind_graph_path
    await_graph

    fill_in "Find a page, post or tag", with: "gem"

    assert_selector "[data-mind-graph-results] a", text: "<img src=x onerror=alert(1)> gem"
    assert_no_selector "[data-mind-graph-results] img", visible: :all
  end

  test "Back to the graph shows no results list and an empty search field" do
    create_post(title: "Hidden gem")
    visit admin_mind_graph_path
    await_graph
    fill_in "Find a page, post or tag", with: "hidden"
    click_frame_link { within("[data-mind-graph-results]") { click_link "Hidden gem" } }
    assert_selector "[data-mind-graph-focus]"

    page.go_back
    await_graph

    assert_no_selector "[data-mind-graph-results]", visible: :visible
    assert_equal "", find_field("Find a page, post or tag").value
  end

  test "leaving the screen aborts a search request still in flight" do
    create_post(title: "Hidden gem")
    visit admin_mind_graph_path
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
    fill_in "Find a page, post or tag", with: "hid"
    assert_eventually(wait: 3, message: "the search request was never sent") { page.evaluate_script("window.searchSignals.length") == 1 }

    # Left through a real link (the sidebar's Posts), a Turbo visit: the window,
    # and the signals recorded in it, outlive it.
    click_frame_link { within("nav[aria-label='Modules']") { click_link "Posts" } }

    assert page.evaluate_script("window.searchSignals.every((signal) => signal.aborted)"), "the request was left open after the screen was left"
  end

  test "search finds a page, groups its rows under Pages, Posts and Tags, shows a page's path, and opens the page's neighbourhood" do
    docs = create_page(title: "Ruby docs")
    create_post(title: "Ruby notes", tags: [ "ruby" ])
    create_post(title: "Other", tags: [ "ruby" ])
    visit admin_mind_graph_path
    await_graph

    fill_in "Find a page, post or tag", with: "ruby"

    within("#{GRAPH} [data-mind-graph-results]") do
      assert_equal %w[PAGES POSTS TAGS], all("[data-search-group] > p").map { |heading| heading.text.upcase }
      assert_selector "[data-search-group=page] a", text: "Ruby docs"
      assert_selector "[data-search-group=page] a span.text-small", text: PublicPath.current.where(record: docs).pick(:path)
      assert_no_match(/mono/i, find("[data-search-group=page] a span.text-small", text: PublicPath.current.where(record: docs).pick(:path)).evaluate_script("getComputedStyle(this).fontFamily"))
      assert_selector "[data-search-group=post] a", text: "Ruby notes"
      assert_selector "[data-search-group=tag] a", text: "ruby"
      # Each row's mark: a page's is the renderer's small canvas, a post's
      # its type's dot, a tag's the square. All decoration.
      assert_selector "a > [aria-hidden='true']", count: 3
      assert_selector "[data-search-group=page] a > canvas[data-mark=page]"
      assert_selector "[data-search-group] ul[role=list][aria-labelledby]", count: 3
    end
    assert_marks_drawn "#{GRAPH} [data-mind-graph-results]"
    click_frame_link { find("#{GRAPH} [data-search-group=page] a").click }

    assert_current_path admin_mind_graph_path(page: docs.id)
    assert_selector "[data-mind-graph-focus]", text: "Around the page “Ruby docs”"
    await_graph
    assert_equal nid(docs), graph["data-labelled"].split(",").first, "the focus is labelled first"
  end
end
