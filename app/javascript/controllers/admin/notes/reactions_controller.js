import { Controller } from "@hotwired/stimulus"

// The emoji set under a message (handoff "Reaction chip", decision 22), on
// the message `Admin::NotesScreen::MessageComponent` draws. The set itself is
// a <details> with a form of submits (`ReactionsComponent`): it opens, and a
// reaction is given, without this script. What is done here:
//
// - WHERE IT OPENS. Above its chip; below only when there is no room above
//   inside the thread's scroll area -- the drawer's body, or the window where
//   the notes are in no drawer -- and never over row 1 ("All notes", Notify),
//   so the top of the room is whichever is lower: the scroll area's top or
//   row 1's bottom edge. The same rule as the mind graph card's placement
//   (prefer one side, flip when it does not fit), written here for one axis:
//   that one places a box beside a point in a canvas. Flipped below, it is
//   scrolled into view, since the reply dock stands at the bottom.
// - ESCAPE closes the set and gives the focus back to its chip. The key is
//   used up here, so the drawer around it stays open.
// - A PRESS OUTSIDE the set closes it.
// - "React" in the message's "⋯" menu (for touch, where nothing hovers)
//   opens the same set and puts the focus on its first emoji.
const GAP = 6

export default class extends Controller {
  static targets = [ "add", "panel" ]

  // `toggle` on the <details> (it does not bubble: the action is on the
  // element itself).
  toggled() {
    if (!this.hasAddTarget || !this.addTarget.open) return

    const add = this.addTarget
    delete add.dataset.side
    // The messages' own scroller where they have one (the drawer and the
    // sheet, decision 35: it starts under the thread's two rows and clips
    // the set), else the drawer's body.
    const own = this.element.closest("[data-note-scroll]")
    const scroller = own && /auto|scroll/.test(window.getComputedStyle(own).overflowY) ? own : this.element.closest("[data-notes-scroller]")
    const row = this.element.closest("[data-notes-view]")?.querySelector("a[data-note-back]")?.parentElement
    const ceiling = Math.max(scroller ? scroller.getBoundingClientRect().top : 0, row ? row.getBoundingClientRect().bottom : 0)
    if (add.getBoundingClientRect().top - ceiling < this.panelTarget.offsetHeight + GAP) {
      add.dataset.side = "below"
      this.panelTarget.scrollIntoView({ block: "nearest" })
    }
  }

  // The menu's "React".
  open() {
    if (!this.hasAddTarget) return

    this.addTarget.open = true
    this.toggled()
    this.panelTarget.querySelector("button")?.focus({ preventScroll: true })
  }

  escape(event) {
    if (!this.hasAddTarget || !this.addTarget.open) return

    event.preventDefault()
    event.stopPropagation()
    this.addTarget.open = false
    this.addTarget.querySelector("summary")?.focus({ preventScroll: true })
  }

  // `click` on the window. The press that opened the set from the menu is
  // outside it too, and is not what closes it.
  outside(event) {
    if (!this.hasAddTarget || !this.addTarget.open) return
    if (this.addTarget.contains(event.target) || event.target.closest?.("[data-note-react]")) return

    this.addTarget.open = false
  }
}
