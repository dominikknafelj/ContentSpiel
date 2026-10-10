import { Controller } from "@hotwired/stimulus"

// A list of rows the editor can add to and remove from (Settings' social
// links, round 3, Task 5). The rows are server-rendered once per stored item;
// "+ Add link" clones the `<template>` -- the same markup with `__INDEX__` where
// the row's number goes -- and the row's × removes it. Row numbers only have
// to be unique and increasing (`next` starts past the last server-rendered
// one): the server reads the rows in numeric order, whatever has gaps.
//
// Adding or removing dispatches a bubbling `change` from the list, which is
// what the form's save footer (`admin--saving--save-bar`) listens to, so it counts a
// row added or removed. The new row's first field takes the focus; after a
// removal focus goes to the next row's field (or "+ Add link" when none is
// left), never to the page.
export default class extends Controller {
  static targets = [ "list", "row", "template" ]
  static values = { next: Number }

  add() {
    const html = this.templateTarget.innerHTML.replaceAll("__INDEX__", String(this.nextValue))
    this.nextValue += 1
    this.listTarget.insertAdjacentHTML("beforeend", html)
    this.listTarget.lastElementChild.querySelector("input")?.focus()
    this.changed()
  }

  remove(event) {
    const row = event.currentTarget.closest("[data-admin--repeat-rows-target='row']")
    if (!row) return
    // The last row is cleared, not removed: one empty row is the "none" state,
    // and without it the form would post no rows at all, which the server
    // reads as "not touched" -- the removed link would stay stored.
    if (this.rowTargets.length === 1) {
      row.querySelectorAll("input").forEach((input) => { input.value = "" })
      row.querySelector("input")?.focus()
      this.changed()
      return
    }
    const following = row.nextElementSibling || row.previousElementSibling
    row.remove()
    ;(following?.querySelector("input") || this.element.querySelector("[data-action~='admin--repeat-rows#add']"))?.focus()
    this.changed()
  }

  changed() {
    this.listTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
