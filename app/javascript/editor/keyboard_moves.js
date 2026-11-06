import { messages } from "i18n/messages"
import { itemsOf, titleOf } from "editor/containers"

// The handle's keyboard path (handoff §9 A9). Space on a card's handle picks
// it up; ArrowUp/ArrowDown move it among the cards; Space drops it
// (`MoveQueue#reorder`, the request a drag's `onEnd` makes, with the order as
// it was when the card was picked up, in case it fails) and Escape puts it
// back without saving. What it says, it says in the live region in the
// words of the locale (`block_moves.picked_up`, `dropped`, `cancelled` and
// `position`, served by the screen's `data-messages`).
//
// `host` is the blocks controller: its `listTarget`, `element`,
// `sayMoving()` and `announce(text)`.
export class KeyboardMoves {
  constructor(host, queue) {
    this.host = host
    this.queue = queue
    this.card = null
  }

  // The card in someone's hand: one of the three holds `sayMoving` judges.
  get picked() {
    return this.card
  }

  set picked(card) {
    this.card = card
  }

  key(event, card) {
    if (event.key === " ") {
      event.preventDefault()
      this.card === card ? this.drop(card) : this.pickUp(card)
      return
    }
    if (this.card !== card) return

    if (event.key === "Escape") {
      event.preventDefault()
      this.cancel(card)
    } else if (event.key === "ArrowUp" || event.key === "ArrowDown") {
      event.preventDefault()
      this.step(card, event.key === "ArrowUp" ? -1 : 1)
    }
  }

  pickUp(card) {
    if (this.card && this.card !== card) this.cancel(this.card, { refocus: false })
    this.card = card
    this.host.sayMoving()
    this.originNext = card.nextElementSibling
    this.orderBeforePick = itemsOf(this.host.listTarget)
    card.dataset.picked = "true"
    card.classList.add("admin-drag-chosen")
    this.announce("picked_up", { block: titleOf(card), position: this.positionOf(card) })
  }

  // Swaps with the neighbouring card in the list's own order, as Move
  // up/down does (never raw DOM siblings -- see `MenuMoves#up`). The list's
  // items, not every `card` target: a card resting in a lane between its
  // drop and its answer is one too, and is no child of the list to step past.
  step(card, direction) {
    const list = this.host.listTarget
    const cards = itemsOf(list)
    const index = cards.indexOf(card)
    const neighbour = cards[index + direction]
    if (!neighbour) return
    list.insertBefore(card, direction < 0 ? neighbour : neighbour.nextElementSibling)
    // A DOM move blurs the focused handle; put focus back so the next key
    // press still reaches this card.
    this.focusHandle(card)
    this.host.announce(this.positionOf(card))
  }

  drop(card) {
    // Not said yet: the move that follows holds on (no false in between).
    this.clearPicked(card, { say: false })
    this.announce("dropped", { block: titleOf(card), position: this.positionOf(card) })
    return this.queue.reorder(this.orderBeforePick)
  }

  // Focus leaving the handle puts a picked card back: the DOM move has saved
  // nothing. A move blurs the handle too and refocuses at once, so judge
  // after the current task.
  blur(handle, card) {
    setTimeout(() => {
      if (this.card === card && document.activeElement !== handle) this.cancel(card, { refocus: false })
    }, 0)
  }

  cancel(card, { refocus = true } = {}) {
    this.host.listTarget.insertBefore(card, this.originNext)
    this.clearPicked(card)
    if (refocus) this.focusHandle(card)
    this.announce("cancelled", { block: titleOf(card) })
  }

  clearPicked(card, { say = true } = {}) {
    delete card.dataset.picked
    card.classList.remove("admin-drag-chosen")
    this.card = null
    if (say) this.host.sayMoving()
  }

  focusHandle(card) {
    card.querySelector(".admin-block-card__handle")?.focus()
  }

  positionOf(card) {
    const cards = itemsOf(this.host.listTarget)
    return this.sentence("position", { position: cards.indexOf(card) + 1, count: cards.length })
  }

  announce(key, vars) {
    this.host.announce(this.sentence(key, vars))
  }

  // `block_moves.<key>` in the screen's `data-messages`.
  sentence(key, vars) {
    return messages(this.host.element).t(`components.editor_screen.block_moves.${key}`, vars)
  }
}
