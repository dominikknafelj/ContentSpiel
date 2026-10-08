require "application_system_test_case"

# The Mind graph (mind graph canvas spec): drawn on a canvas, so nothing on it
# is an element a test can find. The controller says what it shows through
# data attributes on its element (`data-state`, `data-settled`, `data-nodes`,
# `data-edges`, `data-zoom`, `data-labelled`) and answers a node's place on
# screen through `element.mindGraph.screenPosition(id)`, where a test then
# points for real. What a mark LOOKS like is read from the canvas's own pixels
# (`pixel_at`): a canvas can pass every other test and still draw nothing.
class Admin::MindGraphSystemTest < ApplicationSystemTestCase
  GRAPH = "[data-controller~='admin--mind-graph']".freeze
  CANVAS = "#{GRAPH} canvas".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
  end

  test "the graph loads, settles, and the first view fits every node inside the canvas" do
    posts = 6.times.map { |i| create_post(title: "Post #{i}", tags: [ "shared" ]) }
    PostRelation.create!(post: posts[0], related_post: posts[1])

    visit admin_mind_graph_path
    await_graph

    assert_equal "7", graph["data-nodes"], "six posts and the tag they share"
    assert_equal "7", graph["data-edges"], "one related and six tag edges"
    assert_selector "#{CANVAS}[aria-label='Post relationship graph: 7 posts and tags, 7 connections.']"
    box = canvas_box
    (posts.map(&:id) + [ "tag-#{Tag.find_by!(name: "shared").id}" ]).each do |id|
      point = screen_position(id)
      assert point, "no position for #{id}"
      assert point["x"].between?(box[0], box[2]) && point["y"].between?(box[1], box[3]), "#{id} is outside the canvas: #{point} in #{box}"
    end
    assert_no_text "Loading the graph…"
  end

  # The box is the whole view: (almost) the content column wide -- main's width
  # less its padding and the box's border -- and it ends inside the window, so
  # the graph is there without scrolling.
  test "the box fills the content column and ends inside the window" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_mind_graph_path
    await_graph

    sizes = page.evaluate_script(<<~JS)
      (() => {
        const box = document.querySelector(#{GRAPH.to_json}).getBoundingClientRect()
        const canvas = document.querySelector(#{CANVAS.to_json}).getBoundingClientRect()
        return { width: box.width, main: document.querySelector("main").getBoundingClientRect().width, bottom: box.bottom, viewport: window.innerHeight, canvasHeight: canvas.height, canvasBottom: canvas.bottom }
      })()
    JS

    assert_operator sizes["width"], :>=, sizes["main"] - 60
    assert_operator sizes["width"], :<=, sizes["main"]
    assert_operator sizes["bottom"], :<=, sizes["viewport"]
    assert_operator sizes["canvasHeight"], :>, 300
    assert_operator sizes["canvasBottom"], :<=, sizes["bottom"]
  end

  test "the canvas is sharp: its bitmap is the box times the device pixel ratio" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_mind_graph_path
    await_graph

    sizes = page.evaluate_script("(() => { const c = document.querySelector(#{CANVAS.to_json}); const r = c.getBoundingClientRect(); return [c.width, Math.round(r.width * window.devicePixelRatio), c.height, Math.round(r.height * window.devicePixelRatio)] })()")

    assert_equal sizes[1], sizes[0]
    assert_equal sizes[3], sizes[2]
    assert_operator sizes[0], :>, 0
  end

  # Mind graph canvas spec §5.1, read from the pixels. Both posts have one
  # connection, so both are drawn six pixels in radius; four pixels left of the
  # centre is inside a filled dot, and in a draft's ring it is the gap between
  # the core (2.4 px) and the dashed outline (from 5 px). Left, because the
  # label is on the right.
  test "a live post is a filled dot, a draft a ring with a core: the status is a shape, not a colour" do
    live = create_post(title: "Live one")
    draft = create_post(title: "Draft one")
    draft.update_column(:published_at, nil)
    PostRelation.create!(post: live, related_post: draft)
    visit admin_mind_graph_path
    await_graph

    surface = pixel_at(*canvas_box.first(2).map { |edge| edge + 3 })
    live_centre, live_inside = pixels_of(live)
    draft_centre, draft_inside = pixels_of(draft)

    assert_operator surface[3], :<, 10, "the canvas's corner is not empty: #{surface}"
    assert_equal 255, live_centre[3], "nothing is drawn where the live post is"
    assert_equal live_centre, live_inside, "a live post is filled out to its edge"
    assert_equal live_centre, draft_centre, "both are the same type: the draft's core has the type's hue"
    assert_not_equal draft_centre, draft_inside, "a draft is a ring around a core, not a filled dot"
  end

  # Mind graph canvas spec §5.2: hubs are labelled first and the rest arrive
  # with zoom. The fitted view of 66 nodes has room for every label, so the
  # test first zooms OUT, to where only the best-connected are named (every
  # node still on the canvas), and then back in. (Zooming in from the fitted
  # view names FEWER nodes, not more: most of them leave the canvas, and a
  # node outside it has no label.)
  test "the zoom buttons zoom, hubs are labelled first and more labels arrive with zoom, and Fit all brings everything back" do
    posts = 60.times.map { |i| create_post(title: "Post #{i}", tags: [ "t#{i % 6}" ]) }
    posts.each_cons(2) { |a, b| PostRelation.create!(post: a, related_post: b) }
    tag_ids = Tag.where(name: 6.times.map { |i| "t#{i}" }).map { |tag| "tag-#{tag.id}" }
    visit admin_mind_graph_path
    await_graph
    zoom = "Number(document.querySelector(#{GRAPH.to_json}).dataset.zoom)"
    labelled = -> { graph["data-labelled"].split(",") }

    fitted = graph["data-zoom"].to_f
    4.times { press "Zoom out" }
    await_js("Math.abs(#{zoom} - #{fitted / (1.4**4)}) < 0.002")
    await_frames
    far = labelled.call
    assert_operator far.size, :<, 20, "zoomed far out, only the hubs are named: #{far}"
    assert_operator far.size, :>, 0
    # A tag here has ten edges, a post three: the hubs are the tags.
    assert_operator (far & tag_ids).size, :>=, [ far.size, tag_ids.size ].min - 1, "the labels did not go to the best-connected first: #{far} (tags: #{tag_ids})"

    2.times { press "Zoom in" }
    await_js("Math.abs(#{zoom} - #{fitted / (1.4**2)}) < 0.002")
    await_frames
    nearer = labelled.call
    assert_operator nearer.size, :>, far.size, "no label arrived with the zoom"

    press "Zoom in"
    press "Fit all"
    await_js("Math.abs(#{zoom} - #{fitted}) < 0.002")
    await_frames
    assert_operator labelled.call.size, :>=, nearer.size
  end

  test "the wheel zooms and a drag on empty space pans" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_mind_graph_path
    await_graph
    before = graph["data-zoom"].to_f
    first_id = Post.order(:id).first.id
    corner = canvas_box.first(2).map { |edge| edge + 12 }

    # Ferrum's mouse has no wheel (its `scroll_to` is `window.scrollTo`), so the
    # wheel is sent the way its clicks are: a native input event through CDP.
    mouse = page.driver.browser.mouse
    mouse.move(x: corner[0], y: corner[1])
    page.driver.browser.page.command("Input.dispatchMouseEvent", type: "mouseWheel", x: corner[0], y: corner[1], deltaX: 0, deltaY: 240)
    await_js("Number(document.querySelector(#{GRAPH.to_json}).dataset.zoom) < #{before}")

    moved_from = screen_position(first_id)
    mouse.move(x: corner[0], y: corner[1])
    mouse.down
    mouse.move(x: corner[0] + 60, y: corner[1] + 40)
    mouse.up
    await_js("(() => { const p = document.querySelector(#{GRAPH.to_json}).mindGraph.screenPosition(#{first_id}); return Math.abs(p.x - #{moved_from["x"] + 60}) < 2 && Math.abs(p.y - #{moved_from["y"] + 40}) < 2 })()")
  end

  # Mind graph canvas spec §4.4: with the canvas focused, + and - zoom around
  # its middle and the arrow keys pan.
  test "with the canvas focused, + and - zoom and the arrow keys pan" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_mind_graph_path
    await_graph
    first_id = Post.order(:id).first.id
    zoom = -> { graph["data-zoom"].to_f }
    fitted = zoom.call

    canvas = find(CANVAS)
    canvas.send_keys("-")
    await_js("Number(document.querySelector(#{GRAPH.to_json}).dataset.zoom) < #{fitted}")
    smaller = zoom.call
    canvas.send_keys("+")
    await_js("Number(document.querySelector(#{GRAPH.to_json}).dataset.zoom) > #{smaller}")

    from = screen_position(first_id)
    canvas.send_keys(:right)
    await_js("(() => { const p = document.querySelector(#{GRAPH.to_json}).mindGraph.screenPosition(#{first_id}); return Math.abs(p.x - #{from["x"] - 60}) < 1 && Math.abs(p.y - #{from["y"]}) < 1 })()")
    canvas.send_keys(:down)
    await_js("(() => { const p = document.querySelector(#{GRAPH.to_json}).mindGraph.screenPosition(#{first_id}); return Math.abs(p.x - #{from["x"] - 60}) < 1 && Math.abs(p.y - #{from["y"] - 60}) < 1 })()")
  end

  test "the filter hands the layout only what is shown" do
    a, b, c = 3.times.map { |i| create_post(title: "P#{i}") }
    PostRelation.create!(post: a, related_post: b)
    [ b, c ].each { |post| PostTag.create!(post: post, tag: Tag.find_or_create_by!(name: "t")) }
    visit admin_mind_graph_path
    await_graph
    assert_equal [ "4", "3" ], [ graph["data-nodes"], graph["data-edges"] ]

    find("label", text: "Related").click
    await_graph
    assert_equal [ "2", "1" ], [ graph["data-nodes"], graph["data-edges"] ]
    assert_nil screen_position(c.id), "a hidden node has no place on screen"
    assert_nil screen_position("tag-#{Tag.find_by!(name: "t").id}"), "a hidden tag has no place on screen"

    find("label", text: "Tags").click
    await_graph
    assert_equal [ "3", "2" ], [ graph["data-nodes"], graph["data-edges"] ]
    assert_nil screen_position(a.id)

    find("label", text: "All").click
    await_graph
    assert_equal [ "4", "3" ], [ graph["data-nodes"], graph["data-edges"] ]
    assert screen_position(a.id)
  end

  test "posts with no connection are counted, not drawn" do
    a = create_post(title: "A")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    alone = create_post(title: "Alone")
    visit admin_mind_graph_path
    await_graph

    assert_equal "2", graph["data-nodes"]
    assert_nil screen_position(alone.id)
    assert_text "1 post has no connections yet."
    assert_no_text "Link posts with Related posts"
  end

  test "posts but no connection at all: the hint, and nothing to draw" do
    2.times { |i| create_post(title: "Alone #{i}") }
    visit admin_mind_graph_path

    assert_selector "#{GRAPH}[data-state='ready'][data-settled]"
    assert_text "Link posts with Related posts, or give them shared tags, to see connections."
    assert_text "2 posts have no connections yet."
    assert_equal "0", graph["data-nodes"]
  end

  test "no readable post: 'No posts yet.' and no canvas" do
    visit admin_mind_graph_path

    assert_text "No posts yet."
    assert_no_selector "canvas"
  end

  # Mind graph canvas spec §5.2: cut by code point (an emoji is never halved),
  # and a tag's count is never cut. The labels are drawn, not elements, so the
  # rule is asked of the function that makes them.
  test "a long label is cut with an ellipsis by code point, and a tag keeps its count whole" do
    visit admin_tags_path
    await_admin_controllers

    labels = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import("mind_graph/app").then(({ labelFor }) => done([
        labelFor({ kind: "post", title: "Short" }),
        labelFor({ kind: "post", title: "A very long post title that goes on and on and on" }),
        labelFor({ kind: "post", title: "😀".repeat(40) }),
        labelFor({ kind: "tag", title: "a-long-shared-tag-name-for-the-box", count: 3 }),
        labelFor({ kind: "tag", title: "ruby", count: 12 })
      ]))
    JS

    assert_equal "Short", labels[0]
    assert_equal "A very long post title that goe…", labels[1]
    assert_equal 32, labels[1].each_char.size
    assert_equal ("😀" * 31) + "…", labels[2]
    assert_equal "a-long-shared-tag-name-for-… (3)", labels[3]
    assert_equal "ruby (12)", labels[4]
  end

  test "the data can't be loaded: a message with Retry, which loads it" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_tags_path
    await_admin_controllers
    page.execute_script(<<~JS)
      const original = window.fetch
      window.failGraph = true
      window.fetch = (url, options) => (window.failGraph && String(url).includes("/mind_graph/data") ? Promise.reject(new TypeError("Failed to fetch")) : original(url, options))
    JS

    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    assert_selector "#{GRAPH}[data-state='failed']"
    assert_text "The graph could not be loaded."
    assert_no_selector "#{GRAPH}[data-settled]"

    page.execute_script("window.failGraph = false")
    press "Retry"
    await_graph
    assert_no_text "The graph could not be loaded."
    assert_equal "3", graph["data-nodes"]
  end

  test "the server refuses the data: the same message" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_tags_path
    await_admin_controllers
    page.execute_script(<<~JS)
      const original = window.fetch
      window.fetch = (url, options) => (String(url).includes("/mind_graph/data") ? Promise.resolve(new Response("", { status: 500 })) : original(url, options))
    JS

    within("nav[aria-label='Modules']") { click_link "Mind graph" }

    assert_selector "#{GRAPH}[data-state='failed']"
    assert_text "The graph could not be loaded."
    assert_button "Retry"
  end

  # Mind graph canvas spec §6: a request that gets no answer is given up after
  # 15 seconds and shown like any other failure. The stubbed request never
  # answers but honours its signal, as `fetch` does; the 15 seconds are made 50
  # milliseconds by handing `AbortSignal.timeout` a shorter one, so nothing
  # here waits out the real time.
  test "the data request gets no answer: it times out into the same message, and Retry loads the graph" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_tags_path
    await_admin_controllers
    page.execute_script(<<~JS)
      const original = window.fetch
      const timeout = AbortSignal.timeout.bind(AbortSignal)
      window.hangGraph = true
      window.askedFor = []
      AbortSignal.timeout = (milliseconds) => { window.askedFor.push(milliseconds); return timeout(window.hangGraph ? 50 : milliseconds) }
      window.fetch = (url, options) => {
        if (!window.hangGraph || !String(url).includes("/mind_graph/data")) return original(url, options)
        return new Promise((resolve, reject) => options.signal.addEventListener("abort", () => reject(options.signal.reason)))
      }
    JS

    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    assert_selector "#{GRAPH}[data-state='failed']"
    assert_text "The graph could not be loaded."
    assert_equal [ 15_000 ], page.evaluate_script("window.askedFor"), "the request is given fifteen seconds"

    page.execute_script("window.hangGraph = false")
    press "Retry"
    await_graph
    assert_no_text "The graph could not be loaded."
    assert_equal "3", graph["data-nodes"]
  end

  # Mind graph canvas spec §5.6. Six thousand posts are not made for this: the
  # endpoint's answer is replaced by one that says it was cut, and the screen
  # has to say so. (The isolated count is the message's own `%{count}`, which
  # is written plainly, as Rails writes a count.)
  test "over the cap the screen says what it shows and what it leaves out" do
    create_post(title: "A")
    visit admin_tags_path
    await_admin_controllers
    stub_graph_data(CAPPED_GRAPH)

    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    await_graph

    assert_text "Showing the 2,000 best-connected of 6,000 posts."
    assert_text "1214 posts have no connections yet."
    assert_no_text "Link posts with Related posts"
    assert_equal "2", graph["data-nodes"]
  end

  # The numbers in those sentences are written the way the UI's language
  # writes them -- the `@locale` the server's messages name -- and not the way
  # the browser's own locale would. There is no German UI yet, so the test says
  # the messages are German between a failed load and its Retry.
  test "the cap's numbers are formatted for the language of the messages, not the browser's" do
    create_post(title: "A")
    visit admin_tags_path
    await_admin_controllers
    page.execute_script("window.failGraph = true")
    stub_graph_data(CAPPED_GRAPH)

    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    assert_selector "#{GRAPH}[data-state='failed']"
    page.execute_script(<<~JS)
      const element = document.querySelector(#{GRAPH.to_json})
      element.setAttribute("data-messages", JSON.stringify({ ...JSON.parse(element.getAttribute("data-messages")), "@locale": "de" }))
      window.failGraph = false
    JS
    press "Retry"
    await_graph

    assert_text "Showing the 2.000 best-connected of 6.000 posts."
    assert_text "1214 posts have no connections yet."
  end

  test "the worker can't start: a message without Retry, and an error in the console" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_tags_path
    await_admin_controllers
    page.execute_script("window.Worker = class { constructor() { throw new Error('no workers here') } }")

    within("nav[aria-label='Modules']") { click_link "Mind graph" }

    assert_selector "#{GRAPH}[data-state='worker-failed']"
    assert_text "The graph can't be drawn in this browser."
    assert_no_button "Retry"
    assert_no_selector "#{GRAPH}[data-settled]"
    # Loud: the failure is a console error, which is what fails any test that
    # did not ask for it.
    expect_js_error(/layout worker.*no workers here/)
  end

  # Review focus 2. Leaving while the request is out, and leaving while the
  # layout is still running. For the second the graph has to be big enough to
  # be settling for seconds, so the endpoint's answer is replaced by 1,500
  # posts and 30 tags made in the page (`BIG_GRAPH`); the worker is the real one.
  test "leaving while the graph is loading or settling raises nothing and stops the worker" do
    create_post(title: "A")
    visit admin_tags_path
    await_admin_controllers
    count_workers
    page.execute_script(<<~JS)
      const original = window.fetch
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
    visit admin_tags_path
    await_admin_controllers
    stub_graph_data(BIG_GRAPH)
    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    assert_selector "#{GRAPH}[data-state='ready'][data-nodes='1530']", wait: 15
    await_js("document.querySelector(#{GRAPH.to_json}).mindGraph.draws() >= 2")
    page.execute_script(<<~JS)
      window.leftGraph = document.querySelector(#{GRAPH.to_json})
      window.leftDraws = window.leftGraph.mindGraph.draws
      window.drawnAfter = null
      const context = window.leftGraph.querySelector("canvas").getContext("2d")
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

  # Review focus 3. Turbo restores the page as it was left -- `data-state=
  # "ready"`, `data-settled`, the counts -- before anything is fetched, so the
  # controller takes those back on connect; `data-url` is fetched once more
  # and the graph drawn from it.
  test "Back to the graph draws it once, with the filter the control shows" do
    a, b = 2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    PostRelation.create!(post: a, related_post: b)
    visit admin_mind_graph_path
    await_graph
    find("label", text: "Related").click
    await_graph
    assert_equal "2", graph["data-nodes"]

    within("nav[aria-label='Modules']") { click_link "Tags" }
    assert_selector "h1", text: "Tags"
    page.execute_script(<<~JS)
      window.graphFetches = 0
      const original = window.fetch
      window.fetch = (url, options) => { if (String(url).includes("/mind_graph/data")) window.graphFetches += 1; return original(url, options) }
    JS
    page.go_back
    assert_selector "h1", text: "Mind graph"
    await_js("window.graphFetches === 1")
    await_graph

    assert_equal "2", graph["data-nodes"], "the Related filter is still chosen, so the tag is not drawn"
    assert_equal "1", graph["data-edges"]
    assert_selector "#{GRAPH} canvas", count: 1
    assert_equal 1, page.evaluate_script("window.graphFetches")
    box = canvas_box
    [ a, b ].each do |post|
      point = screen_position(post.id)
      assert point["x"].between?(box[0], box[2]) && point["y"].between?(box[1], box[3]), "#{post.id} is outside the canvas after Back: #{point} in #{box}"
    end
  end

  # Review focus 4.
  test "a box that changes size is redrawn at the new size and still holds every node" do
    posts = 5.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_mind_graph_path
    await_graph
    original = page.current_window.size
    width_before = page.evaluate_script("document.querySelector(#{CANVAS.to_json}).width")

    begin
      page.current_window.resize_to(900, 620)
      await_js("(() => { const c = document.querySelector(#{CANVAS.to_json}); const r = c.getBoundingClientRect(); return c.width !== #{width_before} && c.width === Math.round(r.width * window.devicePixelRatio) && c.height === Math.round(r.height * window.devicePixelRatio) })()")
      press "Fit all"
      box = canvas_box
      posts.each do |post|
        point = screen_position(post.id)
        assert point["x"].between?(box[0], box[2]) && point["y"].between?(box[1], box[3]), "#{post.id} is outside the resized canvas: #{point} in #{box}"
      end
      assert_equal 255, pixels_of(posts.first).first[3], "nothing is drawn at the new size"
    ensure
      page.current_window.resize_to(*original)
    end
  end

  test "the theme's colours are read from the page, and the graph is redrawn when the theme changes" do
    posts = 2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_mind_graph_path
    await_graph

    before = pixels_of(posts.first).first
    draws = page.evaluate_script("document.querySelector(#{GRAPH.to_json}).mindGraph.draws()")
    theme = page.evaluate_script("document.documentElement.getAttribute('data-theme')")
    begin
      page.execute_script("document.documentElement.setAttribute('data-theme', #{(theme == "dark" ? "light" : "dark").to_json})")
      await_js("document.querySelector(#{GRAPH.to_json}).mindGraph.draws() > #{draws}")

      assert_not_equal before, pixels_of(posts.first).first, "the post's dot kept the other theme's colour"
    ensure
      page.execute_script("document.documentElement.setAttribute('data-theme', #{theme.to_json})")
    end
  end

  private

  # What the endpoint answers for a site over the cap, cut down to two nodes:
  # the counts are the point.
  CAPPED_GRAPH = <<~JS.freeze
    ({
      nodes: [ { id: 1, title: "One", type: "blog", colour_index: 1, status: "live", url: "/one", degree: 1 }, { id: 2, title: "Two", type: "blog", colour_index: 1, status: "live", url: "/two", degree: 1 } ],
      tags: [], edges: [ { source: 1, target: 2, kind: "related" } ], total: 6000, shown: 2000, isolated: 1214
    })
  JS

  # A graph that takes the worker seconds to lay out: 1,500 posts in a chain,
  # each also on one of 30 tags. A JavaScript expression, made in the page.
  BIG_GRAPH = <<~JS.freeze
    (() => {
      const nodes = Array.from({ length: 1500 }, (_, index) => ({ id: index + 1, title: `Post ${index + 1}`, type: "blog", colour_index: 1, status: "live", url: "/post", degree: 3 }))
      const tags = Array.from({ length: 30 }, (_, index) => ({ id: `tag-${index + 1}`, name: `tag ${index + 1}`, count: 50, degree: 50 }))
      const edges = [
        ...nodes.slice(1).map((node) => ({ source: node.id - 1, target: node.id, kind: "related" })),
        ...nodes.map((node) => ({ source: node.id, target: `tag-${(node.id % 30) + 1}`, kind: "tag" }))
      ]
      return { nodes, tags, edges, total: 1500, shown: 1500, isolated: 0 }
    })()
  JS

  # Answers the data endpoint from the page: `payload` is a JavaScript
  # expression for the graph. Installed on a screen visited BEFORE the Mind
  # graph (the window outlives a Turbo visit), so the graph's first request
  # already gets it. While `window.failGraph` is set the request fails instead.
  def stub_graph_data(payload)
    page.execute_script(<<~JS)
      const original = window.fetch
      window.fetch = (url, options) => {
        if (!String(url).includes("/mind_graph/data")) return original(url, options)
        if (window.failGraph) return Promise.reject(new TypeError("Failed to fetch"))
        return Promise.resolve(new Response(JSON.stringify(#{payload}), { headers: { "Content-Type": "application/json" } }))
      }
    JS
  end

  # Counts the workers started and still alive, on a screen visited before the
  # Mind graph.
  def count_workers
    page.execute_script(<<~JS)
      window.liveWorkers = 0
      window.startedWorkers = 0
      const Real = window.Worker
      window.Worker = class extends Real {
        constructor(...args) { super(...args); window.liveWorkers += 1; window.startedWorkers += 1 }
        terminate() { window.liveWorkers -= 1; super.terminate() }
      }
    JS
  end

  def graph = find(GRAPH)

  def await_graph
    assert_selector "#{GRAPH}[data-state='ready'][data-settled]", wait: 15
  end

  def screen_position(id)
    page.evaluate_script("document.querySelector(#{GRAPH.to_json}).mindGraph.screenPosition(#{id.to_json})")
  end

  # The canvas's box in client coordinates: left, top, right, bottom.
  def canvas_box
    page.evaluate_script("(() => { const r = document.querySelector(#{CANVAS.to_json}).getBoundingClientRect(); return [r.left, r.top, r.right, r.bottom] })()")
  end

  # The colour the canvas holds at a client point, as [r, g, b, a]. Read after
  # two frames, so a draw that was asked for has happened.
  def pixel_at(x, y)
    await_frames
    page.evaluate_script(<<~JS)
      (() => {
        const canvas = document.querySelector(#{CANVAS.to_json})
        const box = canvas.getBoundingClientRect()
        const ratio = canvas.width / box.width
        return Array.from(canvas.getContext("2d").getImageData(Math.round((#{x} - box.left) * ratio), Math.round((#{y} - box.top) * ratio), 1, 1).data)
      })()
    JS
  end

  # A post's mark at its centre and four pixels to the left of it.
  def pixels_of(post)
    point = screen_position(post.id)
    [ pixel_at(point["x"], point["y"]), pixel_at(point["x"] - 4, point["y"]) ]
  end
end
