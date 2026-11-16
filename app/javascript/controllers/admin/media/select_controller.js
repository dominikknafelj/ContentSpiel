import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"

// Select-then-use for the media picker, on the same
// `<dialog>` as `admin--media--picker` (`Admin::Ui::MediaPickerComponent`).
//
// - A click on a tile SELECTS it (one at a time): `aria-pressed` is what the stylesheet
//   draws the accent outline from (`.admin-tile`), and the footer says "1 selected" -- announced, it is a live region --
//   with the title after it for a screen reader ("say what you chose").
// - **Use image** confirms; so does a double click (which also selects), and so
//   does Enter on a tile that is already selected. A tile is a real `<button>`, so
//   Tab reaches every one and Enter or Space selects it with no code of ours; the
//   keydown below only adds the second Enter.
// - Confirming dispatches `admin--media--select:chosen` with the asset's payload
//   (`{ id, url, title, alt, caption }`); the picker closes and answers its opener.
//
// A MULTIPLE opening (the Gallery card's, the card StudioGallery, D4; the
// picker hands `multiple`, `max` and the ids already in the gallery in its
// `reset`): a press, Enter or Space TOGGLES a tile, and the choice is a list in
// the order chosen. Each chosen tile wears its place as the accent pill (the
// `orderMark` template, a picture: the tile's name ends ", chosen 2nd"), and
// unchoosing renumbers the rest. A tile already in the gallery wears "In the
// gallery" (`inGalleryMark`, its description), its thumbnail desaturated
// (`data-media-pick-present`), and is `aria-disabled`; when the list reaches
// `max` every other tile is `aria-disabled` too. A press on an
// `aria-disabled` tile does nothing. A double click is no confirm there, and
// its second click is not a second toggle (a click's `detail` counts it), so
// a quick double press chooses once. The primary reads "Add 3 images" and
// confirms the list: `chosen` carries `{ items: [payload, ...] }`.
//
// The selection is the payload held HERE, not a mark in the DOM: searching or
// choosing a segment replaces the grid inside its frame, and the choice has to
// survive that (a selected image the new search no longer lists is still
// selected, still usable). After each frame render `reapply` sets `aria-pressed`
// (and a multiple opening's marks) on whichever tiles are those images again.
// Nothing here is in a form: the dialog is outside `#content` and every
// autosave form, and the tiles are plain buttons.
// The footer's words are the dialog's `data-messages` (`components.ui.media_picker.*`).
export default class extends Controller {
  static targets = [ "status", "use", "orderMark", "inGalleryMark" ]

  connect() {
    this.selected = null
    this.multiple = false
    this.order = []
    this.max = 0
    this.total = 0
    this.present = new Set()
  }

  select(event) {
    if (!this.multiple) {
      this.setSelected(event.params.asset)
      return
    }
    if (event.detail > 1) return

    this.toggle(event.params.asset)
  }

  // Double click: select (already done by its two clicks, but a script's lone
  // `dblclick` is the same) and confirm.
  choose(event) {
    if (this.multiple) return

    this.setSelected(event.params.asset)
    this.confirm()
  }

  // Enter on a tile that is already selected confirms. The first Enter falls
  // through to the button's own click, which selects.
  key(event) {
    // Holding the key repeats keydown: one Enter confirms, not a stream of them.
    if (this.multiple || event.key !== "Enter" || event.repeat || event.currentTarget.getAttribute("aria-pressed") !== "true") return

    event.preventDefault()
    this.confirm()
  }

  confirm() {
    if (this.multiple) {
      if (this.order.length > 0) this.dispatch("chosen", { detail: { items: [ ...this.order ] } })
    } else if (this.selected) {
      this.dispatch("chosen", { detail: this.selected })
    }
  }

  // The picker opened afresh: nothing is chosen yet, and its opening says
  // whether several are (`multiple`, `max`, the ids `present` in the gallery).
  // `total`, what the gallery holds at most, is what it holds and what it
  // still takes.
  reset(event) {
    const opening = event?.detail || {}
    this.multiple = opening.multiple === true
    this.present = new Set((opening.present || []).map(String))
    this.max = this.multiple ? opening.max : 0
    this.total = this.multiple ? (opening.present || []).length + opening.max : 0
    this.order = []
    this.setSelected(null)
  }

  // A finished upload: the picker selects the first one of a batch (in a
  // multiple opening, adds it to the list while the gallery takes more).
  selectUploaded(event) {
    const payload = event.detail?.payload
    if (!this.multiple) {
      this.setSelected(payload)
      return
    }
    if (payload && Number.isInteger(payload.id) && !this.chosenAt(payload.id) && !this.present.has(String(payload.id)) && !this.full) this.toggle(payload)
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

  toggle(payload) {
    if (!payload || !Number.isInteger(payload.id) || this.present.has(String(payload.id))) return

    const at = this.order.findIndex((each) => each.id === payload.id)
    if (at >= 0) this.order.splice(at, 1)
    else if (!this.full) this.order.push(payload)
    else return

    this.mark()
    this.say()
  }

  // The 1-based place of an image in the list, or 0.
  chosenAt(id) {
    return this.order.findIndex((each) => each.id === id) + 1
  }

  get full() {
    return this.order.length >= this.max
  }

  mark() {
    const id = this.selected ? String(this.selected.id) : null
    this.element.querySelectorAll("[data-asset-id]").forEach((tile) => {
      if (this.multiple) this.markMultiple(tile)
      else {
        this.unmark(tile)
        tile.setAttribute("aria-pressed", tile.dataset.assetId === id ? "true" : "false")
      }
    })
  }

  markMultiple(tile) {
    const present = this.present.has(tile.dataset.assetId)
    const place = present ? 0 : this.chosenAt(Number(tile.dataset.assetId))
    this.unmark(tile)
    tile.setAttribute("aria-pressed", place > 0 ? "true" : "false")
    if (present || (place === 0 && this.full)) tile.setAttribute("aria-disabled", "true")

    if (present) {
      const mark = this.addMark(tile, this.inGalleryMarkTarget)
      mark.id = `media-picker-in-gallery-${tile.dataset.assetId}`
      tile.setAttribute("aria-describedby", mark.id)
      tile.dataset.mediaPickPresent = ""
    } else if (place > 0) {
      this.addMark(tile, this.orderMarkTarget).textContent = String(place)
      const words = messages(this.element)
      const ordinal = words.t("components.ui.media_picker.ordinal", { count: place, ordinal: true })
      tile.setAttribute("aria-label", words.t("components.ui.media_picker.chosen_order", { name: this.order[place - 1].title, ordinal }))
    }
  }

  // A tile as a single opening draws it: nothing of a multiple opening's.
  unmark(tile) {
    tile.querySelectorAll("[data-media-pick-order], [data-media-pick-in-gallery]").forEach((mark) => mark.remove())
    for (const name of [ "aria-disabled", "aria-describedby", "aria-label", "data-media-pick-present" ]) tile.removeAttribute(name)
  }

  // A mark cloned onto the tile's thumbnail (its first child, the
  // positioned face).
  addMark(tile, template) {
    const mark = template.content.firstElementChild.cloneNode(true)
    tile.firstElementChild.append(mark)
    return mark
  }

  say() {
    const words = messages(this.element)
    if (this.multiple) {
      const count = this.order.length
      if (this.hasUseTarget) {
        this.useTarget.disabled = count === 0
        this.useTarget.textContent = words.t("components.ui.media_picker.add_count", { count })
      }
      if (this.hasStatusTarget) {
        this.statusTarget.textContent = this.full
          ? words.t("components.ui.media_picker.full", { max: this.total })
          : words.t("components.ui.media_picker.takes", { count, left: this.max - count })
      }
      return
    }

    if (this.hasUseTarget) {
      this.useTarget.disabled = !this.selected
      this.useTarget.textContent = words.t("components.ui.media_picker.use")
    }
    if (!this.hasStatusTarget) return

    if (!this.selected) {
      this.statusTarget.textContent = words.t("components.ui.media_picker.none")
      return
    }

    this.statusTarget.textContent = words.t("components.ui.media_picker.selected")
    const title = document.createElement("span")
    title.className = "sr-only"
    title.textContent = `: ${this.selected.title}`
    this.statusTarget.append(title)
  }
}
