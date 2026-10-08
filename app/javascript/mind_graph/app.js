// The mind graph, wired together (mind graph canvas spec §4): fetch the data,
// hand the layout to the worker, and redraw the canvas when something changed.
// `mount(element)` is everything `admin--mind-graph` asks for; `destroy()`
// stops all of it -- the request, the worker, the frame, the observers -- so
// nothing runs or draws after the screen is left.
//
// What the screen shows is said on the element, for tests and for anything
// that wants to know without reading a canvas: `data-state` (loading, ready,
// failed, worker-failed), `data-settled`, `data-nodes`, `data-edges`,
// `data-zoom`, `data-labelled`, `data-selected` (the selected node's id, or
// empty) and `data-neighbours` (the ids of the selection's direct neighbours
// by the edges shown, comma-separated, or empty; written when the selection
// or the filter changes, never per frame). `element.mindGraph.
// screenPosition(id)` answers where a visible node is, in client coordinates
// (null for one the filter hides, and for every node until the layout has
// placed them), and `.draws()` how many frames have been drawn.
//
// THE CAMERA. The first view fits everything: while the layout takes shape the
// camera follows it, and when it has cooled down the fit is final
// (`state.fitted`). From then on -- or from the user's first zoom or pan, if
// that comes sooner -- the camera moves only on the user's input or "Fit all":
// a filter, a resize and a later reheat of the layout leave it where it is.
// Dragging a node is such an input too: the camera stops following the layout
// the moment a node is held, or the node would slide from under the pointer.
// Nodes are not clamped to the box; the box is a window onto the graph.
//
// SELECTING (spec §5.3). A click on a node selects it: it and its direct
// neighbours stay at full strength and are always labelled, the rest dims,
// and the card (`card.js`) opens with what can be done with it. A click on
// empty space, Escape and the card's Close clear the selection. A click never
// navigates by itself; the card's links do. A press that moves is a drag, not
// a click: it moves the node (`pin` / `unpin` in the worker) and leaves the
// selection as it was. Hovering a node shows its whole title in the tooltip.
import { messages } from "i18n/messages"
import { createLayout } from "mind_graph/layout_client"
import { identity, toGraph, zoomAt, panBy, bounds, fit } from "mind_graph/camera"
import { nodeAt } from "mind_graph/hit_test"
import { chooseLabels } from "mind_graph/labels"
import { readTheme, watchTheme } from "mind_graph/theme"
import { draw, radiusFor } from "mind_graph/renderer"
import { attachInput } from "mind_graph/input"
import { createCard } from "mind_graph/card"
import { attachSearch } from "mind_graph/search_box"
import { renderList } from "mind_graph/node_list"

// A label longer than this is cut with an ellipsis; a tag's count is appended
// whole. Counted by code point, so an emoji is never cut in half. Exported for
// the test that asks it directly: a drawn label is not an element to read.
const MAX_LABEL_CHARACTERS = 32
const BUTTON_ZOOM = 1.4
// How long the data request may go unanswered before it is given up and shown
// as a failure, with Retry (spec §6).
const LOAD_TIMEOUT_MS = 15_000
// The tooltip's distance from the pointer, and from the box's edge when it
// would otherwise leave the box.
const TOOLTIP_OFFSET = 14
const TOOLTIP_MARGIN = 4

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
    theme: readTheme(canvas), width: 0, height: 0, ratio: 1, fitted: false, placed: false, data: null
  }
  let destroyed = false
  let layout = null
  let frame = null
  let draws = 0
  let labelled = null
  let zoom = null
  // The node a press is on (an index, -1 for none) and whether the layout was
  // told to hold it: a press becomes a drag only once it has moved, and a
  // plain click must send the worker nothing -- an `unpin` reheats the layout
  // as a `pin` does, and the graph would twitch under a click.
  let pressed = -1
  let pinned = false
  // The node the tooltip names (an index, -1 while it is hidden).
  let hovered = -1

  const tooltip = element.querySelector("[data-mind-graph-tooltip]")
  const cardElement = element.querySelector("[data-mind-graph-card]")
  const card = createCard(cardElement, {
    text,
    urls: { postFocus: element.dataset.postFocusUrl, tagFocus: element.dataset.tagFocusUrl, tagPosts: element.dataset.tagPostsUrl },
    typeLabels: JSON.parse(element.dataset.typeLabels),
    // The button goes with the card it is in; the focus goes back to the canvas.
    onClose: closeCard
  })
  // Escape closes the card from inside it too, not only from the canvas
  // (`input.js` hears the canvas's keys alone).
  const cardKeydown = (event) => {
    if (event.key !== "Escape" || event.ctrlKey || event.metaKey || event.altKey) return
    event.preventDefault()
    closeCard()
  }
  cardElement.addEventListener("keydown", cardKeydown)

  // The search field is HTML beside the canvas, not part of the data request:
  // it works whatever the graph is doing, a failed load included (spec §6).
  const search = element.querySelector("[data-mind-graph-search]")
  // The list of links (spec §5.7): rewritten by `applyFilter`, which runs once
  // per load and once per filter change, never per frame.
  const listBody = element.querySelector("[data-mind-graph-list-body]")
  const stopSearch = attachSearch(search.querySelector("input"), search.querySelector("[data-mind-graph-results]"), { url: search.dataset.url, text, status: search.querySelector("[data-mind-graph-status]") })

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

      // In this order: where two of these labels would overlap, the one put
      // in first keeps the place (`labels.js`, rule 3).
      const always = new Set()
      if (state.selected >= 0) always.add(state.selected)
      if (state.focusIndex >= 0) always.add(state.focusIndex)
      state.neighbours.forEach((index) => always.add(index))
      // Until the worker's first positions arrive every node is at 0, 0 -- the
      // canvas's top-left corner -- so a frame drawn before then (the data has
      // just come, or the worker never started) is an empty one, not a pile.
      const labels = state.placed ? chooseLabels({ order: state.order, positions: state.positions, widths: state.widths, radii: state.radii,
        camera: state.camera, width: state.width, height: state.height, always }) : []
      // With reduced motion a label switches on, it does not fade in (§5.2).
      if (reducedMotion.matches) labels.forEach((label) => { label.alpha = 1 })
      draw(context, state.placed ? { ...state, labels } : { ...state, labels, visibleNodes: [], visibleEdges: [] })
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
    hideTooltip()
    requestDraw()
  }

  // No node is under any point until the layout has placed them: unplaced,
  // every one is at 0, 0 -- the canvas's corner, where nothing is drawn -- and
  // when the worker failed that is for good.
  function hit(x, y) {
    if (!state.placed) return -1
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
    renderList(listBody, {
      nodes: state.visibleNodes.map((index) => state.nodes[index]), text,
      urls: { postFocus: element.dataset.postFocusUrl, tagFocus: element.dataset.tagFocusUrl }
    })
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
    element.dataset.neighbours = Array.from(state.neighbours, (neighbour) => state.nodes[neighbour].id).join(",")
    if (index >= 0) card.show(state.nodes[index])
    else card.hide()
    requestDraw()
  }

  // The card's Close and Escape inside it: what had the focus goes with the
  // card, so the focus goes back to the canvas.
  function closeCard() {
    select(-1)
    canvas.focus()
  }

  function hideTooltip() {
    tooltip.hidden = true
    hovered = -1
  }

  // The whole title of the node under the pointer, beside the pointer and
  // inside the box (which clips what leaves it). `textContent`: a title is
  // text, and it is written only when the pointer comes onto another node.
  function hover(x, y) {
    const index = pressed < 0 && x >= 0 ? hit(x, y) : -1
    canvas.style.cursor = index >= 0 ? "pointer" : ""
    if (index < 0) return hideTooltip()

    if (index !== hovered) tooltip.textContent = state.nodes[index].title
    hovered = index
    tooltip.hidden = false
    // Measured from the left edge: an absolute box near the right edge is
    // only as wide as the room left there, and the clamp needs the width the
    // title has when it is not squeezed.
    tooltip.style.left = "0px"
    const left = Math.min(x + TOOLTIP_OFFSET, state.width - tooltip.offsetWidth - TOOLTIP_MARGIN)
    const below = y + TOOLTIP_OFFSET
    const top = below + tooltip.offsetHeight + TOOLTIP_MARGIN > state.height ? y - TOOLTIP_OFFSET - tooltip.offsetHeight : below
    tooltip.style.left = `${Math.max(TOOLTIP_MARGIN, left)}px`
    tooltip.style.top = `${Math.max(TOOLTIP_MARGIN, top)}px`
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
    state.fitted = false
    state.placed = false
    select(-1)
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
          state.placed = true
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

  // The tooltip is where the pointer was when it was shown: once the view
  // moves under it, it names the wrong place.
  const moveCamera = (camera) => {
    state.camera = camera
    state.fitted = true
    hideTooltip()
    requestDraw()
  }

  const stopInput = attachInput(canvas, {
    // A press on a node may become a drag of it, a press on empty space pans.
    // Whether the press was a click is known only at release (`input.js`), so
    // nothing is sent to the layout yet. The answer is the index plus one,
    // because `input.js` asks for something truthy and index 0 is a node.
    onPress: (x, y) => {
      pressed = hit(x, y)
      pinned = false
      hideTooltip()
      return pressed >= 0 ? pressed + 1 : null
    },
    // The press has moved: the node is held under the pointer in the worker
    // (`pin`), which reheats the layout so the rest resettles around it.
    onDrag: (x, y) => {
      if (pressed < 0 || !layout) return
      const [ gx, gy ] = toGraph(state.camera, x, y)
      state.fitted = true
      pinned = true
      element.removeAttribute("data-settled")
      layout.pin(state.nodes[pressed].id, gx, gy)
    },
    // Also the end of a press a second finger took over (a pinch). `unpin`
    // only answers a `pin`; `settled` is announced again when the layout has
    // cooled down with the node let go.
    onDrop: () => {
      if (pinned) layout?.unpin(state.nodes[pressed].id)
      pressed = -1
      pinned = false
    },
    onClick: (x, y) => select(hit(x, y)),
    onEscape: () => select(-1),
    onHover: hover,
    onPan: (dx, dy) => moveCamera(panBy(state.camera, dx, dy)),
    onZoom: (x, y, factor) => moveCamera(zoomAt(state.camera, x, y, factor))
  })
  const stopTheme = watchTheme(() => { state.theme = readTheme(canvas); requestDraw() })
  const observer = new ResizeObserver(resize)
  observer.observe(canvas)
  resize()
  load()

  const zoomBy = (factor) => moveCamera(zoomAt(state.camera, state.width / 2, state.height / 2, factor))

  element.mindGraph = {
    screenPosition(id) {
      const index = state.nodes.findIndex((node) => node.id === id)
      if (index < 0 || !state.placed || !state.visibleNodes.includes(index)) return null
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
      hideTooltip()
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
      cardElement.removeEventListener("keydown", cardKeydown)
      stopSearch()
      listBody.replaceChildren()
      card.hide()
      hideTooltip()
      canvas.style.cursor = ""
      delete element.mindGraph
    }
  }
}
