import { Controller } from "@hotwired/stimulus"

// The Default radios of the Languages card (round 3, Task 6). Choosing another
// radio opens that language's "Make <Name> the default?" dialog
// (`change->admin--dialog#open` on the radio itself); nothing changes until the
// dialog's own form is confirmed. Closing the dialog any other way -- Cancel,
// Escape, the x, the backdrop -- must therefore put the radio back on the
// language that IS the default, which is all this does. The dialogs sit
// outside this element (forms can't nest), so the close is heard on `document`
// in the capture phase (`close` doesn't bubble).
export default class extends Controller {
  static targets = ["radio"]

  connect() {
    this.onClose = (event) => {
      if (event.target instanceof HTMLDialogElement && event.target.id.startsWith("language-default-dialog-")) this.reset()
    }
    document.addEventListener("close", this.onClose, true)
  }

  disconnect() {
    document.removeEventListener("close", this.onClose, true)
  }

  reset() {
    this.radioTargets.forEach((radio) => { radio.checked = radio.hasAttribute("data-current") })
  }
}
