// The write queue itself: one write at a time (`acquire`, `enqueue`,
// `holdTurboRequest`), each answer's bases written back before the next
// request is sent (`syncBases`), and `drained()`, the promise everything that
// replaces an editor waits on. `saving/queue.js` says WHY and has "THE
// RULE" and the module map; the state this file works on -- the chain, the
// counters, the registered forms, the page generations -- is in
// `saving/queue_state.js`.
//
// This module registers no listener as it is evaluated. The ones it adds
// later come and go with what they serve: `beforeunload` with the first and
// last registered form (`registerForm`), and a held Turbo request's three
// (`holdTurboRequest`, `streamRenders`).
//
// Failure never blocks the queue. A task that throws releases its slot
// (`finally`); a fetch that never answers is cut by the caller's own timeout;
// a held Turbo request releases when its answer arrives OR errors OR is
// aborted OR its form leaves the DOM (see `holdTurboRequest`), and after
// `HOLD_LIMIT_MS` regardless.
import {
  addForm, chain, chainOnto, currentGeneration, formCount, isCurrentGeneration, queuedWrites, registeredForms,
  removeForm, writeLeft, writeQueued
} from "saving/queue_state"

const HOLD_LIMIT_MS = 30000
export const DRAIN_LIMIT_MS = 10000
const STREAM_RENDER_LIMIT_MS = 1000

// Autosave controllers register themselves so `drained()` can ask them to
// flush and report whether they ended clean. A form offers `flush(drain)`,
// `outstanding()` (debounced, queued, in flight, retrying) and `clean()`.
//
// The first form to register also puts up THE UNLOAD GUARD below, and the
// last to leave takes it down: a screen with no autosave form has nothing of
// this module's to lose (and the explicit-save screens have their own,
// `admin--saving--save-bar`).
export function registerForm(form) {
  if (formCount() === 0) window.addEventListener("beforeunload", guardUnload)
  addForm(form)
}
export function unregisterForm(form) {
  removeForm(form)
  if (formCount() === 0) window.removeEventListener("beforeunload", guardUnload)
}

const idle = () => queuedWrites() === 0 && !registeredForms().some((form) => form.outstanding())

// Nothing queued, in flight or waiting to be sent, and every form's last
// outcome clean.
export function settled() { return idle() && registeredForms().every((form) => form.clean()) }

// THE UNLOAD GUARD. Everything else in the write queue is about Turbo
// replacing the editor, which it can hold until the queue has drained. Closing the
// tab, reloading it or typing another address cannot be held: the document
// is gone as soon as the handler returns, a debounce timer never fires and a
// request on the wire may be cut. All there is, is the browser's own "Leave
// site?" dialog, which `preventDefault()` on `beforeunload` asks for. So it
// is asked for exactly when leaving would lose something -- when the screen
// is not `settled()`:
// - a write is queued or in flight, or a form holds an edit inside its
//   debounce or is waiting to retry (`busy()`);
// - or a form's last save did not land -- paused by a 409 "Changed
//   elsewhere", refused, invalid, given up on after the retries, signed out
//   (`clean()` false). The typed text is then in the page and nowhere else;
//   the 409 bar says in so many words that it is still there to be copied.
// Never on a clean screen, and never once a save has been answered with a
// success: asked every time, the dialog would be dismissed unread the one
// time it mattered. Nothing is sent from here -- a request started while the
// page unloads is not reliably delivered, and the prompt is what gives the
// debounce and the queue the time to finish when the editor chooses to stay.
//
// A Turbo visit fires no `beforeunload`, so the Reload link of the 409 bar
// (how that text is given up on purpose) and every link inside CS Studio
// stay under "THE RULE" (`queue.js`) alone.
function guardUnload(event) {
  if (!settled()) event.preventDefault()
}

// True while any write is queued, in flight, or still held by a form.
export function busy() { return !idle() }

// Resolves when `promise` does or after `ms`, whichever is first.
function within(promise, ms) {
  let timer
  const limit = new Promise((resolve) => { timer = setTimeout(resolve, Math.max(ms, 0)) })
  return Promise.race([ promise, limit ]).finally(() => clearTimeout(timer))
}

// See "THE RULE" (`queue.js`). Never waits longer than `limit` in all: the wait for
// the chain itself is raced against what is left of it, so a request that
// does not answer cannot hold the caller past the deadline. Whatever is left
// behind then still runs, in order, and finds `isCurrent()` false once the
// page is gone. `token` is this call's own: a form uses it to send a
// retry that is waiting out its backoff at most ONCE per drain (see
// `admin--saving--autosave#flush`).
//
// It NEVER REJECTS (follow-up N3). Everything that waits on it holds something
// of Turbo's -- a visit, a frame's request or render, a form submission -- and
// lets it go in a `then`: a rejection would strand that for good, the editor
// left on a page whose links and buttons do nothing. A form whose `flush`
// throws is skipped (its edit is then only sent by its own timer); anything
// else that throws ends the wait at once, reported as unclean.
export function drained(options) {
  return drain(options).catch(() => ({ clean: false, timedOut: false }))
}

async function drain({ limit = DRAIN_LIMIT_MS } = {}) {
  const deadline = Date.now() + limit
  const token = {}
  let timedOut = false

  for (;;) {
    registeredForms().forEach((form) => { try { form.flush(token) } catch { /* see `drained` */ } })
    await within(chain(), deadline - Date.now())
    await new Promise((resolve) => setTimeout(resolve, 25))
    if (idle()) break
    if (Date.now() >= deadline) { timedOut = true; break }
  }

  return { clean: !timedOut && registeredForms().every((form) => form.clean()), timedOut }
}

// Resolves with a `release` function once every earlier holder has released.
// The next holder waits for exactly this one's release.
export function acquire() {
  let release
  const released = new Promise((resolve) => { release = resolve })
  writeQueued()
  const turn = chain().then(() => release)
  chainOnto(chain().then(() => released).then(() => { writeLeft() }))
  return turn
}

// Runs `task` (an async function, handed `isCurrent`) alone: returns its
// result or rethrows its error -- and in every case lets the next one go.
// `generation` is the page the task belongs to (the caller's
// `currentGeneration()` at connect -- see "PAGE GENERATIONS" in
// `queue_state.js`); left out, it is
// the page showing as the task is queued.
export async function enqueue(task, { generation: belongsTo = currentGeneration() } = {}) {
  const release = await acquire()
  try {
    return await task(() => isCurrentGeneration(belongsTo))
  } finally {
    release()
  }
}

// Copies each named base field's fresh value out of a Turbo Stream answer onto
// the live hidden field, synchronously. Matched by id (a block's answer may
// carry both its own base and the page form's).
export function syncBases(streamText, ids) {
  const templates = Array.from(new DOMParser().parseFromString(streamText, "text/html").querySelectorAll("template"))
  for (const id of ids) {
    const field = document.getElementById(id)
    if (!field) continue
    const fresh = templates
      .map((template) => template.content.querySelector(`[name="base_updated_at"][id="${id}"]`))
      .find((candidate) => candidate)?.value
    if (fresh) field.value = fresh
  }
}

// Lets a caller wait until Turbo has APPLIED a Turbo Stream answer it is
// about to render itself (see `holdTurboRequest`). Turbo appends the answer's
// `<turbo-stream>` elements to the document; each dispatches
// `turbo:before-stream-render` as it connects -- all of them in that one
// append -- and performs its action after the next repaint (`StreamElement
// #render`, turbo-rails 2.0.23; a timer instead when the tab is hidden).
// `applied(text)` resolves once every stream element OF THAT ANSWER has been
// seen since this was created, plus that repaint and the task after it.
//
// "Of that answer" (follow-up N5): the event is heard on `document`, where
// every stream on the page passes -- a translation suggestion arriving in the
// same moment (`admin--translate` renders its own), a toast. Counting events
// let a foreign stream stand in for the held answer's and release the slot
// before the card was in the list. The held answer is rendered by Turbo, so
// its elements cannot be tagged beforehand; they are recognised by their
// markup instead: each stream seen is kept as its `outerHTML`, and the wait
// ends when the answer's own streams (parsed from the same text, so the same
// markup) are all among them, each matched once. Turbo may render before or
// after this caller has read the body, hence the list rather than a count
// from "now".
//
// Never longer than `STREAM_RENDER_LIMIT_MS`: an answer Turbo does not render
// after all (the form's page is gone) must not hold the queue.
function streamRenders() {
  const seen = []
  let check = () => {}
  const note = (event) => { seen.push(event.target.outerHTML); check() }
  document.addEventListener("turbo:before-stream-render", note)

  return {
    stop: () => document.removeEventListener("turbo:before-stream-render", note),
    async applied(streamText) {
      const expected = Array.from(new DOMParser().parseFromString(streamText, "text/html").querySelectorAll("turbo-stream"), (stream) => stream.outerHTML)
      if (expected.length === 0) return

      await within(new Promise((resolve) => {
        check = () => {
          const pool = seen.slice()
          const all = expected.every((markup) => {
            const index = pool.indexOf(markup)
            if (index < 0) return false
            pool.splice(index, 1)
            return true
          })
          if (all) resolve()
        }
        check()
      }), STREAM_RENDER_LIMIT_MS)
      await new Promise((resolve) => (document.visibilityState === "hidden" ? setTimeout(resolve, 0) : requestAnimationFrame(resolve)))
      await new Promise((resolve) => setTimeout(resolve, 0))
    }
  }
}

// For a Turbo-driven block request (add, duplicate, delete, the Undo toast;
// `turbo:before-fetch-request`) and the tree move's Undo: holds it until the
// queue is free, lets `before` set its headers at send time, then keeps the
// queue's slot until the answer's bases (`baseIds`) and its streams are
// applied.
//
// When the slot is released -- checked against Turbo's own source (turbo-rails
// 2.0.23), not assumed:
// - the answer arrives (`turbo:before-fetch-response`) AND, when it is a
//   Turbo Stream, Turbo has applied it (`streamRenders`; ledger b6). The bases
//   are in the hidden fields at once, but the stream itself -- the card an
//   Add or Duplicate inserts, the one a Delete removes, the list an Undo
//   re-renders -- is applied a frame later, and the next task may read the
//   DOM: a reorder lists the cards as it is SENT, and sent in that gap it
//   listed them without the new card (422, the unsaved order left on screen);
// - or the request errors (`turbo:fetch-request-error`);
// - the request is ABORTED. Turbo cancels the previous form submission when a
//   new one starts (`Navigator#submitForm`), and `FetchRequest#perform`
//   swallows the `AbortError` without dispatching any event, so the request's
//   own signal (`fetchOptions.signal`) is listened to;
// - those events are listened for on `document`, not on the form: Turbo's
//   `dispatch` sends an event to `document.documentElement` instead when the
//   target is no longer connected (the Undo toast auto-dismissed mid-request,
//   a card re-rendered by a predecessor's stream). For that case only, an
//   event is accepted as this request's by what identifies it: the answer by
//   its URL, or by being a redirected one (a block action answers with a
//   stream, but an expired session answers with a redirect to sign-in, whose
//   final URL is not the request's -- unmatched, the slot stayed held for the
//   whole `HOLD_LIMIT_MS`); the error by the request's own abort signal --
//   never "any event on the document element", which would also match
//   another request's;
// - `HOLD_LIMIT_MS` passes.
// `resume()` is always called, even if `before` throws, so Turbo's submission
// is never left waiting. A request whose page is gone (replaced while
// it waited) or that was already aborted just resumes at once, unmodified.
export function holdTurboRequest(event, { before = () => {}, baseIds = [] } = {}) {
  event.preventDefault()
  const target = event.target
  const request = event.detail
  const signal = request.fetchOptions?.signal
  const queuedUnder = currentGeneration()
  const url = request.url?.href

  acquire().then((release) => {
    if (signal?.aborted || !isCurrentGeneration(queuedUnder)) {
      release()
      request.resume()
      return
    }

    let finished = false
    const gone = () => !target.isConnected
    const isMyResponse = (e) => {
      if (e.target === target) return true
      const response = e.detail.fetchResponse?.response
      return gone() && e.target === document.documentElement && (response?.url === url || Boolean(response?.redirected))
    }
    const isMyError = (e) => e.target === target || (gone() && e.target === document.documentElement && e.detail.request?.abortSignal === signal)
    const finish = () => {
      if (finished) return
      finished = true
      clearTimeout(limit)
      document.removeEventListener("turbo:before-fetch-response", onResponse)
      document.removeEventListener("turbo:fetch-request-error", onError)
      signal?.removeEventListener("abort", finish)
      release()
    }
    const onResponse = async (responseEvent) => {
      if (!isMyResponse(responseEvent)) return
      // From now, before anything is awaited: Turbo reads the same body and
      // renders it on its own schedule.
      const renders = streamRenders()
      try {
        const response = responseEvent.detail.fetchResponse.response
        const text = await response.clone().text()
        if (isCurrentGeneration(queuedUnder)) syncBases(text, baseIds)
        if ((response.headers.get("Content-Type") || "").includes("text/vnd.turbo-stream.html")) await renders.applied(text)
      } finally {
        renders.stop()
        finish()
      }
    }
    const onError = (errorEvent) => { if (isMyError(errorEvent)) finish() }
    const limit = setTimeout(finish, HOLD_LIMIT_MS)

    document.addEventListener("turbo:before-fetch-response", onResponse)
    document.addEventListener("turbo:fetch-request-error", onError)
    signal?.addEventListener("abort", finish, { once: true })
    try {
      before(request)
    } finally {
      request.resume()
    }
  })
}
