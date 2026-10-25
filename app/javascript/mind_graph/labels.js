// Which labels the mind graph shows (mind graph canvas spec §5.2). Four rules:
//
// 1. HUBS FIRST, AMONG THE NODES ON THE CANVAS. `order` is the visible nodes,
//    best-connected first, and the zoom decides how far down that list labels
//    reach: LABEL_BUDGET of them at zoom 1, growing with the square of the zoom
//    (four times the area on screen per node, four times the labels). Only a
//    node on the canvas has a rank: one outside neither gets a label nor uses
//    up a place, so zoomed into a corner the budget goes to what can be seen.
//    The last quarter of that reach fades -- strictly, from just below full
//    strength to just above none -- so a label arrives gradually as you zoom in.
// 2. NO OVERLAP. A label is placed only where no label placed before it, and no notes badge, is;
//    better-connected nodes place first, so the hub wins.
// 3. `always` -- the selection, the focus, the selection's neighbours -- is
//    labelled at any zoom, at full strength, and places before everything
//    else. Rule 2 still holds among them: where two of their labels would
//    overlap both can't be shown, and NO OVERLAP WINS. Who keeps the place is
//    the Set's own insertion order, not `order`: `app.js` puts the selected
//    node in first, then the focus, then the neighbours, so the selection is
//    labelled whenever it is on the canvas, and a neighbour gives way to it
//    however well connected it is. A member that is not in `order` (hidden by
//    the filter) or not on the canvas gets no label, like any other node.
// 4. `free` -- Home, the top-level pages and the post-type nodes (pages spec
//    §4; `graph_data.js`, `freeOf`) -- is labelled at any zoom and does NOT
//    count against the budget of rule 1. It places after `always` and before
//    the ranked rest, in the order of `order`, and only a member that is in
//    `order` (the filter shows it). Rule 2 still holds: no overlap wins over
//    "always shown".
//
// A NOTES BADGE is one more box the labels keep clear of (`obstacles`, from
// `badgeBoxes`), by the same test as rule 2: no label, and no notes badge
// (Claude Design, 2026-10-25), covers another. The layout makes no room.
//
// A node outside the canvas gets no label. Answers `{ index, alpha, x, y }`,
// `x`/`y` the label's left edge and vertical middle in screen pixels: a label
// sits right of its node, LABEL_GAP pixels from the node's edge, centred on
// it. `labelAt` answers that place for one node, whatever the rules say of
// it: the hovered node's label is shown even where the ranking hides it.
//
// LABEL_GAP and LABEL_HEIGHT are also the hit test's (`hit_test.js`): a drawn
// label is part of its node's target.
import { notesBadgeBox } from "mind_graph/marks"

const LABEL_BUDGET = 40
export const LABEL_GAP = 4
export const LABEL_HEIGHT = 14

const GAP = LABEL_GAP
const HEIGHT = LABEL_HEIGHT

const overlaps = (box, other) => box.left < other.right && box.right > other.left && box.top < other.bottom && box.bottom > other.top

// The boxes (badge and ring) of the notes badges of `indexes`, in screen
// pixels; a node with none is left out.
export function badgeBoxes({ nodes, indexes, positions, radii, camera }) {
  const boxes = []
  for (const index of indexes) {
    const box = notesBadgeBox(nodes[index], positions[index * 2] * camera.k + camera.tx, positions[index * 2 + 1] * camera.k + camera.ty, radii[index])
    if (box) boxes.push(box)
  }
  return boxes
}

export function labelAt({ index, positions, radii, camera }) {
  const sx = positions[index * 2] * camera.k + camera.tx
  const sy = positions[index * 2 + 1] * camera.k + camera.ty
  return { index, alpha: 1, x: sx + radii[index] + GAP, y: sy }
}

//
// `free` HAS NO DEFAULT, on purpose: a caller that forgot it would name Home
// and the post types only while the budget lasts, and nothing would look
// wrong on a small graph. Without it this throws.
export function chooseLabels({ order, positions, widths, radii, camera, width, height, always, free, obstacles = [] }) {
  const reach = Math.max(1, Math.ceil(LABEL_BUDGET * camera.k * camera.k))
  const fadeFrom = reach * 0.75
  const placed = []
  const labels = []

  const onCanvas = (index) => {
    const sx = positions[index * 2] * camera.k + camera.tx
    const sy = positions[index * 2 + 1] * camera.k + camera.ty
    return sx >= 0 && sy >= 0 && sx <= width && sy <= height
  }

  const place = (index, alpha) => {
    const sx = positions[index * 2] * camera.k + camera.tx
    const sy = positions[index * 2 + 1] * camera.k + camera.ty
    const box = { left: sx + radii[index] + GAP, top: sy - HEIGHT / 2, right: sx + radii[index] + GAP + widths[index], bottom: sy + HEIGHT / 2 }
    if (obstacles.some((other) => overlaps(box, other)) || placed.some((other) => overlaps(box, other))) return

    placed.push(box)
    labels.push({ index, alpha, x: box.left, y: sy })
  }

  const shown = new Set(order)
  for (const index of always) if (shown.has(index) && onCanvas(index)) place(index, 1)

  for (const index of order) if (free.has(index) && !always.has(index) && onCanvas(index)) place(index, 1)

  let rank = 0
  for (const index of order) {
    if (rank >= reach) break
    if (free.has(index) || !onCanvas(index)) continue
    const alpha = rank < fadeFrom ? 1 : 1 - (rank - fadeFrom + 1) / (reach - fadeFrom + 1)
    rank += 1
    if (!always.has(index)) place(index, alpha)
  }
  return labels
}
