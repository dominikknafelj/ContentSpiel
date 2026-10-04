import { Controller } from "@hotwired/stimulus"

// Select-then-use for the media picker (round 3, Task 9, D14), on the same
// `<dialog>` as `admin--media-picker` (`Media::PickerComponent`).
//
// - A click on a tile SELECTS it (one at a time): `aria-pressed` draws the accent
//   ring and the footer says "1 selected" -- announced, it is a live region --
//   with the title after it for a screen reader ("say what you chose").
// - **Use image** confirms; so does a double click (which also selects), and so
//   does Enter on a tile that is already selected. A tile is a real `<button>`, so
//   Tab reaches every one and Enter or Space selects it with no code of ours; the
//   keydown below only adds the second Enter.
// - Confirming dispatches `admin--media-select:chosen` with the asset's payload
//   (`{ id, url, title, alt, caption }`); the picker closes and answers its opener.
//
// The selection is the payload held HERE, not a mark in the DOM: searching or
// choosing a segment replaces the grid inside its frame, and the choice has to
// survive that (a selected image the new search no longer lists is still
// selected, still usable). After each frame render `reapply` draws the ring on
// whichever tile is that image again. Nothing here is in a form: the dialog is
// outside `#content` and every autosave form, and the tiles are plain buttons.
export default class extends Controller {
  static targets = [ "status", "use" ]

  static texts = { none: "No image selected", selected: "1 selected" }

  connect() {
    this.selected = null
  }

  select(event) {
    this.setSelected(event.params.asset)
  }

  // Double click: select (already done by its two clicks, but a script's lone
  // `dblclick` is the same) and confirm.
  choose(event) {
    this.setSelected(event.params.asset)
    this.confirm()
  }

  // Enter on a tile that is already selected confirms. The first Enter falls
  // through to the button's own click, which selects.
  key(event) {
    if (event.key !== "Enter" || event.currentTarget.getAttribute("aria-pressed") !== "true") return

    event.preventDefault()
    this.confirm()
  }

  confirm() {
    if (this.selected) this.dispatch("chosen", { detail: this.selected })
  }

  // The picker opened afresh: nothing is chosen yet.
  reset() {
    this.setSelected(null)
  }

  // A finished upload: the picker selects the first one of a batch.
  selectUploaded(event) {
    this.setSelected(event.detail?.payload)
  }

  // The grid frame (not an upload tile's own events) was rendered or navigated.
  reapply(event) {
    if (event.target?.id !== "media-picker-grid") return

    this.mark()
  }

  setSelected(payload) {
    this.selected = payload && Number.isInteger(payload.id) ? payload : null
    this.mark()
    this.say()
  }

  mark() {
    const id = this.selected ? String(this.selected.id) : null
    this.element.querySelectorAll("[data-asset-id]").forEach((tile) => {
      tile.setAttribute("aria-pressed", tile.dataset.assetId === id ? "true" : "false")
    })
  }

  say() {
    if (this.hasUseTarget) this.useTarget.disabled = !this.selected
    if (!this.hasStatusTarget) return

    if (!this.selected) {
      this.statusTarget.textContent = this.constructor.texts.none
      return
    }

    this.statusTarget.textContent = this.constructor.texts.selected
    const title = document.createElement("span")
    title.className = "sr-only"
    title.textContent = `: ${this.selected.title}`
    this.statusTarget.append(title)
  }
}
