import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"

// The counter under a code field (code block spec §3): hidden until the text
// is within a tenth of the limit, then "18,412 of 20,000", in the warning
// colour once it is over. It counts what the server counts: `Array.from`
// walks code points, as Ruby's `String#length` does.
//
// It only READS the field. It sets no value, has nothing to tell autosave,
// and is one of the actions that survive in a form someone else holds
// (`Admin::EditorScreen::HeldFields::ALLOWED_ACTIONS`). The limit itself is
// the server's: a save over it is the form's ordinary 422, with the text
// left in the field.
export default class extends Controller {
  static targets = [ "input", "output" ]
  static values = { limit: Number, from: Number }

  connect() {
    this.update()
  }

  update() {
    const used = Array.from(this.inputTarget.value).length
    const text = messages(this.element).t("components.fields.code_field.count", { used: this.number(used), limit: this.number(this.limitValue) })

    this.outputTarget.textContent = text
    this.outputTarget.hidden = used < this.fromValue
    this.outputTarget.classList.toggle("text-warn-ink", used > this.limitValue)
    this.outputTarget.classList.toggle("text-meta", used <= this.limitValue)
  }

  // Grouped for the reader's language, as the server's first paint is; a
  // locale tag `Intl` rejects gets the bare digits.
  number(value) {
    try {
      return new Intl.NumberFormat(messages(this.element).locale()).format(value)
    } catch (error) {
      return String(value)
    }
  }
}
