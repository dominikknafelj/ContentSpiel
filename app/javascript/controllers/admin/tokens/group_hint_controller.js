import { Controller } from "@hotwired/stimulus"

// The one-line description under the AI assistant page's Group select: each
// option carries its group's description (`data-description`), so changing
// the selection swaps the text with no request. The server renders the
// selected option's description in the first place, so this only follows
// later changes.
export default class extends Controller {
  static targets = ["select", "text"]

  show() {
    const option = this.selectTarget.selectedOptions[0]
    this.textTarget.textContent = option?.dataset.description || ""
  }
}
