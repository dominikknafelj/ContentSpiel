import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Autosaves a page/post editor form (cs-studio spec §6.1) -- the page
// settings form today, a block card and the post form once Tasks 5/6 add
// them. `data-controller="admin--autosave"` sits directly on the `<form>`
// itself (never a wrapping element): every id this controller reads or
// writes (the status line, the hidden `base_updated_at` field) is resolved
// from the *response*, not from a Stimulus `target` declared here, which is
// exactly what lets the save-status line live in the record header (spec
// §5.1) -- outside this form's own DOM subtree -- without this controller
// needing to reach outside itself at all: it only ever touches whatever
// `Admin::AutosaveResponses#autosave_stream` names in the Turbo Stream it
// sends back, applied wholesale via `Turbo.renderStreamMessage`, the same
// "fetch bypasses Turbo Drive, so nothing else applies this for us" pattern
// `admin--tree`'s own drag handler already uses.
//
// Debounced 1000ms after `input`/`change`, immediately on `focusout`
// (global constraints §6.1) -- `queue`/`saveNow` below are just two ways of
// arriving at the same `trigger`.
//
// Concurrency: `busy` covers the *entire* attempt, including any retry
// backoff, not just the fetch itself -- an edit that arrives while a save
// is in flight *or* waiting to retry sets `pending` instead of firing its
// own request, and whichever `attempt()` call is currently running is the
// only thing that ever starts the next one (on success, immediately, with
// whatever the form holds *now*; a retry's own `attempt()` picks up the
// same latest state automatically, since it always builds `FormData` fresh
// rather than replaying whatever body the failed attempt sent).
// This is what "one request in flight, at most one queued" (spec §6.1)
// actually means: never two in-flight saves racing to overwrite each
// other's fields on screen with a stale response, and never a queue of
// more than one -- a second, third, fourth edit while busy all collapse
// into the same single follow-up.
export default class extends Controller {
  static values = {
    statusId: String,
    debounce: { type: Number, default: 1000 }
  }

  // Client-only states `Admin::SaveStatusComponent` never has occasion to
  // render server-side -- there is no request to answer with them, since
  // they describe the request *not landing* at all.
  static texts = {
    saving: "Saving…",
    retrying: "Not saved — retrying",
    offline: "Not saved — check your connection"
  }

  // Backoff after a failed attempt (spec §6.1/global constraints): 1s, 3s,
  // then 9s, then give up and show the offline state until the next edit.
  static retryDelays = [ 1000, 3000, 9000 ]

  connect() {
    this.timer = null
    this.busy = false
    this.pending = false
    this.retryCount = 0
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
  }

  queue() {
    if (this.timer) clearTimeout(this.timer)
    this.timer = setTimeout(() => this.trigger(), this.debounceValue)
  }

  saveNow() {
    if (this.timer) clearTimeout(this.timer)
    this.trigger()
  }

  trigger() {
    this.timer = null

    if (this.busy) {
      this.pending = true
      return
    }

    this.busy = true
    this.pending = false
    this.attempt()
  }

  async attempt() {
    this.setStatus(this.constructor.texts.saving)

    let response
    try {
      response = await fetch(this.element.action, {
        method: "PATCH",
        body: new FormData(this.element),
        headers: {
          Accept: "text/vnd.turbo-stream.html",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        }
      })
    } catch (error) {
      this.scheduleRetry()
      return
    }

    // A network error throws (caught above); a 422 with a body is still a
    // real answer -- the server-rendered stream already turns that into the
    // "Couldn't save" status and the per-field errors, so it counts as
    // success from *this* controller's point of view (nothing to retry).
    Turbo.renderStreamMessage(await response.text())
    this.retryCount = 0
    this.busy = false

    if (this.pending) this.trigger()
  }

  scheduleRetry() {
    const delays = this.constructor.retryDelays

    if (this.retryCount >= delays.length) {
      this.setStatus(this.constructor.texts.offline)
      this.retryCount = 0
      this.busy = false
      return
    }

    this.setStatus(this.constructor.texts.retrying)
    const delay = delays[this.retryCount]
    this.retryCount += 1
    // `busy` stays true across the wait: an edit that lands mid-backoff
    // still only ever queues (see the class comment above), it doesn't
    // jump the line and fire its own request ahead of the scheduled retry.
    setTimeout(() => this.attempt(), delay)
  }

  setStatus(text) {
    const status = document.getElementById(this.statusIdValue)
    if (status) status.textContent = text
  }
}
