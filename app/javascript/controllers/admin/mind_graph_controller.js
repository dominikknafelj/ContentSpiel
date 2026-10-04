import { Controller } from "@hotwired/stimulus"
import { forceCenter, forceCollide, forceLink, forceManyBody, forceSimulation, forceX, forceY } from "d3-force"

// CS Studio's mind graph (`admin/mind_graph/show`, design spec §6.1):
// d3-force computes node positions, this controller turns them into SVG and
// wires up dragging and the All / Related / Tags filter. The data is
// `PostGraph`'s `{ nodes, tags, edges }`, read from a
// `<script type="application/json">` data island (see the view's own
// comment for why not a data attribute). Each post node carries its own `url`
// (the post editor, built server-side through the route helper), its
// `colour_index` and its `status`; there is no colour value anywhere -- the
// controller only picks CSS classes (`.mg-*` in content-spiel.tailwind.css),
// which take their colours from the `--cs-*` tokens, so nothing here knows a
// path, a type or a hue.
const SVG_NS = "http://www.w3.org/2000/svg"

// Half a tag node's side. Tag nodes are small squares.
const TAG_HALF = 6

// A pointerdown that moves less than this many total pixels before its
// pointerup is a click, not a drag -- "click a node to open that post" and
// "drag a node to reposition it" start identically and can only be told
// apart after the fact.
const CLICK_DRAG_THRESHOLD = 5

// Minimum distance between a node's centre and the SVG's edge: the circle's
// radius (8) plus some air (a tag square's half side is smaller), so no node
// is ever cut off by the box.
const EDGE_PADDING = 16

// A label longer than this is drawn cut off with an ellipsis, so even a very
// long title can't be wider than the box. The full title stays reachable as
// the node's <title> (tooltip and accessible name).
const MAX_LABEL_CHARACTERS = 32
const LABEL_OFFSET = 12

export default class extends Controller {
  static targets = ["data", "svg", "empty"]

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

    const { nodes, tags, edges } = JSON.parse(this.dataTarget.textContent)
    // Posts and tag nodes in one list for d3 (ids can't collide: a post's id is
    // a number, a tag's is "tag-<id>"). `kind` tells them apart afterwards.
    this.nodes = [
      ...nodes.map((node) => ({ ...node, kind: "post" })),
      ...tags.map((tag) => ({ ...tag, title: tag.name, kind: "tag" }))
    ]
    this.edges = edges
    // The radios may not be on "All": Back restores the page with the one that
    // was chosen still checked, and the graph has to show what the control says.
    this.mode = this.element.querySelector("input[name=mind_graph_filter]:checked")?.value || "all"

    this.measure()

    this.edgeElements = this.edges.map((edge) => this.buildEdgeElement(edge))
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

    this.applyFilter()

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

  // The filter radios (All / Related / Tags), client-side. A node stays when
  // the filter is All, or when it has at least one edge of the chosen kind;
  // "All" keeps a post with no edge at all too (the message says there are no
  // connections), the other two hide it. The simulation is handed only the
  // visible nodes and edges, so hidden ones leave no gap and exert no force,
  // and it is reheated so what is left spreads out again -- inside the same
  // clamped box as ever.
  filter(event) {
    this.mode = event.target.value
    this.applyFilter()
    this.reheat(0.8)
  }

  applyFilter() {
    const shows = (edge) => this.mode === "all" || edge.kind === this.mode
    const connected = new Set()
    this.edges.forEach((edge) => {
      if (!shows(edge)) return
      connected.add(edge.source.id ?? edge.source)
      connected.add(edge.target.id ?? edge.target)
    })

    this.visibleEdges = this.edges.filter(shows)
    this.visibleNodes = this.nodes.filter((node) => this.mode === "all" || connected.has(node.id))
    const visibleIds = new Set(this.visibleNodes.map((node) => node.id))
    // For `tick`: asked once per node per tick, so a Set, not a list search.
    this.visibleSet = new Set(this.visibleNodes)

    this.edges.forEach((edge, index) => this.edgeElements[index].classList.toggle("mg-hidden", !shows(edge)))
    this.nodes.forEach((node, index) => this.nodeElements[index].classList.toggle("mg-hidden", !visibleIds.has(node.id)))
    // Hidden elements have no text length; `placeLabel` measures a label again
    // when its node comes back.
    this.labelWidths = []

    if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("hidden", this.visibleEdges.length > 0)

    this.simulation?.nodes(this.visibleNodes)
    this.simulation?.force("link")?.links(this.visibleEdges)
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
    // node could drift, or be flung, past the edge of the box and out of
    // sight (the box fills the view and hides what overflows it).
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
    })
    this.nodes.forEach((node, index) => {
      if (this.visibleSet.has(node)) this.placeLabel(index, node)
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
    // On the left its END is at `x`: a label longer than the room to the
    // node's left would start outside the box, so its end is pushed right
    // until its start is inside (over the node, if it must be: readable beats
    // tidy).
    const leftX = Math.max(-LABEL_OFFSET, 2 - node.x + this.labelWidths[index])
    label.setAttribute("x", onLeft ? leftX : LABEL_OFFSET)
    label.setAttribute("text-anchor", onLeft ? "end" : "start")
  }

  // Related edges are solid, a shared tag's dashed (`.mg-edge-*`): the two
  // differ in line style, not only in colour.
  buildEdgeElement(edge) {
    const line = document.createElementNS(SVG_NS, "line")
    line.setAttribute("class", `mg-edge mg-edge-${edge.kind}`)
    this.svgTarget.appendChild(line)
    return line
  }

  // The `.mg-*` classes a post's mark needs (the CSS says what each draws).
  // `colour_index` follows `Admin::ContentTypeDotComponent`: 1-6 are the six
  // hues filled, 7-12 the same hues as a ring (`mg-ring`), 13+ cycle. No index
  // at all (a type that isn't registered any more) is a ring in the neutral
  // `meta` hue. A post that isn't live is `mg-hollow`: a dashed ring.
  postClasses(node) {
    const classes = ["mg-node"]
    if (node.colour_index != null) {
      const slot = (node.colour_index - 1) % 12
      classes.push(`mg-cat-${(slot % 6) + 1}`)
      if (slot >= 6) classes.push("mg-ring")
    } else {
      classes.push("mg-ring")
    }
    if (node.status !== "live") classes.push("mg-hollow")
    return classes.join(" ")
  }

  circle(className, radius) {
    const circle = document.createElementNS(SVG_NS, "circle")
    circle.setAttribute("class", className)
    circle.setAttribute("r", radius)
    return circle
  }

  buildNodeElement(node) {
    const group = document.createElementNS(SVG_NS, "g")
    // SVG <text> is natively selectable -- without this, a drag that starts
    // over a node's label selects the text instead of moving the node.
    group.style.userSelect = "none"

    if (node.kind === "tag") {
      group.setAttribute("class", "mg-tag")
      group.dataset.tagId = node.id
      const square = document.createElementNS(SVG_NS, "rect")
      square.setAttribute("x", -TAG_HALF)
      square.setAttribute("y", -TAG_HALF)
      square.setAttribute("width", TAG_HALF * 2)
      square.setAttribute("height", TAG_HALF * 2)
      group.appendChild(square)
    } else {
      group.setAttribute("class", this.postClasses(node))
      group.dataset.postId = node.id
      // Reachable without a pointer: a link to the editor, in the tab order
      // while the node is shown (a hidden node is display: none).
      group.setAttribute("role", "link")
      group.setAttribute("tabindex", "0")
      group.setAttribute("aria-label", String(node.title))
      group.addEventListener("keydown", (event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault()
          this.open(node.url)
        }
      })
      // The focus ring outside, the dot, and -- only where it is drawn, so no
      // element sits in the SVG without a box -- the core a dashed 1-6 ring
      // keeps its hue in.
      group.append(this.circle("mg-focus", 12), this.circle("mg-dot", 8))
      if (group.classList.contains("mg-hollow") && !group.classList.contains("mg-ring")) group.append(this.circle("mg-core", 3))
    }

    // `textContent`, never markup -- a title is plain text whatever it
    // contains.
    const label = document.createElementNS(SVG_NS, "text")
    // Counted and cut by character (code point), not by UTF-16 unit: slicing
    // the string itself can split an emoji or any other astral character in
    // two and leave half of it, a lone surrogate, at the end of the label.
    // A tag's label carries its count: how many readable posts share it was
    // only in the tooltip, which a touch screen and a keyboard never see.
    const title = String(node.title)
    const characters = Array.from(node.kind === "tag" ? `${title} (${node.count})` : title)
    label.textContent = characters.length > MAX_LABEL_CHARACTERS ? `${characters.slice(0, MAX_LABEL_CHARACTERS - 1).join("")}\u2026` : characters.join("")
    label.setAttribute("x", 12)
    label.setAttribute("y", 4)
    label.setAttribute("font-size", "12")
    // A post's label takes the SVG's text colour; a tag's is `meta` (CSS).
    if (node.kind !== "tag") label.setAttribute("fill", "currentColor")
    group.appendChild(label)

    // The full title as tooltip and accessible name, whatever the label shows;
    // a tag's says how many readable posts carry it.
    const tooltip = document.createElementNS(SVG_NS, "title")
    tooltip.textContent = node.kind === "tag" ? `${title} (${node.count} posts)` : title
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

        if (node.kind === "post" && totalMovement < CLICK_DRAG_THRESHOLD) this.open(node.url)
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
