import { Controller } from "@hotwired/stimulus"
import { beginAction, drained, endAction, settled } from "autosave/queue"

// On a form in an editor's header whose submission REPLACES THE PAGE (Publish,
// Unpublish, Schedule, Remove schedule, Move to trash: each redirects).
// Nothing that replaces the page starts until the page's write queue is empty
// (`autosave/queue.js`, "THE RULE"): the submit is intercepted, the button
// shows it is waiting, `drained()` sends every edit still held by any form --
// debounced, queued, in flight, or typed while a save was in flight -- and
// only then is the form submitted for real. The action therefore runs on the
// fresh state, with the last edit saved.
//
// If a form ENDED UNCLEAN (its last save refused, invalid, offline, or paused
// by a "changed elsewhere" 409), the action does not run: its redirect would
// throw away exactly the text the bar promised to keep, or publish a record
// without an edit nobody was told was lost. The editor gets one plain
// sentence in an error toast, and the button comes back. Unpublish, Schedule,
// Remove schedule and Move to trash sit in a modal dialog, and a modal is
// drawn in the top layer, above `#toasts`: the dialog is closed first, or the
// sentence would sit unseen behind it. And if the editor closed that dialog
// themselves while the queue drained (Escape, Cancel, the backdrop), they
// took the action back: it does not run.
//
// The submission that is let through is announced to the queue
// (`beginAction`), so the visit its redirect ends in is not held and fetched
// a second time by the queue's own `turbo:before-visit` handler, should an
// edit have landed in the meantime -- see there. `end` takes the announcement
// back when the submission ends with no redirect to follow (aborted, a network
// error, an answer Turbo renders in place or not at all).
//
// With nothing outstanding and every form clean the submit is not touched at
// all (only announced). Only the five header forms carry this controller, so nothing outside an
// editor (sign out, the palette, other screens) is ever held. A double click
// while waiting is ignored.
export default class extends Controller {
  static MESSAGE = "Your last change wasn't saved, so this didn't run. Fix it or reload, then try again."

  connect() {
    this.waiting = false
    this.passing = false
    this.acting = false
    // On `document`: Turbo dispatches an event to the document element instead
    // when its form is no longer connected.
    this.end = (event) => {
      if (!this.acting || event.detail.formSubmission?.formElement !== this.element) return
      this.acting = false
      const { success, fetchResponse } = event.detail
      if (!success || !fetchResponse?.redirected) endAction()
    }
    document.addEventListener("turbo:submit-end", this.end)
  }

  disconnect() {
    document.removeEventListener("turbo:submit-end", this.end)
  }

  async submit(event) {
    if (this.passing) {
      this.passing = false
      this.announce()
      return
    }
    if (this.waiting) {
      event.preventDefault()
      return
    }
    if (settled()) {
      this.announce()
      return
    }

    event.preventDefault()
    const submitter = event.submitter || undefined
    const dialog = this.element.closest("dialog")
    const fromOpenDialog = Boolean(dialog?.open)
    this.waiting = true
    const restore = this.markBusy(submitter)

    const { clean } = await drained()

    restore()
    this.waiting = false
    if (!this.element.isConnected) return
    if (fromOpenDialog && !dialog.open) return

    if (!clean) {
      if (dialog?.open) dialog.close()
      this.showToast(this.constructor.MESSAGE)
      return
    }

    this.passing = true
    this.element.requestSubmit(submitter)
  }

  // The submission goes through now, untouched: tell the queue (see the class
  // comment), until `end` hears how it ended.
  announce() {
    this.acting = true
    beginAction()
  }

  // The same busy look `admin--busy` gives a submitting button: disabled, the
  // width it had, a spinner before its label. Returns the undo.
  markBusy(button) {
    if (!button) return () => {}

    const { width, innerHTML } = { width: button.style.width, innerHTML: button.innerHTML }
    button.style.width = `${button.offsetWidth}px`
    button.disabled = true
    button.setAttribute("aria-busy", "true")
    const spinner = document.createElement("span")
    spinner.className = "admin-spinner"
    spinner.setAttribute("aria-hidden", "true")
    button.replaceChildren(spinner, " ", button.textContent.trim())

    return () => {
      button.style.width = width
      button.innerHTML = innerHTML
      button.disabled = false
      button.removeAttribute("aria-busy")
    }
  }

  // One error toast (`Admin::ToastComponent`'s markup; its own controller
  // dismisses it and keeps it to a handful). Errors never auto-hide.
  showToast(message) {
    const region = document.getElementById("toasts")
    if (!region) return

    document.getElementById("toast-queue-hold")?.remove()
    const toast = document.createElement("div")
    toast.id = "toast-queue-hold"
    toast.setAttribute("role", "alert")
    toast.dataset.controller = "admin--toast"
    toast.setAttribute("data-admin--toast-timeout-value", "0")
    toast.setAttribute("data-kind", "error")
    toast.setAttribute("data-action", "mouseenter->admin--toast#pause mouseleave->admin--toast#start focusin->admin--toast#pause focusout->admin--toast#start")
    toast.className = "admin-toast pointer-events-auto flex items-center gap-3 rounded-cs bg-ink px-4 py-2.5 text-sm text-paper shadow-menu"
    const text = document.createElement("span")
    text.textContent = message
    const dismiss = document.createElement("button")
    dismiss.type = "button"
    dismiss.setAttribute("aria-label", "Dismiss")
    dismiss.setAttribute("data-action", "admin--toast#dismiss")
    dismiss.className = "cursor-pointer text-lg leading-none opacity-70 after:content-['×'] hover:opacity-100"
    toast.append(text, dismiss)
    region.append(toast)
  }
}
