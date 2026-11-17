import { Controller } from "@hotwired/stimulus"
import { jumpTo } from "controllers/admin/shell/fragment_links_controller"

// Settings' in-page nav marks the section in view (Admin::SettingsScreen::NavComponent).
//
// What decides "current": the LAST heading whose top is above 40% of the
// window; on a page that scrolls and is scrolled to its end, the last section
// (a short last card never gets its heading that high); on a page that does
// not scroll, the first. A heading is found by the link's own fragment, so
// the markup keeps one source for the ids.
//
// The attribute is the whole state and the stylesheet draws it from there.
// Turbo's snapshot would keep what is written here, so `reset` takes it back at
// turbo:before-cache, and the page that is shown decides again at connect.
// Listeners are the window's and are removed in disconnect.
//
// Below 640px the links are hidden and a select stands for them: `choose`
// makes the jump a link makes (`admin--shell--fragment-links`' `jumpTo`: the
// heading focused and in view, no history entry, no visit, so no leave
// guard). The select keeps the section last chosen: the jump centres the
// heading, which the 40% rule above can still count as the section before.
export default class extends Controller {
  static targets = [ "link", "select" ]

  connect() {
    this.headings = this.linkTargets.map((link) => document.getElementById(link.hash.slice(1)))
    this.listener = () => this.mark()
    window.addEventListener("scroll", this.listener, { passive: true })
    window.addEventListener("resize", this.listener)
    this.mark()
  }

  disconnect() {
    window.removeEventListener("scroll", this.listener)
    window.removeEventListener("resize", this.listener)
  }

  choose() {
    const heading = document.getElementById(this.selectTarget.value)
    if (heading) jumpTo(heading)
  }

  reset() {
    this.linkTargets.forEach((link) => link.removeAttribute("aria-current"))
  }

  mark() {
    const root = document.documentElement
    const scrolls = root.scrollHeight > window.innerHeight + 2
    const atEnd = scrolls && window.scrollY + window.innerHeight >= root.scrollHeight - 2
    let current = 0
    if (atEnd) current = this.headings.length - 1
    else if (scrolls) {
      this.headings.forEach((heading, index) => {
        if (heading && heading.getBoundingClientRect().top <= window.innerHeight * 0.4) current = index
      })
    }
    this.linkTargets.forEach((link, index) => {
      if (index === current) link.setAttribute("aria-current", "true")
      else link.removeAttribute("aria-current")
    })
  }
}
