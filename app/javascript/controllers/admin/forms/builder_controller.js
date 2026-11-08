import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"

// The form builder: adds a field
// from the `<template>` of its type, moves a field up or down, removes one,
// folds a row, and does the same for the choices of a choice field. It writes
// nothing but the form's own inputs, and nothing to the server: the save bar
// (`admin--saving--save-bar`) counts what changed and Save sends it.
//
// ONE CHANGE PER MOVE. Every input of a row is named by the row
// (`form[fields][<row>][...]`), a name that does not move, and the order is
// one tracked hidden input (`form[field_order]`, the rows' names, and inside
// a field `choice_order`). A move rewrites that one input and dispatches a
// bubbling `input` on it, so the bar counts one change for one move;
// renumbered names would have counted every input below the move.
//
// A REMOVED ROW STAYS IN THE PAGE, hidden, and leaves the order: the server
// reads the rows the order names and drops the rest (`Admin::FormsScreen::
// Draft`), and its inputs, unchanged, count nothing, so a removal is one
// change too. The save bar's Discard, which reloads, brings it back.
//
// FOCUS AND WORDS. The focus stays on the arrow pressed; at
// the end of the list it goes to the row's other arrow. After a removal it
// goes to the next row's heading, else the previous one's, else the picker's
// first button. Each move, removal and addition is said in the polite live
// region. Every word comes from `data-messages`; a label typed into the page
// is written with `textContent` and attributes only.
export default class extends Controller {
  static targets = [ "form", "list", "row", "template", "choiceTemplate", "order", "status", "empty", "picker", "full", "keep" ]
  static values = { maxFields: Number, maxChoices: { type: Number, default: 50 } }

  connect() {
    this.counter = 0
  }

  // --- fields ---------------------------------------------------------------

  add(event) {
    const type = event.params.type
    const template = this.templateTargets.find((element) => element.dataset.type === type)
    if (!template || this.rows.length >= this.maxFieldsValue) return

    const name = this.newName()
    const html = template.innerHTML.replaceAll("__ROW__", name).replace(/__CHOICE(\d+)__/g, (_, index) => `${name}-c${index}`)
    this.listTarget.insertAdjacentHTML("beforeend", html)
    const row = this.listTarget.lastElementChild
    this.refreshChoices(row)
    this.refresh()
    this.writeOrder()
    row.querySelector("input[name$='[label][" + this.labelLocale(row) + "]']")?.focus()
    this.say("components.forms_screen.builder.added", { type: event.currentTarget.textContent.trim() })
  }

  up(event) { this.move(event, -1) }

  down(event) { this.move(event, 1) }

  move(event, step) {
    const row = this.rowOf(event.currentTarget)
    const rows = this.rows
    const index = rows.indexOf(row)
    const other = rows[index + step]
    if (!other) return

    if (step < 0) other.before(row)
    else other.after(row)
    this.refresh()
    this.writeOrder()
    this.keepFocus(row, step < 0 ? "up" : "down")
    this.say("components.forms_screen.builder.moved", { label: this.labelOf(row), position: this.rows.indexOf(row) + 1, count: this.rows.length })
  }

  remove(event) {
    const row = this.rowOf(event.currentTarget)
    const rows = this.rows
    const index = rows.indexOf(row)
    const label = this.labelOf(row)
    row.hidden = true
    this.refresh()
    this.writeOrder()
    const next = rows[index + 1] || rows[index - 1]
    ;(next ? next.querySelector("[aria-expanded]") : this.pickerTargets.find((button) => !button.disabled))?.focus()
    this.say("components.forms_screen.builder.removed", { label })
  }

  // The head's button folds the row's body; the body stays in the form.
  fold(event) {
    const button = event.currentTarget
    const body = this.rowOf(button).querySelector("[data-admin--forms--builder-target='body']")
    const open = button.getAttribute("aria-expanded") !== "true"
    button.setAttribute("aria-expanded", String(open))
    if (body) body.hidden = !open
  }

  // The label as typed is the row's name everywhere: the head, and the
  // arrows' and Remove's names.
  relabel(event) {
    const row = this.rowOf(event.currentTarget)
    const heading = row.querySelector("[data-admin--forms--builder-target='heading']")
    const label = event.currentTarget.value.trim()
    if (heading) {
      heading.textContent = label || this.text.t("components.forms_screen.field_row.no_label")
      heading.classList.toggle("text-meta", !label)
      heading.classList.toggle("font-normal", !label)
    }
    this.nameButtons(row)
  }

  required(event) {
    const mark = this.rowOf(event.currentTarget).querySelector("[data-admin--forms--builder-target='requiredMark']")
    if (mark) mark.hidden = !event.currentTarget.checked
  }

  // --- choices --------------------------------------------------------------

  addChoice(event) {
    const row = this.rowOf(event.currentTarget)
    const list = row.querySelector("[data-admin--forms--builder-target='choices']")
    if (!list || this.choicesOf(row).length >= this.maxChoicesValue) return

    const html = this.choiceTemplateTarget.innerHTML.replaceAll("__ROW__", row.dataset.row).replaceAll("__CHOICE__", this.newName())
    list.insertAdjacentHTML("beforeend", html)
    this.refreshChoices(row)
    this.writeChoiceOrder(row)
    list.lastElementChild.querySelector("input[type=text]")?.focus()
  }

  choiceUp(event) { this.moveChoice(event, -1) }

  choiceDown(event) { this.moveChoice(event, 1) }

  moveChoice(event, step) {
    const choice = event.currentTarget.closest("[data-admin--forms--builder-target='choice']")
    const row = this.rowOf(choice)
    const choices = this.choicesOf(row)
    const other = choices[choices.indexOf(choice) + step]
    if (!other) return

    if (step < 0) other.before(choice)
    else other.after(choice)
    this.refreshChoices(row)
    this.writeChoiceOrder(row)
    this.keepFocus(choice, step < 0 ? "choiceUp" : "choiceDown")
    this.say("components.forms_screen.builder.moved", { label: this.choiceLabelOf(choice), position: this.choicesOf(row).indexOf(choice) + 1, count: this.choicesOf(row).length })
  }

  removeChoice(event) {
    const choice = event.currentTarget.closest("[data-admin--forms--builder-target='choice']")
    const row = this.rowOf(choice)
    const choices = this.choicesOf(row)
    const index = choices.indexOf(choice)
    const label = this.choiceLabelOf(choice)
    choice.hidden = true
    this.refreshChoices(row)
    this.writeChoiceOrder(row)
    const next = choices[index + 1] || choices[index - 1]
    ;(next ? next.querySelector("input[type=text]") : row.querySelector("[data-admin--forms--builder-target='addChoice']"))?.focus()
    this.say("components.forms_screen.builder.removed", { label })
  }

  relabelChoice(event) {
    const choice = event.currentTarget.closest("[data-admin--forms--builder-target='choice']")
    this.nameChoiceButtons(choice)
  }

  // --- destinations ---------------------------------------------------------

  // A section's settings show while its box is ticked; keeping's "not kept"
  // line, and the mail warning's "They wait…", while it is not.
  toggle(event) {
    const box = event.currentTarget
    const section = box.closest("[data-forms-section]")
    section?.querySelectorAll("[data-when-checked]").forEach((element) => { element.hidden = !box.checked })
    section?.querySelectorAll("[data-when-unchecked]").forEach((element) => { element.hidden = box.checked })
    if (this.hasKeepTarget && box === this.keepTarget) {
      this.element.querySelectorAll("[data-unless-kept]").forEach((element) => { element.hidden = box.checked })
    }
  }

  // --- the bookkeeping ------------------------------------------------------

  get text() { return messages(this.element) }

  get rows() { return this.rowTargets.filter((row) => !row.hidden) }

  rowOf(element) { return element.closest(".admin-form-field-row") }

  choicesOf(row) {
    return [ ...row.querySelectorAll("[data-admin--forms--builder-target='choice']") ].filter((choice) => !choice.hidden)
  }

  // A row's name: unique in the page, never a stored key's shape.
  newName() {
    this.counter += 1
    return `new-${Date.now().toString(36)}-${this.counter}`
  }

  labelLocale(row) {
    const input = row.querySelector("input[name*='[label]']")
    return input?.name.match(/\[label\]\[([^\]]+)\]$/)?.[1] || ""
  }

  labelOf(row) {
    const input = row.querySelector(`input[name$='[label][${this.labelLocale(row)}]']`)
    return input?.value.trim() || this.text.t("components.forms_screen.field_row.no_label")
  }

  choiceLabelOf(choice) {
    const input = choice.querySelector("input[type=text]")
    const number = this.choicesOf(this.rowOf(choice)).indexOf(choice) + 1
    return input?.value.trim() || this.text.t("components.forms_screen.choice_row.number", { number: Math.max(number, 1) })
  }

  // The arrows of the first and last rows are disabled, the empty line and
  // the picker follow the number of rows, and every button is named after
  // its row's label.
  refresh() {
    const rows = this.rows
    rows.forEach((row, index) => {
      const up = row.querySelector("[data-admin--forms--builder-target='up']")
      const down = row.querySelector("[data-admin--forms--builder-target='down']")
      if (up) up.disabled = index === 0
      if (down) down.disabled = index === rows.length - 1
      this.nameButtons(row)
    })
    if (this.hasEmptyTarget) this.emptyTarget.hidden = rows.length > 0
    const full = rows.length >= this.maxFieldsValue
    this.pickerTargets.forEach((button) => { button.disabled = full })
    if (this.hasFullTarget) this.fullTarget.hidden = !full
  }

  nameButtons(row) {
    const label = this.labelOf(row)
    const name = (selector, key) => row.querySelector(selector)?.setAttribute("aria-label", this.text.t(key, { label }))
    name(":scope > div > span > [data-admin--forms--builder-target='up']", "components.forms_screen.field_row.up")
    name(":scope > div > span > [data-admin--forms--builder-target='down']", "components.forms_screen.field_row.down")
    name(":scope > div > span > [data-action~='admin--forms--builder#remove']", "components.forms_screen.field_row.remove_label")
  }

  refreshChoices(row) {
    const choices = this.choicesOf(row)
    choices.forEach((choice, index) => {
      const number = choice.querySelector("[data-admin--forms--builder-target='choiceNumber']")
      const label = choice.querySelector("[data-admin--forms--builder-target='choiceLabel']")
      if (number) number.textContent = String(index + 1)
      if (label) label.textContent = this.text.t("components.forms_screen.choice_row.number", { number: index + 1 })
      const up = choice.querySelector("[data-admin--forms--builder-target='choiceUp']")
      const down = choice.querySelector("[data-admin--forms--builder-target='choiceDown']")
      if (up) up.disabled = index === 0
      if (down) down.disabled = index === choices.length - 1
      this.nameChoiceButtons(choice)
    })
    const add = row.querySelector("[data-admin--forms--builder-target='addChoice']")
    const full = row.querySelector("[data-admin--forms--builder-target='choicesFull']")
    const atMost = choices.length >= this.maxChoicesValue
    if (add) add.disabled = atMost
    if (full) full.hidden = !atMost
  }

  nameChoiceButtons(choice) {
    const label = this.choiceLabelOf(choice)
    const name = (selector, key) => choice.querySelector(selector)?.setAttribute("aria-label", this.text.t(key, { label }))
    name("[data-admin--forms--builder-target='choiceUp']", "components.forms_screen.choice_row.up")
    name("[data-admin--forms--builder-target='choiceDown']", "components.forms_screen.choice_row.down")
    name("[data-action~='admin--forms--builder#removeChoice']", "components.forms_screen.choice_row.remove_label")
  }

  writeOrder() {
    if (!this.hasOrderTarget) return
    this.write(this.orderTarget, this.rows.map((row) => row.dataset.row).join(" "))
  }

  writeChoiceOrder(row) {
    const order = row.querySelector("[data-admin--forms--builder-target='choiceOrder']")
    if (order) this.write(order, this.choicesOf(row).map((choice) => choice.dataset.row).join(" "))
  }

  // A tracked hidden input's new value, told to the save bar.
  write(input, value) {
    input.value = value
    input.dispatchEvent(new Event("input", { bubbles: true }))
  }

  // The focus stays on the arrow pressed; one that is now disabled hands it
  // to the other arrow of the same row.
  keepFocus(element, which) {
    const other = which.startsWith("choice") ? (which === "choiceUp" ? "choiceDown" : "choiceUp") : (which === "up" ? "down" : "up")
    const scope = which.startsWith("choice") ? element : element.querySelector(":scope > div")
    const pressed = scope.querySelector(`[data-admin--forms--builder-target='${which}']`)
    const fallback = scope.querySelector(`[data-admin--forms--builder-target='${other}']`)
    ;(pressed && !pressed.disabled ? pressed : fallback)?.focus()
  }

  say(key, values) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = this.text.t(key, values)
  }
}
