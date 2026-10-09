import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import Sortable from "sortablejs"
import { currentGeneration, enqueue, holdTurboRequest, syncBases } from "autosave/queue"
import { errorToast, orderErrorToast, sendOrder, streamsApplied } from "autosave/order_request"
import { messages } from "i18n/messages"

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
// CONTAINERS (sections spec §3.1, §4.4). The list is one place a block can
// be; each column of each section is another -- a `lane` target, whose direct
// children are exactly its tiles (`Admin::EditorScreen::SectionLanesComponent`:
// the lane's "+" sits after it, never in it), as the list's are exactly the
// cards. A block's element in its container (`itemsOf`) is a card in the list
// and a `tile` in a lane; both carry `data-block-id`, which is all a move
// reads. Each container is a Sortable of one group, so a tile is dragged
// along its lane, to another lane and out into the list, and a card into a
// lane -- except a section's card, which no lane takes (`accepts`: a section
// never holds a section). The order of ONE container is what a request sends
// (`move`), with where the dragged block came from when that is another one.
//
// Each card's "⋯" menu has Move up and Move down; the first card's Move up
// and the last card's Move down are disabled. `refreshMoveState` keeps that
// right in the browser, for every container: it runs on connect, after every
// move this controller sends, and whenever a container's children change (a
// drop, a keyboard step, a card streamed in by Add block or Duplicate, one
// removed by Delete, the whole list replaced by an Undo) -- the server
// renders the right state for the cards it sends, but a streamed insertion
// or removal touches no neighbour, so it can only be corrected here.
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
  static targets = ["card", "list", "lane", "tile", "announcer"]
  static values = { reorderUrl: String }

  // Every block request also carries the page settings form's current base
  // (`X-Page-Base-Updated-At`): a block write touches the page, and the
  // server only moves that form's base forward when the one it holds was
  // still current (`Admin::ContentBlocksController#page_base_streams`).
  // Turbo's own submissions inside this section (add, duplicate, delete)
  // get it here; `move` below adds it itself; a card's autosave through
  // `admin--autosave`'s `pageBaseId` value.
  static pageBaseId = "page-base-updated-at"

  // What the lanes need is made here, not in `connect`: Stimulus tells a
  // controller of the targets already in the page (`laneTargetConnected`)
  // BEFORE it calls `connect`. The list's own children are the only place a
  // Duplicate's copy arrives (`focusCopy`).
  initialize() {
    this.laneSortables = new Map()
    this.moveStateObserver = new MutationObserver((mutations) => {
      this.refreshMoveState()
      this.focusCopy(mutations.filter((mutation) => mutation.target === this.listTarget))
    })
  }

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
    this.moveStateObserver.observe(this.listTarget, { childList: true })
    this.refreshMoveState()
    this.sortable = Sortable.create(this.listTarget, {
      ...this.sortableOptions(true),
      onMove: (event, pointer) => this.besideSection(event, pointer)
    })
  }

  // A lane is a Sortable for as long as it is in the page. The lanes of a
  // section are replaced as a row by a save that changed its number of
  // columns, by a refused add and with the whole list (`Admin
  // ::ContentBlocksController#section_structure_streams`, `#blocks_list_stream`):
  // the row that comes is new elements, each made a Sortable here, and the
  // one that left is destroyed below.
  //
  // NOT FOR A LANE THAT WAS ONLY MOVED. A section's card dragged along the
  // list, or stepped by the keyboard, is taken out of the document and put
  // back with every lane in it, and Stimulus reports that as each lane
  // disconnected and connected again. `Sortable#destroy` ends whatever drag
  // is under way -- its `_onDrop` works on the one drag the library knows of,
  // whichever Sortable it started in -- so destroying the lanes of the very
  // card being dragged dropped that card after its first step. A lane that is
  // back in the document by the time Stimulus says it left is the same lane:
  // it keeps its Sortable, and its observer.
  laneTargetConnected(lane) {
    if (this.laneSortables.has(lane)) return

    this.laneSortables.set(lane, Sortable.create(lane, this.sortableOptions((to, _from, dragged) => this.accepts(to.el, dragged))))
    this.moveStateObserver.observe(lane, { childList: true })
    this.refreshMoveState([ lane ])
  }

  laneTargetDisconnected(lane) {
    if (lane.isConnected) return

    this.laneSortables.get(lane)?.destroy()
    this.laneSortables.delete(lane)
  }

  // A lane does not accept a section (sections spec §3.2, §4.4): asked by
  // SortableJS for every lane the pointer passes over, so a section's card
  // dragged across another section's lanes never lands in one and the list
  // goes on taking it. The markup's own word for "this card holds blocks"
  // (`data-container`, `Admin::EditorScreen::SectionCardComponent`), not the
  // type's name. The server refuses the same move
  // (`ContentBlocks::Reorder::NESTED`).
  accepts(_lane, dragged) {
    return !dragged.hasAttribute("data-container")
  }

  // Whether the LIST may put the dragged block before or after the card
  // under the pointer (SortableJS `onMove`, asked on every sample of the
  // pointer: `false` leaves the block where it is).
  //
  // A BLOCK OVER A SECTION'S CARD IS MORE OFTEN ON ITS WAY INTO IT THAN PAST
  // IT. Left to itself the list sorts the dragged block to the other side of
  // whatever card the pointer enters, at once -- and a section's card is
  // entered through its edge on the way to a lane. A card dragged up from
  // below jumped above the section the moment it touched it, which pushed
  // the section, and the lane being aimed at, down from under the pointer;
  // chased there, the card went into the lane, the section jumped back, and
  // the pointer -- now in the section's lower edge -- had the list take the
  // card out again. A tile crossing the gap between two lanes was taken out
  // into the list on the way. So over a section's card the list only does
  // what the pointer's place says:
  // - above the lanes (the header): the block may go BEFORE the section;
  // - below them (the open form, the lower edge): AFTER it;
  // - level with them: nothing. A lane the pointer is over takes the block
  //   itself, being asked first; between lanes it stays where it is.
  // A section's card being dragged is sorted as any card is (no lane takes
  // it, `accepts`), and so is a block over a collapsed section, which has no
  // lanes on screen.
  besideSection(event, pointer) {
    const section = event.related
    if (!section.hasAttribute("data-container") || event.dragged.hasAttribute("data-container")) return true
    const lanes = section.querySelector('[data-admin--section-target="lanes"]')?.getBoundingClientRect()
    if (!lanes || lanes.height === 0) return true

    if (pointer.clientY < lanes.top) return !event.willInsertAfter
    if (pointer.clientY > lanes.bottom) return event.willInsertAfter
    return false
  }

  // One set of options for the list and every lane; `put` is what the
  // container takes from another one.
  sortableOptions(put) {
    return {
      // One group, so a drag can end in another container than it began in.
      group: { name: "blocks", put },
      draggable: "[data-block-id]",
      // A card's handle and a tile's grip. The grip is a `<span>` for the
      // pointer only (`Admin::EditorScreen::BlockTileComponent`).
      handle: ".admin-block-card__handle, .admin-block-tile__grip",
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
      // Every container's order before the drag (`move` puts it back if the
      // request fails), read after the clone lost its targets. `onEnd` is
      // called once, on the Sortable the drag began in, wherever it ended:
      // `event.from` is that container, and the item's parent the one it is
      // in now.
      onStart: () => {
        this.makeCloneInert()
        this.dragSnapshot = this.snapshot()
      },
      onEnd: (event) => this.move(event.item, event.from, this.dragSnapshot)
    }
  }

  // The places a block can be: the page's own list, then every lane.
  containers() {
    return [ this.listTarget, ...this.laneTargets ]
  }

  // A container's blocks, in its order: its direct children that stand for
  // one (a card, a tile -- and, for the moment between a drop and its
  // answer, a card resting in a lane or a tile in the list).
  itemsOf(container) {
    return Array.from(container.children).filter((child) => child.dataset.blockId)
  }

  // What the server calls a container (`ContentBlocks::Reorder`): a section
  // and one of its columns, or neither for the page's own list.
  placeOf(container) {
    return { section_id: container.dataset.sectionId || null, column: container.dataset.column || null }
  }

  // Every container's order as it is now: what a caller takes BEFORE it
  // moves an element, for `move` to go back to.
  snapshot() {
    return new Map(this.containers().map((container) => [ container, this.itemsOf(container) ]))
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
    this.moveStateObserver.disconnect()
    this.sortable?.destroy()
    // The lanes are told to go after this (`laneTargetDisconnected`), which
    // would keep the Sortable of one that is still in a document.
    for (const sortable of this.laneSortables.values()) sortable.destroy()
    this.laneSortables.clear()
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

  // Move up is disabled on the first block of a container, Move down on the
  // last. Only the attribute is touched, so it is idempotent and cheap to run
  // on every child-list change. The button is the item's OWN: a section's
  // card holds the blocks in it, and their Move items are not the section's.
  refreshMoveState(containers = this.containers()) {
    for (const container of containers) {
      const items = this.itemsOf(container)
      items.forEach((item, index) => {
        const own = (direction) => Array.from(item.querySelectorAll(`[data-move="${direction}"]`))
          .find((button) => button.closest("[data-block-id]") === item)
        const up = own("up")
        const down = own("down")
        if (up) up.disabled = index === 0
        if (down) down.disabled = index === items.length - 1
      })
    }
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
  // task's own brief): swaps this block with its immediate neighbour in its
  // container's own order (`itemsOf`: the list for a card, its lane for a
  // tile), then fires the exact same request a drag's `onEnd` does. A
  // disabled item (first card's Move up, last card's Move down) never gets
  // here; the index guards are a belt for a programmatic call. The menu has
  // closed by the time the card moves, so focus goes to the card's handle
  // rather than being lost with the DOM move (a tile has no handle to take
  // it: its grip is for the pointer).
  moveUp(event) {
    const item = this.itemFor(event)
    const items = this.itemsOf(item.parentElement)
    const index = items.indexOf(item)
    if (index <= 0) return
    const before = this.snapshot()
    item.parentElement.insertBefore(item, items[index - 1])
    this.moved(item, before)
  }

  moveDown(event) {
    const item = this.itemFor(event)
    const items = this.itemsOf(item.parentElement)
    const index = items.indexOf(item)
    if (index < 0 || index >= items.length - 1) return
    const before = this.snapshot()
    item.parentElement.insertBefore(items[index + 1], item)
    this.moved(item, before)
  }

  moved(item, before) {
    this.focusHandle(item)
    this.move(item, item.parentElement, before)
  }

  // THE ONE SENDER of a block's move: a drop's `onEnd`, the menu's Move
  // up/down and (through `reorder`) the keyboard path all end here. `item` is
  // the element that was moved -- null for "send the list's order as it is"
  // -- `from` the container it left, and `before` every container's order as
  // it was before the element was moved (`snapshot`).
  //
  // Queued with every other write on the screen (`autosave/queue.js`): the
  // order is read when the request is sent (a Move up/down made while an
  // autosave was in flight still sends the final order), and the page base
  // it carries is the freshest one. The answer's page base is written into
  // the hidden field before the next request goes.
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
  // (`autosave/order_request.js`, which also says what this used to do with
  // an expired session's sign-in page):
  // - a Turbo Stream is rendered, whatever its status. A refusal (403, 422:
  //   the status line and the reason) is the endpoint's own answer -- and
  //   also means the order was not saved, so the cards go back;
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
  // the form (`Admin::ContentBlocksController#move_streams`) -- the one time
  // a form on this screen is replaced while its block stays. A form is what
  // holds an edit that is not saved yet, so:
  // - every autosave form is told to send what it holds as the move is
  //   queued (`sendHeldEdits`), which puts those saves AHEAD of the move. The
  //   same before a move inside a lane, which redraws nothing if it is saved
  //   but the whole list if it is refused (below);
  // - when the move's turn comes, the block's own form must have ended saved
  //   (`formState`). One that did not end clean -- paused by a 409, refused,
  //   invalid, offline -- is not moved: its text is on this screen and
  //   nowhere else, and the 409 bar has promised it stays. Everything goes
  //   back (`putBack`) and a toast says to reload or fix the block first;
  // - one whose edit is still on its way stands back ONCE. That is an edit
  //   typed while the form's own save was on the wire: `admin--autosave`
  //   sends it as that save's follow-up, queued only when the save is
  //   answered -- behind this move. Sent in its turn, the move's answer would
  //   draw the form without those words, and on a base the follow-up then
  //   makes stale. So the form is told to send again, the move is queued
  //   again behind it, and if the form is still not saved when that turn
  //   comes (a save waiting out a retry) the move is given up like a refused
  //   one.
  // A move within one container moves the element and nothing else, as it
  // always did, and never waits on a form.
  //
  // THE ANSWER IS DRAWN BEFORE THE NEXT WRITE GOES, for a move that names a
  // section or changes containers (`streamsApplied`). Its answer changes what
  // the next task reads: the moved block's new element and form, or -- for a
  // refusal -- the whole list as the server has it (`blocks_list_stream`:
  // the screen was behind, sections spec §6). Turbo draws a stream a frame
  // after it is handed over; a move queued behind would otherwise be sent
  // from the old elements (ledger b6, which `holdTurboRequest` settles for a
  // Turbo form). The page's own reorder draws a status line and a toast, and
  // releases its turn at once as before.
  async move(item, from, before = null) {
    this.refreshMoveState()
    const to = item ? item.parentElement : this.listTarget
    if (before) {
      this.restoreTo ||= new Map()
      for (const [ container, items ] of before) {
        if (!this.restoreTo.has(container)) this.restoreTo.set(container, items)
      }
    }
    this.reordersQueued = (this.reordersQueued || 0) + 1
    if (to !== this.listTarget || (from && from !== to)) this.sendHeldEdits()
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    await this.queueMove({ item, from, to, csrfToken, stoodBack: false })
  }

  // The page's own order, sent as it is: what the keyboard path's drop asks
  // for, and a caller that has moved the cards itself. `before` is the list's
  // cards in the order they had.
  reorder(before = null) {
    return this.move(null, null, before && new Map([ [ this.listTarget, before ] ]))
  }

  queueMove(move) {
    return enqueue((isCurrent) => this.sendMove(move, isCurrent), { generation: this.generation }).catch(() => {})
  }

  // One move's turn in the queue (see `move`).
  async sendMove(move, isCurrent) {
    const { item, to, csrfToken } = move
    // The element is no longer where this move put it. It was put back (an
    // earlier request failed, or its own form was not saved), it was moved on
    // by a later drop -- whose own request sends where it is now -- or the
    // screen it was made on has been redrawn (a refusal's list, a section's
    // lanes: new elements, and these are out of the document). Either way
    // there is no order of this move's left to send; sending the container
    // as it is would announce an arrival that is not in it. And when nothing
    // else waits, what the screen shows is what stays: the orders remembered
    // are of elements that may be gone.
    if (!to.isConnected || (item && item.parentElement !== to)) {
      this.reordersQueued -= 1
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
    const structural = crossing || to !== this.listTarget

    if (crossing) {
      const state = this.formState(item)
      if (state === "unsent" && !move.stoodBack) {
        move.stoodBack = true
        this.formOf(item).saveNow()
        // Not awaited: it runs after this task has given up its turn.
        this.queueMove(move)
        return
      }
      if (state !== "saved") {
        this.reordersQueued -= 1
        if (isCurrent()) {
          this.putBack()
          errorToast(messages(this.element).t("components.editor_screen.section_card.unsaved_move"), "toast-move-refused")
        }
        return
      }
    }

    const sent = this.itemsOf(to)
    const answer = await sendOrder(this.reorderUrlValue, {
      headers: {
        "Content-Type": "application/json",
        Accept: "text/vnd.turbo-stream.html",
        "X-CSRF-Token": csrfToken,
        "X-Page-Base-Updated-At": document.getElementById(this.constructor.pageBaseId)?.value || ""
      },
      body: JSON.stringify({
        ids: sent.map((element) => element.dataset.blockId),
        ...this.placeOf(to),
        moved_from: crossing ? { [item.dataset.blockId]: this.placeOf(origin) } : {}
      })
    })
    this.reordersQueued -= 1
    // The page was replaced while the request was on its way: its cards,
    // its base field and its toast region are gone.
    if (!isCurrent()) return

    if (answer.outcome === "answered") {
      syncBases(answer.text, [ this.constructor.pageBaseId ])
      Turbo.renderStreamMessage(answer.text)
      if (answer.ok) {
        this.restoreTo = this.reordersQueued > 0 ? this.taken(to, sent) : null
        if (crossing) {
          await streamsApplied()
          this.followRedraw(item)
        }
        return
      }
    }

    this.putBack()
    if (answer.outcome !== "answered") orderErrorToast(answer.outcome, "toast-order-error")
    else if (structural) await streamsApplied()
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
    const redrawn = this.containers().flatMap((container) => this.itemsOf(container))
      .find((element) => element.dataset.blockId === item.dataset.blockId)
    if (!redrawn) return

    for (const [ container, items ] of this.restoreTo) {
      this.restoreTo.set(container, items.map((element) => (element === item ? redrawn : element)))
    }
  }

  // Every autosave form on the screen sends what it holds, now: an edit
  // inside its debounce is queued ahead of the move being made (see `move`).
  // An unchanged form sends nothing and a paused one refuses, as always.
  sendHeldEdits() {
    for (const form of this.element.querySelectorAll("form[data-controller~='admin--autosave']")) {
      this.application.getControllerForElementAndIdentifier(form, "admin--autosave")?.saveNow()
    }
  }

  // The autosave controller of a block's own form: in its card, or -- for a
  // tile -- in its panel under the lanes, which is no descendant of the tile
  // (`Admin::BlockCardComponent.panel_id`). Undefined for a block with no
  // form: an unavailable type.
  formOf(item) {
    const holder = document.getElementById(`block-${item.dataset.blockId}-panel`) || item
    const form = holder.querySelector("form[data-controller~='admin--autosave']")
    return form ? this.application.getControllerForElementAndIdentifier(form, "admin--autosave") : undefined
  }

  // Whether what a block's form holds is on the server: "saved"; "unsent",
  // an edit debounced, queued, on the wire or typed since; or "refused", a
  // form whose last save did not land (`admin--autosave#clean`). A block
  // with no form has nothing to lose.
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
    if (this.picked) this.clearPicked(this.picked)

    for (const [ container, items ] of remembered) {
      for (const item of items) {
        if (item.isConnected && item.parentElement !== container) container.append(item)
      }
    }
    for (const [ container, items ] of remembered) {
      const order = items.filter((item) => item.parentElement === container)
      order.forEach((item, index) => {
        const holder = this.itemsOf(container).filter((candidate) => order.includes(candidate))[index]
        if (holder !== item) container.insertBefore(item, holder)
      })
    }
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

  // The block an action was pressed in: the nearest card or tile. A tile is
  // inside its section's card, which is what `cardFor` would answer.
  itemFor(event) {
    return event.currentTarget.closest('[data-admin--blocks-target="card"], [data-admin--blocks-target="tile"]')
  }
}
