import { Controller } from "@hotwired/stimulus"
import { drained, settled } from "autosave/queue"

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
// sentence in an error toast, and the button comes back.
//
// With nothing outstanding and every form clean the submit is not touched at
// all. Only the five header forms carry this controller, so nothing outside an
// editor (sign out, the palette, other screens) is ever held. A double click
// while waiting is ignored.
export default class extends Controller {
  static MESSAGE = "Your last change wasn't saved, so this didn't run. Fix it or reload, then try again."

  connect() {
    this.waiting = false
    this.passing = false
  }

  async submit(event) {
    if (this.passing) {
      this.passing = false
      return
    }
    if (this.waiting) {
      event.preventDefault()
      return
    }
    if (settled()) return

    event.preventDefault()
    const submitter = event.submitter || undefined
    this.waiting = true
    const restore = this.markBusy(submitter)

    const { clean } = await drained()

    restore()
    this.waiting = false
    if (!this.element.isConnected) return

    if (!clean) {
      this.showToast(this.constructor.MESSAGE)
      return
    }

    this.passing = true
    this.element.requestSubmit(submitter)
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
