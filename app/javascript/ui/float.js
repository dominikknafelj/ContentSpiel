// A popover that opens inside a docked rail panel. The panel scrolls inside
// itself (`overflow-y: auto`, `.admin-rail__panel` in
// content-spiel.tailwind.css), so a popover that stands in it as an
// absolute box would be cut at the panel's edge, or would lengthen the
// panel's scroll instead of hanging over what is below. `float` lifts it out
// of the panel's clip: it is drawn `position: fixed` under its anchor, at the
// anchor's left (or right) edge, and placed again on every scroll and resize
// while it is open, since the page and the panel both scroll under it.
//
// A fixed box is laid out against its containing block, which here is not
// the window: the editor area is a size container (`container-type`), and a
// container contains its layout, fixed boxes included. So the corner is not
// assumed but measured: the popover is put at 0,0 first and where it lands
// is that corner (its own margin with it, so the margin it has as an
// absolute box stays its gap under the anchor). Its layer is unchanged, the
// popover's own (`--cs-z-popover`), inside the panel's stacking context.
//
// Outside a scrolling panel (below the rail's threshold, a translation tab,
// every other screen) it does nothing, and the popover stays the absolute
// box its classes draw. It returns what puts the popover back, called when
// the popover closes.
export function float(popover, anchor, { align = "left", width = false } = {}) {
  const panel = anchor.closest(".admin-rail__panel")
  if (!panel || !["auto", "scroll"].includes(getComputedStyle(panel).overflowY)) return () => {}

  const place = () => {
    const box = anchor.getBoundingClientRect()
    Object.assign(popover.style, { position: "fixed", top: "0px", left: "0px", right: "auto", width: width ? `${box.width}px` : "" })
    const corner = popover.getBoundingClientRect()
    const left = align === "right" ? box.right - corner.width : box.left
    popover.style.top = `${box.bottom - corner.top}px`
    popover.style.left = `${left - corner.left}px`
  }
  place()
  window.addEventListener("scroll", place, { capture: true, passive: true })
  window.addEventListener("resize", place)

  return () => {
    window.removeEventListener("scroll", place, { capture: true })
    window.removeEventListener("resize", place)
    for (const property of [ "position", "top", "left", "right", "width" ]) popover.style.removeProperty(property)
  }
}
