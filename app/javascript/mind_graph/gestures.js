// What the canvas's gestures do to the graph. `input.js` says which gesture
// the pointer, the wheel or a key made and knows nothing of the graph; this
// module turns each into a change of the state, the camera or the layout,
// and keeps the hover and its tooltip. What a gesture asks of the selection
// and the frame comes in as `act` (`select`, `dismiss`, `unpin`,
// `pinsChanged`, `measureCard`, `openCard`, `request`), and `layout()`
// answers the layout client of the moment, or null when there is none (the
// data is still on its way, or the worker failed).
//
// THE CAMERA moves on the person's input: a pan, a zoom, the arrow keys
// (`moveCamera`). The first such move ends the first view's fit
// (`state.fitted`), as a drag of a node does: the camera stops following the
// layout the moment a node is held, or the node would slide from under the
// pointer. After every move the hover is asked again (`rehover`), so a zoom
// towards a node keeps it lit and a pan leaves no node lit that is no longer
// under the pointer.
//
// DRAGGING AND PINNING. A press that moves is a drag, not a click: it moves
// the node, the neighbours follow (the worker ticks once per frame while a
// node is held), and the selection is left as it was. A DROPPED NODE STAYS
// WHERE IT WAS DROPPED: it is pinned from its first move. The node is held
// where it was grabbed, not by its centre: a drag by the label must not make
// the mark jump to the pointer. While its own node is dragged the card is out
// of the way, and comes back with the drop. A double click on a pinned node
// lets that one go.
//
// HOVERING a node -- with the pointer, or its row in the list (`hoverRow`) --
// rings it and shows its label on a backing, even where the label rule hides
// it; nothing else dims. The pointer's hover wins over the row's. The
// tooltip is only for a title the label cuts short: beside the pointer and
// inside the box (which clips what leaves it), written with `textContent`, a
// title being text, and only when the pointer comes onto another node.
import { attachInput } from "mind_graph/input"
import { toGraph, zoomAt, panBy } from "mind_graph/camera"
import { hitAt } from "mind_graph/state"

// The tooltip's distance from the pointer, and from the box's edge when it
// would otherwise leave the box.
const TOOLTIP_OFFSET = 14
const TOOLTIP_MARGIN = 4

export function attachGestures({ canvas, element, state, tooltip, cardElement, layout, act }) {
  // The node a press is on (an index, -1 for none), where on it the press
  // took hold (in graph units from its centre) and whether it has become a
  // drag: a press becomes one only once it has moved, and a plain click must
  // send the worker nothing -- a `drag` reheats the layout, and the graph
  // would twitch under a click.
  let pressed = -1
  let grab = { dx: 0, dy: 0 }
  let dragging = false
  // What is hovered, by each of its two sources (indexes, -1 for none).
  // `pointerAt` is where the pointer last was over the canvas, so the hover
  // can be worked out again when the view moves under it.
  let pointerHover = -1
  let rowHover = -1
  let pointerAt = null

  function hideTooltip() {
    tooltip.hidden = true
  }

  function syncHover() {
    const next = pointerHover >= 0 ? pointerHover : rowHover
    if (next === state.hovered) return
    state.hovered = next
    element.dataset.hovered = next >= 0 ? state.nodes[next].id : ""
    act.request()
  }

  function rehover() {
    if (pointerAt) hover(...pointerAt)
    else hideTooltip()
  }

  function hover(x, y) {
    pointerAt = x >= 0 ? [ x, y ] : null
    const index = pressed < 0 && x >= 0 ? hitAt(state, x, y) : -1
    canvas.style.cursor = index >= 0 ? "pointer" : ""
    const changed = index !== pointerHover
    pointerHover = index
    syncHover()
    // The label on its backing names the node; the tooltip is for the rest of
    // a title the label cuts short.
    if (index < 0 || !state.nodes[index].cut) return hideTooltip()

    if (changed || tooltip.hidden) tooltip.textContent = state.nodes[index].title
    tooltip.hidden = false
    // Measured from the left edge: an absolute box near the right edge is
    // only as wide as the room left there, and the clamp needs the width the
    // title has when it is not squeezed.
    tooltip.style.left = "0px"
    const left = Math.min(x + TOOLTIP_OFFSET, state.width - tooltip.offsetWidth - TOOLTIP_MARGIN)
    const below = y + TOOLTIP_OFFSET
    const top = below + tooltip.offsetHeight + TOOLTIP_MARGIN > state.height ? y - TOOLTIP_OFFSET - tooltip.offsetHeight : below
    tooltip.style.left = `${Math.max(TOOLTIP_MARGIN, left)}px`
    tooltip.style.top = `${Math.max(TOOLTIP_MARGIN, top)}px`
  }

  function moveCamera(camera) {
    state.camera = camera
    state.fitted = true
    rehover()
    act.request()
  }

  const stopInput = attachInput(canvas, {
    // A press on a node may become a drag of it, a press on empty space pans.
    // Whether the press was a click is known only at release (`input.js`), so
    // nothing is sent to the layout yet. The answer is the index plus one,
    // because `input.js` asks for something truthy and index 0 is a node.
    onPress: (x, y) => {
      pressed = hitAt(state, x, y)
      dragging = false
      if (pressed >= 0) {
        const [ gx, gy ] = toGraph(state.camera, x, y)
        grab = { dx: gx - state.positions[pressed * 2], dy: gy - state.positions[pressed * 2 + 1] }
      }
      // Where the pointer is over is not known again until it moves with no
      // button down; a node that is held stays lit meanwhile.
      pointerAt = null
      if (pressed < 0) pointerHover = -1
      syncHover()
      hideTooltip()
      return pressed >= 0 ? pressed + 1 : null
    },
    // The press has moved: the node is held under the pointer in the worker
    // (`drag`), which keeps the layout warm so the neighbours follow.
    onDrag: (x, y) => {
      const client = layout()
      if (pressed < 0 || !client) return
      const [ gx, gy ] = toGraph(state.camera, x, y)
      state.fitted = true
      if (!dragging) {
        dragging = true
        // Pinned here, not through the selection's `pin`: the worker holds a
        // dragged node itself, so no `pin` message is sent for it.
        state.pinned.add(pressed)
        act.pinsChanged()
        if (pressed === state.selected) cardElement.hidden = true
      }
      element.removeAttribute("data-settled")
      client.drag(state.nodes[pressed].id, gx - grab.dx, gy - grab.dy)
    },
    // Also the end of a press a second finger took over (a pinch). `drop`
    // only answers a `drag`: the node stays where it is, pinned, and `settled`
    // is announced again when the layout has cooled down around it.
    onDrop: () => {
      if (dragging) {
        layout()?.drop(state.nodes[pressed].id)
        if (pressed === state.selected) {
          cardElement.hidden = false
          act.measureCard()
        }
      }
      pressed = -1
      dragging = false
    },
    onClick: (x, y) => {
      const index = hitAt(state, x, y)
      if (index < 0) act.dismiss()
      else act.select(index)
    },
    // The shortcut for "let this one go". (Both of its clicks have selected
    // the node already.)
    onDoubleClick: (x, y) => {
      const index = hitAt(state, x, y)
      if (index >= 0) act.unpin([ index ])
    },
    onEscape: () => act.dismiss(),
    // Enter with a post or a page selected opens it (the card's own "Open
    // post" or "Open page").
    onEnter: () => act.openCard(),
    onHover: hover,
    onPan: (dx, dy) => moveCamera(panBy(state.camera, dx, dy)),
    onZoom: (x, y, factor) => moveCamera(zoomAt(state.camera, x, y, factor))
  })

  return {
    hoverRow(index) {
      rowHover = index
      syncHover()
    },
    // Neither source hovers a node the legend hides any longer.
    forgetHidden() {
      const shown = new Set(state.visibleNodes)
      if (rowHover >= 0 && !shown.has(rowHover)) rowHover = -1
      if (pointerHover >= 0 && !shown.has(pointerHover)) pointerHover = -1
      syncHover()
    },
    rehover,
    moveCamera,
    // The graph the hover was of has gone: nothing is hovered, by either
    // source.
    clearHover() {
      state.hovered = pointerHover = rowHover = -1
      element.dataset.hovered = ""
    },
    hideTooltip,
    stop() {
      stopInput()
      hideTooltip()
      canvas.style.cursor = ""
    }
  }
}
