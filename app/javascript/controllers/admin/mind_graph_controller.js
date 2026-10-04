import { Controller } from "@hotwired/stimulus"
import { forceCenter, forceCollide, forceLink, forceManyBody, forceSimulation, forceX, forceY } from "d3-force"

// CS Studio's mind graph (`admin/mind_graph/show`, design spec §6.1):
// d3-force computes node positions, this controller turns them into SVG and
// wires up dragging. The data is `PostGraph`'s `{ nodes, edges }`, read from a
// `<script type="application/json">` data island (see the view's own
// comment for why not a data attribute). Each node carries its own `url`
// (the post editor, built server-side through the route helper) and
// `color` (the content type's registry colour, or `PostGraph::PALETTE`'s
// stable pick) -- nothing here knows a path or a type.
const SVG_NS = "http://www.w3.org/2000/svg"

// Only used if a node somehow arrives without a colour at all.
const FALLBACK_NODE_COLOR = "var(--cs-meta)"

// A pointerdown that moves less than this many total pixels before its
// pointerup is a click, not a drag -- "click a node to open that post" and
// "drag a node to reposition it" start identically and can only be told
// apart after the fact.
const CLICK_DRAG_THRESHOLD = 5

// Minimum distance between a node's centre and the SVG's edge: the circle's
// radius (8) plus some air, so no node is ever cut off by the box.
const EDGE_PADDING = 16

// A label longer than this is drawn cut off with an ellipsis, so even a very
// long title can't be wider than the box. The full title stays reachable as
// the node's <title> (tooltip and accessible name).
const MAX_LABEL_CHARACTERS = 32
const LABEL_OFFSET = 12

export default class extends Controller {
  static targets = ["data", "svg"]

  connect() {
    // Turbo snapshots the page *before* `disconnect()` below gets to clear
    // the SVG (fix round 1, I1), so a page restored by Back arrives with
    // the previous visit's `<g>`/`<line>` elements still inside -- inert
    // copies with no simulation behind them. Start from an empty canvas
    // every time rather than drawing a second live set on top.
    this.svgTarget.replaceChildren()
    // The same snapshot carries `data-settled` if it was taken after the
    // previous visit's simulation cooled down; the new simulation is only
    // just starting.
    this.svgTarget.removeAttribute("data-settled")

    const { nodes, edges } = JSON.parse(this.dataTarget.textContent)
    this.nodes = nodes
    this.edges = edges

    this.measure()

    this.edgeElements = this.edges.map(() => this.buildEdgeElement())
    this.nodeElements = this.nodes.map((node) => this.buildNodeElement(node))

    this.simulation = forceSimulation(this.nodes)
      .force("charge", forceManyBody().strength(-250))
      .force("link", forceLink(this.edges).id((node) => node.id).distance(90))
      .force("center", forceCenter(this.width / 2, this.height / 2))
      // A gentle pull towards the middle on each axis, so repulsion pushes
      // nodes towards the edges less often than it would with forceCenter
      // alone (which only moves the *mean* position).
      .force("x", forceX(this.width / 2).strength(0.04))
      .force("y", forceY(this.height / 2).strength(0.04))
      .force("collide", forceCollide(36))
      .on("tick", () => this.tick())
      // `end` fires once alpha drops below alphaMin, i.e. the layout has
      // cooled down. Exposed as a DOM attribute so tests can wait on it.
      .on("end", () => this.svgTarget.setAttribute("data-settled", ""))

    // The box is `w-full` of a shell column, so it changes with the window.
    // The observer also fires once on observe(); that first call finds the
    // size unchanged and does nothing.
    this.resizeObserver = new ResizeObserver(() => this.resize())
    this.resizeObserver.observe(this.svgTarget)
  }

  disconnect() {
    this.resizeObserver?.disconnect()
    this.simulation?.stop()
    this.svgTarget.replaceChildren()
  }

  // If the SVG has no layout at connect time (a hidden tab, a Turbo cache
  // preview) the rect is 0x0, so the clamp would pin every node to a corner
  // (min wins over max). That recovers by itself: the ResizeObserver fires
  // when the box gets its real size, `resize()` sees it differs, re-centres,
  // re-clamps and reheats.
  measure() {
    const { width, height } = this.svgTarget.getBoundingClientRect()
    this.width = width
    this.height = height
  }

  // The box changed size: re-centre the forces on the new middle, pull any
  // node that is now outside back in, and reheat so the layout resettles.
  resize() {
    const { width, height } = this.svgTarget.getBoundingClientRect()
    if (width === this.width && height === this.height) return

    this.width = width
    this.height = height
    this.simulation
      .force("center", forceCenter(width / 2, height / 2))
      .force("x", forceX(width / 2).strength(0.04))
      .force("y", forceY(height / 2).strength(0.04))
    this.clampNodes()
    this.reheat(0.3)
  }

  reheat(alpha) {
    this.svgTarget.removeAttribute("data-settled")
    this.simulation.alpha(alpha).restart()
  }

  clampX(x) {
    return Math.max(EDGE_PADDING, Math.min(this.width - EDGE_PADDING, x))
  }

  clampY(y) {
    return Math.max(EDGE_PADDING, Math.min(this.height - EDGE_PADDING, y))
  }

  clampNodes() {
    for (const node of this.nodes) {
      node.x = this.clampX(node.x)
      node.y = this.clampY(node.y)
      // A pinned (being dragged) node's fx/fy would put it back outside on
      // the next tick.
      if (node.fx != null) node.fx = this.clampX(node.fx)
      if (node.fy != null) node.fy = this.clampY(node.fy)
    }
  }

  tick() {
    // Keep every node inside the box (design pass round 1): forceCenter
    // only centres the *mean* position, so a strongly repelled or dragged
    // node could drift, or be flung, past the edge -- and the box used to
    // fill the whole content column, so "past the edge" was off-screen.
    this.clampNodes()

    this.edges.forEach((edge, index) => {
      const line = this.edgeElements[index]
      line.setAttribute("x1", edge.source.x)
      line.setAttribute("y1", edge.source.y)
      line.setAttribute("x2", edge.target.x)
      line.setAttribute("y2", edge.target.y)
    })

    this.nodes.forEach((node, index) => {
      this.nodeElements[index].setAttribute("transform", `translate(${node.x}, ${node.y})`)
      this.placeLabel(index, node)
    })
  }

  // A node clamped near the right edge would have its label cut off by the
  // box's overflow-hidden, so such a label is drawn on the node's left
  // instead (text-anchor end), and flips back as the node moves away.
  placeLabel(index, node) {
    const label = this.nodeElements[index].querySelector("text")
    this.labelWidths ||= []
    // Measured once the text is laid out; 0 (not yet laid out) is retried.
    if (!this.labelWidths[index]) this.labelWidths[index] = label.getComputedTextLength()

    const crossesRight = node.x + LABEL_OFFSET + this.labelWidths[index] > this.width
    const onLeft = crossesRight && node.x > this.width / 2
    label.setAttribute("x", onLeft ? -LABEL_OFFSET : LABEL_OFFSET)
    label.setAttribute("text-anchor", onLeft ? "end" : "start")
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
    // `style`, not the attribute: a custom property reference is CSS, and the
    // fallback is a token so it follows the theme.
    circle.style.fill = node.color || FALLBACK_NODE_COLOR
    group.appendChild(circle)

    // `textContent`, never markup -- a title is plain text whatever it
    // contains.
    const label = document.createElementNS(SVG_NS, "text")
    // Counted and cut by character (code point), not by UTF-16 unit: slicing
    // the string itself can split an emoji or any other astral character in
    // two and leave half of it, a lone surrogate, at the end of the label.
    const title = String(node.title)
    const characters = Array.from(title)
    label.textContent = characters.length > MAX_LABEL_CHARACTERS ? `${characters.slice(0, MAX_LABEL_CHARACTERS - 1).join("")}\u2026` : characters.join("")
    label.setAttribute("x", 12)
    label.setAttribute("y", 4)
    label.setAttribute("font-size", "12")
    label.setAttribute("fill", "currentColor")
    group.appendChild(label)

    // The full title as tooltip and accessible name, whatever the label shows.
    const tooltip = document.createElementNS(SVG_NS, "title")
    tooltip.textContent = title
    group.appendChild(tooltip)

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
      this.svgTarget.removeAttribute("data-settled")
      this.simulation.alphaTarget(0.3).restart()

      const onMove = (moveEvent) => {
        totalMovement += Math.abs(moveEvent.movementX) + Math.abs(moveEvent.movementY)
        const point = this.toSvgPoint(moveEvent.clientX, moveEvent.clientY)
        // Clamped too: a node held at the pointer outside the box would
        // otherwise be drawn outside it for as long as the drag lasts.
        node.fx = this.clampX(point.x)
        node.fy = this.clampY(point.y)
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
