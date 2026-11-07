// One frame of the mind graph: the canvas is redrawn once per animation
// frame, and only when something asked for one (`request`). The frame
// chooses the labels (`labels.js`), adds the hovered node's, draws
// (`renderer.js`), then runs `onDrawn` -- where the card is placed, in the
// frame that draws its node, so it never lags behind it -- and writes
// `data-zoom`, `data-labelled` and the zoom readout, each only when it
// changed: a pan redraws every frame and changes neither. `percent` writes
// the readout's figure in the messages' language; nothing here chooses a
// word.
//
// `resize()` fits the canvas's bitmap to its box times the device pixel
// ratio and answers whether that changed. A box with no size (a Turbo cache
// preview, a hidden tab) draws nothing; the observer calls again when it
// gets one. `stop()` cancels a frame that is still pending, and nothing is
// drawn after it.
import { chooseLabels, badgeBoxes, labelAt } from "mind_graph/labels"
import { draw } from "mind_graph/renderer"
import { screenOf } from "mind_graph/state"

export function createFrame({ element, canvas, context, state, reducedMotion, zoomReadout, percent, onDrawn }) {
  let pending = null
  let stopped = false
  let draws = 0
  let labelled = null
  let zoom = null

  function render() {
    // In this order: where two of these labels would overlap, the one put in
    // first keeps the place (`labels.js`, rule 3).
    const always = new Set()
    if (state.selected >= 0) always.add(state.selected)
    if (state.focusIndex >= 0) always.add(state.focusIndex)
    state.neighbours.forEach((index) => always.add(index))
    // Until the worker's first positions arrive every node is at 0, 0 -- the
    // canvas's top-left corner -- so a frame drawn before then (the data has
    // just come, or the worker never started) is an empty one, not a pile.
    const labels = state.placed ? chooseLabels({ order: state.order, positions: state.positions, widths: state.widths, radii: state.radii,
      camera: state.camera, width: state.width, height: state.height, always, free: state.free,
      obstacles: badgeBoxes({ nodes: state.nodes, indexes: state.visibleNodes, positions: state.positions, radii: state.radii, camera: state.camera }) }) : []
    // With reduced motion a label switches on, it does not fade in.
    if (reducedMotion.matches) labels.forEach((label) => { label.alpha = 1 })
    // The hovered node's label is drawn whatever the rule said of it: marked
    // where the rule placed it, added on top where it did not (a node outside
    // the canvas has none either way). A node with no label (the pill: its
    // words are inside it) has none when hovered either.
    if (state.placed && state.hovered >= 0 && state.nodes[state.hovered].label && state.visibleNodes.includes(state.hovered)) {
      const ruled = labels.find((label) => label.index === state.hovered)
      const own = ruled || labelAt({ index: state.hovered, positions: state.positions, radii: state.radii, camera: state.camera })
      own.hover = true
      const mark = screenOf(state, state.hovered)
      if (!ruled && mark.x >= 0 && mark.y >= 0 && mark.x <= state.width && mark.y <= state.height) labels.push(own)
    }
    state.labels = labels
    draw(context, state.placed ? { ...state, labels } : { ...state, labels, visibleNodes: [], visibleEdges: [] })
    draws += 1
    onDrawn()

    const k = state.camera.k.toFixed(3)
    if (k !== zoom) {
      element.dataset.zoom = zoom = k
      zoomReadout.textContent = percent(state.camera.k)
    }
    const ids = labels.map((label) => state.nodes[label.index].id).join(",")
    if (ids !== labelled) element.dataset.labelled = labelled = ids
  }

  function request() {
    if (stopped || pending != null) return
    pending = requestAnimationFrame(() => {
      pending = null
      if (stopped || state.width === 0) return
      render()
    })
  }

  function resize() {
    const box = canvas.getBoundingClientRect()
    const ratio = window.devicePixelRatio || 1
    if (box.width === state.width && box.height === state.height && ratio === state.ratio) return false

    state.width = box.width
    state.height = box.height
    state.ratio = ratio
    canvas.width = Math.round(box.width * ratio)
    canvas.height = Math.round(box.height * ratio)
    return true
  }

  function stop() {
    stopped = true
    if (pending != null) cancelAnimationFrame(pending)
    pending = null
  }

  return { request, resize, draws: () => draws, stop }
}
