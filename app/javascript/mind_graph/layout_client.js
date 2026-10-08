// The page's side of the layout worker (`layout_worker.js`, which documents
// the messages). One worker per graph; `stop()` terminates it, and nothing it
// had in flight is delivered afterwards.
export function createLayout({ workerUrl, d3Url, onTick, onSettled, onError }) {
  const worker = new Worker(workerUrl, { type: "module" })
  let stopped = false

  worker.onmessage = ({ data }) => {
    if (stopped) return
    if (data.type === "tick") onTick(data.positions)
    else if (data.type === "settled") onSettled()
    else if (data.type === "error") onError(data.message)
  }
  // A worker that can't be fetched or parsed at all never runs `onmessage`.
  worker.onerror = (event) => {
    event.preventDefault()
    if (!stopped) onError(event.message || "the layout worker could not start")
  }

  return {
    start(nodes, edges) { worker.postMessage({ type: "start", d3Url, nodes, edges }) },
    filter(nodeIds, edgeIndexes) { worker.postMessage({ type: "filter", nodeIds, edgeIndexes }) },
    pin(id, x, y) { worker.postMessage({ type: "pin", id, x, y }) },
    unpin(id) { worker.postMessage({ type: "unpin", id }) },
    stop() {
      stopped = true
      worker.terminate()
    }
  }
}
