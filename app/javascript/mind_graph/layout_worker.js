// The mind graph's layout, off the main thread (mind graph canvas spec §4.2):
// d3-force runs here and the page only draws, so zoom, pan and clicks stay
// smooth while a graph of a few thousand nodes is still settling.
//
// A MODULE worker started from its own asset URL. An import map does not
// apply inside a worker, so d3-force can't be imported by name: the page
// hands over the vendored file's URL (`d3Url`) with `start`, and it is
// imported once, dynamically. That file is one self-contained bundle.
//
// Messages in:  { type: "start", d3Url, nodes: [{ id, radius }], edges: [{ source, target }], reducedMotion }
//               { type: "filter", nodeIds: [...], edgeIndexes: [...] }
//               { type: "drag", id, x, y }   the node is held under the pointer
//               { type: "drop", id }         the pointer let go: the node STAYS where it is
//               { type: "pin", id }          hold the node where it is now
//               { type: "unpin", ids: [...] } let these nodes go
// Messages out: { type: "tick", positions: Float32Array }   (transferred, not copied)
//               { type: "settled", after }
//               { type: "error", message }
//
// PINNING. A node that was dragged keeps its place (`fx` / `fy` stay set after
// `drop`), and so does one pinned from its card; only `unpin` gives it back
// to the forces. A `filter` lets go of every node it hides: a pin is for a
// node on screen. Which nodes are pinned is the page's to know and to show.
//
// `after` is how many messages had been taken up when the layout cooled down.
// The page counts what it sent and believes a `settled` only when the two
// agree: a `filter` sent right behind `start` may be handled after the first
// layout has cooled down, and that first `settled` describes a layout the
// page has already asked to change (`layout_client.js`).
//
// `positions` always covers EVERY node given to `start`, in that order, two
// numbers each: a node the filter hides keeps its last place, so it comes
// back where it was.
//
// Messages are handled strictly in order (see `queue` below): the first
// `start` awaits the d3 import, and what follows it must wait for it.
//
// PACING (spec §4.2, the round of 2026-10-08). The simulation's own timer is
// stopped at once and it is stepped by hand, at one of three paces:
// - FRAME: one simulation tick, one `tick` message, then FRAME_MS until the
//   next -- so the page shows every step and the graph visibly eases to rest.
//   This is the pace of a small graph's first layout (up to SMALL_GRAPH
//   nodes), of a drag, and of the settle after a drop, a filter or an unpin.
// - FAST: as many ticks as fit into SLICE_MS, one message, then a zero timeout
//   so a message that arrived meanwhile is handled before the next slice. A
//   larger graph's first layout runs like this until about FINAL_STRETCH_MS
//   of frame-paced ticks are left, and those last ones are shown one by one.
// - SILENT, with reduced motion: the ticks run in slices with no message at
//   all, and the one `tick` that is posted is the layout at rest. A dragged
//   node moves alone (`drag` posts the last layout shown with that one node
//   moved, and ticks nothing); `drop` lays the rest out and shows the result
//   in one step.
// Whatever the pace, the run ends: `alpha` decays below `alphaMin` and
// `settled` is posted. Only a node held under the pointer keeps the layout
// warm (`alphaTarget`), and `drop` takes that back.
//
// The page says whether motion is reduced, with `start`: a worker has no
// `matchMedia` to ask.
const SLICE_MS = 12
const FRAME_MS = 16
// Up to this many nodes the first layout unfolds tick by tick (about five
// seconds); above it, it is computed as fast as the machine allows and only
// its end is shown at frame pace.
const SMALL_GRAPH = 300
const FINAL_STRETCH_MS = 600
const FINAL_TICKS = Math.round(FINAL_STRETCH_MS / FRAME_MS)
// How warm the layout is while a node is held, and what an unpin or (with
// reduced motion) a drop warms it up to: d3's own drag uses the same figure.
const HELD_ALPHA = 0.3

let d3 = null
let simulation = null
let nodes = []
let edges = []
let running = false
let reduced = false
// "frame" or "fast"; see PACING.
let pace = "frame"
// With reduced motion, the positions last posted: what a `drag` moves one
// node of, while the simulation's own are ahead of what is shown.
let shown = null

// Messages are handled strictly in order, each after the previous one has
// finished. `start` awaits the d3 import, and a `filter`, `drag` or `unpin`
// sent right behind it would otherwise run before the simulation exists: the
// filter would throw and report a spurious error, a drag would be dropped.
// An error in one message is posted and the chain goes on with the next.
let queue = Promise.resolve()
let taken = 0

self.onmessage = (event) => {
  queue = queue
    .then(() => {
      taken += 1
      return handle(event.data)
    })
    .catch((error) => self.postMessage({ type: "error", message: String(error?.message || error) }))
}

const find = (id) => nodes.find((candidate) => candidate.id === id)

async function handle(message) {
  if (message.type === "start") {
    d3 ||= await import(message.d3Url)
    reduced = Boolean(message.reducedMotion)
    start(message.nodes, message.edges)
  } else if (message.type === "filter") {
    filter(new Set(message.nodeIds), new Set(message.edgeIndexes))
  } else if (message.type === "drag") {
    const node = find(message.id)
    if (!node) return idle()
    node.fx = message.x
    node.fy = message.y
    if (reduced) {
      // The node moves alone: nothing ticks until the drop.
      node.x = message.x
      node.y = message.y
      return postMoved(node)
    }
    // A drag on a graph that has cooled down must wake it: `alphaTarget` only
    // pulls `alpha` up by ticking, and the loop does not tick while `alpha`
    // is below `alphaMin`.
    simulation.alphaTarget(HELD_ALPHA).alpha(Math.max(simulation.alpha(), HELD_ALPHA))
    pace = "frame"
    run()
  } else if (message.type === "drop") {
    if (!find(message.id)) return idle()
    // The node keeps `fx` / `fy`: it stays where it was dropped.
    simulation.alphaTarget(0)
    if (reduced) simulation.alpha(Math.max(simulation.alpha(), HELD_ALPHA))
    pace = "frame"
    run()
  } else if (message.type === "pin") {
    const node = find(message.id)
    if (node) {
      node.fx = node.x
      node.fy = node.y
    }
    // Nothing moves: the node is held where the forces had put it.
    idle()
  } else if (message.type === "unpin") {
    const freed = message.ids.map(find).filter(Boolean)
    if (!freed.length) return idle()
    freed.forEach((node) => {
      node.fx = null
      node.fy = null
    })
    simulation.alphaTarget(0).alpha(Math.max(simulation.alpha(), HELD_ALPHA))
    pace = "frame"
    run()
  }
}

// A message that changes nothing (a pin, a drag of a node that isn't there)
// still has to be answered when the layout is at rest: the page waits for a
// `settled` that counts it. While the layout runs, the `settled` that ends the
// run does.
function idle() {
  if (!running) self.postMessage({ type: "settled", after: taken })
}

function start(givenNodes, givenEdges) {
  nodes = givenNodes.map((node) => ({ id: node.id, radius: node.radius }))
  edges = givenEdges.map((edge, index) => ({ source: edge.source, target: edge.target, index }))
  shown = null
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
  pace = nodes.length <= SMALL_GRAPH ? "frame" : "fast"
  run()
}

function filter(nodeIds, edgeIndexes) {
  nodes.forEach((node) => {
    if (nodeIds.has(node.id)) return
    node.fx = null
    node.fy = null
  })
  simulation.nodes(nodes.filter((node) => nodeIds.has(node.id)))
  simulation.force("link").links(edges.filter((edge) => edgeIndexes.has(edge.index)))
  simulation.alpha(0.8)
  pace = "frame"
  run()
}

function run() {
  if (running) return
  running = true
  step()
}

const cooling = () => simulation.alpha() >= simulation.alphaMin()

// How many ticks are left until the layout has cooled down; none ends it
// while a node is held.
function remaining() {
  if (simulation.alphaTarget() > 0) return Infinity
  if (!cooling()) return 0
  return Math.ceil(Math.log(simulation.alphaMin() / simulation.alpha()) / Math.log(1 - simulation.alphaDecay()))
}

function step() {
  const started = performance.now()
  const sliceLeft = () => performance.now() - started < SLICE_MS

  if (reduced) {
    while (cooling() && sliceLeft()) simulation.tick()
    if (cooling()) return void setTimeout(step, 0)
    post()
    return finish()
  }

  if (pace === "frame" || remaining() <= FINAL_TICKS) {
    if (cooling()) simulation.tick()
    post()
    if (cooling()) setTimeout(step, Math.max(0, FRAME_MS - (performance.now() - started)))
    else finish()
  } else {
    while (remaining() > FINAL_TICKS && sliceLeft()) simulation.tick()
    post()
    setTimeout(step, 0)
  }
}

function finish() {
  running = false
  self.postMessage({ type: "settled", after: taken })
}

function current() {
  const positions = new Float32Array(nodes.length * 2)
  nodes.forEach((node, index) => {
    positions[index * 2] = node.x
    positions[index * 2 + 1] = node.y
  })
  return positions
}

function post() {
  const positions = current()
  if (reduced) shown = positions.slice()
  self.postMessage({ type: "tick", positions }, [ positions.buffer ])
}

// Reduced motion's drag: what was last shown, with the one node moved.
function postMoved(node) {
  shown ||= current()
  const index = nodes.indexOf(node)
  shown[index * 2] = node.x
  shown[index * 2 + 1] = node.y
  const positions = shown.slice()
  self.postMessage({ type: "tick", positions }, [ positions.buffer ])
}
