// The mind graph, wired together (mind graph canvas spec §4): fetch the data,
// hand the layout to the worker, and redraw the canvas when something changed.
// `mount(element)` is everything `admin--mind-graph` asks for; `destroy()`
// stops all of it -- the request, the worker, the frame, the observers -- so
// nothing runs or draws after the screen is left.
//
// What the screen shows is said on the element, for tests and for anything
// that wants to know without reading a canvas: `data-state` (loading, ready,
// failed, worker-failed), `data-settled`, `data-nodes`, `data-edges`,
// `data-zoom`, `data-labelled`. `element.mindGraph.screenPosition(id)` answers
// where a visible node is, in client coordinates, and `.draws()` how many
// frames have been drawn.
//
// THE CAMERA. The first view fits everything: while the layout takes shape the
// camera follows it, and when it has cooled down the fit is final
// (`state.fitted`). From then on -- or from the user's first zoom or pan, if
// that comes sooner -- the camera moves only on the user's input or "Fit all":
// a filter, a resize and a later reheat of the layout leave it where it is.
// Nodes are not clamped to the box; the box is a window onto the graph.
import { messages } from "i18n/messages"
import { createLayout } from "mind_graph/layout_client"
import { identity, toGraph, zoomAt, panBy, bounds, fit } from "mind_graph/camera"
import { nodeAt } from "mind_graph/hit_test"
import { chooseLabels } from "mind_graph/labels"
import { readTheme, watchTheme } from "mind_graph/theme"
import { draw, radiusFor } from "mind_graph/renderer"
import { attachInput } from "mind_graph/input"

// A label longer than this is cut with an ellipsis; a tag's count is appended
// whole. Counted by code point, so an emoji is never cut in half. Exported for
// the test that asks it directly: a drawn label is not an element to read.
const MAX_LABEL_CHARACTERS = 32
const BUTTON_ZOOM = 1.4
// How long the data request may go unanswered before it is given up and shown
// as a failure, with Retry (spec §6).
const LOAD_TIMEOUT_MS = 15_000

export function labelFor(node) {
  const suffix = node.kind === "tag" ? ` (${node.count})` : ""
  const room = MAX_LABEL_CHARACTERS - Array.from(suffix).length
  const characters = Array.from(String(node.title))
  return (characters.length > room ? `${characters.slice(0, room - 1).join("")}…` : characters.join("")) + suffix
}

export function mount(element) {
  const canvas = element.querySelector("canvas")
  const notice = element.querySelector("[data-admin--mind-graph-target='notice']")
  const context = canvas.getContext("2d")
  const text = messages(element)
  const aborter = new AbortController()
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)")
  // The state later tasks extend. `edges[i].source` / `.target`, `visibleNodes`,
  // `visibleEdges`, `selected`, `neighbours` and `focusIndex` are all INDEXES
  // into `nodes` (or `edges`); `positions` is the worker's x/y pairs, in the
  // order of `nodes`. `order` is the visible nodes, best-connected first.
  const state = {
    nodes: [], edges: [], positions: new Float32Array(0), radii: [], widths: [], order: [],
    visibleNodes: [], visibleEdges: [], camera: identity(), selected: -1, neighbours: new Set(), focusIndex: -1,
    theme: readTheme(canvas), width: 0, height: 0, ratio: 1, fitted: false, data: null
  }
  let destroyed = false
  let layout = null
  let frame = null
  let draws = 0
  let labelled = null
  let zoom = null

  const mode = () => element.querySelector("input[name=mind_graph_filter]:checked")?.value || "all"
  const setState = (value) => { element.dataset.state = value }

  // A figure that goes into a sentence is written the way the sentence's
  // language writes it (the messages' `@locale`), not the browser's own. A
  // tag `Intl` does not know falls back to the plain digits.
  function number(value) {
    try {
      return new Intl.NumberFormat(text.locale()).format(value)
    } catch {
      return String(value)
    }
  }

  // The lines over the canvas's top-left corner (a polite live region). A line is a string or a node
  // (the Retry button); always `textContent`, never markup.
  function say(...lines) {
    notice.replaceChildren(...lines.filter(Boolean).map((line) => {
      const paragraph = document.createElement("p")
      paragraph.className = "m-0 w-fit rounded-cs bg-surface px-1"
      if (line instanceof Node) paragraph.append(line)
      else paragraph.textContent = line
      return paragraph
    }))
  }

  // One redraw per animation frame, and only when something asked for one.
  function requestDraw() {
    if (destroyed || frame != null) return
    frame = requestAnimationFrame(() => {
      frame = null
      if (destroyed || state.width === 0) return

      const always = new Set(state.neighbours)
      if (state.selected >= 0) always.add(state.selected)
      if (state.focusIndex >= 0) always.add(state.focusIndex)
      const labels = chooseLabels({ order: state.order, positions: state.positions, widths: state.widths, radii: state.radii,
        camera: state.camera, width: state.width, height: state.height, always })
      // With reduced motion a label switches on, it does not fade in (§5.2).
      if (reducedMotion.matches) labels.forEach((label) => { label.alpha = 1 })
      draw(context, { ...state, labels })
      draws += 1

      // Written only when changed: a pan redraws every frame and changes neither.
      const k = state.camera.k.toFixed(3)
      if (k !== zoom) element.dataset.zoom = zoom = k
      const ids = labels.map((label) => state.nodes[label.index].id).join(",")
      if (ids !== labelled) element.dataset.labelled = labelled = ids
    })
  }

  // The canvas's bitmap is the box times the device pixel ratio. A box with no
  // size (a Turbo cache preview, a hidden tab) draws nothing; the observer
  // calls again when it gets one, and that first real size fits the view.
  function resize() {
    const box = canvas.getBoundingClientRect()
    const ratio = window.devicePixelRatio || 1
    if (box.width === state.width && box.height === state.height && ratio === state.ratio) return

    state.width = box.width
    state.height = box.height
    state.ratio = ratio
    canvas.width = Math.round(box.width * ratio)
    canvas.height = Math.round(box.height * ratio)
    if (!state.fitted && element.hasAttribute("data-settled")) fitAll()
    requestDraw()
  }

  function fitAll() {
    if (state.width === 0) return
    state.camera = fit(bounds(state.positions, state.visibleNodes), state.width, state.height)
    state.fitted = true
    requestDraw()
  }

  function hit(x, y) {
    return nodeAt({ positions: state.positions, indexes: state.visibleNodes, radii: state.radii, camera: state.camera, sx: x, sy: y })
  }

  // What the filter shows: every edge of the chosen kind, and under "All"
  // every node, otherwise only the nodes such an edge touches.
  function applyFilter() {
    const chosen = mode()
    state.visibleEdges = state.edges.flatMap((edge, index) => (chosen === "all" || edge.kind === chosen ? [ index ] : []))
    const touched = new Set(state.visibleEdges.flatMap((index) => [ state.edges[index].source, state.edges[index].target ]))
    state.visibleNodes = state.nodes.flatMap((_, index) => (chosen === "all" || touched.has(index) ? [ index ] : []))
    state.order = state.visibleNodes.slice().sort((a, b) => state.nodes[b].degree - state.nodes[a].degree || a - b)
    // The selection goes with a node the filter hides; one that stays keeps
    // its place, but its neighbours are the ones the shown edges give it now,
    // so nothing stays lit (or dimmed) by an edge that is no longer drawn.
    if (state.selected >= 0) select(state.visibleNodes.includes(state.selected) ? state.selected : -1)
    element.dataset.nodes = state.visibleNodes.length
    element.dataset.edges = state.visibleEdges.length
  }

  function select(index) {
    state.selected = index
    state.neighbours = new Set()
    if (index >= 0) {
      for (const edgeIndex of state.visibleEdges) {
        const edge = state.edges[edgeIndex]
        if (edge.source === index) state.neighbours.add(edge.target)
        if (edge.target === index) state.neighbours.add(edge.source)
      }
    }
    element.dataset.selected = index >= 0 ? state.nodes[index].id : ""
    requestDraw()
  }

  function show(data) {
    state.data = data
    state.nodes = [ ...data.nodes.map((node) => ({ ...node, kind: "post" })), ...data.tags.map((tag) => ({ ...tag, title: tag.name, kind: "tag" })) ]
    const indexOf = new Map(state.nodes.map((node, index) => [ node.id, index ]))
    state.edges = data.edges.map((edge) => ({ kind: edge.kind, source: indexOf.get(edge.source), target: indexOf.get(edge.target) }))
    state.positions = new Float32Array(state.nodes.length * 2)
    state.radii = state.nodes.map(radiusFor)
    context.font = state.theme.font
    state.nodes.forEach((node) => { node.label = labelFor(node) })
    state.widths = state.nodes.map((node) => context.measureText(node.label).width)
    state.focusIndex = data.focus ? indexOf.get(data.focus.node_id) ?? -1 : -1
    state.selected = -1
    state.neighbours = new Set()
    state.fitted = false
    applyFilter()
    // The canvas is one image to a screen reader, and its name says what is on it.
    canvas.setAttribute("aria-label", text.t("mind_graph.script.summary", { posts: state.nodes.length, edges: state.edges.length }))

    say(
      state.edges.length === 0 ? text.t("mind_graph.script.no_connections") : null,
      data.shown < data.total ? text.t("mind_graph.script.capped", { shown: number(data.shown), total: number(data.total) }) : null,
      data.isolated > 0 ? text.t("mind_graph.script.isolated", { count: data.isolated }) : null
    )
    setState("ready")

    // Nothing to lay out: settled as it stands, and no worker is started.
    if (state.nodes.length === 0) {
      element.setAttribute("data-settled", "")
      return requestDraw()
    }
    startLayout()
  }

  function startLayout() {
    try {
      layout = createLayout({
        workerUrl: element.dataset.workerUrl,
        d3Url: element.dataset.d3Url,
        onTick: (positions) => {
          state.positions = positions
          // The first view fits everything as soon as there is a shape to fit;
          // after that the camera moves only when the user moves it.
          if (!state.fitted) state.camera = fit(bounds(positions, state.visibleNodes), state.width, state.height)
          requestDraw()
        },
        // Only a `settled` that answers everything sent so far arrives here
        // (`layout_client.js`), so with a filter sent right behind `start` --
        // Back to a screen whose control says "Related" -- the fit is made on
        // the filtered layout, not on the one before it.
        onSettled: () => {
          if (!state.fitted) fitAll()
          element.setAttribute("data-settled", "")
        },
        onError: workerFailed
      })
    } catch (error) {
      return workerFailed(error.message)
    }
    // The worker handles its messages strictly in order, so the filter may
    // follow `start` at once.
    layout.start(state.nodes.map((node, index) => ({ id: node.id, radius: state.radii[index] })),
      state.edges.map((edge) => ({ source: state.nodes[edge.source].id, target: state.nodes[edge.target].id })))
    if (mode() !== "all") sendFilter()
  }

  function sendFilter() {
    layout?.filter(state.visibleNodes.map((index) => state.nodes[index].id), state.visibleEdges)
  }

  // Loud on purpose: the system tests fail on any console error, so a worker
  // that breaks is never a graph that silently stays empty. No Retry: a
  // browser that can't run the worker can't run it a second time either.
  function workerFailed(message) {
    if (destroyed) return
    console.error(`mind graph: the layout worker failed: ${message}`)
    layout?.stop()
    layout = null
    element.removeAttribute("data-settled")
    setState("worker-failed")
    say(text.t("mind_graph.script.worker_failed"))
  }

  async function load() {
    setState("loading")
    element.removeAttribute("data-settled")
    say(text.t("mind_graph.script.loading"))
    try {
      // Two ways out of a request that is still open: leaving the screen
      // (`aborter`, an AbortError, silent) and no answer in time (a
      // TimeoutError, which is a failure like any other and gets Retry).
      const signal = AbortSignal.any([ aborter.signal, AbortSignal.timeout(LOAD_TIMEOUT_MS) ])
      const response = await fetch(element.dataset.url, { headers: { Accept: "application/json" }, signal })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json()
      if (!destroyed) show(data)
    } catch (error) {
      if (destroyed || error.name === "AbortError") return
      setState("failed")
      const retry = document.createElement("button")
      retry.type = "button"
      retry.className = "pointer-events-auto cursor-pointer font-semibold text-ink underline"
      retry.textContent = text.t("mind_graph.script.retry")
      retry.addEventListener("click", load, { once: true })
      say(text.t("mind_graph.script.load_failed"), retry)
    }
  }

  // This task draws and moves the camera; what a press, a click, a hover and
  // Escape mean (selecting, dragging a node, the card) comes with the next.
  const stopInput = attachInput(canvas, {
    onPress: () => null,
    onDrag: () => {},
    onDrop: () => {},
    onClick: () => {},
    onHover: () => {},
    onEscape: () => {},
    onPan: (dx, dy) => { state.camera = panBy(state.camera, dx, dy); state.fitted = true; requestDraw() },
    onZoom: (x, y, factor) => { state.camera = zoomAt(state.camera, x, y, factor); state.fitted = true; requestDraw() }
  })
  const stopTheme = watchTheme(() => { state.theme = readTheme(canvas); requestDraw() })
  const observer = new ResizeObserver(resize)
  observer.observe(canvas)
  resize()
  load()

  const zoomBy = (factor) => { state.camera = zoomAt(state.camera, state.width / 2, state.height / 2, factor); state.fitted = true; requestDraw() }

  element.mindGraph = {
    screenPosition(id) {
      const index = state.nodes.findIndex((node) => node.id === id)
      if (index < 0 || !state.visibleNodes.includes(index)) return null
      const box = canvas.getBoundingClientRect()
      return { x: box.left + state.positions[index * 2] * state.camera.k + state.camera.tx, y: box.top + state.positions[index * 2 + 1] * state.camera.k + state.camera.ty }
    },
    draws: () => draws
  }

  return {
    state, requestDraw, select, toGraph, hit,
    layout: () => layout,
    zoomIn: () => zoomBy(BUTTON_ZOOM),
    zoomOut: () => zoomBy(1 / BUTTON_ZOOM),
    fit: fitAll,
    // The control changed: hand the layout only what is shown now. The camera
    // stays where it is.
    filter() {
      if (!layout) return
      applyFilter()
      element.removeAttribute("data-settled")
      sendFilter()
      requestDraw()
    },
    destroy() {
      destroyed = true
      aborter.abort()
      layout?.stop()
      layout = null
      if (frame != null) cancelAnimationFrame(frame)
      frame = null
      observer.disconnect()
      stopInput()
      stopTheme()
      delete element.mindGraph
    }
  }
}
