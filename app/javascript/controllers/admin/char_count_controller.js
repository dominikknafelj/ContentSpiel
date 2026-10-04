import { Controller } from "@hotwired/stimulus"

// A soft character counter under a field with a recommended length, e.g. a
// page's meta title (60) and meta description (160) (design pass round 2,
// handoff §9 B22). It counts what a person would count: `Array.from` walks
// code points, so an emoji or an astral character is one, not two UTF-16 units.
//
// Soft: past the limit the counter says "70 / 60 · long" and takes the warning
// colour, and nothing else changes -- the field still saves (the counter is a
// hint, never a validation). It only reads the input, so it never sets a value
// and has nothing to tell autosave.
export default class extends Controller {
  static targets = [ "input", "output", "announcement" ]
  static values = { limit: Number }

  // The count is not a live region (it would be read out on every
  // keystroke); the field is `aria-describedby` it instead, and only the
  // moment the text goes over the recommended length, or back under it, is
  // said, through the separate `announcement` target. Connecting is silent.
  connect() {
    this.long = Array.from(this.inputTarget.value).length > this.limitValue
    this.update()
  }

  update() {
    const length = Array.from(this.inputTarget.value).length
    const long = length > this.limitValue

    this.outputTarget.textContent = long ? `${length} / ${this.limitValue} · long` : `${length} / ${this.limitValue}`
    this.outputTarget.classList.toggle("text-warn-ink", long)
    this.outputTarget.classList.toggle("text-meta", !long)

    if (long !== this.long && this.hasAnnouncementTarget) {
      this.announcementTarget.textContent = long ? `Over the recommended length: ${length} of ${this.limitValue}.` : "Back within the recommended length."
    }
    this.long = long
  }
}
