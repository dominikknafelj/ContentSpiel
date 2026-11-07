require "application_system_test_case"

class Admin::MindGraphWorkerAndBackSystemTest < Admin::MindGraphSystemTestCase
  test "the worker can't start: a message without Retry, and an error in the console" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit_screen admin_tags_path

    without_workers do
      within("nav[aria-label='Modules']") { click_link "Mind graph" }

      assert_selector "#{GRAPH}[data-state='worker-failed']"
      assert_text "The graph can't be drawn in this browser."
      assert_no_button "Retry"
      assert_no_selector "#{GRAPH}[data-settled]"
      # Nothing was ever laid out, so nothing is drawn: without positions every
      # node is at 0, 0, and the graph would be a pile in the canvas's corner.
      assert_operator pixel_at(*canvas_box.first(2).map { |edge| edge + 3 })[3], :<, 10, "the unplaced nodes are drawn in the corner"
      # Loud: the failure is a console error, which is what fails any test that
      # did not ask for it.
      expect_js_error(/layout worker.*no workers here/)
    end
  end

  # A node that was never placed is nowhere: every position is still 0, 0, the
  # canvas's top-left corner, and nothing is drawn there -- so nothing may be
  # hovered, clicked or located there either.
  test "the worker can't start: the corner where unplaced nodes would be answers no hover, no click and no position" do
    post = create_post(title: "Alpha", tags: [ "shared" ])
    create_post(title: "Beta", tags: [ "shared" ])
    visit_screen admin_tags_path
    without_workers do
      within("nav[aria-label='Modules']") { click_link "Mind graph" }
      assert_selector "#{GRAPH}[data-state='worker-failed']"
      expect_js_error(/layout worker.*no workers here/)
    end

    left, top = canvas_box.first(2)
    page.driver.browser.mouse.move(x: left + 3, y: top + 3)
    await_frames
    assert_no_selector "[data-mind-graph-tooltip]", visible: :visible
    page.driver.browser.mouse.click(x: left + 3, y: top + 3)
    await_frames

    assert_no_selector "[data-mind-graph-card]", visible: :visible
    assert_equal "", graph["data-selected"].to_s
    assert_nil screen_position(post), "an unplaced node has no place on screen"
  end

  # The list is filled before the layout starts, so a worker that
  # fails leaves the nodes reachable. A row opens the node's card -- in the
  # canvas's corner, since no node has a place to stand beside -- and the
  # card's links lead on. There is nothing to pin without a layout.
  test "the worker can't start: the list still gives every node as a row, and its card leads to the node's local view" do
    create_post(title: "Alpha", tags: [ "shared" ])
    create_post(title: "Beta", tags: [ "shared" ])
    tag = Tag.find_by!(name: "shared")
    visit_screen admin_tags_path

    # The window outlives the visit below: the real worker comes back first.
    without_workers do
      within("nav[aria-label='Modules']") { click_link "Mind graph" }
      assert_selector "#{GRAPH}[data-state='worker-failed']"
      expect_js_error(/layout worker.*no workers here/)
    end

    within(LIST) do
      assert_selector "li", count: 3
      assert_row "Alpha: post, 1 connection. Shows it in the graph."
      assert_row "Beta: post, 1 connection. Shows it in the graph."
      find("button", text: "shared").click
    end
    assert_equal "tag-#{tag.id}", graph["data-selected"]
    within("[data-mind-graph-card]") do
      assert_link "Focus", href: /mind_graph\?tag=#{tag.id}\z/
      assert_no_button "Pin"
    end
    card = element_box("[data-mind-graph-card]")
    box = canvas_box
    assert_in_delta box[2] - 8, card["right"], 1, "with no layout the card stands in the canvas's top-right corner"
    assert_in_delta box[1] + 8, card["top"], 1
    click_frame_link { within("[data-mind-graph-card]") { click_link "Focus" } }
    assert_selector "[data-mind-graph-focus]", text: "Around the tag “shared”"
  end

  # With no layout the list is all there is, so it has to follow the filter:
  # the legend saying "Tags" is off over a list that still holds the tag would be
  # the screen contradicting itself.
  test "the worker can't start: the filter still narrows the list and the counts" do
    a = create_post(title: "Alpha", tags: [ "shared" ])
    create_post(title: "Beta", tags: [ "shared" ])
    PostRelation.create!(post: a, related_post: create_post(title: "Gamma"))
    visit_screen admin_tags_path
    without_workers do
      within("nav[aria-label='Modules']") { click_link "Mind graph" }
      assert_selector "#{GRAPH}[data-state='worker-failed'][data-nodes='4'][data-edges='3']"
      expect_js_error(/layout worker.*no workers here/)
    end
    assert_selector "#{LIST} li", count: 4

    toggle "Tags"

    assert_selector "#{GRAPH}[data-state='worker-failed'][data-nodes='3'][data-edges='1']"
    within(LIST) do
      assert_selector "li", count: 3
      assert_selector "button", text: "Alpha"
      assert_selector "button", text: "Beta"
      assert_selector "button", text: "Gamma"
      assert_no_selector "button", text: "shared"
    end
    assert_no_selector "#{GRAPH}[data-settled]"
    assert_text "The graph can't be drawn in this browser."
  end

  test "a graph with nothing to draw says so in the list" do
    create_post(title: "Alone")
    visit_screen admin_tags_path
    stub_graph_data("({ nodes: [], tags: [], edges: [], total: 0, shown: 0, isolated: 0 })")

    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    await_graph

    within(LIST) do
      assert_text "Nothing is drawn yet."
      assert_no_selector "li"
    end
  end

  # Leaving while the request is out, and leaving while the layout is still
  # running, leaves nothing running and nothing raised. For the second the graph has to be big enough to
  # be settling for seconds, so the endpoint's answer is replaced by 1,500
  # posts and 30 tags made in the page (`BIG_GRAPH`); the worker is the real one.
  test "leaving while the graph is loading or settling raises nothing and stops the worker" do
    create_post(title: "A")
    visit_screen admin_tags_path
    count_workers
    page.execute_script(<<~JS)
      const original = window.fetch
      window.realFetch ??= original
      window.holdGraph = true
      window.heldRequests = 0
      window.abortedRequests = 0
      window.fetch = (url, options) => {
        if (!window.holdGraph || !String(url).includes("/mind_graph/data")) return original(url, options)
        window.heldRequests += 1
        return new Promise((resolve, reject) => options.signal.addEventListener("abort", () => { window.abortedRequests += 1; reject(options.signal.reason) }))
      }
    JS

    # Loading: the request is out when the screen is left, and is aborted.
    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    await_js("window.heldRequests === 1")
    assert_selector "#{GRAPH}[data-state='loading']"
    within("nav[aria-label='Modules']") { click_link "Tags" }
    assert_selector "h1", text: "Tags"
    await_js("window.abortedRequests === window.heldRequests")
    assert_equal [ 0, 0 ], page.evaluate_script("[window.startedWorkers, window.liveWorkers]"), "no data, no worker"

    # Settling: a worker was started, is still laying out, and is terminated.
    page.execute_script("window.holdGraph = false")
    stub_graph_data(BIG_GRAPH)
    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    assert_selector "#{GRAPH}[data-state='ready'][data-nodes='1530']", wait: 15
    await_js("window.liveWorkers === 1")
    page.execute_script("window.leftGraph = document.querySelector(#{GRAPH.to_json})")
    within("nav[aria-label='Modules']") { click_link "Tags" }
    assert_selector "h1", text: "Tags"
    await_js("window.liveWorkers === 0")
    assert_not page.evaluate_script("window.leftGraph.hasAttribute('data-settled')"), "the layout had cooled down before the screen was left: nothing was stopped"
    assert_operator page.evaluate_script("window.startedWorkers"), :>=, 1
  end

  # Nothing draws after disconnect. The screen is left while the layout of
  # 1,500 nodes is still running (the element that was left never got
  # `data-settled`), so there IS something to stop: frames were being drawn up
  # to the moment of leaving, and none is drawn afterwards.
  test "nothing is drawn once the screen is left" do
    create_post(title: "A")
    visit_screen admin_tags_path
    stub_graph_data(BIG_GRAPH)
    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    assert_selector "#{GRAPH}[data-state='ready'][data-nodes='1530']", wait: 15
    await_js("document.querySelector(#{GRAPH.to_json}).mindGraph.draws() >= 2")
    page.execute_script(<<~JS)
      window.leftGraph = document.querySelector(#{GRAPH.to_json})
      window.leftDraws = window.leftGraph.mindGraph.draws
      window.drawnAfter = null
      const context = document.querySelector(#{CANVAS.to_json}).getContext("2d")
      const clear = context.clearRect.bind(context)
      context.clearRect = (...args) => { if (window.drawnAfter !== null) window.drawnAfter += 1; clear(...args) }
      // The moment of leaving: Stimulus disconnects the controller when the
      // element goes, and from then on a frame drawn is a frame too many.
      new MutationObserver((_, observer) => {
        if (window.leftGraph.isConnected) return
        observer.disconnect()
        queueMicrotask(() => { window.drawnAfter = 0; window.countAtLeave = window.leftDraws() })
      }).observe(document.documentElement, { childList: true, subtree: true })
    JS

    within("nav[aria-label='Modules']") { click_link "Tags" }
    assert_selector "h1", text: "Tags"
    await_js("window.drawnAfter !== null")
    await_frames
    await_frames

    assert_not page.evaluate_script("window.leftGraph.hasAttribute('data-settled')"), "the layout had cooled down before the screen was left: nothing was stopped"
    assert_operator page.evaluate_script("window.countAtLeave"), :>=, 2
    assert_equal [ true, 0 ], page.evaluate_script("[window.leftDraws() === window.countAtLeave, window.drawnAfter]")
    assert page.evaluate_script("window.leftGraph.mindGraph === undefined"), "the element that was left still carries its hook"
  end

  # Turbo restores the page as it was left -- `data-state=
  # "ready"`, `data-settled`, the counts -- before anything is fetched, so the
  # controller takes those back on connect; `data-url` is fetched once more
  # and the graph drawn from it.
  test "Back to the graph draws it once, with what the legend shows: its counts gone until the data is back, its checkboxes kept" do
    a, b = 2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    PostRelation.create!(post: a, related_post: b)
    visit admin_mind_graph_path
    await_graph
    assert_equal "3", graph["data-nodes"]
    assert_selector "#{CANVAS}[aria-label='Mind graph: 2 posts and 1 tag, 3 connections. Showing everything.']"
    toggle "Tags"
    await_graph
    assert_equal [ "2", "1" ], [ graph["data-nodes"], graph["data-edges"] ]
    assert_selector "#{CANVAS}[aria-label='Mind graph: 2 posts, 1 connection. Showing everything. Tags hidden.']"
    assert_selector "#{GRAPH} [data-mind-graph-announced]", visible: :all

    within("nav[aria-label='Modules']") { click_link "Tags" }
    assert_selector "h1", text: "Tags"
    # The data request is counted, and held until `releaseGraph()`: what the
    # restored page says before its data has come is the point of the middle.
    page.execute_script(<<~JS)
      window.graphFetches = 0
      const original = window.fetch
      window.realFetch ??= original
      window.fetch = (url, options) => {
        if (!String(url).includes("/mind_graph/data")) return original(url, options)
        window.graphFetches += 1
        return new Promise((resolve) => { window.releaseGraph = () => resolve(original(url, options)) })
      }
    JS
    page.go_back
    assert_selector "h1", text: "Mind graph"
    await_js("window.graphFetches === 1")
    # The snapshot's canvas was named with the summary of the visit that was
    # left; until this visit's data has come, it has the server's name again.
    # So with the legend: its counts and the names made of them are gone,
    # and the announcement with the notice; the checkboxes are the person's
    # choice and are kept, so "Tags" is still off.
    assert_selector "#{GRAPH}[data-state='loading']"
    assert_selector "#{CANVAS}[aria-label='Mind graph']"
    assert_equal [ "Posts", "Tags", "Related", "Shares a tag" ], legend_counts, "a count of the visit that was left is still beside its toggle"
    assert_no_selector "#{GRAPH} [data-mind-graph-legend] input[aria-label]", visible: :all
    assert_no_selector "#{GRAPH} [data-mind-graph-announced]", visible: :all
    assert_no_selector "#{GRAPH} input[name=mind_graph_nodes][value=tag]:checked", visible: :all
    assert_selector "#{GRAPH} input[name=mind_graph_nodes][value=post]:checked", visible: :all
    page.execute_script("window.releaseGraph()")
    await_graph
    assert_selector "#{CANVAS}[aria-label='Mind graph: 2 posts, 1 connection. Showing everything. Tags hidden.']"
    assert_equal [ "Posts 2", "Tags 1", "Related 1", "Shares a tag 2" ], legend_counts, "the counts are what was loaded, not what the legend shows"

    assert_equal "2", graph["data-nodes"], "Tags is still switched off, so the tag is not drawn"
    assert_equal "1", graph["data-edges"]
    assert_selector CANVAS, count: 1
    # The swatches are drawn again in the restored page: a snapshot keeps a
    # canvas and none of its pixels.
    # So are the Status key's, outside the graph's element: the whole body is
    # the snapshot's.
    drawn = ->(selector) { "Array.from(document.querySelectorAll(#{selector.to_json})).every((canvas) => canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data.some((value) => value > 0))" }
    assert_equal [ 6, 5 ], page.evaluate_script("[ document.querySelectorAll(#{"#{GRAPH} canvas[data-swatch]".to_json}).length, document.querySelectorAll('#mind-graph-status-key canvas[data-swatch]').length ]")
    await_js(drawn.call("#{GRAPH} canvas[data-swatch]"))
    await_js(drawn.call("#mind-graph-status-key canvas[data-swatch]"))
    assert_equal 1, page.evaluate_script("window.graphFetches")
    box = canvas_box
    [ a, b ].each do |post|
      point = screen_position(post)
      assert point["x"].between?(box[0], box[2]) && point["y"].between?(box[1], box[3]), "#{post.id} is outside the canvas after Back: #{point} in #{box}"
    end
  end

  # Turbo's snapshot is the page as it was left, card and all; Back shows a
  # clean screen (the controller's `reset`), and nothing is selected.
  test "Back to the graph after a selection shows no card" do
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph
    click_node(a)
    click_frame_link { within("[data-mind-graph-card]") { click_link "Open post" } }
    assert_current_path admin_post_path(a)

    page.go_back
    await_graph

    assert_no_selector "[data-mind-graph-card]", visible: :visible
    assert_equal "", graph["data-selected"].to_s
  end
end
