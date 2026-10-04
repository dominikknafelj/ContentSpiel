import { Controller } from "@hotwired/stimulus"
import { holdTurboRequest } from "autosave/queue"

// On a form in an editor's header whose submission changes the record (Publish,
// Unpublish, Schedule, Remove schedule, Move to trash): the submission waits
// for the page's write queue (`autosave/queue.js`) to drain first. An edit
// still queued behind another form's request would otherwise lose the race:
// the action commits first and redirects, and the edit is then sent on the old
// base -- refused as "changed elsewhere", its text dropped. Waiting means a
// pending edit is saved first and the action then runs on the fresh state. An
// edit still inside its debounce is flushed first (`autosave:flush`), so it is
// queued ahead of the action.
//
// Only these forms carry the controller, so nothing outside an editor (sign
// out, the palette, other screens) is ever held. Release on abort, error or a
// disconnected form is `holdTurboRequest`'s.
export default class extends Controller {
  hold(event) {
    if (String(event.detail.fetchOptions.method).toUpperCase() === "GET") return

    document.dispatchEvent(new CustomEvent("autosave:flush"))
    holdTurboRequest(event, { untilNavigation: true })
  }
}
