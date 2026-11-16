import { Controller } from "@hotwired/stimulus"

// Settings › Post types: what a switch's description says to a screen reader
// (Admin::SettingsScreen::PostTypesCardComponent).
//
// The look needs no script: a row with posts draws its "leaving" or
// "returning" line `hidden`, and two `:has()` rules in
// content-spiel.tailwind.css show it while the switch differs from the stored
// state (`data-stored`). The server names only the type's description in the
// switch's `aria-describedby`, because an element named there is read even
// while it is hidden. This adds the row's line to the switch's description
// while the stylesheet shows it, and only then, so a screen reader hears the
// unsaved consequence the eye sees, and nothing that is not shown.
//
// The line's state is read from the stylesheet (is it drawn?), never decided
// here a second time. What it writes, the switches' `aria-describedby`, it
// takes back to the server's at disconnect and at turbo:before-cache, so
// Turbo's snapshot keeps the server's markup.
export default class extends Controller {
  static targets = [ "switch" ]

  connect() {
    this.servers = new Map()
    this.switchTargets.forEach((input) => this.describe(input))
  }

  disconnect() { this.reset() }

  switchTargetDisconnected(input) {
    this.restore(input)
    this.servers?.delete(input)
  }

  update({ target }) {
    if (this.switchTargets.includes(target)) this.describe(target)
  }

  reset() {
    this.switchTargets.forEach((input) => this.restore(input))
    this.servers = new Map()
  }

  describe(input) {
    if (!this.servers.has(input)) this.servers.set(input, input.getAttribute("aria-describedby"))
    const line = document.getElementById(`${input.id}-line`)
    const shown = line && getComputedStyle(line).display !== "none"
    const ids = [ this.servers.get(input), shown ? line.id : null ].filter(Boolean)
    if (ids.length) input.setAttribute("aria-describedby", ids.join(" "))
    else input.removeAttribute("aria-describedby")
  }

  restore(input) {
    if (!this.servers?.has(input)) return
    const server = this.servers.get(input)
    if (server === null) input.removeAttribute("aria-describedby")
    else input.setAttribute("aria-describedby", server)
  }
}
