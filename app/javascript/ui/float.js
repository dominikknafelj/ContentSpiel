// A popover that opens inside a docked rail panel. The panel scrolls inside
// itself (`overflow-y: auto`, `.admin-rail__panel` in
// content-spiel.tailwind.css), so a popover that stands in it as an
// absolute box would be cut at the panel's edge, or would lengthen the
// panel's scroll instead of hanging over what is below. `float` lifts it out
// of the panel's clip: it is drawn `position: fixed` under its anchor, its own
// top margin under the anchor's bottom (the gap it has as an absolute box), at
// the anchor's left (or right) edge, and placed again on every scroll and
// resize while it is open, since the page and the panel both scroll under it.
// Where the window has no room for it below the anchor and has room above, it
// hangs above the anchor instead, the same gap away.
//
// A fixed box is laid out against its containing block, which here is not
// the window: the editor area is a size container (`container-type`), and a
// container contains its layout, fixed boxes included. So the corner is not
// assumed but measured: the popover is put at 0,0 first and where its border
// box lands, less its top margin, is that corner. Its layer is unchanged,
// the popover's own (`--cs-z-popover`), inside the panel's stacking context.
//
// When the anchor leaves the panel's visible area (the panel or the page
// scrolled it away) the popover would hang from nothing, so `leave` is
// called and the caller closes it.
//
// Outside a scrolling panel (below the rail's threshold, a translation tab,
// every other screen) it does nothing, and the popover stays the absolute
// box its classes draw. It returns what puts the popover back, called when
// the popover closes, with `floated` saying whether it lifted anything.
export function float(popover, anchor, { align = "left", width = false, leave = () => {} } = {}) {
  const panel = anchor.closest(".admin-rail__panel")
  if (!panel || !["auto", "scroll"].includes(getComputedStyle(panel).overflowY)) return Object.assign(() => {}, { floated: false })

  const outside = (box) => {
    const visible = panel.getBoundingClientRect()
    return box.bottom <= visible.top || box.top >= visible.bottom
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
