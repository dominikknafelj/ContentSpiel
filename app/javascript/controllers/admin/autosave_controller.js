import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Autosaves a page/post editor form (cs-studio spec §6.1): the page settings
// form, a block card, and the post form all share this one controller.
// `data-controller="admin--autosave"` sits directly on the `<form>` itself
// (never a wrapping element): every id this controller reads or writes (the
// status line, the hidden `base_updated_at` field) is resolved from the
// *response*, not from a Stimulus `target` declared here, which is exactly
// what lets the save-status line live in the record header (spec §5.1) --
// outside this form's own DOM subtree -- without this controller needing to
// reach outside itself at all: it only ever touches whatever `Admin::
// AutosaveResponses#autosave_stream` names in the Turbo Stream it sends
// back, applied wholesale via `Turbo.renderStreamMessage`, the same "fetch
// bypasses Turbo Drive, so nothing else applies this for us" pattern
// `admin--tree`'s own drag handler already uses.
//
// Debounced 1000ms after `input`/`change` (a rich-text editor reports its
// own edits by dispatching `input` from its hidden field, tiptap spec
// §4.1), immediately on `focusout` (global constraints §6.1) -- `queue`/
// `saveNow` below are just two ways of arriving at the same `trigger`.
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
    debounce: { type: Number, default: 1000 },
    // A block card's form names the page settings form's base field here
    // (`Admin::BlockCardComponent#form_data`): its current value rides
    // along as `X-Page-Base-Updated-At`, so the server only moves that
    // form's base forward when it was still current (`Admin::
    // ContentBlocksController#page_base_streams`).
    pageBaseId: String
  }

  // Client-only states `Admin::SaveStatusComponent` never has occasion to
  // render server-side -- there is no request to answer with them, since
  // they describe the request *not landing* at all. Every one of these has
  // to read exactly like `Admin::SaveStatusComponent#text`'s own matching
  // state (`signedOut`/`:signed_out` included, even though that one's never
  // actually rendered by a server response either -- see that component's
  // own comment for why it's still a named state there).
  static texts = {
    saving: "Saving…",
    retrying: "Not saved — retrying",
    offline: "Not saved — check your connection",
    signedOut: "Signed out — sign in again to keep saving"
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
        headers: this.requestHeaders()
      })
    } catch (error) {
      this.scheduleRetry()
      return
    }

    // Fix (final-fixes round, finding 4): a network error throws (caught
    // above), but a *response* arriving isn't automatically a real answer
    // -- an expired session's redirect to sign-in, a stray 404/500 error
    // page, are all "responses" too, and treating every one of them as a
    // successful save (the original code's own bug) is exactly what used
    // to leave the status line stuck on "Saving…" forever while nothing
    // was actually being saved.
    //
    // `response.redirected` is checked first and on its own: `fetch`'s
    // default `redirect: "follow"` means a 302 to sign-in ends up here as
    // a *followed*, final 200 response for the sign-in page itself -- this
    // controller's own PATCH endpoints never redirect otherwise -- and it
    // gets its own client-only status (`signedOut`, matching `Admin::
    // SaveStatusComponent`'s own `:signed_out`) rather than the retry path
    // below: retrying a PATCH against an expired session can never
    // succeed on its own, only signing back in does.
    if (response.redirected) {
      this.retryCount = 0
      this.busy = false
      this.setStatus(this.constructor.texts.signedOut)
      return
    }

    // Anything else has to actually be the Turbo Stream response this
    // controller's own endpoints answer with -- global constraints' own
    // "Couldn't save"/"Changed elsewhere" status texts only ever reach the
    // page through one of *those* streams (`Admin::AutosaveResponses
    // #autosave_stream`), so a response with some other content type, or a
    // status outside this endpoint's own documented range (2xx a save;
    // 410 "this block was deleted"; 422 a failed save's own per-field
    // errors) was never actually processed by the endpoint at all -- a 500,
    // a proxy's own error page, ... -- and takes the same retry path a
    // network error does, rather than being handed to
    // `Turbo.renderStreamMessage` as if it were one.
    if (!this.isTurboStreamAnswer(response)) {
      this.scheduleRetry()
      return
    }

    // A 422 with a body is still a real answer at this point -- the
    // server-rendered stream already turns that into the "Couldn't save"
    // status and the per-field errors, so it counts as success from *this*
    // controller's own point of view (nothing left to retry).
    const text = await response.text()

    // Fix (discovered by this task's own autosave-queue system test):
    // `Turbo.renderStreamMessage` doesn't patch the DOM synchronously --
    // confirmed empirically, its `<turbo-stream>` elements apply on the
    // *next animation frame*, not on this line, not even after a
    // microtask/macrotask -- so a `pending` retrigger just below used to
    // build its own `FormData` from the *stale* `base_updated_at` hidden
    // field this very response is about to refresh, making a client's own
    // very next save spuriously report "Changed elsewhere — reload to see
    // the latest" against nothing but itself (spec §6.1's staleness check
    // is meant to catch an edit from *elsewhere*, not this). Reading the
    // field's fresh value straight out of the response text and writing it
    // onto the form ourselves, synchronously, right now, is what keeps that
    // race from ever mattering -- Turbo's own (later) replace of the same
    // element just re-applies the identical value once it catches up.
    // `template.content` (not a plain `querySelector` on the parsed
    // document) is what a `<turbo-stream>`'s own hidden field actually
    // lives in -- a `<template>`'s content is its own document fragment,
    // invisible to a query against the document around it.
    //
    // Matched by id, not just by name: a block card's response also carries
    // the page settings form's own base (the block write touched the page --
    // `Admin::ContentBlocksController#page_base_stream`), and taking the
    // first `base_updated_at` in the response would hand this card the
    // page's value instead of its own.
    const ownBase = this.element.querySelector('[name="base_updated_at"]')
    const freshBase = ownBase && Array.from(new DOMParser().parseFromString(text, "text/html").querySelectorAll("template"))
      .map((template) => template.content.querySelector(`[name="base_updated_at"][id="${ownBase.id}"]`))
      .find((field) => field)
    if (freshBase && ownBase) ownBase.value = freshBase.value

    Turbo.renderStreamMessage(text)
    this.retryCount = 0
    this.busy = false

    if (this.pending) this.trigger()
  }

  requestHeaders() {
    const headers = {
      Accept: "text/vnd.turbo-stream.html",
      "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
    }
    const pageBase = this.hasPageBaseIdValue && document.getElementById(this.pageBaseIdValue)?.value
    if (pageBase) headers["X-Page-Base-Updated-At"] = pageBase
    return headers
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

  // True for exactly the responses this controller's own PATCH endpoints
  // (`Admin::AutosaveResponses#autosave_stream`'s callers) actually answer
  // with (final-fixes round, finding 4) -- a real Turbo Stream body, at one
  // of the three statuses those endpoints ever send: a plain 2xx success,
  // 410 (a destroyed block/post, "This block was deleted"), or 422 (a
  // failed save's own per-field errors). Anything else -- wrong content
  // type, or a status this endpoint never documents sending at all -- is
  // treated as "no real answer arrived," not as this save having somehow
  // succeeded.
  isTurboStreamAnswer(response) {
    const contentType = response.headers.get("Content-Type") || ""
    const answeredStatus = (response.status >= 200 && response.status < 300) || response.status === 410 || response.status === 422

    return answeredStatus && contentType.includes("text/vnd.turbo-stream.html")
  }

  setStatus(text) {
    const status = document.getElementById(this.statusIdValue)
    if (status) status.textContent = text
  }
}
