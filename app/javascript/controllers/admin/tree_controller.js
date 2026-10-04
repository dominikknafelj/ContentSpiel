import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import Sortable from "sortablejs"

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
export default class extends Controller {
  static targets = ["list", "announcer"]
  static values = { moveUrl: String }

  connect() {
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
        onEnd: (event) => this.onDrop(event)
      })
    )
  }

  disconnect() {
    this.sortables?.forEach((sortable) => sortable.destroy())
    this.sortables = []
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
  async save(item, list, index) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    const response = await fetch(this.moveUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Accept: "text/vnd.turbo-stream.html",
        "X-CSRF-Token": csrfToken
      },
      body: JSON.stringify({
        page_id: item.dataset.pageId,
        parent_id: list.dataset.parentId,
        position: index
      })
    })

    // The tree's own re-render (success or 422 alike) is always a Turbo
    // Stream body -- rendering it is what actually undoes SortableJS's own
    // optimistic DOM move on a failed drop, by replacing the whole frame
    // with the server's (unchanged) version of it. It also appends the
    // "Moved ... Undo" toast on a success.
    Turbo.renderStreamMessage(await response.text())
  }

  // ---- Keyboard path (handoff §9 A9) -------------------------------------
  //
  // Space on a row's handle picks the row up; ArrowUp/ArrowDown move it among
  // its siblings, ArrowRight nests it under the sibling above, ArrowLeft moves
  // it out one level; Space drops it (`save`, the mouse path's own request)
  // and Escape puts it back without saving. Only drops the mouse path could
  // also make are offered: the destination must be one of this controller's
  // own `list` targets (never the homepage's own level -- the homepage is the
  // one root and `Pages::Move` refuses to move a page out of it -- nor a
  // context-only page's list, which is no drop target), and a page never goes
  // under itself (it can only nest under a *sibling*, never into its own
  // subtree).
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

  cancel(row) {
    this.origin.list.insertBefore(row, this.origin.next)
    this.clearPicked(row)
    this.focusHandle(row)
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
