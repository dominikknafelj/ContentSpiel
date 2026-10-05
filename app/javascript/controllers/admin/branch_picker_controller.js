import { Controller } from "@hotwired/stimulus"

// The page-branch tree of a `pages.*` row's scope editor
// (`Admin::GroupsScreen::ScopeEditorComponent`, round 3 Task 10): a checkbox
// per page whose ticked boxes are submitted as the grant's `page_ids` --
// branch ROOTS. Tri-state:
//
//   chosen   ticked, submitted (a stored root);
//   implied  below a chosen page, so covered by it (a `page_ids` scope matches a
//            root and everything below it): a greyed tick, DISABLED, so never
//            submitted;
//   partial  an ancestor of a chosen page, itself neither: `indeterminate`
//            ("-"), UNCHECKED, so never submitted.
//
// The server renders exactly these states (the form is correct with scripts
// off); this keeps them true as boxes are ticked. The truth is on the `<li>`
// nodes (`data-chosen`), not on the boxes, because not every node has one: a
// context-only ancestor (a page the viewer can't open, shown only as the path
// to one they can) is greyed text with a mark, and a chosen one still implies
// everything below it. `chosen` is remembered apart from what a box shows --
// an implied box is shown ticked and disabled, but gets its own choice back
// when the ancestor is unticked.
//
// Stored roots the viewer has no place for in the tree at all are hidden
// inputs (`kept`), never touched. A change on a box bubbles to the row's
// editor, whose `admin--permission-matrix` rewrites the chips from the state
// this has just settled (the box's own action runs first); the form's footer
// reads the same event.
export default class extends Controller {
  static targets = ["node", "kept"]

  connect() {
    this.refresh()
  }

  // A box was ticked or unticked.
  change(event) {
    const node = event.target.closest("li")
    if (node) node.dataset.chosen = event.target.checked ? "1" : ""
    this.refresh()
  }

  refresh() {
    this.nodeTargets.forEach((node) => {
      const chosen = node.dataset.chosen === "1"
      const implied = this.ancestorNodes(node).some((ancestor) => ancestor.dataset.chosen === "1")
      const below = this.descendantNodes(node)
      const partial = !chosen && !implied && below.some((descendant) => descendant.dataset.chosen === "1")

      // Every lookup stays inside the node's OWN row, its first `<div>`: the
      // second is the children wrapper, and a bare `:scope > div ...` reaches
      // through it into a descendant's row whenever this node has no such
      // element itself (a context-only node has no box; a node that isn't a
      // chosen root has no carried input) -- and would then set a descendant's
      // control from this node's state.
      const box = node.querySelector(":scope > div:first-child > label > input[type=checkbox]")
      if (box) {
        box.disabled = implied
        box.checked = chosen || implied
        box.indeterminate = partial
      }

      // A chosen root that is also implied is carried as a hidden input (the
      // server renders it only for a chosen one): submitted exactly while it is
      // chosen AND implied, so the disabled box and it are never both submitted
      // and an untouched save keeps a redundant stored root.
      const carried = node.querySelector(":scope > div:first-child > input[type=hidden]")
      if (carried) carried.disabled = !(chosen && implied)

      const mark = node.querySelector(":scope > div:first-child > span > [data-admin--branch-picker-target='mark']")
      if (mark) mark.textContent = implied || chosen ? "✓" : partial ? "–" : ""

      const note = node.querySelector(":scope > div:first-child > [data-admin--branch-picker-target='note']")
      if (note) note.textContent = implied ? "included" : partial ? "contains a chosen page" : chosen ? this.includes(below.length) : ""
    })
  }

  includes(count) {
    return count === 0 ? "" : `includes ${count} ${count === 1 ? "subpage" : "subpages"}`
  }

  // The `node`s enclosing this one, nearest first.
  ancestorNodes(node) {
    const nodes = []
    let parent = node.parentElement?.closest("li")
    while (parent && this.element.contains(parent)) {
      nodes.push(parent)
      parent = parent.parentElement?.closest("li")
    }
    return nodes
  }

  descendantNodes(node) {
    return Array.from(node.querySelectorAll("li"))
  }
}
