import { Controller } from "@hotwired/stimulus"
import { holdTurboRequest } from "saving/queue"
import { messages } from "i18n/messages"

// The folder dialogs of the Media screen: on the New folder / Rename folder
// dialog (`Admin::MediaLibrary::FolderDialogComponent`), and on the delete
// confirm's form (`DeleteFolderDialogComponent`), which uses `send` and `sent`
// alone.
//
// ONE DIALOG, SET UP AS IT OPENS. The dialog is drawn once and every trigger
// opens it by its id (`admin--ui--dialog#open`, which announces the opening
// on `document` with the trigger, before the dialog is shown). The trigger
// says what to set it up for, as attributes of this controller's params:
// - a create: `parent-id` (empty for the top) and `parent-path` ("Clients /
//   Client A", empty for the top);
// - a rename: `folder-id`, `folder-name` and `parent-path` (where the folder
//   stands).
// So the title, the button, the form's address and method, the parent sent,
// the name, the line saying where and the place and search the screen shows
// (from `#content`'s `data-media-place` and `data-media-query`, which the
// answer's address keeps) are written again at each opening, and the last
// refusal's sentences are taken away. Every opening writes all of them, so
// nothing an earlier opening, a refusal's redrawn form or a restored
// snapshot left in the dialog is ever shown stale. A rename sends no parent at all (the
// field is disabled), so it never moves the folder. The words are the
// server's (`data-messages`), and a name reaches the page only through
// `value` and `textContent`.
//
// SENT THROUGH THE WRITE QUEUE. The form is a Turbo form; its request is
// held until the screen's other writes have answered (`holdTurboRequest`),
// as every write of a CS Studio screen is (docs/reference/save-rule-and-write-queue.md).
//
// THE ANSWER.
// - A success closes the dialog. The answer replaces the Folders column's
//   part, which names the place to go to (`admin--media--folders`): the new
//   folder, the renamed one, the deleted one's parent.
// - A refused create or rename answers with the whole form drawn again
//   (`Admin::Answers::FolderRefused`): the name as typed and the sentences
//   under it. The dialog stays open and, as the new field connects, the
//   focus goes back into it with the caret at the end (`nameTargetConnected`):
//   the old field, which had it, is gone.
// - A refused delete answers with an error toast; the confirm closes, since
//   pressing it again would say the same. With no answer at all (offline) it
//   stays open.
const PARAM = "data-admin--media--folder-dialog-"

export default class extends Controller {
  static targets = ["form", "method", "parent", "place", "q", "filter", "name", "errors", "where", "whereText", "submit"]
  static values = { createUrl: String, updateUrl: String }

  opening(event) {
    const { dialog, trigger } = event.detail || {}
    if (dialog !== this.element || !trigger || !this.hasFormTarget) return

    const param = (name) => trigger.getAttribute(`${PARAM}${name}-param`) || ""
    const folderId = param("folder-id")
    const rename = folderId !== ""
    const words = messages(this.element)

    document.getElementById(`${this.element.id}-title`).textContent = rename
      ? words.t("components.media_library.folder_dialog.rename_title")
      : words.t("components.media_library.folder_dialog.new_title")
    this.submitTarget.textContent = rename
      ? words.t("components.media_library.folder_dialog.rename")
      : words.t("components.media_library.folder_dialog.create")

    this.formTarget.action = rename ? this.updateUrlValue.replace("__ID__", encodeURIComponent(folderId)) : this.createUrlValue
    this.methodTarget.value = rename ? "patch" : "post"
    this.parentTarget.disabled = rename
    this.parentTarget.value = rename ? "" : param("parent-id")
    this.nameTarget.value = rename ? param("folder-name") : ""

    const path = param("parent-path")
    this.whereTextTarget.textContent = path
      ? words.t("components.media_library.folder_dialog.inside", { path })
      : words.t("components.media_library.folder_dialog.top")
    this.whereTarget.hidden = false

    this.errorsTarget.replaceChildren()
    this.nameTarget.removeAttribute("aria-invalid")
    this.nameTarget.setAttribute("aria-describedby", this.whereTarget.id)
    this.keepShown()

    // `admin--ui--dialog` focuses the field once the dialog shows, after this
    // event; a rename's name is then selected, to be typed over.
    if (rename) queueMicrotask(() => { if (this.element.open) this.nameTarget.select() })
  }

  // The place and the search the content frame shows.
  keepShown() {
    const library = document.querySelector("#content [data-media-place]")
    this.placeTarget.value = library?.dataset.mediaPlace ?? ""
    let query = {}
    try {
      query = JSON.parse(library?.dataset.mediaQuery || "{}") || {}
    } catch {
      query = {}
    }
    this.qTarget.value = typeof query.q === "string" ? query.q : ""
    this.filterTarget.value = typeof query.filter === "string" ? query.filter : ""
  }

  send(event) {
    holdTurboRequest(event)
  }

  sent(event) {
    const dialog = this.element.closest("dialog")
    if (!dialog?.open) return

    if (event.detail.success) dialog.close()
    else if (!this.hasNameTarget && event.detail.fetchResponse) dialog.close()
  }

  nameTargetConnected(field) {
    if (!this.element.open || field.getAttribute("aria-invalid") !== "true") return

    field.focus()
    field.setSelectionRange(field.value.length, field.value.length)
  }
}
