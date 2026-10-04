import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { enqueue, syncBases } from "autosave/queue"

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
//
// Across forms: that rule is per form. Every request this controller sends
// also goes through the page-level queue (`autosave/queue.js`), shared with
// every other autosaving form on the screen and with block add/duplicate/
// delete/reorder: one request is on the wire at a time, and each reads its
// body and bases when it is SENT, after the previous answer's bases were
// written into the hidden fields. Without it, forms that debounce on the same
// tick ("Use all") send the same page base together, one write makes the
// other's base stale, and the page settings form is left holding a base
// nobody else made stale -- now a final 409. See the queue's own comment.
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
  //
  // `savingLive` is the same line for a live record, whose edits go
  // straight to the site: the status element says so with `data-live`
  // (`Admin::SaveStatusComponent`'s `live:`). `offline` ends in a Retry
  // button (`setStatus` builds it), which is why its text stops at "· ".
  static texts = {
    saving: "SAVING…",
    savingLive: "SAVING TO SITE…",
    retrying: "NOT SAVED · RETRYING…",
    offline: "NOT SAVED · ",
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
    // Set by a 409 ("changed elsewhere"): this form's saves are over until
    // the page is reloaded (see `attempt`).
    this.paused = false
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
  }

  queue() {
    if (this.paused) return
    if (this.timer) clearTimeout(this.timer)
    this.timer = setTimeout(() => this.trigger(), this.debounceValue)
  }

  saveNow() {
    if (this.paused) return
    if (this.timer) clearTimeout(this.timer)
    this.trigger()
  }

  trigger() {
    this.timer = null
    if (this.paused) return

    if (this.busy) {
      this.pending = true
      return
    }

    this.busy = true
    this.pending = false
    this.attempt()
  }

  // One save attempt. The request itself is SENT from inside the page-level
  // queue (`autosave/queue.js` -- read its comment for why every write on a
  // screen goes one at a time): the "saving" line shows from the moment the
  // attempt is queued, and the body, headers and bases are read when the
  // request is actually sent, not now. `send()` answers with what happened;
  // everything that needs the controller's own state is done here, after.
  async attempt() {
    const status = document.getElementById(this.statusIdValue)
    this.setStatus(status && status.hasAttribute("data-live") ? this.constructor.texts.savingLive : this.constructor.texts.saving)

    const outcome = await enqueue(() => this.send())

    switch (outcome) {
      case "retry":
        this.scheduleRetry()
        return
      case "signedOut":
        this.retryCount = 0
        this.busy = false
        this.setStatus(this.constructor.texts.signedOut)
        return
      case "conflict":
        // 409: the server refused this save because the record changed since
        // the form loaded (`Admin::AutosaveResponses#refuse_stale_autosave`).
        // It is FINAL, unlike every other failure here: no retry (the same
        // request would be refused again), and no further saves from this
        // form at all (`paused`), because the editor's text on screen is the
        // only copy of what they typed and any later save would be refused
        // too -- or, were the base ever advanced, would overwrite the other
        // editor's work. The stream (rendered in `send`) puts the "Changed
        // elsewhere" status and bar up; the fields are left exactly as they
        // are so the text can be copied, and Reload (a full page visit)
        // discards it. No base is read out of the answer, there being none
        // -- a refusal never vouches for a newer one. A paused form drops out
        // of the queue by simply never queueing again; other forms go on.
        this.paused = true
        this.pending = false
        this.retryCount = 0
        this.busy = false
        if (this.timer) clearTimeout(this.timer)
        this.timer = null
        return
      default:
        this.retryCount = 0
        this.busy = false
        // A newer edit made while this save was queued or in flight: its own
        // save follows, and (queued behind this one) reads the bases this
        // answer just wrote.
        if (this.pending) this.trigger()
    }
  }

  // The request, run alone by the queue. Returns "done" (a real answer was
  // received and rendered), "conflict" (a 409, rendered), "signedOut" or
  // "retry". It never throws.
  async send() {
    let response
    try {
      response = await fetch(this.element.action, {
        method: "PATCH",
        body: new FormData(this.element),
        headers: this.requestHeaders(),
        // A fetch that never answers must not hold the whole screen's queue.
        signal: AbortSignal.timeout(30000)
      })
    } catch (error) {
      return "retry"
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
    if (response.redirected) return "signedOut"

    // Anything else has to actually be the Turbo Stream response this
    // controller's own endpoints answer with -- the status texts only ever
    // reach the page through one of *those* streams (`Admin::AutosaveResponses
    // #autosave_stream`), so a response with some other content type, or a
    // status outside this endpoint's own documented range (2xx a save; 409 a
    // refused stale save; 410 "this block was deleted"; 422 a failed save's
    // own per-field errors) was never actually processed by the endpoint at
    // all -- a 500, a proxy's own error page, ... -- and takes the same retry
    // path a network error does, rather than being handed to
    // `Turbo.renderStreamMessage` as if it were one.
    if (!this.isTurboStreamAnswer(response)) return "retry"

    const text = await response.text()

    if (response.status === 409) {
      Turbo.renderStreamMessage(text)
      return "conflict"
    }

    // A 422 with a body is still a real answer at this point -- the
    // server-rendered stream already turns that into the "Couldn't save"
    // status and the per-field errors, so it counts as success from *this*
    // controller's own point of view (nothing left to retry).
    //
    // `Turbo.renderStreamMessage` doesn't patch the DOM synchronously -- its
    // `<turbo-stream>` elements apply on the *next animation frame* -- so the
    // next request (queued behind this one, or this form's own `pending`
    // retrigger) would otherwise build its `FormData` from the *stale*
    // `base_updated_at` hidden field this very response is about to refresh,
    // and be refused as "changed elsewhere" against nothing but itself.
    // `syncBases` reads the fresh values straight out of the response text and
    // writes them onto the live fields synchronously, right now; Turbo's own
    // (later) replace of the same element re-applies the identical value.
    //
    // Matched by id, not just by name: a block card's response may also carry
    // the page settings form's own base (the block write touched the page --
    // `Admin::ContentBlocksController#page_base_streams`), and taking the
    // first `base_updated_at` in the response would hand this card the page's
    // value instead of its own. The page base is applied too because the next
    // request sends it as `X-Page-Base-Updated-At` (`#requestHeaders`).
    const ownBase = this.element.querySelector('[name="base_updated_at"]')
    syncBases(text, [ ownBase?.id, this.hasPageBaseIdValue && this.pageBaseIdValue ].filter(Boolean))

    Turbo.renderStreamMessage(text)
    return "done"
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
      this.setStatus(this.constructor.texts.offline, { retry: true })
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
  // of the four statuses those endpoints ever send: a plain 2xx success,
  // 409 (a stale base, refused), 410 (a destroyed block/post, "This block
  // was deleted"), or 422 (a failed save's own per-field errors). Anything else -- wrong content
  // type, or a status this endpoint never documents sending at all -- is
  // treated as "no real answer arrived," not as this save having somehow
  // succeeded.
  isTurboStreamAnswer(response) {
    const contentType = response.headers.get("Content-Type") || ""
    const answeredStatus = (response.status >= 200 && response.status < 300) || response.status === 409 || response.status === 410 || response.status === 422

    return answeredStatus && contentType.includes("text/vnd.turbo-stream.html")
  }

  // `retry: true` appends the Retry button of `Admin::SaveStatusComponent`'s
  // offline state. The status line sits in the record header, outside this
  // controller's form, so a `data-action` on the button would never reach
  // it: the listener is bound here instead.
  setStatus(text, { retry = false } = {}) {
    const status = document.getElementById(this.statusIdValue)
    if (!status) return

    status.textContent = text
    if (!retry) return

    const button = document.createElement("button")
    button.type = "button"
    button.className = "cursor-pointer underline hover:text-ink"
    button.textContent = "Retry"
    button.addEventListener("click", () => this.saveNow())
    status.append(button)
  }
}
