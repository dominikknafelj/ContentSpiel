// The page's side of the layout worker (`layout_worker.js`, which documents
// the messages). One worker per graph; `stop()` terminates it, and nothing it
// had in flight is delivered afterwards.
//
// `onSettled` is called only for a `settled` that answers EVERYTHING sent so
// far: the worker says how many messages it had taken up when it cooled down
// (`after`), and one that is behind `sent` describes a layout the page has
// since asked to change -- another `settled` follows it. So "settled" on the
// page always means "what is shown is what was last asked for, at rest".
import { SPRINGS, EASE } from "mind_graph/layout_parameters"

export function createLayout({ workerUrl, d3Url, onTick, onSettled, onError }) {
  const worker = new Worker(workerUrl, { type: "module" })
  let stopped = false
  let sent = 0

  const send = (message) => {
    sent += 1
    worker.postMessage(message)
  }

  worker.onmessage = ({ data }) => {
    if (stopped) return
    if (data.type === "tick") onTick(data.positions)
    else if (data.type === "settled") { if (data.after === sent) onSettled() }
    else if (data.type === "error") onError(data.message)
  }
  // A worker that can't be fetched or parsed at all never runs `onmessage`.
  worker.onerror = (event) => {
    event.preventDefault()
    if (!stopped) onError(event.message || "the layout worker could not start")
  }

  return {
    // A node may carry `anchor` (held at the centre) and an edge carries its
    // `kind` (which chooses its spring); both are passed on as given.
    // `reducedMotion`: the worker has no `matchMedia`, so the page says it.
    // `springs` and `ease` are the layout's own (`layout_parameters.js`)
    // unless a caller names others: the app never does, a test of the worker
    // does, to see a spring or an ease at work without waiting out the real one.
    start(nodes, edges, { reducedMotion = false, springs = SPRINGS, ease = EASE } = {}) { send({ type: "start", d3Url, nodes, edges, reducedMotion, springs, ease }) },
    filter(nodeIds, edgeIndexes) { send({ type: "filter", nodeIds, edgeIndexes }) },
    drag(id, x, y) { send({ type: "drag", id, x, y }) },
    drop(id) { send({ type: "drop", id }) },
    pin(id) { send({ type: "pin", id }) },
    unpin(ids) { send({ type: "unpin", ids }) },
    stop() {
      stopped = true
      worker.terminate()
    }
  }
}
