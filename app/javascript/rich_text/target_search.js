import { createSuggestions, statusLabel, TEXTS as SEARCH_TEXTS } from "search/suggestions"

// A search box over pages and posts, shared by the editor's Link popover and
// the "Page link" dialog (design pass round 2, Task 13): both ask
// `Admin::LinkTargetsController` (`admin_link_targets_path`) for rows --
// `{ type, id, title, path, status, dot }` -- and show them in a listbox
// under a combobox input. The search core is the chip input's own
// (`search/suggestions`); a pick here is a callback, never a value in a
// form. The row shape, the status wording ("Draft" / "Scheduled", live shows
// nothing) and the combobox pattern (`aria-activedescendant`, focus stays in
// the input, a mousedown on a row must not blur it) are the chip input's.
//
// Nothing here writes to a form: the input has no `name`, and the owner
// (popover or dialog) is outside the autosave form or stops `input`/`change`
// at its own root, so typing a query never queues a save.
//
// The fetch / debounce / abort / stale-answer logic and the status wording
// are `search/suggestions`, the same module the chip input runs on; this file
// is only the rendering and the combobox keys.
//
// Every string reaches the DOM through `textContent`/attributes -- a title is
// data, never markup.
export const TEXTS = {
  hint: "Type to search titles",
  noResults: "No pages or posts match",
  searchFailed: SEARCH_TEXTS.searchFailed
}

let sequence = 0

// `input`      the combobox text input (gets role/aria wiring)
// `listbox`    an empty <ul> the rows go in (may be a persistent element)
// `message`    an element for the hint / "No pages or posts match" / failure line
// `url`        the link-targets endpoint; `locale` the language titles are searched in
// `autoSelect` highlight the first row as soon as results arrive, so Enter picks it
// `skip(q)`    true for text that is not a title search (a pasted URL): no request, no rows
// `onPick(row)` called with the chosen row
//
// Every listener is registered with one AbortController signal, so `destroy()`
// removes them all -- a dialog that creates a new search on every open
// against the same list element never accumulates old ones.
export function createTargetSearch({ input, listbox, message, url, locale, autoSelect = false, skip = () => false, onPick }) {
  sequence += 1
  const prefix = `rich-text-target-${sequence}`
  const lifetime = new AbortController()
  const { signal } = lifetime
  let rows = []
  let active = -1

  listbox.id ||= `${prefix}-listbox`
  listbox.setAttribute("role", "listbox")
  input.setAttribute("role", "combobox")
  input.setAttribute("aria-autocomplete", "list")
  input.setAttribute("aria-controls", listbox.id)
  input.setAttribute("aria-expanded", "false")

  const say = (text) => { if (message) message.textContent = text || "" }

  const suggestions = createSuggestions({
    url,
    params: () => ({ locale }),
    getQuery: () => input.value.trim(),
    onRows: (_query, found) => render(found),
    onError: () => { clear(); say(TEXTS.searchFailed) }
  })

  function highlight(index) {
    active = index
    Array.from(listbox.children).forEach((item, position) => item.setAttribute("aria-selected", position === index ? "true" : "false"))
    const item = listbox.children[index]
    if (item) {
      input.setAttribute("aria-activedescendant", item.id)
      item.scrollIntoView?.({ block: "nearest" })
    } else {
      input.removeAttribute("aria-activedescendant")
    }
  }

  function clear() {
    rows = []
    listbox.replaceChildren()
    listbox.hidden = true
    input.setAttribute("aria-expanded", "false")
    highlight(-1)
  }

  function render(found) {
    rows = found
    listbox.replaceChildren(...found.map((row, index) => rowItem(row, index)))
    listbox.hidden = found.length === 0
    input.setAttribute("aria-expanded", found.length ? "true" : "false")
    say(found.length ? "" : TEXTS.noResults)
    highlight(autoSelect && found.length ? 0 : -1)
  }

  function rowItem(row, index) {
    const item = document.createElement("li")
    item.id = `${prefix}-option-${index}`
    item.setAttribute("role", "option")
    item.setAttribute("aria-selected", "false")
    item.className = "flex cursor-pointer items-center gap-2 rounded-cs px-2 py-1.5 text-sm text-ink hover:bg-sunken aria-selected:bg-accent-tint"

    if (row.dot) {
      const dot = document.createElement("span")
      dot.className = `h-[7px] w-[7px] shrink-0 rounded-full ${row.dot}`
      dot.setAttribute("aria-hidden", "true")
      item.append(dot)
    }

    const title = document.createElement("span")
    title.className = "min-w-0 flex-1 truncate"
    title.textContent = row.title || `(untitled ${row.type} #${row.id})`
    item.append(title)

    const where = document.createElement("span")
    where.className = "shrink-0 font-cs-mono text-label text-meta"
    where.textContent = [ row.type === "post" ? "Post" : "Page", row.path ].filter(Boolean).join(" · ")
    item.append(where)

    const status = statusLabel(row)
    if (status) {
      const label = document.createElement("span")
      label.className = "shrink-0 text-meta"
      label.textContent = `· ${status}`
      item.append(label)
    }
    return item
  }

  function search() {
    // Whatever was in flight is stale the moment the text changes.
    suggestions.cancel()
    const query = input.value.trim()
    if (query === "" || skip(query)) {
      clear()
      say(query === "" ? TEXTS.hint : "")
      return
    }
    suggestions.schedule()
  }

  function pick(index) {
    const row = rows[index]
    if (row) onPick(row)
  }

  function keydown(event) {
    if (event.key === "ArrowDown" && rows.length) {
      event.preventDefault()
      highlight((active + 1) % rows.length)
    } else if (event.key === "ArrowUp" && rows.length) {
      event.preventDefault()
      highlight((active - 1 + rows.length) % rows.length)
    } else if (event.key === "Enter" && active >= 0) {
      // Stopped here as well: the popover's own Enter handler would otherwise
      // also run its primary action ("apply the typed text as a URL").
      event.preventDefault()
      event.stopPropagation()
      pick(active)
    } else if (event.key === "Escape" && (!listbox.hidden || suggestions.inFlight)) {
      // The first Escape closes the list (and cancels a search on its way);
      // only a second one reaches the popover or dialog and closes it.
      event.preventDefault()
      event.stopPropagation()
      suggestions.cancel()
      clear()
      say("")
    }
  }

  // mousedown on a row must not move focus out of the input.
  listbox.addEventListener("mousedown", (event) => event.preventDefault(), { signal })
  listbox.addEventListener("click", (event) => {
    const item = event.target.closest("[role=option]")
    if (item && listbox.contains(item)) pick(Array.from(listbox.children).indexOf(item))
  }, { signal })
  input.addEventListener("input", search, { signal })
  input.addEventListener("keydown", keydown, { signal })

  clear()
  say(TEXTS.hint)

  return {
    destroy() {
      lifetime.abort()
      suggestions.destroy()
      clear()
      say("")
    }
  }
}
