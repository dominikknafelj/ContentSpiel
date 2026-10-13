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
// or the filter changes, never per frame), `data-nodes` and `data-edges`
// (how many the legend's toggles show; written by the toggle itself, before
// the layout has moved), `data-hovered` (the hovered node's
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
// THE LEGEND IS THE FILTER (pages spec §6). Its checkboxes say which kinds
// of node and of line are shown, and `graph_data.js`'s `visible` is the one
// place that decides what that means; the state is the checkboxes' own and
// nothing here keeps a copy. A toggle changes what is drawn, the list
// beside the canvas and the canvas's name, and leaves each toggle's COUNT
// as it is: a count is what the response holds, written once per load
// (`writeCounts`). The layout keeps a hidden node's place, so switching a
// kind back on does not shuffle the picture. THE CANVAS'S NAME is the
// summary of what is in view (`summary.js`); after a toggle the same words
// go into the notice's live region, hidden from the eye, which is how the
// change is announced.
//
// THE LIST (`node_list.js`; pages spec §7) shows the four groups of what is
// drawn, or a read's rows in their place: the posts no page lists while "Not
// listed on any page" is on (`data-unlisted-url`), and the posts behind a
// "+N more" after a press on it (`data-listed-url`, the pill's page and
// target), with "Open in Posts →" under them. A pill is NOT SELECTED: a
// press on it opens the list (design answer F4), and Escape on the canvas
// or a click on empty space, with nothing selected, gives the groups back
// (`dismiss`). A row of such a read whose post the
// canvas does not draw is "not in view", and a press ADDS the post
// (`addPost`): the row is the post's node as the data has it, so nothing is
// fetched; it joins the hub that brings it in (`via`) by that hub's line,
// the layout is told (the worker's `add`) and the post is selected. A read that
// fails says so in the list, with "Try again" (G5).
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
import { nodesOf, anchorOf, visible, counts, NODE_TOGGLES, LINE_TOGGLES } from "mind_graph/graph_data"
import { summaryOf } from "mind_graph/summary"
import { attachInput } from "mind_graph/input"
import { createCard, fill } from "mind_graph/card"
import { recordId } from "mind_graph/ids"
import { paintMarks } from "mind_graph/swatches"
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
// How far from its hub (or, with none, from the centre) a post added from
// the list starts, in graph units each way: the layout takes it from there.
const ADDED_OFFSET = 30

// Exported for the test that asks it directly: a drawn label is not an
// element to read.
export function labelFor(node) {
  const suffix = node.kind === "tag" ? ` (${node.count})` : ""
  const room = MAX_LABEL_CHARACTERS - Array.from(suffix).length
  const characters = Array.from(String(node.title))
  return (characters.length > room ? `${characters.slice(0, room - 1).join("")}…` : characters.join("")) + suffix
}

export function mount(element) {
  // The graph's own canvas, by its target: the legend's swatches are
  // canvases too, and come before it in the document.
  const canvas = element.querySelector("[data-admin--mind-graph--graph-target='canvas']")
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
  const typeLabels = JSON.parse(element.dataset.typeLabels)
  const buttonClasses = JSON.parse(element.dataset.buttonClasses)
  const card = createCard(cardElement, {
    text,
    urls: { postFocus: element.dataset.postFocusUrl, tagFocus: element.dataset.tagFocusUrl, tagPosts: element.dataset.tagPostsUrl, postNotes: element.dataset.postNotesUrl },
    typeLabels,
    dotClasses,
    buttonClasses,
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
  // The list beside the canvas (spec §5.7): rewritten by `drawList`, which
  // runs once per load, once per filter change and once per answer of one
  // of the list's reads, never per frame. "Not listed on any page" is there
  // only for a viewer the server gave its address (one who reads a page).
  const list = createList(element.querySelector("[data-mind-graph-list]"), {
    text, dotClasses, typeLabels, retryClass: buttonClasses.secondary, unlisted: Boolean(element.dataset.unlistedUrl),
    onSelect: (id) => {
      const index = indexOf.get(id)
      if (index != null) reveal(index)
    },
    onHover: (id) => {
      rowHover = id == null ? -1 : indexOf.get(id) ?? -1
      syncHover()
    },
    onAdd: addPost,
    onUnlisted: (on) => {
      if (on) showRowsFrom(element.dataset.unlistedUrl)
      else showGroups()
    }
  })
  // The list's rows while a read's are shown in place of the groups: the
  // read's answer (`heading`, `rows`, `link`) and, for a pill's, the pill
  // (`pill`, its node's id). `asked` counts the reads, so that an answer
  // that comes after a later ask, or after the groups were asked back, is
  // not drawn.
  let rowsShown = null
  let asked = 0
  const stopSearch = attachSearch(search.querySelector("input"), search.querySelector("[data-mind-graph-results]"), { url: search.dataset.url, text, status: search.querySelector("[data-mind-graph-status]"), dotClasses })

  // The legend's toggles (pages spec §6): the state is the checkboxes' own,
  // so Back restores what the person had chosen. `switched(name, true)` is
  // the kinds that are on, `switched(name, false)` those that are off, each
  // in the legend's order.
  const toggles = (name) => Array.from(element.querySelectorAll(`[data-mind-graph-legend] input[name="${name}"]`))
  const switched = (name, on) => toggles(name).filter((input) => input.checked === on).map((input) => input.value)
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

  // What the legend shows (`graph_data.js`): a kind of node that is off takes
  // its nodes and their lines; a kind of line that is off takes its lines
  // and nothing else.
  function applyFilter() {
    // A kind is hidden only by a toggle that is switched OFF: one the viewer
    // has no toggle for (the legend gives none for a kind they cannot read,
    // and the data then holds none of it) is never hidden by its absence.
    const on = (all, name) => new Set(all.filter((kind) => !switched(name, false).includes(kind)))
    const shownNow = visible({ nodes: state.nodes, edges: state.edges, on: { nodes: on(NODE_TOGGLES, "mind_graph_nodes"), lines: on(LINE_TOGGLES, "mind_graph_lines") } })
    state.visibleNodes = shownNow.visibleNodes
    state.visibleEdges = shownNow.visibleEdges
    state.order = shownNow.order
    state.free = shownNow.free
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
    drawList()
    pinsChanged()
    syncHover()
    summarise()
  }

  // The list shows the groups of what is drawn, or -- while "Not listed on
  // any page" is on, or after "+N more" -- a read's rows in their place,
  // drawn again whenever what is in view changes (a post was added, a kind
  // switched). A row whose post IS drawn is the drawn node, with the
  // connections it has on the canvas; one that is not is the read's row.
  function drawList() {
    if (rowsShown) {
      const shown = new Set(state.visibleNodes)
      const drawn = (id) => shown.has(indexOf.get(id))
      list.showRows({ heading: rowsShown.heading, link: rowsShown.link, inView: drawn, rows: rowsShown.rows.map((row) => (drawn(row.id) ? state.nodes[indexOf.get(row.id)] : row)) })
    } else {
      list.render(state.visibleNodes.map((index) => state.nodes[index]))
    }
    list.mark(state.selected >= 0 ? state.nodes[state.selected].id : null)
  }

  function showGroups() {
    asked += 1
    rowsShown = null
    list.setUnlisted(false)
    drawList()
  }

  // One of the list's reads (`unlisted`, or a pill's `listed`). A plain
  // `fetch`, ended with everything else when the screen is left. A read
  // that fails says so in the list with "Try again" (design answer G5),
  // which asks for the same read; `again` says the ask came from that
  // button: if the read fails once more, the new button takes the focus the
  // old one had, and when it brings the rows the list itself puts the focus
  // on the first of them (`node_list.js`: the focus was in the rows' region).
  // The heading's figure is the read's whole `total`, which can be more
  // than its rows (the server answers the first `PostGraph::ROW_LIMIT`).
  // "Open in Posts →" stands under a pill's rows (`pill`), where there are
  // any: the server names the address also when it found none.
  async function showRowsFrom(url, { pill = null, again = false } = {}) {
    const mine = (asked += 1)
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, signal: aborter.signal })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const answer = await response.json()
      if (destroyed || mine !== asked) return
      rowsShown = {
        pill,
        heading: text.t("mind_graph.script.list.posts", { count: number(answer.total) }),
        rows: answer.rows,
        link: pill && answer.posts_url && answer.rows.length > 0 ? { href: answer.posts_url, label: text.t("mind_graph.script.list.open_in_posts") } : null
      }
      drawList()
    } catch (error) {
      if (destroyed || error.name === "AbortError" || mine !== asked) return
      rowsShown = null
      list.fail(text.t("mind_graph.script.list.failed"), { label: text.t("mind_graph.script.list.try_again"), focus: again, onRetry: () => showRowsFrom(url, { pill, again: true }) })
    }
  }

  // "+N more" pressed (design answer F4; H1: a pill per target): the list
  // shows the posts THIS pill stands for, read for its page and its target.
  // Pressed again it reads them again. THE WAY BACK to the groups is the
  // one that already clears what a press on the canvas brought (`dismiss`):
  // Escape on the canvas or a click on empty space, once nothing is selected.
  function openMore(pill) {
    list.setUnlisted(false)
    showRowsFrom(fill(fill(element.dataset.listedUrl, "__ID__", recordId(pill.page)), "__TARGET__", pill.target), { pill: pill.id })
  }

  // A post the canvas does not draw, added from its row (pages spec §7): the
  // row IS the post's node, so nothing is fetched. Added once: pressed again,
  // or for a post that is drawn after all, it selects. A row of a page's
  // "+N more" says which hub brings its post in (`via`), and the post gets
  // that hub's line, as the posts the view drew have theirs: a faint line
  // from a post type or "All posts", its own "Shares a tag" line to a tag.
  // A row of "Not listed on any page" has no hub, and its post no line.
  //
  // WHAT THE PAGE DOES NOT KNOW IT DOES NOT SAY: the row was read with no
  // line counted, so the post's related posts and tags are not known here.
  // Its `degree` is the lines it was given, and its two counts are null,
  // which the card leaves out (`card.js`) instead of saying "0 related".
  function addPost(row) {
    const known = indexOf.get(row.id)
    if (known != null) return state.visibleNodes.includes(known) ? reveal(known) : undefined

    const hub = row.via == null ? -1 : indexOf.get(row.via) ?? -1
    const index = state.nodes.length
    const lines = hub < 0 ? [] : state.nodes[hub].kind === "tag" ? [ { kind: "tag", source: index, target: hub } ] : [ { kind: "brings", source: hub, target: index } ]
    const node = { ...row, kind: "post", degree: lines.length, related_count: null, tag_count: null }
    node.label = labelFor(node)
    node.cut = !node.label.startsWith(String(node.title))
    state.nodes.push(node)
    indexOf.set(node.id, index)
    state.radii.push(radiusFor(node))
    state.boxes.push(boxOf(node))
    for (const [ widths, selected ] of [ [ plainWidths, false ], [ strongWidths, true ] ]) {
      context.font = labelFont(state.theme, node, selected)
      widths.push(context.measureText(node.label).width)
    }
    state.widths.push(plainWidths[index])

    // Beside its hub, or beside the centre: where the layout starts it.
    const at = hub >= 0 && state.placed ? [ state.positions[hub * 2] + ADDED_OFFSET, state.positions[hub * 2 + 1] + ADDED_OFFSET ] : [ ADDED_OFFSET, ADDED_OFFSET ]
    const positions = new Float32Array(state.nodes.length * 2)
    positions.set(state.positions)
    positions.set(at, index * 2)
    state.positions = positions
    state.edges.push(...lines)

    applyFilter()
    writeCounts()
    if (layout) {
      element.removeAttribute("data-settled")
      layout.add({ id: node.id, radius: collisionRadius(node), x: at[0], y: at[1] }, lines.map((line) => ({ source: state.nodes[line.source].id, target: state.nodes[line.target].id, kind: line.kind })))
      if (state.visibleNodes.length < state.nodes.length || state.visibleEdges.length < state.edges.length) sendFilter()
    } else if (element.dataset.state === "ready") {
      // Nothing was drawn, so no layout was started: there is something now.
      element.removeAttribute("data-settled")
      startLayout()
    }
    if (state.visibleNodes.includes(index)) reveal(index)
  }

  // Escape on the canvas and a click on empty space take back what the last
  // press on the canvas brought: the selection, and with nothing selected
  // the rows of a "+N more" (the list shows its groups again). The rows of
  // "Not listed on any page" are not a press's: its checkbox lets them go.
  function dismiss() {
    if (state.selected < 0 && rowsShown?.pill) showGroups()
    else select(-1)
  }

  // What a row does to its node: select it, bring it to the middle, and
  // hand the focus to its card.
  function reveal(index) {
    select(index)
    openedFromRow = state.nodes[index].id
    centre(index)
    cardElement.focus()
  }

  // The canvas is one image to a screen reader, and its name says what is on
  // it NOW (`summary.js`; design answers G6 and H5). After a toggle
  // (`announce`) the same words are put into the notice's polite live
  // region, in a line hidden from the eye, beside whatever the notice shows.
  function summarise({ announce = false } = {}) {
    const summary = summaryOf({
      nodes: state.nodes, visibleNodes: state.visibleNodes, lines: state.visibleEdges.length, data: state.data,
      off: { nodes: switched("mind_graph_nodes", false), lines: switched("mind_graph_lines", false) }, toggles: toggles("mind_graph_nodes").length,
      // The view the 3,000-line rule opened (the server says so on the element).
      aroundHome: Boolean(element.dataset.openedLines)
    }, { text, number })
    canvas.setAttribute("aria-label", summary)
    if (!announce) return

    notice.querySelector("[data-mind-graph-announced]")?.remove()
    const line = document.createElement("p")
    line.className = "sr-only"
    line.dataset.mindGraphAnnounced = ""
    line.textContent = summary
    notice.append(line)
  }

  // Each toggle's count beside its name, and its whole name for a screen
  // reader ("Pages, 200"). What the RESPONSE holds, so switching a toggle
  // changes none of them. The controller's `reset` takes both back.
  function writeCounts() {
    const held = counts(state.nodes, state.edges)
    for (const [ name, group ] of [ [ "mind_graph_nodes", held.nodes ], [ "mind_graph_lines", held.lines ] ]) {
      for (const input of toggles(name)) {
        const count = number(group[input.value] ?? 0)
        input.closest("label").querySelector("[data-legend-count]").textContent = count
        input.setAttribute("aria-label", text.t("mind_graph.script.legend.toggle", { name: input.dataset.name, count }))
      }
    }
  }

  function select(index) {
    // "+N more" is not something to select (design answer F4): it opens the
    // list beside the canvas with the posts it stands for, each a row "not
    // in view", and "Open in Posts →" under them. The selection stays as
    // it was.
    if (index >= 0 && state.nodes[index].kind === "more") return openMore(state.nodes[index])

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
    // A new load shows the groups: a read's rows were the load's before.
    asked += 1
    rowsShown = null
    list.setUnlisted(false)
    applyFilter()
    writeCounts()

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
        // Back to a screen whose legend has "Tags" switched off -- the fit is
        // made on the filtered layout, not on the one before it.
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
    if (state.visibleNodes.length < state.nodes.length || state.visibleEdges.length < state.edges.length) sendFilter()
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
    onClick: (x, y) => {
      const index = hit(x, y)
      if (index < 0) dismiss()
      else select(index)
    },
    // The shortcut for "let this one go". (Both of its clicks have selected
    // the node already.)
    onDoubleClick: (x, y) => {
      const index = hit(x, y)
      if (index >= 0) unpin([ index ])
    },
    onEscape: dismiss,
    // Enter with a post selected opens it (the card's own "Open post").
    onEnter: () => card.open(),
    onHover: hover,
    onPan: (dx, dy) => moveCamera(panBy(state.camera, dx, dy)),
    onZoom: (x, y, factor) => moveCamera(zoomAt(state.camera, x, y, factor))
  })
  // A canvas holds colours, not tokens: the graph's and the rows' marks
  // (the list's, the open search results') are drawn again.
  const stopTheme = watchTheme(() => {
    state.theme = readTheme(canvas)
    paintMarks(element)
    requestDraw()
  })
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
    // A toggle of the legend changed: hand the layout only what is shown
    // now. The camera stays where it is. The list, `data-nodes` and
    // `data-edges` and the canvas's name follow the legend whenever there is
    // data, a layout or not: when the worker could not start, the list is
    // all there is, and it must show what the legend says.
    filter() {
      if (!state.data) return
      applyFilter()
      summarise({ announce: true })
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
