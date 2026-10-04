import { Controller } from "@hotwired/stimulus"

// The Tags list's two dialogs, Merge and Delete (`app/views/admin/tags/index.html.erb`).
// There is ONE of each in the page, not one per row: a row's menu item opens
// the dialog with `data: dialog_trigger(id)` and carries that row's facts as
// `data-tag-*` attributes (the id, the name, the already-worded title and
// sentence -- `Admin::TagsHelper` writes them, so the copy is tested in Ruby).
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
// leaves the dialog open, so a successful submission closes it (`submitted`).
//
// Everything reaches the DOM through `textContent` and attributes: a tag name
// is whatever an editor typed, never markup.
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
    dialog.querySelector("[id$='-title']").textContent = data.tagMergeTitle
    this.mergeTextTarget.textContent = data.tagMergeText
    this.mergeFormTarget.action = this.mergeUrlValue.replace("__ID__", encodeURIComponent(data.tagId))

    const picker = this.mergeFormTarget.querySelector("[data-controller~='admin--chip-input']")
    picker.setAttribute("data-admin--chip-input-exclude-value", JSON.stringify([data.tagName]))
    picker.querySelector("[data-admin--chip-input-target='list']").replaceChildren()
    const input = picker.querySelector("[data-admin--chip-input-target='input']")
    input.value = ""
    picker.querySelector("[data-admin--chip-input-target='listbox']").hidden = true
    this.mergeButtonTarget.disabled = true
  }

  openDelete(dialog, data) {
    dialog.querySelector("[id$='-title']").textContent = data.tagDeleteTitle
    this.deleteTextTarget.textContent = data.tagDeleteText
    this.deleteFormTarget.action = this.deleteUrlValue.replace("__ID__", encodeURIComponent(data.tagId))
  }

  // Enabled once the picker holds a tag: its chips' hidden inputs carry the
  // name (`into`); the blank sentinel ahead of them does not count.
  targetChanged(event) {
    if (!event.target.closest("#merge-tag-form")) return
    const chosen = Array.from(this.mergeFormTarget.querySelectorAll("input[type=hidden][name=into]")).some((input) => input.value !== "")
    this.mergeButtonTarget.disabled = !chosen
  }

  submitted(event) {
    if (event.target !== this.deleteFormTarget || !event.detail?.success) return
    this.deleteFormTarget.closest("dialog")?.close()
  }
}
