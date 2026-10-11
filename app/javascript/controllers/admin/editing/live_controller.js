// Task 5 fills this: the live editor's controller (listens, fetches, merges).
// Until then the one thing it must do is answer for its part: the server
// renders `data-live-part="waiting"`, which `live/state` (and
// `await_notes_live` in the system tests) waits on, so a controller that
// never says "answered" would hold every screen in "connecting". It says
// so through `settle`, which puts <body>'s answer together again.
//
// What Task 5's real controller must keep: its live part says "answered" only
// once its subscription has been confirmed or rejected, "waiting" until then
// and again whenever the connection drops, and it calls `settle` on connect,
// on disconnect and on each change of that word.
import { Controller } from "@hotwired/stimulus"
import { settle } from "live/state"

export default class extends Controller {
  connect() {
    this.element.setAttribute("data-live-part", "answered")
    settle(document.body)
  }

  disconnect() {
    settle(document.body)
  }
}
