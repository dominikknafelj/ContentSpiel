import { Controller } from "@hotwired/stimulus"

// The Site card's language tabs (round 3, Task 5; decision D6, handoff B32).
// Every enabled language's title and tagline are in the page at once, one
// `[data-language-panel]` per language; the tabs only choose which panel is
// shown. A tab is a `<button type="button">` (`Ui::LanguageTabsComponent`, `mode:
// :buttons`): nothing navigates, so Turbo never sees a visit and the save
// footer's leave guard never hears of it, and nothing here touches a form
// control's value -- a hidden panel's inputs are still the form's, still
// submitted, still counted exactly as before, so switching tabs never changes
// the footer's count.
//
// State is `hidden` on panels and `aria-selected` on tabs (the tabs' look keys
// on `aria-selected`, so no class is edited). The tabs are a roving tabindex:
// the selected one is in the tab order, Left/Right/Home/End move between them
// as the ARIA tabs pattern asks.
//
// Switching tells `admin--translation--translate` (`translate:changed`): its header counts
// the empty fields of the language that is visible, and which one that is
// just changed.
export default class extends Controller {
  static targets = [ "tab", "panel", "locale" ]
  static values = { current: String }

  connect() {
    this.show(this.currentValue || this.tabTargets[0]?.dataset.code, { announce: false })
  }

  select(event) {
    this.show(event.currentTarget.dataset.code)
  }

  // A link to a field on this screen (the error summary's) may name one inside
  // a hidden panel, which can't take focus: show its panel first. This listens
  // on `document`'s click, which runs before Turbo turns the click into the
  // `turbo:click` the save footer answers with its own focus jump.
  reveal(event) {
    const link = event.target instanceof Element && event.target.closest("a[href^='#']")
    if (!link || link.getAttribute("href").length < 2) return
    const target = document.getElementById(decodeURIComponent(link.getAttribute("href").slice(1)))
    const panel = target?.closest("[data-language-panel][hidden]")
    if (panel && this.element.contains(panel)) this.show(panel.dataset.languagePanel)
  }

  keydown(event) {
    const tabs = this.tabTargets
    const index = tabs.indexOf(event.currentTarget)
    const target = { ArrowRight: tabs[(index + 1) % tabs.length], ArrowLeft: tabs[(index - 1 + tabs.length) % tabs.length], Home: tabs[0], End: tabs[tabs.length - 1] }[event.key]
    if (!target) return
    event.preventDefault()
    target.focus()
    this.show(target.dataset.code)
  }

  show(code, { announce = true } = {}) {
    this.currentValue = code
    // The form's `locale` (a hidden field, not counted by the footer) follows
    // the tab, so a Save or a refused one comes back on the tab being looked at.
    if (this.hasLocaleTarget) this.localeTarget.value = code
    this.tabTargets.forEach((tab) => {
      const selected = tab.dataset.code === code
      tab.setAttribute("aria-selected", String(selected))
      tab.tabIndex = selected ? 0 : -1
    })
    this.panelTargets.forEach((panel) => { panel.hidden = panel.dataset.languagePanel !== code })
    if (announce) document.dispatchEvent(new CustomEvent("translate:changed"))
  }
}
