import { Turbo } from "@hotwired/turbo-rails"
import { currentGeneration, enqueue } from "saving/queue"
import { errorToast, orderErrorToast, sendOrder, streamsApplied } from "saving/order_request"
import { messages } from "i18n/messages"
import { TAB_HEADER } from "editing/requests"
import { TAB } from "live/connection"
import { isClosed, itemsOf, placeOf, titleOf } from "editor/containers"

// The page this list was rendered on, for the controller to note at connect:
// a reorder belongs to it whenever it is queued (`saving/queue_state.js`,
// "PAGE GENERATIONS"). Re-exported so the controller reaches the write queue
// through this module alone.
export { currentGeneration }

// The queued send of a block's move, its put-back and its answer: what
// `admin--editor--blocks#move`, the one sender of a reorder, hands its move
// to. A drop's `onEnd`, the menu's moves (`editor/menu_moves.js`) and
// (through `#reorder`) the keyboard path (`editor/keyboard_moves.js`) all
// call that action, and nothing else calls this queue's `move`.
//
// `host` is the blocks controller. What is read of it: `listTarget`,
// `containers()`, `reorderUrlValue`, `generation`, `application` and
// `element`; what is called: `sayMoving()`, `refreshMoveState()`,
// `letGo()` (a card picked up on the keyboard, when everything is put
// back), `focusItem(item)` and `announce(text)`.
export class MoveQueue {
  constructor(host) {
    this.host = host
    this.moveHolds = 0
  }

  // How many moves are in the queue: one of the three holds `sayMoving`
  // judges (`admin--editor--blocks#sayMoving`).
  get holds() {
    return this.moveHolds
  }

  // The controller left the page: no move it queued is in anyone's hand.
  reset() {
    this.moveHolds = 0
  }

  // `item` is the element that was moved -- null for "send the list's order
  // as it is" -- `from` the container it left, and `before` every
  // container's order as it was before the element was moved (`snapshot`).
  //
  // Queued with every other write on the screen (`saving/queue.js`): the
  // order is read when the request is sent (a Move up/down made while an
  // autosave was in flight still sends the final order).
  //
  // WHAT IS SENT is the complete order of ONE container -- the one the item
  // is in now (`to`) -- and, when the server has the item in another one,
  // where (`moved_from`): `ContentBlocks::Reorder` moves it only if it is
  // there. The container it left needs no request of its own; the server
  // closes it up.
  //
  // AN ORDER THAT WAS NOT SAVED IS NOT LEFT ON SCREEN. The cards are moved in
  // the DOM before the request goes (the drop, the menu, the keyboard), and
  // the endpoint's answer does not redraw the list -- so when the request
  // fails, the order on screen would be one the server never took, looking
  // exactly like one it did. What came back is judged by `sendOrder`
  // (`saving/order_request.js`, which also says what an expired session's
  // sign-in page is taken for):
  // - a Turbo Stream is rendered, whatever its status. A refusal (403, 422:
  //   the status line and the reason, `Admin::Answers::BlockRefused#reordered`) is the
  //   endpoint's own answer -- and also means the order was not saved, so the
  //   cards go back;
  // - anything else -- the redirect to sign-in, an error page, no answer at
  //   all -- renders nothing: the cards go back and an error toast says why.
  //
  // `before` is what the screen showed before this move (every caller that
  // moves an element takes it first; left out, as by a caller that moved
  // nothing, there is nothing to put back). The orders to go back to are
  // `restoreTo`: each container's order as the server last took it, as far as
  // this screen knows. It is `before` of the FIRST move since then, not of
  // each -- two quick moves queue two requests, and when the first fails the
  // second's `before` is itself an order that was never saved. A request that
  // succeeds while another waits behind it makes the order it sent the one to
  // go back to, for ITS container (`taken`). After a failure the requests
  // still queued read the order as it is then (put back), and so save nothing
  // new: the screen and the server agree. A container the remembered orders
  // do not name yet is taken from this move's `before`: nothing has been
  // moved in it since they were taken, or the move that did would have named
  // it. (The keyboard path remembers the list alone, `reorder`; a tile then
  // dragged out of a lane has to go back to that lane with the rest.)
  //
  // A MOVE BETWEEN CONTAINERS REDRAWS THE BLOCK (sections plan, D8). A card
  // that goes into a column becomes a tile with its form under the lanes, a
  // tile that leaves its section a card: the answer replaces the element and
  // the form (`Admin::Answers::BlockSaved#reordered`, through
  // `Admin::Answers::BlockDrawing#move_streams`) -- the one time a form on
  // this screen is replaced while its block stays. A form is what holds an
  // edit that is not saved yet, so:
  // - every autosave form is told to send what it holds as the move is
  //   queued (`sendHeldEdits`), which puts those saves AHEAD of the move. The
  //   same before a move inside a lane, which redraws nothing if it is saved
  //   but the whole list if it is refused (below);
  // - when the move's turn comes, the block's own form must have ended saved
  //   (`formState`). One that did not end clean -- paused by a 409
  //   (`Admin::Answers::Stale`), refused, invalid, offline -- is not moved:
  //   its text is on this screen and nowhere else, and the 409 bar has
  //   promised it stays. Everything goes back (`putBack`) and a toast says to
  //   reload or fix the block first;
  // - one whose edit is still on its way stands back ONCE. That is an edit
  //   typed while the form's own save was on the wire: `admin--saving--autosave`
  //   sends it as that save's follow-up, queued only when the save is
  //   answered -- behind this move. Sent in its turn, the move's answer would
  //   draw the form without those words, and on a base the follow-up then
  //   makes stale. So the form is told to send again, the move is queued
  //   again behind it, and if the form is still not saved when that turn
  //   comes (a save waiting out a retry) the move is given up like a refused
  //   one.
  // A move within one container moves the element and nothing else, and
  // never waits on a form.
  //
  // `focus` is for a move made from a menu (`MenuMoves#relocate`): when its
  // turn has ended, the block's element takes the focus back if the move took
  // it away and nothing has it (`sendMove`, `focusMoved`). A drag is the
  // pointer's and asks for none.
  //
  // THE ANSWER IS DRAWN BEFORE THE NEXT WRITE GOES, for a move that names a
  // section or changes containers (`streamsApplied`). Its answer changes what
  // the next task reads: the moved block's new element and form, or -- for a
  // refusal -- the whole list as the server has it
  // (`BlockDrawing#blocks_list_stream`: the screen was behind, sections spec
  // §6). Turbo draws a stream a frame after it is handed over; a move queued
  // behind would otherwise be sent from the old elements (ledger b6, which
  // `holdTurboRequest` settles for a Turbo form). The page's own reorder
  // draws a status line and a toast, and releases its turn at once.
  //
  // Whether a block is in someone's hand is `sayMoving`'s to judge, and it
  // is judged again on every path out of here (an early return included).
  async move(item, from, before = null, { focus = false } = {}) {
    try {
      await this.moveBlock(item, from, before, { focus })
    } finally {
      this.host.sayMoving()
    }
  }

  // The page's own order, sent as it is: what the keyboard path's drop asks
  // for, and a caller that has moved the cards itself. `before` is the list's
  // cards in the order they had.
  reorder(before = null) {
    return this.move(null, null, before && new Map([ [ this.host.listTarget, before ] ]))
  }

  async moveBlock(item, from, before, { focus }) {
    this.host.refreshMoveState()
    const to = item ? item.parentElement : this.host.listTarget
    // An element that is in no container has no order to send: one the
    // answer of an earlier move has just replaced, handed over by a drag that
    // was holding it.
    if (!to) return
    // A tile picked up and let go in its own closed lane: it is where it was
    // (the lane sorts nothing), and the lane has no order the server takes
    // (`isClosed`).
    if (isClosed(to)) return
    if (before) {
      this.restoreTo ||= new Map()
      for (const [ container, items ] of before) {
        if (!this.restoreTo.has(container)) this.restoreTo.set(container, items)
      }
    }
    this.reordersQueued = (this.reordersQueued || 0) + 1
    if (to !== this.host.listTarget || (from && from !== to)) this.sendHeldEdits()
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    // The block's name is read now, for a put-back's announcement: by then
    // the element may be one the answer has replaced.
    const title = focus ? titleOf(item) : null
    await this.queueMove({ item, from, to, csrfToken, focus, title, stoodBack: false, held: from && from !== to ? this.hold(item) : [] })
  }

  // A BLOCK ON ITS WAY TO ANOTHER CONTAINER IS HELD STILL, from its drop
  // until its answer is drawn or it is put back: the element and, for a
  // tile, its form's panel are made `inert` (after the forms were told to
  // send, so a field that loses the focus to it has been read). Its answer
  // replaces both. Grabbed again in the meantime -- the pointer is still on
  // the grip -- a second drag would hold an element the answer then takes
  // out of the document: that drag's move would have nothing to send, and
  // the card the answer drew would stay wherever the old tile happened to
  // be, an order the server never took. And words typed into the form in
  // that moment would go with the form. `sendMove` lets go in a `finally`,
  // whatever the turn came to; an element the answer replaced is gone, and
  // its successor was never held.
  hold(item) {
    const held = [ item, document.getElementById(`block-${item.dataset.blockId}-panel`) ].filter(Boolean)
    for (const element of held) element.inert = true
    return held
  }

  // The queue lets the next write go whatever a task does (`enqueue`
  // releases in a `finally`), so nothing here is caught to keep it alive --
  // and nothing is swallowed: an error is reported where the system tests'
  // collector and a developer's console see it.
  queueMove(move) {
    this.moveHolds += 1
    return enqueue((isCurrent) => this.sendMove(move, isCurrent), { generation: this.host.generation })
      .catch((error) => console.error(error))
      .finally(() => { this.moveHolds = Math.max(0, this.moveHolds - 1); this.host.sayMoving() })
  }

  // One move's turn in the queue, and its bookkeeping: unless the move has
  // queued itself again (`takeTurn` answers "again"), it is counted off and
  // what it held still is let go -- in a `finally`, so a turn that throws
  // leaves neither a count that never reaches zero (`restoreTo` would then
  // be kept for good) nor a block nobody can touch.
  //
  // A menu's move then gives the focus back (`focusMoved`) -- here, after the
  // hold is let go: an inert element takes no focus. ONLY WHERE THE MOVE TOOK
  // IT: a block that was held (it changed containers, and `inert` drops the
  // focus) or whose move did not stand (`move.undone`: it was put back, or
  // the list was redrawn around it). A move along one container that was
  // saved touched the focus once, in `MenuMoves#relocate`, and has nothing to
  // give back: a person who has since clicked the blank page has the focus on
  // <body> on purpose, and pulling it to the card's handle would scroll the
  // page under them. A move that did not stand also says so, over the
  // announcement `relocate` made of it.
  async sendMove(move, isCurrent) {
    let again = false
    try {
      again = (await this.takeTurn(move, isCurrent)) === "again"
    } finally {
      if (!again) {
        this.settle(move)
        for (const element of move.held) element.inert = false
        if (move.focus && isCurrent()) {
          if (move.held.length > 0 || move.undone) this.focusMoved(move.item)
          if (move.undone) this.host.announce(messages(this.host.element).t("components.editor_screen.block_moves.back", { block: move.title }))
        }
      }
    }
  }

  // WHERE THE FOCUS IS AFTER A MENU'S MOVE (sections spec §1: the menu is
  // the keyboard's path, so it must not end at the top of the page). When
  // the turn of a move that took the focus away has ended (`sendMove` says
  // which), the element that stands for the block NOW takes it, whatever the
  // turn came to:
  // - saved, between containers: the block was redrawn, a card for a tile or
  //   a tile for a card (`move_streams`), and that new element is the one;
  // - saved, to another lane of its section: the tile itself, free again;
  // - refused, failed or not sent because its form was not saved: the block
  //   was put back (`putBack`) -- or, where a refusal redrew the whole list,
  //   is one of the new elements, found by the block's id.
  // Only when nothing has the focus: a person who went somewhere else while
  // the request was out is left there. "Nothing" includes an element that is
  // no longer drawn, which is where Chrome leaves the focus for a moment
  // after a dialog or a menu closes (`admin--ui--dialog#returnFocus`).
  focusMoved(item) {
    const active = document.activeElement
    if (active && active !== document.body && active.getClientRects().length > 0) return

    const element = item.isConnected ? item : this.standingFor(item.dataset.blockId)
    if (element) this.host.focusItem(element)
  }

  // The element that stands for a block in its container now: its card in
  // the list or its tile in a lane (never its form's panel, which is no
  // child of either).
  standingFor(blockId) {
    return this.host.containers().flatMap((container) => itemsOf(container)).find((element) => element.dataset.blockId === blockId)
  }

  // Counts a move off, once: `takeTurn` does it as soon as the answer is in,
  // because what it does next depends on whether another move still waits.
  settle(move) {
    if (move.settled) return
    move.settled = true
    this.reordersQueued -= 1
  }

  async takeTurn(move, isCurrent) {
    const { item, to, csrfToken } = move
    // The element is no longer where this move put it. It was put back (an
    // earlier request failed, or its own form was not saved); it was dropped
    // again, into another container, before this request went -- that drop's
    // own request sends where it is now, announced from where the server has
    // it (`origin` below); or the screen it was made on has been redrawn (a
    // refusal's list, a section's lanes: new elements, and these are out of
    // the document). Either way there is no order of this move's left to
    // send; sending the container as it is would announce an arrival that is
    // not in it. And when nothing else waits, what the screen shows is what
    // stays: the orders remembered are of elements that may be gone.
    if (!to.isConnected || (item && item.parentElement !== to)) {
      this.settle(move)
      if (this.reordersQueued === 0) this.restoreTo = null
      return
    }

    // Where the server has the item: the container it is in in `restoreTo`,
    // which is not always the one this drop took it from -- dropped into one
    // lane and then into another before the first request went, it is still
    // where it began, and that is what the server checks `moved_from`
    // against. `from` when no order is remembered that names it.
    const origin = item && (this.takenFrom(item) || move.from)
    const crossing = Boolean(origin && origin !== to)
    const structural = crossing || to !== this.host.listTarget

    if (crossing) {
      const state = this.formState(item)
      if (state === "unsent" && !move.stoodBack) {
        move.stoodBack = true
        this.formOf(item).saveNow()
        // Not awaited: it runs after this task has given up its turn.
        this.queueMove(move)
        return "again"
      }
      if (state !== "saved") {
        this.settle(move)
        if (isCurrent()) {
          move.undone = true
          this.putBack()
          errorToast(messages(this.host.element).t("components.editor_screen.section_card.unsaved_move"), "toast-move-refused")
        }
        return
      }
    }

    const sent = itemsOf(to)
    const answer = await sendOrder(this.host.reorderUrlValue, {
      headers: {
        "Content-Type": "application/json",
        Accept: "text/vnd.turbo-stream.html",
        "X-CSRF-Token": csrfToken,
        [TAB_HEADER]: TAB
      },
      body: JSON.stringify({
        ids: sent.map((element) => element.dataset.blockId),
        ...placeOf(to),
        moved_from: crossing ? { [item.dataset.blockId]: placeOf(origin) } : {}
      })
    })
    this.settle(move)
    // The page was replaced while the request was on its way: its cards,
    // its base field and its toast region are gone.
    if (!isCurrent()) return

    // Asked as the answer arrives, before anything of it is drawn: see
    // `renderKeepingForms`.
    const keepForms = answer.outcome === "answered" && !answer.ok && this.formsHoldText()
    if (answer.outcome === "answered") {
      if (keepForms) this.renderKeepingForms(answer.text)
      else Turbo.renderStreamMessage(answer.text)
      if (answer.ok) {
        this.restoreTo = this.reordersQueued > 0 ? this.taken(to, sent) : null
        if (crossing) {
          await streamsApplied()
          this.followRedraw(item)
        }
        return
      }
    }

    move.undone = true
    this.putBack()
    if (answer.outcome !== "answered") orderErrorToast(answer.outcome, "toast-order-error")
    else if (structural) await streamsApplied()
    if (keepForms) this.sayReloadLater()
  }

  // A REFUSAL'S LIST IS NOT DRAWN OVER TEXT THAT IS ONLY ON THIS SCREEN. A
  // refused move that named a section is answered with the whole list as the
  // server has it (`Admin::Answers::BlockRefused#reordered`: the screen was behind),
  // and that replaces every form. A form paused by a 409 holds the one copy
  // of what was typed, and its bar has said in so many words that the text
  // stays to be copied; a 409 and a refused move have the same cause, a
  // second editor on this page, so the two arrive together. The same for a
  // save that was refused or is being retried, and for words typed into any
  // form while this move was on the wire -- which is why it is asked when
  // the answer arrives, not when the move was made.
  //
  // So while any form here holds text the server does not have
  // (`formsHoldText`), the answer is drawn WITHOUT its list: the status line
  // and the reason, as the server said them. The block goes back where it
  // was (`putBack`, as after every refusal), a line under the reason says to
  // reload once the text is safe, and nothing else on the screen changes.
  // The screen stays behind until then -- a move made from it may be refused
  // again -- which is the lesser harm. The server sends the list either way;
  // it cannot know what the forms hold.
  //
  // The list's stream is stopped as Turbo is about to draw it
  // (`turbo:before-stream-render`, which every stream of the answer
  // dispatches inside `renderStreamMessage`'s own append, so the listener
  // is there for exactly this answer's).
  renderKeepingForms(text) {
    const keepList = (event) => {
      if (event.target.getAttribute("target") === this.host.listTarget.id) event.preventDefault()
    }
    document.addEventListener("turbo:before-stream-render", keepList)
    try {
      Turbo.renderStreamMessage(text)
    } finally {
      document.removeEventListener("turbo:before-stream-render", keepList)
    }
  }

  // Whether any autosave form of the block list holds text the server does
  // not: a form that did not end clean (`admin--saving--autosave#clean`: paused,
  // refused, invalid, offline), or one with an edit still to be sent or
  // answered. The questions the write queue asks of a form (`settled()` in
  // `saving/queue_core.js`), put to the forms a redrawn list would replace --
  // which include the forms of what a script moved out of the list
  // (`[data-editing-away]`: a section's settings in the editor's rail), since
  // a redrawn list brings their section's card again.
  formsHoldText() {
    return this.listForms()
      .map((form) => this.host.application.getControllerForElementAndIdentifier(form, "admin--saving--autosave"))
      .some((form) => form && (!form.clean() || form.outstanding() || !form.unchanged()))
  }

  // The line under a refusal's reason whose list was not drawn. Written into
  // the alert the answer has just drawn (its turn in the queue is held until
  // then), in the alert's own markup: a copy of the reason's line with the
  // sentence in it. The next answer that writes the alert takes it away.
  sayReloadLater() {
    const reason = document.querySelector("#content-blocks-alert > p")
    if (!reason) return

    const line = reason.cloneNode(true)
    line.lastElementChild.textContent = messages(this.host.element).t("components.editor_screen.section_card.reload_later")
    reason.after(line)
  }

  // `restoreTo` after the server took `sent` as the order of `to`, while
  // other moves still wait: that container's order is now the one to go back
  // to, and an element that arrived in it is no longer one of the container
  // it came from. Every OTHER container stays as it was remembered -- what
  // the screen shows of them may be a move that has not been sent yet. (With
  // nothing remembered, as after a `putBack`, the order sent is all there is
  // to remember: the screen showed what the server had.)
  taken(to, sent) {
    const taken = new Map(this.restoreTo || [])
    for (const [ container, items ] of taken) taken.set(container, items.filter((element) => !sent.includes(element)))
    return taken.set(to, sent)
  }

  // The container `restoreTo` has an element in, or undefined.
  takenFrom(item) {
    for (const [ container, items ] of this.restoreTo || []) {
      if (items.includes(item)) return container
    }
  }

  // A saved move between containers has had its block redrawn: `item` is out
  // of the document and another element stands for the block. The orders
  // still remembered name the old one, and `putBack` leaves alone what it
  // does not know -- so a later move of the new card that failed would stay
  // on screen. The new element takes the old one's place in them. (A tile
  // that changed lanes inside its section was not redrawn, and is itself.)
  followRedraw(item) {
    if (item.isConnected || !this.restoreTo) return
    const redrawn = this.standingFor(item.dataset.blockId)
    if (!redrawn) return

    for (const [ container, items ] of this.restoreTo) {
      this.restoreTo.set(container, items.map((element) => (element === item ? redrawn : element)))
    }
  }

  // Every autosave form on the screen sends what it holds, now: an edit
  // inside its debounce is queued ahead of the move being made (see `move`).
  // An unchanged form sends nothing and a paused one refuses, as always.
  sendHeldEdits() {
    for (const form of this.listForms()) {
      this.host.application.getControllerForElementAndIdentifier(form, "admin--saving--autosave")?.saveNow()
    }
  }

  // The autosave forms of the block list, and of every element of it a
  // script moved elsewhere (`[data-editing-away]`, `editing/merge.js`).
  listForms() {
    const selector = "form[data-controller~='admin--saving--autosave']"
    return [ ...this.host.element.querySelectorAll(selector), ...document.querySelectorAll(`[data-editing-away] ${selector}`) ]
  }

  // The autosave controller of a block's own form: in its card, or -- for a
  // tile -- in its panel under the lanes, which is no descendant of the tile
  // (`Admin::EditorScreen::BlockCardComponent.panel_id`). Undefined for a
  // block with no form: an unavailable type.
  formOf(item) {
    const holder = document.getElementById(`block-${item.dataset.blockId}-panel`) || item
    const form = holder.querySelector("form[data-controller~='admin--saving--autosave']")
    return form ? this.host.application.getControllerForElementAndIdentifier(form, "admin--saving--autosave") : undefined
  }

  // Whether what a block's form holds is on the server: "saved"; "unsent",
  // an edit debounced, queued, on the wire or typed since; or "refused", a
  // form whose last save did not land (`admin--saving--autosave#clean`). A
  // block with no form has nothing to lose.
  formState(item) {
    const form = this.formOf(item)
    if (!form) return "saved"
    if (!form.clean()) return "refused"
    return form.outstanding() || !form.unchanged() ? "unsent" : "saved"
  }

  // Puts every block back where `restoreTo` has it (see `move`): first into
  // its container, then into its place there. Only elements still in the
  // document take part, each put into a place one of them holds now: a card
  // streamed in since (an Add queued in between) stays where it is, one
  // removed since is skipped, and a list an Undo re-rendered -- new elements
  // throughout -- is left exactly as the server drew it. The same for a
  // section's lanes a save or a refusal has redrawn: the row is new elements,
  // so a lane remembered from before is out of the document and is skipped
  // with its tiles. A card picked up by keyboard in the meantime is let go
  // first: it goes back with the rest, and its remembered place would no
  // longer be true.
  putBack() {
    const remembered = Array.from(this.restoreTo || []).filter(([ container ]) => container.isConnected)
    this.restoreTo = null
    this.host.letGo()

    for (const [ container, items ] of remembered) {
      for (const item of items) {
        if (item.isConnected && item.parentElement !== container) container.append(item)
      }
    }
    for (const [ container, items ] of remembered) {
      const order = items.filter((item) => item.parentElement === container)
      order.forEach((item, index) => {
        const holder = itemsOf(container).filter((candidate) => order.includes(candidate))[index]
        if (holder !== item) container.insertBefore(item, holder)
      })
    }
    this.host.refreshMoveState()
  }
}
