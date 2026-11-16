import { Controller } from "@hotwired/stimulus"
import { holdTurboRequest } from "saving/queue"
import { messages } from "i18n/messages"

// The Move to… dialog of the Media screen (`Admin::MediaLibrary::
// MoveDialogComponent`), on the `<dialog>` itself.
//
// ONE DIALOG, LOADED AS IT OPENS. The dialog is drawn once, a shell with an
// empty frame, and every trigger opens it by its id (`admin--ui--dialog#open`,
// which announces the opening on `document` with the trigger, before the
// dialog is shown). The trigger says what moves, as this controller's params
// (written by `MoveDialogComponent.images_trigger` and `.folder_trigger`):
// `asset-ids` (comma-joined) or `folder-id`, and `title` (the one image's
// title, or the folder's name). From them the title is worded ("Move 3
// images", "Move “beach.jpg”" (one image with no title: "Move 1 image"),
// "Move “Client A”", the server's words in
// `data-messages`, a name reaching the page only through `textContent`) and
// the frame is pointed at the list for that subject (`GET /media/move/new`),
// with the place and the search the content frame shows (`#content`'s
// `data-media-place` and `data-media-query`), which the move's answer keeps.
// Every opening empties the frame and loads it afresh, so nothing an earlier
// opening chose, typed or was refused is ever shown.
//
// MOVE HERE (the footer's, tied to the list's form by `form=`) is disabled
// until a place is chosen: at each opening, and whenever the list is drawn
// again. A list that arrives puts the focus on "Find a folder", or, when it
// carries a refusal, on the refusal's notice.
//
// FIND A FOLDER hides the rows whose name does not hold what is typed (case
// ignored), and a chosen row it hides is chosen no more (Move here is
// disabled again). It stands outside the form, so Enter in it sends nothing.
//
// SENT THROUGH THE WRITE QUEUE. The list's form is a Turbo form; its request
// is held until the screen's other writes have answered (`holdTurboRequest`),
// as every write of a CS Studio screen is
// (docs/reference/save-rule-and-write-queue.md). The frame's own load is a
// read and is not held.
//
// THE ANSWER. A success closes the dialog (the answer's streams move the
// tiles, the counts, the panel's Folder fact and the column). A refusal
// answers with the list drawn again, the notice on top
// (`Admin::Answers::MoveRefused`): the dialog stays open, and the focus goes
// to the notice as the new list connects. With no answer at all (offline) it
// stays as it was.
const PARAM = "data-admin--media--move-"

export default class extends Controller {
  static targets = ["frame", "submit", "choices"]
  static values = { url: String }

  opening(event) {
    const { dialog, trigger } = event.detail || {}
    if (dialog !== this.element || !trigger) return

    const param = (name) => trigger.getAttribute(`${PARAM}${name}-param`) || ""
    const folderId = param("folder-id")
    const ids = param("asset-ids").split(",").filter(Boolean)
    const title = param("title")
    const words = messages(this.element)

    // One image is named by its title; with none (a blank title) it is
    // counted, as several are, never "Move “”".
    let heading
    if (folderId) heading = words.t("components.media_library.move_dialog.title.folder", { name: title })
    else if (ids.length === 1 && title.trim() !== "") heading = words.t("components.media_library.move_dialog.title.image", { title })
    else heading = words.t("components.media_library.move_dialog.title.images", { count: ids.length })
    document.getElementById(`${this.element.id}-title`).textContent = heading
    this.submitTarget.disabled = true
    this.load(folderId, ids)
  }

  load(folderId, ids) {
    const url = new URL(this.urlValue, window.location.origin)
    if (folderId) url.searchParams.set("folder_id", folderId)
    else ids.forEach((id) => url.searchParams.append("asset_ids[]", id))

    const library = document.querySelector("#content [data-media-place]")
    url.searchParams.set("place", library?.dataset.mediaPlace ?? "")
    let query = {}
    try {
      query = JSON.parse(library?.dataset.mediaQuery || "{}") || {}
    } catch {
      query = {}
    }
    for (const name of ["q", "filter"]) {
      if (typeof query[name] === "string" && query[name] !== "") url.searchParams.set(name, query[name])
    }

    this.frameTarget.removeAttribute("src")
    this.frameTarget.replaceChildren()
    this.frameTarget.setAttribute("src", url.toString())
  }

  // The list arrived (the frame's load, or a refusal's redraw).
  choicesTargetConnected(choices) {
    this.submitTarget.disabled = !choices.querySelector("input[type=radio]:checked")
    if (!this.element.open) return

    const notice = choices.querySelector("[role=alert]")
    const find = choices.querySelector("input[type=search]")
    ;(notice || find)?.focus()
  }

  choose(event) {
    if (event.target.type === "radio" && event.target.checked) this.submitTarget.disabled = false
  }

  find(event) {
    const field = event.target
    if (field.type !== "search" || !this.hasChoicesTarget) return

    const typed = field.value.trim().toLowerCase()
    this.choicesTarget.querySelectorAll("[data-move-choice]").forEach((row) => {
      row.hidden = typed !== "" && !row.dataset.moveName.includes(typed)
      // A choice the find hides is no choice: Move here would send a place
      // the person can no longer see.
      const radio = row.querySelector("input[type=radio]")
      if (row.hidden && radio?.checked) radio.checked = false
    })
    this.submitTarget.disabled = !this.choicesTarget.querySelector("input[type=radio]:checked")
  }

  send(event) {
    if (event.target instanceof HTMLFormElement) holdTurboRequest(event)
  }

  sent(event) {
    if (event.target instanceof HTMLFormElement && event.detail.success && this.element.open) this.element.close()
  }
}
