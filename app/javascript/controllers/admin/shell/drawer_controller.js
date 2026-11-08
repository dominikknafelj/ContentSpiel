import { Controller } from "@hotwired/stimulus"

// The shell's two drawers: below 1280px the modules sidebar slides in over
// the content, below 1024px so does the tree column. Lives on <body>, because its triggers (the top bar) and its
// panels (the grid's sidebar and tree columns) are siblings, not nested.
//
// A panel is any `[data-admin--shell--drawer-target=panel]` carrying
// `data-drawer="<name>"` and an `id`; a trigger is a button with
// `data-admin--shell--drawer-target=trigger` and `aria-controls="<that id>"`,
// passing the name as `data-admin--shell--drawer-name-param`. "Open" is the
// `data-open` attribute on the panel -- the CSS does the sliding, and above
// the breakpoint the attribute is simply never set (no drawer exists), so
// nothing here has to know about widths. The scrim is shown while any panel
// is open and closes them on click.
//
// The editors' notes (`admin--notes--drawer`) are the one other thing that
// slides in, from the right, below the rail's threshold: opening a panel
// here says so (`admin--shell--drawer:opened`, with the panel's name) and the
// slide-over closes; when the notes open, these stand aside (`standAside`).
export default class extends Controller {
  static targets = [ "panel", "scrim", "trigger" ]

  toggle(event) {
    const panel = this.panelNamed(event.params.name)
    if (!panel) return

    if (panel.hasAttribute("data-open")) {
      this.close(panel, { refocus: true })
    } else {
      this.closeAll({ refocus: false })
      this.open(panel, event.currentTarget)
    }
  }

  open(panel, trigger) {
    this.returnFocusTo = trigger
    panel.setAttribute("data-open", "")
    this.syncTriggers()
    this.scrimTarget.hidden = false
    // Focus moves into the drawer so a keyboard user isn't left behind it
    // on the page it covers: to its first control that is drawn. A control
    // the stylesheet does not draw in a drawer (the page tree's strip button
    // and "Hide page tree", which are the column's) cannot take the focus.
    const first = Array.from(panel.querySelectorAll("a[href], button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex='-1'])"))
      .find((control) => control.checkVisibility())
    ;(first || panel).focus({ preventScroll: true })
    // The notes' slide-over hears this and makes room
    // (`admin--notes--drawer#shellOpened`).
    this.dispatch("opened", { detail: { name: panel.dataset.drawer } })
  }

  close(panel, { refocus = false } = {}) {
    panel.removeAttribute("data-open")
    this.syncTriggers()
    this.scrimTarget.hidden = !this.anyOpen
    if (refocus && this.returnFocusTo?.isConnected) this.returnFocusTo.focus()
  }

  // Escape, a scrim click and every Turbo visit land here. Focus goes back
  // to the trigger only when something was actually open -- Escape pressed
  // with no drawer (a dialog's own Escape, say) must not steal it.
  closeAll({ refocus = true } = {}) {
    const wasOpen = this.anyOpen
    this.panelTargets.forEach((panel) => panel.removeAttribute("data-open"))
    this.syncTriggers()
    this.scrimTarget.hidden = true
    if (wasOpen && refocus && this.returnFocusTo?.isConnected) this.returnFocusTo.focus()
  }

  // A page picked in the tree loads into the content frame: that closes the
  // tree drawer (the sidebar's own links are full visits, handled by
  // `turbo:before-visit`). Only `#content`: the layout hears every frame's
  // load on `document` -- the ⌘K results (on each keystroke), the New page /
  // New post dialogs' forms, the media picker's library -- and none of those
  // is a page having been picked, so ⌘K with the tree drawer open does not
  // close the drawer behind the palette.
  frameLoaded(event) {
    if (event.target.id !== "content") return
    const tree = this.panelNamed("tree")
    if (tree?.hasAttribute("data-open")) this.close(tree)
  }

  // Something in a drawer was chosen that is shown outside it (`tree:chosen`,
  // the mind graph's list selecting a node, whose card is over the canvas):
  // the drawer it stands in closes, its scrim with it, and the focus is the
  // chooser's to place.
  chosen(event) {
    const panel = this.panelTargets.find((candidate) => candidate.contains(event.target))
    if (panel?.hasAttribute("data-open")) this.close(panel)
  }

  // Navigation never keeps a drawer open and never steals focus into the
  // page that is about to be replaced.
  visiting() { this.closeAll({ refocus: false }) }

  // The notes opened (`admin--notes--drawer:opened`): a shell drawer makes
  // room. The focus is the notes', so it is not handed back here.
  standAside() { this.closeAll({ refocus: false }) }

  get anyOpen() { return this.panelTargets.some((panel) => panel.hasAttribute("data-open")) }

  panelNamed(name) { return this.panelTargets.find((panel) => panel.dataset.drawer === name) }

  syncTriggers() {
    this.triggerTargets.forEach((trigger) => {
      const panel = this.panelTargets.find((candidate) => candidate.id === trigger.getAttribute("aria-controls"))
      trigger.setAttribute("aria-expanded", panel?.hasAttribute("data-open") ? "true" : "false")
    })
  }
}
