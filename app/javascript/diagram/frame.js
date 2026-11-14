// The Diagram block's renderer frame, as the card's script holds it: the
// `<iframe sandbox="allow-scripts">` at `<admin>/diagram-renderer`
// (`Admin::DiagramRenderersController`, whose script is
// `public/diagram-renderer.js`), and the one listener that hears it.
//
// THE PROTOCOL. The frame posts `{ ready: true }` once, when its fonts and
// Mermaid are set up. The card then posts `{ id, source, colours }` with
// target '*' (an opaque origin cannot be named), and the frame answers each in
// order with `{ id, svg, bytes, elements }` or `{ id, error }`. A draw asked
// for before the frame is ready waits here and is posted at `ready`: a message
// posted to a frame whose script has not run yet is lost.
//
// WHAT IS HEARD. A message counts only when it comes from THIS frame's window
// (`event.source`) and from the opaque origin (`event.origin === "null"`), and
// an answer only when it is for the last draw posted (`id === latest`): an
// answer for an older source, or a message from anything else on the page, a
// second card's frame included, is dropped. The frame keeps its own order, so
// an older answer can only be late or forged, never newer.
//
// `openFrame(slot, { url, title, onAnswer })` builds the frame as the slot's
// first child and answers `{ draw(source, colours), close() }`. `draw` answers
// the id it posted. `close` removes the frame and the listener and may be
// called more than once; nothing is posted or heard after it.
export function openFrame(slot, { url, title, onAnswer }) {
  const frame = document.createElement("iframe")
  frame.setAttribute("sandbox", "allow-scripts")
  frame.title = title
  // The drawing is the editor's decoration (the description is its text and
  // the source is the text itself), and nothing in the frame takes a key.
  frame.tabIndex = -1
  frame.className = "admin-mermaid-field__renderer"
  frame.src = url

  let latest = 0
  let ready = false
  let waiting = null
  let closed = false

  const post = (message) => frame.contentWindow.postMessage(message, "*")

  const receive = (event) => {
    if (event.source !== frame.contentWindow || event.origin !== "null") return
    const data = event.data
    if (!data || typeof data !== "object") return
    if (data.ready === true) {
      if (ready) return
      ready = true
      if (waiting) post(waiting)
      waiting = null
      return
    }
    if (data.id === latest) onAnswer(data)
  }

  window.addEventListener("message", receive)
  slot.prepend(frame)

  return {
    draw(source, colours) {
      if (closed) return null
      latest += 1
      const message = { id: latest, source, colours }
      if (ready) post(message)
      else waiting = message
      return latest
    },
    // Whether `id` is still the last draw posted.
    current(id) {
      return !closed && id === latest
    },
    close() {
      closed = true
      window.removeEventListener("message", receive)
      frame.remove()
    }
  }
}
