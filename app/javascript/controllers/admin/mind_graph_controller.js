import { Controller } from "@hotwired/stimulus"
import { forceCenter, forceCollide, forceLink, forceManyBody, forceSimulation } from "d3-force"

// CS Studio's mind graph (`admin/mind_graph/show`, design spec §6.1),
// ported from the Avo tool's own `mind_graph_controller.js`: d3-force
// computes node positions, this controller turns them into SVG and wires
// up dragging. The data is `PostGraph`'s `{ nodes, edges }`, read from a
// `<script type="application/json">` data island (see the view's own
// comment for why not a data attribute). Each node carries its own `url`
// (the post editor, built server-side through the route helper) and
// `color` (the content type's registry colour, or `PostGraph::PALETTE`'s
// stable pick) -- nothing here knows a path or a type.
const SVG_NS = "http://www.w3.org/2000/svg"

// Only used if a node somehow arrives without a colour at all.
const FALLBACK_NODE_COLOR = "#9ca3af"

// A pointerdown that moves less than this many total pixels before its
// pointerup is a click, not a drag -- "click a node to open that post" and
// "drag a node to reposition it" start identically and can only be told
// apart after the fact.
const CLICK_DRAG_THRESHOLD = 5

export default class extends Controller {
  static targets = ["data", "svg"]

  connect() {
    const { nodes, edges } = JSON.parse(this.dataTarget.textContent)
    this.nodes = nodes
    this.edges = edges

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
    this.svgTarget.replaceChildren()
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
    // over a node's label selects the text instead of moving the node.
    group.style.userSelect = "none"
    group.dataset.postId = node.id

    const circle = document.createElementNS(SVG_NS, "circle")
    circle.setAttribute("r", 8)
    circle.setAttribute("fill", node.color || FALLBACK_NODE_COLOR)
    group.appendChild(circle)

    // `textContent`, never markup -- a title is plain text whatever it
    // contains.
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
  // fx/fy while dragging, and nudge alphaTarget up so the rest of the graph
  // visibly resettles around it.
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

        if (totalMovement < CLICK_DRAG_THRESHOLD) this.open(node.url)
      }

      group.addEventListener("pointermove", onMove)
      group.addEventListener("pointerup", onUp)
    })
  }

  // A full Turbo visit rather than `window.location`: the post editor is
  // an ordinary CS Studio screen, so this keeps the shell's own navigation.
  open(url) {
    if (window.Turbo) window.Turbo.visit(url)
    else window.location.assign(url)
  }

  toSvgPoint(clientX, clientY) {
    const point = this.svgTarget.createSVGPoint()
    point.x = clientX
    point.y = clientY
    return point.matrixTransform(this.svgTarget.getScreenCTM().inverse())
  }
}
