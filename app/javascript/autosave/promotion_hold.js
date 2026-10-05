// THE PROMOTION HOLD (round 3, final wave B, ledger C-Q1). A link into
// `#content` is a frame navigation that Turbo PROMOTES to a page visit once
// the frame has rendered (the frame carries `data-turbo-action="advance"`;
// `FrameController#proposeVisitIfNavigatedWithAction` arms
// `fetchResponseLoaded`, which `#loadFrameResponse` awaits after the render
// and which calls `session.visit(frame.src, { willRender: false, ... })`).
// That visit begins with `Navigator#startVisit` -> `Navigator#stop()`, and
// `stop()` STOPS THE NAVIGATOR'S FORM SUBMISSION (`this.formSubmission.stop()`
// aborts its fetch): every form Turbo's SESSION submits rather than a frame --
// one carrying `data-turbo-frame="_top"` or sitting outside every frame (the
// Trash's Restore and Delete, the media panel's Move to trash, the tags'
// Merge, the editor header's actions, "Still correct", every Undo toast; not
// Sign out, which is `data-turbo="false"` and no submission of Turbo's). Its POST has reached the server by then; only the ANSWER is thrown
// away -- the redirect, the toast. The write is done and the screen does not
// show it: the row is still there, and pressing again is a 404.
// The window is the whole frame fetch (click a tab, then Restore on the old
// list that is still showing: hundreds of milliseconds on a real connection)
// plus the moment after the render in which Turbo reads the answer's body
// once more before it proposes the visit.
//
// So for that window such a submission is not started at all. A CAPTURING
// `submit` listener on `window` -- ahead of Turbo's own (`FormSubmitObserver`,
// on `document`), of `admin--queue-hold` and of every Stimulus action --
// cancels it and keeps (form, submitter); when the promoted visit has
// COMPLETED (`turbo:load`) the form is submitted again with `requestSubmit`,
// and everybody sees that one submit as if it were the first. Never released
// on the promoted visit's `turbo:before-visit`: `stop()` runs just after it.
//
// WHAT IS HELD: exactly what `Navigator#stop()` would abort -- a NAVIGATOR-
// LEVEL submission (`navigatorLevel`, over `frameFor` in `frame_hold.js`;
// Turbo's own rule read off its source):
// - a form inside a `<turbo-frame>` is the frame's, submitted by its
//   `FrameController` (`formSubmitted`, which keeps its own `formSubmission`
//   the navigator never touches) -- unless it or its submitter says
//   `data-turbo-frame="_top"`, the frame has `target="_top"`, or the frame it
//   names is disabled (`FrameController##shouldInterceptNavigation`);
// - a form outside every frame is the session's, unless it names an enabled
//   frame (`FrameRedirector##shouldRedirect`, `#findFrameElement`).
//   So the block picker's buttons, a block's Delete and Duplicate, the account
//   screen's name form -- frame-level forms inside `#content` -- are NEVER
//   held: nothing stops them, and held they would be resubmitted into a
//   re-rendered screen.
// - Never `method="dialog"` (Keep editing and Cancel close at once), a GET (a
//   filter form replaces nothing a visit could lose), or a form Turbo does not
//   drive (`data-turbo="false"`: a real navigation).
//
// WHILE IT IS HELD:
// - a double press holds one entry (a `Map` keyed by the form);
// - the submitter shows the press was taken: disabled, the width it had, a
//   spinner before its label (`markBusy`, the same look `admin--queue-hold`
//   and `admin--busy` give), and the form is `aria-busy`. Put back when the
//   entry is dropped or released;
// - a press made in a DIALOG is taken back by closing the dialog (Cancel,
//   Escape, the x, the backdrop): the entry is deleted on the dialog's
//   `close`. Nothing in CS Studio closes a dialog because its form was
//   submitted -- the answer replaces the page -- so a `close` while held is
//   always the editor backing out; without this a permanent delete was sent
//   after Cancel. (A dialog REMOVED with its content fires no `close`.)
//
// AT RELEASE:
// - a form still connected is submitted with its submitter. If
//   `requestSubmit` throws (the submitter is gone or no longer the form's) the
//   entry is dropped: never submitted WITHOUT the submitter, which could be a
//   different action of the same form;
// - a form that is NO LONGER CONNECTED belonged to the content the navigation
//   replaced, and is DROPPED: nothing was sent, as if the press had come a
//   moment later, on a screen where that button no longer is. The editor is
//   told (`droppedToast`, also when `requestSubmit` threw): the button had
//   shown it was taken.
//   One exception, opted into by the form with `data-promotion-stand-in` --
//   only the Trash rows' Restore, "Restore under" and Delete forms, where the
//   tab just opened shows the same row: the form in the new content with the
//   same `action`, the same method and the SAME FULL PAYLOAD (`payload`: every
//   named control, hidden ones and `_method` included, minus the CSRF token
//   and fields marked `data-hold-ignore`, the row's "come back to this tab")
//   is submitted in its place -- when there is EXACTLY ONE such form. None, or
//   more than one, and it is dropped. Matching on less submitted a different
//   action that shared a URL (the posts list's Publish for a confirmed Move
//   to trash; "Rich text" for "Image").
//
// WHICH RENDERS ARE PROMOTED: every `#content` render with a `src`, except
// the one that re-renders a REFUSED frame form (a 422): Turbo's
// `formSubmissionFailedWithResponse` loads the answer without arming the
// visit. Its `turbo:submit-end` (dispatched before the render, which awaits
// the body) says so (`frameFormRefused` -- set only by a form that submits
// into `#content`, cleared by any submission that succeeds); that render ends
// the hold at once.
// THE FETCH WINDOW starts where `frame_hold.js` already sees the frame's GET
// go out, with a longer limit; it ends early when the fetch fails
// (`turbo:fetch-request-error`) or its answer has no such frame
// (`turbo:frame-missing`: Turbo then draws "Content missing" and starts no
// visit). A second link clicked meanwhile restarts the limit and keeps what is
// held.
// It composes with the two other holds. `admin--queue-hold` never saw the
// held submit (propagation stopped here), so the resubmit is its first; and
// its own `requestSubmit` after a drain, if caught here, is released with its
// `passing` flag still set. The request the resubmit makes is held by "TURBO
// FORM SUBMISSIONS" (`frame_hold.js`) like any other while a save is
// outstanding.
// Never longer than the limits: a promotion that does not come (cancelled, a
// frame that never loads) must not swallow a press for good.
// The LINK variant -- a `_top` link clicked during a frame fetch loses to the
// promoted visit -- is not covered (it loses a navigation, not a write).
//
// THE MODULES. This file is the hold itself: the `submit` listener that takes
// a press, and what becomes of the presses when the window closes. The
// window's record (`promotion`), its two limits and `frameFormRefused` are in
// `autosave/queue_state.js`, and the window is opened from
// `autosave/frame_hold.js`'s listeners, which are evaluated before this file
// and cannot import it (see the order in `autosave/queue.js`): this file
// hands its release in with `onPromotionEnd`.
import { messages } from "i18n/messages"
import { frameFor } from "autosave/frame_hold"
import { onPromotionEnd, promotionEnds, promotionHeld, promotionOpen } from "autosave/queue_state"

const formMethod = (form, submitter) => (submitter?.getAttribute("formmethod") || form.getAttribute("method") || "get").toLowerCase()
const navigatorLevel = (form, submitter) => frameFor(form, submitter) === null

// See "AT RELEASE". What the form would send, as text: the order of the
// controls is the render's and the same in two renders of one form.
// (A `<select multiple>` is compared by its first chosen value only -- its
// `value`; no form that opts in has one.)
const payload = (form) => Array.from(form.elements)
  .filter((field) => field.name && !field.disabled && field.name !== "authenticity_token" && !("holdIgnore" in field.dataset))
  .filter((field) => ![ "submit", "button", "reset", "file" ].includes(field.type) && (![ "checkbox", "radio" ].includes(field.type) || field.checked))
  .map((field) => `${encodeURIComponent(field.name)}=${encodeURIComponent(field.value)}`)
  .join("&")

function standInFor(form, entry) {
  if (!form.hasAttribute("data-promotion-stand-in")) return null
  if (entry.submitter?.name || entry.submitter?.hasAttribute("formaction")) return null
  const matches = Array.from(document.forms).filter((candidate) =>
    candidate.hasAttribute("data-promotion-stand-in") &&
    candidate.getAttribute("action") === form.getAttribute("action") &&
    formMethod(candidate) === entry.method && payload(candidate) === entry.payload)
  return matches.length === 1 ? matches[0] : null
}

// The busy look `admin--queue-hold#markBusy` gives its button. Returns the undo.
function markBusy(form, button) {
  form.setAttribute("aria-busy", "true")
  if (!button) return () => form.removeAttribute("aria-busy")

  const { width, innerHTML } = { width: button.style.width, innerHTML: button.innerHTML }
  button.style.width = `${button.offsetWidth}px`
  button.disabled = true
  button.setAttribute("aria-busy", "true")
  const spinner = document.createElement("span")
  spinner.className = "admin-spinner"
  spinner.setAttribute("aria-hidden", "true")
  button.replaceChildren(spinner, " ", button.textContent.trim())

  return () => {
    form.removeAttribute("aria-busy")
    button.style.width = width
    button.innerHTML = innerHTML
    button.disabled = false
    button.removeAttribute("aria-busy")
  }
}

// Forgets one held press and puts its button back.
function letGo(form, entry) {
  entry.dialog?.removeEventListener("close", entry.onClose)
  entry.restore()
}

// The second half of `promotionEnds` (`queue_state.js`, which has already
// closed the window, so a `requestSubmit` below is not held again): see "AT
// RELEASE".
onPromotionEnd((held) => {
  let dropped = false
  held.forEach((entry, form) => {
    letGo(form, entry)
    try {
      const target = form.isConnected ? form : standInFor(form, entry)
      if (target) target.requestSubmit(target === form ? entry.submitter || undefined : undefined)
      else dropped = true
    } catch {
      // Dropped: see "AT RELEASE".
      dropped = true
    }
  })
  if (dropped) droppedToast()
})

// A press that was taken (the button showed its spinner) and then not sent
// must not end in silence. One error toast however many were dropped, in the
// server's own markup (`#toast-error-template` in the layout, as
// `orderErrorToast` clones it); errors never auto-hide. Not for a press the
// editor took back by closing its dialog: that entry is gone before release.
function droppedToast() {
  const toast = document.getElementById("toast-error-template")?.content.firstElementChild?.cloneNode(true)
  const region = document.getElementById("toasts")
  if (!toast || !region) return
  toast.id = "toast-promotion-dropped"
  toast.querySelector("span").textContent = messages(document.body).t("components.toast.dropped")
  document.getElementById(toast.id)?.remove()
  region.append(toast)
}

window.addEventListener("submit", (event) => {
  const form = event.target
  if (!promotionOpen() || event.defaultPrevented || !(form instanceof HTMLFormElement)) return
  const submitter = event.submitter
  const method = formMethod(form, submitter)
  if (method === "get" || method === "dialog") return
  if (form.closest("[data-turbo='false']") || submitter?.closest("[data-turbo='false']")) return
  if (!navigatorLevel(form, submitter)) return

  event.preventDefault()
  // Nobody has seen it; the resubmit is the one submit.
  event.stopImmediatePropagation()
  const held = promotionHeld()
  if (held.has(form)) return

  // Read before the button is disabled: a disabled control is no part of it.
  const entry = { submitter, method, payload: payload(form) }
  const dialog = (submitter || form).closest("dialog") || form.closest("dialog")
  if (dialog?.open) {
    entry.dialog = dialog
    entry.onClose = () => {
      if (held.get(form) !== entry) return
      held.delete(form)
      letGo(form, entry)
    }
    dialog.addEventListener("close", entry.onClose)
  }
  entry.restore = markBusy(form, submitter)
  held.set(form, entry)
}, true)

document.addEventListener("turbo:load", promotionEnds)
document.addEventListener("turbo:fetch-request-error", (event) => { if (event.target?.id === "content") promotionEnds() })
document.addEventListener("turbo:frame-missing", (event) => { if (event.target?.id === "content") promotionEnds() })
