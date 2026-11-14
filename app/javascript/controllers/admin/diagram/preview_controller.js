import { Controller } from "@hotwired/stimulus"

// A Diagram block's source and its preview (`Admin::Fields::MermaidField`).
// This file declares what the field draws for it: the targets and values
// below are the server's markup, and `Admin::Fields::MermaidField` says what
// each holds. Opening a card writes nothing.
export default class extends Controller {
  static targets = ["source", "frameSlot", "status", "counter", "colourProbe"]

  static values = {
    rendererUrl: String,
    rules: Object,
    drawingField: String,
    drawingName: String,
    sourceName: String,
    starting: Boolean,
    limit: Number,
    from: Number
  }
}
