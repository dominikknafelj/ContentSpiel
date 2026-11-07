import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"
import { clearFilter, filterTree, matchFocuses } from "tree/find"

// How long after the last keystroke the status line says the count.
const SAY_AFTER_MS = 300

// The find field of a tree column (`Admin::Ui::TreeFindComponent`). It
// narrows its tree as the person types (`tree/find.js`) and says the count
// in its status line once the typing stops, so a screen reader hears one
// sentence and not one per key.
//
// THE TREE is the element the field's `aria-controls` names, looked up
// whenever it is needed, since a tree's owner may draw it again; its
// `data-tree-locale` is the language a title is matched in. The find tells
// the tree's other scripts by events dispatched on it, which bubble:
// `tree-find:filtered` (`{ query, count }`) whenever it narrows the tree and
// `tree-find:cleared` when it gives the tree back. It hears `tree:changed`
// on the tree, which the tree's owner dispatches after drawing rows again,
// and runs the query once more over the new rows: once per frame however
// many rows were drawn (a tree's rows connect one at a time).
//
// THE KEYS OF A FIND are this controller's alone, for every tree: "/" from
// anywhere but a text field, a dialog or a held modifier focuses the field
// (not when the field cannot be seen: a shut drawer, a folded column);
// Down Arrow in the field focuses the first match's `[data-tree-focus]` (a
// treeitem first takes the tree's one `tabindex="0"`), and Up Arrow from
// there comes back; Enter presses the first match. Escape in a field that
// holds text clears it and keeps the focus there; in an empty field it is
// not taken, so the Escape of a drawer around it still closes the drawer.
//
// IT IS THE ONE WRITER THAT CLEANS THE FIELD: on `turbo:before-cache` the
// field, its hint, its Clear, its status line and the tree's narrowing are
// all taken back, so Turbo's snapshot, and a page restored from it, holds
// the whole tree and an empty field.
export default class extends Controller {
  static targets = ["field", "hint", "clear", "status"]
  static values = { noun: String, moving: Boolean }
  static classes = ["figure", "line"]

  connect() {
    this.filtering = false
    this.said = null
    if (this.fieldTarget.value) this.filter()
  }

  disconnect() {
    clearTimeout(this.sayTimer)
    cancelAnimationFrame(this.frame)
  }

  get tree() {
    return document.getElementById(this.fieldTarget.getAttribute("aria-controls"))
  }

  get query() {
    return this.fieldTarget.value.trim()
  }

  // `input` on the field: the tree narrows at once, the line is written
  // after the typing stops.
  filter() {
    const empty = this.fieldTarget.value === ""
    this.hintTarget.hidden = !empty
    this.clearTarget.hidden = empty
    this.apply()
  }

  apply() {
    const tree = this.tree
    if (!tree) return

    const query = this.query
    if (!query) {
      this.unfilter(tree)
      return
    }
    const { count } = filterTree(tree, query, { locale: tree.dataset.treeLocale })
    this.filtering = true
    tree.dispatchEvent(new CustomEvent("tree-find:filtered", { bubbles: true, detail: { query, count } }))
    this.sayLater(count)
  }

  unfilter(tree) {
    clearTimeout(this.sayTimer)
    this.said = null
    this.statusTarget.replaceChildren()
    if (!this.filtering) return

    this.filtering = false
    clearFilter(tree)
    tree.dispatchEvent(new CustomEvent("tree-find:cleared", { bubbles: true }))
  }

  // Clear: the field emptied and the tree given back, the focus in the field.
  clear() {
    this.empty()
    this.fieldTarget.focus()
  }

  empty() {
    this.fieldTarget.value = ""
    this.filter()
  }

  // The tree's rows were drawn again: the query runs over them, once a frame.
  changed(event) {
    if (!this.filtering || event.target !== this.tree) return

    cancelAnimationFrame(this.frame)
    this.frame = requestAnimationFrame(() => this.apply())
  }

  // The line is written whole, in one change, and only when what it says
  // changed (a redrawn row that runs the query again says nothing new).
  sayLater(count) {
    clearTimeout(this.sayTimer)
    this.sayTimer = setTimeout(() => this.say(count), SAY_AFTER_MS)
  }

  say(count) {
    if (this.said === count) return
    this.said = count

    const words = messages(this.element)
    const parts = []
    if (count === 0) {
      parts.push(words.t(`components.ui.tree_find.none.${this.nounValue}`))
    } else {
      // The figure keeps the sentence's own place for it, drawn in its look.
      const sentence = words.t(`components.ui.tree_find.count.${this.nounValue}`, { count })
      const figure = String(count)
      const at = sentence.indexOf(figure)
      if (at < 0) {
        parts.push(sentence)
      } else {
        const span = document.createElement("span")
        span.classList.add(...this.figureClasses)
        span.textContent = figure
        parts.push(sentence.slice(0, at), span, sentence.slice(at + figure.length))
      }
    }
    if (this.movingValue) {
      const line = document.createElement("span")
      line.classList.add(...this.lineClasses)
      line.textContent = words.t("components.ui.tree_find.no_moving")
      parts.push(" ", line)
    }
    this.statusTarget.replaceChildren(...parts)
  }

  // Keys in the field.
  key(event) {
    if (event.key === "Escape") {
      if (this.fieldTarget.value === "") return
      event.preventDefault()
      event.stopPropagation()
      this.empty()
    } else if (event.key === "ArrowDown") {
      const first = this.firstMatch()
      if (!first) return
      event.preventDefault()
      const tree = this.tree
      if (first.matches('[role="treeitem"]')) {
        tree.querySelectorAll('[role="treeitem"][tabindex="0"]').forEach((item) => item.setAttribute("tabindex", "-1"))
        first.setAttribute("tabindex", "0")
      }
      first.focus()
    } else if (event.key === "Enter") {
      const first = this.firstMatch()
      if (!first) return
      event.preventDefault()
      first.click()
    }
  }

  // Up Arrow on the first match goes back to the field.
  treeKey(event) {
    if (event.key !== "ArrowUp" || !this.filtering) return
    const first = this.firstMatch()
    if (!first || event.target !== first) return

    event.preventDefault()
    event.stopPropagation()
    this.fieldTarget.focus()
  }

  firstMatch() {
    const tree = this.tree
    if (!this.filtering || !tree) return null
    return matchFocuses(tree)[0] ?? null
  }

  // "/" anywhere a slash is not being typed: not in a control that takes
  // text (a checkbox, a radio or a button leaves the key to the find).
  slash(event) {
    if (event.key !== "/" || event.defaultPrevented || event.isComposing) return
    if (event.ctrlKey || event.metaKey || event.altKey) return
    const target = event.target
    if (target instanceof Element) {
      if (takesText(target) || target.closest("dialog[open]") || target.isContentEditable) return
    }
    if (!this.fieldTarget.checkVisibility({ visibilityProperty: true })) return

    event.preventDefault()
    this.fieldTarget.focus()
  }

  // Before Turbo's snapshot: an empty field and the whole tree.
  reset() {
    cancelAnimationFrame(this.frame)
    this.empty()
  }
}

// The input types that are not text entry; any other type, a made-up one
// included, is drawn as a text field by the browser.
const NOT_TEXT_INPUTS = new Set(["checkbox", "radio", "button", "submit", "reset", "image", "file", "range", "color", "hidden"])

function takesText(element) {
  const control = element.closest("input, textarea, select")
  if (!control) return false
  if (control instanceof HTMLInputElement) return !NOT_TEXT_INPUTS.has(control.type)
  return true
}
