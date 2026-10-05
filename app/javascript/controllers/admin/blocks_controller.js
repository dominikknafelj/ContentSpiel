import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import Sortable from "sortablejs"
import { currentGeneration, enqueue, holdTurboRequest, syncBases } from "autosave/queue"
import { orderErrorToast, sendOrder } from "autosave/order_request"

// Drives the block list's own reordering (cs-studio spec §5.1/§6.1):
// dragging a card, its "⋯" menu's Move up/down, or the keyboard path on its
// handle (Space, arrows, Space). `card` targets are
// `Admin::BlockCardComponent`'s own top-level wrapper -- one per block, in
// document order -- and the list's direct children are exactly the cards,
// nothing else (the one "Add block" row sits after the list, not in it), so
// Sortable never has to be told to skip anything. (The list is its own
// target, not `this.element`: the controller's element is the whole Blocks
// section, whose direct children are the header, the list and the picker.)
//
// Each card's "⋯" menu has Move up and Move down; the first card's Move up
// and the last card's Move down are disabled. `refreshMoveState` keeps that
// right in the browser: it runs on connect, after every reorder this
// controller sends, and whenever the list's children change (a drop, a
// keyboard step, a card streamed in by Add block or Duplicate, one removed by
// Delete, the whole list replaced by an Undo) -- the server renders the
// right state for the cards it sends, but a streamed insertion or removal
// touches no neighbour, so it can only be corrected here.
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
    // The page this list was rendered on: a reorder belongs to it whenever it
    // is queued (`autosave/queue_state.js`, "PAGE GENERATIONS").
    this.generation = currentGeneration()
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
    // Duplicate is picked from a card's "⋯" menu, which closes on the pick:
    // the item that had focus is hidden, and focus fell to <body> -- a
    // keyboard user was back at the top of the page with the copy somewhere
    // below. So a Duplicate that succeeded is remembered (`turbo:submit-end`
    // bubbles up from its form), and the card its answer's stream then adds
    // to the list gets focus on its handle (`focusCopy`, from the list's
    // observer): the copy, where Space and the arrows move it on. The note is
    // dropped after a moment in case no card follows.
    this.duplicated = (event) => {
      const action = event.detail.formSubmission?.formElement?.getAttribute("action") || ""
      if (!event.detail.success || !new URL(action, window.location.origin).pathname.endsWith("/duplicate")) return
      this.awaitingCopy = true
      clearTimeout(this.copyTimer)
      this.copyTimer = setTimeout(() => { this.awaitingCopy = false }, 2000)
    }
    this.element.addEventListener("turbo:submit-end", this.duplicated)
    this.moveStateObserver = new MutationObserver((mutations) => {
      this.refreshMoveState()
      this.focusCopy(mutations)
    })
    this.moveStateObserver.observe(this.listTarget, { childList: true })
    this.refreshMoveState()
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
      // The order before the drag (`reorder` puts it back if the request
      // fails), read after the clone lost its `card` target.
      onStart: () => {
        this.makeCloneInert()
        this.orderBeforeDrag = this.cardTargets.slice()
      },
      onEnd: () => this.reorder(this.orderBeforeDrag)
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
    this.element.removeEventListener("turbo:submit-end", this.duplicated)
    clearTimeout(this.copyTimer)
    this.moveStateObserver?.disconnect()
    this.sortable?.destroy()
  }

  // See `duplicated` in `connect`: the first card added to the list after a
  // Duplicate is the copy.
  focusCopy(mutations) {
    if (!this.awaitingCopy) return
    const copy = mutations.flatMap((mutation) => Array.from(mutation.addedNodes))
      .find((node) => node.nodeType === Node.ELEMENT_NODE && node.matches('[data-admin--blocks-target="card"]'))
    if (!copy) return

    this.awaitingCopy = false
    this.focusHandle(copy)
  }

  // Move up is disabled on the first card, Move down on the last. Only the
  // attribute is touched, so it is idempotent and cheap to run on every
  // child-list change.
  refreshMoveState() {
    const cards = this.cardTargets
    cards.forEach((card, index) => {
      const up = card.querySelector('[data-move="up"]')
      const down = card.querySelector('[data-move="down"]')
      if (up) up.disabled = index === 0
      if (down) down.disabled = index === cards.length - 1
    })
  }

  // Shows/hides one card's own field list -- purely client-side (spec §5.1
  // names no "remember this across a reload" requirement for it), so this
  // never round-trips to the server the way a drag/move does. The title
  // button is the disclosure: `aria-expanded` follows.
  toggle(event) {
    const hidden = this.cardFor(event)?.querySelector("[data-block-body]")?.classList.toggle("hidden")
    if (hidden !== undefined) event.currentTarget.setAttribute("aria-expanded", String(!hidden))
  }

  // "Move up/down (client-side move, then the same reorder request)" (this
  // task's own brief): swaps this card with its immediate neighbour in
  // `cardTargets`' own order, then fires the exact same request a drag's
  // `onEnd` does. A disabled item (first card's Move up, last card's Move
  // down) never gets here; the index guards are a belt for a programmatic
  // call. The menu has closed by the time the card moves, so focus goes to
  // the card's handle rather than being lost with the DOM move.
  moveUp(event) {
    const card = this.cardFor(event)
    const index = this.cardTargets.indexOf(card)
    if (index <= 0) return
    const before = this.cardTargets.slice()
    this.listTarget.insertBefore(card, this.cardTargets[index - 1])
    this.moved(card, before)
  }

  moveDown(event) {
    const card = this.cardFor(event)
    const index = this.cardTargets.indexOf(card)
    if (index < 0 || index >= this.cardTargets.length - 1) return
    const before = this.cardTargets.slice()
    this.listTarget.insertBefore(this.cardTargets[index + 1], card)
    this.moved(card, before)
  }

  moved(card, before) {
    this.focusHandle(card)
    this.reorder(before)
  }

  // Queued with every other write on the screen (`autosave/queue.js`): the
  // order is read when the request is sent (a Move up/down made while an
  // autosave was in flight still sends the final order), and the page base
  // it carries is the freshest one. The answer's page base is written into
  // the hidden field before the next request goes.
  //
  // AN ORDER THAT WAS NOT SAVED IS NOT LEFT ON SCREEN. The cards are moved in
  // the DOM before the request goes (the drop, the menu, the keyboard), and
  // the endpoint's answer does not redraw the list -- so when the request
  // fails, the order on screen would be one the server never took, looking
  // exactly like one it did. What came back is judged by `sendOrder`
  // (`autosave/order_request.js`, which also says what this used to do with
  // an expired session's sign-in page):
  // - a Turbo Stream is rendered, whatever its status. A refusal (403, 422:
  //   the status line and the reason) is the endpoint's own answer -- and
  //   also means the order was not saved, so the cards go back;
  // - anything else -- the redirect to sign-in, an error page, no answer at
  //   all -- renders nothing: the cards go back and an error toast says why.
  //
  // `before` is the cards in the order they had before this move (every
  // caller that moves a card takes it first; left out, as by a caller that
  // moved nothing, there is nothing to put back). The order to go back to is
  // `restoreTo`: the order the server last took, as far as this screen knows.
  // It is `before` of the FIRST move since then, not of each -- two quick
  // moves queue two requests, and when the first fails the second's `before`
  // is itself an order that was never saved. A request that succeeds while
  // another waits behind it makes the order it sent the one to go back to.
  // After a failure the requests still queued read the order as it is then
  // (put back), and so save nothing new: the screen and the server agree.
  async reorder(before = null) {
    this.refreshMoveState()
    if (before && !this.restoreTo) this.restoreTo = before
    this.reordersQueued = (this.reordersQueued || 0) + 1
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    await enqueue(async (isCurrent) => {
      const sent = this.cardTargets.slice()
      const answer = await sendOrder(this.reorderUrlValue, {
        headers: {
          "Content-Type": "application/json",
          Accept: "text/vnd.turbo-stream.html",
          "X-CSRF-Token": csrfToken,
          "X-Page-Base-Updated-At": document.getElementById(this.constructor.pageBaseId)?.value || ""
        },
        body: JSON.stringify({ ids: sent.map((card) => card.dataset.blockId) })
      })
      this.reordersQueued -= 1
      // The page was replaced while the request was on its way: its cards,
      // its base field and its toast region are gone.
      if (!isCurrent()) return

      if (answer.outcome === "answered") {
        syncBases(answer.text, [ this.constructor.pageBaseId ])
        Turbo.renderStreamMessage(answer.text)
        if (answer.ok) {
          this.restoreTo = this.reordersQueued > 0 ? sent : null
          return
        }
      }

      this.putBack()
      if (answer.outcome !== "answered") orderErrorToast(answer.outcome, "toast-order-error")
    }, { generation: this.generation }).catch(() => {})
  }

  // Puts the cards back in the order of `restoreTo` (see `reorder`). Only
  // cards still in the list take part, each put into a place one of them
  // holds now: a card streamed in since (an Add queued in between) stays
  // where it is, one removed since is skipped, and a list an Undo re-rendered
  // -- new elements throughout -- is left exactly as the server drew it. A
  // card picked up by keyboard in the meantime is let go first: it goes back
  // with the rest, and its remembered place would no longer be true.
  putBack() {
    const order = (this.restoreTo || []).filter((card) => card.parentElement === this.listTarget)
    this.restoreTo = null
    if (this.picked) this.clearPicked(this.picked)

    order.forEach((card, index) => {
      const holder = this.cardTargets.filter((candidate) => order.includes(candidate))[index]
      if (holder !== card) this.listTarget.insertBefore(card, holder)
    })
    this.refreshMoveState()
  }

  // ---- Keyboard path (handoff §9 A9) -------------------------------------
  //
  // Space on a card's handle picks it up; ArrowUp/ArrowDown move it among the
  // cards; Space drops it (`reorder`, the request a drag's `onEnd` makes, with
  // the order as it was when the card was picked up, in case it fails) and
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
    this.orderBeforePick = this.cardTargets.slice()
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
    return this.reorder(this.orderBeforePick)
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
