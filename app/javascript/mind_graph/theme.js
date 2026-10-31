// The mind graph's colours (mind graph canvas spec §4.3): read from the CSS
// custom properties, never written here. A canvas takes a colour as a string,
// and the browser accepts whatever CSS does (`oklch(...)` included), so the
// tokens are handed over exactly as the stylesheet resolves them.
//
// `watchTheme` answers a function that stops watching. The theme changes when
// `<html data-theme>` does (`theme_controller.js`) or, with no explicit
// choice, when the system's scheme does.
// `line` is the border of the notes badge and of the "+N more" pill; `tree`
// the tree's lines; `page` a page's mark (in dark not the ink, which glared);
// `faint` a hub's lines to what it brings in; `dim` the lists
// lines, a scheduled record's outline, a post's label and the dot of a live
// record with unpublished changes; `warn` means "scheduled", as on the
// status chip: a scheduled record's centre dot and a scheduled change's.
const TOKENS = { ink: "--cs-ink", meta: "--cs-meta", dim: "--cs-dim", warn: "--cs-warn", surface: "--cs-surface", sunken: "--cs-sunken", accent: "--cs-accent", line: "--cs-line-strong", faint: "--cs-line", page: "--cs-graph-page", tree: "--cs-graph-tree" }
const CATEGORIES = 6

export function readTheme(element) {
  const style = getComputedStyle(element)
  const read = (name) => style.getPropertyValue(name).trim()
  const theme = Object.fromEntries(Object.entries(TOKENS).map(([ key, name ]) => [ key, read(name) ]))
  theme.categories = Array.from({ length: CATEGORIES }, (_, index) => read(`--cs-cat-${index + 1}`))
  theme.font = `12px ${style.fontFamily}`
  // The selected node's label.
  theme.strongFont = `600 12px ${style.fontFamily}`
  // The notes count on a node and a "+N more" pill's words: the small mono
  // label style (`text-label`), read from the mono token so the canvas and
  // the page agree. 11px, never less: the brand book allows no text under
  // 11px in CS Studio, and a canvas's text is text. (It was 10px until
  // 2026-10-31; the badge's geometry in `marks.js` still holds "99+".)
  theme.countFont = `11px ${read("--cs-mono") || style.fontFamily}`
  // A tag's label: mono, like a tag everywhere else in CS Studio, and still
  // mono when its node is selected.
  theme.monoFont = `12px ${read("--cs-mono") || style.fontFamily}`
  theme.strongMonoFont = `600 12px ${read("--cs-mono") || style.fontFamily}`
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
