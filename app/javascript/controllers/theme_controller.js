import { Controller } from "@hotwired/stimulus"

// The theme: CS Studio's three-way switch (Admin::Ui::ThemeSwitchComponent)
// and the public footer's two-state toggle (layouts/public/_theme_toggle).
// `choice` is what the person picked (light | dark | auto) and lives in
// localStorage and on <html data-theme-choice>; `data-theme` is what it
// resolves to and is what the token CSS keys every colour off.
// shared/_theme_head does the same resolution before first paint, and
// `connect` only marks the checked button (and makes it the Tab stop), so the first paint never fades.
//
// A change after it (a press, a toggle, the OS changing while the choice is
// Auto) goes through `apply`, which cross-fades the page with a view
// transition. The choice and `aria-checked` change first and at once, so the
// pressed button is checked, and keeps the focus, before the fade begins;
// only `data-theme` is written inside the transition. The change is direct
// where the API is missing, where it throws (a hidden document) and under
// `prefers-reduced-motion: reduce`. `resolve` reads the choice on <html> when
// it runs, not the one `apply` was called with: a transition's callback runs
// late, and still runs when a newer press skips its transition, so the last
// choice is what every callback writes.
//
// The switch is an ARIA radio group: one Tab stop, the checked choice
// (`sync` keeps a roving `tabindex`, 0 on it and -1 on the others), and
// Left/Up and Right/Down choose the previous or next choice, wrapping at the
// ends. An arrow moves the focus before it chooses, so the newly checked
// choice already holds the focus when the fade starts, as a press does. Space
// and Enter on the focused choice are the button's own click (`choose`).
//
// The fade's length and easing are `--cs-theme-fade-*` in content-spiel.css,
// read under CS Studio's surface only. The public toggle calls the same
// transition and gets the browser's default cross-fade, since the theme's
// stylesheet carries no such rule.
export default class extends Controller {
  static targets = ["choice"]

  connect() {
    this.media = window.matchMedia("(prefers-color-scheme: dark)")
    this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.onSystemChange = () => { if (this.choice === "auto") this.apply("auto") }
    this.media.addEventListener("change", this.onSystemChange)
    this.sync()
  }

  disconnect() {
    this.media.removeEventListener("change", this.onSystemChange)
  }

  choose({ params }) {
    this.pick(params.choice)
  }

  previous(event) {
    this.step(event, -1)
  }

  next(event) {
    this.step(event, 1)
  }

  // The arrows' default would scroll the page (Up, Down) under the switch.
  step(event, offset) {
    event.preventDefault()
    const choices = this.choiceTargets
    const index = choices.indexOf(event.currentTarget)
    const target = choices[(index + offset + choices.length) % choices.length]
    target.focus()
    this.pick(target.dataset.themeChoiceParam)
  }

  pick(value) {
    const choice = ["light", "dark", "auto"].includes(value) ? value : "auto"
    try { localStorage.setItem("cs-theme", choice) } catch (e) {}
    this.apply(choice)
  }

  // The footer's toggle has no Auto: it flips the theme the current choice
  // resolves to and stores that as an explicit choice. It reads the choice,
  // not `data-theme`, which keeps the old theme until a fade's callback runs.
  toggle() {
    const next = this.resolved(this.choice) === "dark" ? "light" : "dark"
    try { localStorage.setItem("cs-theme", next) } catch (e) {}
    this.apply(next)
  }

  apply(choice) {
    document.documentElement.dataset.themeChoice = choice
    this.sync()
    if (typeof document.startViewTransition !== "function" || this.reducedMotion.matches) return this.resolve()

    try {
      // A transition skipped by a newer one rejects `ready`; its callback still runs.
      document.startViewTransition(() => this.resolve()).ready?.catch(() => {})
    } catch (e) {
      this.resolve()
    }
  }

  resolve() {
    document.documentElement.dataset.theme = this.resolved(this.choice)
  }

  resolved(choice) {
    return choice === "auto" ? (this.media.matches ? "dark" : "light") : choice
  }

  sync() {
    this.choiceTargets.forEach((button) => {
      const checked = button.dataset.themeChoiceParam === this.choice
      button.setAttribute("aria-checked", String(checked))
      button.tabIndex = checked ? 0 : -1
    })
  }

  get choice() {
    return document.documentElement.dataset.themeChoice || "auto"
  }
}
