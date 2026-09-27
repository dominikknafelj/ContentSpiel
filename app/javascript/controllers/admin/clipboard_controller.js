import { Controller } from "@hotwired/stimulus"

// The record header's "Copy" button next to the public URL (cs-studio spec
// §5.1) -- `navigator.clipboard` needs no server round trip, so this stays
// its own tiny controller rather than folding into `admin--autosave` (which
// this button has nothing to do with) or `admin--tree`. `urlValue` is the
// URL to copy, read once from the value the header already computed
// server-side (`PublicSite::Urls`) -- this never builds a URL of its own.
export default class extends Controller {
  static values = { url: String }

  async copy(event) {
    event?.preventDefault()

    try {
      await navigator.clipboard.writeText(this.urlValue)
      this.flash("Copied")
    } catch (error) {
      this.flash("Copy failed")
    }
  }

  // Swaps the button's own label for a moment rather than a separate status
  // element -- there's nothing else on this button worth preserving mid-flash,
  // and it's gone before an editor could tab away and lose the original text.
  flash(message) {
    const original = this.element.textContent
    this.element.textContent = message
    setTimeout(() => { this.element.textContent = original }, 1500)
  }
}
