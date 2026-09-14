import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Drives the custom "Pages tree" Avo tool (app/views/avo/tools/pages_tree.html.erb).
// Every page's own children <ul> is a `list` target; they all share one
// `group`, so a node can be dropped under any page in the tree, not just
// reordered among its current siblings.
//
// A drop is reloaded unconditionally, success or failure. A single move can
// renumber siblings the dragged node never touched (Page#place_among_siblings
// on the server), so the only tree state that's actually correct afterward is
// whatever the server now has -- not whatever SortableJS left the DOM in.
export default class extends Controller {
  static targets = ["list"]
  static values = { reorderUrl: String }

  connect() {
    this.sortables = this.listTargets.map((list) =>
      Sortable.create(list, {
        group: "pages-tree",
        animation: 150,
        // Only the ⠿ handle starts a drag -- the row's own link stays a
        // normal, clickable link to the page's edit form.
        handle: ".pages-tree-node__handle",
        onEnd: (event) => this.onDrop(event)
      })
    )
  }

  disconnect() {
    this.sortables?.forEach((sortable) => sortable.destroy())
    this.sortables = []
  }

  async onDrop(event) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    const response = await fetch(this.reorderUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken
      },
      body: JSON.stringify({
        page_id: event.item.dataset.pageId,
        parent_id: event.to.dataset.parentId,
        position: event.newIndex
      })
    })

    if (!response.ok) {
      const body = await response.json().catch(() => ({}))
      // eslint-disable-next-line no-console
      console.error("Could not move page:", body.errors)
    }

    window.location.reload()
  }
}
