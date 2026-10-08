// The mind graph's search field (mind graph canvas spec §5.5): readable posts
// and tags by name, each row a LINK to that row's local view -- so a result is
// opened like any other link, by click, Enter or a new tab, and Back returns.
// The script never navigates by itself, and a row's URL is the server's
// (`href` from the response); a title or tag name is written with
// `textContent`, never as markup.
//
// Keyboard: the results are real links placed right after the field, so Tab
// reaches the first one and Enter opens it -- no arrow-key handling of our own
// to keep in step with what is focused. Escape, from the field or from a
// result, closes the list; from a result the focus goes back to the field.
// A press outside the search closes it too, so it never lingers over the graph.
//
// Debounce, one request at a time and the stale-answer guard are
// `search/suggestions.js`'s, shared with the chip input and the link search.
import { createSuggestions } from "search/suggestions"

//
// Announcing: the list stays a plain list of links, and what a screen reader
// should hear -- how many results arrived, "No post or tag matches.", the
// failure -- goes through the `role="status"` line beside it, which stays in
// the page. The same two sentences are drawn in the list for the eye, hidden
// from assistive technology so they are not read twice.
//
// Old rows never sit under newer text: the list is emptied the moment the text
// changes, and filled again by the answer to the new text.
const KIND_KEYS = {
  post: "mind_graph.script.search.post",
  tag: "mind_graph.script.search.tag"
}

export function attachSearch(field, list, { url, text, status }) {
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

      list.replaceChildren(...rows.map((row) => {
        const item = document.createElement("li")
        const link = document.createElement("a")
        link.href = row.url
        link.className = "flex items-baseline justify-between gap-3 rounded-cs px-2 py-1.5 text-sm text-ink hover:bg-sunken focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-accent"
        const label = document.createElement("span")
        label.textContent = row.label
        const kind = document.createElement("span")
        kind.className = "shrink-0 text-label text-meta"
        kind.textContent = text.t(KIND_KEYS[row.kind])
        link.append(label, kind)
        item.append(link)
        return item
      }))
      list.hidden = false
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
