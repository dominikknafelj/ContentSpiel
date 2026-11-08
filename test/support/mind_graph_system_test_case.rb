# The setup, the graph scripts and the helpers the files of
# test/system/admin/mind_graph_*_test.rb (but the modules' ones) share.
#
# The Mind graph is drawn on a canvas, so nothing on it is an element a test
# can find. The controller says what it shows through data attributes on its
# element (`data-state`, `data-settled`, `data-nodes`, `data-edges`,
# `data-zoom`, `data-labelled`, `data-selected`, `data-hovered`,
# `data-pinned`) and answers a node's place on screen through
# `element.mindGraph.screenPosition(id)`, where a test then points for real.
#
# A small graph UNFOLDS at one tick a frame, about five seconds from load to
# rest, and eases for about as long after a drop, a filter or an unpin: every
# `await_graph` waits that out, which is the screen as a person gets it. What a
# mark LOOKS like is read from the canvas's own pixels (`pixel_at`): a canvas
# can pass every other test and still draw nothing.
class Admin::MindGraphSystemTestCase < ApplicationSystemTestCase
  GRAPH = "[data-controller~='admin--mind-graph--graph']".freeze
  # The graph's own canvas: the legend's swatches are canvases too.
  CANVAS = "#{GRAPH} canvas[data-admin--mind-graph--graph-target='canvas']".freeze
  LIST = "#{GRAPH} [data-mind-graph-list]".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
  end

  # A test that stubs `window.fetch` or `AbortSignal.timeout` remembers the
  # real one (`window.realFetch`, `window.realTimeout`: every stub in the
  # graph's browser files writes it before it replaces anything), and it is put
  # back here, whatever happened in the test. A test that goes on in the same
  # window after its stub's work is done, or a session kept between tests,
  # would otherwise meet the stub.
  teardown do
    page.execute_script(<<~JS)
      if (window.realFetch) { window.fetch = window.realFetch; delete window.realFetch }
      if (window.realTimeout) { AbortSignal.timeout = window.realTimeout; delete window.realTimeout }
    JS
  rescue Ferrum::Error, Capybara::CapybaraError
    # The browser has gone with the test: there is no window to put right.
  end

  private

  # A post, a tag and a page of ONE database id (the three
  # tables count on their own), with a page's lines to a tag and to a
  # post type, and a pill hanging off the type by a `brings` line as in a
  # page's local view.
  SHARED_ID_GRAPH = <<~JS.freeze
    ({
      nodes: [ { id: "post-12", title: "Twelve", type: "blog", colour_index: 1, status: "live", changes: null, change_at: null, unpublished: false, listed: true, url: "/twelve", degree: 2, related_count: 1, tag_count: 1, open_notes: 0 },
               { id: "post-13", title: "Thirteen", type: "blog", colour_index: 1, status: "live", changes: null, change_at: null, unpublished: false, listed: true, url: "/thirteen", degree: 2, related_count: 1, tag_count: 1, open_notes: 0 } ],
      tags: [ { id: "tag-12", name: "twelve", count: 2, degree: 3 } ],
      pages: [ { id: "page-12", title: "Page twelve", path: "/twelve", depth: 0, home: true, parent: null, order: 0, status: "live", changes: null, change_at: null, unpublished: false, url: "/pages/12", degree: 2, child_count: 0, listed_count: 2, open_notes: 0 } ],
      types: [ { id: "type-blog", name: "blog", label: "Blog post", colour_index: 1, count: 2, degree: 1 } ],
      edges: [ { source: "post-12", target: "post-13", kind: "related" }, { source: "post-12", target: "tag-12", kind: "tag" }, { source: "post-13", target: "tag-12", kind: "tag" },
               { source: "page-12", target: "tag-12", kind: "lists" }, { source: "page-12", target: "type-blog", kind: "lists" },
               { source: "type-blog", target: "more-type-blog", kind: "brings" } ],
      more: [ { id: "more-type-blog", count: 1980, page: "page-12", target: "type-blog" } ],
      total: 2, shown: 2, isolated: 0
    })
  JS

  # What the endpoint answers for a site over the cap, cut down to two nodes:
  # the counts are the point.
  CAPPED_GRAPH = <<~JS.freeze
    ({
      nodes: [ { id: "post-1", title: "One", type: "blog", colour_index: 1, status: "live", url: "/one", degree: 1, related_count: 1, tag_count: 0 }, { id: "post-2", title: "Two", type: "blog", colour_index: 1, status: "live", url: "/two", degree: 1, related_count: 1, tag_count: 0 } ],
      tags: [], edges: [ { source: "post-1", target: "post-2", kind: "related" } ], total: 6000, shown: 2000, isolated: 1214
    })
  JS

  # The same for a local view: the data names its focus, and the walk reached
  # more posts than the cap keeps.
  CAPPED_LOCAL_GRAPH = <<~JS.freeze
    ({
      nodes: [ { id: "post-1", title: "One", type: "blog", colour_index: 1, status: "live", url: "/one", degree: 1, related_count: 1, tag_count: 0 }, { id: "post-2", title: "Two", type: "blog", colour_index: 1, status: "live", url: "/two", degree: 1, related_count: 1, tag_count: 0 } ],
      tags: [], edges: [ { source: "post-1", target: "post-2", kind: "related" } ], total: 2695, shown: 2000,
      focus: { kind: "post", id: 1, node_id: "post-1", title: "One", depth: 2 }
    })
  JS

  # A graph that takes the worker seconds to lay out: 1,500 posts in a chain,
  # each also on one of 30 tags. A JavaScript expression, made in the page.
  BIG_GRAPH = <<~JS.freeze
    (() => {
      const nodes = Array.from({ length: 1500 }, (_, index) => ({ id: `post-${index + 1}`, title: `Post ${index + 1}`, type: "blog", colour_index: 1, status: "live", url: "/post", degree: 3, related_count: 2, tag_count: 1 }))
      const tags = Array.from({ length: 30 }, (_, index) => ({ id: `tag-${index + 1}`, name: `tag ${index + 1}`, count: 50, degree: 50 }))
      const edges = [
        ...nodes.slice(1).map((node, index) => ({ source: `post-${index + 1}`, target: node.id, kind: "related" })),
        ...nodes.map((node, index) => ({ source: node.id, target: `tag-${((index + 1) % 30) + 1}`, kind: "tag" }))
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
      window.realFetch ??= original
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

  # Escape with the canvas focused. The key is real; the focus is given by
  # script, because Cuprite's `send_keys` CLICKS an element that is not
  # focused -- in its middle, where the card of a centred node now stands.
  def escape_on_canvas
    find(CANVAS).execute_script("this.focus()")
    page.driver.browser.keyboard.type(:Escape)
  end

  # A row of the list by its accessible name: the list is a tree, each row
  # a `[role=treeitem]` named by its `aria-label` (which Capybara's locators
  # do not read), and a parent's item holds its children's, so it is found
  # by its own name and never by the text inside it.
  def assert_row(name) = assert_selector("[role=treeitem][aria-label=#{name.to_json}]")

  # The item of the row whose name begins with `name` ("Alpha" finds
  # "Alpha: post, 1 connection. Shows it in the graph.").
  def list_item(name, **options) = find("[role=treeitem][aria-label^=#{name.to_json}]", **options)

  # The headings of what the list shows, in its order: each group's (its
  # item's row) and a section's (the rows a filter or a pill brings).
  def list_headings = all("#{LIST} :is([data-tree-group] > .admin-tree-row, section h2)").map { |heading| heading.text.squish.upcase }

  # Opens the branches of `pages` in the open set both trees read, as a
  # person who opened them in Pages left it: a page below Home is folded
  # until it is opened. On a CS Studio page, before the graph is visited.
  def open_branches(*pages)
    page.execute_script("document.cookie = arguments[0]", "cs_tree_open=#{pages.map(&:id).join(".")}; path=/#{ContentSpiel::ADMIN_PATH}")
  end

  # A press on that row: on its own row, so an open parent's press never
  # lands on one of its children, which its item's middle may hold.
  def press_list_item(name, **options) = list_item(name, **options).find(:xpath, "./*[1]").click

  # Every mark of a row inside `selector` that is a canvas has been drawn:
  # something is on each one (a canvas that was never painted is all zeros).
  def assert_marks_drawn(selector)
    await_js(<<~JS)
      (() => {
        const canvases = Array.from(document.querySelectorAll(#{"#{selector} canvas[data-mark]".to_json}))
        return canvases.length > 0 && canvases.every((canvas) => canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height).data.some((value) => value > 0))
      })()
    JS
  end

  # Every swatch inside `selector` has been drawn by the graph's renderer:
  # something is on each one (a canvas that was never painted is all zeros).
  # `count:` the swatches there must be, so an empty match is no pass.
  def assert_swatches_drawn(selector, count:)
    assert_equal count, page.evaluate_script("document.querySelectorAll(#{"#{selector} canvas[data-swatch]".to_json}).length"), "swatches in #{selector}"
    await_js(<<~JS)
      Array.from(document.querySelectorAll(#{"#{selector} canvas[data-swatch]".to_json}))
        .every((canvas) => canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height).data.some((value) => value > 0))
    JS
  end

  # A real click where the node is drawn.
  def click_node(id)
    point = screen_position(id)
    assert point, "node #{id} is not on screen"
    page.driver.browser.mouse.click(x: point["x"], y: point["y"])
  end

  # Presses the mouse on a node and walks it `by` pixels in two steps, waiting
  # until the node is under the pointer again; releases unless told not to.
  # Answers where the node was dropped, in client coordinates.
  #
  # It first waits for the layout to be AT REST. A node is held where it was
  # grabbed, so one that is still easing (after an earlier drop, a filter, an
  # unpin) has moved on between this helper reading its place and the press
  # reaching the browser, and stays that far from the pointer for the whole
  # drag: on a slow runner that was more than the two pixels allowed below,
  # and "the node is where it was dropped" timed out. A person presses where
  # the node is; a test can only press where it was.
  def drag_node(id, by:, release: true, steps: 1)
    assert_selector "#{GRAPH}[data-settled]", wait: 15
    from = screen_position(id)
    assert from, "node #{id} is not on screen"
    to = { "x" => from["x"] + by[0], "y" => from["y"] + by[1] }
    mouse = page.driver.browser.mouse
    mouse.move(x: from["x"], y: from["y"])
    mouse.down
    mouse.move(x: from["x"] + (by[0] / 2), y: from["y"] + (by[1] / 2), steps: steps)
    mouse.move(x: to["x"], y: to["y"], steps: steps)
    await_js("(() => { const p = document.querySelector(#{GRAPH.to_json}).mindGraph.screenPosition(#{nid(id).to_json}); return Math.abs(p.x - #{to["x"]}) < 2 && Math.abs(p.y - #{to["y"]}) < 2 })()")
    mouse.up if release
    to
  end

  # The card stands 22 px from the edge of a node of one connection (a 7 px
  # dot), on the given side, and is vertically centred on it.
  def assert_card_beside(id, side: nil, radius: 7)
    node = screen_position(id)
    card = element_box("[data-mind-graph-card]")
    shown = find("[data-mind-graph-card]")["data-side"]
    assert_equal side, shown if side
    if shown == "right"
      assert_in_delta node["x"] + radius + 22, card["left"], 1.5, "the card is not 22 px right of the node: #{node} #{card}"
    else
      assert_in_delta node["x"] - radius - 22, card["right"], 1.5, "the card is not 22 px left of the node: #{node} #{card}"
    end
    assert_in_delta node["y"], (card["top"] + card["bottom"]) / 2, 1.5, "the card is not centred on the node: #{node} #{card}"
  end

  # An element's box in client coordinates.
  def element_box(selector)
    page.evaluate_script("(() => { const r = document.querySelector(#{selector.to_json}).getBoundingClientRect(); return { left: r.left, top: r.top, right: r.right, bottom: r.bottom, width: r.width, height: r.height } })()")
  end

  # The boxes the screen is made of, the window's height and the page's own.
  def layout_boxes
    page.evaluate_script(<<~JS)
      (() => {
        const box = (selector) => { const r = document.querySelector(selector).getBoundingClientRect(); return { left: r.left, top: r.top, right: r.right, bottom: r.bottom, width: r.width, height: r.height } }
        return {
          box: box(#{GRAPH.to_json}), canvas: box(#{CANVAS.to_json}), list: box(#{LIST.to_json}), search: box("#mind-graph-search"),
          main: document.querySelector("main").getBoundingClientRect().width, viewport: window.innerHeight, page: document.documentElement.scrollHeight
        }
      })()
    JS
  end

  # The canvas's colour where a pinned node's mark is: up and to the right of
  # the centre of a 7 px dot.
  def pin_pixel(post)
    point = screen_position(post)
    pixel_at(point["x"] + 5.04, point["y"] - 5.04)
  end

  # The canvas's colour where a node's notes badge is: up and to the LEFT of
  # the centre of a 7 px dot (the pin's corner is up and to the right).
  def notes_badge_pixel(post)
    point = screen_position(post)
    pixel_at(point["x"] - 5.04, point["y"] - 5.04)
  end

  # The browser says the person prefers reduced motion inside the block, and
  # not afterwards: it is shared with the tests that follow.
  def with_reduced_motion
    page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    yield
  ensure
    page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [])
  end

  # Records the type of every message a worker started from now on sends the
  # page (`tick`, `settled`, `error`), on a screen visited BEFORE the Mind
  # graph: how many steps a layout was shown in.
  def record_worker_answers
    page.execute_script(<<~JS)
      window.workerAnswers = []
      const Real = window.Worker
      window.Worker = class extends Real {
        constructor(...args) { super(...args); this.addEventListener("message", ({ data }) => window.workerAnswers.push(data.type)) }
      }
    JS
  end

  def worker_answers = page.evaluate_script("window.workerAnswers")

  # Records the type of every message the page sends a worker from now on
  # (the prototype's method, so the graph's own worker, already running, is
  # covered): what the layout is TOLD, which no pixel shows.
  def record_worker_messages
    page.execute_script(<<~JS)
      window.workerMessages = []
      const post = Worker.prototype.postMessage
      Worker.prototype.postMessage = function(message, ...rest) { window.workerMessages.push(message?.type); return post.call(this, message, ...rest) }
    JS
  end

  def worker_messages = page.evaluate_script("window.workerMessages")

  def graph = find(GRAPH)

  # A toggle of the legend, by the name on it. No `await_graph` is needed to
  # read what it shows: `data-nodes`, `data-edges`, the list and the canvas's
  # name are written by the change itself, before the layout moves.
  def toggle(name) = find("#{GRAPH} [data-mind-graph-legend] label", text: name).click

  # Each toggle as a person reads it: its name, and its count once written.
  def legend_counts = all("#{GRAPH} label[data-legend-toggle]").map { |label| label.text.squish }

  # The graph is loaded and its layout has cooled down -- and the frame that
  # was asked for when it did has been drawn. `data-settled` is written BEFORE
  # that frame, which is the one that writes `data-zoom` and `data-labelled`
  # for the final fit, so a test that read either straight after the selector
  # could find nothing there yet, or the value of the frame before.
  def await_graph
    assert_selector "#{GRAPH}[data-state='ready'][data-settled]", wait: 15
    await_frames
  end

  # No worker can be started inside the block (the constructor throws, as in a
  # browser that has none), and the real one is back afterwards whatever
  # happened: the window outlives a Turbo visit, and a test that fails halfway
  # must not leave the stub behind.
  def without_workers
    page.execute_script("window.RealWorker = window.Worker; window.Worker = class { constructor() { throw new Error('no workers here') } }")
    yield
  ensure
    page.execute_script("if (window.RealWorker) { window.Worker = window.RealWorker; delete window.RealWorker }")
  end

  # A node's id as the data and the page write it (the three tables count on their own):
  # of a record (a post, a tag, a page), or the id itself as a string
  # ("post-12", "type-blog"). NEVER of a bare number: 12 is a post, a tag
  # and a page at once, and a helper that read it as a post would press the
  # wrong node for the other two and call it found. A number is refused.
  def nid(node)
    case node
    when String then node
    when ApplicationRecord then "#{node.class.name.underscore}-#{node.id}"
    else raise ArgumentError, "a node is named by its record or by its id as a string (\"post-12\"), not by #{node.inspect}: a bare number names no kind"
    end
  end

  # Where the layout has a node, in graph units (the camera not applied).
  def graph_position(id) = page.evaluate_script("document.querySelector(#{GRAPH.to_json}).mindGraph.graphPosition(#{nid(id).to_json})")

  def screen_position(id)
    page.evaluate_script("document.querySelector(#{GRAPH.to_json}).mindGraph.screenPosition(#{nid(id).to_json})")
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

  # The canvas's colours at `samples` points evenly round a node's centre,
  # `radius` pixels from it: one read, after the frames `pixel_at` waits for.
  # `quadrant: :left` reads the quarter on the node's left only, where there
  # is no label. A sample is the pixel that CONTAINS its point (floor). The
  # point's CENTRE is fractional (the fitted view's zoom puts it at a fraction),
  # and rounding reads the NEAREST pixel's corner, i.e. the pixel after the
  # point for a fraction under one half, up to a pixel away, which put a sample
  # 8px out on the antialiased edge of a mark of radius 7; flooring reads the
  # pixel that contains the point.
  def ring_pixels(node, radius:, samples:, quadrant: nil)
    point = screen_position(node)
    await_frames
    page.evaluate_script(<<~JS)
      (() => {
        const canvas = document.querySelector(#{CANVAS.to_json})
        const box = canvas.getBoundingClientRect()
        const ratio = canvas.width / box.width
        const context = canvas.getContext("2d")
        return Array.from({ length: #{samples} }, (_, step) => {
          const angle = #{quadrant == :left ? "Math.PI * 0.75 + step * Math.PI / 2 / #{samples}" : "step * 2 * Math.PI / #{samples}"}
          const x = #{point["x"]} + #{radius} * Math.cos(angle), y = #{point["y"]} + #{radius} * Math.sin(angle)
          return Array.from(context.getImageData(Math.floor((x - box.left) * ratio), Math.floor((y - box.top) * ratio), 1, 1).data)
        })
      })()
    JS
  end

  # A post's mark at its centre and four pixels to the left of it.
  def pixels_of(post)
    point = screen_position(post)
    [ pixel_at(point["x"], point["y"]), pixel_at(point["x"] - 4, point["y"]) ]
  end
end
