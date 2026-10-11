import { Controller } from "@hotwired/stimulus"
import { drained, settled } from "saving/queue"

// On a form in an editor's header whose submission REPLACES THE PAGE (Publish,
// Unpublish, Schedule, Remove schedule, Move to trash: each redirects), and on
// the one block action whose answer REPLACES FORMS OF BLOCKS THAT STAY: a
// section's "Remove section, keep blocks" (below).
// Nothing that replaces the page starts until the page's write queue is empty
// (`saving/queue.js`, "THE RULE"): the submit is intercepted, the button
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
// The visit the action's redirect ends in is not held by the queue's own
// `turbo:before-visit` handler, should an edit have landed in the meantime:
// that holds for every Turbo form submission and is the queue's business
// (`saving/frame_hold.js`, "TURBO FORM SUBMISSIONS"), which also holds the
// request itself once more if something became outstanding between this
// controller's drain and the request going out.
//
// "REMOVE SECTION, KEEP BLOCKS" (`Admin::EditorScreen::SectionCardComponent`)
// is no visit: its form is inside the blocks section and its answer is a
// Turbo Stream that puts a new card where each of the section's blocks had a
// form. For the text in those forms that is the same as a redirect, so the
// same rule holds, and it composes with `admin--editor--blocks` like this: the
// `submit` is taken here first and nothing of Turbo's has started; after a
// clean drain the form is submitted for real, ONCE (`passing`); only then
// does Turbo build the request, whose `turbo:before-fetch-request` bubbles
// to `admin--editor--blocks`, which takes its turn in the -- now empty -- queue
// (`holdTurboRequest`), exactly as for an unheld delete.
// After an unclean drain no request is ever built. `holdTurboRequest` alone
// was not enough: it waits for the queue's slot, so the delete went ahead of
// the follow-up of a save still on the wire, and it never asks whether a
// form is clean.
//
// With nothing outstanding and every form clean the submit is not touched at
// all. Only those forms carry this controller; other forms get the queue's
// general treatment, without the refusal. A double click while waiting is
// ignored.
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

  // The same busy look `admin--ui--busy` gives a submitting button: disabled, the
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

  // One error toast (`Admin::Ui::ToastComponent`'s markup; its own controller
  // dismisses it and keeps it to a handful). Errors never auto-hide.
  showToast(message) {
    const region = document.getElementById("toasts")
    if (!region) return

    document.getElementById("toast-queue-hold")?.remove()
    const toast = document.createElement("div")
    toast.id = "toast-queue-hold"
    toast.setAttribute("role", "alert")
    toast.dataset.controller = "admin--ui--toast"
    toast.setAttribute("data-admin--ui--toast-timeout-value", "0")
    toast.setAttribute("data-kind", "error")
    toast.setAttribute("data-action", "mouseenter->admin--ui--toast#pause mouseleave->admin--ui--toast#start focusin->admin--ui--toast#pause focusout->admin--ui--toast#start")
    toast.className = "admin-toast pointer-events-auto flex items-center gap-3 rounded-cs bg-ink px-4 py-2.5 text-sm text-paper shadow-menu"
    const text = document.createElement("span")
    text.textContent = message
    const dismiss = document.createElement("button")
    dismiss.type = "button"
    dismiss.setAttribute("aria-label", "Dismiss")
    dismiss.setAttribute("data-action", "admin--ui--toast#dismiss")
    dismiss.className = "cursor-pointer text-lg leading-none opacity-70 after:content-['×'] hover:opacity-100"
    toast.append(text, dismiss)
    region.append(toast)
  }
}
