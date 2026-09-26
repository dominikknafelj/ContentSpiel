import { Controller } from "@hotwired/stimulus"

// Flips data-theme on <html> (the token CSS keys every colour off it) and
// remembers the choice; app/views/shared/_theme_head.html.erb re-applies it
// before first paint on the next full page load.
export default class extends Controller {
  static targets = ["label"]

  connect() {
    this.render()
  }

  toggle() {
    const next = this.current === "dark" ? "light" : "dark"
    document.documentElement.dataset.theme = next
    try { localStorage.setItem("cs-theme", next) } catch (e) {}
    this.render()
  }

  get current() {
    return document.documentElement.dataset.theme
  }

  render() {
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = this.current === "dark" ? "Light mode" : "Dark mode"
    }
  }
}
