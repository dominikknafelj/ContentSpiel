import { Controller } from "@hotwired/stimulus"

// The desktop-notification row of the account screen (notes spec §6.4,
// handoff "Account switches"). The SETTING is the person's and is saved with
// the form; the PERMISSION is this browser's, and this shows which of three
// states it is in (`data-state` on the element says which):
// - `default`, not asked yet: an accent-toned info line with "Allow in this
//   browser", which asks at once, in the click, as browsers require;
// - `granted`: nothing;
// - `denied`: a warn-toned line saying where to change it, and no button --
//   a browser that was told no does not ask again.
// A browser without notifications (`unsupported`) shows nothing.
//
// ONLY WHILE THE SWITCH IS ON (handoff decision 14). The permission matters
// to someone who wants the notification: the lines follow the desktop switch
// as it stands in the page, saved or not, so turning it on shows the line at
// once and turning it off takes it away. `data-state` says the browser's
// state either way.
//
// The permission is changed outside this page too (the browser's site
// settings, another tab's prompt), so the state is read again whenever the
// window is looked at again (`render`, on `visibilitychange` and `focus`).
export default class extends Controller {
  static targets = [ "switch", "ask", "blocked" ]

  connect() {
    this.render()
  }

  async allow() {
    if (!("Notification" in window)) return
    try {
      // A promise in today's browsers; older ones take a callback and answer
      // nothing.
      await window.Notification.requestPermission(() => this.render())
    } catch {
      // Refused to ask at all (an insecure origin, a frame): the state says.
    }
    this.render()
  }

  render() {
    const state = "Notification" in window ? window.Notification.permission : "unsupported"
    this.element.dataset.state = state
    const wanted = this.switchTarget.checked
    this.askTarget.hidden = !wanted || state !== "default"
    this.blockedTarget.hidden = !wanted || state !== "denied"
  }
}
