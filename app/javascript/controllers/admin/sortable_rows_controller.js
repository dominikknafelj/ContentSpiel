import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Rows that can be reordered, where the new order is only PENDING (design pass
// round 3, Task 6): the Languages card in Settings. Unlike the block list
// (`admin--editor--blocks`, whose every move is a request through the write queue --
// that controller is not touched), nothing is sent here. A drag or a keyboard
// drop only rewrites the DOM order and the one tracked field that carries it,
// then dispatches a bubbling `input` + `change` on that field so the screen's
// save footer counts it ("1 unsaved change") and the Save that follows sends
// the rows in their new order. Cancel on the footer reloads the screen.
//
//   <section data-controller="admin--sortable-rows">
//     <input type="hidden" data-admin--sortable-rows-target="order" data-save-bar-track value="en,de">
//     <p data-admin--sortable-rows-target="announcer" aria-live="assertive" class="sr-only"></p>
//     <ul data-admin--sortable-rows-target="list">
//       <li data-admin--sortable-rows-target="row" data-label="Deutsch">
//         <button type="button" data-admin--sortable-rows-target="handle"
//                 data-action="keydown->admin--sortable-rows#key focusout->admin--sortable-rows#blur">⠿</button>
//
// WHY ONE ORDER FIELD. The footer counts a change per control POSITION, so
// moving one row down by one would change two positional keys (the row inputs
// swap places) and read "2 unsaved changes" for what the editor did once. The
// `order` field is one control whose value is the codes in order (each row's
// `data-code`): one reorder, one change however far it went, and moved back
// to where it started it is no change at all. The rows' own inputs (hidden
// `[][code]`, the fallback select) move with their row and are what is
// submitted.
//
// Same drag options as the block list and the page tree (SortableJS with
// `forceFallback`: the handles are `<button>`s, which Firefox can't start a
// native drag from) and the same keyboard path: Space picks a row up,
// ArrowUp/ArrowDown move it, Space drops it, Escape (or focus leaving the
// handle) puts it back; each step is announced in the `aria-live` region.
export default class extends Controller {
  static targets = ["list", "row", "order", "announcer", "handle"]

  connect() {
    this.sortable = Sortable.create(this.listTarget, {
      handle: "[data-admin--sortable-rows-target='handle']",
      animation: 150,
      ghostClass: "admin-drag-ghost",
      chosenClass: "admin-drag-chosen",
      forceFallback: true,
      fallbackOnBody: true,
      fallbackClass: "admin-drag-fallback",
      fallbackTolerance: 3,
      onStart: (event) => {
        this.endKeyboardPickUp(event.item)
        this.makeCloneInert()
      },
      onEnd: () => this.commit()
    })
  }

  disconnect() {
    this.sortable?.destroy()
    this.sortable = null
  }

  // A pointer drag that starts while a row is still picked up by the keyboard
  // ends that pick-up: two rows "held" at once, one by each path, left the
  // announcer and the picked styling describing a move that was no longer
  // happening, and a later Escape put a row "back" over the drag's result.
  // Another row goes back where it was picked up; the dragged row itself is
  // only un-picked -- it is in SortableJS's hands now, from where it stands.
  endKeyboardPickUp(dragged) {
    if (!this.picked) return
    if (this.picked === dragged) this.clearPicked(dragged)
    else this.cancel(this.picked, { refocus: false })
  }

  // The dragged clone is a picture of the row, appended to <body> outside the
  // form: stripped of ids and Stimulus wiring (as `admin--editor--blocks` does) so
  // nothing exists twice or connects in it.
  makeCloneInert() {
    const clone = Sortable.ghost
    if (!clone) return
    for (const element of [clone, ...clone.querySelectorAll("*")]) {
      for (const { name } of Array.from(element.attributes)) {
        if (name === "id" || name === "name" || name === "data-controller" || name === "data-action" || /^data-.+-target$/.test(name)) {
          element.removeAttribute(name)
        }
      }
    }
  }

  // The order field follows the rows. Only an actual change is announced to
  // the form, so a drop where it was picked up counts nothing.
  commit() {
    if (!this.hasOrderTarget) return
    const value = this.rowTargets.map((row) => row.dataset.code).join(",")
    if (this.orderTarget.value === value) return
    this.orderTarget.value = value
    this.orderTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.orderTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  // ---- Keyboard path -----------------------------------------------------
  key(event) {
    const row = this.rowFor(event)
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
    }
  }

  pickUp(row) {
    if (this.picked && this.picked !== row) this.cancel(this.picked, { refocus: false })
    this.picked = row
    this.originNext = row.nextElementSibling
    row.dataset.picked = "true"
    row.classList.add("admin-drag-chosen")
    this.announce(`Picked up ${this.labelOf(row)}. ${this.positionOf(row)}`)
  }

  step(row, direction) {
    const index = this.rowTargets.indexOf(row)
    const neighbour = this.rowTargets[index + direction]
    if (!neighbour) return
    this.listTarget.insertBefore(row, direction < 0 ? neighbour : neighbour.nextElementSibling)
    // A DOM move blurs the focused handle; give it back so the next key
    // press still reaches this row.
    this.focusHandle(row)
    this.announce(this.positionOf(row))
  }

  drop(row) {
    this.clearPicked(row)
    this.announce(`Dropped ${this.labelOf(row)}. ${this.positionOf(row)}`)
    this.commit()
  }

  // Focus leaving the handle puts a picked row back. A move blurs the handle
  // too and refocuses at once, so judge after the current task.
  blur(event) {
    const handle = event.currentTarget
    const row = this.rowFor(event)
    setTimeout(() => {
      if (this.picked === row && document.activeElement !== handle) this.cancel(row, { refocus: false })
    }, 0)
  }

  cancel(row, { refocus = true } = {}) {
    this.listTarget.insertBefore(row, this.originNext)
    this.clearPicked(row)
    if (refocus) this.focusHandle(row)
    this.announce(`Cancelled. ${this.labelOf(row)} is back where it was.`)
  }

  clearPicked(row) {
    delete row.dataset.picked
    row.classList.remove("admin-drag-chosen")
    this.picked = null
  }

  focusHandle(row) {
    row.querySelector("[data-admin--sortable-rows-target='handle']")?.focus()
  }

  labelOf(row) { return row.dataset.label || "row" }

  positionOf(row) {
    return `Position ${this.rowTargets.indexOf(row) + 1} of ${this.rowTargets.length}.`
  }

  announce(message) {
    if (this.hasAnnouncerTarget) this.announcerTarget.textContent = message
  }

  rowFor(event) {
    return event.currentTarget.closest("[data-admin--sortable-rows-target='row']")
  }
}
