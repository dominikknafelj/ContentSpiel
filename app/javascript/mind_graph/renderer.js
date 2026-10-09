// Draws one frame of the mind graph (mind graph canvas spec §4.3, §5.1).
// Order: edges, nodes (each with its pin mark and its notes badge), labels, rings. Everything is in SCREEN pixels: the
// camera moves a node's centre, and a node is the same size at every zoom.
//
// A node's mark carries two cues that never share a shape, exactly as
// `Admin::ContentTypeDotComponent` and the legend draw them:
// - the TYPE is the fill: colour slots 1-6 are filled with the hue, 7-12 are a
//   ring of the same six hues (13+ cycle);
// - the STATUS is the outline: a live post's is solid, a draft's or a
//   scheduled post's dashed -- with a small filled core for slots 1-6, so the
//   hue is still there;
// - a post whose type is no longer registered (no `colour_index`) is a ring in
//   the `meta` grey WITH A STROKE THROUGH IT, so it differs from a 7-12 ring
//   by shape, not by colour alone.
// A tag is a square. A related edge is solid, a shared tag's dashed.
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
// - SELECTED: a 2px accent ring with a gap, a semibold label, its edges
//   brightened, and every node and edge not connected to it at DIM.
// - PINNED (`pinned`, a Set of indexes): a small ink dot with a surface ring
//   at the mark's top-right. It is drawn with the node, at the node's
//   strength, whatever else the node is.
// - WITH OPEN NOTES (`open_notes` above zero, a post only; notes spec §4.4):
//   the count in a small mono badge at the mark's top-LEFT, opposite the pin,
//   so a node can carry both. Not a ring: a ring means hovered, selected or
//   focused. Drawn with the node, at the node's strength, and the same size at
//   every zoom. Neutral, and in the accent tint with accent ink while those
//   notes hold something unread for the viewer (`unread_notes`), the one
//   meaning accent has in notes (§4.5).
// - The focus of a local view: a dotted accent ring.
// A tag's rings are squares, like its mark.
//
// Nothing here is a colour: every one comes in with `theme` (`theme.js`), and
// what dims is dimmed by `globalAlpha`.
// Up to this many connections: a post's radius, a tag's half side. The
// posts' are the sizes of the design review's mock (2026-10-08), which draws
// its dots a step larger than the first build did (6, 8, 11, 14).
const STEPS = [ [ 2, 7, 4.5 ], [ 5, 10, 6 ], [ 12, 13, 8.25 ], [ Infinity, 16, 10.5 ] ]
const DIM = 0.28
// The width of the surface-coloured outline under a label, which keeps a title
// readable where it crosses an edge.
const LABEL_HALO = 3
// The backing of the hovered node's label: how far it reaches beyond the text.
const BACKING_X = 4
const BACKING_HEIGHT = 18
// How far outside the canvas an edge's end or a node's edge may be and still
// count as on it: half the widest stroke, rounded up, and a node's rings and
// its notes badge (which reaches furthest on the smallest mark: "99+" on a
// 7px dot ends 13px beyond its edge).
const EDGE_MARGIN = 2
const NODE_MARGIN = 13
// A ring's distance from the mark's edge.
const HOVER_RING = 2.5
const SELECTED_RING = 4
const FOCUS_RING = 5
// A post with open notes (notes spec §4.4, handoff "Mind graph node badge"):
// the count in a small pill on the mark's top-left corner. Half its height
// (the handoff's 14px line), half a character's advance at 10px mono, and the
// room beside the text (`px-1`).
const NOTES_BADGE = 7
const NOTES_CHARACTER = 3
const NOTES_BADGE_PAD = 4

// Four sizes by degree: small differences in size can't be read, so a hub is
// one of four steps, not a point on a scale. A tag's is its half side.
export function radiusFor(node) {
  const [ , post, tag ] = STEPS.find(([ upTo ]) => node.degree <= upTo)
  return node.kind === "tag" ? tag : post
}

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

  // One path per kind and strength, so a few thousand edges are four strokes.
  // With a selection, the edges that touch it are the bright pass and the
  // rest the faded one; with none, every edge is the plain pass.
  for (const kind of [ "tag", "related" ]) {
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
      context.globalAlpha = bright ? 0.9 : (kind === "tag" ? 0.8 : 0.35) * (pass === "faded" ? DIM : 1)
      context.strokeStyle = kind === "tag" && !bright ? theme.meta : theme.ink
      context.lineWidth = (kind === "tag" ? 1 : 1.5) + (bright ? 0.5 : 0)
      context.setLineDash(kind === "tag" ? [ 4, 3 ] : [])
      context.stroke()
    }
  }
  context.setLineDash([])

  for (const index of visibleNodes) {
    if (beyond(x(index), y(index), radii[index] + NODE_MARGIN)) continue
    context.globalAlpha = dimmed(index) ? DIM : 1
    if (nodes[index].kind === "tag") drawTag(context, theme, x(index), y(index), radii[index])
    else drawPost(context, theme, nodes[index], x(index), y(index), radii[index])
    if (pinned.has(index)) drawPin(context, theme, x(index), y(index), radii[index])
    if (nodes[index].kind !== "tag" && (nodes[index].open_notes ?? 0) > 0) drawNotes(context, theme, nodes[index], x(index), y(index), radii[index])
  }

  context.textBaseline = "middle"
  context.lineJoin = "round"
  for (const label of labels) {
    const node = nodes[label.index]
    context.font = label.index === selected ? theme.strongFont : theme.font
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
    context.fillStyle = node.kind === "tag" ? theme.meta : theme.ink
    context.strokeText(node.label, label.x, label.y)
    context.fillText(node.label, label.x, label.y)
  }

  // Rings, over everything: the focus's, the hovered node's, the selection's.
  // The selection's own ring says more than the hover's, so a node that is
  // both gets the one.
  context.globalAlpha = 1
  const shown = (index) => index != null && index >= 0 && visibleNodes.includes(index)
  const ring = (index, distance) => {
    const reach = radii[index] + distance
    context.beginPath()
    if (nodes[index].kind === "tag") context.rect(x(index) - reach, y(index) - reach, reach * 2, reach * 2)
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

// A small ink dot with a surface ring, at the mark's top-right: "this node
// stays where it was put". The legend's "Pinned" swatch is the same mark.
function drawPin(context, theme, x, y, radius) {
  const offset = radius * 0.72
  context.beginPath()
  context.arc(x + offset, y - offset, 3, 0, Math.PI * 2)
  context.setLineDash([])
  context.fillStyle = theme.ink
  context.fill()
  context.strokeStyle = theme.surface
  context.lineWidth = 1.5
  context.stroke()
}

// A pill like the count badges of the lists: surface, a line, ink -- and the
// accent tint with accent ink while the count holds something unread for the
// viewer, the border kept, as the chip on a media tile. Never the only cue:
// the node's card says the count in words and marks the unread rows. More
// than ninety-nine reads "99+". `save` and `restore` keep the node's own
// strength (`globalAlpha`) and leave the text settings as the labels expect
// them.
function drawNotes(context, theme, node, x, y, radius) {
  const label = node.open_notes > 99 ? "99+" : String(node.open_notes)
  const offset = radius * 0.72
  const half = Math.max(NOTES_BADGE, NOTES_CHARACTER * label.length + NOTES_BADGE_PAD)
  context.save()
  context.setLineDash([])
  context.beginPath()
  context.roundRect(x - offset - half, y - offset - NOTES_BADGE, half * 2, NOTES_BADGE * 2, NOTES_BADGE)
  context.fillStyle = node.unread_notes ? theme.accentTint : theme.surface
  context.fill()
  context.strokeStyle = theme.line
  context.lineWidth = 1
  context.stroke()
  context.font = theme.countFont
  context.textAlign = "center"
  context.textBaseline = "middle"
  context.fillStyle = node.unread_notes ? theme.accent : theme.ink
  context.fillText(label, x - offset, y - offset + 0.5)
  context.restore()
}

function drawTag(context, theme, x, y, half) {
  context.fillStyle = theme.surface
  context.strokeStyle = theme.meta
  context.lineWidth = 1.5
  context.setLineDash([])
  context.fillRect(x - half, y - half, half * 2, half * 2)
  context.strokeRect(x - half, y - half, half * 2, half * 2)
}

function drawPost(context, theme, node, x, y, radius) {
  const retired = node.colour_index == null
  const slot = retired ? null : (node.colour_index - 1) % 12
  const hue = retired ? theme.meta : theme.categories[slot % 6]
  const ring = retired || slot >= 6
  const hollow = node.status !== "live"

  context.beginPath()
  context.arc(x, y, radius, 0, Math.PI * 2)
  context.fillStyle = ring || hollow ? theme.surface : hue
  context.fill()
  context.strokeStyle = hue
  context.lineWidth = ring ? 2.5 : hollow ? 2 : 1.5
  context.setLineDash(hollow ? [ 3, 2.5 ] : [])
  context.stroke()
  context.setLineDash([])

  if (hollow && !ring) {
    context.beginPath()
    context.arc(x, y, radius * 0.4, 0, Math.PI * 2)
    context.fillStyle = hue
    context.fill()
  }
  if (retired) {
    const reach = radius * 0.72
    context.beginPath()
    context.moveTo(x - reach, y + reach)
    context.lineTo(x + reach, y - reach)
    context.lineWidth = 1.5
    context.stroke()
  }
}
