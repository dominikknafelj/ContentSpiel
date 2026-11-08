import { Controller } from "@hotwired/stimulus"
import { expanderOf, idOf, isFolded, openByRule, readOpenSet, setFolded, setOpen } from "tree/open_set"

// Folds and unfolds a page tree's branches: on the tree itself (the
// `.admin-tree` element a find names; in Pages `ul#tree-list`), answering
// the press of each row's disclosure (`TreeItemComponent`'s button,
// `toggle`). A press flips the branch, Alt and a press opens it with every
// branch below it, and each fold or open the person makes is written to the
// open set (`tree/open_set.js`, its one writer), relative to the node's
// default: the root and the selected page's ancestors are open by default.
// Every toggle is told to the tree's other scripts as `tree:changed` on the
// tree.
//
// THE SERVER DRAWS THE FOLDS from the cookie, from the first paint
// (`TreeOpenSet`), and connect draws them again from the cookie as it stands:
// a page Turbo restores from its snapshot is drawn as the open set is now,
// not as it was when the snapshot was taken. Only what differs is written,
// so on a fresh page connect changes nothing. What this writes into the page
// (`data-folded`, a list's `hidden`, the button's `aria-expanded` and name)
// is the open set's own drawing, the one the server draws, so the snapshot
// keeps it.
export default class extends Controller {
  connect() {
    const set = readOpenSet()
    this.element.querySelectorAll("[data-tree-node]").forEach((node) => setFolded(node, !openByRule(node, set)))
  }

  toggle(event) {
    const node = event.currentTarget.closest("[data-tree-node]")
    if (!node || !this.element.contains(node)) return

    event.preventDefault()
    if (event.altKey) {
      this.openBranch(node)
    } else {
      const open = isFolded(node)
      setFolded(node, !open)
      this.store(node, open)
    }
    this.element.dispatchEvent(new CustomEvent("tree:changed", { bubbles: true }))
  }

  // The node and every branch below it, opened and stored.
  openBranch(node) {
    [ node, ...node.querySelectorAll("[data-tree-node]") ].filter((each) => expanderOf(each)).forEach((each) => {
      setFolded(each, false)
      this.store(each, true)
    })
  }

  store(node, open) {
    const id = idOf(node)
    if (!id) return

    const openByDefault = node.hasAttribute("data-tree-root") || node.hasAttribute("data-tree-on-path")
    setOpen(this.element, id, open, { openByDefault })
  }
}
