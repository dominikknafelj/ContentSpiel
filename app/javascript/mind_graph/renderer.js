// Draws one frame of the mind graph (mind graph canvas spec §4.3, §5.1).
// Order: edges, marks (each with its pin), labels, notes badges, rings. Everything is in SCREEN pixels: the
// camera moves a node's centre, and a node is the same size at every zoom.
//
// The marks and the five looks of a record's state are `marks.js`'s
// (`drawMark`); the lines are the five styles of `LINE_STYLES` below.
//
// WHAT IS OUTSIDE THE CANVAS IS NOT DRAWN. A node whose mark lies wholly
// outside is skipped, and so is an edge that can't cross the canvas: both its
// ends beyond the same side. (Not "both ends outside": an edge from far left
// to far right crosses the whole view.) Zoomed in, most of the graph is
// outside, and a path of long dashed lines costs the rasteriser by its length,
// seen or not -- measured at 2,000 posts and the largest zoom, about one frame
// in fifty took two frames' time while panning without this, none with it
// (spec §7).
//
// THE STATES (the round of 2026-10-08), which combine:
// - HOVERED (`hovered`, by the pointer or by its row in the list): a 1px ink
//   ring round the mark, and its label in full ink on a backing, drawn even
//   where the label rule hides it. Hovering dims nothing.
// - SELECTED: a 2px accent ring with a gap, a semibold label in full ink, its
//   edges brightened in ink (each keeps its kind's dash and cap; the accent
//   stays the ring's), and every node and edge not connected to it at DIM.
// - PINNED (`pinned`, a Set of indexes): a small ink dot with a surface ring
//   at the mark's top-right. It is drawn with the node, at the node's
//   strength, whatever else the node is.
// - WITH OPEN NOTES (`open_notes` above zero, a post's and a page's; notes spec §4.4):
//   the count in a small mono badge on the mark's top-LEFT corner, opposite
//   the pin, so a node can carry both: the badge keeps its right edge where
//   it is and grows to the LEFT with its text, away from the pin. A card's
//   badge stands OUTSIDE it, over whatever it lands on, on a 2px ring of the
//   ground (`marks.js`, `notesPill`). Not a ring:
//   a ring means hovered, selected or focused. Drawn after the labels, at
//   the node's strength, and the same size at every zoom. Always neutral: what
//   is unread for the viewer is said on the rows of the node's card.
// - The focus of a local view: a dotted accent ring.
// A ring follows its mark: a tag's is a square, a page's card's a box, the
// pill's a pill (rounded as the pill is), every other a circle. So does what hangs on a corner: on a
// box the pin and the notes badge are at the box's own corners
// (`marks.js`, `topCorner`), not where a circle as wide as it would have them.
//
// A LABEL (pages spec §4; design answer F6): a page's and a post type's in
// ink, a tag's in mono `meta`, a post's in `dim`; the selected node's is
// semibold (a tag's still mono) and the hovered node's on its backing, both
// in full ink. A node
// with no label (the "+N more" pill: its words are inside it) has none.
//
// Nothing here is a colour: every one comes in with `theme` (`theme.js`), and
// what dims is dimmed by `globalAlpha`.
import { drawMark, boxOf, radiusFor, topCorner, notesPill, notesLabel, NOTES_BADGE, NOTES_RING } from "mind_graph/marks"

// The app and the module tests ask for a node's size here.
export { radiusFor }

const DIM = 0.28
// One path per style (pages spec §4): Shares a tag dashed `meta`, Related
// solid ink, a hub's line to what it brings in faint, Lists dotted `dim`,
// Tree solid in `tree` (dim; in dark dim at 60%). Drawn in this order, so a tree line
// is on top of a tag's. A value of `colour` is a theme key.
//
// LISTS (design answer G3): 1.5px with ROUND caps and a dash of 0.1 / 3.5.
// A dash that short is its two caps, so each is a round dot 1.5px across,
// 3.6px from the next; with a butt cap it would be a hairline.
// BRINGS (the third answers' "Local view lines", G2, H1): a page's local
// view only, the hub's line to each post it brings in and to "+N more".
export const LINE_STYLES = {
  tag: { colour: "meta", width: 1, dash: [ 4, 3 ], alpha: 0.8, cap: "butt" },
  related: { colour: "ink", width: 1.5, dash: [], alpha: 0.35, cap: "butt" },
  brings: { colour: "faint", width: 1, dash: [], alpha: 1, cap: "butt" },
  lists: { colour: "dim", width: 1.5, dash: [ 0.1, 3.5 ], alpha: 1, cap: "round" },
  tree: { colour: "tree", width: 1, dash: [], alpha: 1, cap: "butt" }
}
// Below this zoom the lines of shared tags are not drawn (design answer,
// part one §6): zoomed out they are most of the ink and say the least. A
// DRAWING rule only: the filter, its counts and a selection's neighbours do
// not change with it.
const HIDE_TAG_LINES_BELOW = 0.4
// The font a node's label is drawn in, and so the font its width is measured
// in (`app.js`): a tag's is mono, like a tag everywhere else in CS Studio,
// and the selected node's is semibold in its own face.
export const labelFont = (theme, node, selected) =>
  node.kind === "tag" ? (selected ? theme.strongMonoFont : theme.monoFont) : selected ? theme.strongFont : theme.font

// A label's colour by kind, as a theme key (pages spec §4): a page's and a
// type's read first, a post's is `dim` until it is hovered or selected.
const LABEL_COLOURS = { page: "ink", type: "ink", tag: "meta", post: "dim", more: "dim" }
// The width of the surface-coloured outline under a label, which keeps a title
// readable where it crosses an edge.
const LABEL_HALO = 3
// The backing of the hovered node's label: how far it reaches beyond the text.
const BACKING_X = 4
const BACKING_HEIGHT = 18
// How far outside the canvas an edge's end or a node's edge may be and still
// count as on it: half the widest stroke, rounded up, and a node's rings and
// its notes badge (which reaches furthest on a page's card: "99+" and its ring
// there end 30px left of the card's edge, and 20.5px left of a 7px dot's).
const EDGE_MARGIN = 2
const NODE_MARGIN = 30
// A ring's distance from the mark's edge.
const HOVER_RING = 2.5
const SELECTED_RING = 4
const FOCUS_RING = 5
// `edges[i].source` / `.target` are node INDEXES (`app.js` converts the ids
// once), `visibleNodes` / `visibleEdges` indexes too. `width` and `height` are
// CSS pixels; the bitmap is `ratio` times that, which the transform takes up.
// A label of `labels` marked `hover` is the hovered node's.
export function draw(context, { width, height, ratio, camera, theme, nodes, edges, positions, radii, widths = [], visibleNodes, visibleEdges, labels, selected, neighbours, focusIndex, hovered = -1, pinned = new Set() }) {
  context.setTransform(ratio, 0, 0, ratio, 0, 0)
  context.clearRect(0, 0, width, height)

  const x = (index) => positions[index * 2] * camera.k + camera.tx
  const y = (index) => positions[index * 2 + 1] * camera.k + camera.ty
  const dimmed = (index) => selected >= 0 && index !== selected && !neighbours.has(index)
  // Which sides of the canvas a point lies beyond, as four bits (left, right,
  // above, below; 0 is "on the canvas", give or take `margin`).
  const beyond = (sx, sy, margin) =>
    (sx < -margin ? 1 : sx > width + margin ? 2 : 0) | (sy < -margin ? 4 : sy > height + margin ? 8 : 0)

  // One path per style and strength, so a few thousand edges are a handful
  // of strokes. With a selection, the edges that touch it are the bright pass
  // and the rest the faded one; with none, every edge is the plain pass.
  for (const [ kind, style ] of Object.entries(LINE_STYLES)) {
    if (kind === "tag" && camera.k < HIDE_TAG_LINES_BELOW) continue
    for (const pass of selected < 0 ? [ "plain" ] : [ "faded", "bright" ]) {
      context.beginPath()
      for (const edgeIndex of visibleEdges) {
        const edge = edges[edgeIndex]
        if (edge.kind !== kind) continue
        const touchesSelection = edge.source === selected || edge.target === selected
        if (pass !== "plain" && touchesSelection !== (pass === "bright")) continue
        const fromX = x(edge.source), fromY = y(edge.source), toX = x(edge.target), toY = y(edge.target)
        if (beyond(fromX, fromY, EDGE_MARGIN) & beyond(toX, toY, EDGE_MARGIN)) continue
        context.moveTo(fromX, fromY)
        context.lineTo(toX, toY)
      }
      const bright = pass === "bright"
      context.globalAlpha = bright ? 0.9 : style.alpha * (pass === "faded" ? DIM : 1)
      context.strokeStyle = bright ? theme.ink : theme[style.colour]
      context.lineWidth = style.width + (bright ? 0.5 : 0)
      context.lineCap = style.cap
      context.setLineDash(style.dash)
      context.stroke()
    }
  }
  // The marks, the pin and the rings are drawn with the cap they expect.
  context.lineCap = "butt"
  context.setLineDash([])

  const badged = []
  for (const index of visibleNodes) {
    if (beyond(x(index), y(index), radii[index] + NODE_MARGIN)) continue
    context.globalAlpha = dimmed(index) ? DIM : 1
    const node = nodes[index]
    drawMark(context, theme, node, x(index), y(index), radii[index])
    if (pinned.has(index)) drawPin(context, theme, x(index), y(index), topCorner(node, radii[index]))
    // A record's notes: a tag, a post type and the pill have none. Drawn
    // after every mark and label, below.
    if (notesPill(node, x(index), y(index), radii[index])) badged.push(index)
  }

  context.textBaseline = "middle"
  context.lineJoin = "round"
  for (const label of labels) {
    const node = nodes[label.index]
    // The pill's words are inside it: no label, and no empty backing beside
    // it when it is hovered.
    if (!node.label) continue
    const chosen = label.index === selected
    context.font = labelFont(theme, node, chosen)
    if (label.hover) {
      // Full ink on a backing, at full strength whatever the selection dims.
      context.globalAlpha = 1
      context.fillStyle = theme.sunken
      context.fillRect(label.x - BACKING_X, label.y - BACKING_HEIGHT / 2, (widths[label.index] || 0) + BACKING_X * 2, BACKING_HEIGHT)
      context.fillStyle = theme.ink
      context.fillText(node.label, label.x, label.y)
      continue
    }
    context.globalAlpha = label.alpha * (dimmed(label.index) ? DIM : 1)
    context.lineWidth = LABEL_HALO
    context.strokeStyle = theme.surface
    context.fillStyle = chosen ? theme.ink : theme[LABEL_COLOURS[node.kind]]
    context.strokeText(node.label, label.x, label.y)
    context.fillText(node.label, label.x, label.y)
  }

  // The notes badges, over every mark and label, each on a ring of the
  // canvas's ground, at its node's strength.
  for (const index of badged) {
    context.globalAlpha = dimmed(index) ? DIM : 1
    drawNotes(context, theme, nodes[index], x(index), y(index), radii[index])
  }

  // Rings, over everything: the focus's, the hovered node's, the selection's.
  // The selection's own ring says more than the hover's, so a node that is
  // both gets the one.
  context.globalAlpha = 1
  const shown = (index) => index != null && index >= 0 && visibleNodes.includes(index)
  const ring = (index, distance) => {
    const box = boxOf(nodes[index])
    const reach = radii[index] + distance
    context.beginPath()
    if (nodes[index].kind === "tag") context.rect(x(index) - reach, y(index) - reach, reach * 2, reach * 2)
    // The pill's ring is a pill: its ends are half circles, and a square box
    // round it read as a second border. A plain box where the canvas cannot
    // draw a rounded one (`drawNotes` says why that is asked first).
    else if (nodes[index].kind === "more" && typeof context.roundRect === "function") context.roundRect(x(index) - box.width / 2 - distance, y(index) - box.height / 2 - distance, box.width + distance * 2, box.height + distance * 2, box.height / 2 + distance)
    else if (box) context.rect(x(index) - box.width / 2 - distance, y(index) - box.height / 2 - distance, box.width + distance * 2, box.height + distance * 2)
    else context.arc(x(index), y(index), reach, 0, Math.PI * 2)
    context.stroke()
  }
  if (shown(focusIndex) && focusIndex !== selected) {
    context.strokeStyle = theme.accent
    context.lineWidth = 1.5
    context.setLineDash([ 2, 3 ])
    ring(focusIndex, FOCUS_RING)
  }
  context.setLineDash([])
  if (shown(hovered) && hovered !== selected) {
    context.strokeStyle = theme.ink
    context.lineWidth = 1
    ring(hovered, HOVER_RING)
  }
  if (shown(selected)) {
    context.strokeStyle = theme.accent
    context.lineWidth = 2
    ring(selected, SELECTED_RING)
  }
}

// A small ink dot with a surface ring, at the mark's top-right (`corner`,
// from `topCorner`): "this node stays where it was put". The legend's
// "Pinned" swatch is the same mark.
function drawPin(context, theme, x, y, corner) {
  context.beginPath()
  context.arc(x + corner.x, y - corner.y, 3, 0, Math.PI * 2)
  context.setLineDash([])
  context.fillStyle = theme.ink
  context.fill()
  context.strokeStyle = theme.surface
  context.lineWidth = 1.5
  context.stroke()
}

// A neutral pill, like the count badges of the lists: surface, a line, ink
// (handoff: `bg-surface border-line-strong text-ink`), whatever the viewer
// has read. Never the only cue: the node's card says the count in words.
// More than ninety-nine reads "99+". It stands on a ring of the canvas's
// ground (`NOTES_RING`), which is what lets it cover a neighbour cleanly.
//
// THE RIGHT EDGE IS FIXED and the pill grows to the left (`marks.js`): the
// pin's dot is at the top-right, and a pill centred on the corner covered
// half of it at two digits and all of it at "99+" on a small mark. `save`
// and `restore` keep the node's own strength (`globalAlpha`) and leave the
// text settings as the labels expect them.
function drawNotes(context, theme, node, x, y, radius) {
  const label = notesLabel(node)
  const { right, top, half } = notesPill(node, x, y, radius)
  // A pill where the canvas can draw one; a plain rectangle where it can't
  // (`roundRect` is newer than the rest of what is drawn here): a missing
  // method would throw inside the draw and take the whole canvas with it,
  // for every graph that has a note on any post.
  const pill = (inset) => {
    context.beginPath()
    const left = right - half * 2 - inset, width = half * 2 + inset * 2, height = NOTES_BADGE * 2 + inset * 2
    if (typeof context.roundRect === "function") context.roundRect(left, top - inset, width, height, NOTES_BADGE + inset)
    else context.rect(left, top - inset, width, height)
  }
  context.save()
  context.setLineDash([])
  pill(NOTES_RING)
  context.fillStyle = theme.surface
  context.fill()
  pill(0)
  context.fill()
  context.strokeStyle = theme.line
  context.lineWidth = 1
  context.stroke()
  context.font = theme.countFont
  context.textAlign = "center"
  context.textBaseline = "middle"
  context.fillStyle = theme.ink
  context.fillText(label, right - half, top + NOTES_BADGE + 0.5)
  context.restore()
}
