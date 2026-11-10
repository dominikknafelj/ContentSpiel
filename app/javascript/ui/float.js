// A popover that opens inside a box that clips it: a docked rail panel,
// which scrolls inside itself (`overflow-y: auto`, `.admin-rail__panel` in
// content-spiel.tailwind.css), or a table's scroll box (`.admin-table-scroll`
// and `.admin-table-scroll--x`, Translations', Trash's and the Forms list's;
// `.admin-posts-scroll`, the posts list's), which scrolls sideways and so
// clips upright too (`overflow-x: auto` makes `overflow-y` auto). A popover
// that stands in one as an absolute box would be cut at the box's edge, or
// would lengthen the box's scroll instead of hanging over what is below: a
// row's "⋯" menu on a list of one row. `CLIPS` names them all, and the one
// path below serves each. `float` lifts the popover out of the box's clip:
// it is drawn `position: fixed` under its anchor, its own top margin under
// the anchor's bottom (the gap it has as an absolute box), at the anchor's
// left (or right) edge, and placed again on every scroll and resize while it
// is open, since the page and the box both scroll under it. Where the window
// has no room for it below the anchor and has room above, it hangs above the
// anchor instead, the same gap away.
//
// A fixed box is laid out against its containing block, which here is not
// always the window: the editor area is a size container (`container-type`),
// and a container contains its layout, fixed boxes included. So the corner is
// not assumed but measured: the popover is put at 0,0 first and where its
// border box lands, less its top margin, is that corner. Its layer is
// unchanged, the popover's own (`--cs-z-popover`), inside the box's stacking
// context.
//
// When the anchor leaves the box's visible area (the box or the page
// scrolled it away, up and down or sideways) the popover would hang from
// nothing, so `leave` is called and the caller closes it. The caller closes
// a lifted popover before Turbo caches the page, too.
//
// Outside such a box (below the rail's threshold, a translation tab, every
// other screen) it does nothing, and the popover stays the absolute box its
// classes draw. It returns what puts the popover back, called when the
// popover closes, with `floated` saying whether it lifted anything.
const CLIPS = ".admin-rail__panel, .admin-table-scroll, .admin-table-scroll--x, .admin-posts-scroll"

export function float(popover, anchor, { align = "left", width = false, leave = () => {} } = {}) {
  const panel = anchor.closest(CLIPS)
  if (!panel || !["auto", "scroll"].includes(getComputedStyle(panel).overflowY)) return Object.assign(() => {}, { floated: false })

  const outside = (box) => {
    const visible = panel.getBoundingClientRect()
    return box.bottom <= visible.top || box.top >= visible.bottom || box.right <= visible.left || box.left >= visible.right
  }

  // Whether the anchor left is asked on a scroll or a resize, never as the
  // popover opens: the caller has the function to close with only once
  // `float` has returned.
  const place = (event) => {
    const box = anchor.getBoundingClientRect()
    if (event && outside(box)) return leave()

    Object.assign(popover.style, { position: "fixed", top: "0px", left: "0px", right: "auto", width: width ? `${box.width}px` : "" })
    const gap = parseFloat(getComputedStyle(popover).marginTop) || 0
    const at = popover.getBoundingClientRect()
    const corner = { top: at.top - gap, left: at.left }
    const below = box.bottom + gap
    const above = box.top - gap - at.height
    const top = below + at.height > window.innerHeight && above >= 0 ? above : below
    const left = align === "right" ? box.right - at.width : box.left
    // `top` is where the border box goes; the browser adds the margin, so it
    // is taken off here.
    popover.style.top = `${top - corner.top - gap}px`
    popover.style.left = `${left - corner.left}px`
  }
  place()
  window.addEventListener("scroll", place, { capture: true, passive: true })
  window.addEventListener("resize", place)

  return Object.assign(() => {
    window.removeEventListener("scroll", place, { capture: true })
    window.removeEventListener("resize", place)
    for (const property of [ "position", "top", "left", "right", "width" ]) popover.style.removeProperty(property)
  }, { floated: true })
}
