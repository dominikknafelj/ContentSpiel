// The canvas's pointer, wheel and key events as callbacks (mind graph canvas
// spec §4.4). It knows nothing of the graph: it says where something happened,
// in canvas pixels, and `app.js` decides what that means.
//
// ONE POINTER (a mouse, a pen, one finger):
// - `onPress(x, y)` answers what the press is on: anything truthy starts a
//   drag of that thing (`onDrag(x, y)`, `onDrop()`), null pans (`onPan(dx, dy)`).
// - A press released within CLICK_SLOP pixels of where it began is a click
//   (`onClick(x, y)`), whatever it was on: "select" and "drag" start alike and
//   can only be told apart afterwards.
//
// TWO POINTERS (a pinch on a touch screen). Pointers are tracked by id. When a
// second one comes down the press is over -- a drag is dropped, and no click
// will come of it -- and the two are one gesture: the change in their distance
// zooms around the point between them (`onZoom(midX, midY, factor)`), and that
// point's own movement pans. When one of the two is lifted the gesture ends
// and the finger that stays down does NOTHING until it is lifted too: it must
// not turn into a pan that starts from where the pinch began (a jump), nor
// into a click. A third finger is ignored. A NEW finger that comes down while
// that one remains restarts the pinch: the two now down are the gesture, and
// it starts from where they are, so nothing jumps.
//
// A POINTER THAT IS NEVER LIFTED. A touch can end with neither `pointerup` nor
// `pointercancel` reaching the canvas (the browser takes the gesture, the
// window loses the pointer). What always comes is `lostpointercapture`, since
// every press is captured, and it ends the pointer as a cancel does: no
// click. Without it the entry would stay in the table for good, and every
// later touch would be the "second finger" of a pinch with a ghost. After an
// ordinary `pointerup` the same event finds nothing left to end. A MOUSE is
// left out: it always produces a `pointerup`, and a capture the browser drops
// between its press and its first move must not end a drag that is still held.
//
// - `onZoom(x, y, factor)` is also the wheel (and a trackpad's pinch, which
//   arrives as a wheel with ctrlKey), and + / - with the canvas focused,
//   around its middle.
// - Arrow keys pan; Escape is `onEscape()`. `onHover(x, y)` only with no
//   pointer down.
// Answers a function that removes every listener.
const CLICK_SLOP = 5
const KEY_PAN = 60
const KEY_ZOOM = 1.25

export function attachInput(canvas, { onPress, onDrag, onDrop, onPan, onClick, onZoom, onHover, onEscape }) {
  const at = (event) => {
    const box = canvas.getBoundingClientRect()
    return [ event.clientX - box.left, event.clientY - box.top ]
  }
  // Every pointer that is down, by id, where it last was; `press` is the one
  // pointer of a press, `pinch` the two of a gesture. Never both.
  const pointers = new Map()
  let press = null
  let pinch = null

  // The two pointers of the gesture as a distance and a midpoint.
  const span = () => {
    const [ a, b ] = pinch.ids.map((id) => pointers.get(id))
    return { distance: Math.hypot(a.x - b.x, a.y - b.y), x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 }
  }

  const pointerdown = (event) => {
    if (event.button !== 0 || pointers.size >= 2) return
    const [ x, y ] = at(event)
    pointers.set(event.pointerId, { x, y })
    // A synthetic pointer (a test's) has nothing to capture and throws.
    try { canvas.setPointerCapture(event.pointerId) } catch { /* nothing to capture */ }

    if (pointers.size === 2) {
      // The second finger: what the first one began is over.
      const hadTarget = Boolean(press?.target)
      press = null
      if (hadTarget) onDrop()
      pinch = { ids: Array.from(pointers.keys()) }
      Object.assign(pinch, span())
    } else if (!pinch) {
      press = { id: event.pointerId, startX: x, startY: y, lastX: x, lastY: y, moved: 0, target: onPress(x, y) }
    }
  }
  const pointermove = (event) => {
    const [ x, y ] = at(event)
    if (pointers.has(event.pointerId)) pointers.set(event.pointerId, { x, y })

    if (pinch) {
      if (pointers.size < 2 || !pinch.ids.includes(event.pointerId)) return
      const now = span()
      onPan(now.x - pinch.x, now.y - pinch.y)
      if (pinch.distance > 0 && now.distance > 0) onZoom(now.x, now.y, now.distance / pinch.distance)
      Object.assign(pinch, now)
      return
    }
    if (!press) return pointers.size === 0 ? onHover(x, y) : undefined
    if (event.pointerId !== press.id) return

    press.moved = Math.max(press.moved, Math.hypot(x - press.startX, y - press.startY))
    if (press.moved >= CLICK_SLOP) {
      if (press.target) onDrag(x, y)
      else onPan(x - press.lastX, y - press.lastY)
    }
    press.lastX = x
    press.lastY = y
  }
  // The end of a pointer, lifted (`click` may follow) or taken away by the
  // browser (a touch that became a scroll, a lost capture: never a click).
  const release = (event, lifted) => {
    if (!pointers.delete(event.pointerId)) return
    if (pinch) {
      // One finger of the two is gone: the gesture stays "on", doing nothing,
      // until the last one is lifted.
      if (pointers.size === 0) pinch = null
      return
    }
    if (!press || event.pointerId !== press.id) return

    const [ x, y ] = at(event)
    const wasClick = lifted && press.moved < CLICK_SLOP
    const hadTarget = Boolean(press.target)
    press = null
    if (hadTarget) onDrop()
    if (wasClick) onClick(x, y)
  }
  const pointerup = (event) => release(event, true)
  const pointercancel = (event) => release(event, false)
  // Touch and pen only: a mouse's `pointerup` always comes, and ending its
  // press here would leave a node where it started under a button still down.
  const lostpointercapture = (event) => {
    if (event.pointerType === "mouse") return
    release(event, false)
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

  const listeners = { pointerdown, pointermove, pointerup, pointercancel, lostpointercapture, pointerleave, keydown }
  Object.entries(listeners).forEach(([ name, handler ]) => canvas.addEventListener(name, handler))
  canvas.addEventListener("wheel", wheel, { passive: false })

  return () => {
    Object.entries(listeners).forEach(([ name, handler ]) => canvas.removeEventListener(name, handler))
    canvas.removeEventListener("wheel", wheel)
  }
}
