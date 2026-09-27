import { Controller } from "@hotwired/stimulus"
import { forceCenter, forceCollide, forceLink, forceManyBody, forceSimulation } from "d3-force"

// Drives the mind-graph Avo tool (app/views/avo/tools/mind_graph.html.erb):
// d3-force computes node positions, this controller owns everything about
// turning that into SVG -- there is no rendering half in the vendored
// library itself (unlike SortableJS, which is a complete drag
// implementation on its own).
const SVG_NS = "http://www.w3.org/2000/svg"

// A node whose post's content type isn't (or is no longer) registered --
// `Avo::ToolsController#mind_graph` sends `color: nil` for one, the same
// `find`-not-`fetch` reasoning as `Post#definition` itself -- falls back to
// this neutral grey rather than the old hard-coded per-content_type map,
// which only ever knew about the three built-ins.
const FALLBACK_NODE_COLOR = "#9ca3af"

// A pointerdown that moves less than this many total pixels before its
// pointerup is a click, not a drag -- "click a node to open that post"
// (design spec section 9) and "drag a node to reposition it" start
// identically and can only be told apart after the fact.
const CLICK_DRAG_THRESHOLD = 5

export default class extends Controller {
  static targets = ["svg"]
  static values = { nodes: Array, edges: Array }

  connect() {
    // Copied rather than used in place: d3-force mutates every node/edge
    // object it's given (adding x/y/vx/vy, replacing an edge's source/target
    // ids with direct node references) -- these are Stimulus's own parsed
    // values and re-reading nodesValue later would see those mutations
    // reflected back as if they were part of the original payload.
    this.nodes = this.nodesValue.map((node) => ({ ...node }))
    this.edges = this.edgesValue.map((edge) => ({ ...edge }))

    const { width, height } = this.svgTarget.getBoundingClientRect()

    this.edgeElements = this.edges.map(() => this.buildEdgeElement())
    this.nodeElements = this.nodes.map((node) => this.buildNodeElement(node))

    this.simulation = forceSimulation(this.nodes)
      .force("charge", forceManyBody().strength(-250))
      .force("link", forceLink(this.edges).id((node) => node.id).distance(90))
      .force("center", forceCenter(width / 2, height / 2))
      .force("collide", forceCollide(36))
      .on("tick", () => this.tick())
  }

  disconnect() {
    this.simulation?.stop()
  }

  tick() {
    this.edges.forEach((edge, index) => {
      const line = this.edgeElements[index]
      line.setAttribute("x1", edge.source.x)
      line.setAttribute("y1", edge.source.y)
      line.setAttribute("x2", edge.target.x)
      line.setAttribute("y2", edge.target.y)
    })

    this.nodes.forEach((node, index) => {
      this.nodeElements[index].setAttribute("transform", `translate(${node.x}, ${node.y})`)
    })
  }

  buildEdgeElement() {
    const line = document.createElementNS(SVG_NS, "line")
    line.setAttribute("stroke", "currentColor")
    line.setAttribute("stroke-opacity", "0.25")
    this.svgTarget.appendChild(line)
    return line
  }

  buildNodeElement(node) {
    const group = document.createElementNS(SVG_NS, "g")
    group.style.cursor = "pointer"
    // SVG <text> is natively selectable -- without this, a drag that starts
    // over a node's label (labels sit right next to their circle, an easy
    // target to land on) selects the text instead of moving the node.
    group.style.userSelect = "none"

    const circle = document.createElementNS(SVG_NS, "circle")
    circle.setAttribute("r", 8)
    circle.setAttribute("fill", node.color || FALLBACK_NODE_COLOR)
    group.appendChild(circle)

    const label = document.createElementNS(SVG_NS, "text")
    label.textContent = node.title
    label.setAttribute("x", 12)
    label.setAttribute("y", 4)
    label.setAttribute("font-size", "12")
    label.setAttribute("fill", "currentColor")
    group.appendChild(label)

    this.svgTarget.appendChild(group)
    this.attachDragHandlers(group, node)
    return group
  }

  // The standard d3-force drag pattern: pin the node at the pointer with
  // fx/fy while dragging (the simulation leaves a fixed node's position
  // alone but keeps applying it to every other force, e.g. its links), and
  // nudge alphaTarget up so the rest of the graph visibly resettles around
  // it instead of sitting frozen at whatever alpha it had already decayed to.
  attachDragHandlers(group, node) {
    group.addEventListener("pointerdown", (event) => {
      event.preventDefault()
      group.setPointerCapture(event.pointerId)

      let totalMovement = 0
      node.fx = node.x
      node.fy = node.y
      this.simulation.alphaTarget(0.3).restart()

      const onMove = (moveEvent) => {
        totalMovement += Math.abs(moveEvent.movementX) + Math.abs(moveEvent.movementY)
        const point = this.toSvgPoint(moveEvent.clientX, moveEvent.clientY)
        node.fx = point.x
        node.fy = point.y
      }

      const onUp = () => {
        group.removeEventListener("pointermove", onMove)
        group.removeEventListener("pointerup", onUp)
        this.simulation.alphaTarget(0)

        if (totalMovement < CLICK_DRAG_THRESHOLD) window.location = node.editUrl
      }

      group.addEventListener("pointermove", onMove)
      group.addEventListener("pointerup", onUp)
    })
  }

  toSvgPoint(clientX, clientY) {
    const point = this.svgTarget.createSVGPoint()
    point.x = clientX
    point.y = clientY
    return point.matrixTransform(this.svgTarget.getScreenCTM().inverse())
  }
}
