import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { enqueue, holdTurboRequest } from "saving/queue"
import { orderErrorToast, sendOrder } from "saving/order_request"
import { TAB_HEADER } from "editing/requests"
import { TAB } from "live/connection"
import { loadSortable } from "editor/drag"
import { messages } from "i18n/messages"
import { idOf, isFolded, openPathIn, setFolded, setOpen } from "tree/open_set"

// How long a dragged row rests on a folded parent before the parent opens.
const OPEN_ON_HOVER_MS = 600

// Drives the page tree column. Every page's own
// children <ul> is a `list` target (Admin::PagesScreen::TreeNodeComponent); they all
// share one `group`, so a node can be dropped under any other page in the
// tree, not just reordered among its current siblings -- a nested-list
// SortableJS setup.
//
// A drop PATCHes Admin::TreeController and asks for a Turbo Stream back
// (`Accept: text/vnd.turbo-stream.html`), which it renders itself via
// `Turbo.renderStreamMessage` -- `fetch` never goes through Turbo Drive, so
// nothing else applies that response for us. The controller always answers
// with a full re-render of the tree, success or failure alike (see its own
// comment for why), so this never has to guess at what the drop actually
// did -- it only ever displays what the server says happened. When the
// server says nothing (offline, signed out, an error page), nothing is
// rendered: the row is put back where it was and a toast says why (`save`).
//
// A MOVE IS A WRITE TO THE MOVED PAGE, made from outside its editor, so it
// takes its turn in the page's write queue (`enqueue`) like a block write (`admin--editor--blocks`,
// `saving/queue.js`): it is never on the wire together with an autosave of
// the same page. The toast's Undo is the same PATCH, sent by Turbo from
// `#toasts`: it is caught by its URL and held in the same queue (`holdUndo`).
//
// IT SAYS NOTHING TO THE OPEN SETTINGS FORM. `Pages::Move` saves the page, so
// its `updated_at` moves, but not the settings form's base: a move is not a
// change of the page's settings (`Page::SETTINGS_BASE_IGNORES`). So a move
// sends no base and writes none: the form's base stays valid in the mover's
// tab and in a colleague's alike.
//
// A MOVED PAGE'S NEW PARENT IS OPEN in the open set before the move is sent
// (`save`): the move's answer redraws the tree, and the redraw folds by the
// open set (`admin--tree--disclosure` on connect), so without it a page
// dropped into a folded or childless parent would vanish into the fold.
//
// No generation is handed to `enqueue`: the tree column sits outside
// `#content` and outlives a frame navigation, so "the page showing as the
// move is queued" is the page the move belongs to.
export default class extends Controller {
  static targets = ["list", "announcer", "row"]
  static values = { moveUrl: String }
  static classes = ["selected", "markerAtRest", "dropTarget"]

  connect() {
    this.holdUndo = (event) => {
      if (this.element.contains(event.target)) return
      if (String(event.detail.fetchOptions.method).toUpperCase() === "GET") return
      const url = event.detail.url
      if (url?.pathname !== new URL(this.moveUrlValue, window.location.origin).pathname) return

      holdTurboRequest(event)
    }
    document.addEventListener("turbo:before-fetch-request", this.holdUndo)
    this.settleHover = () => this.endHover()
    document.addEventListener("turbo:before-cache", this.settleHover)
    this.arrive()
    this.element.dataset.sortable = "pending"
    const token = this.loadToken = {}
    loadSortable().then((Sortable) => {
      // Disconnected (or connected again) before SortableJS arrived: nothing to make.
      if (this.loadToken !== token) return

      this.sortables = this.listTargets.map((list) =>
        Sortable.create(list, {
          group: "pages",
          animation: 150,
          // Only the ⠿ handle starts a drag -- the row's own title stays a
          // normal, clickable link.
          handle: ".admin-tree-node__handle",
          // The drag look: a dashed placeholder where the row would land, and
          // the lifted row itself with a shadow.
          ghostClass: "admin-drag-ghost",
          chosenClass: "admin-drag-chosen",
          // SortableJS's own pointer-driven drag instead of native HTML5
          // drag-and-drop: the handle is a `<button>` (so the keyboard reaches
          // it), and Firefox never starts a native drag from a button -- with
          // the default, the mouse path would be dead there. The fallback
          // drags a clone of the row (`fallbackClass`, styled like the lifted
          // row), appended to `<body>` so no scrolling or transformed ancestor
          // (the tree column is a drawer on a narrow screen) can clip or
          // offset it. `fallbackTolerance`: a press has to travel a few pixels
          // before it is a drag, so a slightly shaky click that only means to
          // focus the handle doesn't lift the row.
          forceFallback: true,
          fallbackOnBody: true,
          fallbackClass: "admin-drag-fallback",
          fallbackTolerance: 3,
          onStart: (event) => this.startHover(event.item),
          onMove: (event, pointer) => this.hoverOver(event.related, pointer),
          onEnd: (event) => {
            this.endHover()
            this.onDrop(event)
          }
        })
      )
      this.element.dataset.sortable = "ready"
    })
  }

  disconnect() {
    this.loadToken = null
    document.removeEventListener("turbo:before-fetch-request", this.holdUndo)
    document.removeEventListener("turbo:before-cache", this.settleHover)
    this.endHover()
    this.sortables?.forEach((sortable) => sortable.destroy())
    this.sortables = null
    delete this.element.dataset.sortable
  }

  // SortableJS's `onEnd`: where the dragged <li> landed (`event.to`, the
  // children <ul> of its new parent) and at what index among that list's
  // <li>s.
  //
  // Where it came from (`event.from`, `event.oldIndex`) is kept as the
  // sibling it stood before, for `save` to put it back if the move fails:
  // SortableJS has already moved the row, so its old neighbours are the
  // old list's children without it.
  onDrop(event) {
    const origin = event.from && {
      list: event.from,
      next: Array.from(event.from.children).filter((child) => child !== event.item)[event.oldIndex] || null
    }
    return this.save(event.item, event.to, event.newIndex, origin)
  }

  // The one place a move is sent -- the mouse path (`onDrop`) and the
  // keyboard path (`drop`) both end here, so a keyboard drop is exactly the
  // request a mouse drop makes.
  //
  // Queued with every other write on the screen (see the class comment). A
  // move queued behind a save that never answers waits for that save's own
  // 30 s timeout at most; its own request has the same limit, so it cannot
  // hold the queue either.
  //
  // What came back is judged by `sendOrder` (`saving/order_request.js`,
  // which also says why an expired session's sign-in page is not rendered):
  // - a Turbo Stream is the endpoint's answer, at any status, and is
  //   rendered: it redraws the whole tree as the server has it, which is
  //   also what undoes the optimistic DOM move of a refused drop;
  // - anything else -- the redirect to sign-in, an error page, no answer at
  //   all (offline, timed out) -- redraws nothing, so the row would stay
  //   where it was dropped, a place it was never saved to. It is put back
  //   at `origin` (`{ list, next }`: where it stood before the move) and an
  //   error toast says why.
  //
  // Before anything is sent, the list's parent is written open in the open
  // set (see the class comment): a hover-opened parent, a page the drop made
  // a parent and a sibling a keyboard move nested into alike. A move that is
  // refused leaves that open stored, which is harmless: the open set is
  // bounded, and an open of a page with no children means only "open once
  // it has some".
  async save(item, list, index, origin = null) {
    this.storeOpen(list.closest("[data-tree-node]"))
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const pageId = item.dataset.pageId
    const body = JSON.stringify({ page_id: pageId, parent_id: list.dataset.parentId, position: index })

    await enqueue(async (isCurrent) => {
      const headers = {
        "Content-Type": "application/json",
        Accept: "text/vnd.turbo-stream.html",
        "X-CSRF-Token": csrfToken,
        [TAB_HEADER]: TAB
      }

      const answer = await sendOrder(this.moveUrlValue, { headers, body })
      // The page was replaced while the move was on its way (a visit that
      // gave up waiting, Back): the answer's tree and toast belong to a
      // document that is gone.
      if (!isCurrent()) return

      if (answer.outcome !== "answered") {
        this.putBack(item, origin)
        orderErrorToast(answer.outcome, "toast-move-error")
        return
      }

      // The tree's own re-render (success or 422 alike) is always a Turbo
      // Stream body -- rendering it is what actually undoes SortableJS's own
      // optimistic DOM move on a failed drop, by replacing the whole frame
      // with the server's (unchanged) version of it. It also appends the
      // "Moved ... Undo" toast on a success.
      Turbo.renderStreamMessage(answer.text)
    }).catch(() => {})
  }

  // ---- A folded parent under a dragged row ---------------------------------
  //
  // THE POINTER RESTS ON A FOLDED PARENT'S ROW for `OPEN_ON_HOVER_MS`, and
  // the parent opens: drawn, stored open as a person's open (`unfold`), and
  // marked the drop target while the pointer is inside it, so its children
  // take the drop.
  //
  // SortableJS moves the slot past a row as soon as the pointer enters it,
  // which would move a folded row out from under the pointer before it
  // could rest there. So `onMove` (`hoverOver`) refuses the move (`false`)
  // while the pointer is in the middle half of a folded row, where the
  // timer starts, and in the quarter on the slot's side, which the pointer
  // crosses to reach the middle; only the far quarter lets the slot pass
  // it. A slot resting beside a folded parent therefore never opens it.
  //
  // The node is the one `related` stands in (a row's `<li>`, or the empty
  // list of a leaf, whose node is the leaf), and any other node cancels the
  // timer. The pointer is followed for the whole drag (`followPointer`),
  // since SortableJS calls `onMove` only where it would move the slot:
  // leaving the parent's row cancels the timer, leaving an opened parent
  // takes its mark away, and coming back over a parent this drag opened
  // marks it again. Boxes are judged by their height inside the tree's
  // width, never by what is hit under the pointer: the handle a drag holds
  // stands in the gutter, outside its row's box.
  //
  // The timer and the mark go on drag end (the drop), Escape,
  // `turbo:before-cache` and disconnect (`endHover`), so neither outlives a
  // drag nor is kept in Turbo's snapshot. Escape ends opening on hover for
  // the rest of that drag (the drag itself goes on: SortableJS has no
  // Escape). What an open writes (the fold's drawing and the open set) is
  // the open set's own, which stays.
  startHover(item) {
    this.endHover()
    this.dragged = item
    this.openedThisDrag = []
    this.pointerFollower = (event) => this.followPointer(event)
    this.escapeFollower = (event) => { if (event.key === "Escape") this.endHover() }
    document.addEventListener("pointermove", this.pointerFollower)
    document.addEventListener("keydown", this.escapeFollower)
  }

  // SortableJS's `onMove`: `false` keeps the slot where it is.
  hoverOver(related, pointer) {
    if (!this.pointerFollower) return undefined
    const node = related?.closest?.("[data-tree-node]") ?? null
    if (node !== this.hovered) this.cancelHover()
    if (!node || !isFolded(node) || !this.dropListOf(node)) return undefined

    const box = node.querySelector(":scope > [data-tree-row]")?.getBoundingClientRect()
    if (!box?.height || pointer?.clientY == null) return undefined
    const at = (pointer.clientY - box.top) / box.height
    if (at < 0 || at > 1) return undefined

    const slotAbove = !!(this.dragged && (this.dragged.compareDocumentPosition(node) & Node.DOCUMENT_POSITION_FOLLOWING))
    const middle = at >= 0.25 && at <= 0.75
    const slotSide = slotAbove ? at < 0.25 : at > 0.75
    if (!middle && !slotSide) {
      // The slot passes the row, which moves from under the pointer.
      this.cancelHover()
      return undefined
    }
    if (middle && !this.hovered) {
      this.hovered = node
      this.hoverTimer = setTimeout(() => this.openUnder(node), OPEN_ON_HOVER_MS)
    }
    return false
  }

  followPointer(event) {
    const tree = this.element.querySelector(".admin-tree")?.getBoundingClientRect()
    const inTree = !!tree && event.clientX >= tree.left && event.clientX <= tree.right
    const at = (element) => {
      const box = element?.getBoundingClientRect()
      return inTree && !!box && event.clientY >= box.top && event.clientY <= box.bottom
    }
    if (this.hovered && !at(this.hovered.querySelector(":scope > [data-tree-row]"))) this.cancelHover()
    if (this.dropTarget && !at(this.dropTarget)) this.unmarkDropTarget()
    if (!this.dropTarget) {
      // The innermost parent this drag opened that the pointer is back in.
      const back = this.openedThisDrag.filter((node) => node.isConnected && !isFolded(node) && at(node))
        .sort((a, b) => a.getBoundingClientRect().height - b.getBoundingClientRect().height)[0]
      if (back) this.markDropTarget(back)
    }
  }

  openUnder(node) {
    this.hoverTimer = null
    this.hovered = null
    if (!node.isConnected || !isFolded(node)) return

    this.unfold(node)
    this.openedThisDrag?.push(node)
    this.markDropTarget(node)
  }

  markDropTarget(node) {
    this.unmarkDropTarget()
    this.dropTarget = node
    this.dropTargetClasses.forEach((name) => node.classList.add(name))
  }

  cancelHover() {
    clearTimeout(this.hoverTimer)
    this.hoverTimer = null
    this.hovered = null
  }

  unmarkDropTarget() {
    this.dropTarget?.classList.remove(...this.dropTargetClasses)
    this.dropTarget = null
  }

  endHover() {
    this.cancelHover()
    this.unmarkDropTarget()
    this.dragged = null
    this.openedThisDrag = []
    if (!this.pointerFollower) return
    document.removeEventListener("pointermove", this.pointerFollower)
    document.removeEventListener("keydown", this.escapeFollower)
    this.pointerFollower = null
    this.escapeFollower = null
  }

  // Opens a folded `node` as a person's open: drawn, stored, and told to the
  // tree's other scripts.
  unfold(node) {
    setFolded(node, false)
    this.storeOpen(node)
    node.closest(".admin-tree")?.dispatchEvent(new CustomEvent("tree:changed", { bubbles: true }))
  }

  // The node's own children list, when it takes a drop.
  dropListOf(node) {
    return node.querySelector(":scope > ul[data-admin--pages--tree-target='list']")
  }

  // Writes `node`'s branch open in the open set, against its default: the
  // root and the open page's ancestors are open by default
  // (`tree/open_set.js`).
  storeOpen(node) {
    const tree = node?.closest(".admin-tree")
    const id = node && idOf(node)
    if (!tree || !id) return

    const openByDefault = node.hasAttribute("data-tree-root") || node.hasAttribute("data-tree-on-path")
    setOpen(tree, id, true, { openByDefault })
  }

  // Puts a row whose move was not saved back where it stood. Not when the
  // tree has been redrawn since the drop (an earlier move's answer replaces
  // the whole frame, this row's element with it): what is on screen then is
  // the server's own tree, which never had the move in it.
  putBack(item, origin) {
    if (!origin || !item.isConnected || !origin.list.isConnected) return
    if (origin.next && origin.next.parentElement !== origin.list) return

    origin.list.insertBefore(item, origin.next)
  }

  // ---- Keyboard path ------------------------------------------------------
  //
  // Space on a row's handle picks the row up; ArrowUp/ArrowDown move it among
  // its siblings, ArrowRight nests it under the sibling above, ArrowLeft moves
  // it out one level; Space drops it (`save`, the mouse path's own request)
  // and Escape puts it back without saving. Only drops the mouse path could
  // also make are offered: the destination must be one of this controller's
  // own `list` targets (`data-admin--pages--tree-target="list"`): the homepage's own
  // level has none (the homepage is the one root; a page can't leave it), and
  // neither does a context-only page's list, so ArrowLeft out to a level
  // whose parent is context-only does nothing. (ArrowRight never meets a
  // context-only sibling: a row only has a handle when its parent is a page
  // the editor can read -- `Admin::PagesScreen::TreeRowComponent#movable?` -- and every
  // page under a readable one is readable.) A page can only nest under a
  // *sibling*, never into its own subtree.
  //
  // A picked row whose handle loses focus is put back (`blur`): the DOM move
  // has saved nothing, so leaving it displaced and styled would show an order
  // that isn't real.
  key(event) {
    const row = event.currentTarget.closest("li[data-page-id]")
    if (!row) return

    if (event.key === " ") {
      event.preventDefault()
      this.picked === row ? this.drop(row) : this.pickUp(row)
      return
    }
    if (this.picked !== row) return

    if (event.key === "Escape") {
      event.preventDefault()
      this.cancel(row)
    } else if (event.key === "ArrowUp" || event.key === "ArrowDown") {
      event.preventDefault()
      this.step(row, event.key === "ArrowUp" ? -1 : 1)
    } else if (event.key === "ArrowRight") {
      event.preventDefault()
      this.nest(row)
    } else if (event.key === "ArrowLeft") {
      event.preventDefault()
      this.outdent(row)
    }
  }

  pickUp(row) {
    if (this.picked && this.picked !== row) this.cancel(this.picked, { refocus: false })
    this.picked = row
    this.origin = { list: row.parentElement, next: row.nextElementSibling }
    row.dataset.picked = "true"
    row.classList.add("admin-drag-chosen")
    this.announce(messages(this.element).t("components.pages_screen.tree.moves.picked_up", { title: this.titleOf(row), position: this.positionOf(row) }))
  }

  step(row, direction) {
    const sibling = direction < 0 ? row.previousElementSibling : row.nextElementSibling
    if (!sibling) return
    row.parentElement.insertBefore(row, direction < 0 ? sibling : sibling.nextElementSibling)
    this.moved(row)
  }

  nest(row) {
    // Under the sibling above: the last child of its own list, if that list
    // is a real drop target. A folded sibling is opened first, and stored
    // open, as a drag resting on it opens it: a row moved into a hidden list
    // would lose the focus, and with it the pick-up.
    const above = row.previousElementSibling
    const list = above && this.dropListOf(above)
    if (!list) return
    const opened = isFolded(above)
    if (opened) this.unfold(above)
    list.append(row)
    if (!opened) return this.moved(row)

    this.focusHandle(row)
    this.announce(messages(this.element).t("components.pages_screen.tree.moves.opened", { title: this.titleOf(above), position: this.positionOf(row) }))
  }

  outdent(row) {
    // Out one level: right after its current parent, in the parent's own list.
    const parentRow = row.parentElement.closest("li[data-page-id]")
    const list = parentRow?.parentElement
    if (!list?.matches("ul[data-admin--pages--tree-target='list']")) return
    list.insertBefore(row, parentRow.nextElementSibling)
    this.moved(row)
  }

  // A DOM move blurs the focused handle; put focus back on it so the next
  // key press still reaches this row.
  moved(row) {
    this.focusHandle(row)
    this.announce(this.positionOf(row))
  }

  async drop(row) {
    // Where it was picked up: `save` puts it back there if the move fails.
    const origin = this.origin
    this.clearPicked(row)
    const list = row.parentElement
    const index = Array.from(list.children).indexOf(row)
    const id = row.dataset.pageId
    this.announce(messages(this.element).t("components.pages_screen.tree.moves.dropped", { title: this.titleOf(row), position: this.positionOf(row) }))
    await this.save(row, list, index, origin)
    // The answer replaces the whole tree (this controller's own element with
    // it), so the row the editor was on is a new element: give focus back to
    // its handle so the keyboard user isn't dropped at the top of the page.
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)))
    document.querySelector(`li[data-page-id='${id}'] > [data-tree-row] .admin-tree-node__handle`)?.focus()
  }

  // ---- The selected row -------------------------------------------------
  //
  // THE SELECTED ROW IS THE PAGE THAT IS OPEN. The tree column sits outside
  // `#content` and outlives a frame navigation, and a frame answer carries
  // no tree (`admin/pages/_tree`), so the server's drawing of the
  // selection holds only for the page it was drawn with. The open page is
  // the one `#content` names (`[data-tree-open-page]`, drawn by the page
  // editor; nothing on another screen, which selects no row), and this
  // marks exactly that row, whoever drew it: as each row connects (a full
  // visit, a restored snapshot, a move's redrawn tree, a save's redrawn row)
  // and after every load of the content frame (`follow`). Turbo's snapshot
  // keeps what this marked, which is right for the URL it is kept under,
  // and a restored one is marked again as its rows connect.
  //
  // The marks are the shared row's own classes, handed over as Stimulus
  // classes (`TreeItemComponent::CLASSES[:row_selected]` and `[:reveal]`):
  // the row's selection (its ground, its bar and its title's weight), the
  // title's `aria-current="page"`, and the translation markers shown rather
  // than at rest. Only rows that can be selected are `row` targets (a
  // context-only row never is).
  //
  // A row redrawn alone (a save's answer) stands under a node whose fold the
  // person may have changed since the server drew the row: its disclosure is
  // drawn again from the node. Every row that connects is told to the tree's
  // other scripts (`tree:changed` on the tree).
  rowTargetConnected(row) {
    this.mark(row, row.dataset.pageId === this.openPageId())
    const node = row.closest("[data-tree-node]")
    if (node) setFolded(node, isFolded(node))
    row.closest(".admin-tree")?.dispatchEvent(new CustomEvent("tree:changed", { bubbles: true }))
  }

  follow(event) {
    if (event.target.id !== "content") return

    const open = this.openPageId()
    this.rowTargets.forEach((row) => this.mark(row, row.dataset.pageId === open))
    this.arrive()
  }

  // ARRIVING AT A PAGE (a full load, a restored snapshot, a redrawn tree, a
  // page opened from the tree) opens the path to it, forgetting the folds on
  // that path (`openPathIn`), so the selected row is never inside a folded
  // branch, and scrolls the selected row into view inside the column.
  arrive() {
    const tree = this.element.querySelector(".admin-tree")
    if (!tree) return

    const open = this.openPageId()
    openPathIn(tree, open)
    this.scrollToRow(open)
  }

  // Inside the tree's column only (`#tree-column`'s `scrollTop`, at once,
  // never smoothly), and only when the row is out of its view, which it then
  // stands inside with one row's height to spare; never the window, so the
  // editor beside it stays where it is. A column that is not a scroller does
  // not move.
  scrollToRow(id) {
    const column = document.getElementById("tree-column")
    const row = id == null ? null : this.element.querySelector(`#tree-row-${CSS.escape(id)}`)
    if (!column || !row) return

    const box = column.getBoundingClientRect()
    const rowBox = row.getBoundingClientRect()
    if (rowBox.top >= box.top && rowBox.bottom <= box.bottom) return

    const spare = rowBox.height
    if (rowBox.top < box.top) column.scrollTop -= box.top - rowBox.top + spare
    else column.scrollTop += rowBox.bottom - box.bottom + spare
  }

  openPageId() {
    return document.querySelector("#content [data-tree-open-page]")?.dataset.treeOpenPage ?? null
  }

  mark(row, selected) {
    this.selectedClasses.forEach((name) => row.classList.toggle(name, selected))
    const title = row.querySelector(`#tree-link-${row.dataset.pageId}`)
    if (selected) title?.setAttribute("aria-current", "page")
    else title?.removeAttribute("aria-current")
    row.querySelectorAll("[data-translation-marker]").forEach((marker) => {
      this.markerAtRestClasses.forEach((name) => marker.classList.toggle(name, !selected))
    })
  }

  // Focus leaving the handle. A DOM move (`moved`) blurs it too and refocuses
  // straight away, so judge after the current task: only a handle that is
  // still unfocused means the editor really left.
  blur(event) {
    // `currentTarget` is only set during dispatch: keep the handle itself.
    const handle = event.currentTarget
    const row = handle.closest("li[data-page-id]")
    setTimeout(() => {
      if (this.picked === row && document.activeElement !== handle) this.cancel(row, { refocus: false })
    }, 0)
  }

  cancel(row, { refocus = true } = {}) {
    this.origin.list.insertBefore(row, this.origin.next)
    this.clearPicked(row)
    if (refocus) this.focusHandle(row)
    this.announce(messages(this.element).t("components.pages_screen.tree.moves.cancelled", { title: this.titleOf(row) }))
  }

  clearPicked(row) {
    delete row.dataset.picked
    row.classList.remove("admin-drag-chosen")
    this.picked = null
    this.origin = null
  }

  // A row's parts are found from its `<li>` through the shared row's own
  // hook (`[data-tree-row]`), never by the markup's shape.
  focusHandle(row) {
    row.querySelector(":scope > [data-tree-row] .admin-tree-node__handle")?.focus()
  }

  // The whole title the server drew the row with (`data-tree-title`).
  titleOf(row) {
    return row.querySelector(":scope > [data-tree-row]")?.dataset.treeTitle?.trim() ||
      messages(this.element).t("components.pages_screen.tree_row.untitled")
  }

  positionOf(row) {
    const siblings = row.parentElement.children
    return messages(this.element).t("components.pages_screen.tree.moves.position", { position: Array.from(siblings).indexOf(row) + 1, count: siblings.length })
  }

  announce(message) {
    if (this.hasAnnouncerTarget) this.announcerTarget.textContent = message
  }
}
