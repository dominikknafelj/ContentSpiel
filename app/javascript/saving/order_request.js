// The request behind a drag: a block move (`admin--editor--blocks#move`) and a
// page tree move (`admin--pages--tree#save`). Both are hand-built `fetch`es -- a drop
// is no form submission, so Turbo Drive sends nothing -- that ask for a Turbo
// Stream and render it themselves. This module is the part the two share:
// deciding whether what came back IS that stream.
//
// WHY. `fetch` resolves for anything that answers, and both controllers used
// to hand whatever arrived to `Turbo.renderStreamMessage` and swallow every
// error:
// - an expired session answers with a redirect to sign-in, which `fetch`
//   follows: the "answer" was the sign-in page's HTML, appended to the
//   document as if it were a stream;
// - a 500, a proxy's error page or a network failure rendered nothing and
//   said nothing, and the card or row stayed where the editor had dropped it
//   -- an order on screen that was never saved, looking exactly like one that
//   was.
// `admin--saving--autosave#send` already tells these apart for a form's save
// (`response.redirected`, `isTurboStreamAnswer`, its retry and signed-out
// states); this is the same judgement for a drop, which has no status line to
// write into and nothing to retry: the dragged thing is put BACK where it was
// (each controller knows how) and an error toast says why.
//
// The queue (`saving/queue.js`) is not this module's business: each caller
// still runs `sendOrder` inside its own `enqueue` task, reads its bases at
// send time and writes the answer's back (`syncBases`) exactly as before.
// `sendOrder` never throws, so the task always ends and the slot is released.

import { messages } from "i18n/messages"

// The texts of the toast are the page's messages (`i18n/messages.js`).
// `signedOut` is the autosave status line's own key
// (`components.ui.save_status.signed_out`, `Admin::Ui::SaveStatusComponent`'s
// `:signed_out`): the same thing happened, and the same thing fixes it.
const ORDER_MESSAGES = {
  failed: "components.ui.toast.order_failed",
  signedOut: "components.ui.save_status.signed_out"
}

// Sends the PATCH and answers with one of:
// - `{ outcome: "answered", ok, text }`: a Turbo Stream body, to be rendered.
//   `ok` is the status: both endpoints also answer a REFUSED move with a
//   stream (403, 404, 422 -- the reason, and for the tree the tree as it
//   really is), which is a real answer about an order that was not saved;
// - `{ outcome: "signedOut" }`: the request was redirected. Neither endpoint
//   redirects on its own; only `Authentication#request_authentication` does;
// - `{ outcome: "failed" }`: no answer (offline, the 30 s timeout -- which also
//   cuts a body still being read), or one that is not a Turbo Stream at all
//   (a 500, an error page): the endpoint never processed the move.
// The timeout is what keeps a request that never answers from holding the
// whole screen's queue.
export async function sendOrder(url, { headers, body }) {
  try {
    const response = await fetch(url, { method: "PATCH", headers, body, signal: AbortSignal.timeout(30000) })
    if (response.redirected) return { outcome: "signedOut" }
    if (!(response.headers.get("Content-Type") || "").includes("text/vnd.turbo-stream.html")) return { outcome: "failed" }

    return { outcome: "answered", ok: response.ok, text: await response.text() }
  } catch {
    return { outcome: "failed" }
  }
}

// An error toast made in the browser, for a request that got no answer the
// server could have put one into. The markup is the server's own: the layout
// holds one `Admin::Ui::ToastComponent` (kind `error`, so `role=alert` and no
// auto-hide) in `<template id="toast-error-template">`, and this clones it,
// writes the message as text and appends it to `#toasts`, where
// `admin--ui--toast` takes over like for any other toast.
//
// `id` makes it one toast per cause: dropping again while still offline
// replaces the toast instead of stacking three of the same sentence.
export function orderErrorToast(outcome, id) {
  errorToast(messages(document.body).t(ORDER_MESSAGES[outcome] || ORDER_MESSAGES.failed), id)
}

// The same toast with a caller's own sentence, for a drop that was never
// sent at all (`admin--editor--blocks#move`, a block whose form holds an edit that
// was not saved): one copy of the cloning.
export function errorToast(text, id) {
  const template = document.getElementById("toast-error-template")
  const region = document.getElementById("toasts")
  const toast = template?.content.firstElementChild?.cloneNode(true)
  if (!toast || !region) return

  toast.id = id
  toast.querySelector("span").textContent = text
  document.getElementById(id)?.remove()
  region.append(toast)
}

// Resolves once the streams of an answer the caller has JUST handed to
// `Turbo.renderStreamMessage` are in the page. Turbo appends the answer's
// `<turbo-stream>` elements at once but performs each one's action after the
// next repaint (`StreamElement#render`, turbo-rails 2.0.23; a timer instead
// when the tab is hidden), so this waits for that repaint and the task after
// it -- the end of `streamRenders().applied` in `saving/queue_core.js`,
// which has to recognise an answer Turbo renders; here the caller rendered
// it, a line earlier, and Turbo's frame callback is ahead of this one.
//
// For a caller inside its `enqueue` task whose answer changes what the next
// task reads from the page (ledger b6, for a drop): a block moved between
// containers is redrawn by its answer, and a refused move's answer redraws
// the list.
export function streamsApplied() {
  return new Promise((resolve) => {
    const afterTask = () => setTimeout(resolve, 0)
    if (document.visibilityState === "hidden") setTimeout(afterTask, 0)
    else requestAnimationFrame(afterTask)
  })
}
