// The selection card (mind graph canvas spec §5.3): what a click on a node
// opens, and the only place a selection leads anywhere. HTML beside the
// canvas, so its links are links -- reachable by keyboard, opened in a new tab
// like any other -- and a click on the canvas never navigates by itself.
//
// Built with `textContent` and `href` only: a title or a tag's name is the
// editor's text, whatever it contains. A URL comes from a template the server
// built with its route helpers (`__ID__`, `__NAME__`), never from a path
// written here; a post's own editor URL arrives with its node.
//
// `createCard(container, { text, urls, typeLabels, onClose })` answers
// `{ show(node), hide() }`. `text` is `messages(element)`, `urls` the three
// templates (`postFocus`, `tagFocus`, `tagPosts`), `typeLabels` a content
// type's human name by its stored name, `onClose` what the Close button does
// (the app clears the selection, which hides the card).
//
// The status chip is `Admin::StatusChipComponent`'s, class for class: a dot in
// the status's token colour AND the word, so the colour is never the only cue.
const STATUS_DOTS = { draft: "bg-meta", scheduled: "bg-warn", live: "bg-ok" }
const LINK = "w-fit text-sm text-accent underline hover:text-accent-hover"

export function createCard(container, { text, urls, typeLabels, onClose }) {
  const element = (tag, className, content) => {
    const node = document.createElement(tag)
    if (className) node.className = className
    if (content != null) node.textContent = content
    return node
  }
  const link = (label, href) => {
    const anchor = element("a", LINK, label)
    anchor.href = href
    return anchor
  }
  // A function as the replacement: a string would have its `$&` and `$1` read
  // as patterns. (`encodeURIComponent` escapes `$` anyway; this does not rely
  // on it.)
  const fill = (template, placeholder, value) => template.replace(placeholder, () => encodeURIComponent(value))

  const title = (node) => element("h2", "m-0 break-words text-base font-semibold text-ink", node.title)

  function statusChip(status) {
    const chip = element("span", "admin-status-chip inline-flex shrink-0 items-center gap-1.5 rounded-cs border border-line-strong px-2 py-0.5 text-xs text-ink")
    chip.dataset.status = status
    const dot = element("span", `h-1.5 w-1.5 rounded-full ${STATUS_DOTS[status]}`)
    dot.setAttribute("aria-hidden", "true")
    chip.append(dot, text.t(`mind_graph.script.card.status.${status}`))
    return chip
  }

  function post(node) {
    // A type that is no longer registered has no label: its stored name, as
    // the type dot shows it everywhere else. `hasOwn`, because a stored name
    // is data and `typeLabels.constructor` is not a label.
    const kind = element("p", "m-0 flex flex-wrap items-center gap-2 text-sm text-dim")
    kind.append(element("span", "", Object.hasOwn(typeLabels, node.type) ? typeLabels[node.type] : node.type))
    if (Object.hasOwn(STATUS_DOTS, node.status)) kind.append(statusChip(node.status))
    return [
      kind,
      title(node),
      element("p", "m-0 text-sm text-dim", text.t("mind_graph.script.card.connections", { count: node.degree })),
      link(text.t("mind_graph.script.card.open_post"), node.url),
      link(text.t("mind_graph.script.card.focus"), fill(urls.postFocus, "__ID__", node.id))
    ]
  }

  function tag(node) {
    return [
      element("p", "m-0 text-sm text-dim", text.t("mind_graph.script.card.tag")),
      title(node),
      element("p", "m-0 text-sm text-dim", text.t("mind_graph.script.card.tag_posts", { count: node.count })),
      link(text.t("mind_graph.script.card.focus"), fill(urls.tagFocus, "__ID__", String(node.id).replace("tag-", ""))),
      link(text.t("mind_graph.script.card.show_tagged"), fill(urls.tagPosts, "__NAME__", node.title))
    ]
  }

  return {
    show(node) {
      const close = element("button", "cursor-pointer self-end text-sm text-meta underline hover:text-ink", text.t("mind_graph.script.card.close"))
      close.type = "button"
      close.addEventListener("click", onClose)

      container.replaceChildren(close, ...(node.kind === "tag" ? tag(node) : post(node)))
      container.hidden = false
    },
    hide() {
      container.hidden = true
      container.replaceChildren()
    }
  }
}
