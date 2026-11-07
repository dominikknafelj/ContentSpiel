import { Controller } from "@hotwired/stimulus"

// Waiting for you's frame (`Admin::DashboardScreen::WaitingPanelComponent`),
// for the focus. A filter link navigates the frame, and the frame's answer
// replaces the panel with the link that was pressed in it: the focus would
// fall to <body>, and the next Tab start at the top of the document. So after
// a load that a filter's press started, the focus goes to the filter now
// current, the one the person chose.
//
// Only a press moves it. The live reload (`admin--notes--inbox#reload`) loads
// the same frame from the same `src` while the person may be anywhere on the
// screen, and must leave the focus where it is; that is why this is not a
// server-side `autofocus`, which Turbo would honour on every load. Which load
// a press started is decided when its request is made
// (`turbo:before-fetch-request`): every request takes the press, or its
// absence, with it, so a press whose fetch failed is not carried into the
// next reload. A press is a link's `turbo:click`, not its `click`: Turbo
// sends no such event for a click it leaves to the browser (a modifier key,
// a new tab), which starts no load here and must not mark the next one.
//
// Nothing is written into the page, so Turbo's snapshot keeps nothing of this.
export default class extends Controller {
  static targets = ["filter"]

  connect() {
    this.pressed = false
    this.focusOnLoad = false
  }

  press() {
    this.pressed = true
  }

  requested(event) {
    if (event.target !== this.element) return
    this.focusOnLoad = this.pressed
    this.pressed = false
  }

  loaded(event) {
    if (event.target !== this.element || !this.focusOnLoad) return
    this.focusOnLoad = false
    this.filterTargets.find((link) => link.getAttribute("aria-current") === "page")?.focus()
  }
}
