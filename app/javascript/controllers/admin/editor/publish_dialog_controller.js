import { Controller } from "@hotwired/stimulus"
import { drained, enqueue } from "saving/queue"
import { post } from "editing/requests"

// The part of the publish, discard and cancel dialogs that is asked from the
// server each time one of them is opened (`Admin::EditorScreen::
// PublishChangesDialogComponent`): what a publish would change (the publish
// dialog's overview), and WHAT IS SCHEDULED NOW (all three).
//
// ASKED THROUGH THE WRITE QUEUE, by a POST. What a publish publishes is what
// is SAVED, so the overview is true only once everything this tab still has
// to send has landed: `drained()` makes every form send what it holds, and
// the request then takes its turn in the queue (`enqueue`), behind any save
// queued meanwhile. And part of the overview is found by trying the publish
// under the record's row lock (`Admin::PublishingController#changes`), which
// is no business of a GET. `post` is the reservations' own request: it
// carries the tab's id, so the server can tell this tab's holds from a
// colleague's, and gives up after ten seconds. One request per opening.
//
// Asked on every opening, never kept: a save of this tab, a colleague's save,
// a publish or a schedule elsewhere may have moved what is true. An answer
// that arrives after a newer one was asked for, or after the dialog was
// closed and opened again, is dropped (`turn`).
//
// THE SCHEDULE. Every answer carries one hidden element,
// `[data-publishing-schedule]`: the pending copy's id (empty for none) and
// the sentences that name its time, whole, as the server words them. From it
// (`applySchedule`): each form of this dialog gets the id in its `pending`
// field, which the server compares with what is so when the press arrives
// and refuses on a mismatch; the publish dialog's "At the scheduled time
// (…)" row is shown or hidden and worded; the discard dialog's line and the
// cancel dialog's sentence are written. When the answer differs from what
// the form held, the choice follows it (the scheduled time where there is
// one, else Now); when it does not, the person's choice is left alone.
//
// The answer is this application's own markup (`ChangesOverviewComponent`,
// every name in it escaped by the server), parsed and put into the overview
// element; nothing in it is a form, so nothing the write queue holds is
// ever replaced here. The dialogs' own forms are never replaced: fields of
// theirs are set.
//
// The sentences this script shows are elements or attributes the server
// wrote: it holds no words of its own.
export default class extends Controller {
  static targets = [ "overview", "loading", "failed", "at", "kept", "now", "keptRow", "keptLabel", "discardLine", "cancelLine" ]
  static values = { url: String }

  connect() {
    this.turn = 0
    // Reopened by the server with a refusal: no `opening` event is sent for it.
    const dialog = this.element.closest("dialog")
    if (dialog?.open || dialog?.hasAttribute("data-admin--ui--dialog-open-on-load")) this.load()
  }

  disconnect() {
    this.turn += 1
  }

  opening(event) {
    if (event.detail?.dialog === this.element.closest("dialog")) this.load()
  }

  async load() {
    const turn = ++this.turn
    if (this.hasOverviewTarget) {
      this.overviewTarget.replaceChildren()
      this.overviewTarget.setAttribute("aria-busy", "true")
      this.loadingTarget.hidden = false
      this.failedTarget.hidden = true
    }

    await drained()
    if (turn !== this.turn) return
    const answer = await enqueue(() => post(this.urlValue))
    if (turn !== this.turn) return

    if (this.hasOverviewTarget) {
      this.loadingTarget.hidden = true
      this.overviewTarget.removeAttribute("aria-busy")
    }
    if (answer.status !== 200) {
      if (this.hasFailedTarget) this.failedTarget.hidden = false
      return
    }
    const body = new DOMParser().parseFromString(answer.text, "text/html").body
    this.applySchedule(body.querySelector("[data-publishing-schedule]"))
    if (this.hasOverviewTarget) this.overviewTarget.replaceChildren(...body.querySelectorAll("[data-publishing-overview]"))
  }

  applySchedule(facts) {
    if (!facts) return

    const id = facts.dataset.pendingId || ""
    let moved = false
    this.element.closest("dialog").querySelectorAll("input[name=pending]").forEach((field) => {
      if (field.value !== id) moved = true
      field.value = id
    })
    if (this.hasKeptRowTarget) {
      this.keptRowTarget.hidden = !id
      this.keptLabelTarget.textContent = facts.dataset.keptLabel || ""
      if (moved) (id ? this.keptTarget : this.nowTarget).checked = true
      else if (!id && this.keptTarget.checked) this.nowTarget.checked = true
    }
    if (this.hasDiscardLineTarget) {
      this.discardLineTarget.textContent = facts.dataset.discardLine || ""
      this.discardLineTarget.hidden = !id
    }
    if (this.hasCancelLineTarget) this.cancelLineTarget.textContent = facts.dataset.cancelLine || ""
  }

  // A time typed or picked means "At a time": nobody who chose a date should
  // publish at once because another radio button was still on.
  choseTime() {
    if (this.hasAtTarget) this.atTarget.checked = true
  }
}
