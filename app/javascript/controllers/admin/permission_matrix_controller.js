import { Controller } from "@hotwired/stimulus"

// The group editor's permission rows (`Admin::PermissionMatrixComponent`,
// `Admin::GroupsScreen::PermissionRowComponent`, round 3 Task 10).
//
// - Opens and closes each row's scope editor ("Edit scope" / "Done": the
//   button carries `aria-expanded` and `aria-controls`). Opening moves focus
//   into the editor; Escape inside it closes it and puts focus back on the
//   button. Open and close are only `hidden`: every control stays in the form
//   either way, and the server ignores the scope of an unticked permission, so
//   neither changes what is submitted (the footer's count included).
// - NO SCRIPT: the server renders every editor open and every "Edit scope"
//   held back; `connect` closes the editors it wasn't told to leave open and
//   shows the buttons of the ticked rows.
// - Rewrites the scope CHIPS from the ticked boxes after every change in an
//   editor. The rules are `PermissionRowComponent#chips`' (and its class
//   strings), spelled again here: "All content types" / "All pages" for no
//   restriction, a chip with the type's dot per chosen type, "Own only",
//   "Under <page>" per branch root ("A page you can't open" per kept one), at
//   most three and then "+N", and a warn chip per removed content type.
// - Remove (a removed content type's chip) disables the carried hidden input
//   -- a disabled control is not submitted, so that is the removal -- and
//   announces it with a bubbling `change`, since a hidden input is invisible to
//   the form's footer unless something dispatches.
export default class extends Controller {
  connect() {
    this.rows.forEach((row) => {
      const ticked = this.checkbox(row).checked
      this.button(row).hidden = !ticked
      this.setOpen(row, ticked && this.editor(row).dataset.open === "true")
    })
  }

  get rows() {
    return Array.from(this.element.querySelectorAll("[data-permission]"))
  }

  row(event) {
    return event.target.closest("[data-permission]")
  }

  checkbox(row) {
    return row.querySelector("input[type=checkbox][name$='[enabled]']")
  }

  button(row) {
    return row.querySelector("button[aria-controls]")
  }

  editor(row) {
    return row.querySelector("[data-scope-editor]")
  }

  // The row's own checkbox was ticked or unticked.
  toggle(event) {
    const row = this.row(event)
    const ticked = this.checkbox(row).checked
    this.button(row).hidden = !ticked
    if (!ticked) this.setOpen(row, false)
    this.rewriteChips(row)
  }

  toggleEditor(event) {
    const row = event.currentTarget.closest("[data-permission]")
    const open = this.editor(row).hidden
    this.setOpen(row, open)
    if (open) this.focusInto(row)
  }

  closeFromKey(event) {
    const row = this.row(event)
    if (this.editor(row).hidden) return

    event.preventDefault()
    event.stopPropagation()
    this.setOpen(row, false)
    this.button(row).focus()
  }

  setOpen(row, open) {
    const button = this.button(row)
    this.editor(row).hidden = !open
    button.setAttribute("aria-expanded", String(open))
    button.textContent = open ? button.dataset.openLabel : button.dataset.closedLabel
  }

  focusInto(row) {
    this.editor(row).querySelector("input:not([type=hidden]):not(:disabled), button")?.focus()
  }

  // Something inside a scope editor changed (a box, the Own only switch).
  scopeChanged(event) {
    this.rewriteChips(this.row(event))
  }

  removeType(event) {
    const chip = event.currentTarget.closest("[data-removed-type]")
    const row = chip.closest("[data-permission]")
    const carried = chip.querySelector("input[type=hidden]")
    if (carried) carried.disabled = true
    chip.hidden = true
    this.rewriteChips(row)
    // The chip itself, not the disabled input: it is inside the form, so the
    // footer hears it, and `scopeChanged` rewrites nothing new.
    chip.dispatchEvent(new Event("change", { bubbles: true }))
    this.focusInto(row)
  }

  rewriteChips(row) {
    const container = row.querySelector("[data-chips]")
    container.replaceChildren()
    if (!this.checkbox(row).checked) return

    const editor = this.editor(row)
    const pages = editor.querySelector(".admin-branch-picker")
    const items = pages ? this.pageItems(editor) : this.typeItems(editor)
    const removed = Array.from(editor.querySelectorAll("[data-removed-type]:not([hidden])")).map((chip) => chip.dataset.removedType)

    if (items.length === 0 && removed.length === 0) {
      container.append(this.chip(pages ? "All pages" : "All content types", "dim"))
      return
    }

    items.slice(0, 3).forEach((item) => container.append(this.chip(item.label, "plain", item.dot)))
    if (items.length > 3) container.append(this.chip(`+${items.length - 3}`, "more"))
    removed.sort().forEach((name) => container.append(this.chip(`! ${name} · type removed`, "warn")))
  }

  typeItems(editor) {
    const items = Array.from(editor.querySelectorAll("input[type=checkbox][data-chip-label]:checked"))
      .map((box) => ({ label: box.dataset.chipLabel, dot: box.dataset.chipDot }))
    if (editor.querySelector("input[data-chip-own]:checked")) items.push({ label: "Own only" })
    return items
  }

  pageItems(editor) {
    const roots = Array.from(editor.querySelectorAll("input[type=checkbox][data-chip-label]:checked:not(:disabled)"))
      .map((box) => ({ label: `Under ${box.dataset.chipLabel}` }))
    const kept = editor.querySelectorAll("input[type=hidden][data-admin--branch-picker-target='kept']").length
    return roots.concat(Array.from({ length: kept }, () => ({ label: "A page you can't open" })))
  }

  chip(label, kind, dot) {
    const base = "admin-scope-chip inline-flex items-center gap-1.5 whitespace-nowrap rounded-cs border px-2 py-0.5 text-xs"
    const span = document.createElement("span")
    span.className = kind === "dim" ? `${base} border-transparent text-dim`
      : kind === "warn" ? `${base} border-warn text-warn-ink`
      : `${base} border-transparent bg-sunken text-ink`
    if (dot) {
      const mark = document.createElement("span")
      mark.setAttribute("aria-hidden", "true")
      mark.className = `h-[7px] w-[7px] shrink-0 rounded-full ${dot}`
      span.append(mark)
    }
    span.append(label)
    return span
  }
}
