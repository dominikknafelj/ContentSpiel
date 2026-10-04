import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import Sortable from "sortablejs"
import { enqueue, holdTurboRequest, syncBases } from "autosave/queue"

// Drives the page tree column (cs-studio spec §4.2). Every page's own
// children <ul> is a `list` target (Admin::TreeNodeComponent); they all
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
// did -- it only ever displays what the server says happened.
//
// A MOVE IS A WRITE TO THE MOVED PAGE, made from outside its editor (final
// fix wave 1, reviews A I1 / B I1). `Pages::Move` saves the page, so its
// `updated_at` moves -- and when that page is the one open in the editor next
// to the tree, its settings form holds the old value as its autosave base,
// and a stale base is refused (409, final). The move used to go straight out
// and tell that form nothing: the editor's next keystroke was "Changed
// elsewhere" against their own move, the form dead until Reload. So a move is
// treated exactly like a block write (`admin--blocks`, `autosave/queue.js`):
// - it takes its turn in the page's write queue (`enqueue`), so it is never
//   on the wire together with an autosave of the same page, and reads the
//   base when it is SENT, after the previous answer's was written back;
// - it carries the open form's base as `X-Page-Base-Updated-At` -- only when
//   the moved page IS the open one (`pageBaseFor`); the tree lists every
//   page, and another page's move says nothing about this form;
// - its answer's `page-base-updated-at` is written into the hidden field
//   synchronously (`syncBases`), before the next request goes. The server
//   sends it only when the base was still current
//   (`Admin::TreeController#page_base_streams`).
// The toast's Undo is the same PATCH, sent by Turbo from `#toasts`: it is
// caught by its URL and held in the same queue with the same header
// (`holdUndo`, as `admin--blocks#addPageBaseToUndo` does for a reorder).
//
// No generation is handed to `enqueue`: the tree column sits outside
// `#content` and outlives a frame navigation, so "the page showing as the
// move is queued" is the page the move belongs to.
export default class extends Controller {
  static targets = ["list", "announcer"]
  static values = { moveUrl: String }

  // The page settings form's base field (`Admin::PageSettingsFormComponent`).
  static pageBaseId = "page-base-updated-at"

  connect() {
    this.holdUndo = (event) => {
      if (this.element.contains(event.target)) return
      if (String(event.detail.fetchOptions.method).toUpperCase() === "GET") return
      const url = event.detail.url
      if (url?.pathname !== new URL(this.moveUrlValue, window.location.origin).pathname) return

      holdTurboRequest(event, {
        baseIds: [ this.constructor.pageBaseId ],
        before: (request) => {
          const pageBase = this.pageBaseFor(url.searchParams.get("page_id"))
          if (pageBase) request.fetchOptions.headers["X-Page-Base-Updated-At"] = pageBase
        }
      })
    }
    document.addEventListener("turbo:before-fetch-request", this.holdUndo)
    this.sortables = this.listTargets.map((list) =>
      Sortable.create(list, {
        group: "pages",
        animation: 150,
        // Only the ⠿ handle starts a drag -- the row's own title stays a
        // normal, clickable link.
        handle: ".admin-tree-node__handle",
        // The drag look (handoff §9 A9): a dashed placeholder where the row
        // would land, and the lifted row itself with a shadow.
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
        onEnd: (event) => this.onDrop(event)
      })
    )
  }

  disconnect() {
    document.removeEventListener("turbo:before-fetch-request", this.holdUndo)
    this.sortables?.forEach((sortable) => sortable.destroy())
    this.sortables = []
  }

  // The open page settings form's base, when the page it edits is `pageId`
  // (the editor header names its record); nothing otherwise -- another page
  // is open, a post, a view-only page (no form), or no editor at all.
  pageBaseFor(pageId) {
    const open = document.querySelector("header.admin-editor-header[data-record-type='page']")?.dataset.recordId
    if (!open || String(open) !== String(pageId)) return null
    return document.getElementById(this.constructor.pageBaseId)?.value || null
  }

  // SortableJS's `onEnd`: where the dragged <li> landed (`event.to`, the
  // children <ul> of its new parent) and at what index among that list's
  // <li>s.
  onDrop(event) {
    return this.save(event.item, event.to, event.newIndex)
  }

  // The one place a move is sent -- the mouse path (`onDrop`) and the
  // keyboard path (`drop`) both end here, so a keyboard drop is exactly the
  // request a mouse drop makes.
  //
  // Queued with every other write on the screen (see the class comment). A
  // move queued behind a save that never answers waits for that save's own
  // 30 s timeout at most; its own request has the same limit, so it cannot
  // hold the queue either. A request that fails outright (offline, timed
  // out) leaves the optimistic DOM move in place with nothing saved, as it
  // always did: there is no answer to draw.
  async save(item, list, index) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const pageId = item.dataset.pageId
    const body = JSON.stringify({ page_id: pageId, parent_id: list.dataset.parentId, position: index })

    await enqueue(async (isCurrent) => {
      const headers = {
        "Content-Type": "application/json",
        Accept: "text/vnd.turbo-stream.html",
        "X-CSRF-Token": csrfToken
      }
      const pageBase = isCurrent() && this.pageBaseFor(pageId)
      if (pageBase) headers["X-Page-Base-Updated-At"] = pageBase

      const response = await fetch(this.moveUrlValue, { method: "PATCH", headers, body, signal: AbortSignal.timeout(30000) })
      const text = await response.text()
      // The page was replaced while the move was on its way (a visit that
      // gave up waiting, Back): the answer's tree, toast and base belong to
      // a document that is gone.
      if (!isCurrent()) return

      if (pageBase) syncBases(text, [ this.constructor.pageBaseId ])
      // The tree's own re-render (success or 422 alike) is always a Turbo
      // Stream body -- rendering it is what actually undoes SortableJS's own
      // optimistic DOM move on a failed drop, by replacing the whole frame
      // with the server's (unchanged) version of it. It also appends the
      // "Moved ... Undo" toast on a success.
      Turbo.renderStreamMessage(text)
    }).catch(() => {})
  }

  // ---- Keyboard path (handoff §9 A9) -------------------------------------
  //
  // Space on a row's handle picks the row up; ArrowUp/ArrowDown move it among
  // its siblings, ArrowRight nests it under the sibling above, ArrowLeft moves
  // it out one level; Space drops it (`save`, the mouse path's own request)
  // and Escape puts it back without saving. Only drops the mouse path could
  // also make are offered: the destination must be one of this controller's
  // own `list` targets (`data-admin--tree-target="list"`): the homepage's own
  // level has none (the homepage is the one root; a page can't leave it), and
  // neither does a context-only page's list, so ArrowLeft out to a level
  // whose parent is context-only does nothing. (ArrowRight never meets a
  // context-only sibling: a row only has a handle when its parent is a page
  // the editor can read -- `Admin::TreeNodeComponent#movable?` -- and every
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
    this.announce(`Picked up ${this.titleOf(row)}. ${this.positionOf(row)}`)
  }

  step(row, direction) {
    const sibling = direction < 0 ? row.previousElementSibling : row.nextElementSibling
    if (!sibling) return
    row.parentElement.insertBefore(row, direction < 0 ? sibling : sibling.nextElementSibling)
    this.moved(row)
  }

  nest(row) {
    // Under the sibling above: the last child of its own list, if that list
    // is a real drop target.
    const above = row.previousElementSibling
    const list = above?.querySelector(":scope > ul[data-admin--tree-target='list']")
    if (!list) return
    list.append(row)
    this.moved(row)
  }

  outdent(row) {
    // Out one level: right after its current parent, in the parent's own list.
    const parentRow = row.parentElement.closest("li[data-page-id]")
    const list = parentRow?.parentElement
    if (!list?.matches("ul[data-admin--tree-target='list']")) return
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
    this.clearPicked(row)
    const list = row.parentElement
    const index = Array.from(list.children).indexOf(row)
    const id = row.dataset.pageId
    this.announce(`Dropped ${this.titleOf(row)}. ${this.positionOf(row)}`)
    await this.save(row, list, index)
    // The answer replaces the whole tree (this controller's own element with
    // it), so the row the editor was on is a new element: give focus back to
    // its handle so the keyboard user isn't dropped at the top of the page.
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)))
    document.querySelector(`li[data-page-id='${id}'] .admin-tree-node__handle`)?.focus()
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
    this.announce(`Cancelled. ${this.titleOf(row)} is back where it was.`)
  }

  clearPicked(row) {
    delete row.dataset.picked
    row.classList.remove("admin-drag-chosen")
    this.picked = null
    this.origin = null
  }

  focusHandle(row) {
    row.querySelector(":scope > div .admin-tree-node__handle")?.focus()
  }

  titleOf(row) {
    return row.querySelector(":scope > div a")?.textContent.trim() || "page"
  }

  positionOf(row) {
    const siblings = row.parentElement.children
    return `Position ${Array.from(siblings).indexOf(row) + 1} of ${siblings.length}.`
  }

  announce(message) {
    if (this.hasAnnouncerTarget) this.announcerTarget.textContent = message
  }
}
