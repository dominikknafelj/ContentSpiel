// The mind graph's camera (mind graph canvas spec §4.4): where the graph sits
// on the canvas. A plain object `{ k, tx, ty }` -- screen = graph * k + t --
// and pure functions that answer a new one, so a zoom or a pan is a value the
// redraw compares, and all of it can be checked without a canvas.
const MIN_ZOOM = 0.05
const MAX_ZOOM = 4
// "Fit all" never zooms a small graph in further than this: three nodes
// stretched over the whole box would be drawn as three huge gaps.
const MAX_FIT_ZOOM = 1.5

const clamp = (value, low, high) => Math.max(low, Math.min(high, value))

export function identity() {
  return { k: 1, tx: 0, ty: 0 }
}

export function toScreen(camera, x, y) {
  return [ x * camera.k + camera.tx, y * camera.k + camera.ty ]
}

export function toGraph(camera, sx, sy) {
  return [ (sx - camera.tx) / camera.k, (sy - camera.ty) / camera.k ]
}

// Zooms by `factor` around the screen point (sx, sy): what is under the
// pointer stays under it.
export function zoomAt(camera, sx, sy, factor) {
  const k = clamp(camera.k * factor, MIN_ZOOM, MAX_ZOOM)
  const ratio = k / camera.k
  return { k, tx: sx - (sx - camera.tx) * ratio, ty: sy - (sy - camera.ty) * ratio }
}

export function panBy(camera, dx, dy) {
  return { k: camera.k, tx: camera.tx + dx, ty: camera.ty + dy }
}

// The box around the nodes at `indexes`; null when there are none. A node
// whose position is not a finite number (not laid out yet) is skipped, so the
// box -- and the camera fitted to it -- is never NaN.
export function bounds(positions, indexes) {
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
  for (const index of indexes) {
    const x = positions[index * 2], y = positions[index * 2 + 1]
    if (!Number.isFinite(x) || !Number.isFinite(y)) continue
    if (x < minX) minX = x
    if (x > maxX) maxX = x
    if (y < minY) minY = y
    if (y > maxY) maxY = y
  }
  return minX === Infinity ? null : { minX, minY, maxX, maxY }
}

// The camera that shows the whole box with `padding` pixels around it, its
// middle in the middle of the canvas. A box with no extent (one node, or
// every node at one point) has nothing to scale by: it is centred at the
// largest fit zoom.
export function fit(box, width, height, padding = 40) {
  if (!box) return { k: 1, tx: width / 2, ty: height / 2 }

  const spanX = box.maxX - box.minX
  const spanY = box.maxY - box.minY
  const roomX = Math.max(width - padding * 2, 1)
  const roomY = Math.max(height - padding * 2, 1)
  const k = clamp(Math.min(spanX > 0 ? roomX / spanX : Infinity, spanY > 0 ? roomY / spanY : Infinity), MIN_ZOOM, MAX_FIT_ZOOM)
  return { k, tx: width / 2 - ((box.minX + box.maxX) / 2) * k, ty: height / 2 - ((box.minY + box.maxY) / 2) * k }
}
