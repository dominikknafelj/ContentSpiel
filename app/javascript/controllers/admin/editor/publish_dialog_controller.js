import { Controller } from "@hotwired/stimulus"
import { drained, enqueue } from "saving/queue"
import { post } from "editing/requests"

// The body of the "Publish changes" dialog (`Admin::EditorScreen::
// PublishChangesDialogComponent`): it asks the server what a publish would
// change each time the dialog is opened, and draws the answer.
//
// THE OVERVIEW IS ASKED THROUGH THE WRITE QUEUE, by a POST. What a publish
// publishes is what is SAVED, so the overview is true only once everything
// this tab still has to send has landed: `drained()` makes every form send
// what it holds, and the request then takes its turn in the queue
// (`enqueue`), behind any save queued meanwhile. And part of the answer is
// found by trying the publish under the record's row lock (`Admin::
// PublishingController#changes`), which is no business of a GET. `post` is
// the reservations' own request: it carries the tab's id, so the server can
// tell this tab's holds from a colleague's, and gives up after ten seconds.
//
// Asked on every opening, never kept: a save of this tab, a colleague's save
// or a publish elsewhere may have moved what would be published. An answer
// that arrives after a newer one was asked for, or after the dialog was
// closed and opened again, is dropped (`turn`).
//
// The answer is this application's own markup (`ChangesOverviewComponent`,
// every name in it escaped by the server), parsed and put into the overview
// element; nothing in it is a form, so nothing the write queue holds is
// ever replaced here. The dialog's own forms stand beside the overview and
// are never touched.
//
// The two sentences this script shows (loading, failed) are elements the
// server drew, shown and hidden: it holds no words of its own.
export default class extends Controller {
  static targets = [ "overview", "loading", "failed", "at" ]
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
    this.overviewTarget.replaceChildren()
    this.overviewTarget.setAttribute("aria-busy", "true")
    this.loadingTarget.hidden = false
    this.failedTarget.hidden = true

    await drained()
    if (turn !== this.turn) return
    const answer = await enqueue(() => post(this.urlValue))
    if (turn !== this.turn) return

    this.loadingTarget.hidden = true
    this.overviewTarget.removeAttribute("aria-busy")
    if (answer.status !== 200) {
      this.failedTarget.hidden = false
      return
    }
    const body = new DOMParser().parseFromString(answer.text, "text/html").body
    this.overviewTarget.replaceChildren(...body.childNodes)
  }

  // A time typed or picked means "At a time": nobody who chose a date should
  // publish at once because another radio button was still on.
  choseTime() {
    if (this.hasAtTarget) this.atTarget.checked = true
  }
}
