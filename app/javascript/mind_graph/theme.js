// The mind graph's colours and fonts: read from the CSS
// custom properties, never written here. A canvas takes a colour as a string,
// and the browser accepts whatever CSS does (`oklch(...)` included), so the
// tokens are handed over exactly as the stylesheet resolves them.
//
// `watchTheme` answers a function that stops watching. The theme changes when
// `<html data-theme>` does (`theme_controller.js`) or, with no explicit
// choice, when the system's scheme does.
// Each key and what it draws:
// - `line` the border of the notes badge and of the "+N more" pill;
// - `edge` a draft's dashed outline, the Draft chip's edge (`--cs-field-line`);
// - `page` a page's mark (ink in light, dim in dark, where the ink glares);
// - `tag` a tag's square and its label, the structure hue;
// - `lineTree`, `lineLists`, `lineRelated`, `lineTag`, `lineBrings` the five
//   lines (`renderer.js`, `LINE_STYLES`), each at its own strength in its
//   token, so the script holds none;
// - `dim` a scheduled record's outline, a post's label and the dot of a live
//   record with unpublished changes; `warn` means "scheduled", as on the
//   status chip: a scheduled record's centre dot and a scheduled change's;
// - `faded` (a number, 0 to 1) the strength of what a selection leaves out.
const TOKENS = {
  ink: "--cs-ink", meta: "--cs-meta", dim: "--cs-dim", warn: "--cs-warn", surface: "--cs-surface", sunken: "--cs-sunken", accent: "--cs-accent",
  line: "--cs-line-strong", page: "--cs-graph-page", edge: "--cs-field-line", tag: "--cs-graph-tag",
  lineTree: "--cs-graph-line-tree", lineLists: "--cs-graph-line-lists", lineRelated: "--cs-graph-line-related", lineTag: "--cs-graph-line-tag", lineBrings: "--cs-graph-line-brings"
}
const CATEGORIES = 6

export function readTheme(element) {
  const style = getComputedStyle(element)
  const read = (name) => style.getPropertyValue(name).trim()
  const theme = Object.fromEntries(Object.entries(TOKENS).map(([ key, name ]) => [ key, read(name) ]))
  theme.categories = Array.from({ length: CATEGORIES }, (_, index) => read(`--cs-cat-${index + 1}`))
  // A missing token draws what it fades at full strength, never not at all.
  const faded = Number.parseFloat(read("--cs-graph-faded"))
  theme.faded = Number.isFinite(faded) ? faded : 1
  // Every word on the canvas is in the page's own sans, CS Studio's one type
  // voice. Each is a face the stylesheet loads (`@font-face`, Archivo 400,
  // 500 and 600), so a label is measured in the face it is drawn in. 11px is
  // the least: the brand book allows no text under 11px in CS Studio.
  theme.font = `12px ${style.fontFamily}`
  // The selected node's label.
  theme.strongFont = `600 12px ${style.fontFamily}`
  // The notes count on a node and a "+N more" pill's words, as a count is
  // set on the page (`text-count`).
  theme.countFont = `500 11px ${style.fontFamily}`
  // The card's corner radius (`rounded-cs`), for a page's mark. The token is
  // a length in pixels and is read as one: `parseFloat` takes the number in
  // front of "px" and knows no other unit, so a token given in `rem` would
  // be read as that many pixels.
  theme.radius = Number.parseFloat(read("--cs-radius")) || 0
  return theme
}

export function watchTheme(callback) {
  const observer = new MutationObserver(callback)
  observer.observe(document.documentElement, { attributes: true, attributeFilter: [ "data-theme", "class" ] })
  const scheme = window.matchMedia("(prefers-color-scheme: dark)")
  scheme.addEventListener("change", callback)
  return () => {
    observer.disconnect()
    scheme.removeEventListener("change", callback)
  }
}
