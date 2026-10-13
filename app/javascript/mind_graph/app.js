// The mind graph, wired together (mind graph canvas spec §4): fetch the data,
// hand the layout to the worker, and redraw the canvas when something changed.
// `mount(element)` is everything `admin--mind-graph--graph` asks for; `destroy()`
// stops all of it -- the request, the worker, the frame, the observers -- so
// nothing runs or draws after the screen is left.
//
// What the screen shows is said on the element, for tests and for anything
// that wants to know without reading a canvas: `data-state` (loading, ready,
// failed, worker-failed), `data-settled`, `data-nodes`, `data-edges`,
// `data-zoom`, `data-labelled`, `data-selected` (the selected node's id, or
// empty), `data-neighbours` (the ids of the selection's direct neighbours
// by the edges shown, comma-separated, or empty; written when the selection
// or the filter changes, never per frame), `data-hovered` (the hovered node's
// id, or empty) and `data-pinned` (how many nodes are pinned).
// `element.mindGraph.screenPosition(id)` answers where a visible node is, in
// client coordinates (null for one the filter hides, and for every node until
// the layout has placed them), `.labelBox(id)` the box of its label as the
// last frame drew it (null when it drew none), `.markBox(id)` the box of a
// mark that is one (a page's card, the pill; null for any other),
// `.graphPosition(id)` where the
// layout has a node in GRAPH units, the camera not applied (null until the
// layout has placed them), and `.draws()` how many frames have been drawn.
//
// WHAT IS DRAWN (pages in the mind graph, spec §4). Five kinds of node
// (`graph_data.js` makes them from the payload; `marks.js` draws each): a
// page, a post, a tag, a post type a page lists (with the one "All posts")
// and, in a page's local view, a "+N more" pill per target. Five kinds of
// line (`renderer.js`). Labels go to Home first, then the top-level pages
// and the post types, which are named at any zoom, then the rest by their
// links. ONE NODE RESTS AT THE CENTRE of the layout (`graph_data.js`,
// `anchorOf`): Home in the whole graph, the focus in a local view, where
// Home is a page like any other. The worker holds it there
// (`layout_worker.js`, the anchor). That is not a pin: `state.pinned` does
// not hold it, nothing shows it as pinned, and nothing here can release it.
// Dragged, it is pinned where it is dropped like any node, and released it
// eases back to the centre.
//
// A LABEL'S WIDTH is measured in the font the label is drawn in
// (`renderer.js`, `labelFont`): a tag's in mono, and the selected node's in
// semibold, so `state.widths` holds the selected node's semibold width while
// it is selected. The label rule, the hit test and the hover's backing all
// read that one array.
//
// MOTION (spec §4.2). How fast the layout is shown is the worker's business
// (`layout_worker.js`, PACING): this page draws every `tick` it is sent. All
// it adds is the one fact the worker can't find out -- whether the person
// asked for reduced motion -- handed over with `start`.
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
// SELECTING (spec §5.3). A click on a node -- its mark or its drawn label,
// which are one target (`hit_test.js`) -- selects it: it and its direct
// neighbours stay at full strength and are always labelled, the rest dims,
// and the card (`card.js`) opens BESIDE the node (`card_placement.js`) and
// stays beside it through a pan, a zoom and the layout's own movement: its
// place is worked out in the frame that draws the node. A click on empty
// space, Escape and the card's Close clear the selection. A click never
// navigates by itself; the card's links do. A row of the list (`node_list.js`)
// selects the same way, brings the node to the middle of the canvas and
// moves the focus to the card, so the keyboard reaches the actions; closing
// that card gives the focus back to the row.
//
// HOVERING a node -- with the pointer, or its row in the list -- rings it and
// shows its label on a backing, even where the label rule hides it; nothing
// else dims. The tooltip is only for a title the label cuts short.
//
// DRAGGING AND PINNING (spec §4.4, §5.3). A press that moves is a drag, not a
// click: it moves the node, the neighbours follow (the worker ticks once per
// frame while a node is held), and the selection is left as it was. A DROPPED
// NODE STAYS WHERE IT WAS DROPPED: it is pinned. So is one pinned from its
// card. A pinned node carries a mark (`renderer.js`), the card's button reads
// Unpin, "Release N pinned" beside the zoom buttons lets all of them go, and
// a double click on a pinned node lets that one go. Pins live in this page
// only -- `state.pinned`, nothing stored -- so a reload or leaving the screen
// forgets them, and a filter change forgets those of the nodes it hides (the
// worker lets go of them too). The node is held where it was grabbed, not by
// its centre: a drag by the label must not make the mark jump to the pointer.
// While its own node is dragged the card is out of the way, and comes back
// with the drop.
import { messages } from "i18n/messages"
import { createLayout } from "mind_graph/layout_client"
import { identity, toGraph, zoomAt, panBy, bounds, fit } from "mind_graph/camera"
import { nodeAt } from "mind_graph/hit_test"
import { chooseLabels, labelAt, LABEL_GAP, LABEL_HEIGHT } from "mind_graph/labels"
import { placeCard } from "mind_graph/card_placement"
import { readTheme, watchTheme } from "mind_graph/theme"
import { draw, radiusFor, labelFont } from "mind_graph/renderer"
import { collisionRadius, boxOf, moreWidth } from "mind_graph/marks"
import { nodesOf, orderOf, freeOf, anchorOf } from "mind_graph/graph_data"
import { attachInput } from "mind_graph/input"
import { createCard } from "mind_graph/card"
import { attachSearch } from "mind_graph/search_box"
import { createList } from "mind_graph/node_list"

// A label longer than this is cut with an ellipsis; a tag's count is appended
// whole. Counted by code point, so an emoji is never cut in half.
const MAX_LABEL_CHARACTERS = 32
const BUTTON_ZOOM = 1.4
// How long the data request may go unanswered before it is given up and shown
// as a failure, with Retry (spec §6).
const LOAD_TIMEOUT_MS = 15_000
// The tooltip's distance from the pointer, and from the box's edge when it
// would otherwise leave the box.
const TOOLTIP_OFFSET = 14
const TOOLTIP_MARGIN = 4

// Exported for the test that asks it directly: a drawn label is not an
// element to read.
export function labelFor(node) {
  const suffix = node.kind === "tag" ? ` (${node.count})` : ""
  const room = MAX_LABEL_CHARACTERS - Array.from(suffix).length
  const characters = Array.from(String(node.title))
  return (characters.length > room ? `${characters.slice(0, room - 1).join("")}…` : characters.join("")) + suffix
}

export function mount(element) {
  const canvas = element.querySelector("canvas")
  const notice = element.querySelector("[data-admin--mind-graph--graph-target='notice']")
  const context = canvas.getContext("2d")
  const text = messages(element)
  const aborter = new AbortController()
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)")
  // Everything the graph is and how it is looked at: the data as it arrived
  // (`data`), the nodes and edges made from it, what the filter shows, the
  // layout's positions, the camera, the selection, the theme and the canvas's
  // size. `renderer.js` draws from it and nothing else. `edges[i].source` /
  // `.target`, `visibleNodes`, `visibleEdges`, `selected`, `neighbours` and
  // `focusIndex`, `hovered` and the members of `pinned` are all INDEXES into
  // `nodes` (or `edges`); `positions` is the worker's x/y pairs, in the order
  // of `nodes`. `order` is the visible nodes that have a label, in the order
  // labels go to them, and `free` those of them that are named at any zoom
  // (`graph_data.js`). `boxes` is each node's box, for one that is a box
  // (a page's card, the pill), else null. `labels` is what the last frame
  // drew, which is what the hit test may answer for.
  const state = {
    nodes: [], edges: [], positions: new Float32Array(0), radii: [], boxes: [], widths: [], order: [], free: new Set(),
    visibleNodes: [], visibleEdges: [], camera: identity(), selected: -1, neighbours: new Set(), focusIndex: -1,
    hovered: -1, pinned: new Set(), labels: [],
    theme: readTheme(canvas), width: 0, height: 0, ratio: 1, fitted: false, placed: false, data: null
  }
  let destroyed = false
  let layout = null
  let frame = null
  let draws = 0
  let labelled = null
  let zoom = null
  let indexOf = new Map()
  // Each label's width in its regular font and in the selected node's
  // (semibold): `state.widths` is the first, with the selected node's entry
  // from the second.
  let plainWidths = []
  let strongWidths = []
  // The node a press is on (an index, -1 for none), where on it the press
  // took hold (in graph units from its centre) and whether it has become a
  // drag: a press becomes one only once it has moved, and a plain click must
  // send the worker nothing -- a `drag` reheats the layout, and the graph
  // would twitch under a click.
  let pressed = -1
  let grab = { dx: 0, dy: 0 }
  let dragging = false
  // What is hovered, by each of its two sources (indexes, -1 for none); the
  // pointer's wins. `pointerAt` is where the pointer last was over the canvas,
  // so the hover can be worked out again when the view moves under it.
  let pointerHover = -1
  let rowHover = -1
  let pointerAt = null
  // The card as measured when it was last filled, where it was last put (so
  // its style is written only when it moves), and the id of the row that
  // opened it, when one did: closing it gives the focus back there.
  let cardSize = { width: 0, height: 0 }
  let cardPlace = null
  let openedFromRow = null

  const tooltip = element.querySelector("[data-mind-graph-tooltip]")
  const release = element.querySelector("[data-mind-graph-release]")
  const zoomReadout = element.querySelector("[data-mind-graph-zoom]")
  const cardElement = element.querySelector("[data-mind-graph-card]")
  const dotClasses = JSON.parse(element.dataset.dotClasses)
  const card = createCard(cardElement, {
    text,
    urls: { postFocus: element.dataset.postFocusUrl, tagFocus: element.dataset.tagFocusUrl, tagPosts: element.dataset.tagPostsUrl, postNotes: element.dataset.postNotesUrl },
    typeLabels: JSON.parse(element.dataset.typeLabels),
    dotClasses,
    buttonClasses: JSON.parse(element.dataset.buttonClasses),
    // The button goes with the card it is in; the focus goes back to where the
    // card was opened from.
    onClose: closeCard,
    onPin: () => {
      if (state.selected < 0) return
      if (state.pinned.has(state.selected)) unpin([ state.selected ])
      else pin(state.selected)
    },
    // The card's notes arrive after the card was measured, and a note started
    // there changes the node's badge: the card is measured and placed again,
    // and the canvas redrawn.
    onChange: () => {
      measureCard()
      requestDraw()
    }
  })
  // Escape closes the card from inside it too, not only from the canvas
  // (`input.js` hears the canvas's keys alone).
  // Enter opens the selected post while the focus is on the card ITSELF,
  // where the list hands it: on a control inside the card Enter is that
  // control's own (a link, a button, a line break in the note's field).
  const cardKeydown = (event) => {
    if (event.ctrlKey || event.metaKey || event.altKey) return
    if (event.key === "Enter" && event.target === cardElement) {
      event.preventDefault()
      card.open()
    } else if (event.key === "Escape") {
      event.preventDefault()
      closeCard()
    }
  }
  cardElement.addEventListener("keydown", cardKeydown)

  // The search field is HTML beside the canvas, not part of the data request:
  // it works whatever the graph is doing, a failed load included (spec §6).
  const search = element.querySelector("[data-mind-graph-search]")
  // The list beside the canvas (spec §5.7): rewritten by `applyFilter`, which
  // runs once per load and once per filter change, never per frame.
  const list = createList(element.querySelector("[data-mind-graph-list]"), {
    text, dotClasses,
    onSelect: (id) => {
      const index = indexOf.get(id)
      if (index == null) return
      select(index)
      openedFromRow = id
      centre(index)
      cardElement.focus()
    },
    onHover: (id) => {
      rowHover = id == null ? -1 : indexOf.get(id) ?? -1
      syncHover()
    }
  })
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

  // The zoom beside its buttons, as the messages' language writes a percentage.
  function percent(value) {
    try {
      return new Intl.NumberFormat(text.locale(), { style: "percent", maximumFractionDigits: 0 }).format(value)
    } catch {
      return `${Math.round(value * 100)}%`
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
        camera: state.camera, width: state.width, height: state.height, always, free: state.free }) : []
      // With reduced motion a label switches on, it does not fade in (§5.2).
      if (reducedMotion.matches) labels.forEach((label) => { label.alpha = 1 })
      // The hovered node's label is drawn whatever the rule said of it: marked
      // where the rule placed it, added on top where it did not (a node
      // outside the canvas has none either way).
      // A node with no label (the pill: its words are inside it) has none
      // when hovered either.
      if (state.placed && state.hovered >= 0 && state.nodes[state.hovered].label && state.visibleNodes.includes(state.hovered)) {
        const ruled = labels.find((label) => label.index === state.hovered)
        const own = ruled || labelAt({ index: state.hovered, positions: state.positions, radii: state.radii, camera: state.camera })
        own.hover = true
        const mark = screenOf(state.hovered)
        if (!ruled && mark.x >= 0 && mark.y >= 0 && mark.x <= state.width && mark.y <= state.height) labels.push(own)
      }
      state.labels = labels
      draw(context, state.placed ? { ...state, labels } : { ...state, labels, visibleNodes: [], visibleEdges: [] })
      draws += 1
      // In the frame that draws the node, so the card never lags behind it.
      positionCard()

      // Written only when changed: a pan redraws every frame and changes neither.
      const k = state.camera.k.toFixed(3)
      if (k !== zoom) {
        element.dataset.zoom = zoom = k
        zoomReadout.textContent = percent(state.camera.k)
      }
      const ids = labels.map((label) => state.nodes[label.index].id).join(",")
      if (ids !== labelled) element.dataset.labelled = labelled = ids
    })
  }

  // A node's centre on the canvas, in CSS pixels.
  const screenOf = (index) => ({ x: state.positions[index * 2] * state.camera.k + state.camera.tx, y: state.positions[index * 2 + 1] * state.camera.k + state.camera.ty })

  // The card beside the selected node (`card_placement.js`). A node the layout
  // never placed (the worker failed, and the selection came from the list) has
  // no place to stand beside: the card takes the canvas's corner.
  function positionCard() {
    if (state.selected < 0 || cardElement.hidden) return
    const at = state.placed ? screenOf(state.selected) : { x: NaN, y: NaN }
    const { left, top, side } = placeCard({ ...at, radius: state.radii[state.selected], cardWidth: cardSize.width, cardHeight: cardSize.height, width: state.width, height: state.height })
    const place = `${Math.round(left)},${Math.round(top)},${side}`
    if (place === cardPlace) return

    cardPlace = place
    cardElement.style.left = `${Math.round(left)}px`
    cardElement.style.top = `${Math.round(top)}px`
    cardElement.dataset.side = side
  }

  // After the card was filled or its content changed: its size is read once,
  // here, never in a frame.
  function measureCard() {
    cardSize = { width: cardElement.offsetWidth, height: cardElement.offsetHeight }
    cardPlace = null
    positionCard()
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
    cardPlace = null
    requestDraw()
  }

  function fitAll() {
    if (state.width === 0) return
    state.camera = fit(bounds(state.positions, state.visibleNodes), state.width, state.height)
    state.fitted = true
    rehover()
    requestDraw()
  }

  // The camera with this node in the middle of the canvas, at the zoom it has.
  function centre(index) {
    if (!state.placed || state.width === 0) return
    const { k } = state.camera
    moveCamera({ k, tx: state.width / 2 - state.positions[index * 2] * k, ty: state.height / 2 - state.positions[index * 2 + 1] * k })
  }

  // No node is under any point until the layout has placed them: unplaced,
  // every one is at 0, 0 -- the canvas's corner, where nothing is drawn -- and
  // when the worker failed that is for good.
  function hit(x, y) {
    if (!state.placed) return -1
    return nodeAt({ positions: state.positions, indexes: state.visibleNodes, radii: state.radii, boxes: state.boxes, camera: state.camera, sx: x, sy: y, labels: state.labels, widths: state.widths })
  }

  // What the filter shows: every edge of the chosen kind, and under "All"
  // every node, otherwise only the nodes such an edge touches.
  function applyFilter() {
    const chosen = mode()
    state.visibleEdges = state.edges.flatMap((edge, index) => (chosen === "all" || edge.kind === chosen ? [ index ] : []))
    const touched = new Set(state.visibleEdges.flatMap((index) => [ state.edges[index].source, state.edges[index].target ]))
    state.visibleNodes = state.nodes.flatMap((_, index) => (chosen === "all" || touched.has(index) ? [ index ] : []))
    state.order = orderOf(state.nodes, state.visibleNodes)
    state.free = freeOf(state.nodes, state.visibleNodes)
    // The selection goes with a node the filter hides; one that stays keeps
    // its place, but its neighbours are the ones the shown edges give it now,
    // so nothing stays lit (or dimmed) by an edge that is no longer drawn.
    if (state.selected >= 0) select(state.visibleNodes.includes(state.selected) ? state.selected : -1)
    // A pin is for a node on screen: one the filter hides is let go (the
    // worker does the same with its `filter`), the others stay.
    const shown = new Set(state.visibleNodes)
    state.pinned.forEach((index) => { if (!shown.has(index)) state.pinned.delete(index) })
    // Nor is a node the filter hides hovered any longer, by either source.
    if (rowHover >= 0 && !shown.has(rowHover)) rowHover = -1
    if (pointerHover >= 0 && !shown.has(pointerHover)) pointerHover = -1
    element.dataset.nodes = state.visibleNodes.length
    element.dataset.edges = state.visibleEdges.length
    list.render(state.visibleNodes.map((index) => state.nodes[index]))
    list.mark(state.selected >= 0 ? state.nodes[state.selected].id : null)
    pinsChanged()
    syncHover()
  }

  function select(index) {
    openedFromRow = null
    // The node the card already shows: a second click on it, or a filter
    // change that keeps it, must not build the card again -- that would
    // throw away a note half typed in it and fetch its notes once more.
    const shown = index >= 0 && index === state.selected && cardElement.childElementCount > 0
    // The selected label is semibold, and as wide as that.
    if (state.selected >= 0) state.widths[state.selected] = plainWidths[state.selected]
    if (index >= 0) state.widths[index] = strongWidths[index]
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
    if (index >= 0) {
      // Without a layout there is nothing to pin (the worker failed).
      if (!shown) card.show(state.nodes[index], { pinned: state.pinned.has(index), pinnable: Boolean(layout) })
      measureCard()
    } else {
      card.hide()
    }
    list.mark(index >= 0 ? state.nodes[index].id : null)
    requestDraw()
  }

  // The card's Close and Escape inside it: what had the focus goes with the
  // card, so the focus goes back to where the card was opened from -- the row
  // of the list, or the canvas.
  function closeCard() {
    const row = openedFromRow == null ? null : list.row(openedFromRow)
    select(-1)
    if (row) row.focus()
    else canvas.focus()
  }

  // What the pins are, said on the element and beside the zoom buttons:
  // "Release N pinned" is there only while something is pinned.
  function pinsChanged() {
    const count = state.pinned.size
    element.dataset.pinned = count
    release.hidden = count === 0
    release.textContent = count === 0 ? "" : text.t("mind_graph.script.release_pinned", { count })
    if (state.selected >= 0) {
      card.setPinned(state.pinned.has(state.selected))
      measureCard()
    }
    requestDraw()
  }

  // Holds a node where the layout has put it. Nothing moves, but the worker
  // is asked, so the screen is "settled" again only when it has answered.
  function pin(index) {
    if (!layout || state.pinned.has(index)) return
    state.pinned.add(index)
    element.removeAttribute("data-settled")
    layout.pin(state.nodes[index].id)
    pinsChanged()
  }

  // Gives nodes back to the forces: the layout warms up and eases to rest
  // with them free.
  function unpin(indexes) {
    const freed = indexes.filter((index) => state.pinned.has(index))
    if (!layout || freed.length === 0) return
    freed.forEach((index) => state.pinned.delete(index))
    element.removeAttribute("data-settled")
    layout.unpin(freed.map((index) => state.nodes[index].id))
    pinsChanged()
  }

  function hideTooltip() {
    tooltip.hidden = true
  }

  // The hovered node is the pointer's, or else the list's.
  function syncHover() {
    const next = pointerHover >= 0 ? pointerHover : rowHover
    if (next === state.hovered) return
    state.hovered = next
    element.dataset.hovered = next >= 0 ? state.nodes[next].id : ""
    requestDraw()
  }

  // The view moved under a pointer that did not: what it is over is asked
  // again, so a zoom towards a node keeps it lit and a pan leaves no node lit
  // that is no longer under the pointer.
  function rehover() {
    if (pointerAt) hover(...pointerAt)
    else hideTooltip()
  }

  // The whole title of the node under the pointer, beside the pointer and
  // inside the box (which clips what leaves it). `textContent`: a title is
  // text, and it is written only when the pointer comes onto another node.
  function hover(x, y) {
    pointerAt = x >= 0 ? [ x, y ] : null
    const index = pressed < 0 && x >= 0 ? hit(x, y) : -1
    canvas.style.cursor = index >= 0 ? "pointer" : ""
    const changed = index !== pointerHover
    pointerHover = index
    syncHover()
    // The label on its backing names the node; the tooltip is for the rest of
    // a title the label cuts short.
    if (index < 0 || !state.nodes[index].cut) return hideTooltip()

    if (changed || tooltip.hidden) tooltip.textContent = state.nodes[index].title
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
    // A pill's figure is grouped as the messages' language groups it
    // ("+1,980 more", design answer H4); `count` in that message is the
    // figure as text, not a plural's number: the words have one form.
    state.nodes = nodesOf(data, {
      allPosts: text.t("mind_graph.script.all_posts"),
      more: (count) => text.t("mind_graph.script.more", { count: number(count) }),
      retired: (name) => text.t("mind_graph.script.retired_type", { name })
    })
    indexOf = new Map(state.nodes.map((node, index) => [ node.id, index ]))
    // Every end of a line is a node the server sent with it. One whose end
    // is missing all the same is left out, not drawn to the canvas's corner.
    state.edges = data.edges.map((edge) => ({ kind: edge.kind, source: indexOf.get(edge.source), target: indexOf.get(edge.target) }))
      .filter((edge) => edge.source != null && edge.target != null)
    state.positions = new Float32Array(state.nodes.length * 2)
    // A pill grows to fit its words: measured in the font they are drawn in,
    // BEFORE the sizes are read, because a pill's size is its width.
    context.font = state.theme.countFont
    for (const node of state.nodes) if (node.kind === "more") node.width = moreWidth(context.measureText(node.title).width)
    state.radii = state.nodes.map(radiusFor)
    state.boxes = state.nodes.map(boxOf)
    state.nodes.forEach((node) => {
      // The pill has no label: its words are inside it.
      node.label = node.kind === "more" ? "" : labelFor(node)
      // Whether the label leaves some of the title out (a tag's count after
      // its whole name does not, and a node without a label has nothing cut).
      node.cut = node.label !== "" && !node.label.startsWith(String(node.title))
    })
    // Each label is measured in the font it is drawn in: a tag's is mono,
    // the selected node's semibold. Both once, here, never in a frame.
    const measured = (selected) => state.nodes.map((node) => {
      context.font = labelFont(state.theme, node, selected)
      return context.measureText(node.label).width
    })
    plainWidths = measured(false)
    strongWidths = measured(true)
    state.widths = plainWidths.slice()
    // The selection of the data before this is not one of these nodes.
    state.selected = -1
    state.focusIndex = data.focus ? indexOf.get(data.focus.node_id) ?? -1 : -1
    state.fitted = false
    state.placed = false
    state.pinned = new Set()
    state.labels = []
    state.hovered = pointerHover = rowHover = -1
    element.dataset.hovered = ""
    select(-1)
    applyFilter()
    // The canvas is one image to a screen reader, and its name says what is on it.
    canvas.setAttribute("aria-label", text.t("mind_graph.script.summary", { posts: state.nodes.length, edges: state.edges.length }))

    // The two views cut differently (`PostGraph::Global` keeps the best
    // connected, `PostGraph::Local` the nearest to the focus), so each has its
    // own sentence. A figure in a sentence is grouped (`number`); `count`
    // only chooses the plural form.
    const cut = { shown: number(data.shown), total: number(data.total) }
    const capped = data.focus ? text.t("mind_graph.script.capped_local", cut) : text.t("mind_graph.script.capped", cut)
    say(
      state.edges.length === 0 ? text.t("mind_graph.script.no_connections") : null,
      data.shown < data.total ? capped : null,
      // "Other" posts, beside the ones drawn; with nothing drawn there are no
      // others, and the sentence is the plain one.
      data.isolated > 0 ? text.t(state.nodes.length > 0 ? "mind_graph.script.isolated" : "mind_graph.script.isolated_only", { count: data.isolated, figure: number(data.isolated) }) : null
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
          // The first positions: a card opened from the list before there was
          // a layout now has a node to stand beside.
          cardPlace = null
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
    // The worker can't ask about motion itself, so it is told (as the page
    // found it now; a change of the setting applies from the next load).
    // What the layout keeps clear around a node is its mark's reach (a box's
    // is half its diagonal). One node is the anchor, held at the centre:
    // Home in the whole graph, the focus in a local view.
    const anchor = anchorOf(state.data)
    layout.start(state.nodes.map((node) => ({ id: node.id, radius: collisionRadius(node), anchor: node.id === anchor })),
      state.edges.map((edge) => ({ source: state.nodes[edge.source].id, target: state.nodes[edge.target].id, kind: edge.kind })),
      { reducedMotion: reducedMotion.matches })
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
    state.pinned = new Set()
    pinsChanged()
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

  // The hover is asked again: the view has moved under the pointer.
  function moveCamera(camera) {
    state.camera = camera
    state.fitted = true
    rehover()
    requestDraw()
  }

  const stopInput = attachInput(canvas, {
    // A press on a node may become a drag of it, a press on empty space pans.
    // Whether the press was a click is known only at release (`input.js`), so
    // nothing is sent to the layout yet. The answer is the index plus one,
    // because `input.js` asks for something truthy and index 0 is a node.
    onPress: (x, y) => {
      pressed = hit(x, y)
      dragging = false
      if (pressed >= 0) {
        const [ gx, gy ] = toGraph(state.camera, x, y)
        grab = { dx: gx - state.positions[pressed * 2], dy: gy - state.positions[pressed * 2 + 1] }
      }
      // Where the pointer is over is not known again until it moves with no
      // button down; a node that is held stays lit meanwhile.
      pointerAt = null
      if (pressed < 0) pointerHover = -1
      syncHover()
      hideTooltip()
      return pressed >= 0 ? pressed + 1 : null
    },
    // The press has moved: the node is held under the pointer in the worker
    // (`drag`), which keeps the layout warm so the neighbours follow. From
    // its first move the node is pinned, and its own card is out of the way.
    onDrag: (x, y) => {
      if (pressed < 0 || !layout) return
      const [ gx, gy ] = toGraph(state.camera, x, y)
      state.fitted = true
      if (!dragging) {
        dragging = true
        state.pinned.add(pressed)
        pinsChanged()
        if (pressed === state.selected) cardElement.hidden = true
      }
      element.removeAttribute("data-settled")
      layout.drag(state.nodes[pressed].id, gx - grab.dx, gy - grab.dy)
    },
    // Also the end of a press a second finger took over (a pinch). `drop`
    // only answers a `drag`: the node stays where it is, pinned, and `settled`
    // is announced again when the layout has cooled down around it.
    onDrop: () => {
      if (dragging) {
        layout?.drop(state.nodes[pressed].id)
        if (pressed === state.selected) {
          cardElement.hidden = false
          measureCard()
        }
      }
      pressed = -1
      dragging = false
    },
    onClick: (x, y) => select(hit(x, y)),
    // The shortcut for "let this one go". (Both of its clicks have selected
    // the node already.)
    onDoubleClick: (x, y) => {
      const index = hit(x, y)
      if (index >= 0) unpin([ index ])
    },
    onEscape: () => select(-1),
    // Enter with a post selected opens it (the card's own "Open post").
    onEnter: () => card.open(),
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
    labelBox(id) {
      const label = state.labels.find((candidate) => state.nodes[candidate.index].id === id)
      if (!label) return null
      const box = canvas.getBoundingClientRect()
      return { left: box.left + label.x - LABEL_GAP, right: box.left + label.x + state.widths[label.index], top: box.top + label.y - LABEL_HEIGHT / 2, bottom: box.top + label.y + LABEL_HEIGHT / 2 }
    },
    // The box of a visible node whose mark is one (a page's card, the pill),
    // in client coordinates; null for a mark that is a circle or a square.
    markBox(id) {
      const index = indexOf.get(id)
      const at = this.screenPosition(id)
      const size = index == null ? null : state.boxes[index]
      return at && size ? { left: at.x - size.width / 2, right: at.x + size.width / 2, top: at.y - size.height / 2, bottom: at.y + size.height / 2 } : null
    },
    // Where the layout has a node, in GRAPH units (the camera not applied):
    // the anchor's is 0, 0 while nobody holds it.
    graphPosition(id) {
      const index = indexOf.get(id)
      return index == null || !state.placed ? null : { x: state.positions[index * 2], y: state.positions[index * 2 + 1] }
    },
    draws: () => draws
  }

  return {
    zoomIn: () => zoomBy(BUTTON_ZOOM),
    zoomOut: () => zoomBy(1 / BUTTON_ZOOM),
    fit: fitAll,
    releasePinned: () => unpin(Array.from(state.pinned)),
    // The control changed: hand the layout only what is shown now. The camera
    // stays where it is. The list and the counts follow the control whenever
    // there is data, a layout or not: when the worker could not start, the
    // list is all there is, and it must show what the control says.
    filter() {
      if (!state.data) return
      applyFilter()
      rehover()
      if (!layout) return
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
      list.destroy()
      card.hide()
      hideTooltip()
      release.hidden = true
      release.textContent = ""
      canvas.style.cursor = ""
      delete element.mindGraph
    }
  }
}
