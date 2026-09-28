import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import Sortable from "sortablejs"

// Drives the page tree column (cs-studio spec §4.2). Every page's own
// children <ul> is a `list` target (Admin::TreeNodeComponent); they all
// share one `group`, so a node can be dropped under any other page in the
// tree, not just reordered among its current siblings -- the same nested-
// list SortableJS pattern as the Avo "Pages tree" tool
// (app/javascript/controllers/pages_tree_controller.js) this follows.
//
// It differs from that tool in how a drop is applied: rather than a bare
// JSON PATCH plus a full page reload, this PATCHes Admin::TreeController
// and asks for a Turbo Stream back (`Accept: text/vnd.turbo-stream.html`),
// which it renders itself via `Turbo.renderStreamMessage` -- `fetch` never
// goes through Turbo Drive, so nothing else applies that response for us.
// The controller always answers with a full re-render of the tree, success
// or failure alike (see its own comment for why), so this never has to
// guess at what the drop actually did -- it only ever displays what the
// server says happened.
export default class extends Controller {
  static targets = ["list"]
  static values = { moveUrl: String }

  connect() {
    this.sortables = this.listTargets.map((list) =>
      Sortable.create(list, {
        group: "pages",
        animation: 150,
        // Only the ⠿ handle starts a drag -- the row's own title stays a
        // normal, clickable link.
        handle: ".admin-tree-node__handle",
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

    const response = await fetch(this.moveUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Accept: "text/vnd.turbo-stream.html",
        "X-CSRF-Token": csrfToken
      },
      body: JSON.stringify({
        page_id: event.item.dataset.pageId,
        parent_id: event.to.dataset.parentId,
        position: event.newIndex
      })
    })

    // The tree's own re-render (success or 422 alike) is always a Turbo
    // Stream body -- rendering it is what actually undoes SortableJS's own
    // optimistic DOM move on a failed drop, by replacing the whole frame
    // with the server's (unchanged) version of it.
    Turbo.renderStreamMessage(await response.text())
  }
}
