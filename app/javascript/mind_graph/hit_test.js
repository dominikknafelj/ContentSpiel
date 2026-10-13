// The node under a screen point (mind graph canvas spec §4.1, §5.3). A node's
// DOT AND ITS LABEL ARE ONE TARGET: a press on the title is a press on the
// node, as a person expects of a name written beside a mark.
//
// The dot. A node's radius is in SCREEN pixels -- nodes are drawn the same size
// at every zoom -- so the camera moves the centres only. A small dot would be
// hard to hit, so its target is its radius plus `slack`, and never less than
// MIN_TARGET pixels across, at any zoom.
//
// WHAT IS DRAWN COMES FIRST. A press INSIDE a mark -- within a dot's radius,
// on a box -- is a press on that mark, whatever other target reaches the
// point with its slack: a pill is 60 pixels wide or more, so its drawn end is
// 30 from its centre, and a post resting against it would otherwise take, by
// its nearer centre, a press that is on the pill's words. The nearer centre
// decides only among the marks that hold the point (two that overlap), or,
// where none holds it, among the targets that reach it. A BOX (a page's card, the "+N more" pill: `boxes`, from `marks.js`'s
// `boxOf`) is pressed on the box itself, grown by the same slack and never
// less than MIN_TARGET either way: the pill is 60 wide and 16 high, and a
// circle as wide as it would take every press 25 pixels above and below it.
//
// The label. `labels` is what the last frame DREW (`labels.js`'s answer, plus
// the hovered node's): a label counts only while it is drawn, so nothing
// invisible can be pressed. Its box runs from the node's edge to the end of
// the text (`widths`), LABEL_HEIGHT tall. A dot wins over a label it lies
// under; among labels the LAST drawn wins, because that is the one on top
// (the hovered node's is drawn over the others).
//
// Still a linear scan: at the cap that is 2,000 distance checks and at most a
// few hundred box checks per pointer event, which needs no index.
import { LABEL_GAP, LABEL_HEIGHT } from "mind_graph/labels"

export const MIN_TARGET = 24

// `boxes[index]` is `{ width, height }` for a node that is a box, and
// nothing (null, or no entry at all) for one that is a circle.
export function nodeAt({ positions, indexes, radii, camera, sx, sy, slack = 4, labels = [], widths = [], boxes = [] }) {
  // The nearest centre among the marks that hold the point, and among the
  // targets that reach it.
  let on = -1, onDistance = Infinity
  let near = -1, nearDistance = Infinity
  for (const index of indexes) {
    const dx = Math.abs(positions[index * 2] * camera.k + camera.tx - sx)
    const dy = Math.abs(positions[index * 2 + 1] * camera.k + camera.ty - sy)
    const distance = Math.hypot(dx, dy)
    const box = boxes[index]
    const inside = box ? dx <= box.width / 2 && dy <= box.height / 2 : distance <= radii[index]
    const reached = inside || (box
      ? dx <= Math.max(box.width / 2 + slack, MIN_TARGET / 2) && dy <= Math.max(box.height / 2 + slack, MIN_TARGET / 2)
      : distance <= Math.max(radii[index] + slack, MIN_TARGET / 2))
    if (inside && distance < onDistance) {
      on = index
      onDistance = distance
    }
    if (reached && distance < nearDistance) {
      near = index
      nearDistance = distance
    }
  }
  if (on >= 0) return on
  if (near >= 0) return near

  for (let at = labels.length - 1; at >= 0; at -= 1) {
    const label = labels[at]
    if (sx >= label.x - LABEL_GAP && sx <= label.x + widths[label.index] && Math.abs(sy - label.y) <= LABEL_HEIGHT / 2) return label.index
  }
  return -1
}
