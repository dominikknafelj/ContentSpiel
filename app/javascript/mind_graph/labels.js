// Which labels the mind graph shows (mind graph canvas spec §5.2). Three rules:
//
// 1. HUBS FIRST, AMONG THE NODES ON THE CANVAS. `order` is the visible nodes,
//    best-connected first, and the zoom decides how far down that list labels
//    reach: LABEL_BUDGET of them at zoom 1, growing with the square of the zoom
//    (four times the area on screen per node, four times the labels). Only a
//    node on the canvas has a rank: one outside neither gets a label nor uses
//    up a place, so zoomed into a corner the budget goes to what can be seen.
//    The last quarter of that reach fades -- strictly, from just below full
//    strength to just above none -- so a label arrives gradually as you zoom in.
// 2. NO OVERLAP. A label is placed only where no label placed before it is;
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
//
// A node outside the canvas gets no label. Answers `{ index, alpha, x, y }`,
// `x`/`y` the label's left edge and vertical middle in screen pixels: right
// of the node, as the SVG graph drew it.
export const LABEL_BUDGET = 40

const GAP = 4
const HEIGHT = 14

export function chooseLabels({ order, positions, widths, radii, camera, width, height, always }) {
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
    if (placed.some((other) => box.left < other.right && box.right > other.left && box.top < other.bottom && box.bottom > other.top)) return

    placed.push(box)
    labels.push({ index, alpha, x: box.left, y: sy })
  }

  const shown = new Set(order)
  for (const index of always) if (shown.has(index) && onCanvas(index)) place(index, 1)

  let rank = 0
  for (const index of order) {
    if (rank >= reach) break
    if (!onCanvas(index)) continue
    const alpha = rank < fadeFrom ? 1 : 1 - (rank - fadeFrom + 1) / (reach - fadeFrom + 1)
    rank += 1
    if (!always.has(index)) place(index, alpha)
  }
  return labels
}
