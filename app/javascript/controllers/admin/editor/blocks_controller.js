import { Controller } from "@hotwired/stimulus"
import { accepts, besideSection, isClosed, refreshMoveState, snapshot } from "editor/containers"
import { loadSortable, makeCloneInert, sortableOptions } from "editor/drag"
import { MoveQueue, currentGeneration } from "editor/move_queue"
import { MenuMoves } from "editor/menu_moves"
import { KeyboardMoves } from "editor/keyboard_moves"
import { watchWrites } from "editor/adding"

// The page editor's block list (cs-studio spec §5.1/§6.1; sections spec
// §3.1, §4.4): its targets, its Sortables and the actions its markup names,
// each handing its concern to a module of the `editor` topic.
//
// Targets. `list` is the page's own list, whose direct children are exactly
// the cards (`Admin::EditorScreen::BlockCardComponent`'s top-level wrapper;
// the "Add block" row sits after it, not in it). Each `lane` is a column of
// a section, whose direct children are exactly its `tile`s
// (`Admin::EditorScreen::SectionLanesComponent`). `announcer` is the live
// region a move is said in, `destination` the Move dialog's select. The
// controller's element is the whole Blocks section, not the list.
//
// Where each concern is:
// - `editor/containers`: pure reads of the containers;
// - `editor/drag`: the SortableJS options and the inert clone of a drag;
// - `editor/move_queue`: `move`, the one sender of a reorder, through the
//   write queue (`saving/queue.js`), with its put-back and its answer;
// - `editor/menu_moves`: the "⋯" menu's moves and the Move dialog;
// - `editor/keyboard_moves`: the handle's Space / arrows / Escape path;
// - `editor/adding`: add, duplicate, delete and Undo held in the queue.
//
// `move`, `dragging`, `sayMoving()` and `containers()` are read by the browser
// tests, the `moving` and `toggled` events by `admin--editing--{live,hold}`.
export default class extends Controller {
  static targets = ["card", "list", "lane", "tile", "announcer", "destination"]
  static values = { reorderUrl: String }

  // What the lanes need is made here, not in `connect`: Stimulus tells a
  // controller of the targets already in the page (`laneTargetConnected`)
  // BEFORE it calls `connect`. What is observed is every container's own
  // children, the list's and each lane's, and those are the places a
  // Duplicate's copy arrives in (`focusCopy`): a card's copy in the list, a
  // tile's in its lane.
  initialize() {
    this.laneSortables = new Map()
    this.queue = new MoveQueue(this)
    this.menu = new MenuMoves(this)
    this.keyboard = new KeyboardMoves(this)
    this.moveStateObserver = new MutationObserver((mutations) => {
      this.refreshMoveState()
      this.writes?.focusCopy(mutations)
    })
  }

  connect() {
    this.generation = currentGeneration()
    this.writes = watchWrites(this)
    this.moveStateObserver.observe(this.listTarget, { childList: true })
    this.refreshMoveState()
    this.element.dataset.sortable = "pending"
    this.sortableLoaded = loadSortable().then((Sortable) => {
      // Gone before SortableJS arrived: nothing to make, nothing to destroy.
      if (!this.element.isConnected || this.sortable) return

      this.Sortable = Sortable
      this.sortable = Sortable.create(this.listTarget, {
        ...this.dragOptions(true),
        onMove: (event, pointer) => besideSection(event, pointer)
      })
      // The lanes that connected while it was on its way.
      for (const lane of this.laneTargets) this.makeLane(lane)
      this.element.dataset.sortable = "ready"
    })
  }

  // A lane is a Sortable for as long as it is in the page. The lanes of a
  // section are replaced as a row by a save that changed its number of
  // columns, by a refused add and with the whole list (`Admin
  // ::Answers::BlockDrawing#section_structure_streams`, `#blocks_list_stream`):
  // the row that comes is new elements, each made a Sortable here, and the
  // one that left is destroyed below. `sort: false` for a lane that takes
  // nothing (`isClosed`): its tiles are dragged OUT of it, and not along it.
  //
  // NOT FOR A LANE THAT WAS ONLY MOVED. A section's card dragged along the
  // list, or stepped by the keyboard, is taken out of the document and put
  // back with every lane in it, and Stimulus reports that as each lane
  // disconnected and connected again. `Sortable#destroy` ends whatever drag
  // is under way -- its `_onDrop` works on the one drag the library knows of,
  // whichever Sortable it started in -- so destroying the lanes of the very
  // card being dragged would drop that card after its first step. A lane
  // that is back in the document by the time Stimulus says it left is the
  // same lane: it keeps its Sortable, and its observer.
  //
  // A lane that connects before SortableJS has arrived is made with the rest
  // (`connect`): `this.Sortable` is the library once it has.
  laneTargetConnected(lane) {
    if (this.Sortable) this.makeLane(lane)
  }

  makeLane(lane) {
    if (this.laneSortables.has(lane)) return

    this.laneSortables.set(lane, this.Sortable.create(lane, {
      ...this.dragOptions((to, _from, dragged) => accepts(to.el, dragged)),
      sort: !isClosed(lane)
    }))
    this.moveStateObserver.observe(lane, { childList: true })
    this.refreshMoveState([ lane ])
  }

  laneTargetDisconnected(lane) {
    if (lane.isConnected) return

    // A lane destroyed under a drag that began in it: SortableJS calls no
    // `onEnd` for `destroy()`, so the hold is let go here.
    if (this.dragging && this.Sortable?.active?.el === lane) { this.dragging = false; this.sayMoving() }
    this.laneSortables.get(lane)?.destroy()
    this.laneSortables.delete(lane)
  }

  // Every container's order before the drag (`move` puts it back if the
  // request fails), read after the clone lost its targets.
  dragOptions(put) {
    return sortableOptions({
      put,
      onStart: () => {
        this.dragging = true
        this.sayMoving()
        makeCloneInert(this.Sortable.ghost)
        this.dragSnapshot = this.snapshot()
      },
      onEnd: (event) => {
        this.dragging = false
        return this.move(event.item, event.from, this.dragSnapshot)
      }
    })
  }

  disconnect() {
    this.writes.stop()
    this.moveStateObserver.disconnect()
    this.dragging = false
    this.picked = null
    this.queue.reset()
    this.sayMoving()
    this.sortable?.destroy()
    this.sortable = null
    delete this.element.dataset.sortable
    // The lanes are told to go after this (`laneTargetDisconnected`), which
    // would keep the Sortable of one that is still in a document.
    for (const sortable of this.laneSortables.values()) sortable.destroy()
    this.laneSortables.clear()
  }

  // The places a block can be: the page's own list, then every lane; and
  // the lanes a block can be moved into.
  containers() { return [ this.listTarget, ...this.laneTargets ] }
  openLanes() { return this.laneTargets.filter((lane) => !isClosed(lane)) }

  // The reads the browser tests ask of the controller (`editor/containers`).
  snapshot() { return snapshot(this.containers()) }
  accepts(lane, dragged) { return accepts(lane, dragged) }
  besideSection(event, pointer) { return besideSection(event, pointer) }

  // The lanes are asked of the page as it is (`laneTargets` is a query), so
  // the answer is right whichever of a section's parts arrived first.
  refreshMoveState(containers = this.containers()) {
    refreshMoveState(containers, this.openLanes())
  }

  // Shows/hides one card's own field list -- purely client-side (spec §5.1
  // names no "remember this across a reload" requirement for it), so this
  // never round-trips to the server the way a drag/move does. The title
  // button is the disclosure: `aria-expanded` follows.
  toggle(event) {
    const card = this.cardFor(event)
    const hidden = card?.querySelector("[data-block-body]")?.classList.toggle("hidden")
    if (hidden === undefined) return

    event.currentTarget.setAttribute("aria-expanded", String(!hidden))
    // A collapsed card's form is closed: what it holds is sent now (not left
    // to the `focusout` the click usually causes), and then whoever holds the
    // block for this tab lets it go (`admin--editing--hold`), which waits
    // until none of the card's forms -- a section's panels included -- has a
    // save left to send.
    if (hidden) {
      for (const form of card.querySelectorAll("form[data-controller~='admin--saving--autosave']")) {
        this.application.getControllerForElementAndIdentifier(form, "admin--saving--autosave")?.saveNow()
      }
    }
    this.dispatch("toggled", { detail: { blockId: card.dataset.blockId, hidden } })
  }

  moveUp(event) { this.menu.up(this.itemFor(event)) }
  moveDown(event) { this.menu.down(this.itemFor(event)) }
  askWhere(event) { this.menu.askWhere(this.itemFor(event)) }
  moveTo() { this.menu.moveTo() }
  moveOut(event) { this.menu.out(this.itemFor(event)) }

  key(event) {
    const card = this.cardFor(event)
    if (card) this.keyboard.key(event, card)
  }

  // `currentTarget` is only set during dispatch: the handle is passed on.
  blur(event) {
    this.keyboard.blur(event.currentTarget, this.cardFor(event))
  }

  // THE ONE SENDER of a block's move: a drop's `onEnd`, the menu's moves
  // (`MenuMoves#relocate`) and, through `reorder`, the keyboard path's drop
  // all call it. What is sent, what is put back and when the answer is drawn
  // is `editor/move_queue.js`'s.
  move(item, from, before = null, options = {}) {
    return this.queue.move(item, from, before, options)
  }

  reorder(before = null) { return this.queue.reorder(before) }
  putBack() { this.queue.putBack() }
  get reordersQueued() { return this.queue.reordersQueued }

  // The keyboard path's card in hand, and its release (`MoveQueue#putBack`).
  get picked() { return this.keyboard.picked }
  set picked(card) { this.keyboard.picked = card }
  letGo() { if (this.picked) this.keyboard.clearPicked(this.picked) }

  // LIVE REFRESH (`admin--editing--live`) does not draw the list while a block
  // is in someone's hand or its move has not been answered and drawn. That is
  // not an edge to relay but a state to judge, because holds overlap (a
  // second drag begins before the first move is answered): true while ANY of
  // a drag (`dragging`), a keyboard pick-up (`picked`) or a move in the queue
  // (`MoveQueue#holds`) is open, false only when none is; the event is sent
  // when the answer changes. Every place one of the three ends calls this:
  // `onEnd`, `KeyboardMoves#clearPicked`, `move`'s end, the end of a queued
  // move, a lane destroyed under a drag (SortableJS does not call `onEnd` for
  // `destroy()`), `disconnect`.
  sayMoving() {
    // A card picked up and then taken out of the document by a redraw is not in anyone's hand.
    if (this.picked && !this.picked.isConnected) this.picked = null
    const moving = Boolean(this.dragging || this.picked || this.queue.holds > 0)
    if (moving === Boolean(this.saidMoving)) return
    this.saidMoving = moving
    this.dispatch("moving", { detail: { moving } })
  }

  // Where the focus goes on a block that was moved or copied from a menu: a
  // card's handle -- Space and the arrows move it on from there -- and a
  // tile's "⋯", its one control for moving (its grip is a `<span>` for the
  // pointer, and its face would open the form). A tile holds one menu, its
  // own; a card is asked for its handle first, so a menu inside its form
  // (the rich-text toolbar's) is never taken for it.
  focusItem(item) {
    const control = item.querySelector(".admin-block-card__handle") || item.querySelector('[data-admin--ui--menu-target="button"]')
    control?.focus()
  }

  announce(message) {
    if (this.hasAnnouncerTarget) this.announcerTarget.textContent = message
  }

  cardFor(event) {
    return event.currentTarget.closest('[data-admin--editor--blocks-target="card"]')
  }

  // The block an action was pressed in: the nearest card or tile. A tile is
  // inside its section's card, which is what `cardFor` would answer.
  itemFor(event) {
    return event.currentTarget.closest('[data-admin--editor--blocks-target="card"], [data-admin--editor--blocks-target="tile"]')
  }
}
