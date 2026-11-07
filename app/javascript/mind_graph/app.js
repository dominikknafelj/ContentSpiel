// The mind graph, wired together: fetch the data, hand the layout to the
// worker, and redraw the canvas when something changed. `mount(element)` is
// everything `admin--mind-graph--graph` asks for; `destroy()` stops all of it
// -- the request, the worker, the frame, the observers -- so nothing runs or
// draws after the screen is left. The parts it builds own the rest, each
// with its contract in its header: the state and its operations
// (`state.js`), the frame (`frame.js`), the canvas's gestures and the hover
// (`gestures.js`), the selection, its card and the pins (`selection.js`), the
// list's reads (`list_reads.js`) and the notice (`notice.js`).
//
// What the screen shows is said on the element, for tests and for anything
// that wants to know without reading a canvas: `data-state` (loading, ready,
// failed, worker-failed), `data-settled`, `data-nodes` and `data-edges` (how
// many the legend's toggles show, written by the toggle itself, before the
// layout has moved), `data-opened-lines` (below), and from the parts
// `data-zoom`, `data-labelled`, `data-selected`, `data-neighbours`,
// `data-hovered` and `data-pinned`. `element.mindGraph.screenPosition(id)`
// answers where a visible node is, in client coordinates (null for one the
// filter hides, and for every node until the layout has placed them),
// `.labelBox(id)` the box of its label as the last frame drew it (null when
// it drew none), `.markBox(id)` the box of a mark that is one (a page's card,
// the pill; null for any other), `.graphPosition(id)` where the layout has a
// node in GRAPH units, the camera not applied (null until the layout has
// placed them), and `.draws()` how many frames have been drawn. Whatever of
// this is written into the page, the controller's `reset` takes back.
//
// WHAT IS DRAWN. Five kinds of node (`graph_data.js` makes them from the
// payload; `marks.js` draws each): a page, a post, a tag, a post type a page
// lists (with the one "All posts") and, in a page's local view, a "+N more"
// pill per target. Five kinds of line (`renderer.js`). ONE NODE RESTS AT THE
// CENTRE of the layout (`graph_data.js`, `anchorOf`): Home in the whole
// graph, the focus in a local view, where Home is a page like any other. The
// worker holds it there (`layout_worker.js`, the anchor). That is not a pin:
// `state.pinned` does not hold it, nothing shows it as pinned, and nothing
// here can release it. Dragged, it is pinned where it is dropped like any
// node, and released it eases back to the centre.
//
// THE LEGEND IS THE FILTER. Its checkboxes say which kinds of node and of
// line are shown, and `graph_data.js`'s `visible` is the one place that
// decides what that means; the state is the checkboxes' own and nothing here
// keeps a copy. A toggle changes what is drawn, the list beside the canvas
// and the canvas's name, and leaves each toggle's COUNT as it is: a count is
// what the response holds, written once per load (`writeCounts`).
//
// A TOGGLE IS A FILTER ON WHAT IS DRAWN, NOT A NEW LAYOUT. THE LAYOUT IS
// COMPUTED ONCE, OVER EVERYTHING THE DATA HOLDS, and a toggle sends the
// worker nothing: no node moves, nothing warms up, `data-settled` stays, the
// camera stays. With eight toggles, four of them of lines alone, a layout per
// toggle would reshuffle the picture when a line was hidden, and a node
// nobody touched could leave the view. Every node keeps its place, shown or
// not, and what is switched back on comes back where it was. What a toggle
// changes is `state.visibleNodes` and `state.visibleEdges`, which the
// renderer, the hit test, the labels, the list and the summary read. A PIN IS
// THE LAYOUT'S, so a toggle does not touch it either: a pinned node that is
// hidden is still held, still counted by "Release N pinned", and comes back
// pinned (letting it go would warm the layout up). The selection and the
// hover are of what is drawn, and go with a node that is hidden. The price: a
// cluster does not close up when what held it apart is hidden. THE CANVAS'S
// NAME is the summary of what is in view (`summary.js`); after a toggle the
// same words are announced (`notice.js`).
//
// A POST ADDED FROM THE LIST is a change of the graph itself, and the layout
// is told of it (`addPost`, the worker's `add`). The row IS the post's node,
// so nothing is fetched (`state.js`, `addNode`). Added once: pressed again,
// or for a post that is drawn after all, it selects. WITH "POSTS" SWITCHED
// OFF the press switches it back on first: the row says "Activate to add it
// to the graph", and with posts hidden the press would add a node nobody
// sees; the checkbox is the state, so it follows, and the change is
// announced as a toggle's is. AFTER A ROW IS ADDED EVERY FIGURE IS TRUE: the
// pill stands for one post fewer (its words, its width, and at none the pill
// itself and its rows go), the canvas's name counts the pills as they now
// are, and the notice no longer counts the post among those that aren't
// shown -- all three read what the page holds (`graph_data.js`,
// `countAdded`). WITHOUT A GRAPH THERE IS NOTHING TO ADD TO (it is still
// being read, its read failed, or "Show everything" is on its way): the
// press does nothing.
//
// A SITE WITH TOO MANY LINES FOR ONE PICTURE (pages spec, decision 6) opens
// around Home. The data's answer says where (`open`, and how many lines the
// site has); this page then reads that page's local view (`data-open-url`),
// writes the figure on the element (`data-opened-lines`, which the canvas's
// name reads: "Showing the area around Home. The site has ...", H5) and
// shows the bar that says why, with "Show everything". That is a BUTTON: it
// reads the whole graph (`data-everything-url`) into this page and navigates
// nowhere, so the choice is in no address and a reload, and Back to this
// page, open around Home again.
//
// THE FIRST VIEW FITS EVERYTHING: while the layout takes shape the camera
// follows it, and when it has cooled down the fit is final (`state.fitted`).
// From then on -- or from the person's first zoom, pan or drag, if that
// comes sooner (`gestures.js`) -- the camera moves only on their input or
// "Fit all": a filter, a resize and a later reheat of the layout leave it
// where it is. Nodes are not clamped to the box; the box is a window onto
// the graph.
//
// MOTION. How fast the layout is shown is the worker's business
// (`layout_worker.js`, PACING): this page draws every `tick` it is sent. All
// it adds is the one fact the worker can't find out -- whether the person
// asked for reduced motion -- handed over with `start`.
import { messages } from "i18n/messages"
import { createLayout } from "mind_graph/layout_client"
import { zoomAt, bounds, fit } from "mind_graph/camera"
import { LABEL_GAP, LABEL_HEIGHT } from "mind_graph/labels"
import { readTheme, watchTheme } from "mind_graph/theme"
import { collisionRadius } from "mind_graph/marks"
import { anchorOf, visible, counts, countAdded, placedFor, NODE_TOGGLES, LINE_TOGGLES } from "mind_graph/graph_data"
import { summaryOf } from "mind_graph/summary"
import { createCard, fill } from "mind_graph/card"
import { recordId } from "mind_graph/ids"
import { paintMarks } from "mind_graph/swatches"
import { attachSearch } from "mind_graph/search_box"
import { createList } from "mind_graph/node_list"
import { createState, takeData, addNode, resizePill, showOnly, clearData } from "mind_graph/state"
import { createFrame } from "mind_graph/frame"
import { attachGestures } from "mind_graph/gestures"
import { createSelection } from "mind_graph/selection"
import { createListReads, LOAD_TIMEOUT_MS } from "mind_graph/list_reads"
import { say, announce } from "mind_graph/notice"
import { readParts } from "mind_graph/parts"

const BUTTON_ZOOM = 1.4

export function mount(element) {
  // The graph's own canvas, by its target: the legend's swatches are
  // canvases too, and come before it in the document.
  const canvas = element.querySelector("[data-admin--mind-graph--graph-target='canvas']")
  const notice = element.querySelector("[data-admin--mind-graph--graph-target='notice']")
  const context = canvas.getContext("2d")
  const text = messages(element)
  const aborter = new AbortController()
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)")
  const state = createState(readTheme(canvas))
  let destroyed = false
  let layout = null
  // The address the graph was last asked from: the page's own (`data-url`),
  // the local view a large site opens in, or the whole graph after "Show
  // everything". Retry asks the same one again.
  let source = element.dataset.url
  // The graph that is being read was asked for by "Show everything": its
  // summary is announced when it is drawn, as the opened view's was.
  let announceNext = false

  const tooltip = element.querySelector("[data-mind-graph-tooltip]")
  const release = element.querySelector("[data-mind-graph-release]")
  const zoomReadout = element.querySelector("[data-mind-graph-zoom]")
  const cardElement = element.querySelector("[data-mind-graph-card]")
  // The bar of the view a large site opens in, its sentence and its button
  // (absent from a focused view's page: such a view is never opened by rule).
  const openedBar = element.querySelector("[data-mind-graph-opened]")
  const search = element.querySelector("[data-mind-graph-search]")
  const dotClasses = JSON.parse(element.dataset.dotClasses)
  const typeLabels = JSON.parse(element.dataset.typeLabels)
  const buttonClasses = JSON.parse(element.dataset.buttonClasses)
  // The chips and the card's Close, cloned from the server's own markup.
  const parts = readParts(element)

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

  // What the data's nodes are called, in the page's words. A pill's figure
  // is grouped as the messages' language groups it, and `count` in that
  // message is the figure as text, not a plural's number, because the words
  // have one form.
  const words = {
    allPosts: text.t("mind_graph.script.all_posts"),
    more: (count) => text.t("mind_graph.script.more", { count: number(count) }),
    retired: (name) => text.t("mind_graph.script.retired_type", { name })
  }

  // The parts call one another through these: each is built before the one
  // it calls is, and nothing is called until the screen is in use.
  const frame = createFrame({ element, canvas, context, state, reducedMotion, zoomReadout, percent, onDrawn: () => selection.positionCard() })
  const card = createCard(cardElement, {
    text,
    number,
    urls: {
      postFocus: element.dataset.postFocusUrl, tagFocus: element.dataset.tagFocusUrl, tagPosts: element.dataset.tagPostsUrl, postNotes: element.dataset.postNotesUrl,
      pageFocus: element.dataset.pageFocusUrl, pageNotes: element.dataset.pageNotesUrl
    },
    typeLabels,
    dotClasses,
    buttonClasses,
    parts,
    // The button goes with the card it is in; the focus goes back to where the
    // card was opened from.
    onClose: () => selection.closeCard(),
    onPin: () => {
      if (state.selected < 0) return
      if (state.pinned.has(state.selected)) selection.unpin([ state.selected ])
      else selection.pin(state.selected)
    },
    // The card's notes arrive after the card was measured, and a note started
    // there changes the node's badge: the card is measured and placed again,
    // and the canvas redrawn.
    onChange: () => {
      selection.measureCard()
      frame.request()
    }
  })
  // "Not listed on any page" is there only for a viewer the server gave its
  // address (one who reads a page).
  const list = createList(element.querySelector("[data-mind-graph-list]"), {
    text, number, dotClasses, typeLabels, parts, retryClass: buttonClasses.tertiary, unlisted: Boolean(element.dataset.unlistedUrl),
    onSelect: (id) => {
      const index = state.indexOf.get(id)
      if (index != null) selection.reveal(index)
    },
    onHover: (id) => gestures.hoverRow(id == null ? -1 : state.indexOf.get(id) ?? -1),
    onAdd: addPost,
    // A pill's row: what a press on the pill does.
    onMore: (id) => {
      const index = state.indexOf.get(id)
      if (index != null) reads.openMore(state.nodes[index])
    },
    onUnlisted: (on) => {
      if (on) reads.showRowsFrom(element.dataset.unlistedUrl)
      else reads.showGroups()
    }
  })
  const reads = createListReads({ element, list, state, text, number, signal: aborter.signal, destroyed: () => destroyed })
  const gestures = attachGestures({
    canvas, element, state, tooltip, cardElement, layout: () => layout,
    act: { select: (index) => selection.select(index), dismiss, unpin: (indexes) => selection.unpin(indexes), pinsChanged: () => selection.pinsChanged(),
           measureCard: () => selection.measureCard(), openCard: () => card.open(), request: frame.request }
  })
  const selection = createSelection({
    element, canvas, state, card, cardElement, list, layout: () => layout, release, text, request: frame.request, moveCamera: gestures.moveCamera, onMore: (node) => reads.openMore(node)
  })
  // The search field is HTML beside the canvas, not part of the data request:
  // it works whatever the graph is doing, a failed load included.
  const stopSearch = attachSearch(search.querySelector("input"), search.querySelector("[data-mind-graph-results]"), { url: search.dataset.url, text, status: search.querySelector("[data-mind-graph-status]"), dotClasses })

  // The legend's toggles: the state is the checkboxes' own, so Back restores
  // what the person had chosen. `switched(name, true)` is the kinds that are
  // on, `switched(name, false)` those that are off, each in the legend's
  // order.
  const toggles = (name) => Array.from(element.querySelectorAll(`[data-mind-graph-legend] input[name="${name}"]`))
  const switched = (name, on) => toggles(name).filter((input) => input.checked === on).map((input) => input.value)
  const setState = (value) => { element.dataset.state = value }

  function fitAll() {
    if (state.width === 0) return
    state.camera = fit(bounds(state.positions, state.visibleNodes), state.width, state.height)
    state.fitted = true
    gestures.rehover()
    frame.request()
  }

  // A kind of node that is off takes its nodes and their lines; a kind of
  // line that is off takes its lines and nothing else.
  function applyFilter() {
    // A kind is hidden only by a toggle that is switched OFF: one the viewer
    // has no toggle for (the legend gives none for a kind they cannot read,
    // and the data then holds none of it) is never hidden by its absence.
    const on = (all, name) => new Set(all.filter((kind) => !switched(name, false).includes(kind)))
    showOnly(state, visible({ nodes: state.nodes, edges: state.edges, on: { nodes: on(NODE_TOGGLES, "mind_graph_nodes"), lines: on(LINE_TOGGLES, "mind_graph_lines") } }))
    // The selection goes with a node the filter hides; one that stays keeps
    // its place, and its neighbours are the ones the shown edges give it now.
    if (state.selected >= 0) selection.select(state.visibleNodes.includes(state.selected) ? state.selected : -1)
    element.dataset.nodes = state.visibleNodes.length
    element.dataset.edges = state.visibleEdges.length
    reads.draw()
    selection.pinsChanged()
    gestures.forgetHidden()
    summarise()
  }

  function addPost(row) {
    if (!state.data) return
    const switchedOn = showPosts()
    const known = state.indexOf.get(row.id)
    if (known != null) {
      if (switchedOn) refilter()
      return state.visibleNodes.includes(known) ? selection.reveal(known) : undefined
    }

    const { index, node, lines, at } = addNode(state, row, { context })
    // What the page holds now says the post is drawn: its pill stands for
    // one fewer (and is written and measured again), and at none its rows
    // go with it; an unconnected post is no longer one that isn't shown.
    const pill = countAdded(state.nodes, state.data, row)
    if (pill >= 0) {
      resizePill(state, pill, { context, words })
      if (state.nodes[pill].count <= 0) {
        // A SPENT PILL is not shown again (`graph_data.js`, `spent`), so a
        // pin on it is let go: "Release 1 pinned" would name something
        // nobody can see.
        selection.unpin([ pill ])
        reads.dropPillRows(state.nodes[pill].id)
      }
    }

    applyFilter()
    writeCounts()
    // (Only over a graph that is drawn: the notice of a worker that failed
    // says so, and stays.)
    if (element.dataset.state === "ready") notify()
    if (switchedOn) summarise({ announce: true })
    if (layout) {
      element.removeAttribute("data-settled")
      // The layout holds every node, whatever the legend hides, so the
      // post's hub is there for its line also while "Post types" is off.
      layout.add({ id: node.id, radius: collisionRadius(node), x: at[0], y: at[1] }, lines.map((line) => ({ source: state.nodes[line.source].id, target: state.nodes[line.target].id, kind: line.kind })))
    } else if (element.dataset.state === "ready") {
      // Nothing was drawn, so no layout was started: there is something now.
      element.removeAttribute("data-settled")
      startLayout()
    }
    if (state.visibleNodes.includes(index)) selection.reveal(index)
  }

  // The "Posts" toggle, switched on if it was off: whether it was. A viewer
  // with no such toggle has no posts hidden.
  function showPosts() {
    const toggle = toggles("mind_graph_nodes").find((input) => input.value === "post")
    if (!toggle || toggle.checked) return false
    toggle.checked = true
    return true
  }

  // Escape on the canvas and a click on empty space take back what the last
  // press on the canvas brought: the selection, and with nothing selected
  // the rows of a "+N more", or the error line of a pill's read that failed
  // (the list shows its groups again).
  function dismiss() {
    if (state.selected < 0 && reads.pillShown()) reads.showGroups()
    else selection.select(-1)
  }

  // The canvas is one image to a screen reader, and its name says what is on
  // it NOW (`summary.js`; design answers G6 and H5). After a toggle
  // (`announce`) the same words are announced (`notice.js`).
  function summarise({ announce: aloud = false } = {}) {
    const summary = summaryOf({
      nodes: state.nodes, visibleNodes: state.visibleNodes, lines: state.visibleEdges.length, data: state.data,
      off: { nodes: switched("mind_graph_nodes", false), lines: switched("mind_graph_lines", false) }, toggles: toggles("mind_graph_nodes").length,
      // The view the 3,000-line rule opened (the server says so on the element).
      aroundHome: opened()
    }, { text, number })
    canvas.setAttribute("aria-label", summary)
    if (aloud) announce(notice, summary)
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

  function show(data) {
    // TOO MANY LINES FOR ONE PICTURE: the server says where to open instead,
    // and this page reads that page's local view in the whole graph's place.
    // Nothing navigates: the address stays the screen's own, so a reload asks
    // the server again. The figure is written for the bar and for the
    // canvas's name, and is a whole number or the answer is no answer. Only
    // the page's OWN address may be answered so: a local view or
    // "everything" that said "open" would be asked for ever.
    if (data.open) {
      if (source !== element.dataset.url || !Number.isSafeInteger(data.edges) || data.edges < 0) throw new Error("mind graph: an answer that says where to open, where none can")
      element.dataset.openedLines = data.edges
      return load(fill(element.dataset.openUrl, "__ID__", recordId(data.open)))
    }

    // (A graph was drawn before this one, after "Show everything": its
    // layout ends here, if `clear` has not ended it.)
    layout?.stop()
    layout = null
    takeData(state, data, { context, words })
    gestures.clearHover()
    selection.select(-1)
    reads.forgetPillReads()
    showOpened()
    applyFilter()
    writeCounts()
    notify()
    // The view a large site opened in is not what was asked for: where it
    // is, and what the site holds, is announced. So is the whole graph that
    // "Show everything" put in its place.
    if (opened() || announceNext) summarise({ announce: true })
    announceNext = false
    setState("ready")

    // Nothing to lay out: settled as it stands, and no worker is started.
    if (state.nodes.length === 0) {
      element.setAttribute("data-settled", "")
      return frame.request()
    }
    startLayout()
  }

  // The notice's sentences about what is NOT drawn, from what the page holds
  // now: said when the data arrives, and again when a post was added from
  // the list (`data.isolated` is then one fewer, `graph_data.js`).
  //
  // The two views cut differently (`PostGraph::Global` keeps the best
  // connected, `PostGraph::Local` the nearest to the focus), so each has its
  // own sentence. A figure in a sentence is grouped (`number`); `count`
  // only chooses the plural form.
  function notify() {
    const data = state.data
    const cut = { shown: number(data.shown), total: number(data.total) }
    const capped = data.focus ? text.t("mind_graph.script.capped_local", cut) : text.t("mind_graph.script.capped", cut)
    say(
      notice,
      state.edges.length === 0 ? text.t("mind_graph.script.no_connections") : null,
      data.shown < data.total ? capped : null,
      // "Other" posts, beside the ones drawn; with nothing drawn there are no
      // others, and the sentence is the plain one.
      data.isolated > 0 ? text.t(state.nodes.length > 0 ? "mind_graph.script.isolated" : "mind_graph.script.isolated_only", { count: data.isolated, figure: number(data.isolated) }) : null
    )
  }

  // Whether what is drawn is the view a large site opened in: the server
  // said where to open (`data-opened-lines`), and this is that local view.
  const opened = () => Boolean(element.dataset.openedLines) && Boolean(state.data?.focus)

  // The bar of that view: why the whole graph is not what is drawn, and
  // "Show everything", whose whole name says how many lines that is. Shown
  // while the view is drawn, hidden and emptied otherwise.
  function showOpened() {
    if (!openedBar) return
    const lines = Number(element.dataset.openedLines)
    const button = openedBar.querySelector("[data-mind-graph-everything]")
    openedBar.hidden = !opened()
    openedBar.querySelector("[data-mind-graph-opened-line]").textContent = opened() ? text.t("mind_graph.script.opened.line", { count: lines, figure: number(lines) }) : ""
    if (opened()) button.setAttribute("aria-label", text.t("mind_graph.script.opened.everything_name", { count: lines, figure: number(lines) }))
    else button.removeAttribute("aria-label")
  }

  // The graph that is drawn goes, before another is read in its place: its
  // layout, its selection and its card, its rows and its name. What `show`
  // writes when the data arrives is written again then.
  function clear() {
    layout?.stop()
    layout = null
    selection.select(-1)
    reads.forget()
    clearData(state)
    gestures.clearHover()
    element.dataset.nodes = 0
    element.dataset.edges = 0
    selection.pinsChanged()
    gestures.hideTooltip()
    list.setUnlisted(false)
    list.clear()
    canvas.setAttribute("aria-label", canvas.dataset.label)
    frame.request()
  }

  // "Show everything": the whole graph is read into this page. The figure
  // and the bar go first, so nothing says "around Home" of what is then
  // drawn; the focus, which was on the button the bar hides, goes to the
  // canvas. Nothing is stored and the address is not touched.
  function showEverything() {
    if (destroyed || !openedBar || !opened()) return
    const focused = openedBar.contains(document.activeElement)
    element.removeAttribute("data-opened-lines")
    clear()
    showOpened()
    if (focused) canvas.focus()
    announceNext = true
    load(element.dataset.everythingUrl)
  }

  function startLayout() {
    try {
      layout = createLayout({
        workerUrl: element.dataset.workerUrl,
        d3Url: element.dataset.d3Url,
        onTick: (positions) => {
          // Whole, also when the worker answered before it took a node this
          // page has added since (`graph_data.js`, `placedFor`).
          state.positions = placedFor(positions, state.positions, state.nodes.length)
          state.placed = true
          if (!state.fitted) state.camera = fit(bounds(state.positions, state.visibleNodes), state.width, state.height)
          // The first positions: a card opened from the list before there was
          // a layout now has a node to stand beside.
          selection.forgetPlace()
          frame.request()
        },
        // Only a `settled` that answers everything sent so far arrives here
        // (`layout_client.js`). The fit is of what is SHOWN: Back to a
        // screen whose legend has "Tags" switched off fits what is drawn.
        onSettled: () => {
          if (!state.fitted) fitAll()
          element.setAttribute("data-settled", "")
        },
        onError: workerFailed
      })
    } catch (error) {
      return workerFailed(error.message)
    }
    // EVERY node and line of the data, whatever the legend shows: a toggle
    // is no business of the layout's. The worker can't ask about motion
    // itself, so it is told (as the page found it now; a change of the
    // setting applies from the next load). What the layout keeps clear
    // around a node is its mark's reach (a box's is half its diagonal).
    const anchor = anchorOf(state.data)
    layout.start(state.nodes.map((node) => ({ id: node.id, radius: collisionRadius(node), anchor: node.id === anchor })),
      state.edges.map((edge) => ({ source: state.nodes[edge.source].id, target: state.nodes[edge.target].id, kind: edge.kind })),
      { reducedMotion: reducedMotion.matches })
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
    selection.pinsChanged()
    element.removeAttribute("data-settled")
    setState("worker-failed")
    say(notice, text.t("mind_graph.script.worker_failed"))
  }

  // Reads the graph from `url`: the address it was last read from, unless
  // another is named (the local view a large site opens in, the whole graph
  // after "Show everything"). Retry asks `source` again.
  async function load(url = source) {
    source = url
    setState("loading")
    element.removeAttribute("data-settled")
    say(notice, text.t("mind_graph.script.loading"))
    try {
      // Two ways out of a request that is still open: leaving the screen
      // (`aborter`, an AbortError, silent) and no answer in time (a
      // TimeoutError, which is a failure like any other and gets Retry).
      const signal = AbortSignal.any([ aborter.signal, AbortSignal.timeout(LOAD_TIMEOUT_MS) ])
      const response = await fetch(source, { headers: { Accept: "application/json" }, signal })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json()
      if (!destroyed) show(data)
    } catch (error) {
      if (destroyed || error.name === "AbortError") return
      setState("failed")
      const retry = document.createElement("button")
      retry.type = "button"
      // The shared tertiary button; the notice lets the pointer through to
      // the canvas, and this one button takes it back.
      retry.className = `pointer-events-auto ${buttonClasses.tertiary}`
      retry.textContent = text.t("mind_graph.script.retry")
      retry.addEventListener("click", () => load(), { once: true })
      say(notice, text.t("mind_graph.script.load_failed"), retry)
    }
  }

  // A canvas holds colours, not tokens: the graph's and the rows' marks
  // (the list's, the open search results') are drawn again.
  const stopTheme = watchTheme(() => {
    state.theme = readTheme(canvas)
    paintMarks(element)
    frame.request()
  })
  // The first real size fits the view, once the layout has settled.
  function resize() {
    if (!frame.resize()) return
    if (!state.fitted && element.hasAttribute("data-settled")) fitAll()
    selection.forgetPlace()
    frame.request()
  }
  const observer = new ResizeObserver(resize)
  observer.observe(canvas)
  resize()
  load()

  // A toggle of the legend changed (or was switched back on by a row that
  // adds a post): what is drawn changes, and nothing else.
  function refilter() {
    if (!state.data) return
    applyFilter()
    summarise({ announce: true })
    gestures.rehover()
    frame.request()
  }

  const zoomBy = (factor) => gestures.moveCamera(zoomAt(state.camera, state.width / 2, state.height / 2, factor))

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
      const index = state.indexOf.get(id)
      const at = this.screenPosition(id)
      const size = index == null ? null : state.boxes[index]
      return at && size ? { left: at.x - size.width / 2, right: at.x + size.width / 2, top: at.y - size.height / 2, bottom: at.y + size.height / 2 } : null
    },
    // Where the layout has a node, in GRAPH units (the camera not applied):
    // the anchor's is 0, 0 while nobody holds it.
    graphPosition(id) {
      const index = state.indexOf.get(id)
      return index == null || !state.placed ? null : { x: state.positions[index * 2], y: state.positions[index * 2 + 1] }
    },
    draws: frame.draws
  }

  return {
    zoomIn: () => zoomBy(BUTTON_ZOOM),
    zoomOut: () => zoomBy(1 / BUTTON_ZOOM),
    fit: fitAll,
    releasePinned: () => selection.unpin(Array.from(state.pinned)),
    // A toggle of the legend changed: what is drawn changes, and nothing
    // else. The layout is told nothing and the camera stays where it is.
    // The list, `data-nodes` and `data-edges` and the canvas's name follow
    // the legend whenever there is data, a layout or not: when the worker
    // could not start, the list is all there is, and it must show what the
    // legend says.
    filter: refilter,
    showEverything,
    destroy() {
      destroyed = true
      frame.stop()
      aborter.abort()
      layout?.stop()
      layout = null
      observer.disconnect()
      gestures.stop()
      stopTheme()
      selection.stop()
      stopSearch()
      list.destroy()
      card.hide()
      release.hidden = true
      release.textContent = ""
      delete element.mindGraph
    }
  }
}
