import { Controller } from "@hotwired/stimulus"

// Your account's Sessions card (`Admin::AccountScreen::SessionsCardComponent`).
// A row's End is answered by a stream that takes the row away, and the End
// that had the focus goes with it: the focus would fall to the page. So the
// row an End was pressed in is remembered, and when that row leaves the
// document the focus goes to the next row's End, or, after the last row, to
// the foot's "Sign out everywhere else…", or, when no other session is left
// and the foot offers nothing (or that button waits, disabled, for the
// screen's unsaved changes: `admin--saving--pending-lock`), to the foot itself.
//
// The answer replaces the foot before it removes the row, so the foot read
// here is already the new one. A row that goes for any other reason (a visit,
// the page drawn again) was not being ended, and moves nothing.
export default class extends Controller {
  static targets = ["row", "end", "foot", "endOthers"]

  ending(event) {
    const row = event.target.closest("li")
    if (!row) return
    this.leaving = row
    this.following = this.rowTargets.slice(this.rowTargets.indexOf(row) + 1)
  }

  rowTargetDisconnected(row) {
    if (row !== this.leaving) return
    this.leaving = null

    const next = this.following.find((candidate) => candidate.isConnected)
    this.following = []
    const end = next && this.endTargets.find((button) => next.contains(button))
    const target = end || (this.hasEndOthersTarget && !this.endOthersTarget.disabled && this.endOthersTarget) || (this.hasFootTarget && this.footTarget)
    if (target) target.focus()
  }
}
