import { Controller } from "@hotwired/stimulus"

// The Tags list's rail (`app/views/admin/tags/index.html.erb`), on the grid
// that holds the rail and the list. A row's Details link targets the rail's
// frame (`tag-detail`, `Admin::TagsScreen::DetailComponent`); Turbo fetches
// and draws the detail, and this controller does the rest of a choice:
// - `chose` (`turbo:click` from a `[data-tag-details]` link): the chosen
//   mark, `aria-current` on the link and `data-selected` on its row, moves
//   to the pressed link's row, and the link is remembered;
// - `loaded` (`turbo:frame-load`): after a press, and only then, the focus
//   goes to the detail's heading, so a keyboard user is where the detail
//   begins and Tab goes on through its posts and buttons. A detail drawn by
//   a rename's stream is no load of the frame and moves nothing;
// - `close` (Close, and Escape anywhere in the rail): the frame loses its
//   `src` and holds the empty line again (a clone of the `empty`
//   template, which the server rendered from the same component), the
//   marks go, and the focus returns to the pressed link if it is still in
//   the page (a delete takes its row).
//
// It never reloads the frame: Turbo answers a GET of an address it
// prefetched in the last ten seconds with that prefetch, so a reload could
// draw a detail older than a rename. A rename's answer replaces the detail
// by stream instead, and a delete's puts the empty line back. The screen is
// `turbo-cache-control: no-cache`, so nothing this writes is kept in a
// snapshot.
export default class extends Controller {
  static targets = ["frame", "empty"]

  chose(event) {
    const link = event.target.closest?.("[data-tag-details]")
    if (!link || !this.element.contains(link)) return

    this.unmark()
    link.setAttribute("aria-current", "true")
    link.closest("tr")?.setAttribute("data-selected", "")
    this.pressed = link
    this.focusOnLoad = true
  }

  loaded(event) {
    if (event.target !== this.frameTarget || !this.focusOnLoad) return

    this.focusOnLoad = false
    this.frameTarget.querySelector("[data-tag-detail-heading]")?.focus()
  }

  close() {
    this.focusOnLoad = false
    this.frameTarget.removeAttribute("src")
    this.frameTarget.replaceChildren(this.emptyTarget.content.cloneNode(true))
    this.unmark()

    const link = this.pressed
    this.pressed = null
    if (link?.isConnected) link.focus()
  }

  unmark() {
    this.element.querySelectorAll("[data-tag-details][aria-current]").forEach((link) => {
      link.removeAttribute("aria-current")
      link.closest("tr")?.removeAttribute("data-selected")
    })
  }
}
