// Every mark of the mind graph and its size (mind graph canvas spec §5.1;
// pages in the mind graph, spec §4, whose values are the design answer's --
// its later parts where they replace the earlier ones).
// Everything is in SCREEN pixels, the same at every zoom.
//
// THE KINDS, each a shape of its own so none is told by colour alone:
// - a POST is a dot filled with its type's hue (colour slots 1-6). A RING
//   TYPE (7-12; 13+ cycle) is the same mark, smaller, inside a thin ring of
//   the hue; a post of a type that is no longer registered is a ring type
//   in `meta` with a stroke through it;
// - a PAGE is a small card, 14 by 10 with the card's corner radius, Home 18
//   by 13, in neutral ink (the hues mean post types). Fixed: a page's size
//   does not follow its connections;
// - a POST TYPE a page lists is a hub: a 12px circle in the type's hue with a
//   surface ring inside it, so it is not one more post. "All posts" is the
//   same, filled in `dim`. A RING TYPE's hub is a ring in the hue round a
//   filled centre; a RETIRED type's is a DASHED ring in `dim` round a small
//   `dim` centre: it differs from "All posts" by fill, not by shade, and
//   from a ring type's hub by its dashes. A hub has no state;
// - a TAG is a square; "+N more" is a pill with its words inside it.
//
// THE STATE is one table, `LOOKS`, which a page, a post and a ring type's
// inner mark all read (spec §4; never worked out here: `status` and
// `changes` are `Publishing::State`'s, from the data). A draft is DASHED on
// every mark, so no state rests on colour alone. The corners are then:
// notes top-left, pin top-right (`renderer.js`), changes bottom-right.
//
// A MARK'S SIZE IS ITS OUTER SIZE (the ruling on this task's review): an
// outline is drawn INSIDE the mark's edge, so an outlined mark is exactly as
// large as a filled one -- a draft page is 14 by 10, a ring type's hub and a
// retired hub 12px across, a ring post's ring ends at its radius, the pill
// is 60 by 16 with its border in it. `inside` below traces the path such a
// stroke is centred on. Two marks are older than that rule and are left as
// they were: a live filled post's own outline in its hue and a tag's
// square are centred on the edge.
//
// Nothing here is a colour: every one comes in with `theme` (`theme.js`),
// and a value of the table is a theme KEY.

// Up to this many connections: a post's radius, a tag's half side. The
// posts' are the sizes of the design review's mock (2026-10-08).
const STEPS = [ [ 2, 7, 4.5 ], [ 5, 10, 6 ], [ 12, 13, 8.25 ], [ Infinity, 16, 10.5 ] ]
const PAGE_BOX = { width: 14, height: 10 }
const HOME_BOX = { width: 18, height: 13 }
// "+N more" (design answers G2, H4): a pill that grows to fit its words,
// 8px each side, and is never narrower than 60.
const MORE_HEIGHT = 16
const MORE_MIN_WIDTH = 60
const MORE_PADDING = 8
const TYPE_RADIUS = 6
// The hub's inner ring (G3): 1.5px wide with its outer edge 1.5px inside
// the hub's radius, so from 3 to 4.5: a stroke centred on 3.75.
const TYPE_RING = { radius: 3.75, width: 1.5 }
// A ring type's hub (H3): a ring in the hue round "a filled 6px centre".
// A READING: 6px ACROSS (a centre of radius 6 would be the whole hub).
const RING_HUB_CENTRE = 3
// A scheduled record's centre dot, 4px across (G3), and a retired hub's (G1).
const CENTRE_DOT = 2
// The corner dot (G3): 5px across, its centre 1px in from the mark's
// bottom-right corner (on the 45 degree line for a circle), with a 1.5px
// surface ring. A READING for a ring type (H3: "on the outer ring, at the
// 45 degree point"): the outer ring's corner by the same rule, 1px in.
const CORNER_DOT = 2.5
const CORNER_INSET = 1
const CORNER_RING = 1.5
// Every outline here: a draft's, a scheduled record's, a ring type's ring.
const OUTLINE = 1.5
// The pill's border (G2).
const MORE_BORDER = 1
// A READING of "dashed": the dash a draft has had since the first build.
const DRAFT_DASH = [ 3, 2.5 ]
// How far along its radius a circle's top corners are, for what hangs on
// them (the pin, the notes badge) and for a retired type's stroke.
const CIRCLE_CORNER = 0.72

// A ring type's inner mark (G3, H3): 4/7 of the outer radius at every size,
// rounded to the nearest half pixel: 4 in 7, 5.5 in 10, 7.5 in 13, 9 in 16.
const innerRadius = (radius) => Math.round((radius * 4 / 7) * 2) / 2

// THE FIVE LOOKS (the design answer's status table with the third answers'
// correction: WARN MEANS "SCHEDULED", as on CS Studio's status chip). One
// row per state; each mark that has a state draws its row and nothing else:
//   fill     "own" (the mark's colour: ink for a page, the type's hue for a
//            post) or a theme key
//   outline  a theme key, or none; `dashed` with the draft's dash
//   centre   the colour of a 4px dot in the mark's middle, or none
//   corner   the colour of the 5px dot at the mark's bottom-right, or none
//
//   live                       filled
//   draft                      a DASHED outline, 1.5px `meta`, surface inside
//   scheduled                  an outline in `dim`, with a `warn` centre dot
//   live with changes          filled, with a `dim` dot at the bottom right
//   live, a change scheduled   filled, with a `warn` dot at the bottom right
export const LOOKS = {
  live: { fill: "own", outline: null, dashed: false, centre: null, corner: null },
  draft: { fill: "surface", outline: "meta", dashed: true, centre: null, corner: null },
  scheduled: { fill: "surface", outline: "dim", dashed: false, centre: "warn", corner: null },
  unpublished: { fill: "own", outline: null, dashed: false, centre: null, corner: "dim" },
  change_scheduled: { fill: "own", outline: null, dashed: false, centre: null, corner: "warn" }
}

// Which row a node is in. `changes` is a LIVE record's second state
// (`Publishing::State`): a draft's or a scheduled record's is not read. A
// status this table does not know is drawn live, not left undrawn.
export function lookOf(node) {
  if (node.status === "draft" || node.status === "scheduled") return node.status
  return node.changes === "scheduled" ? "change_scheduled" : node.changes === "unpublished" ? "unpublished" : "live"
}

// A pill's width for its words as the canvas measures them (`app.js` writes
// the answer on the node as `width`): a whole number of pixels.
export const moreWidth = (wordsWidth) => Math.max(MORE_MIN_WIDTH, Math.ceil(wordsWidth) + MORE_PADDING * 2)

// A page's card and the pill are boxes; nothing else is.
export const boxOf = (node) =>
  node.kind === "page" ? (node.home ? HOME_BOX : PAGE_BOX) : node.kind === "more" ? { width: node.width ?? MORE_MIN_WIDTH, height: MORE_HEIGHT } : null

// Four sizes by degree for a post and a tag: small differences in size can't
// be read, so a hub is one of four steps, not a point on a scale. A box's
// is half its width (its label starts beside it), a type hub's is fixed.
export function radiusFor(node) {
  const box = boxOf(node)
  if (box) return box.width / 2
  if (node.kind === "type") return TYPE_RADIUS
  const [ , post, tag ] = STEPS.find(([ upTo ]) => (node.degree ?? 0) <= upTo)
  return node.kind === "tag" ? tag : post
}

// What the layout keeps clear around a node: a box's is half its diagonal.
export function collisionRadius(node) {
  const box = boxOf(node)
  return box ? Math.hypot(box.width, box.height) / 2 : radiusFor(node)
}

// How far right of and above its centre a mark's top-right corner is (the
// top-left one is its mirror): a box's own corner, a circle's and a tag's
// a little outside the 45 degree point, as the pin has always stood.
export function topCorner(node, radius) {
  const box = boxOf(node)
  return box ? { x: box.width / 2, y: box.height / 2 } : { x: radius * CIRCLE_CORNER, y: radius * CIRCLE_CORNER }
}

export function drawMark(context, theme, node, x, y, radius) {
  context.setLineDash([])
  if (node.kind === "tag") return drawTag(context, theme, x, y, radius)
  if (node.kind === "type") return drawType(context, theme, node, x, y)
  if (node.kind === "more") return drawMore(context, theme, node, x, y)

  const look = LOOKS[lookOf(node)]
  if (node.kind === "page") drawPage(context, theme, node, look, x, y)
  else drawPost(context, theme, node, look, x, y, radius)
  if (!look.corner) return

  // The corner dot, on the WHOLE mark's corner (a ring type's is the outer
  // ring's). Its surface ring is a disk under it.
  const box = boxOf(node)
  const reach = (radius - CORNER_INSET) * Math.SQRT1_2
  const cornerX = box ? x + box.width / 2 - CORNER_INSET : x + reach
  const cornerY = box ? y + box.height / 2 - CORNER_INSET : y + reach
  dot(context, theme.surface, cornerX, cornerY, CORNER_DOT + CORNER_RING)
  dot(context, theme[look.corner], cornerX, cornerY, CORNER_DOT)
}

// A mark's shape, centred on x, y: `{ radius }` for a circle, `{ width,
// height, corner }` for a box. `trace` opens its path, `inset` pixels inside
// its edge all round; a stroke of width w on `trace(…, w / 2)` lies wholly
// inside the shape.
function trace(context, shape, x, y, inset = 0) {
  context.beginPath()
  if (shape.radius != null) return context.arc(x, y, Math.max(0, shape.radius - inset), 0, Math.PI * 2)

  const width = shape.width - inset * 2, height = shape.height - inset * 2
  // A rounded box where the canvas can round one; a plain rectangle where
  // it can't (`roundRect` is newer than the rest of what is drawn here, and
  // a missing method would throw inside the draw and take the canvas with it).
  if (typeof context.roundRect === "function") context.roundRect(x - width / 2, y - height / 2, width, height, Math.max(0, (shape.corner ?? 0) - inset))
  else context.rect(x - width / 2, y - height / 2, width, height)
}

// Strokes the path that is open, and leaves no dash behind.
function stroke(context, colour, { dashed = false, width = OUTLINE } = {}) {
  context.strokeStyle = colour
  context.lineWidth = width
  context.setLineDash(dashed ? DRAFT_DASH : [])
  context.stroke()
  context.setLineDash([])
}

// An outline of the shape, INSIDE its edge.
function outline(context, colour, shape, x, y, options = {}) {
  trace(context, shape, x, y, (options.width ?? OUTLINE) / 2)
  stroke(context, colour, options)
}

function fill(context, colour) {
  context.fillStyle = colour
  context.fill()
}

function dot(context, colour, x, y, radius) {
  trace(context, { radius }, x, y)
  fill(context, colour)
}

// A row of `LOOKS` on a shape centred on x, y: the fill, the outline inside
// its edge and the centre dot. (The corner dot is the whole mark's,
// `drawMark`'s.) `own` is the mark's own colour, and `edged` a filled
// post's own outline in its hue, centred on its edge as it has always been
// (drawn on the path the fill left open).
function state(context, theme, look, own, shape, x, y, { edged = false } = {}) {
  trace(context, shape, x, y)
  fill(context, look.fill === "own" ? own : theme[look.fill])
  if (edged && look.fill === "own") stroke(context, own)
  if (look.outline) outline(context, theme[look.outline], shape, x, y, { dashed: look.dashed })
  if (look.centre) dot(context, theme[look.centre], x, y, CENTRE_DOT)
}

function drawPage(context, theme, node, look, x, y) {
  state(context, theme, look, theme.ink, { ...boxOf(node), corner: theme.radius ?? 0 }, x, y)
}

function drawPost(context, theme, node, look, x, y, radius) {
  const retired = node.colour_index == null
  const slot = retired ? null : (node.colour_index - 1) % 12
  const hue = retired ? theme.meta : theme.categories[slot % 6]

  if (retired || slot >= 6) {
    // A ring type (third design answers; H3): the ring, thin and ALWAYS
    // solid, ending at the mark's radius, and inside it the type's mark in
    // whichever of the five looks.
    trace(context, { radius }, x, y)
    fill(context, theme.surface)
    outline(context, hue, { radius }, x, y)
    state(context, theme, look, hue, { radius: innerRadius(radius) }, x, y)
  } else {
    state(context, theme, look, hue, { radius }, x, y, { edged: true })
  }
  if (!retired) return

  const reach = radius * CIRCLE_CORNER
  context.beginPath()
  context.moveTo(x - reach, y + reach)
  context.lineTo(x + reach, y - reach)
  stroke(context, hue)
}

function drawType(context, theme, node, x, y) {
  const retired = node.id !== "all-posts" && node.colour_index == null
  const slot = node.colour_index == null ? null : (node.colour_index - 1) % 12
  const hub = { radius: TYPE_RADIUS }
  // A RING TYPE's hub (slots 7-12; design answer H3) is not filled: a ring
  // in the hue round a filled centre. A RETIRED type's (G1, H3) is the same
  // shape in `dim` with a DASHED ring and a smaller centre, so the two
  // differ by more than colour; and "All posts" is FILLED in `dim`, so it
  // differs from a retired hub by fill, not by shade. Either ring is inside
  // the hub's 12px, like every outline.
  if (retired || slot >= 6) {
    const hue = retired ? theme.dim : theme.categories[slot % 6]
    trace(context, hub, x, y)
    fill(context, theme.surface)
    outline(context, hue, hub, x, y, { dashed: retired })
    return dot(context, hue, x, y, retired ? CENTRE_DOT : RING_HUB_CENTRE)
  }

  dot(context, node.id === "all-posts" ? theme.dim : theme.categories[slot], x, y, TYPE_RADIUS)
  // The inner ring is given by its edges (3 to 4.5), not by a shape's.
  trace(context, { radius: TYPE_RING.radius }, x, y)
  stroke(context, theme.surface, { width: TYPE_RING.width })
}

// "+N more" (design answers G2, H4): a pill on surface with a strong line
// round it (inside its 16px) and its words inside, in the small mono style
// the notes badge has. `save` and `restore` leave the text settings as the
// labels expect them.
function drawMore(context, theme, node, x, y) {
  const box = boxOf(node)
  const pill = { ...box, corner: box.height / 2 }
  context.save()
  trace(context, pill, x, y)
  fill(context, theme.surface)
  outline(context, theme.line, pill, x, y, { width: MORE_BORDER })
  context.font = theme.countFont
  context.textAlign = "center"
  context.textBaseline = "middle"
  context.fillStyle = theme.dim
  context.fillText(node.title, x, y)
  context.restore()
}

function drawTag(context, theme, x, y, half) {
  context.fillStyle = theme.surface
  context.strokeStyle = theme.meta
  context.lineWidth = OUTLINE
  context.fillRect(x - half, y - half, half * 2, half * 2)
  context.strokeRect(x - half, y - half, half * 2, half * 2)
}
