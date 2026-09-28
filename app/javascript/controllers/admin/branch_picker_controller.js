import { Controller } from "@hotwired/stimulus"

// The page-branch picker (`Admin::PermissionMatrixComponent`, access-control
// design spec §5): a page tree with a checkbox per page, whose ticked
// boxes are submitted as the grant's `page_ids` -- branch *roots*.
//
// A page under a ticked page is already covered by it (a `page_ids` scope
// matches a root and everything below it), so ticking it too would only
// store a redundant root. This keeps the submitted list to roots: every box
// under a ticked one is shown ticked and disabled -- a disabled input isn't
// submitted -- and gets its own choice back when the ancestor is unticked
// (`data-chosen` remembers it). The summary counts the roots.
//
// The markup is nested `<li>` nodes (`node` targets) each holding its own
// box (`box`) and its children's `<ul>`; hidden inputs for stored roots the
// user can't see (`kept`) count towards the summary but are never touched.
export default class extends Controller {
  static targets = ["box", "node", "summary", "kept"]

  connect() {
    this.boxTargets.forEach((box) => { box.dataset.chosen = box.checked ? "1" : "" })
    this.refresh()
  }

  change(event) {
    event.target.dataset.chosen = event.target.checked ? "1" : ""
    this.refresh()
  }

  refresh() {
    this.boxTargets.forEach((box) => {
      const implied = this.ancestorBoxes(box).some((ancestor) => ancestor.dataset.chosen === "1")
      box.disabled = implied
      box.checked = implied || box.dataset.chosen === "1"
    })

    const roots = this.boxTargets.filter((box) => box.checked && !box.disabled).length + this.keptTargets.length
    if (this.hasSummaryTarget) {
      this.summaryTarget.textContent = roots === 0 ? "All pages" : `${roots} ${roots === 1 ? "branch" : "branches"}`
    }
  }

  // The boxes of the `node`s enclosing this box's own node, nearest first.
  ancestorBoxes(box) {
    const boxes = []
    let node = box.closest("li")?.parentElement?.closest("li")
    while (node && this.element.contains(node)) {
      const own = this.boxTargets.find((candidate) => candidate.closest("li") === node)
      if (own) boxes.push(own)
      node = node.parentElement?.closest("li")
    }
    return boxes
  }
}
