// What waits for the write queue to drain before it replaces an editor
// ("THE RULE" in `saving/queue.js`, which also has the module map): a Turbo
// visit, a frame navigation inside `#content` -- its request, and its render,
// with the refetch of an answer that is older than a save -- and a Turbo form
// submission. One section each below, in that order; the frame's GET and the
// form submission share one `turbo:before-fetch-request` listener.
//
// The same listeners are where the promotion window opens and closes (the
// frame's GET going out, its render, a refused frame form): what the window
// is for and what is held in it is `saving/promotion_hold.js`; its record
// is in `saving/queue_state.js`, because this module is evaluated before
// `promotion_hold.js` and cannot import it (see the order in `queue.js`).
import { Turbo } from "@hotwired/turbo-rails"
import { busy, drained, DRAIN_LIMIT_MS } from "saving/queue_core"
import {
  formCount, frameFormWasRefused, frameRendered, promotionEnds, promotionOpen, promotionStarts, setFrameFormRefused,
  writeCount, PROMOTION_FETCH_LIMIT_MS, PROMOTION_LIMIT_MS
} from "saving/queue_state"

const VISIT_NOTE_LIMIT_MS = 2000

const isFrame = (element) => element?.localName === "turbo-frame"

// The frame a form's answer is rendered into, or null when the session's
// navigator submits it. See "WHAT IS HELD" in `promotion_hold.js`, whose
// `navigatorLevel` is the other reader; turbo-rails 2.0.23.
// (`data-turbo-frame="_parent"` is not modelled; CS Studio has none.)
export function frameFor(form, submitter) {
  const named = submitter?.getAttribute("data-turbo-frame") ?? form.getAttribute("data-turbo-frame")
  const own = form.closest("turbo-frame")
  if (own) {
    const id = named || own.getAttribute("target")
    if (own.disabled || id === "_top") return null
    const other = id ? document.getElementById(id) : null
    if (isFrame(other)) return other.disabled ? null : other
    return own
  }
  if (!named || named === "_top") return null
  const other = document.getElementById(named)
  return isFrame(other) && !other.disabled ? other : null
}

// A Turbo visit (sidebar link, locale switch, Reload) waits for the queue to
// drain first, so no edit still on its way is lost to the page replacing
// itself. Only when something IS outstanding: with nothing queued the visit
// goes straight on, so screens without autosave (and `admin--saving--save-bar`'s own
// before-visit guard) are untouched. After the drain the visit goes on
// whatever the outcome -- the editor chose to leave, and is never trapped on
// the page (a timeout, a refused or failed save still end in the visit; the
// 409 bar and the leave handling already say what was not saved). `reentry`
// lets the visit this handler starts through without being intercepted again.
//
// Two visits are never held, because holding one means issuing it again with
// `Turbo.visit(url)`, and each of them arrives WITH the answer Turbo already
// fetched -- a second fetch of a page that is, or is about to be, on screen:
// - the redirect that answers a Turbo form submission (`answered`, see
//   "TURBO FORM SUBMISSIONS" below). The flash -- the "Moved to trash · Undo"
//   toast, "Restored …" -- was spent on the first fetch;
// - the visit a `#content` frame navigation is promoted to (`promoted`, the
//   frame's own URL, noted as the frame is let render below). It replaces
//   nothing: the frame has rendered. Held, the page a tree link had just
//   loaded was loaded a second time, and the old page's answer drawn into it
//   in between (review B, M1). Normally nothing is outstanding by then anyway
//   -- the frame's request and render waited for the drain.
// Each note is the URL that visit will have. A note is spent on the next
// `turbo:before-visit`, whichever visit it is, and EXPIRES after
// `VISIT_NOTE_LIMIT_MS` (follow-up N2): Turbo proposes the visit within
// moments of the event the note is taken at, and not every such event is
// followed by one (a frame form re-rendered in place after a 422 is promoted
// to nothing new; a redirected submission inside a frame may end in the
// frame). A note left lying would excuse the editor's NEXT visit to exactly
// that URL from the drain. No note is taken without a URL (a frame with no
// `src`).
let reentry = false
const expectedVisits = { promoted: null, answered: null }
const noteTimers = {}
const absolute = (url) => { try { return new URL(url, document.baseURI).href } catch { return null } }
export function expectVisit(kind, url) {
  clearTimeout(noteTimers[kind])
  expectedVisits[kind] = url ? absolute(url) : null
  if (expectedVisits[kind]) noteTimers[kind] = setTimeout(() => { expectedVisits[kind] = null }, VISIT_NOTE_LIMIT_MS)
}

document.addEventListener("turbo:before-visit", (event) => {
  const expected = Object.values(expectedVisits).filter(Boolean)
  expectVisit("promoted", null)
  expectVisit("answered", null)
  if (expected.includes(absolute(event.detail.url))) return
  if (reentry || event.defaultPrevented || !busy()) return

  event.preventDefault()
  const url = event.detail.url
  drained().then(() => {
    reentry = true
    try {
      Turbo.visit(url)
    } finally {
      reentry = false
    }
  })
})

// FRAME NAVIGATIONS inside `#content` replace the editor exactly as a visit
// does (see "THE RULE" in `queue.js`), but Turbo fetches and renders the frame BEFORE it
// proposes the promoted visit, so the drain cannot hang on
// `turbo:before-visit`. It hangs on the frame's own two steps.
//
// 1. THE REQUEST (follow-up N1; the `window` listener further down, which
//    holds a GET carrying `Turbo-Frame: content` like it holds a write). The
//    link may lead back to the record that is open -- the open page's own row
//    in the tree is such a link. Were only the render held, the GET would go
//    out before the drain and answer with the record as it was BEFORE the
//    saves the render then waits for: the saved text gone from the field,
//    the old base in the form, the next edit a final 409. Held until
//    `drained()`, the answer is fetched after everything outstanding was
//    saved. While it waits the outgoing forms are connected, so `flush()`
//    sends debounced edits and a save's follow-up goes out. A prefetch
//    (`X-Sec-Purpose: prefetch`) is never held -- it replaces nothing -- and
//    a prefetched answer Turbo was about to reuse for a held request is
//    dropped: it was fetched on hover, before the drain. (The editors switch
//    link prefetching off altogether, `turbo-prefetch` in their head, for the
//    same reason on the visit path.)
//
// 2. THE RENDER (`turbo:before-frame-render`, cancelable, carries `resume`;
//    turbo-rails 2.0.23, `FrameController#allowsImmediateRender`). Two jobs:
//    - it is the page change (`frameRendered`, `queue_state.js`), counted just before it
//      happens, so the outgoing forms' late answers draw nothing into the
//      editor that comes in; and the promoted visit's URL is noted;
//    - an edit can still land while the request is on its way -- still being
//      saved as the answer arrives, or saved already. Either way the answer
//      in hand is STALE in the same way as above: fetched before that save.
//      `writeCount()` (every write queued, counted) is noted as the request goes
//      out (`frameRequestedAt`); a different count here, or a busy queue,
//      means stale. The render then waits for the drain, and the answer is
//      not rendered: the frame's URL is fetched again
//      (`fetchFrame`, a plain `fetch` with the same `Turbo-Frame` header)
//      and its `<turbo-frame id="content">` rendered in the stale one's
//      place (`event.detail.render` is wrapped at dispatch; Turbo takes the
//      renderer from the event synchronously). An edit landing during THAT
//      fetch gets one more round; after it a last drain, and the render goes
//      on whatever the outcome -- like a visit, the editor is never trapped.
//      If the second fetch fails or has no such frame (signed out, offline),
//      the answer Turbo has is rendered after all. A flash the first answer
//      relayed as a toast is not in the second: accepted, the edit matters
//      more. The promoted visit still carries the first answer, but it
//      renders nothing (`willRender: false`).
//
// With nothing outstanding neither step is touched. Only `#content`: the
// lazily loaded dialog frames (New page / New post), the ⌘K results and the
// media picker's library replace no editor.
async function fetchFrame(frame) {
  const url = frame.getAttribute("src")
  if (!url) return null

  try {
    const response = await fetch(url, {
      headers: { "Turbo-Frame": frame.id, Accept: "text/html, application/xhtml+xml" },
      signal: AbortSignal.timeout(DRAIN_LIMIT_MS)
    })
    if (!response.ok) return null
    return new DOMParser().parseFromString(await response.text(), "text/html").querySelector(`turbo-frame#${frame.id}`)
  } catch {
    return null
  }
}

let frameRequestedAt = null
document.addEventListener("turbo:before-frame-render", (event) => {
  const frame = event.target
  if (frame.id !== "content" || event.defaultPrevented) return

  const rendering = () => {
    frameRendered()
    expectVisit("promoted", frame.getAttribute("src"))
    // See "THE PROMOTION HOLD" (`promotion_hold.js`): from here to the
    // promoted visit's start.
    const promotes = Boolean(frame.getAttribute("src")) && !frameFormWasRefused()
    setFrameFormRefused(false)
    if (promotes) promotionStarts(PROMOTION_LIMIT_MS)
    else promotionEnds()
  }
  let fetchedAt = frameRequestedAt
  frameRequestedAt = null
  const stale = () => busy() || (fetchedAt !== null && fetchedAt !== writeCount())
  if (!stale()) return rendering()

  event.preventDefault()
  let fresh = null
  const render = event.detail.render
  event.detail.render = (current, answered) => render(current, fresh || answered)

  const settle = async () => {
    for (let round = 0; round < 2 && stale(); round += 1) {
      await drained()
      fetchedAt = writeCount()
      fresh = (await fetchFrame(frame)) || fresh
    }
    if (busy()) await drained()
  }
  settle().catch(() => {}).then(() => {
    rendering()
    event.detail.resume()
  })
})

// TURBO FORM SUBMISSIONS (final fix wave 1, ledger q1). A Turbo form
// submission made from a screen with autosave forms may replace the editor
// (most answer with a redirect), so the rule applies to every one of them, in
// two halves -- generally, not form by form:
//
// 1. It is not SENT while anything is outstanding. `turbo:before-fetch-request`
//    for a non-GET request is held until `drained()`, then resumed whatever
//    the outcome, after `DRAIN_LIMIT_MS` at the latest. On `window`, so it
//    runs after every listener on an element or on `document`: a request
//    `holdTurboRequest` already took (block add/duplicate/delete, the reorder
//    and tree Undo toasts -- which also need the page base) is
//    `defaultPrevented` by then and left to it. The editor header's five
//    actions drain earlier still, at `submit` (`admin--saving--queue-hold`), because
//    they also refuse to run after an unclean drain; this half only catches
//    what lands between their drain and their request.
//    (The same listener holds a `#content` frame's GET: "FRAME NAVIGATIONS",
//    step 1. Every other GET goes straight on.)
//
// 2. The visit its redirect ends in is not HELD. Turbo proposes that visit
//    with the answer it already has (`Navigator
//    #formSubmissionSucceededWithResponse`); held by the handler above it
//    would be issued again and fetched a second time, the flash spent on the
//    first. `turbo:submit-end` is dispatched BEFORE the visit is proposed
//    (the navigator awaits the body first), so the redirect's final URL is
//    noted there (`answered`) and that one visit let through. An edit that
//    lands between the submission and its answer is the price: its save
//    belongs to the page being replaced (sent if it was already on its way,
//    dropped if it was still inside its debounce).
//    The note cannot stick: it is replaced by every submission's end, spent
//    by the next `turbo:before-visit`, dropped by the next render (`queue.js`), and
//    expires on its own (see `expectVisit`).
window.addEventListener("turbo:before-fetch-request", (event) => {
  if (event.defaultPrevented) return
  const { fetchOptions } = event.detail
  const headers = fetchOptions?.headers || {}
  const get = String(fetchOptions?.method || "GET").toUpperCase() === "GET"
  const frameGet = get && headers["Turbo-Frame"] === "content" && headers["X-Sec-Purpose"] !== "prefetch"
  if (get && !frameGet) return

  if (frameGet) {
    // The answer has to be newer than every write so far. A prefetched one
    // (Turbo's `LinkPrefetchObserver` hands it over on this same event) was
    // fetched on hover: dropped wherever there is a form it could be older
    // than.
    if (formCount() > 0) delete event.detail.fetchRequest
    frameRequestedAt = writeCount()
    // See "THE PROMOTION HOLD" (`promotion_hold.js`): the fetch window.
    setFrameFormRefused(false)
    promotionStarts(PROMOTION_FETCH_LIMIT_MS)
  }
  if (!busy()) return

  event.preventDefault()
  drained().then(() => {
    if (frameGet) {
      frameRequestedAt = writeCount()
      // The limit counts from the request going out, not from the drain.
      if (promotionOpen()) promotionStarts(PROMOTION_FETCH_LIMIT_MS)
    }
    event.detail.resume()
  })
})

document.addEventListener("turbo:submit-end", (event) => {
  const { success, fetchResponse } = event.detail
  expectVisit("answered", success && fetchResponse?.redirected ? fetchResponse.location : null)
  // See "THE PROMOTION HOLD" (`promotion_hold.js`), "WHICH RENDERS ARE PROMOTED".
  const { formElement, submitter } = event.detail.formSubmission || {}
  if (success) setFrameFormRefused(false)
  else if (formElement && frameFor(formElement, submitter)?.id === "content") setFrameFormRefused(true)
})
