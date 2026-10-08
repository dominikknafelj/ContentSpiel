// Which labels the mind graph shows (mind graph canvas spec §5.2). Three rules:
//
// 1. HUBS FIRST. `order` is the visible nodes, best-connected first, and the
//    zoom decides how far down that list labels reach: LABEL_BUDGET of them at
//    zoom 1, growing with the square of the zoom (four times the area on
//    screen per node, four times the labels). The last quarter of that reach
//    fades, so a label arrives gradually as you zoom in.
// 2. NO OVERLAP. A label is placed only where no label placed before it is;
//    better-connected nodes place first, so the hub wins.
// 3. `always` -- the selection, its neighbours, the focus -- is labelled at
//    any zoom, at full strength, and places before everything else.
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

  const place = (index, alpha) => {
    const sx = positions[index * 2] * camera.k + camera.tx
    const sy = positions[index * 2 + 1] * camera.k + camera.ty
    if (sx < 0 || sy < 0 || sx > width || sy > height) return

    const box = { left: sx + radii[index] + GAP, top: sy - HEIGHT / 2, right: sx + radii[index] + GAP + widths[index], bottom: sy + HEIGHT / 2 }
    if (placed.some((other) => box.left < other.right && box.right > other.left && box.top < other.bottom && box.bottom > other.top)) return

    placed.push(box)
    labels.push({ index, alpha, x: box.left, y: sy })
  }

  for (const index of order) if (always.has(index)) place(index, 1)

  let rank = 0
  for (const index of order) {
    if (rank >= reach) break
    const alpha = rank < fadeFrom ? 1 : 1 - (rank - fadeFrom) / (reach - fadeFrom)
    rank += 1
    if (!always.has(index) && alpha > 0) place(index, alpha)
  }
  return labels
}
