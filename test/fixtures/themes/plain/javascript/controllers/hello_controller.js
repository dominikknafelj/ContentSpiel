// The second theme's one controller. Pinned under controllers/theme/, so
// its identifier is `theme--hello`.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.dataset.plainHello = "connected"
  }
}
