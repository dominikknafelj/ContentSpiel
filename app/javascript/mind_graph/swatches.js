// The legend's and the Status key's swatches (pages in the mind graph, spec
// §6): each is a small canvas, and what is on it is drawn by THE RENDERER
// THE GRAPH IS DRAWN BY (`renderer.js`, and through it `marks.js`), from a
// scene of one node or one line. So a swatch is not a copy of a mark in CSS
// or SVG that could drift from it: change a look in `marks.js`'s `LOOKS`, a
// size, a line's dash in `LINE_STYLES`, and the key changes with the canvas.
//
// A SCENE is what the renderer is handed, by the swatch's name
// (`Admin::MindGraphScreen::SwatchComponent::SIZES` holds the same names
// with each one's size in the page, and a test holds the two lists equal):
//   node     the one node, as the data would hold it; it stands in the
//            middle of the swatch unless `at` says where (the notes badge
//            hangs off its corner, so that mark stands low and to the right)
//   line     the kind of the one line, drawn across the swatch's width
//   pinned   the node carries the pin
//   hue      a theme key that stands in for a post type's colour. The hues
//            mean post types, and a swatch that names no type has none:
//            the toggles' post is `dim`, as "All posts" is, and the Status
//            key's mark `ink`, as a page is.
//
// A swatch's mark is the SMALLEST the canvas draws (`radiusFor` of a node
// with no connections), in the same pixels.
//
// A ROW'S MARK (pages spec §7; design answer H2) is the same thing for a
// node of the data: `markCanvas(node)` answers a small canvas for a PAGE or
// a POST TYPE, where a row of the list, a search result or a card shows what
// the node is, and `paintMarks(root)` draws every one inside `root` with the
// renderer -- so a post type's row shows its hub as the canvas has it (a
// ring type's a ring round a centre, a retired type's dashed, "All posts"
// filled in dim) and not a copy of it in CSS. SMALLER THAN ON THE CANVAS,
// by a scale and nothing else (`ROW_MARKS`): the whole drawing is scaled,
// its rings and outlines with it, so nothing is redrawn at another size by
// another rule. What a canvas shows is said on it (`data-mark`, and for a
// post type `data-mark-of`: its colour slot, "retired" or "all-posts"),
// which is all `paintMarks` needs to draw it again when the theme changes.
// A row's mark shows the KIND, not the record's state: a page's is the
// live look whatever the page's state is (the canvas and the card say that).
// A post's dot and a tag's square in a row are older than this and are not
// canvases: they are CS Studio's own type dot
// (`Admin::Ui::ContentTypeDotComponent`'s classes, handed over by the view)
// and the tag's square, as everywhere in CS Studio.
import { draw, radiusFor } from "mind_graph/renderer"
import { readTheme } from "mind_graph/theme"
import { ALL_POSTS } from "mind_graph/ids"

const post = (more = {}) => ({ kind: "post", colour_index: 1, status: "live", ...more })

// The mark the five looks are shown on in the Status key. A READING (the
// pages plan, Task 6: "a neutral filled mark"): a post's dot in ink. For
// the designer: a page's card would do as well.
const KEY_MARK = { node: post(), hue: "ink" }
const look = (more) => ({ ...KEY_MARK, node: { ...KEY_MARK.node, ...more } })

export const SCENES = {
  page: { node: { kind: "page", status: "live" } },
  post: { node: post(), hue: "dim" },
  tag: { node: { kind: "tag" } },
  type: { node: { kind: "type", id: ALL_POSTS } },
  "line-tree": { line: "tree" },
  "line-lists": { line: "lists" },
  "line-related": { line: "related" },
  "line-tag": { line: "tag" },
  // By the names `Publishing::State` gives the five states.
  "state-live": look({}),
  "state-draft": look({ status: "draft" }),
  "state-scheduled": look({ status: "scheduled" }),
  "state-live-with-changes": look({ changes: "unpublished" }),
  "state-live-change-scheduled": look({ changes: "scheduled" }),
  retired: { node: post({ colour_index: null }) },
  pinned: { node: post(), hue: "dim", pinned: true },
  notes: { node: post({ open_notes: 1 }), hue: "dim", at: [ 18, 14.1 ] }
}

// Draws the swatch called `name` on `context`, `width` by `height` CSS
// pixels (the bitmap is `ratio` times that).
export function drawSwatch(context, theme, name, { width, height, ratio = 1 }) {
  const scene = SCENES[name]
  if (!scene) throw new Error(`mind graph: no swatch "${name}"`)

  const colours = scene.hue ? { ...theme, categories: theme.categories.map(() => theme[scene.hue]) } : theme
  const nodes = scene.line ? [ { id: "from", kind: "tag" }, { id: "to", kind: "tag" } ] : [ { id: name, degree: 0, label: "", ...scene.node } ]
  const [ x, y ] = scene.at ?? [ width / 2, height / 2 ]
  draw(context, {
    width, height, ratio, camera: { k: 1, tx: 0, ty: 0 }, theme: colours, nodes,
    edges: scene.line ? [ { kind: scene.line, source: 0, target: 1 } ] : [],
    positions: Float32Array.from(scene.line ? [ 0, height / 2, width, height / 2 ] : [ x, y ]),
    radii: nodes.map(radiusFor), widths: nodes.map(() => 0),
    // A line's two ends are no marks: nothing of them is drawn.
    visibleNodes: scene.line ? [] : [ 0 ], visibleEdges: scene.line ? [ 0 ] : [],
    labels: [], selected: -1, neighbours: new Set(), focusIndex: -1, hovered: -1, pinned: new Set(scene.pinned ? [ 0 ] : [])
  })
}

// Every `canvas[data-swatch]` inside `root`, in the colours the page has
// now. A canvas says its size in the page as `data-width` and
// `data-height`: its `width` and `height` are the bitmap's, which this
// writes (the device's pixels), and a Turbo snapshot keeps what was written.
export function paintSwatches(root) {
  const ratio = window.devicePixelRatio || 1
  for (const canvas of root.querySelectorAll("canvas[data-swatch]")) {
    const width = Number(canvas.dataset.width), height = Number(canvas.dataset.height)
    canvas.width = Math.round(width * ratio)
    canvas.height = Math.round(height * ratio)
    canvas.style.width = `${width}px`
    canvas.style.height = `${height}px`
    drawSwatch(canvas.getContext("2d"), readTheme(canvas), canvas.dataset.swatch, { width, height, ratio })
  }
}

// A row's marks: the size of each one's canvas in the page, and the scale
// its drawing has there. A post type's hub is 10px across where the canvas
// draws it at 12 (design answer H2: "a smaller copy of the hub as drawn,
// 10px with the inner ring"). A page's card is 10 wide where the canvas
// draws it 14 by 10: a READING (the pages plan, Task 7: "a 10 by 7 ink
// card"), by the same rule as the hub; its canvas is 8 high so that the
// card's 7.14 pixels are not cut.
export const ROW_MARKS = {
  page: { width: 10, height: 8, scale: 10 / 14 },
  type: { width: 10, height: 10, scale: 10 / 12 }
}

// The node a row's mark is drawn from: its kind, and for a post type what
// tells its hub (`marks.js`, `drawType`). Nothing of the record itself.
const markOf = (node) => (node.id === ALL_POSTS ? ALL_POSTS : node.colour_index == null ? "retired" : String(node.colour_index))
const markNode = (kind, of) =>
  kind === "page" ? { kind, status: "live" } : { kind, id: of === ALL_POSTS ? ALL_POSTS : "type", colour_index: /^\d+$/.test(of) ? Number(of) : null }

// An empty canvas for the mark of `node` (a page or a post type), sized for
// the page; `paintMarks` draws it once it is in the document (a canvas
// outside it has no colours to read). Decoration: the row's name says what
// the node is.
export function markCanvas(node) {
  const { width, height } = ROW_MARKS[node.kind]
  const canvas = document.createElement("canvas")
  canvas.className = "mg-swatch"
  canvas.width = width
  canvas.height = height
  canvas.dataset.mark = node.kind
  if (node.kind === "type") canvas.dataset.markOf = markOf(node)
  canvas.setAttribute("aria-hidden", "true")
  return canvas
}

// Draws the mark a canvas of `markCanvas` says it shows (`kind`, `of`), at
// its scale, in the middle of its box.
export function drawRowMark(context, theme, { kind, of }, { ratio = 1 } = {}) {
  const { width, height, scale } = ROW_MARKS[kind]
  const nodes = [ { id: "mark", degree: 0, label: "", ...markNode(kind, of) } ]
  draw(context, {
    // The renderer's own transform takes the scale up: the mark is drawn in
    // the canvas's pixels, on a page `scale` times as large.
    width: width / scale, height: height / scale, ratio: ratio * scale, camera: { k: 1, tx: 0, ty: 0 }, theme, nodes, edges: [],
    positions: Float32Array.from([ width / scale / 2, height / scale / 2 ]), radii: nodes.map(radiusFor), widths: [ 0 ],
    visibleNodes: [ 0 ], visibleEdges: [], labels: [], selected: -1, neighbours: new Set(), focusIndex: -1, hovered: -1, pinned: new Set()
  })
}

// Every `canvas[data-mark]` inside `root`, in the colours the page has now:
// read ONCE for all of them (a list may hold some hundreds of pages), from
// `root`, which must be in the document.
export function paintMarks(root) {
  const canvases = root.querySelectorAll("canvas[data-mark]")
  if (canvases.length === 0) return

  const theme = readTheme(root)
  const ratio = window.devicePixelRatio || 1
  for (const canvas of canvases) {
    const { width, height } = ROW_MARKS[canvas.dataset.mark]
    canvas.width = Math.round(width * ratio)
    canvas.height = Math.round(height * ratio)
    canvas.style.width = `${width}px`
    canvas.style.height = `${height}px`
    drawRowMark(canvas.getContext("2d"), theme, { kind: canvas.dataset.mark, of: canvas.dataset.markOf }, { ratio })
  }
}
