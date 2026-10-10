import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { messages } from "i18n/messages"
import { currentGeneration, enqueue, isCurrentGeneration, registerForm, syncBases, unregisterForm } from "autosave/queue"

// Each autosave form's SAVE STATE, by form ELEMENT:
// - `saved`: what the server holds of it -- the signature (`#signature`) the
//   form was first rendered with, then whatever its last successful save sent;
// - `sent`: the signature of the last request that got an answer;
// - `paused`: a 409 ended this form's saves until Reload (see `attempt`);
// - `failed`: the last answer was not a success.
// Kept here rather than on the controller because a form's element is
// disconnected and connected again whenever its card is moved in the DOM (a
// block drag, Move up/down), and `connect` must not start over:
// - taking what the form holds at THAT moment for saved would make an edit
//   still inside its debounce -- whose timer `disconnect` has just cleared --
//   compare "unchanged" for good, never to be sent (final fix wave 1, ledger
//   m2);
// - forgetting `paused` would let a card that was refused as "Changed
//   elsewhere" save again after a drag -- its next save refused again, or,
//   were its base ever fresh, an overwrite of the other editor's work -- and
//   forgetting `failed` would hide an unsaved card from a header action's
//   "your last change wasn't saved" (follow-up N4).
// A form rendered anew (a stream replacing the card, a page render) is a new
// element and starts clean, from what it was rendered with, as before.
const saveStates = new WeakMap()

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
//
// Two rules keep a save from being sent, or drawn, where it does not belong
// (fix round 4):
// - a save belongs to the PAGE THIS FORM WAS RENDERED ON (`generation`, read
//   in `connect`), whenever it is queued. A form outlives its page by a
//   moment: as Turbo swaps the body the field that still holds focus gets a
//   `focusout`, and `saveNow` runs on the outgoing form. That save is still
//   sent when there is something to send (an edit inside its debounce is not
//   lost to Back/Forward), but its answer draws nothing and writes no base
//   into the new document (`send`'s "stale");
// - nothing is sent when the form holds exactly what its last successful
//   save sent (`unchanged`). Leaving a field without having typed, a flush
//   before a header action, that teardown `focusout`: none of them is an
//   edit, and after Publish the last would be a save on the base Publish
//   just moved -- a 409 about nothing. What the server holds is remembered
//   per form element (`saveStates` above), so it survives the form being
//   moved in the DOM.
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
  // they describe the request *not landing* at all. Each reads exactly like
  // the component's own matching state because it IS the same key
  // (`admin.components.ui.save_status.*`, handed over on <body> by
  // `Admin::MessagesHelper::SCRIPT_MESSAGES`): `saving`, `saving_live`,
  // `retrying`, `offline`, `signed_out` (even though that one's never
  // actually rendered by a server response either -- see the component's
  // own comment for why it's still a named state there) and `retry`.
  //
  // `saving_live` is the same line for a live record, whose edits go
  // straight to the site: the status element says so with `data-live`
  // (`Admin::SaveStatusComponent`'s `live:`). `offline` ends in a Retry
  // button (`setStatus` builds it), which is why its text stops at "· ".
  text(key) { return messages(this.element).t(key) }

  // Backoff after a failed attempt (spec §6.1/global constraints): 1s, 3s,
  // then 9s, then give up and show the offline state until the next edit.
  static retryDelays = [ 1000, 3000, 9000 ]

  connect() {
    this.timer = null
    this.busy = false
    this.pending = false
    this.retryCount = 0
    // The page this form belongs to.
    this.generation = currentGeneration()
    // `saved`, `sent`, `paused` (set by a 409: this form's saves are over
    // until the page is reloaded) and `failed` (the last answer was not a
    // success -- refused, invalid, offline, signed out: `clean()` reports it
    // to `drained()`, see `autosave/queue.js`) live with the element, see
    // `saveStates`.
    const reconnected = saveStates.has(this.element)
    if (!reconnected) saveStates.set(this.element, { saved: this.signature(new FormData(this.element)), sent: null, paused: false, failed: false })
    registerForm(this)
    // Moved in the DOM while it held an UNSENT edit: the debounce that
    // `disconnect` cleared starts over. Not for a paused form (`queue`
    // refuses it), and not for one whose last answer was a failure about
    // exactly what it holds now -- an invalid field, a refusal: sending the
    // same thing again because the card was dragged would only repeat the
    // error. (That form still sends on its next edit, as always.)
    if (reconnected && !this.unchanged() && !this.refusedAsIs()) this.queue()
  }

  get state() { return saveStates.get(this.element) }
  get saved() { return this.state.saved }
  set saved(signature) { this.state.saved = signature }
  get paused() { return this.state.paused }
  set paused(value) { this.state.paused = value }
  get failed() { return this.state.failed }
  set failed(value) { this.state.failed = value }

  // The form holds exactly what its last answered request sent, and that
  // answer was a failure.
  refusedAsIs() {
    return this.failed && this.signature(new FormData(this.element)) === this.state.sent
  }

  disconnect() {
    unregisterForm(this)
    if (this.timer) clearTimeout(this.timer)
    // A pending retry belongs to a form that is gone (the page changed under
    // it): it must not re-enter the queue on the next page.
    if (this.retryTimer) clearTimeout(this.retryTimer)
  }

  queue() {
    if (this.paused) return
    if (this.timer) clearTimeout(this.timer)
    this.timer = setTimeout(() => this.trigger(), this.debounceValue)
  }

  // Called by `drained()` (`autosave/queue.js`) before a header action or a
  // visit: an edit still inside its debounce is sent now, and so is one
  // typed while a save was in flight (`saveNow` -> `pending`, which sends it
  // as soon as that save is answered). Pressing a button normally blurs the
  // field first (`focusout` -> `saveNow`), but not on every path, and never
  // helps an edit made while this form was busy.
  //
  // A retry waiting out its backoff is sent now rather than waited for -- but
  // only ONCE per drain (`drain` is that `drained()` call's own token). The
  // drain calls this on every pass, a few milliseconds apart: re-firing the
  // retry each time burned all three in about 100 ms, so a brief network blip
  // plus a link click gave up on the save. After its one early attempt the
  // backoff timers run their course, under the drain's own deadline.
  flush(drain) {
    if (this.timer) this.saveNow()
    if (this.retryTimer && this.retryFlushedIn !== drain) {
      this.retryFlushedIn = drain
      clearTimeout(this.retryTimer)
      this.retryTimer = null
      this.attempt()
    }
  }

  // Anything of this form's still to be sent or answered: a debounced edit,
  // or a queued or in-flight save (`busy` also covers the retry backoff). An
  // edit waiting behind a save (`pending`) only ever exists while `busy`, and
  // is deliberately not counted on its own: every branch that ends an attempt
  // without sending it clears it, and were one ever missed, a stuck `pending`
  // would make every visit and header action from this screen wait out the
  // drain's whole limit for a save nobody is going to send.
  outstanding() {
    return Boolean(this.timer || this.busy)
  }

  // Whether the last outcome was fine: not paused by a 409, not a refused,
  // invalid, offline or signed-out save.
  clean() {
    return !this.paused && !this.failed
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

    // Nothing to send (see the class comment). A form whose last save failed
    // always sends: the server may not hold what `saved` says, the Retry
    // button means "send it again", and putting an invalid field back the way
    // it was has to clear the error and the form's unclean state.
    if (this.unchanged()) return

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
    this.setStatus(status && status.hasAttribute("data-live") ? this.text("components.ui.save_status.saving_live") : this.text("components.ui.save_status.saving"))

    const outcome = await enqueue((isCurrent) => this.send(isCurrent), { generation: this.generation })

    switch (outcome) {
      case "stale":
        // This form's page has been replaced -- while the save was in flight
        // or waiting its turn, or before it was even queued (a restoration
        // visit, which cannot be drained first; the `focusout` of a page
        // being torn down): the answer belongs to no live document. Nothing
        // to retry, report or render. (The write itself has happened.)
        this.pending = false
        this.busy = false
        return
      case "retry":
        if (!this.element.isConnected) {
          this.pending = false
          this.busy = false
          return
        }
        this.scheduleRetry()
        return
      case "signedOut":
        // No follow-up either: it would only be redirected again (`pending`
        // is cleared with `busy` in every branch that sends nothing more).
        this.failed = true
        this.pending = false
        this.retryCount = 0
        this.busy = false
        this.setStatus(this.text("components.ui.save_status.signed_out"))
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
        this.failed = true
        this.pending = false
        this.retryCount = 0
        this.busy = false
        if (this.timer) clearTimeout(this.timer)
        this.timer = null
        return
      default:
        this.failed = !this.lastAnswerOk
        this.retryCount = 0
        this.busy = false
        // A newer edit made while this save was queued or in flight: its own
        // save follows, and (queued behind this one) reads the bases this
        // answer just wrote. Not for a form that has left the document in the
        // meantime (a card re-rendered or removed by a stream).
        const followUp = this.pending && this.element.isConnected
        this.pending = false
        if (followUp) this.trigger()
    }
  }

  // The request, run alone by the queue. Returns "done" (a real answer was
  // received and rendered), "conflict" (a 409, rendered), "signedOut",
  // "retry", or "stale" (the page changed while it was in flight: nothing
  // rendered). It never throws: the body read is inside a `try` too, since the
  // 30 s timeout also aborts a body still being read, and a rejection there
  // would leave `busy` set -- that form reading "Saving…" and never saving again.
  async send(isCurrent) {
    const body = new FormData(this.element)
    const sent = this.signature(body)
    let response
    try {
      response = await fetch(this.element.action, {
        method: "PATCH",
        body,
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
    // status outside this endpoint's own documented range (2xx a save; 403 a
    // save refused for want of permission; 409 a refused stale save; 410
    // "this block was deleted"; 422 a failed save's own per-field errors) was
    // never actually processed by the endpoint at
    // all -- a 500, a proxy's own error page, ... -- and takes the same retry
    // path a network error does, rather than being handed to
    // `Turbo.renderStreamMessage` as if it were one.
    if (!this.isTurboStreamAnswer(response)) return "retry"

    let text
    try {
      text = await response.text()
    } catch (error) {
      return "retry"
    }

    // This form's page is gone: the answer's bases and streams belong to a
    // document that no longer exists (the new one has fields with the same
    // ids).
    if (!isCurrent()) return "stale"

    this.lastAnswerOk = response.ok
    this.state.sent = sent
    if (response.ok) this.saved = sent

    if (response.status === 409) {
      Turbo.renderStreamMessage(text)
      return "conflict"
    }

    // A 422 with a body is still a real answer at this point -- the
    // server-rendered stream already turns that into the "Couldn't save"
    // status and the per-field errors, so it counts as success from *this*
    // controller's own point of view (nothing left to retry). So is a 403:
    // its stream says "Not saved — you don't have permission to change this"
    // and raises the error toast, and the same request sent again would be
    // refused again. Either leaves the form unclean (`failed`, set by
    // `attempt` from `lastAnswerOk`).
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

  // What the form would submit, as one comparable string. The base is left
  // out: it is bookkeeping the answers rewrite, not something the editor
  // changed. A file is named by what identifies it; a file input with NO file
  // chosen is "" -- `FormData` hands that over as an empty, nameless `File`
  // whose `lastModified` is the moment it was read, so by its own fields it
  // would differ from itself every time, and a form with one (Settings, with
  // its logo) would never be "unchanged" (ledger m3).
  signature(data) {
    return JSON.stringify(Array.from(data.entries())
      .filter(([ name ]) => name !== "base_updated_at")
      .map(([ name, value ]) => [ name, this.comparable(value) ]))
  }

  comparable(value) {
    if (!(value instanceof File)) return value
    if (value.size === 0 && value.name === "") return ""
    return `${value.name}:${value.size}:${value.lastModified}`
  }

  // True when the form holds exactly what its last successful save sent (or
  // what it was rendered with) and that save was not a failure.
  unchanged() {
    return !this.failed && this.signature(new FormData(this.element)) === this.saved
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
      this.setStatus(this.text("components.ui.save_status.offline"), { retry: true })
      this.failed = true
      // Given up: an edit typed during the backoff waits for Retry or the
      // next edit like everything else in the form, it is not "about to be
      // sent" (`outstanding`).
      this.pending = false
      this.retryCount = 0
      this.busy = false
      return
    }

    this.setStatus(this.text("components.ui.save_status.retrying"))
    const delay = delays[this.retryCount]
    this.retryCount += 1
    // `busy` stays true across the wait: an edit that lands mid-backoff
    // still only ever queues (see the class comment above), it doesn't
    // jump the line and fire its own request ahead of the scheduled retry.
    this.retryTimer = setTimeout(() => {
      this.retryTimer = null
      this.attempt()
    }, delay)
  }

  // True for exactly the responses this controller's own PATCH endpoints
  // (`Admin::AutosaveResponses#autosave_stream`'s callers) actually answer
  // with (final-fixes round, finding 4) -- a real Turbo Stream body, at one
  // of the five statuses those endpoints ever send: a plain 2xx success,
  // 403 (refused for want of permission, `Admin::AutosaveResponses
  // #autosave_status` -- a tab left open while the editor's rights changed),
  // 409 (a stale base, refused), 410 (a destroyed block/post, "This block
  // was deleted"), or 422 (a failed save's own per-field errors). Anything
  // else -- wrong content type, or a status this endpoint never documents
  // sending at all -- is treated as "no real answer arrived," not as this
  // save having somehow succeeded. (403 was missing from this list until
  // final fix wave 1, ledger m7: a refused save was retried three times as
  // if the network had failed and ended in "NOT SAVED · Retry", which could
  // never succeed and never said why. A 403 that is NOT a stream -- the
  // forbidden page of a whole admin area -- still is no answer.)
  isTurboStreamAnswer(response) {
    const contentType = response.headers.get("Content-Type") || ""
    const answeredStatus = (response.status >= 200 && response.status < 300) || [ 403, 409, 410, 422 ].includes(response.status)

    return answeredStatus && contentType.includes("text/vnd.turbo-stream.html")
  }

  // `retry: true` appends the Retry button of `Admin::SaveStatusComponent`'s
  // offline state. The status line sits in the record header, outside this
  // controller's form, so a `data-action` on the button would never reach
  // it: the listener is bound here instead.
  //
  // Nothing is written once this form's page has been replaced (ledger m4):
  // the page that came in has a status line with the same id, and a
  // "Saving…" written there by a save of the OUTGOING form (the `focusout` of
  // a page being torn down) would stay for good -- that save's answer is
  // drawn nowhere.
  setStatus(text, { retry = false } = {}) {
    if (!isCurrentGeneration(this.generation)) return
    const status = document.getElementById(this.statusIdValue)
    if (!status) return

    status.textContent = text
    if (!retry) return

    const button = document.createElement("button")
    button.type = "button"
    button.className = "cursor-pointer underline hover:text-ink"
    button.textContent = this.text("components.ui.save_status.retry")
    button.addEventListener("click", () => this.saveNow())
    status.append(button)
  }
}
