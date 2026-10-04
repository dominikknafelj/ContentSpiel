// A search box over pages and posts, shared by the editor's Link popover and
// the "Page link" dialog (design pass round 2, Task 13): both ask
// `Admin::LinkTargetsController` (`admin_link_targets_path`) for rows --
// `{ type, id, title, path, status, dot }` -- and show them in a listbox
// under a combobox input. It is the same search the chip input
// (`admin--chip-input`) runs for related posts, but that controller is
// welded to chips and hidden inputs in a form, which neither of these has:
// a pick here is a callback, never a value in a form. The row shape, the
// status wording ("Draft" / "Scheduled", live shows nothing) and the
// combobox pattern (`aria-activedescendant`, focus stays in the input, a
// mousedown on a row must not blur it) are the chip input's.
//
// Nothing here writes to a form: the input has no `name`, and the owner
// (popover or dialog) is outside the autosave form or stops `input`/`change`
// at its own root, so typing a query never queues a save.
//
// Every string reaches the DOM through `textContent`/attributes -- a title is
// data, never markup.
const DEBOUNCE_MS = 200

export const TEXTS = {
  hint: "Type to search titles",
  noResults: "No pages or posts match",
  searchFailed: "Search failed — check your connection"
}

let sequence = 0

// `input`      the combobox text input (gets role/aria wiring)
// `listbox`    an empty <ul> the rows go in
// `message`    an element for the hint / "No pages or posts match" / failure line
// `url`        the link-targets endpoint; `locale` the language titles are searched in
// `autoSelect` highlight the first row as soon as results arrive, so Enter picks it
// `skip(q)`    true for text that is not a title search (a pasted URL): no request, no rows
// `onPick(row)` called with the chosen row
export function createTargetSearch({ input, listbox, message, url, locale, autoSelect = false, skip = () => false, onPick }) {
  sequence += 1
  const prefix = `rich-text-target-${sequence}`
  let rows = []
  let active = -1
  let timer = null
  let aborter = null
  let counter = 0
  let destroyed = false

  listbox.id ||= `${prefix}-listbox`
  listbox.setAttribute("role", "listbox")
  input.setAttribute("role", "combobox")
  input.setAttribute("aria-autocomplete", "list")
  input.setAttribute("aria-controls", listbox.id)
  input.setAttribute("aria-expanded", "false")

  const say = (text) => { if (message) message.textContent = text || "" }

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

    if (row.status && row.status !== "live") {
      const status = document.createElement("span")
      status.className = "shrink-0 text-meta"
      status.textContent = `· ${row.status[0].toUpperCase()}${row.status.slice(1)}`
      item.append(status)
    }
    return item
  }

  async function fetchRows(query) {
    aborter?.abort()
    aborter = new AbortController()
    const mine = ++counter

    const endpoint = new URL(url, window.location.origin)
    endpoint.searchParams.set("q", query)
    endpoint.searchParams.set("locale", locale)

    let found
    try {
      const response = await fetch(endpoint, { headers: { Accept: "application/json" }, signal: aborter.signal })
      if (!response.ok) throw new Error(`link_targets answered ${response.status}`)
      found = await response.json()
    } catch (error) {
      // An older request failing must not replace what a newer one shows.
      if (error.name !== "AbortError" && mine === counter && !destroyed) { clear(); say(TEXTS.searchFailed) }
      return
    }
    // An answer for text no longer in the field, or one a newer request
    // superseded, is dropped rather than shown under the wrong query.
    if (destroyed || mine !== counter || input.value.trim() !== query) return
    render(found)
  }

  function search() {
    clearTimeout(timer)
    const query = input.value.trim()
    // Whatever was in flight is stale the moment the text changes.
    counter += 1
    aborter?.abort()
    if (query === "" || skip(query)) {
      clear()
      say(query === "" ? TEXTS.hint : "")
      return
    }
    timer = setTimeout(() => fetchRows(query), DEBOUNCE_MS)
  }

  function pick(index) {
    const row = rows[index]
    if (row) onPick(row)
  }

  // Returns true when the key was a combobox key and has been handled, so the
  // owner knows not to treat Enter as "apply the typed text".
  function keydown(event) {
    if (event.key === "ArrowDown" && rows.length) {
      event.preventDefault()
      highlight((active + 1) % rows.length)
      return true
    }
    if (event.key === "ArrowUp" && rows.length) {
      event.preventDefault()
      highlight((active - 1 + rows.length) % rows.length)
      return true
    }
    if (event.key === "Enter" && active >= 0) {
      // Stopped here as well: the popover's own Enter handler would otherwise
      // also run its primary action ("apply the typed text as a URL").
      event.preventDefault()
      event.stopPropagation()
      pick(active)
      return true
    }
    return false
  }

  // mousedown on a row must not move focus out of the input.
  listbox.addEventListener("mousedown", (event) => event.preventDefault())
  listbox.addEventListener("click", (event) => {
    const item = event.target.closest("[role=option]")
    if (item && listbox.contains(item)) pick(Array.from(listbox.children).indexOf(item))
  })
  input.addEventListener("input", search)
  input.addEventListener("keydown", keydown)

  clear()
  say(TEXTS.hint)

  return {
    keydown,
    search,
    // Back to the empty state (the dialog reopening, say).
    reset() {
      clearTimeout(timer)
      counter += 1
      aborter?.abort()
      clear()
      say(TEXTS.hint)
    },
    destroy() {
      destroyed = true
      clearTimeout(timer)
      aborter?.abort()
      input.removeEventListener("input", search)
      input.removeEventListener("keydown", keydown)
    }
  }
}
