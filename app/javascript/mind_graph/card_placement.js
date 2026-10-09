// Where the selection card stands (mind graph canvas spec §5.3): BESIDE its
// node, so the eye does not travel from the mark to a corner of the box.
//
// - Right of the node, GAP pixels from its edge, vertically centred on it.
// - Where that would run past the canvas's right edge it FLIPS to the node's
//   left, the same distance away.
// - Then it is clamped into the canvas, MARGIN pixels from every edge: near
//   the top or bottom it slides along the node instead of leaving the box,
//   and a card wider than the room on either side still shows whole.
//
// Pure numbers, in canvas pixels: `x`, `y` the node's centre on screen,
// `radius` its mark's, `cardWidth` / `cardHeight` the card as measured,
// `width` / `height` the canvas. Answers `{ left, top, side }`, `side` being
// "right" or "left" of the node. A node with no place (`x` not a number: the
// layout never ran) gets the card in the canvas's top-right corner, where it
// stood before it followed its node.
export const GAP = 22
export const MARGIN = 8

const clamp = (value, low, high) => Math.max(low, Math.min(high, value))

export function placeCard({ x, y, radius, cardWidth, cardHeight, width, height }) {
  const farthestLeft = Math.max(MARGIN, width - cardWidth - MARGIN)
  const farthestTop = Math.max(MARGIN, height - cardHeight - MARGIN)
  if (!Number.isFinite(x) || !Number.isFinite(y)) return { left: farthestLeft, top: MARGIN, side: "right" }

  const right = x + radius + GAP
  const fits = right + cardWidth <= width - MARGIN
  const left = fits ? right : x - radius - GAP - cardWidth
  return { left: clamp(left, MARGIN, farthestLeft), top: clamp(y - cardHeight / 2, MARGIN, farthestTop), side: fits ? "right" : "left" }
}
