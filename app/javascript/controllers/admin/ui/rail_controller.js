import { Controller } from "@hotwired/stimulus"

// An editor's rail (`.admin-rail-grid`), on the grid: its tabs
// (`Admin::Ui::RailTabsComponent`) choose which of its panels
// (`Admin::Ui::RailPanelComponent`) is shown where the rail docks.
//
// WHAT IT READS. Whether the rail is docked is the stylesheet's answer: the
// editor area's container query sets `--admin-rail-docked` to 1 on the grid,
// and this controller only reads the computed property. It never measures a
// width and never decides a threshold of its own.
//
// WHAT IT WRITES. `data-current` on the current panel, `aria-selected` and
// the roving `tabindex` on the tabs (the tabs' look keys on `aria-selected`,
// so no class is edited), and `data-rail-docked` on the grid, present while
// docked. The docked state is written on connect and again from a
// `ResizeObserver` on the grid, whose box changes whenever the rail docks or
// undocks; a change dispatches `admin--ui--rail:docked` with `{ docked }`.
//
// THE CURRENT TAB IS THIS CONTROLLER'S. The server draws one current tab
// and panel; from connect on, `currentValue` is the state, and a tab or
// panel that is drawn again (a live merge replacing a form, a stream
// replacing a tab) takes it as it connects, not the server's default, so the
// rail never shows two current panels or none. It is kept for the document
// only: nothing is stored or remembered.
//
// THE EVENTS ARE THE ONLY WAY A FEATURE OPENS A PANEL. A feature names no
// tab and no panel of the rail's: it dispatches, from an element inside a
// panel, `admin--ui--rail:reveal` (show the panel that holds it, remembering
// the one that was current) or `admin--ui--rail:conceal` (go back to that
// one, if the panel that holds it is current). The grid hears both:
//   data-action="admin--ui--rail:reveal->admin--ui--rail#reveal
//                admin--ui--rail:conceal->admin--ui--rail#conceal"
// Every selection dispatches `admin--ui--rail:shown` with `{ key }` on the
// panel it shows.
//
// PREVIOUS IS THE TAB LAST LEFT. Every selection that changes the tab, the
// person's own (a press, a key) and a reveal alike, remembers the tab it
// leaves; so concealing a panel goes back to where the person was before it
// became current ("close Notes returns to where I was"), never to an older
// tab. A conceal forgets it.
//
// A current key that names no panel and no tab (the server's, or one whose
// tab was taken away) is the first tab's, so one tab is always in the tab
// order and one panel current.
//
// WHAT GOES WHERE (the grid's own stylesheet places it): the tabs and the
// panels in the rail's column; the blocks column is the element marked
// `.admin-rail__main`, and nothing else is placed.
//
// Tabs follow ARIA's tabs with automatic activation: Left and Right move to
// the neighbouring tab (round the ends), Home and End to the first and last,
// and the focused tab is selected.
export default class extends Controller {
  static targets = [ "tab", "panel" ]
  static values = { current: String }

  connect() {
    if (!this.currentValue) this.currentValue = this.drawnKey()
    this.apply()
    this.measure()
    this.observer = new ResizeObserver(() => this.measure())
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
    this.observer = null
    this.wasDocked = undefined
  }

  // Before `connect`, Stimulus connects the targets that are there already;
  // `connect` applies the state to those.
  tabTargetConnected() {
    if (this.currentValue) this.apply()
  }

  panelTargetConnected() {
    if (this.currentValue) this.apply()
  }

  select(event) {
    this.show(event.currentTarget.dataset.key)
  }

  key(event) {
    const tabs = this.tabTargets
    const index = tabs.indexOf(event.currentTarget)
    const target = {
      ArrowRight: tabs[(index + 1) % tabs.length],
      ArrowLeft: tabs[(index - 1 + tabs.length) % tabs.length],
      Home: tabs[0],
      End: tabs[tabs.length - 1]
    }[event.key]
    if (index < 0 || !target) return
    event.preventDefault()
    target.focus()
    this.show(target.dataset.key)
  }

  reveal(event) {
    const panel = this.panelHolding(event.target)
    if (!panel) return
    this.show(panel.dataset.key)
  }

  conceal(event) {
    const panel = this.panelHolding(event.target)
    if (!panel || panel.dataset.key !== this.currentValue) return
    const previous = this.panelTargets.some((other) => other.dataset.key === this.previous) ? this.previous : this.drawnKey(panel.dataset.key)
    if (previous && previous !== this.currentValue) this.show(previous)
    this.previous = null
  }

  get docked() {
    return getComputedStyle(this.element).getPropertyValue("--admin-rail-docked").trim() === "1"
  }

  // private

  show(key) {
    if (key !== this.currentValue) this.previous = this.currentValue
    this.currentValue = key
    this.apply()
    const panel = this.panelTargets.find((candidate) => candidate.dataset.key === key)
    if (panel) this.dispatch("shown", { target: panel, detail: { key } })
  }

  apply() {
    const keyed = [ ...this.tabTargets, ...this.panelTargets ]
    if (!keyed.some((element) => element.dataset.key === this.currentValue)) this.currentValue = keyed[0]?.dataset.key || ""
    const key = this.currentValue
    this.tabTargets.forEach((tab) => {
      const selected = tab.dataset.key === key
      tab.setAttribute("aria-selected", String(selected))
      tab.tabIndex = selected ? 0 : -1
    })
    this.panelTargets.forEach((panel) => panel.toggleAttribute("data-current", panel.dataset.key === key))
  }

  measure() {
    const docked = this.docked
    if (docked === this.wasDocked) return
    const changed = this.wasDocked !== undefined
    this.wasDocked = docked
    this.element.toggleAttribute("data-rail-docked", docked)
    if (changed) this.dispatch("docked", { detail: { docked } })
  }

  // The key the server drew current, else the first tab's or panel's;
  // `except` is passed over (a panel being concealed).
  drawnKey(except = null) {
    const drawn = this.panelTargets.find((panel) => panel.hasAttribute("data-current") && panel.dataset.key !== except)
    const first = [ ...this.tabTargets, ...this.panelTargets ].find((element) => element.dataset.key !== except)
    return (drawn || first)?.dataset.key || ""
  }

  panelHolding(element) {
    return element instanceof Element ? this.panelTargets.find((panel) => panel.contains(element)) : undefined
  }
}
