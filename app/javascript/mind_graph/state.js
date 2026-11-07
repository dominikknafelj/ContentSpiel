// The mind graph's state and its pure operations: the record every other
// part of the screen reads and `renderer.js` draws from, and the functions
// that change it when the data arrives, when a post is added from the list,
// when a pill's figure falls and when the selection moves. No element is
// read or written here and no word is chosen: what a node is called comes in
// as data (`words`), and a label's width is measured on the `context` the
// caller hands over.
//
// THE RECORD. `data` is the answer as it arrived, `nodes` and `edges` what
// was made from it, `visibleNodes` and `visibleEdges` what the legend shows,
// `positions` the layout's x/y pairs in the order of `nodes`, then the
// camera, the selection, the theme and the canvas's size. `edges[i].source`
// / `.target`, `visibleNodes`, `visibleEdges`, `selected`, `neighbours`,
// `focusIndex`, `hovered` and the members of `pinned` are all INDEXES into
// `nodes` (or `edges`); `indexOf` takes a node's id to its index. `order` is
// the visible nodes that have a label, in the order labels go to them, and
// `free` those of them that are named at any zoom (`graph_data.js`).
// `boxes` is each node's box, for one that is a box (a page's card, the
// pill), else null. `labels` is what the last frame drew, which is what the
// hit test may answer for.
//
// A LABEL'S WIDTH is measured in the font the label is drawn in
// (`renderer.js`, `labelFont`): the sans, and the selected node's in
// semibold. Each label is measured in both, once per load and never in a
// frame (`plainWidths`, `strongWidths`), and `widths` is the first with the
// selected node's entry from the second (`selectIndex`). The label rule, the
// hit test and the hover's backing all read that one array.
import { identity } from "mind_graph/camera"
import { nodeAt } from "mind_graph/hit_test"
import { radiusFor, labelFont } from "mind_graph/renderer"
import { boxOf, moreWidth } from "mind_graph/marks"
import { nodesOf } from "mind_graph/graph_data"

// A label longer than this is cut with an ellipsis; a tag's count is appended
// whole. Counted by code point, so an emoji is never cut in half.
const MAX_LABEL_CHARACTERS = 32
// How far from its hub (or, with none, from the centre) a post added from
// the list starts, in graph units each way: the layout takes it from there.
const ADDED_OFFSET = 30

export function createState(theme) {
  return {
    nodes: [], edges: [], positions: new Float32Array(0), radii: [], boxes: [], widths: [], order: [], free: new Set(),
    visibleNodes: [], visibleEdges: [], camera: identity(), selected: -1, neighbours: new Set(), focusIndex: -1,
    hovered: -1, pinned: new Set(), labels: [],
    theme, width: 0, height: 0, ratio: 1, fitted: false, placed: false, data: null,
    indexOf: new Map(), plainWidths: [], strongWidths: []
  }
}

export function labelFor(node) {
  const suffix = node.kind === "tag" ? ` (${node.count})` : ""
  const room = MAX_LABEL_CHARACTERS - Array.from(suffix).length
  const characters = Array.from(String(node.title))
  return (characters.length > room ? `${characters.slice(0, room - 1).join("")}…` : characters.join("")) + suffix
}

// Whether the label leaves some of the title out (a tag's count after its
// whole name does not, and a node without a label has nothing cut).
const isCut = (node) => node.label !== "" && !node.label.startsWith(String(node.title))

function measure(context, theme, node, selected) {
  context.font = labelFont(theme, node, selected)
  return context.measureText(node.label).width
}

// The data as it arrived becomes the graph the page holds. The selection,
// the fit, the layout's places, the pins, the drawn labels and the hover of
// the graph before this one are not of these nodes, and go.
export function takeData(state, data, { context, words }) {
  state.data = data
  state.nodes = nodesOf(data, words)
  state.indexOf = new Map(state.nodes.map((node, index) => [ node.id, index ]))
  // What a pill hangs off, by name: its row in the list and the heading of
  // its rows say it.
  for (const node of state.nodes) if (node.kind === "more") node.of = state.nodes[state.indexOf.get(node.target)]?.title ?? ""
  // Every end of a line is a node the server sent with it. One whose end is
  // missing all the same is left out, not drawn to the canvas's corner.
  state.edges = data.edges.map((edge) => ({ kind: edge.kind, source: state.indexOf.get(edge.source), target: state.indexOf.get(edge.target) }))
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
    node.cut = isCut(node)
  })
  state.plainWidths = state.nodes.map((node) => measure(context, state.theme, node, false))
  state.strongWidths = state.nodes.map((node) => measure(context, state.theme, node, true))
  state.widths = state.plainWidths.slice()
  state.selected = -1
  state.focusIndex = data.focus ? state.indexOf.get(data.focus.node_id) ?? -1 : -1
  state.fitted = false
  state.placed = false
  state.pinned = new Set()
  state.labels = []
  state.hovered = -1
}

// A post the canvas does not draw, from a row of the list: the row IS the
// post's node as the data has it. A row that says which hub brings its post
// in (`via`) gets that hub's line, as the posts the view drew have theirs: a
// "Shares a tag" line to a tag, a faint `brings` line from a post type or
// "All posts". A row with no hub gets no line.
//
// WHAT THE PAGE DOES NOT KNOW IT DOES NOT SAY: the row was read with no line
// counted, so the post's related posts and tags are not known here. Its
// `degree` is the lines it was given, and its two counts are null, which the
// card leaves out (`card.js`) instead of saying "0 related". `added`: the
// person put it there, which the canvas's name says of a post no page lists
// (`summary.js`). `at` is where the layout starts it: beside its hub, or
// beside the centre.
export function addNode(state, row, { context }) {
  const hub = row.via == null ? -1 : state.indexOf.get(row.via) ?? -1
  const index = state.nodes.length
  const lines = hub < 0 ? [] : state.nodes[hub].kind === "tag" ? [ { kind: "tag", source: index, target: hub } ] : [ { kind: "brings", source: hub, target: index } ]
  const node = { ...row, kind: "post", degree: lines.length, related_count: null, tag_count: null, added: true }
  node.label = labelFor(node)
  node.cut = isCut(node)
  state.nodes.push(node)
  state.indexOf.set(node.id, index)
  state.radii.push(radiusFor(node))
  state.boxes.push(boxOf(node))
  state.plainWidths.push(measure(context, state.theme, node, false))
  state.strongWidths.push(measure(context, state.theme, node, true))
  state.widths.push(state.plainWidths[index])

  const at = hub >= 0 && state.placed ? [ state.positions[hub * 2] + ADDED_OFFSET, state.positions[hub * 2 + 1] + ADDED_OFFSET ] : [ ADDED_OFFSET, ADDED_OFFSET ]
  const positions = new Float32Array(state.nodes.length * 2)
  positions.set(state.positions)
  positions.set(at, index * 2)
  state.positions = positions
  state.edges.push(...lines)
  return { index, node, lines, at }
}

// A pill's words for its count, and its size for its words: whenever one of
// its posts is added. A pill grows to fit ("+1,980 more", design answer H4).
export function resizePill(state, index, { context, words }) {
  const node = state.nodes[index]
  node.title = words.more(node.count)
  context.font = state.theme.countFont
  node.width = moreWidth(context.measureText(node.title).width)
  state.radii[index] = radiusFor(node)
  state.boxes[index] = boxOf(node)
}

// The selection moves to `index` (-1 for none). The selected label is
// semibold, and as wide as that. Its neighbours are the ones the SHOWN lines
// give it, so nothing stays lit (or dimmed) by a line that is not drawn.
export function selectIndex(state, index) {
  if (state.selected >= 0) state.widths[state.selected] = state.plainWidths[state.selected]
  if (index >= 0) state.widths[index] = state.strongWidths[index]
  state.selected = index
  state.neighbours = new Set()
  if (index < 0) return
  for (const edgeIndex of state.visibleEdges) {
    const edge = state.edges[edgeIndex]
    if (edge.source === index) state.neighbours.add(edge.target)
    if (edge.target === index) state.neighbours.add(edge.source)
  }
}

// What the legend shows (`graph_data.js`, `visible`).
export function showOnly(state, { visibleNodes, visibleEdges, order, free }) {
  state.visibleNodes = visibleNodes
  state.visibleEdges = visibleEdges
  state.order = order
  state.free = free
}

// The graph goes, before another is read in its place.
export function clearData(state) {
  state.data = null
  state.nodes = []
  state.edges = []
  state.visibleNodes = []
  state.visibleEdges = []
  state.order = []
  state.labels = []
  state.placed = false
  state.pinned = new Set()
  state.focusIndex = -1
  state.hovered = -1
  state.indexOf = new Map()
}

// A node's centre on the canvas, in CSS pixels.
export const screenOf = (state, index) => ({ x: state.positions[index * 2] * state.camera.k + state.camera.tx, y: state.positions[index * 2 + 1] * state.camera.k + state.camera.ty })

// No node is under any point until the layout has placed them: unplaced,
// every one is at 0, 0 -- the canvas's corner, where nothing is drawn -- and
// when the worker failed that is for good.
export function hitAt(state, x, y) {
  if (!state.placed) return -1
  return nodeAt({ positions: state.positions, indexes: state.visibleNodes, radii: state.radii, boxes: state.boxes, camera: state.camera, sx: x, sy: y, labels: state.labels, widths: state.widths })
}
