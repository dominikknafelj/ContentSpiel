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
// removal focus goes to the next row's field, else the previous one's, else
// "+ Add link", never to the page.
//
// Removing the last row leaves no row at all: the list starts empty. The form
// still says it carries the links (the fieldset's hidden
// `site_setting[social_links_present]`), so the server reads "no rows" as
// "none" and clears them.
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
    const row = event.currentTarget.closest("[data-admin--settings--repeat-rows-target='row']")
    if (!row) return
    const following = row.nextElementSibling || row.previousElementSibling
    row.remove()
    ;(following?.querySelector("input") || this.element.querySelector("[data-action~='admin--settings--repeat-rows#add']"))?.focus()
    this.changed()
  }

  changed() {
    this.listTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
