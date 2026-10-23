import { Controller } from "@hotwired/stimulus"

// The placeholder of a text field that shows the label of another field's
// choice (`placeholder_from:` in a type's schema; the Note block's title
// shows the kind's word, design answer B3). The server draws the placeholder
// of the choice stored; this follows a new choice before its save, from the
// labels the server handed over, so the script holds no words.
//
// It only reads: it listens for `change` on the field's own form (a radio
// and a select both bubble one) and writes nothing but the placeholder, so
// it has nothing to tell autosave and is no action of a held form (it uses
// no `data-action`). At connect it reads the choice the form holds now, so
// a page drawn again from Turbo's copy is right; where the form holds no
// such control (a translation tab, where the choice is a shared field) it
// leaves the server's placeholder alone.
export default class extends Controller {
  static values = { source: String, labels: Object }

  connect() {
    this.form = this.element.form
    this.follow = this.follow.bind(this)
    this.form?.addEventListener("change", this.follow)
    const control = this.form?.elements.namedItem(this.sourceValue)
    if (control) this.show(control.value)
  }

  disconnect() {
    this.form?.removeEventListener("change", this.follow)
  }

  follow(event) {
    if (event.target.name === this.sourceValue) this.show(event.target.value)
  }

  show(value) {
    this.element.placeholder = this.labelsValue[value] ?? ""
  }
}
