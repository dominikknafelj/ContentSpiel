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
import { draw, radiusFor } from "mind_graph/renderer"
import { readTheme } from "mind_graph/theme"

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
  type: { node: { kind: "type", id: "all-posts" } },
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
  notes: { node: post({ open_notes: 1 }), hue: "dim", at: [ 17, 14 ] }
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
