import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import Sortable from "sortablejs"
import { enqueue, holdTurboRequest, syncBases } from "autosave/queue"

// Drives the block list's own reordering (cs-studio spec §5.1/§6.1):
// dragging a card, its "⋯" menu's Move up/down, or the keyboard path on its
// handle (Space, arrows, Space). `card` targets are
// `Admin::BlockCardComponent`'s own top-level wrapper -- one per block, in
// document order -- and every between-cards "+ add block" picker lives
// *nested inside* the card it follows (that component's own comment
// explains why), so it's never itself a direct child of the `list` target
// and Sortable never has to be told to skip it: the list's direct children
// are exactly the cards, nothing else. (The list is its own target, not
// `this.element`: the controller's element is the whole Blocks section,
// whose direct children are the header, the list and the picker.)
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
  static targets = ["card", "list", "announcer"]
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
    // A write (never a GET) waits its turn in the page-level queue
    // (`autosave/queue.js`) and reads the page base when it is actually sent;
    // the queue slot is kept until the answer's bases are in the hidden
    // fields, so the next request sees them. Add, duplicate and delete are
    // plain Turbo form submissions, and answer with streams that move the
    // page form's base, so they depend on it exactly as an autosave does.
    this.addPageBase = (event) => {
      if (String(event.detail.fetchOptions.method).toUpperCase() === "GET") return

      holdTurboRequest(event, {
        baseIds: [ this.constructor.pageBaseId ],
        before: (request) => {
          const pageBase = document.getElementById(this.constructor.pageBaseId)?.value
          if (pageBase) request.fetchOptions.headers["X-Page-Base-Updated-At"] = pageBase
        }
      })
    }
    this.element.addEventListener("turbo:before-fetch-request", this.addPageBase)
    // The Undo toast after a reorder lives in `#toasts`, outside this
    // section, so its `button_to` request wouldn't pass through the listener
    // above -- and without the base the server wouldn't move the page form's
    // base forward after the Undo's own page touch (a spurious "Changed
    // elsewhere" on the next page save). It's recognised by its URL.
    this.addPageBaseToUndo = (event) => {
      if (this.element.contains(event.target)) return
      if (event.detail.url?.pathname === new URL(this.reorderUrlValue, window.location.origin).pathname) this.addPageBase(event)
    }
    document.addEventListener("turbo:before-fetch-request", this.addPageBaseToUndo)
    this.sortable = Sortable.create(this.listTarget, {
      handle: ".admin-block-card__handle",
      animation: 150,
      // The drag look (handoff §9 A9): a dashed placeholder where the card
      // would land, and the lifted card itself with a shadow.
      ghostClass: "admin-drag-ghost",
      chosenClass: "admin-drag-chosen",
      // SortableJS's own pointer-driven drag instead of native HTML5
      // drag-and-drop, for the reason `admin--tree` spells out: the handle
      // is a `<button>`, and Firefox never starts a native drag from one.
      // The fallback drags a clone of the card (`fallbackClass`), appended
      // to `<body>` -- so the list's direct children stay exactly the cards.
      // `fallbackTolerance` keeps a shaky click on the handle from lifting
      // the card.
      forceFallback: true,
      fallbackOnBody: true,
      fallbackClass: "admin-drag-fallback",
      fallbackTolerance: 3,
      onStart: () => this.makeCloneInert(),
      onEnd: () => this.reorder()
    })
  }

  // The dragged clone is a deep copy of a card: its forms' autosave and
  // rich-text controllers, its `card` target and every id would otherwise
  // exist twice for as long as the drag lasts -- a second Tiptap editor
  // booting in the clone, a Turbo Stream finding the copy by id. SortableJS
  // fires `onStart` synchronously right after appending the clone, before
  // Stimulus's mutation observer has seen it, so stripping the wiring here
  // means nothing ever connects: the clone is a picture of the card, no more.
  makeCloneInert() {
    const clone = Sortable.ghost
    if (!clone) return

    for (const element of [clone, ...clone.querySelectorAll("*")]) {
      for (const { name } of Array.from(element.attributes)) {
        if (name === "id" || name === "data-controller" || name === "data-action" || /^data-.+-target$/.test(name)) {
          element.removeAttribute(name)
        }
      }
    }
  }

  disconnect() {
    this.element.removeEventListener("turbo:before-fetch-request", this.addPageBase)
    document.removeEventListener("turbo:before-fetch-request", this.addPageBaseToUndo)
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
    if (index > 0) this.listTarget.insertBefore(card, this.cardTargets[index - 1])
    this.reorder()
  }

  moveDown(event) {
    const card = this.cardFor(event)
    const index = this.cardTargets.indexOf(card)
    if (index >= 0 && index < this.cardTargets.length - 1) {
      this.listTarget.insertBefore(this.cardTargets[index + 1], card)
    }
    this.reorder()
  }

  // Queued with every other write on the screen (`autosave/queue.js`): the
  // order is read when the request is sent (a Move up/down made while an
  // autosave was in flight still sends the final order), and the page base
  // it carries is the freshest one. The answer's page base is written into
  // the hidden field before the next request goes.
  async reorder() {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    await enqueue(async () => {
      const response = await fetch(this.reorderUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Accept: "text/vnd.turbo-stream.html",
          "X-CSRF-Token": csrfToken,
          "X-Page-Base-Updated-At": document.getElementById(this.constructor.pageBaseId)?.value || ""
        },
        body: JSON.stringify({ ids: this.cardTargets.map((card) => card.dataset.blockId) }),
        signal: AbortSignal.timeout(30000)
      })

      const text = await response.text()
      syncBases(text, [ this.constructor.pageBaseId ])
      Turbo.renderStreamMessage(text)
    }).catch(() => {})
  }

  // ---- Keyboard path (handoff §9 A9) -------------------------------------
  //
  // Space on a card's handle picks it up; ArrowUp/ArrowDown move it among the
  // cards; Space drops it (`reorder`, the request a drag's `onEnd` makes) and
  // Escape puts it back without saving.
  key(event) {
    const card = this.cardFor(event)
    if (!card) return

    if (event.key === " ") {
      event.preventDefault()
      this.picked === card ? this.drop(card) : this.pickUp(card)
      return
    }
    if (this.picked !== card) return

    if (event.key === "Escape") {
      event.preventDefault()
      this.cancel(card)
    } else if (event.key === "ArrowUp" || event.key === "ArrowDown") {
      event.preventDefault()
      this.step(card, event.key === "ArrowUp" ? -1 : 1)
    }
  }

  pickUp(card) {
    if (this.picked && this.picked !== card) this.cancel(this.picked, { refocus: false })
    this.picked = card
    this.originNext = card.nextElementSibling
    card.dataset.picked = "true"
    card.classList.add("admin-drag-chosen")
    this.announce(`Picked up ${this.titleOf(card)}. ${this.positionOf(card)}`)
  }

  // Swaps with the neighbouring card in `cardTargets`' own order, as Move
  // up/down does (never raw DOM siblings -- see `moveUp`).
  step(card, direction) {
    const index = this.cardTargets.indexOf(card)
    const neighbour = this.cardTargets[index + direction]
    if (!neighbour) return
    this.listTarget.insertBefore(card, direction < 0 ? neighbour : neighbour.nextElementSibling)
    // A DOM move blurs the focused handle; put focus back so the next key
    // press still reaches this card.
    this.focusHandle(card)
    this.announce(this.positionOf(card))
  }

  drop(card) {
    this.clearPicked(card)
    this.announce(`Dropped ${this.titleOf(card)}. ${this.positionOf(card)}`)
    return this.reorder()
  }

  // Focus leaving the handle puts a picked card back: the DOM move has saved
  // nothing. A move blurs the handle too and refocuses at once, so judge
  // after the current task.
  blur(event) {
    // `currentTarget` is only set during dispatch: keep the handle itself.
    const handle = event.currentTarget
    const card = this.cardFor(event)
    setTimeout(() => {
      if (this.picked === card && document.activeElement !== handle) this.cancel(card, { refocus: false })
    }, 0)
  }

  cancel(card, { refocus = true } = {}) {
    this.listTarget.insertBefore(card, this.originNext)
    this.clearPicked(card)
    if (refocus) this.focusHandle(card)
    this.announce(`Cancelled. ${this.titleOf(card)} is back where it was.`)
  }

  clearPicked(card) {
    delete card.dataset.picked
    card.classList.remove("admin-drag-chosen")
    this.picked = null
  }

  focusHandle(card) {
    card.querySelector(".admin-block-card__handle")?.focus()
  }

  titleOf(card) {
    return card.querySelector("[data-action$='admin--blocks#toggle']")?.textContent.trim() || "block"
  }

  positionOf(card) {
    return `Position ${this.cardTargets.indexOf(card) + 1} of ${this.cardTargets.length}.`
  }

  announce(message) {
    if (this.hasAnnouncerTarget) this.announcerTarget.textContent = message
  }

  cardFor(event) {
    return event.currentTarget.closest('[data-admin--blocks-target="card"]')
  }
}
