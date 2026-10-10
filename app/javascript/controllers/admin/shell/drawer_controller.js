import { Controller } from "@hotwired/stimulus"

// The shell's two drawers (design pass spec §4, handoff §9 A7): below 1280px
// the modules sidebar slides in over the content, below 1024px so does the
// page tree. Lives on <body>, because its triggers (the top bar) and its
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
// The editors' notes drawer (`admin--notes--drawer`) is the one other drawer, on the
// right: opening a panel here says so (`admin--shell--drawer:opened`, with the
// panel's name) and that one closes; when that one opens, these stand aside
// (`standAside`). While the notes are a column beside the editor the page
// tree is folded into its drawer at widths where it otherwise is a column
// (content-spiel.tailwind.css, "THE PAGE TREE FOLDS"): the same panel, the
// same `data-open`, nothing here knows.
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
    // on the page it covers.
    const first = panel.querySelector("a[href], button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex='-1'])")
    ;(first || panel).focus({ preventScroll: true })
    // The notes drawer hears this and makes room (`admin--notes--drawer#shellOpened`),
    // unless it is a column and this is the page tree folded beside it.
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
  // is a page having been picked; ⌘K with the tree drawer open used to close
  // the drawer behind the palette.
  frameLoaded(event) {
    if (event.target.id !== "content") return
    const tree = this.panelNamed("tree")
    if (tree?.hasAttribute("data-open")) this.close(tree)
  }

  // Navigation never keeps a drawer open and never steals focus into the
  // page that is about to be replaced.
  visiting() { this.closeAll({ refocus: false }) }

  // The notes drawer opened (`admin--notes--drawer:opened`): a shell drawer makes
  // room. The focus is the notes drawer's, so it is not handed back here.
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
