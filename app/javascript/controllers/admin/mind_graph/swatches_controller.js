import { Controller } from "@hotwired/stimulus"

// The Mind graph's swatches: the small canvases of the legend and of the
// Status key (`Admin::MindGraphScreen::SwatchComponent`). Each is drawn by
// the renderer the graph itself is drawn by (`mind_graph/swatches.js`), so
// a key cannot show a look the canvas does not have.
//
// On the legend and on the key's list, one instance each: the key is a
// dialog OUTSIDE the graph's element, and the graph's own script writes
// nothing there. Thin for the reason `graph_controller.js` is: this file is
// loaded on every CS Studio page, the graph's modules only by `import()`
// when a swatch is on the page.
//
// Drawn on connect, so also on a page Turbo restored (a snapshot keeps a
// canvas's size and none of its pixels), and again when the theme changes:
// a canvas holds colours, not tokens. Nothing else is written into the
// page, so there is nothing to take back.
export default class extends Controller {
  connect() {
    const live = (this.live = Symbol("connection"))
    Promise.all([ import("mind_graph/swatches"), import("mind_graph/theme") ]).then(([ { paintSwatches }, { watchTheme } ]) => {
      if (this.live !== live) return
      paintSwatches(this.element)
      this.stop = watchTheme(() => paintSwatches(this.element))
    })
  }

  disconnect() {
    this.live = null
    this.stop?.()
    this.stop = null
  }
}
