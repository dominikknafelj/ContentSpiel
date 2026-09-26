import { Controller } from "@hotwired/stimulus"

// Flips data-theme on <html> (the token CSS keys every colour off it) and
// remembers the choice; app/views/shared/_theme_head.html.erb re-applies it
// before first paint on the next full page load. The button's label is
// CSS-only (dark:/hidden variants in shared/_theme_toggle.html.erb), so it's
// already correct before this controller ever connects.
export default class extends Controller {
  toggle() {
    const next = this.current === "dark" ? "light" : "dark"
    document.documentElement.dataset.theme = next
    try { localStorage.setItem("cs-theme", next) } catch (e) {}
  }

  get current() {
    return document.documentElement.dataset.theme
  }
}
