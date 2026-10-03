import { Controller } from "@hotwired/stimulus"

// The three-way theme switch (Admin::ThemeSwitchComponent). `choice` is what
// the user picked (light | dark | auto) and lives in localStorage and on
// <html data-theme-choice>; `data-theme` is what it resolves to and is what
// the token CSS keys every colour off. shared/_theme_head does the same
// resolution before first paint; this controller handles clicks and, while
// the choice is "auto", follows the OS when it changes.
export default class extends Controller {
  static targets = ["choice"]

  connect() {
    this.media = window.matchMedia("(prefers-color-scheme: dark)")
    this.onSystemChange = () => { if (this.choice === "auto") this.apply("auto") }
    this.media.addEventListener("change", this.onSystemChange)
    this.sync()
  }

  disconnect() {
    this.media.removeEventListener("change", this.onSystemChange)
  }

  choose({ params }) {
    const choice = ["light", "dark", "auto"].includes(params.choice) ? params.choice : "auto"
    try { localStorage.setItem("cs-theme", choice) } catch (e) {}
    this.apply(choice)
  }

  apply(choice) {
    const root = document.documentElement
    root.dataset.themeChoice = choice
    root.dataset.theme = choice === "auto" ? (this.media.matches ? "dark" : "light") : choice
    this.sync()
  }

  sync() {
    this.choiceTargets.forEach((button) =>
      button.setAttribute("aria-checked", String(button.dataset.themeChoiceParam === this.choice)))
  }

  get choice() {
    return document.documentElement.dataset.themeChoice || "auto"
  }
}
