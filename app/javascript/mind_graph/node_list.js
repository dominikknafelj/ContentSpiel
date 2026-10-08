// Every node the graph draws, as a row beside the canvas (mind graph canvas
// spec §5.7): the path for a keyboard and a screen reader, since nothing on a
// canvas can take focus, and a way to find a node by name for everyone. Two
// groups, "Posts · N" and "Tags · N", best-connected first as on the canvas;
// a row shows the node's mark (its type's dot, or a tag's square), its title
// and its number of connections.
//
// A ROW IS A BUTTON, and it does to the graph what a click on the node does:
// it selects the node, and the app brings it to the middle of the canvas and
// opens its card -- whose "Open post" is what leads to the editor. A row
// never navigates. Its accessible name says all of that in one sentence
// ("Alpha: post, 2 connections. Shows it in the graph."), because the mark is
// decoration and the count alone is a bare number. Hovering or focusing a row
// lights its node up on the canvas (`onHover`), and the row of the selected
// node is marked (`aria-current`) and scrolled into view INSIDE the panel --
// never with `scrollIntoView`, which would scroll the page as well where the
// panel stands under the canvas.
//
// Text goes in with `textContent`; no path is written here. `createList(
// container, { text, dotClasses, onSelect, onHover })` answers `{ render(nodes),
// mark(id), row(id), destroy() }`: `render` replaces the rows (the app calls
// it once per load and once per filter change), `mark` moves the mark to the
// row of `id` (null for none). `onSelect(id)` and `onHover(id | null)` get a
// node's id as the data has it. The listeners are on the container, one of
// each, however many rows there are.
import { dotClass, TAG_MARK } from "mind_graph/card"

const byDegree = (a, b) => b.degree - a.degree || String(a.title).localeCompare(String(b.title))
const ROW = "flex w-full cursor-pointer items-center gap-2 px-3 py-1 text-left text-sm text-ink hover:bg-sunken focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-accent aria-[current]:bg-accent-tint aria-[current]:font-semibold"

export function createList(container, { text, dotClasses, onSelect, onHover }) {
  // The rows by node id, as a string: a `data-` attribute is one, and a
  // post's id is a number.
  let rows = new Map()
  let ids = new Map()
  let marked = null

  const element = (tag, className, content) => {
    const created = document.createElement(tag)
    created.className = className
    if (content != null) created.textContent = content
    return created
  }
  const section = (title, items) => {
    const wrapper = document.createElement("section")
    const list = element("ul", "m-0 list-none p-0")
    list.append(...items)
    wrapper.append(element("h2", "m-0 px-3 pb-1 pt-3 font-cs-mono text-label uppercase tracking-mono text-meta", title), list)
    return wrapper
  }
  const row = (node) => {
    const item = document.createElement("li")
    const button = element("button", ROW)
    button.type = "button"
    button.dataset.nodeId = node.id
    const isTag = node.kind === "tag"
    const name = isTag ? "mind_graph.script.list.select_tag" : "mind_graph.script.list.select_post"
    button.setAttribute("aria-label", text.t(name, { title: node.title, count: node.degree }))
    const mark = element("span", isTag ? TAG_MARK : dotClass(dotClasses, node))
    mark.setAttribute("aria-hidden", "true")
    button.append(mark, element("span", "min-w-0 flex-1 truncate", node.title), element("span", "shrink-0 font-cs-mono text-label text-meta", node.degree))
    item.append(button)
    rows.set(String(node.id), button)
    ids.set(String(node.id), node.id)
    return item
  }

  const rowOf = (event) => event.target.closest?.("button[data-node-id]")
  const idOf = (button) => ids.get(button.dataset.nodeId)
  const click = (event) => {
    const button = rowOf(event)
    if (button) onSelect(idOf(button))
  }
  const over = (event) => {
    const button = rowOf(event)
    if (button) onHover(idOf(button))
  }
  const out = (event) => {
    if (rowOf(event)) onHover(null)
  }
  const listeners = { click, pointerover: over, pointerout: out, focusin: over, focusout: out }
  Object.entries(listeners).forEach(([ name, handler ]) => container.addEventListener(name, handler))

  function mark(id) {
    marked?.removeAttribute("aria-current")
    marked = id == null ? null : rows.get(String(id)) || null
    if (!marked) return

    marked.setAttribute("aria-current", "true")
    // Into view within the panel only, and only as far as needed.
    const box = container.getBoundingClientRect()
    const rowBox = marked.getBoundingClientRect()
    if (rowBox.top < box.top) container.scrollTop -= box.top - rowBox.top
    else if (rowBox.bottom > box.bottom) container.scrollTop += rowBox.bottom - box.bottom
  }

  return {
    render(nodes) {
      rows = new Map()
      ids = new Map()
      marked = null
      const posts = nodes.filter((node) => node.kind === "post").sort(byDegree)
      const tags = nodes.filter((node) => node.kind === "tag").sort(byDegree)
      if (!nodes.length) return container.replaceChildren(element("p", "m-0 px-3 py-3 text-sm text-meta", text.t("mind_graph.script.list.empty")))

      container.replaceChildren(
        ...(posts.length ? [ section(text.t("mind_graph.script.list.posts", { count: posts.length }), posts.map(row)) ] : []),
        ...(tags.length ? [ section(text.t("mind_graph.script.list.tags", { count: tags.length }), tags.map(row)) ] : [])
      )
    },
    mark,
    row: (id) => rows.get(String(id)) || null,
    destroy() {
      Object.entries(listeners).forEach(([ name, handler ]) => container.removeEventListener(name, handler))
      container.replaceChildren()
    }
  }
}
