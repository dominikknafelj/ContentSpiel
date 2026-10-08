// Draws one frame of the mind graph (mind graph canvas spec §4.3, §5.1).
// Order: edges, nodes, labels, rings. Everything is in SCREEN pixels: the
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
// Nothing here is a colour: every one comes in with `theme` (`theme.js`), and
// what dims is dimmed by `globalAlpha`.
const STEPS = [ [ 2, 6 ], [ 5, 8 ], [ 12, 11 ], [ Infinity, 14 ] ]
const DIM = 0.18
// The width of the surface-coloured outline under a label, which keeps a title
// readable where it crosses an edge.
const LABEL_HALO = 3

// Four sizes by degree: small differences in size can't be read, so a hub is
// one of four steps, not a point on a scale. A tag's is its half side.
export function radiusFor(node) {
  const radius = STEPS.find(([ upTo ]) => node.degree <= upTo)[1]
  return node.kind === "tag" ? radius * 0.75 : radius
}

// `edges[i].source` / `.target` are node INDEXES (`app.js` converts the ids
// once), `visibleNodes` / `visibleEdges` indexes too. `width` and `height` are
// CSS pixels; the bitmap is `ratio` times that, which the transform takes up.
export function draw(context, { width, height, ratio, camera, theme, nodes, edges, positions, radii, visibleNodes, visibleEdges, labels, selected, neighbours, focusIndex }) {
  context.setTransform(ratio, 0, 0, ratio, 0, 0)
  context.clearRect(0, 0, width, height)

  const x = (index) => positions[index * 2] * camera.k + camera.tx
  const y = (index) => positions[index * 2 + 1] * camera.k + camera.ty
  const dimmed = (index) => selected >= 0 && index !== selected && !neighbours.has(index)

  // One path per kind and strength, so a few thousand edges are four strokes.
  // With a selection, the edges that do not touch it are the faded pass.
  for (const kind of [ "tag", "related" ]) {
    for (const faded of [ true, false ]) {
      context.beginPath()
      for (const edgeIndex of visibleEdges) {
        const edge = edges[edgeIndex]
        if (edge.kind !== kind) continue
        const touchesSelection = selected < 0 || edge.source === selected || edge.target === selected
        if (touchesSelection === faded) continue
        context.moveTo(x(edge.source), y(edge.source))
        context.lineTo(x(edge.target), y(edge.target))
      }
      context.globalAlpha = (kind === "tag" ? 0.8 : 0.35) * (faded ? DIM : 1)
      context.strokeStyle = kind === "tag" ? theme.meta : theme.ink
      context.lineWidth = kind === "tag" ? 1 : 1.5
      context.setLineDash(kind === "tag" ? [ 4, 3 ] : [])
      context.stroke()
    }
  }
  context.setLineDash([])

  for (const index of visibleNodes) {
    context.globalAlpha = dimmed(index) ? DIM : 1
    if (nodes[index].kind === "tag") drawTag(context, theme, x(index), y(index), radii[index])
    else drawPost(context, theme, nodes[index], x(index), y(index), radii[index])
  }

  context.font = theme.font
  context.textBaseline = "middle"
  context.lineJoin = "round"
  context.lineWidth = LABEL_HALO
  context.strokeStyle = theme.surface
  for (const label of labels) {
    context.globalAlpha = label.alpha * (dimmed(label.index) ? DIM : 1)
    context.fillStyle = nodes[label.index].kind === "tag" ? theme.meta : theme.ink
    context.strokeText(nodes[label.index].label, label.x, label.y)
    context.fillText(nodes[label.index].label, label.x, label.y)
  }

  context.globalAlpha = 1
  for (const index of [ focusIndex, selected ]) {
    if (index == null || index < 0 || !visibleNodes.includes(index)) continue
    context.beginPath()
    context.arc(x(index), y(index), radii[index] + 5, 0, Math.PI * 2)
    context.strokeStyle = theme.accent
    context.lineWidth = index === selected ? 2 : 1.5
    context.setLineDash(index === selected ? [] : [ 2, 3 ])
    context.stroke()
  }
  context.setLineDash([])
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
