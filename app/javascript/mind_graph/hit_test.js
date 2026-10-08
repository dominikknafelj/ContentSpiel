// The node under a screen point (mind graph canvas spec §4.1). A linear scan
// over the visible nodes: at the cap that is 2,000 distance checks per pointer
// event, which needs no index. A node's radius is in SCREEN pixels -- nodes
// are drawn the same size at every zoom -- so the camera moves the centres
// only. `slack` makes a small dot easier to hit. Where two overlap, the
// nearer centre wins.
export function nodeAt({ positions, indexes, radii, camera, sx, sy, slack = 4 }) {
  let best = -1
  let bestDistance = Infinity
  for (const index of indexes) {
    const dx = positions[index * 2] * camera.k + camera.tx - sx
    const dy = positions[index * 2 + 1] * camera.k + camera.ty - sy
    const distance = Math.hypot(dx, dy)
    if (distance <= radii[index] + slack && distance < bestDistance) {
      best = index
      bestDistance = distance
    }
  }
  return best
}
