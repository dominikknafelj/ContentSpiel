import { Controller } from "@hotwired/stimulus"
import { draftKey } from "controllers/admin/note_composer_controller"

// "Unsaved edit" on a message (the handoff's decision 27), on the viewer's own
// messages as `Admin::NotesScreen::MessageComponent` draws them.
//
// The text of an edit that is left without saving -- Edit or Delete on another
// message, "All notes", the drawer closed, a reload -- stays in this tab as
// the edit form's draft (`admin--note-composer`, under
// `cs-note-draft:<user id>:message-<id>`). While such a draft exists and the
// message's edit form is closed, the message says so: the server draws the
// words hidden (`note`), and this shows them when the draft is there. It is
// decided here, from `sessionStorage`, each time a message is drawn -- on
// load, after a live refresh, after the answer to one of the thread's own
// buttons -- so the server is never asked and never knows.
//
// Cancel (a link beside the edit form) gives the edit up: `forget` drops the
// draft before the thread is drawn again without the form. Saving drops it
// in the composer.
//
// `sessionStorage` can be absent or blocked: then there is no draft and no
// note, as for the composer.
export default class extends Controller {
  static targets = [ "note" ]
  static values = { key: String, user: String }

  noteTargetConnected(note) {
    note.hidden = !this.drafted
  }

  forget() {
    try {
      window.sessionStorage.removeItem(draftKey(this.userValue, this.keyValue))
    } catch {
      // Nothing to forget.
    }
  }

  get drafted() {
    try {
      const draft = JSON.parse(window.sessionStorage.getItem(draftKey(this.userValue, this.keyValue)) || "null")
      return typeof draft?.body === "string" && draft.body !== ""
    } catch {
      return false
    }
  }
}
