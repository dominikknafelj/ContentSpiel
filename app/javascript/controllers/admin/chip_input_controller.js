import { Controller } from "@hotwired/stimulus"

// A multi-value input that shows each value as a removable chip, with
// autocomplete (`Admin::ChipInputComponent`; its class comment has the form
// contract). The post editor's tags and related posts both use it, and a
// post-list block's tag filter in its `single` form (one chip at most: a new
// choice replaces the old one).
//
// What it owns: one hidden `<input name=...>` per chip inside the form (next
// to the component's blank sentinel), the suggestion list under the text
// field, keyboard handling, and a polite live region that announces each
// addition and removal. What it deliberately does not own: saving. A chip
// change dispatches a bubbling `change` from the sentinel -- a real control
// in the form -- so the form's own `admin--autosave` sees it like any other
// edit and sends the whole list. The text field's own `input`/`change`
// events are swallowed at the component's root (`swallow`), so typing a
// search never queues a save; and since a save is only sent when the form's
// submitted values differ from the last send, the `focusout` flush that
// follows leaving the field sends nothing either.
//
// Keyboard: ArrowDown opens the list / moves down, ArrowUp moves up, Enter
// picks the highlighted suggestion (or, where `create` is on, commits the
// typed text), a comma commits the typed text (`create` only), Escape closes
// the list, Backspace in an empty field removes the last chip, ArrowLeft at
// the start of the field moves onto the last chip's remove button, and
// from there ArrowLeft/ArrowRight walk the chips (ArrowRight past the last
// returns to the field) and Backspace/Delete/Enter/Space remove one. After a
// removal focus lands on the neighbouring chip's button, else the field.
//
// View-only: the surrounding `<fieldset disabled>` disables the input and
// every remove button, so nothing here can fire; each action still checks
// `inputTarget.disabled` as a belt for a programmatic call.
//
// Every string reaches the DOM through `textContent`/attributes -- a tag
// name or a post title is data, never markup.
const DEBOUNCE_MS = 150
const MAX_OPTIONS = 8

export default class extends Controller {
  static targets = ["input", "list", "listbox", "status", "sentinel", "chipTemplate", "optionTemplate"]
  static values = { searchUrl: String, name: String, create: Boolean, noun: String, single: Boolean }

  connect() {
    this.items = []
    this.active = -1
    this.sequence = 0
  }

  disconnect() {
    clearTimeout(this.timer)
    clearTimeout(this.announceTimer)
    this.aborter?.abort()
  }

  // --- Events that must not reach the form ---------------------------------

  swallow(event) {
    if (event.target === this.inputTarget) event.stopPropagation()
  }

  focusInput(event) {
    if (event.target.closest("button, input, [role=listbox]")) return
    this.inputTarget.focus()
  }

  // --- Searching -----------------------------------------------------------

  search() {
    clearTimeout(this.timer)
    if (this.query === "") return this.close()
    this.timer = setTimeout(() => this.fetchSuggestions(this.query), DEBOUNCE_MS)
  }

  get query() {
    return this.inputTarget.value.trim()
  }

  async fetchSuggestions(query) {
    this.aborter?.abort()
    this.aborter = new AbortController()
    const sequence = ++this.sequence

    const url = new URL(this.searchUrlValue, window.location.origin)
    url.searchParams.set("q", query)

    let rows
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, signal: this.aborter.signal })
      if (!response.ok) throw new Error(`suggestions answered ${response.status}`)
      rows = await response.json()
    } catch (error) {
      if (error.name === "AbortError") return
      // An older request failing must not replace what a newer one shows.
      if (sequence === this.sequence) this.showMessage("Search failed — try again.")
      return
    }

    // An answer for text that is no longer in the field (or superseded by a
    // newer request) is dropped, never rendered under the wrong query.
    if (sequence !== this.sequence || query !== this.query) return
    this.showSuggestions(query, rows.map((row) => this.normalize(row)))
  }

  // Two row shapes: `{ value, label, hint }` (tag suggestions) and the link
  // targets' `{ id, title, status, dot }`. A status other than live reads as
  // "Draft" / "Scheduled" -- in the list and, after "·", on the chip.
  normalize(row) {
    const status = row.status && row.status !== "live" ? row.status[0].toUpperCase() + row.status.slice(1) : null
    return {
      value: String(row.value ?? row.id),
      label: row.label ?? row.title ?? "Untitled",
      hint: row.hint ?? status,
      chipHint: status,
      dot: row.dot ?? null
    }
  }

  showSuggestions(query, rows) {
    const items = rows.filter((item) => !this.hasChip(item.value)).slice(0, MAX_OPTIONS)

    // "Create tag “x”" only when nothing already matches the text exactly,
    // in the results or among the chips (names compare case-insensitively).
    if (this.createValue && query && !rows.some((row) => this.same(row.value, query)) && !this.hasChip(query)) {
      items.push({ value: this.fold(query), label: this.fold(query), create: true })
    }

    if (items.length === 0) return this.showMessage(`No matching ${this.nounValue}s.`)

    this.items = items
    this.listboxTarget.replaceChildren(...items.map((item, index) => this.optionFor(item, index)))
    this.active = -1
    this.open()
  }

  optionFor(item, index) {
    const option = this.optionTemplateTarget.content.firstElementChild.cloneNode(true)
    option.id = `${this.inputTarget.id}-option-${index}`
    option.dataset.index = index

    const label = option.querySelector("[data-option-label]")
    if (item.create) {
      label.textContent = `Create ${this.nounValue} “${item.label}”`
    } else {
      label.textContent = item.label
      this.setDot(option, item.dot)
      this.setHint(option.querySelector("[data-option-hint]"), item.hint, "")
    }
    return option
  }

  showMessage(message) {
    const option = this.optionTemplateTarget.content.firstElementChild.cloneNode(true)
    option.setAttribute("aria-disabled", "true")
    option.classList.remove("cursor-pointer")
    option.querySelector("[data-option-label]").textContent = message
    this.items = []
    this.active = -1
    this.listboxTarget.replaceChildren(option)
    this.open()
  }

  open() {
    this.listboxTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    clearTimeout(this.timer)
    this.listboxTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
    this.active = -1
  }

  // A press on a suggestion must not blur the field (that would close the
  // list, and `focusout` would flush an autosave, before the click lands).
  holdFocus(event) {
    event.preventDefault()
  }

  choose(event) {
    const option = event.target.closest("[role=option]")
    if (!option || option.getAttribute("aria-disabled") === "true") return
    this.pick(this.items[Number(option.dataset.index)])
    this.inputTarget.focus()
  }

  move(step) {
    if (this.items.length === 0) return
    this.active = (this.active + step + this.items.length) % this.items.length
    Array.from(this.listboxTarget.children).forEach((option, index) => {
      option.setAttribute("aria-selected", String(index === this.active))
      if (index === this.active) {
        this.inputTarget.setAttribute("aria-activedescendant", option.id)
        option.scrollIntoView({ block: "nearest" })
      }
    })
  }

  // --- Keyboard ------------------------------------------------------------

  keydown(event) {
    if (this.inputTarget.disabled || event.isComposing) return
    const input = this.inputTarget

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        if (this.listboxTarget.hidden) this.fetchSuggestions(this.query)
        else this.move(1)
        break
      case "ArrowUp":
        if (this.listboxTarget.hidden) return
        event.preventDefault()
        this.move(-1)
        break
      case "Enter":
        // Never submits the form.
        event.preventDefault()
        if (!this.listboxTarget.hidden && this.active >= 0) this.pick(this.items[this.active])
        else if (this.createValue && this.query) this.pick({ value: this.fold(this.query), label: this.fold(this.query) })
        break
      case ",":
        if (!this.createValue) return
        event.preventDefault()
        if (this.query) this.pick({ value: this.fold(this.query), label: this.fold(this.query) })
        break
      case "Escape":
        if (this.listboxTarget.hidden) return
        event.preventDefault()
        event.stopPropagation()
        this.close()
        break
      case "Backspace":
        if (input.value !== "" || this.chips.length === 0) return
        event.preventDefault()
        this.removeChip(this.chips.at(-1), { focus: "input" })
        break
      case "ArrowLeft":
        if (input.selectionStart !== 0 || input.selectionEnd !== 0 || this.chips.length === 0) return
        event.preventDefault()
        this.removeButton(this.chips.at(-1)).focus()
        break
      case "Tab":
        this.close()
        break
    }
  }

  chipKeydown(event) {
    if (this.inputTarget.disabled) return
    const chip = event.currentTarget.closest("li")

    switch (event.key) {
      case "ArrowLeft":
        event.preventDefault()
        ;(chip.previousElementSibling ? this.removeButton(chip.previousElementSibling) : event.currentTarget).focus()
        break
      case "ArrowRight":
        event.preventDefault()
        ;(chip.nextElementSibling ? this.removeButton(chip.nextElementSibling) : this.inputTarget).focus()
        break
      case "Backspace":
      case "Delete":
        event.preventDefault()
        this.removeChip(chip)
        break
    }
  }

  // --- Chips ---------------------------------------------------------------

  get chips() {
    return Array.from(this.listTarget.children)
  }

  removeButton(chip) {
    return chip.querySelector("button")
  }

  hasChip(value) {
    return this.chips.some((chip) => this.same(chip.dataset.chipValue, value))
  }

  same(a, b) {
    return String(a).toLowerCase() === String(b).toLowerCase()
  }

  // Tags are stored lower-case (`Posts::Save#assign_tags`), so a name the
  // editor creates here reads the way it will after the next page load.
  fold(text) {
    return this.createValue ? text.toLowerCase() : text
  }

  pick(item) {
    if (!item || this.inputTarget.disabled) return
    this.inputTarget.value = ""
    this.close()
    if (this.hasChip(item.value)) return this.announce(`${item.label} is already added.`)

    // A one-value field (`single`) holds one chip: choosing another replaces it.
    if (this.singleValue) this.chips.forEach((existing) => existing.remove())

    const chip = this.chipTemplateTarget.content.firstElementChild.cloneNode(true)
    chip.dataset.chipValue = item.value
    chip.querySelector("[data-chip-label]").textContent = item.label
    this.setDot(chip, item.dot)
    this.setHint(chip.querySelector("[data-chip-hint]"), item.chipHint, "· ")
    chip.querySelector("input").value = item.value
    this.removeButton(chip).setAttribute("aria-label", `Remove ${item.label}`)
    this.listTarget.append(chip)

    this.announce(`Added ${item.label}.`)
    this.changed()
  }

  remove(event) {
    if (this.inputTarget.disabled) return
    this.removeChip(event.currentTarget.closest("li"))
  }

  // `focus: "input"` keeps the caret where it is (Backspace in the field);
  // otherwise focus moves to a neighbouring chip's button, else the field,
  // *before* the chip goes, so it never lands on <body>.
  removeChip(chip, { focus = "neighbour" } = {}) {
    if (this.inputTarget.disabled) return
    const neighbour = chip.nextElementSibling || chip.previousElementSibling
    const label = chip.querySelector("[data-chip-label]").textContent

    if (focus === "input" || !neighbour) this.inputTarget.focus()
    else this.removeButton(neighbour).focus()

    chip.remove()
    this.announce(`Removed ${label}.`)
    this.changed()
  }

  setDot(element, dotClasses) {
    const dot = element.querySelector(".admin-chip__dot")
    if (!dot) return
    dot.hidden = !dotClasses
    if (dotClasses) dot.classList.add(...dotClasses.split(" "))
  }

  setHint(element, hint, prefix) {
    if (!element) return
    element.hidden = !hint
    element.textContent = hint ? `${prefix}${hint}` : ""
  }

  announce(message) {
    this.statusTarget.textContent = ""
    // Emptied first, then filled a beat later, so a repeated message is
    // announced again (a timeout, not an animation frame: a background tab
    // runs no frames).
    clearTimeout(this.announceTimer)
    this.announceTimer = setTimeout(() => { this.statusTarget.textContent = message }, 50)
  }

  // The bubbling `change` the form's autosave listens for, from a real
  // control (the sentinel) rather than from the text field, whose own events
  // `swallow` stops.
  changed() {
    this.sentinelTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
