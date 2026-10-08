// The canvas's pointer, wheel and key events as callbacks (mind graph canvas
// spec §4.4). It knows nothing of the graph: it says where something happened,
// in canvas pixels, and `app.js` decides what that means.
//
// - `onPress(x, y)` answers what the press is on: anything truthy starts a
//   drag of that thing (`onDrag(x, y)`, `onDrop()`), null pans (`onPan(dx, dy)`).
// - A press released within CLICK_SLOP pixels of where it began is a click
//   (`onClick(x, y)`), whatever it was on: "select" and "drag" start alike and
//   can only be told apart afterwards.
// - `onZoom(x, y, factor)`: the wheel (and a pinch, which a trackpad sends as
//   a wheel with ctrlKey), and + / - with the canvas focused, around its middle.
// - Arrow keys pan; Escape is `onEscape()`.
// Answers a function that removes every listener.
const CLICK_SLOP = 5
const KEY_PAN = 60
const KEY_ZOOM = 1.25

export function attachInput(canvas, { onPress, onDrag, onDrop, onPan, onClick, onZoom, onHover, onEscape }) {
  const at = (event) => {
    const box = canvas.getBoundingClientRect()
    return [ event.clientX - box.left, event.clientY - box.top ]
  }
  let press = null

  const pointerdown = (event) => {
    if (event.button !== 0) return
    const [ x, y ] = at(event)
    canvas.setPointerCapture(event.pointerId)
    press = { startX: x, startY: y, lastX: x, lastY: y, moved: 0, target: onPress(x, y) }
  }
  const pointermove = (event) => {
    const [ x, y ] = at(event)
    if (!press) return onHover(x, y)

    press.moved = Math.max(press.moved, Math.hypot(x - press.startX, y - press.startY))
    if (press.moved >= CLICK_SLOP) {
      if (press.target) onDrag(x, y)
      else onPan(x - press.lastX, y - press.lastY)
    }
    press.lastX = x
    press.lastY = y
  }
  const pointerup = (event) => {
    if (!press) return
    const [ x, y ] = at(event)
    const wasClick = press.moved < CLICK_SLOP
    const hadTarget = Boolean(press.target)
    press = null
    if (hadTarget) onDrop()
    if (wasClick) onClick(x, y)
  }
  // A press the browser took away (a touch that became a scroll, a lost
  // capture) ends the drag and is never a click.
  const pointercancel = () => {
    if (!press) return
    const hadTarget = Boolean(press.target)
    press = null
    if (hadTarget) onDrop()
  }
  const wheel = (event) => {
    event.preventDefault()
    const [ x, y ] = at(event)
    onZoom(x, y, Math.exp(-event.deltaY * (event.ctrlKey ? 0.01 : 0.0015)))
  }
  const keydown = (event) => {
    if (event.ctrlKey || event.metaKey || event.altKey) return

    const box = canvas.getBoundingClientRect()
    const pans = { ArrowLeft: [ KEY_PAN, 0 ], ArrowRight: [ -KEY_PAN, 0 ], ArrowUp: [ 0, KEY_PAN ], ArrowDown: [ 0, -KEY_PAN ] }
    if (pans[event.key]) onPan(...pans[event.key])
    else if (event.key === "+" || event.key === "=") onZoom(box.width / 2, box.height / 2, KEY_ZOOM)
    else if (event.key === "-") onZoom(box.width / 2, box.height / 2, 1 / KEY_ZOOM)
    else if (event.key === "Escape") onEscape()
    else return
    event.preventDefault()
  }
  const pointerleave = () => onHover(-1, -1)

  const listeners = { pointerdown, pointermove, pointerup, pointercancel, pointerleave, keydown }
  Object.entries(listeners).forEach(([ name, handler ]) => canvas.addEventListener(name, handler))
  canvas.addEventListener("wheel", wheel, { passive: false })

  return () => {
    Object.entries(listeners).forEach(([ name, handler ]) => canvas.removeEventListener(name, handler))
    canvas.removeEventListener("wheel", wheel)
  }
}
