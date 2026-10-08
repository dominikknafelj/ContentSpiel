// Every node the graph draws, as a link (mind graph canvas spec §5.7): the
// path for a keyboard and a screen reader, since nothing on a canvas can take
// focus. Two lists, posts and tags, best-connected first as on the canvas; a
// row links to the node's local view and says how many connections it has,
// and a post's row links to its editor too.
//
// Text goes in with `textContent`, a URL from the server's templates (filled
// by `card.js`'s `fill`) or the node's own `url`; no path is written here.
// `renderList(container, { nodes, text, urls })` replaces the container's
// children; the app calls it once per load and once per filter change.
import { fill } from "mind_graph/card"

const byDegree = (a, b) => b.degree - a.degree || String(a.title).localeCompare(String(b.title))

export function renderList(container, { nodes, text, urls }) {
  const element = (tag, className, content) => {
    const created = document.createElement(tag)
    created.className = className
    if (content != null) created.textContent = content
    return created
  }
  const section = (title, rows) => {
    const wrapper = document.createElement("section")
    const list = element("ul", "m-0 flex list-none flex-col gap-1 p-0")
    list.append(...rows)
    wrapper.append(element("h2", "m-0 mb-1 text-label text-meta", title), list)
    return wrapper
  }
  const row = (node) => {
    const item = element("li", "flex flex-wrap items-baseline gap-x-2")
    const focus = element("a", "text-ink underline", node.title)
    focus.href = node.kind === "tag"
      ? fill(urls.tagFocus, "__ID__", String(node.id).replace("tag-", ""))
      : fill(urls.postFocus, "__ID__", node.id)
    item.append(focus, element("span", "text-meta", text.t("mind_graph.script.list.connections", { count: node.degree })))
    if (node.kind === "post") {
      const edit = element("a", "text-accent underline", text.t("mind_graph.script.list.edit"))
      edit.href = node.url
      edit.setAttribute("aria-label", `${text.t("mind_graph.script.list.edit")}: ${node.title}`)
      item.append(edit)
    }
    return item
  }
  const posts = nodes.filter((node) => node.kind === "post").sort(byDegree)
  const tags = nodes.filter((node) => node.kind === "tag").sort(byDegree)

  container.replaceChildren(
    ...(posts.length ? [ section(text.t("mind_graph.script.list.posts"), posts.map(row)) ] : []),
    ...(tags.length ? [ section(text.t("mind_graph.script.list.tags"), tags.map(row)) ] : [])
  )
}
