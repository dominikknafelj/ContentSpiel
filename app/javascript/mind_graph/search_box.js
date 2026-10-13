// The mind graph's search field (mind graph canvas spec §5.5; pages in the
// mind graph, spec §5): readable pages, posts and tags by name, each row a
// LINK to that row's local view -- so a result is opened like any other
// link, by click, Enter or a new tab, and Back returns. The script never
// navigates by itself, and a row's URL is the server's (`href` from the
// response); a title, a path or a tag's name is written with `textContent`,
// never as markup.
//
// GROUPED (design answer, part one §5): "Pages", "Posts", "Tags", in that
// order, each a list named by its heading and left out when it is empty.
// A row carries its kind's mark -- a page's small card (`swatches.js`,
// drawn by the graph's renderer), a post's type dot, a tag's square -- and
// a page its ADDRESS under its title, in the small mono style: two pages
// may share a title. There is no fourth group: a row opens a local view,
// and a post type has none (the owner's decision of 2026-10-12).
//
// Keyboard: the results are real links placed right after the field, so Tab
// reaches the first one and Enter opens it -- no arrow-key handling of our own
// to keep in step with what is focused. Escape, from the field or from a
// result, closes the list; from a result the focus goes back to the field.
// A press outside the search closes it too, so it never lingers over the graph.
//
// Debounce, one request at a time and the stale-answer guard are
// `search/suggestions.js`'s, shared with the chip input and the link search.
//
// Announcing: the list stays plain lists of links, and what a screen reader
// should hear -- how many results arrived, "No page, post or tag matches.",
// the failure -- goes through the `role="status"` line beside it, which
// stays in the page. The same two sentences are drawn in the list for the
// eye, hidden from assistive technology so they are not read twice.
//
// Old rows never sit under newer text: the list is emptied the moment the text
// changes, and filled again by the answer to the new text.
import { createSuggestions } from "search/suggestions"
import { dotClass, TAG_MARK } from "mind_graph/card"
import { markCanvas, paintMarks } from "mind_graph/swatches"

const GROUPS = [ "page", "post", "tag" ]
const LINK = "flex items-center gap-2 rounded-cs px-2 py-1.5 text-sm text-ink hover:bg-sunken focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-accent"

export function attachSearch(field, list, { url, text, status, dotClasses }) {
  const block = list.parentElement
  const close = () => {
    list.hidden = true
    list.replaceChildren()
    status.textContent = ""
  }
  const say = (line) => {
    const item = document.createElement("li")
    item.className = "px-2 py-1.5 text-sm text-meta"
    item.setAttribute("aria-hidden", "true")
    item.textContent = line
    list.replaceChildren(item)
    list.hidden = false
    status.textContent = line
  }

  const suggestions = createSuggestions({
    url,
    getQuery: () => field.value.trim(),
    onRows: (_query, rows) => {
      if (rows.length === 0) return say(text.t("mind_graph.script.search.none"))

      const element = (tag, className, content) => {
        const created = document.createElement(tag)
        if (className) created.className = className
        if (content != null) created.textContent = content
        return created
      }
      const markOf = (row) => {
        if (row.kind === "page") return markCanvas(row)
        const mark = element("span", row.kind === "tag" ? TAG_MARK : dotClass(dotClasses, row))
        mark.setAttribute("aria-hidden", "true")
        return mark
      }
      const result = (row) => {
        const item = document.createElement("li")
        const link = element("a", LINK)
        link.href = row.url
        const words = element("span", "flex min-w-0 flex-col")
        words.append(element("span", "truncate", row.label))
        // A page's address under its title: two pages may share a title.
        if (row.kind === "page" && row.path) words.append(element("span", "truncate font-cs-mono text-label text-meta", row.path))
        link.append(markOf(row), words)
        item.append(link)
        return item
      }
      list.replaceChildren(...GROUPS.flatMap((kind) => {
        const found = rows.filter((row) => row.kind === kind)
        if (found.length === 0) return []

        const group = document.createElement("li")
        group.dataset.searchGroup = kind
        const heading = element("p", "m-0 px-2 pb-0.5 pt-1.5 font-cs-mono text-label uppercase tracking-mono text-meta", text.t(`mind_graph.script.search.groups.${kind}`))
        heading.id = `mind-graph-results-${kind}`
        const items = element("ul", "m-0 list-none p-0")
        items.setAttribute("role", "list")
        items.setAttribute("aria-labelledby", heading.id)
        items.append(...found.map(result))
        group.append(heading, items)
        return [ group ]
      }))
      list.hidden = false
      // Once the rows are shown: a canvas takes its colours from the page.
      paintMarks(list)
      status.textContent = text.t("mind_graph.script.search.count", { count: rows.length })
    },
    onError: () => say(text.t("mind_graph.script.search.failed"))
  })

  const input = () => {
    if (field.value.trim() === "") {
      suggestions.cancel()
      close()
    } else {
      close()
      suggestions.schedule()
    }
  }
  const keydown = (event) => {
    if (event.key !== "Escape") return
    event.preventDefault()
    suggestions.cancel()
    const inList = list.contains(document.activeElement)
    close()
    if (inList) field.focus()
  }
  const pressOutside = (event) => {
    if (list.hidden || field.contains(event.target) || list.contains(event.target)) return
    suggestions.cancel()
    close()
  }
  // Keyboard focus leaving the search block (Tab past the last result) closes
  // the list. A focusout with no next target (a click on a scrollbar, the
  // window losing focus) is left to `pressOutside`.
  const focusout = (event) => {
    if (!event.relatedTarget || block.contains(event.relatedTarget)) return
    suggestions.cancel()
    close()
  }
  field.addEventListener("input", input)
  block.addEventListener("focusout", focusout)
  field.addEventListener("keydown", keydown)
  list.addEventListener("keydown", keydown)
  document.addEventListener("pointerdown", pressOutside)

  return () => {
    suggestions.cancel()
    field.removeEventListener("input", input)
    block.removeEventListener("focusout", focusout)
    field.removeEventListener("keydown", keydown)
    list.removeEventListener("keydown", keydown)
    document.removeEventListener("pointerdown", pressOutside)
  }
}
