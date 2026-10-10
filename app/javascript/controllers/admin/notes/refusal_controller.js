import { Controller } from "@hotwired/stimulus"

// A refused Pin or Notify (the notes handoff's decision 40), on the warn
// alert `Admin::NotesScreen::ThreadComponent` draws under a thread's two
// rows.
//
// - Its × takes the alert away. The focus, which was on the ×, goes to the
//   thread: never left to fall to <body>.
// - The person's next action in the thread clears it without this script:
//   that action's answer redraws the part the alert is in. (A refresh for
//   someone else's change is no action of theirs; `admin--notes--live` carries
//   the alert over it.)
// - `gone`: the sentence is "This note is gone". Nothing is left to act on,
//   so after `GONE_MS` the notes frame goes back to the list (`back`). The
//   time is counted from when the alert first appeared (`data-until`, on the
//   element): carried over a refresh, the element connects again and must
//   not start four new seconds. The timer goes with the element -- closed,
//   replaced by the next answer, or left behind by a navigation of the frame
//   -- so it never fires into what the person opened meanwhile.
const GONE_MS = 4000

export default class extends Controller {
  static values = { gone: Boolean, back: String }

  connect() {
    if (!this.goneValue || !this.backValue) return

    const until = Number(this.element.dataset.until) || Date.now() + GONE_MS
    this.element.dataset.until = String(until)
    this.timer = setTimeout(() => this.leave(), Math.max(0, until - Date.now()))
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  close() {
    const view = this.element.closest("[data-notes-view]")
    this.element.remove()
    view?.focus({ preventScroll: true })
  }

  leave() {
    const frame = this.element.closest("turbo-frame#notes")
    if (frame) frame.src = this.backValue
  }
}
