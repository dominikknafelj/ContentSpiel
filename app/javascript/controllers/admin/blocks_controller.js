import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import Sortable from "sortablejs"

// Drives the block list's own reordering (cs-studio spec §5.1/§6.1):
// dragging a card, or its "⋯" menu's Move up/down. `card` targets are
// `Admin::BlockCardComponent`'s own top-level wrapper -- one per block, in
// document order -- and every between-cards "+ add block" picker lives
// *nested inside* the card it follows (that component's own comment
// explains why), so it's never itself a direct child of this element and
// Sortable never has to be told to skip it: `this.element`'s direct
// children are exactly the cards, nothing else.
//
// Duplicate and Delete need no controller action of their own -- both are
// plain `button_to`/`form_with` submissions, and Turbo Drive already
// appends `Accept: text/vnd.turbo-stream.html` to every non-GET form
// request on its own (`FormSubmission#requestAcceptsTurboStreamResponse`
// in Turbo's own source: true whenever the request isn't a GET, no
// `data-turbo-stream` attribute required), so the controller's Turbo
// Stream response for either one is applied in place automatically. A
// drag or a Move up/down button click is not a form submission at all
// (there's no `<form>` for Turbo Drive to intercept), which is exactly why
// *this* controller still exists: it builds the request by hand, the same
// "fetch bypasses Turbo Drive, so nothing else applies this for us"
// pattern `admin--tree`'s own drag handler already uses.
export default class extends Controller {
  static targets = ["card"]
  static values = { reorderUrl: String }

  // Every block request also carries the page settings form's current base
  // (`X-Page-Base-Updated-At`): a block write touches the page, and the
  // server only moves that form's base forward when the one it holds was
  // still current (`Admin::ContentBlocksController#page_base_streams`).
  // Turbo's own submissions inside this section (add, duplicate, delete)
  // get it here; `reorder` below adds it itself; a card's autosave through
  // `admin--autosave`'s `pageBaseId` value.
  static pageBaseId = "page-base-updated-at"

  connect() {
    this.addPageBase = (event) => {
      const pageBase = document.getElementById(this.constructor.pageBaseId)?.value
      if (pageBase) event.detail.fetchOptions.headers["X-Page-Base-Updated-At"] = pageBase
    }
    this.element.addEventListener("turbo:before-fetch-request", this.addPageBase)
    this.sortable = Sortable.create(this.element, {
      handle: ".admin-block-card__handle",
      animation: 150,
      onEnd: () => this.reorder()
    })
  }

  disconnect() {
    this.element.removeEventListener("turbo:before-fetch-request", this.addPageBase)
    this.sortable?.destroy()
  }

  // Shows/hides one card's own field list -- purely client-side (spec §5.1
  // names no "remember this across a reload" requirement for it), so this
  // never round-trips to the server the way a drag/move does.
  toggle(event) {
    this.cardFor(event)?.querySelector("[data-block-body]")?.classList.toggle("hidden")
  }

  // "Move up/down (client-side move, then the same reorder request)" (this
  // task's own brief): swaps this card with its immediate neighbour in
  // `cardTargets`' own order -- not raw DOM siblings, since a card's
  // *own* nested trailing picker would otherwise come along as if it were
  // itself another list item -- then fires the exact same request a drag's
  // `onEnd` does.
  moveUp(event) {
    const card = this.cardFor(event)
    const index = this.cardTargets.indexOf(card)
    if (index > 0) this.element.insertBefore(card, this.cardTargets[index - 1])
    this.reorder()
  }

  moveDown(event) {
    const card = this.cardFor(event)
    const index = this.cardTargets.indexOf(card)
    if (index >= 0 && index < this.cardTargets.length - 1) {
      this.element.insertBefore(this.cardTargets[index + 1], card)
    }
    this.reorder()
  }

  async reorder() {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    const response = await fetch(this.reorderUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Accept: "text/vnd.turbo-stream.html",
        "X-CSRF-Token": csrfToken,
        "X-Page-Base-Updated-At": document.getElementById(this.constructor.pageBaseId)?.value || ""
      },
      body: JSON.stringify({ ids: this.cardTargets.map((card) => card.dataset.blockId) })
    })

    Turbo.renderStreamMessage(await response.text())
  }

  cardFor(event) {
    return event.currentTarget.closest('[data-admin--blocks-target="card"]')
  }
}
