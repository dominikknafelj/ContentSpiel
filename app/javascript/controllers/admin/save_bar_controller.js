import { Controller } from "@hotwired/stimulus"

// The explicit-save pattern for configuration screens (design pass spec §4,
// handoff §9 B12): the form's footer (Save, Cancel) is always there, counts
// the changed fields, and leaving with changes asks first. Save is disabled
// while an existing record has nothing to save.
// A change is counted per *control* (per group name for radios; see
// `snapshot`), comparing against a snapshot taken on connect -- so changing a
// field back removes it from the count.
//
// Two server-driven states sit on top of the snapshot count:
//   dirty  -- the server re-rendered the form with errors (a 422). The
//             re-render reconnects this controller, whose snapshot is then the
//             typed, invalid values (count 0); `dirty` keeps Save enabled and
//             the leave guard up regardless, since nothing was saved.
//   always -- Save is enabled even with nothing changed (a new record: the
//             form's whole point is to be submitted). The guard still waits
//             for a real change.
//
// The guard is page-level, not per form: the account screen has two of these
// forms, and each asking separately would prompt twice. One set of document
// listeners (shared by every connected instance) asks "is any form unsaved and
// not the one being submitted?" and opens the single Leave dialog.
//
// FOUR WAYS OUT are guarded (round 3, Task 1), each where Turbo -- or the
// browser -- first says it is about to happen. All were checked against
// Turbo's own source (turbo-rails 2.0.23), not assumed:
//
// 1. A Turbo VISIT (a sidebar link, a `_top` link, `Turbo.visit`):
//    `turbo:before-visit`, cancelable. Discard issues the visit again.
//
// 2. A link that navigates the `#content` FRAME (`onFrameLink`). Turbo fires
//    no `turbo:before-visit` for it until the frame has rendered and the form
//    is gone. It is stopped at `turbo:click`, BEFORE Turbo has started
//    anything -- not at the frame's `turbo:before-fetch-request`, where the
//    write queue holds one (`autosave/queue.js`). A request held there can
//    only be resumed, never dropped: by then `FrameController#navigateFrame`
//    has set the frame's `src` to the new URL and armed the promoted visit,
//    and the event carries no handle to cancel with (`resume`, `url` and
//    `fetchOptions` only). "Keep editing" would leave the frame pointing at a
//    page it never loaded, with a request awaiting its `resume` for good;
//    putting `src` back would load the old page over the typed text. At
//    `turbo:click` nothing has happened yet, so Keep editing has nothing to
//    undo and the same link simply works the next time.
//    Turbo dispatches `turbo:click` on the link for every click it is about
//    to handle itself (unmodified, same-origin, not `data-turbo="false"`), so
//    none of that is decided again here. The listener is a CAPTURING one on
//    `document` because the frames' own `LinkInterceptor`s listen there in
//    the bubble phase and navigate the frame whether or not the event was
//    cancelled: propagation has to stop before it reaches them. Cancelling
//    `turbo:click` alone would make Turbo stand back and the browser follow
//    the link natively, so the original click is cancelled too.
//    Which frame a link navigates is Turbo's rule
//    (`FrameController##findFrameElement`): its own `data-turbo-frame`, else
//    the frame it sits in. Only `#content` holds these forms; the dialogs'
//    and the palette's frames replace nothing.
//    The footer's Cancel (`data-save-bar-cancel`) is such a link and the one
//    that never asks: discarding is what it is for.
//    Discard clicks the link again, so Turbo does exactly what it would have.
//    A `#field` link to the page itself (the error summary's) is no way out
//    and is never asked about; while one of these forms is on the screen it
//    is neither a frame navigation nor a history entry -- the focus is moved
//    by hand (`onFrameLink`, `jumpTo`).
//    NOT covered: a GET *form* submitted into `#content`, and a script setting
//    the frame's `src`. No explicit-save screen has either.
//
// 3. Back / Forward (`onPopState`). A history traversal is a restoration
//    visit: Turbo's `History#onPopState` starts it directly, with no
//    `turbo:before-visit`, and by `popstate` the URL has already changed.
//    So the guard has to hear `popstate` BEFORE Turbo does and keep the event
//    from it. Both listen on `window`, where listeners run in the order they
//    were added, capturing or not (measured in Chrome 154: a capturing
//    listener added later still runs later), and Turbo added its own when it
//    started. `guardPopState` therefore takes Turbo's listener off, adds this
//    one and puts Turbo's back behind it -- once, when the first of these
//    forms connects, and it is NEVER UNDONE: unlike the other listeners,
//    which come and go with the forms, `onPopState` stays on `window` for the
//    life of the document, on every screen visited afterwards. That is
//    harmless: with no form unsaved (and so on every screen without one) it
//    returns at its first check and Turbo's listener, next in line, hears the
//    event exactly as before. Taking it off again would only mean reordering
//    again for the next form. Should Turbo's history ever be stopped and
//    started (`history.stop()` / `start()`), it removes and re-adds its
//    listener, which then lands behind this one again -- the order holds. That
//    reaches into Turbo (`Turbo.session.history.onPopState`, the function it
//    registered): if it is not there, nothing is reordered and Back is
//    guarded by case 4 alone, as it was. Stopping Turbo before it starts is
//    the point -- a restoration visit cancelled after the fact has already
//    moved Turbo's own history bookkeeping, announced `turbo:visit` and
//    marked the page busy.
//    The guard then undoes the traversal with `history.go` by the same number
//    of entries the other way -- so the URL, the form AND the history list
//    are as they were; pushing the old URL instead would cut off everything
//    ahead -- and swallows the `popstate` that undo causes (`returning`).
//    Discard repeats the traversal and lets it through to Turbo. How far the
//    traversal went is read from Turbo's own bookkeeping: the entry's
//    `history.state.turbo.restorationIndex` against
//    `Turbo.session.history.currentIndex` (not yet updated: Turbo has not
//    heard the event). If either is missing -- an entry Turbo didn't write --
//    the traversal is let through unguarded rather than guessed at.
//    Back to a DIFFERENT DOCUMENT (the entry before a full page load) fires
//    no `popstate`; it is an unload, and case 4 covers it.
//    (These screens are also never restored from Turbo's page cache --
//    `Admin::SaveBarHelper` -- so Back TO one shows what the server holds,
//    not a snapshot with a count and a Save state from another time.)
//
// 4. A page unload (reload, closing the tab, a link Turbo doesn't handle):
//    `beforeunload`, the browser's own prompt.
//
// Every listener does nothing unless a form is unsaved, and none takes an
// event another listener has already cancelled. The write queue's own holds
// (visits, `#content` frame requests, non-GET submissions) only act while an
// autosave is outstanding, and no screen has both kinds of form; if one ever
// does, a kept visit is simply never issued, and a discarded one is issued
// again and waits for the queue like any other.
const instances = new Set()
const shared = { leaving: false, pending: null, returning: null }

const RETURN_LIMIT_MS = 2000

const guarded = () => [...instances].filter((instance) => instance.unsaved && !instance.submitting)
const mustAsk = () => !shared.leaving && guarded().length > 0

// THE PROMOTED VISIT is not a way out. A screen reached by a link in the
// content frame is rendered first; only then does Turbo propose the visit the
// frame navigation is "promoted" to (`FrameController
// #proposeVisitIfNavigatedWithAction`: the frame's own URL, `willRender:
// false` -- it renders nothing and only brings Turbo's history and cache up to
// date). Its `turbo:before-visit` arrives a moment AFTER the new form has
// connected, so a change made in that moment (a test types at once; a
// password manager fills a field) made the guard cancel it and ask "Leave
// without saving?" about the very screen that had just opened -- and re-arm
// an open dialog's Discard with a visit to the page already showing.
// As the write queue does for the same visit (`autosave/queue.js`,
// `expectVisit`), the frame's URL is noted as `#content` renders and the next
// `turbo:before-visit` to exactly that URL is let through. The note is spent
// by the next visit whichever it is, and expires: not every frame render is
// followed by a promoted visit (a form re-rendered in place after a 422), and
// a note left lying would excuse a later, real visit to that URL.
const PROMOTED_LIMIT_MS = 2000
let promoted = null
let promotedTimer = null
const absolute = (url) => { try { return new URL(url, document.baseURI).href } catch { return null } }

document.addEventListener("turbo:frame-render", (event) => {
  if (event.target.id !== "content") return
  clearTimeout(promotedTimer)
  const src = event.target.getAttribute("src")
  promoted = src ? absolute(src) : null
  if (promoted) promotedTimer = setTimeout(() => { promoted = null }, PROMOTED_LIMIT_MS)
})

function onVisit(event) {
  const expected = promoted
  promoted = null
  if (expected && expected === absolute(event.detail.url)) return
  if (event.defaultPrevented || !mustAsk()) return
  event.preventDefault()
  const url = event.detail.url
  openLeaveDialog(() => window.Turbo.visit(url))
}

// See "FOUR WAYS OUT", 2.
function navigatesContentFrame(link) {
  const id = link.getAttribute("data-turbo-frame")
  if (id === "_top") return false
  // A name that matches no element falls back to the enclosing frame, as it
  // does in Turbo.
  const frame = (id && document.getElementById(id)) || link.closest("turbo-frame")
  return frame?.id === "content"
}

// A `#field` link to the page that is showing (the error summary's links,
// `Admin::ErrorSummaryComponent`): the element it names, or null. Turbo skips
// a link whose `href` begins with "#" -- but tests the absolute `link.href`,
// which never does (`findLinkFromClickTarget`), so it takes these for
// navigations too.
function targetWithinThePage(url) {
  try {
    const target = new URL(url, document.baseURI)
    if (target.hash.length < 2 || target.origin !== location.origin ||
        target.pathname !== location.pathname || target.search !== location.search) return null
    return { element: document.getElementById(decodeURIComponent(target.hash.slice(1))) }
  } catch {
    return null
  }
}

// What following the fragment would have done, without the history entry: the
// focus on the element (one that can't take it is made able to, as a skip
// link's target is) and the element in view. `scrollIntoView` with no
// `behavior` jumps unless the page's CSS asks for smooth scrolling, so it is
// named: no animation for a reader who asked for reduced motion.
function jumpTo(element) {
  if (!element) return
  if (element.tabIndex < 0 && !element.hasAttribute("tabindex")) element.setAttribute("tabindex", "-1")
  element.focus({ preventScroll: true })
  const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches
  element.scrollIntoView({ block: "center", behavior: still ? "instant" : "auto" })
}

function onFrameLink(event) {
  const link = event.target
  if (event.defaultPrevented || !(link instanceof Element)) return

  // A jump within the page leaves nothing, so nobody asks -- but left to
  // Turbo it is a frame navigation that fetches this screen again, without
  // the typed values and without the errors the link belongs to (the summary
  // only exists after a refused save, when the form is unsaved). And left to
  // the BROWSER it adds a history entry (`…/new#user_email_address`) that
  // Turbo didn't write and never adopts: after the save went through, Back to
  // that entry found no form unsaved, so Turbo took it over without rendering
  // -- the users list on screen under the form's URL, its snapshot cached
  // under that URL, Turbo's index one off from then on.
  // So neither gets it. Turbo is kept out (cancelling `turbo:click` makes the
  // session stand back, stopping it here keeps it from the frames), the click
  // itself is cancelled, and the jump is made by hand (`jumpTo`): no
  // `location.hash`, no history entry. Whether or not a form is unsaved --
  // neither the fetch nor the entry was ever wanted on a screen whose Back
  // has to mean "the previous screen".
  const within = targetWithinThePage(event.detail.url)
  if (within && navigatesContentFrame(link)) {
    event.preventDefault()
    event.stopPropagation()
    event.detail.originalEvent?.preventDefault()
    jumpTo(within.element)
    return
  }

  if (!mustAsk()) return
  if (link.closest("[data-save-bar-cancel]") || !navigatesContentFrame(link)) return

  event.preventDefault()
  event.stopPropagation()
  event.detail.originalEvent?.preventDefault()
  const url = event.detail.url
  openLeaveDialog(() => {
    if (!link.isConnected) return window.Turbo.visit(url)
    link.click()
    // The click has been through this listener by now (events are dispatched
    // synchronously): if the frame then fails to load, the form that is still
    // there is guarded again.
    shared.leaving = false
  })
}

// See "FOUR WAYS OUT", 3.
function onPopState(event) {
  if (shared.returning) {
    // The traversal that put the URL back: Turbo must not see it either.
    shared.returning()
    event.stopImmediatePropagation()
    return
  }
  if (!mustAsk()) return

  // THE ENTRY THE FORM IS ON (`to === from`): the guard's own undo, arriving
  // after `RETURN_LIMIT_MS` and so no longer expected. Nothing is being left,
  // so nobody asks -- and Turbo must not hear of it, because it answers every
  // `popstate` with a restoration visit, and a restoration of this page
  // fetches the form again over the typed text.
  const to = event.state?.turbo?.restorationIndex
  const from = window.Turbo?.session?.history?.currentIndex
  if (Number.isInteger(to) && to === from) {
    event.stopImmediatePropagation()
    return
  }
  if (!Number.isInteger(to) || !Number.isInteger(from)) return

  event.stopImmediatePropagation()
  // `returned` resolves once the undo has arrived, and Discard waits for it:
  // the traversal it repeats is counted in entries from where the document
  // is, and that is only the form's own entry again once the undo has landed.
  // It also resolves after `RETURN_LIMIT_MS` regardless, and `returning` is
  // cleared with it: a `popstate` that doesn't come must neither hold Discard
  // for good nor make the next real one disappear.
  const returned = new Promise((resolve) => {
    const timer = setTimeout(() => shared.returning?.(), RETURN_LIMIT_MS)
    shared.returning = () => {
      clearTimeout(timer)
      shared.returning = null
      resolve()
    }
  })
  history.go(from - to)
  openLeaveDialog(() => returned.then(() => history.go(to - from)))
}

let popStateGuarded = false
function guardPopState() {
  if (popStateGuarded) return
  const turboHistory = window.Turbo?.session?.history
  if (!turboHistory?.started || typeof turboHistory.onPopState !== "function") return
  window.removeEventListener("popstate", turboHistory.onPopState, false)
  window.addEventListener("popstate", onPopState, false)
  window.addEventListener("popstate", turboHistory.onPopState, false)
  popStateGuarded = true
}

function onUnload(event) {
  if (guarded().length > 0) event.preventDefault()
}

// Opens the one Leave dialog (in the layout). `proceed` is what "Discard
// changes" does: the visit, the link or the traversal that was stopped, again.
// "Keep editing" -- and Escape, the ×, a click on the backdrop -- only close
// it; nothing was started, so there is nothing to undo.
function openLeaveDialog(proceed) {
  const dialog = document.getElementById("leave-dialog")
  const confirm = dialog.querySelector("[data-leave-confirm]")
  const body = dialog.querySelector("[data-leave-count]")
  const count = guarded().reduce((sum, instance) => sum + instance.changes, 0)
  // A form the server re-rendered with errors is unsaved with nothing counted
  // (`dirty`): no number to name.
  if (body) {
    body.textContent = count === 0
      ? "You have unsaved changes on this screen."
      : `You have ${count === 1 ? "1 unsaved change" : `${count} unsaved changes`} on this screen.`
  }
  // A listener, not `onclick =`, and `once`: opening the dialog repeatedly
  // (Keep editing, then click another link) must not stack handlers that
  // would each leave. A previous, never-used one is removed before a new one
  // is armed, and again if the dialog is dismissed without Discard.
  clearPendingLeave()
  const handler = () => {
    shared.leaving = true
    dialog.close()
    proceed()
  }
  // `close` is dispatched a task AFTER the dialog closes. One from the
  // previous time it was open can therefore arrive when it has already been
  // opened again (Keep editing, then Back at once): that one is not this
  // opening's, and disarming on it left a Discard that did nothing.
  const onClose = () => { if (!dialog.open) clearPendingLeave() }
  shared.pending = { dialog, confirm, handler, onClose }
  confirm.addEventListener("click", handler, { once: true })
  dialog.addEventListener("close", onClose)
  // Already open: a second Back while it asks. The newest way out is the one
  // Discard takes.
  if (!dialog.open) dialog.showModal()
}

function clearPendingLeave() {
  if (!shared.pending) return
  const { dialog, confirm, handler, onClose } = shared.pending
  confirm.removeEventListener("click", handler)
  dialog.removeEventListener("close", onClose)
  shared.pending = null
}

// PENDING CHANGES, ANNOUNCED. `admin--save-bar:state` on `document`, with
// `detail: { unsaved, count }` for the whole PAGE (any form unsaved; the
// changes of all of them), whenever a form connects, changes or goes. It is
// the one thing this controller tells the rest of the screen, and
// `admin--pending-lock` is its listener: instant actions beside the form are
// disabled while changes are pending (decision D10).
// A listener that connects later than the forms asks for the state again by
// dispatching `admin--save-bar:query` on `document`, which is answered with
// the same event -- controllers are registered by one dynamic import each, so
// no connect order can be relied on. The question is anybody's to ask; the
// answer is still the one thing told.
function announce() {
  const unsaved = [...instances].filter((instance) => instance.unsaved)
  document.dispatchEvent(new CustomEvent("admin--save-bar:state", {
    detail: { unsaved: unsaved.length > 0, count: unsaved.reduce((sum, instance) => sum + instance.changes, 0) }
  }))
}

export default class extends Controller {
  static targets = ["bar", "count", "save"]
  static values = { dirty: Boolean, always: Boolean }

  connect() {
    this.initial = this.snapshot()
    this.submitting = false
    if (instances.size === 0) {
      document.addEventListener("turbo:before-visit", onVisit)
      document.addEventListener("turbo:click", onFrameLink, true)
      guardPopState()
      window.addEventListener("beforeunload", onUnload)
      document.addEventListener("admin--save-bar:query", announce)
    }
    instances.add(this)
    shared.leaving = false
    this.refresh()
  }

  disconnect() {
    instances.delete(this)
    if (instances.size === 0) {
      document.removeEventListener("turbo:before-visit", onVisit)
      document.removeEventListener("turbo:click", onFrameLink, true)
      window.removeEventListener("beforeunload", onUnload)
      document.removeEventListener("admin--save-bar:query", announce)
      clearPendingLeave()
    }
    // After the listeners are gone: the form leaving is a change of state too
    // (a lock outside the replaced frame must not stay locked).
    announce()
  }

  refresh() {
    const count = this.changes
    // A Save that the password field already governs (`data-password-submit`:
    // disabled until the password is long enough) is left to it -- two
    // controllers writing one button's `disabled` on the same keystroke would
    // undo each other, and such a form can't be saved with nothing typed
    // anyway.
    if (this.hasSaveTarget && !("passwordSubmit" in this.saveTarget.dataset)) {
      this.saveTarget.disabled = !(this.unsaved || this.alwaysValue)
    }
    this.countTarget.textContent = count > 0
      ? (count === 1 ? "1 unsaved change" : `${count} unsaved changes`)
      : (this.unsaved ? "Unsaved changes" : (this.alwaysValue ? "" : "No unsaved changes"))
    announce()
  }

  markSubmitting() { this.submitting = true }

  // A submit that didn't go through (a 422 re-renders and reconnects anyway;
  // a network error or an abort leaves this form in place): the form is
  // unsaved again, so leaving must ask again.
  submitEnded(event) {
    if (!event.detail.success) this.submitting = false
  }

  get unsaved() { return this.dirtyValue || this.changes > 0 }

  // What the form would SUBMIT, not what its controls look like: a disabled
  // control and an unticked checkbox are both simply absent. That matters
  // because other controllers inside the form adjust controls on connect --
  // `admin--branch-picker` ticks and disables every box under a chosen
  // branch -- and on a Turbo frame navigation this controller connects (and
  // takes its baseline) *before* they run. Recording a checkbox's `checked`
  // as such made an untouched group form count "1 unsaved change" and ask
  // before leaving; a box that is ticked-and-disabled submits exactly what an
  // unticked one does, so baseline and later snapshots now agree whatever the
  // connect order.
  //
  // KEYS. One per control, so one changed control is one change:
  // - a radio group is one key (its name): flipping a radio is one change,
  //   not two;
  // - a checkbox is `name=value`, present only while ticked;
  // - anything else is its name plus its POSITION among the controls of that
  //   name (`name#0`, `name#1`, ...). Rows of a list share one name
  //   (`site_setting[social_links][][name]`); keyed by name alone they
  //   collapsed into the last row's value, and an edit to an earlier row was
  //   not a change at all. A row added, removed or moved shows up as the
  //   positions whose value now differs.
  // A hidden input is skipped -- the CSRF token, a `_method`, a checkbox's
  // "0" twin are not the editor's doing -- unless it carries
  // `data-save-bar-track`: the real control behind a widget (a chip, the
  // order of sortable rows), whose script dispatches a bubbling `input` or
  // `change` on it when it sets the value.
  snapshot() {
    const values = {}
    const positions = {}
    for (const field of this.element.elements) {
      if (!field.name || field.disabled || field.type === "submit") continue
      if (field.type === "hidden" && !("saveBarTrack" in field.dataset)) continue
      if (field.type === "radio") {
        if (field.checked) values[field.name] = field.value
        else values[field.name] ??= ""
      } else if (field.type === "checkbox") {
        if (field.checked) values[`${field.name}=${field.value}`] = "on"
      } else {
        const position = positions[field.name] ?? 0
        positions[field.name] = position + 1
        values[`${field.name}#${position}`] = field.value
      }
    }
    return values
  }

  get changes() {
    const now = this.snapshot()
    // An absent key and an empty string are the same value: a blank row added
    // to a list (`name#1` appears, empty) is nothing the editor changed yet.
    // For a checkbox the absent key is "unticked" and any present one "on", so
    // the two still differ.
    return Object.keys({ ...this.initial, ...now }).filter((key) => (this.initial[key] ?? "") !== (now[key] ?? "")).length
  }
}
