// The words a card's header says for a few seconds: "Updated by ..." (drawn
// by the server, in the answer to a fetch made with `mark=1`) and "Taken over
// by you" (a template of the live region, cloned here). Both stand in the
// header's `[data-editing-mark-place]`.
//
// A mark fades over 200ms after `after` milliseconds, and goes at once under
// reduced motion. The card's glow is the stylesheet's, drawn from the mark's
// presence and its `admin-editing-mark--leaving`; this module writes only the
// mark and that class.
//
// Whatever a controller shows through here it takes back with
// `clearMarks(root)`, which removes every mark under `root` and stops its
// timers. A controller calls it when it disconnects, which is after Turbo has
// cloned its snapshot: no snapshot of an editor is kept, since its pages are
// `turbo-cache-control: no-cache`, and that is why nothing stale is restored.
const FADE = 200
const timers = new WeakMap()

// The block's own unit: its card in the list or its panel in a section. A
// section's tile carries the card's id too and has no place for a mark.
function unitOf(root, blockId) {
  const id = CSS.escape(blockId)
  return root.querySelector(`.admin-block-card[id="content_block_${id}"], .admin-block-card[id="block-${id}-panel"]`)
}

export function showMark(root, blockId, template) {
  const place = unitOf(root, blockId)?.querySelector("[data-editing-mark-place]")
  if (!place || !template) return null
  const mark = template.content.firstElementChild?.cloneNode(true)
  if (!mark) return null
  place.replaceChildren(mark)
  return mark
}

export function fadeMark(mark, { after }) {
  if (!mark) return
  const ids = []
  const later = (act, ms) => ids.push(setTimeout(act, ms))
  timers.set(mark, ids)
  later(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return mark.remove()
    mark.classList.add("admin-editing-mark--leaving")
    later(() => mark.remove(), FADE)
  }, after)
}

export function clearMarks(root) {
  root.querySelectorAll("[data-editing-mark]").forEach((mark) => {
    timers.get(mark)?.forEach(clearTimeout)
    mark.remove()
  })
}
