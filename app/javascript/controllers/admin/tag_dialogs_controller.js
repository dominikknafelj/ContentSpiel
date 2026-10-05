import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { messages } from "i18n/messages"

// The Tags list's two dialogs, Merge and Delete (`app/views/admin/tags/index.html.erb`).
// There is ONE of each in the page, not one per row: a row's menu item opens
// the dialog with `data: dialog_trigger(id)` and carries that row's facts as
// `data-tag-*` attributes (the id, the name, the already-worded title and
// sentence -- `Admin::TagsHelper` chooses them from the locale file, so the copy is tested in Ruby).
// `admin--dialog#open` announces the opening (`admin--dialog:opening`, on
// `document`, before the dialog is shown) with the trigger; this controller
// reads the trigger and fills the dialog, the way `admin--new-record` does for
// the New page dialog.
//
// Merge: sets the title and the sentence, points the form at
// `POST /tags/:id/merge`, and resets the picker -- an `admin--chip-input`
// (`single`, no create) over the tag suggestions. Its `exclude` value is set
// per opening to the source's own name, so the tag being merged is never
// offered (`Tags::Merge` refuses it again on the server). "Merge tags" is
// disabled until the picker holds a tag; the picker's chip dispatches a
// bubbling `change` from its sentinel, which `targetChanged` reads.
//
// Delete: sets the title and the sentence and points its form at
// `DELETE /tags/:id`. The answer is a Turbo Stream that removes the row, which
// leaves the dialog open, so a submission's end closes it (`submitted`):
// - a success moves the focus to the next row's name (the previous one's for
//   the last row, the heading when none is left) -- the row that had it is
//   gone, and focus on <body> sends a keyboard user back to the top; and when
//   the last tag went, the screen is fetched again for its empty state;
// - a refusal (a 403, a tag someone else deleted) has no body to render: the
//   dialog would stay open over a button that does nothing, so it closes and
//   an error toast says the tag wasn't deleted.
//
// THE NAME IS READ LIVE. The row's `data-tag-*` were written when the list was
// rendered; a name renamed in place since (the row's own autosave) is not in
// them, and the dialog asked to delete "old" beside a row that says "new". So
// the name comes from the row's input as it stands, and the title, the
// sentence and the picker's exclusion are re-worded with it (the name appears
// in them in “curly quotes”, as the locale file wrote it).
//
// Everything reaches the DOM through `textContent` and attributes: a tag name
// is whatever an editor typed, never markup.
// The quotes the tag's name sits in inside the locale file's sentences
// (`admin.tags.dialogs.*`, config/locales/admin/tags.en.yml). They are what
// tells the name from the same letters inside a word; a language that quotes
// differently changes them there and here together.
const QUOTES = ["“", "”"]

export default class extends Controller {
  static targets = ["mergeForm", "mergeText", "mergeButton", "deleteForm", "deleteText"]
  static values = { mergeUrl: String, deleteUrl: String }

  opened(event) {
    const { dialog, trigger } = event.detail
    if (!this.element.contains(dialog) || !trigger) return

    if (dialog.id === "merge-tag-dialog") this.openMerge(dialog, trigger.dataset)
    else if (dialog.id === "delete-tag-dialog") this.openDelete(dialog, trigger.dataset)
  }

  openMerge(dialog, data) {
    const name = this.liveName(data)
    dialog.querySelector("[id$='-title']").textContent = this.reword(data.tagMergeTitle, data, name)
    this.mergeTextTarget.textContent = this.reword(data.tagMergeText, data, name)
    this.mergeFormTarget.action = this.mergeUrlValue.replace("__ID__", encodeURIComponent(data.tagId))

    const picker = this.mergeFormTarget.querySelector("[data-controller~='admin--chip-input']")
    picker.setAttribute("data-admin--chip-input-exclude-value", JSON.stringify([name]))
    // Through the picker's own controller, so an answer still on its way from
    // the last opening is dropped and `aria-expanded` follows the list.
    this.application.getControllerForElementAndIdentifier(picker, "admin--chip-input")?.reset()
    this.mergeButtonTarget.disabled = true
  }

  openDelete(dialog, data) {
    const name = this.liveName(data)
    dialog.querySelector("[id$='-title']").textContent = this.reword(data.tagDeleteTitle, data, name)
    this.deleteTextTarget.textContent = this.reword(data.tagDeleteText, data, name)
    this.deleteFormTarget.action = this.deleteUrlValue.replace("__ID__", encodeURIComponent(data.tagId))
    this.deleting = data.tagId
  }

  // See "THE NAME IS READ LIVE". An emptied or refused input is not a name:
  // the row's own stays.
  liveName(data) {
    const input = document.getElementById(`tag-${data.tagId}-name`)
    const typed = input && input.getAttribute("aria-invalid") !== "true" ? input.value.trim() : ""
    return typed || data.tagName
  }

  reword(text, data, name) {
    if (name === data.tagName) return text

    const [open, close] = QUOTES
    return text.split(`${open}${data.tagName}${close}`).join(`${open}${name}${close}`)
  }

  // Enabled once the picker holds a tag: its chips' hidden inputs carry the
  // name (`into`); the blank sentinel ahead of them does not count.
  targetChanged(event) {
    if (!event.target.closest("#merge-tag-form")) return
    const chosen = Array.from(this.mergeFormTarget.querySelectorAll("input[type=hidden][name=into]")).some((input) => input.value !== "")
    this.mergeButtonTarget.disabled = !chosen
  }

  submitted(event) {
    if (event.target !== this.deleteFormTarget) return
    const row = document.getElementById(`tag_${this.deleting}`)
    this.deleteFormTarget.closest("dialog")?.close()

    if (!event.detail?.success) return this.failed()

    // Chosen before the stream takes the row.
    const neighbour = row?.nextElementSibling || row?.previousElementSibling
    const next = neighbour?.querySelector("input[type=text]") || document.querySelector("#content h1")
    if (next && next.tabIndex < 0 && !next.hasAttribute("tabindex")) next.setAttribute("tabindex", "-1")
    // Once the stream has taken the row (Turbo reads the answer and applies
    // it a frame later; a timer, since a background tab runs no frames).
    const started = Date.now()
    const settle = () => {
      if (row?.isConnected && Date.now() - started < 2000) return setTimeout(settle, 30)
      next?.focus()
      // The last tag: the table is a header over nothing. The screen itself
      // knows its empty state.
      if (!document.querySelector(".admin-tags-table tbody tr")) Turbo.visit(location.href, { action: "replace" })
    }
    settle()
  }

  // The server's own error toast markup (`#toast-error-template` in the
  // layout), one per cause.
  failed() {
    const toast = document.getElementById("toast-error-template")?.content.firstElementChild?.cloneNode(true)
    const region = document.getElementById("toasts")
    if (!toast || !region) return
    toast.id = "toast-tag-delete"
    toast.querySelector("span").textContent = messages(this.element).t("tags.dialogs.delete_failed")
    document.getElementById(toast.id)?.remove()
    region.append(toast)
  }
}
