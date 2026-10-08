// The mind graph's layout, off the main thread (mind graph canvas spec §4.2):
// d3-force runs here and the page only draws, so zoom, pan and clicks stay
// smooth while a graph of a few thousand nodes is still settling.
//
// A MODULE worker started from its own asset URL. An import map does not
// apply inside a worker, so d3-force can't be imported by name: the page
// hands over the vendored file's URL (`d3Url`) with `start`, and it is
// imported once, dynamically. That file is one self-contained bundle.
//
// Messages in:  { type: "start", d3Url, nodes: [{ id, radius }], edges: [{ source, target }] }
//               { type: "filter", nodeIds: [...], edgeIndexes: [...] }
//               { type: "pin", id, x, y } / { type: "unpin", id }
// Messages out: { type: "tick", positions: Float32Array }   (transferred, not copied)
//               { type: "settled" }
//               { type: "error", message }
//
// `positions` always covers EVERY node given to `start`, in that order, two
// numbers each: a node the filter hides keeps its last place, so it comes
// back where it was.
//
// The simulation's own timer is stopped at once and it is stepped by hand:
// as many ticks as fit into SLICE_MS, one message, then a zero timeout so a
// `pin` or `filter` that arrived meanwhile is handled before the next slice.
const SLICE_MS = 12

let d3 = null
let simulation = null
let nodes = []
let edges = []
let running = false

self.onmessage = (event) => {
  handle(event.data).catch((error) => self.postMessage({ type: "error", message: String(error?.message || error) }))
}

async function handle(message) {
  if (message.type === "start") {
    d3 ||= await import(message.d3Url)
    start(message.nodes, message.edges)
  } else if (message.type === "filter") {
    filter(new Set(message.nodeIds), new Set(message.edgeIndexes))
  } else if (message.type === "pin") {
    const node = nodes.find((candidate) => candidate.id === message.id)
    if (!node) return
    node.fx = message.x
    node.fy = message.y
    simulation.alphaTarget(0.3)
    run()
  } else if (message.type === "unpin") {
    const node = nodes.find((candidate) => candidate.id === message.id)
    if (!node) return
    node.fx = null
    node.fy = null
    simulation.alphaTarget(0)
    run()
  }
}

function start(givenNodes, givenEdges) {
  nodes = givenNodes.map((node) => ({ id: node.id, radius: node.radius }))
  edges = givenEdges.map((edge, index) => ({ source: edge.source, target: edge.target, index }))
  simulation = d3.forceSimulation(nodes)
    // `distanceMax` bounds each node's repulsion to its surroundings: without
    // it every node pushes every other, which is what makes a large graph slow
    // and flings its outer nodes away.
    .force("charge", d3.forceManyBody().strength(-250).distanceMax(600))
    .force("link", d3.forceLink(edges.slice()).id((node) => node.id).distance(90))
    .force("x", d3.forceX(0).strength(0.04))
    .force("y", d3.forceY(0).strength(0.04))
    .force("collide", d3.forceCollide((node) => node.radius + 10))
    .stop()
  run()
}

function filter(nodeIds, edgeIndexes) {
  simulation.nodes(nodes.filter((node) => nodeIds.has(node.id)))
  simulation.force("link").links(edges.filter((edge) => edgeIndexes.has(edge.index)))
  simulation.alpha(0.8)
  run()
}

function run() {
  if (running) return
  running = true
  step()
}

function step() {
  const started = performance.now()
  const cooling = () => simulation.alpha() >= simulation.alphaMin()
  while (cooling() && performance.now() - started < SLICE_MS) simulation.tick()

  const positions = new Float32Array(nodes.length * 2)
  nodes.forEach((node, index) => {
    positions[index * 2] = node.x
    positions[index * 2 + 1] = node.y
  })
  self.postMessage({ type: "tick", positions }, [ positions.buffer ])

  if (cooling()) {
    setTimeout(step, 0)
  } else {
    running = false
    self.postMessage({ type: "settled" })
  }
}
