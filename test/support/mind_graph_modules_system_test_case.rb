# The setup and the helpers the files of test/system/admin/mind_graph_*_modules_test.rb
# share. The mind graph's own modules (`app/javascript/mind_graph/`) are
# imported in the browser from any CS Studio page: the project has no
# JavaScript test runner, and these are plain modules the import map
# resolves, so a system test calls them directly and compares what they
# return. This base holds no test.
class Admin::MindGraphModulesSystemTestCase < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    visit admin_tags_path
    await_admin_controllers
  end

  private

  # The canvas's name, in the page's own words: the messages are the locale
  # file's, handed to the module as the view hands them, so each sentence is
  # read here as a screen reader says it.
  def node_set(pages: 0, types: 0, posts: 0, tags: 0, more: [], focus: nil)
    nodes = Array.new(pages) { |index| { kind: "page", id: "page-#{index + 1}" } } + Array.new(posts) { { kind: "post" } } + Array.new(tags) { { kind: "tag" } } +
            Array.new(types) { { kind: "type" } } + more.map { |count| { kind: "more", count: count } }
    nodes.first.merge!(focus) if focus
    nodes
  end

  ALL_ON = { nodes: [], lines: [] }.freeze

  # Runs `script` against a layout and answers what happened, in order:
  # "raw:<after>" for each `settled` the WORKER posted and "called" for each
  # `onSettled` the client made of them (for one message the client's handler
  # runs first: it was attached first). The script sets `onCall(count)`, which
  # is told of every `onSettled`, and ends the watch with `finish()`.
  def settled_log(script)
    using_wait_time(30) { settled_log_script(script) }
  end

  def settled_log_script(script)
    page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"), ActionController::Base.helpers.asset_path("d3-force.js"))
      const [workerUrl, d3Url, done] = arguments
      const Real = window.Worker
      let worker = null
      window.Worker = class extends Real { constructor(...args) { super(...args); worker = this } }
      import("mind_graph/layout_client").then(({ createLayout }) => {
        const log = []
        let count = 0
        let onCall = () => {}
        // A task later, so the watch's own listener has logged the message
        // that ended it.
        const finish = () => setTimeout(() => { layout.stop(); window.Worker = Real; done(log) }, 0)
        const layout = createLayout({
          workerUrl, d3Url,
          onTick: () => {},
          onSettled: () => { log.push("called"); count += 1; onCall(count) },
          onError: (message) => { log.push(`error: ${message}`); finish() }
        })
        worker.addEventListener("message", ({ data }) => { if (data.type === "settled") log.push(`raw:${data.after}`) })
        #{script}
      })
    JS
  end

  # Attaches `mind_graph/input` to a canvas made for the test, runs `script`
  # (which has `fire(type, pointerId, x, y, pointerType = "touch")`) and answers the callbacks made,
  # in order, as [name, *arguments]. `target:` is what `onPress` answers: true
  # makes a press the start of a drag, false of a pan.
  def input_calls(script, target: false)
    page.evaluate_async_script(<<~JS, target)
      const [target, done] = arguments
      import("mind_graph/input").then(({ attachInput }) => {
        const canvas = document.createElement("canvas")
        canvas.style.cssText = "position: fixed; left: 0; top: 0; width: 600px; height: 400px; z-index: 1000"
        document.body.append(canvas)
        const calls = []
        const record = (name) => (...args) => { calls.push([name, ...args.map((value) => Math.round(value * 1000) / 1000)]) }
        const detach = attachInput(canvas, {
          onPress: (x, y) => { calls.push(["press", x, y]); return target ? "node" : null },
          onDrag: record("drag"), onDrop: record("drop"), onPan: record("pan"), onClick: record("click"),
          onDoubleClick: record("doubleclick"), onZoom: record("zoom"), onHover: record("hover"), onEscape: record("escape")
        })
        const fire = (type, pointerId, x, y, pointerType = "touch") => canvas.dispatchEvent(new PointerEvent(type, { pointerId, pointerType, isPrimary: pointerId === 1, button: 0, clientX: x, clientY: y, bubbles: true, cancelable: true }))
        const doubleClick = (x, y) => canvas.dispatchEvent(new MouseEvent("dblclick", { clientX: x, clientY: y, bubbles: true, cancelable: true }))
        #{script}
        detach()
        canvas.remove()
        done(calls)
      })
    JS
  end

  # Draws one frame through `mind_graph/renderer` onto a context that only
  # records, on a 200 x 100 canvas with the camera at rest: every position is
  # a live post of degree one (radius 7) -- or, for an index in `tags`, a tag
  # of degree one (half side 4.5) -- and `edges` are pairs of node indexes.
  # `selected` / `hovered` are indexes, `pinned` a list of them; the selected
  # node's neighbours are the nodes its edges reach. Answers:
  # - `lines`: the line segments stroked as [x1, y1, x2, y2];
  # - `arcs`: the centres of the circles drawn; `circles`: the same with radii;
  # - `rects`: the squares put into a path (a tag's ring) as [x, y, w, h];
  # - `strokes`: for each edge pass, its segments flattened (nil for an empty
  #   pass) and the strength it was stroked at;
  # - `nodeAlphas`: the strength each post's mark was filled at, in order;
  # - `ringWidths`: the line widths of the rings.
  NODE_RADIUS = 7

  PIN_RADIUS = 3

  def renderer_calls(positions:, edges:, selected: -1, hovered: -1, pinned: [], tags: [])
    log = page.evaluate_async_script(<<~JS, positions, edges, selected, hovered, pinned, tags)
      const [positions, pairs, selected, hovered, pinned, tags, done] = arguments
      import("mind_graph/renderer").then(({ draw, radiusFor }) => {
        const round = (value) => Math.round(value * 1000) / 1000
        const log = []
        const set = {}
        let from = null
        const context = new Proxy({}, {
          get: (_, name) => {
            if (name === "moveTo") return (x, y) => { from = [x, y] }
            if (name === "lineTo") return (x, y) => { log.push(["line", ...from, x, y]) }
            if (name === "arc") return (x, y, radius) => { log.push(["arc", round(x), round(y), round(radius)]) }
            if (name === "rect") return (...box) => { log.push(["rect", ...box.map(round)]) }
            if (name === "beginPath" || name === "fill" || name === "stroke") return () => { log.push([name, round(set.globalAlpha), set.lineWidth]) }
            return () => {}
          },
          set: (_, name, value) => { set[name] = value; return true }
        })
        const nodes = Array.from({ length: positions.length / 2 }, (_, id) => ({ id, kind: tags.includes(id) ? "tag" : "post", degree: 1, colour_index: 1, status: "live", label: "" }))
        const neighbours = new Set(pairs.flatMap(([source, target]) => (source === selected ? [target] : target === selected ? [source] : [])))
        draw(context, {
          width: 200, height: 100, ratio: 1, camera: { k: 1, tx: 0, ty: 0 },
          theme: #{recording_theme(ink: "", meta: "", surface: "", sunken: "", accent: "", categories: Array.new(6, ""), font: "", strongFont: "", dim: nil, warn: nil, line: nil, faint: nil, page: nil, tree: nil, radius: nil, monoFont: nil, strongMonoFont: nil, countFont: nil)},
          nodes, edges: pairs.map(([source, target]) => ({ source, target, kind: "related" })), positions: Float32Array.from(positions),
          radii: nodes.map(radiusFor), widths: nodes.map(() => 0), visibleNodes: nodes.map((_, index) => index), visibleEdges: pairs.map((_, index) => index),
          labels: [], selected, neighbours, focusIndex: -1, hovered, pinned: new Set(pinned)
        })
        done(log)
      }).catch((error) => done({ error: String(error) }))
    JS
    flunk "renderer: #{log["error"]}" if log.is_a?(Hash)

    # Each path -- from one `beginPath` to the next -- with what was done to it.
    paths = log.slice_before { |entry| entry.first == "beginPath" }.map { |entries| entries.drop(1) }
    shape = ->(path) { path.find { |entry| %w[arc rect line].include?(entry.first) } }
    done = ->(path, name) { path.find { |entry| entry.first == name } }
    edge_passes = paths.take_while { |path| shape.call(path).nil? || shape.call(path).first == "line" }
    rings = paths.select { |path| shape.call(path)&.first == "rect" || (shape.call(path)&.first == "arc" && ![ NODE_RADIUS, PIN_RADIUS ].include?(shape.call(path)[3])) }
    {
      "lines" => log.select { |entry| entry.first == "line" }.map { |entry| entry.drop(1) },
      "arcs" => log.select { |entry| entry.first == "arc" }.map { |entry| entry[1, 2] },
      "circles" => log.select { |entry| entry.first == "arc" }.map { |entry| entry.drop(1) },
      "rects" => log.select { |entry| entry.first == "rect" }.map { |entry| entry.drop(1) },
      "strokes" => edge_passes.map { |path| [ path.select { |entry| entry.first == "line" }.flat_map { |entry| entry.drop(1) }.presence, done.call(path, "stroke")[1] ] },
      "nodeAlphas" => paths.select { |path| shape.call(path) == [ "arc", *shape.call(path)&.slice(1, 2), NODE_RADIUS ] }.map { |path| done.call(path, "fill")[1] },
      "ringWidths" => rings.map { |path| done.call(path, "stroke")[2] }
    }
  end

  # Draws `nodes` (posts of degree one unless they say otherwise) at
  # `positions` and answers, in order, every fillText as ["fillText", text],
  # every roundRect as ["roundRect"] and every fill as ["fill", fillStyle,
  # globalAlpha]; `labels` are node indexes drawn at `labelAt`'s place.
  def draw_calls(nodes, positions:, labels:)
    drawn = page.evaluate_async_script(<<~JS, nodes, positions, labels)
      const [given, positions, labelled, done] = arguments
      import("mind_graph/renderer").then(({ draw, radiusFor }) => {
        const log = []
        const set = {}
        const context = new Proxy({}, {
          get: (_, name) => {
            if (name === "fillText") return (text) => { log.push(["fillText", text]) }
            if (name === "roundRect") return () => { log.push(["roundRect"]) }
            if (name === "fill") return () => { log.push(["fill", set.fillStyle, set.globalAlpha]) }
            return () => {}
          },
          set: (_, name, value) => { set[name] = value; return true }
        })
        const nodes = given.map((node, index) => ({ id: `n-${index}`, kind: "post", degree: 1, colour_index: 1, status: "live", ...node }))
        const radii = nodes.map(radiusFor)
        draw(context, {
          width: 400, height: 300, ratio: 1, camera: { k: 1, tx: 0, ty: 0 },
          theme: #{recording_theme},
          nodes, edges: [], positions: Float32Array.from(positions), radii, widths: nodes.map(() => 0),
          visibleNodes: nodes.map((_, index) => index), visibleEdges: [],
          labels: labelled.map((index) => ({ index, alpha: 1, x: positions[index * 2] + radii[index] + 4, y: positions[index * 2 + 1] })),
          selected: -1, neighbours: new Set(), focusIndex: -1, hovered: -1, pinned: new Set()
        })
        done(log)
      }).catch((error) => done({ error: String(error) }))
    JS
    flunk "renderer: #{drawn["error"]}" if drawn.is_a?(Hash)
    drawn
  end

  # Draws posts of degree one (radius 7), 100 px apart from x = 50 at y = 50,
  # with the given `open_notes` each (nil: the key is absent), then the tags
  # of `tags` (indexes) with `tag_notes`. Answers, in order, each notes badge
  # as ["pill", x, y, width, height, radius, fill], ["line", stroke, width]
  # and ["text", label, x, y, fill, font], and each pin's dot as
  # ["pin", x, y, radius]. The theme's values are their own names.
  def notes_badges(counts, pinned: [], tags: [], tag_notes: nil)
    drawn = page.evaluate_async_script(<<~JS, counts, pinned, tags, tag_notes)
      const [counts, pinned, tags, tagNotes, done] = arguments
      import("mind_graph/renderer").then(({ draw, radiusFor }) => {
        const round = (value) => Math.round(value * 1000) / 1000
        const log = []
        const set = {}
        let badge = null
        const context = new Proxy({}, {
          get: (_, name) => {
            if (name === "beginPath") return () => { badge = null }
            if (name === "roundRect") return (...box) => { badge = box.map(round) }
            if (name === "arc") return (x, y, radius) => { if (radius === #{PIN_RADIUS}) log.push(["pin", round(x), round(y), radius]) }
            if (name === "fill") return () => { if (badge) log.push(["pill", ...badge, set.fillStyle]) }
            if (name === "stroke") return () => { if (badge) log.push(["line", set.strokeStyle, set.lineWidth]) }
            if (name === "fillText") return (label, x, y) => { log.push(["text", label, round(x), round(y), set.fillStyle, set.font]) }
            return () => {}
          },
          set: (_, name, value) => { set[name] = value; return true }
        })
        const nodes = counts.map((count, id) => ({ id, kind: "post", degree: 1, colour_index: 1, status: "live", label: "", ...(count == null ? {} : { open_notes: count }) }))
        tags.forEach((id) => nodes.push({ id, kind: "tag", degree: 1, label: "", open_notes: tagNotes }))
        draw(context, {
          width: 100 * nodes.length, height: 100, ratio: 1, camera: { k: 1, tx: 0, ty: 0 },
          theme: #{recording_theme(meta: "", sunken: "", categories: Array.new(6, "hue"), font: "", strongFont: "", dim: nil, warn: nil, faint: nil, page: nil, tree: nil, radius: nil, monoFont: nil, strongMonoFont: nil)},
          nodes, edges: [], positions: Float32Array.from(nodes.flatMap((_, index) => [ 50 + index * 100, 50 ])),
          radii: nodes.map(radiusFor), widths: nodes.map(() => 0), visibleNodes: nodes.map((_, index) => index), visibleEdges: [],
          labels: [], selected: -1, neighbours: new Set(), focusIndex: -1, hovered: -1, pinned: new Set(pinned)
        })
        done(log)
      }).catch((error) => done({ error: String(error) }))
    JS
    flunk "renderer: #{drawn["error"]}" if drawn.is_a?(Hash)
    drawn
  end

  # A canvas context that records (`marks_drawn`, `swatch_drawn`): `log`
  # holds what was filled, stroked and written, each with where it is.
  RECORDING_CONTEXT = <<~'JS'.freeze
    const round = (value) => Math.round(value * 100) / 100
    const log = []
    const set = { dash: [] }
    let shape = null
    const box = (x, y, width, height, ...radius) => [ round(x + width / 2), round(y + height / 2), "box", width, height, ...radius ]
    // A stroked shape by its outer edge: half the line's width more, each way.
    const outer = ([ cx, cy, kind, ...sizes ]) => {
      const half = set.lineWidth / 2
      if (kind === "circle") return [ cx, cy, kind, round(sizes[0] + half) ]
      if (kind === "box") return [ cx, cy, kind, round(sizes[0] + half * 2), round(sizes[1] + half * 2), ...sizes.slice(2).map((radius) => round(radius + half)) ]
      return [ cx, cy, kind ]
    }
    const context = new Proxy({}, {
      get: (_, name) => {
        if (name === "beginPath") return () => { shape = null }
        if (name === "arc") return (x, y, radius) => { shape = [round(x), round(y), "circle", round(radius)] }
        if (name === "rect") return (x, y, width, height) => { shape = box(x, y, width, height) }
        if (name === "roundRect") return (x, y, width, height, radius) => { shape = box(x, y, width, height, radius) }
        if (name === "moveTo") return (x, y) => { shape = [round(x), round(y), "line"] }
        if (name === "setLineDash") return (dash) => { set.dash = dash }
        if (name === "setTransform") return (scale) => { set.scale = scale }
        if (name === "fillRect") return (x, y, width, height) => { const [ cx, cy, ...rest ] = box(x, y, width, height); log.push([cx, cy, "fill", ...rest, set.fillStyle]) }
        if (name === "strokeRect") return (x, y, width, height) => { const [ cx, cy, ...rest ] = outer(box(x, y, width, height)); log.push([cx, cy, "stroke", ...rest, set.strokeStyle, set.lineWidth, set.dash]) }
        if (name === "fillText") return (words, x, y) => { log.push([round(x), round(y), "text", words, set.font, set.fillStyle]) }
        if (name === "fill") return () => { if (shape) log.push([shape[0], shape[1], "fill", ...shape.slice(2), set.fillStyle]) }
        if (name === "stroke") return () => { if (shape) { const [ cx, cy, ...rest ] = outer(shape); log.push([cx, cy, "stroke", ...rest, set.strokeStyle, set.lineWidth, set.dash]) } }
        return () => {}
      },
      set: (_, name, value) => { set[name] = value; return true }
    })
  JS

  # Draws the given nodes 100 pixels apart (the first at 50, 50) against a
  # context that records, with a theme whose values are their own names, and
  # answers per node what was filled, stroked and written, in order:
  # `[ "fill", shape, sizes…, colour ]`, `[ "stroke", shape, sizes…, colour,
  # width, dash ]` and `[ "text", words, font, colour ]`, where a circle's
  # size is its radius, a box's its width, height and (rounded) its corner
  # radius, and a line has none. A STROKE'S SIZE IS ITS OUTER SIZE, the
  # path's plus half the line's width each way: what a person sees of it,
  # and what the design gives ("14 by 10", "radius 7"). So an outline drawn
  # inside its mark's edge reads as the mark's own size, and one centred on
  # the edge as three quarters of a pixel more. `places: true` puts where the part is in
  # front of each -- its centre from the node's centre, x then y (a line's:
  # where it starts). `labels: true` draws every node's label; `selected`,
  # `hovered` and `pinned` are indexes.
  def marks_drawn(nodes, places: false, labels: false, selected: -1, hovered: -1, pinned: [], round_rect: true)
    drawn = page.evaluate_async_script(<<~JS, nodes, labels, selected, hovered, pinned, round_rect)
      const [given, labelled, selected, hovered, pinned, roundRect, done] = arguments
      import("mind_graph/renderer").then(({ draw, radiusFor }) => {
        #{RECORDING_CONTEXT}
        // A browser whose canvas has no roundRect (it is newer than the rest).
        const surface = roundRect ? context : new Proxy(context, { get: (target, name) => (name === "roundRect" ? undefined : target[name]), set: (target, name, value) => { target[name] = value; return true } })
        const nodes = given.map((node, index) => ({ id: `n-${index}`, kind: "post", degree: 1, colour_index: 1, status: "live", label: "", ...node }))
        const positions = Float32Array.from(nodes.flatMap((_, index) => [ 50 + index * 100, 50 ]))
        const radii = nodes.map(radiusFor)
        draw(surface, {
          width: 100 * nodes.length, height: 100, ratio: 1, camera: { k: 1, tx: 0, ty: 0 },
          theme: #{recording_theme},
          nodes, edges: [], positions,
          radii, widths: nodes.map(() => 0), visibleNodes: nodes.map((_, index) => index), visibleEdges: [],
          // A label 20px right of its mark's centre, on the node's own line.
          labels: labelled ? nodes.map((_, index) => ({ index, alpha: 1, x: 70 + index * 100, y: 50, ...(index === hovered ? { hover: true } : {}) })) : [],
          selected, neighbours: new Set(), focusIndex: -1, hovered, pinned: new Set(pinned)
        })
        done(log)
      }).catch((error) => done({ error: String(error) }))
    JS
    flunk "renderer: #{drawn["error"]}" if drawn.is_a?(Hash)
    by_node = drawn.group_by { |x, *| (x / 100).floor }
    nodes.each_index.map do |index|
      by_node.fetch(index, []).map { |x, y, *rest| places ? [ (x - 50 - index * 100).to_f.round(2), (y - 50).to_f.round(2), *rest ] : rest }
    end
  end

  # The shapes a frame puts into a path or draws at once, per node, whatever
  # is then done with them: `[ "circle", dx, dy, radius ]` and `[ "box", dx,
  # dy, width, height, (corner radius) ]`, each from the node's centre (a
  # box's by its own centre). For what hangs on a mark and rings it.
  def shapes_drawn(nodes, **state)
    marks_drawn(nodes, places: true, **state).map do |drawn|
      drawn.filter_map do |dx, dy, _done, shape, *rest|
        sizes = rest.take_while { |value| value.is_a?(Numeric) }
        [ shape, dx, dy, *sizes ] if %w[circle box].include?(shape)
      end.uniq
    end
  end

  # One frame of three tags with a line of each given kind from the first to
  # the second: each stroked pass that holds a line, as `[colour, width,
  # dash, strength, cap]`, in the order drawn.
  def lines_drawn(kinds, k: 1, selected: -1)
    drawn = page.evaluate_async_script(<<~JS, kinds, k, selected)
      const [kinds, k, selected, done] = arguments
      import("mind_graph/renderer").then(({ draw, radiusFor }) => {
        const log = []
        const set = { dash: [] }
        let lines = 0
        const context = new Proxy({}, {
          get: (_, name) => {
            if (name === "beginPath") return () => { lines = 0 }
            if (name === "lineTo") return () => { lines += 1 }
            if (name === "setLineDash") return (dash) => { set.dash = dash }
            if (name === "stroke") return () => { if (lines) log.push([set.strokeStyle, set.lineWidth, set.dash, Math.round(set.globalAlpha * 1000) / 1000, set.lineCap]); lines = 0 }
            return () => {}
          },
          set: (_, name, value) => { set[name] = value; return true }
        })
        const nodes = [0, 1, 2].map((id) => ({ id, kind: "tag", degree: 1, label: "" }))
        draw(context, {
          width: 400, height: 100, ratio: 1, camera: { k, tx: 0, ty: 0 },
          theme: #{recording_theme(categories: Array.new(6, "hue"), font: "", strongFont: "", monoFont: "", strongMonoFont: nil, countFont: nil)},
          nodes, edges: kinds.map((kind) => ({ source: 0, target: 1, kind })), positions: Float32Array.from([ 10 / k, 10 / k, 60 / k, 10 / k, 300 / k, 80 / k ]),
          radii: nodes.map(radiusFor), widths: [0, 0, 0], visibleNodes: [0, 1, 2], visibleEdges: kinds.map((_, index) => index),
          labels: [], selected, neighbours: new Set(selected === 0 ? [1] : []), focusIndex: -1, hovered: -1, pinned: new Set()
        })
        done(log)
      }).catch((error) => done({ error: String(error) }))
    JS
    flunk "renderer: #{drawn["error"]}" if drawn.is_a?(Hash)
    drawn
  end

  # What the swatch called `name` draws, at its size in the page
  # (`SwatchComponent::SIZES`), against the recording context and the theme
  # of `marks_drawn`: each part as `[ x, y, "fill" | "stroke" | "text", … ]`.
  def swatch_drawn(name)
    width, height = Admin::MindGraphScreen::SwatchComponent::SIZES.fetch(name.to_sym)
    drawn = page.evaluate_async_script(<<~JS, name, width, height)
      const [name, width, height, done] = arguments
      import("mind_graph/swatches").then(({ drawSwatch }) => {
        #{RECORDING_CONTEXT}
        drawSwatch(context, #{recording_theme},
          name, { width, height })
        done(log)
      }).catch((error) => done({ error: String(error) }))
    JS
    flunk "swatches: #{drawn["error"]}" if drawn.is_a?(Hash)
    drawn
  end

  # What a row's mark draws (`swatches.js`, `drawRowMark`) against the
  # recording context and the theme of `marks_drawn`: its parts as
  # `swatch_drawn` answers them, the scale the drawing has, and its canvas's
  # size in the page.
  def row_mark_drawn(kind, of)
    drawn = page.evaluate_async_script(<<~JS, kind, of)
      const [kind, of, done] = arguments
      import("mind_graph/swatches").then(({ drawRowMark, ROW_MARKS }) => {
        #{RECORDING_CONTEXT}
        drawRowMark(context, #{recording_theme},
          { kind, of })
        done({ parts: log, scale: set.scale, width: ROW_MARKS[kind].width, height: ROW_MARKS[kind].height })
      }).catch((error) => done({ error: String(error) }))
    JS
    flunk "swatches: #{drawn["error"]}" if drawn["error"]
    drawn
  end

  # The canvas's name for each given case, in the locale file's words. A
  # case: `nodes`, `visible` (indexes; every node unless given), `lines`,
  # `data`, `off` (nothing unless given), `around_home`, `toggles` (how many
  # kinds the viewer has a toggle for: four unless given).
  def summaries(*cases)
    keys = I18n.t("admin.mind_graph.script.summary").flat_map { |key, value| value.is_a?(Hash) && !value.key?(:other) ? value.keys.map { |inner| "#{key}.#{inner}" } : [ key ] }
    messages = Class.new { include Admin::MessagesHelper }.new.messages_data("mind_graph.script.capped", "mind_graph.script.isolated_only", *keys.map { |key| "mind_graph.script.summary.#{key}" })
    given = cases.map { |one| { visible: one[:nodes].each_index.to_a, off: ALL_ON, around_home: false, toggles: 4 }.merge(one) }
    result = page.evaluate_async_script(<<~JS, messages, given)
      const [json, cases, done] = arguments
      Promise.all([ import("mind_graph/summary"), import("i18n/messages") ]).then(([ { summaryOf }, { messages } ]) => {
        const holder = document.createElement("div")
        holder.setAttribute("data-messages", json)
        const tools = { text: messages(holder), number: (value) => new Intl.NumberFormat("en").format(value) }
        done(cases.map((one) => summaryOf({ nodes: one.nodes, visibleNodes: one.visible, lines: one.lines, data: one.data, off: one.off, toggles: one.toggles, aroundHome: one.around_home }, tools)))
      }).catch((error) => done({ error: String(error) }))
    JS
    flunk "summary: #{result["error"]}" if result.is_a?(Hash)
    result
  end

  # Imports a module of the page's import map and answers `expression`, in
  # which the module is `m`.
  # The theme every recorded draw is given, as a JavaScript object literal:
  # each colour and font is its own name, so a drawn part says which one it
  # was drawn with. A key given replaces the default and one given as nil is
  # left out, for a draw that is meant to meet a theme without it.
  def recording_theme(**overrides)
    {
      ink: "ink", meta: "meta", dim: "dim", warn: "warn", surface: "surface", sunken: "sunken", accent: "accent", line: "line", faint: "faint", page: "page", tree: "tree", radius: 4,
      categories: (1..6).map { |slot| "cat-#{slot}" }, font: "sans", strongFont: "strong", monoFont: "mono", strongMonoFont: "strongMono", countFont: "count"
    }.merge(overrides).compact.to_json
  end

  def js_module(path, expression)
    result = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import(#{path.to_json}).then((m) => done(#{expression})).catch((error) => done({ error: String(error) }))
    JS
    flunk "#{path}: #{result["error"]}" if result.is_a?(Hash) && result.keys == [ "error" ]
    result
  end
end
