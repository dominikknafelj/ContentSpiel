// The page's side of the layout worker (`layout_worker.js`, which documents
// the messages). One worker per graph; `stop()` terminates it, and nothing it
// had in flight is delivered afterwards.
//
// `onSettled` is called only for a `settled` that answers EVERYTHING sent so
// far: the worker says how many messages it had taken up when it cooled down
// (`after`), and one that is behind `sent` describes a layout the page has
// since asked to change -- another `settled` follows it. So "settled" on the
// page always means "what is shown is what was last asked for, at rest".
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
    start(nodes, edges) { send({ type: "start", d3Url, nodes, edges }) },
    filter(nodeIds, edgeIndexes) { send({ type: "filter", nodeIds, edgeIndexes }) },
    pin(id, x, y) { send({ type: "pin", id, x, y }) },
    unpin(id) { send({ type: "unpin", id }) },
    stop() {
      stopped = true
      worker.terminate()
    }
  }
}
