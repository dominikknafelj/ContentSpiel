import { Controller } from "@hotwired/stimulus"

// The suggestions while typing of the Search block and of a theme's own
// header search box (search 2 spec §4.5, §8.2; the SiteSearchSuggest card).
// A controller of the site's own, which a visitor's page alone registers
// (`PUBLIC_ONLY` in controllers/index.js): a theme that writes its own form
// keeps the suggestions by writing the same markup (the identifier on the
// `<form>`, the `url` and `unavailable` values, the `input`, `listbox`,
// `popup`, `message`, `option`, `status` and `loading` targets, and the
// option template's parts `[data-part="label"]`, `[data-part="kind"]` and
// optionally `[data-part="where"]`; docs/reference/theming.md, "Scripts").
//
// PROGRESSIVE ENHANCEMENT. The form is a plain GET to the search page and
// whole without this script. With no `url` value (the preview, a site with
// no search page) `connect` does nothing at all. Otherwise the field becomes
// an ARIA 1.2 combobox with a listbox popup: `role="combobox"`,
// `aria-autocomplete="list"`, `aria-expanded`, `aria-controls` naming the
// listbox and `autocomplete="off"` on the field, `role="listbox"` on the
// list. `aria-expanded` is "true" only while the listbox holds options and
// is shown: a message row (none, limited, unavailable) stands in the popup's
// frame, outside the listbox, and is no option.
//
// ASKING. From two characters, 150 ms after the last input, `POST` to the
// `url` value with `{ suggest, language }` (the prefix sliced to 100
// characters, the language the page's `<html lang>`), with no credentials
// and no referrer. A newer input aborts the request in flight, and an answer
// is drawn only when it is the newest asked AND the field still holds the
// prefix it was asked for, so a late answer never replaces a newer one.
// The last 20 answers are kept in memory for the field's life, never in any
// storage. After `limited` nothing is asked for 60 seconds. The listbox is
// `aria-busy` from an input that will be answered until its answer is drawn.
//
// STATES on the form, `data-search-suggest-state`, which a theme's
// stylesheet draws: `closed`, `loading` (only after 300 ms without an
// answer, so a quick answer never flickers; the last rows stay), `open`,
// `empty`, `limited` and `unavailable`.
//
// THE WORDS. `status` is the server's one sentence for a screen reader
// ("3 suggestions", "No suggestions. Press Enter to search.", the limited
// sentence), written into the polite live region and, for a message, into
// the message row. A network failure, an answer that is not the endpoint's
// JSON, `refused` (whose `status` is empty) and `unavailable` are the
// template's own words, the `unavailable` value: nothing else the server
// sends is ever drawn as a sentence.
//
// NOTHING IS WRITTEN AS HTML. Each option is a clone of the `option`
// template; its parts are filled with `textContent`, and each mark is a
// `<mark>` made with `document.createElement` between text nodes, from the
// answer's `[start, length]` ranges, which count characters (code points),
// as the server's do. A suggestion whose address is not this site's is
// not drawn.
//
// WHAT IS TAKEN BACK, AND WHEN. Turbo keeps a copy of a page and shows it
// again on Back. At `turbo:before-cache` and at `disconnect` everything this
// script wrote is taken back: the field's and the listbox's attributes (the
// field's own values before them restored), the options, the message, the
// live region, the loading word and the state (`closed`), so a copy never
// holds an open list. Turbo also copies a page that is NOT left (an anchor
// of it, `site.js`): the script then stays connected, and the field becomes
// a combobox again the moment it is focused or typed into.
//
// The elements are kept as fields at `connect`: a controller taken off its
// element finds no target any more, and `disconnect` has to reach them.
const DEBOUNCE = 150
const LOADING_AFTER = 300
const MIN_CHARACTERS = 2
const MAX_CHARACTERS = 100
const KEPT_ANSWERS = 20
const QUIET_AFTER_LIMITED = 60_000

// The field's attributes this script writes, with what it writes.
const FIELD = { role: "combobox", "aria-autocomplete": "list", "aria-expanded": "false", autocomplete: "off" }

// The states whose answer is drawn.
const DRAWN = [ "open", "empty", "limited", "unavailable" ]

export default class extends Controller {
  static targets = [ "input", "listbox", "popup", "message", "option", "status", "loading" ]
  static values = { url: String, unavailable: String }

  connect() {
    if (!this.urlValue) return

    this.field = this.inputTarget
    this.list = this.listboxTarget
    this.popup = this.popupTarget
    this.message = this.messageTarget
    this.template = this.optionTarget
    this.status = this.statusTarget
    this.loading = this.loadingTarget
    this.answers = new Map()
    this.items = []
    this.active = -1
    this.sequence = 0
    this.quietUntil = 0

    this.listen("input", this.field, () => this.typed())
    this.listen("keydown", this.field, (event) => this.key(event))
    this.listen("focus", this.field, () => this.arm())
    this.listen("mousedown", this.popup, (event) => event.preventDefault())
    this.listen("pointermove", this.popup, (event) => this.pointed(event))
    this.listen("click", this.popup, (event) => this.pressed(event))
    this.listen("pointerdown", document, (event) => { if (!this.field.contains(event.target) && !this.popup.contains(event.target)) this.close() })
    // The focus leaving the combobox any way (a screen reader's cursor, a
    // script's focus(), an access key) closes the list. A press on an option
    // never blurs the field: its `mousedown` is cancelled above.
    this.listen("focusout", this.field, (event) => { if (!this.popup.contains(event.relatedTarget)) this.close() })
    this.listen("turbo:before-cache", document, () => this.reset())

    this.live = true
    this.arm()
  }

  disconnect() {
    if (!this.live) return

    this.live = false
    this.listeners.forEach(([ type, target, handler ]) => target.removeEventListener(type, handler))
    this.listeners = []
    this.reset()
  }

  listen(type, target, handler) {
    this.listeners ||= []
    this.listeners.push([ type, target, handler ])
    target.addEventListener(type, handler)
  }

  // The combobox's attributes, the field's own values kept to put back.
  arm() {
    if (this.armed) return

    this.armed = true
    this.before = Object.fromEntries([ ...Object.keys(FIELD), "aria-controls", "aria-activedescendant" ].map((name) => [ name, this.field.getAttribute(name) ]))
    Object.entries(FIELD).forEach(([ name, value ]) => this.field.setAttribute(name, value))
    this.field.setAttribute("aria-controls", this.list.id)
    this.list.setAttribute("role", "listbox")
    this.state = "closed"
  }

  // Everything this script wrote, taken back.
  reset() {
    this.cancel()
    this.items = []
    this.active = -1
    this.list.replaceChildren()
    this.list.hidden = false
    this.list.removeAttribute("role")
    this.list.removeAttribute("aria-busy")
    this.popup.hidden = true
    this.message.hidden = true
    this.message.textContent = ""
    this.loading.hidden = true
    this.status.textContent = ""
    if (this.armed) {
      Object.entries(this.before).forEach(([ name, value ]) => value === null ? this.field.removeAttribute(name) : this.field.setAttribute(name, value))
    }
    this.armed = false
    this.element.removeAttribute("data-search-suggest-state")
    this.drawnFor = null
  }

  // The debounce, the request in flight and the loading timer, stopped; an
  // answer that still arrives is older than the newest sequence number.
  cancel() {
    clearTimeout(this.timer)
    clearTimeout(this.loadingTimer)
    this.request?.abort()
    this.request = null
    this.sequence += 1
  }

  set state(name) {
    this.element.setAttribute("data-search-suggest-state", name)
  }

  get state() {
    return this.element.getAttribute("data-search-suggest-state")
  }

  // The prefix the field holds now: trimmed, at most 100 characters.
  get prefix() {
    return Array.from(this.field.value.trim()).slice(0, MAX_CHARACTERS).join("")
  }

  typed() {
    this.arm()
    this.cancel()
    const prefix = this.prefix
    if (Array.from(prefix).length < MIN_CHARACTERS) {
      this.close()
      this.clear()
      return
    }
    // After `limited` the last row stays and nothing is asked.
    if (Date.now() < this.quietUntil) return

    this.list.setAttribute("aria-busy", "true")
    this.timer = setTimeout(() => this.ask(prefix), DEBOUNCE)
  }

  async ask(prefix) {
    const kept = this.answers.get(prefix)
    if (kept) return this.draw(kept, prefix)

    this.cancel()
    const sequence = this.sequence
    const request = this.request = new AbortController()
    this.loadingTimer = setTimeout(() => this.wait(), LOADING_AFTER)

    let answer = null
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Accept": "application/json" },
        body: JSON.stringify({ suggest: prefix, language: document.documentElement.lang }),
        credentials: "omit",
        referrerPolicy: "no-referrer",
        signal: request.signal
      })
      answer = await this.read(response)
    } catch (error) {
      if (request.signal.aborted) return
      answer = null
    }
    if (!this.live || sequence !== this.sequence) return

    clearTimeout(this.loadingTimer)
    this.request = null
    if (answer?.state === "ok") this.keep(prefix, answer)
    if (answer?.state === "limited") this.quietUntil = Date.now() + QUIET_AFTER_LIMITED
    this.draw(answer, prefix)
  }

  // The endpoint's JSON, or null for anything else.
  async read(response) {
    if (!(response.headers.get("Content-Type") || "").includes("application/json")) return null
    try {
      const answer = await response.json()
      return answer && typeof answer.state === "string" && Array.isArray(answer.suggestions) ? answer : null
    } catch (error) {
      return null
    }
  }

  keep(prefix, answer) {
    this.answers.delete(prefix)
    this.answers.set(prefix, answer)
    if (this.answers.size > KEPT_ANSWERS) this.answers.delete(this.answers.keys().next().value)
  }

  // Shown after 300 ms without an answer: the last rows stay, dimmed by
  // the stylesheet, and the loading word at the field's end.
  wait() {
    this.loading.hidden = false
    this.state = "loading"
  }

  draw(answer, prefix) {
    if (!this.live || !this.armed || this.prefix !== prefix) return

    this.list.removeAttribute("aria-busy")
    this.loading.hidden = true
    this.drawnFor = prefix
    const suggestions = answer?.state === "ok" ? answer.suggestions.filter((item) => typeof item?.label === "string" && this.address(item.url)) : []
    if (answer?.state === "ok" && suggestions.length > 0) return this.open(suggestions, answer.status)

    const state = answer?.state === "ok" ? "empty" : answer?.state === "limited" ? "limited" : "unavailable"
    const words = state === "unavailable" ? this.unavailableValue : this.sentence(answer.status)
    this.items = []
    this.active = -1
    this.list.replaceChildren()
    this.list.hidden = true
    this.message.textContent = words
    this.message.hidden = false
    this.popup.hidden = false
    this.field.setAttribute("aria-expanded", "false")
    this.field.removeAttribute("aria-activedescendant")
    this.status.textContent = words
    this.state = state
  }

  // The server's sentence, or the template's own words when it sent none.
  sentence(status) {
    return typeof status === "string" && status !== "" ? status : this.unavailableValue
  }

  open(suggestions, status) {
    this.items = suggestions
    this.active = -1
    let tags = 0
    this.list.replaceChildren(...suggestions.map((item, index) => this.option(item, index, item.kind === "tag" && tags++ === 0)))
    this.list.hidden = false
    this.message.hidden = true
    this.message.textContent = ""
    this.popup.hidden = false
    this.field.setAttribute("aria-expanded", "true")
    this.field.removeAttribute("aria-activedescendant")
    this.status.textContent = this.sentence(status)
    this.state = "open"
  }

  option(item, index, firstTag) {
    const option = this.template.content.firstElementChild.cloneNode(true)
    option.id = `${this.list.id}-${index}`
    option.setAttribute("role", "option")
    option.setAttribute("aria-selected", "false")
    if (firstTag) option.classList.add("search-suggest__option--first-tag")

    const label = option.querySelector("[data-part='label']")
    if (label) label.replaceChildren(...this.marked(item.label, item.marks))
    const kind = option.querySelector("[data-part='kind']")
    if (kind) kind.textContent = typeof item.kind_label === "string" ? item.kind_label : ""
    const where = option.querySelector("[data-part='where']")
    if (where && typeof item.where === "string" && item.where !== "") {
      where.textContent = item.where
    } else {
      where?.remove()
    }
    return option
  }

  // The label as text nodes with a `<mark>` for each range, in characters;
  // a range that overlaps the one before it, or leaves the label, is left out.
  marked(label, marks) {
    const characters = Array.from(label)
    const nodes = []
    let at = 0
    const ranges = (Array.isArray(marks) ? marks : [])
      .filter((mark) => Array.isArray(mark) && Number.isInteger(mark[0]) && Number.isInteger(mark[1]) && mark[1] > 0)
      .sort((a, b) => a[0] - b[0])
    for (const [ start, length ] of ranges) {
      if (start < at || start + length > characters.length) continue
      if (start > at) nodes.push(document.createTextNode(characters.slice(at, start).join("")))
      const mark = document.createElement("mark")
      mark.textContent = characters.slice(start, start + length).join("")
      nodes.push(mark)
      at = start + length
    }
    if (at < characters.length) nodes.push(document.createTextNode(characters.slice(at).join("")))
    return nodes
  }

  get options() {
    return Array.from(this.list.children).filter((element) => element.getAttribute("role") === "option")
  }

  get expanded() {
    return this.field.getAttribute("aria-expanded") === "true"
  }

  // The ARIA 1.2 combobox's keys; the caret stays in the field.
  key(event) {
    if (event.isComposing) return

    switch (event.key) {
      case "ArrowDown":
      case "ArrowUp":
        if (!this.reopen()) return
        event.preventDefault()
        this.move(event.key === "ArrowDown" ? 1 : -1)
        break
      case "Enter":
        if (!this.expanded || this.active < 0) return this.close()
        event.preventDefault()
        this.go(this.items[this.active].url)
        break
      case "Escape":
        // With the list closed, Escape is the browser's (it empties a search field).
        if (this.popup.hidden) return
        event.preventDefault()
        this.close()
        break
      case "Tab":
        this.close()
        break
    }
  }

  // Opens the list again on the options drawn for what the field holds;
  // answers whether there are options to move through.
  reopen() {
    if (this.expanded) return true
    if (this.items.length === 0 || this.drawnFor !== this.prefix) return false

    this.popup.hidden = false
    this.field.setAttribute("aria-expanded", "true")
    this.state = "open"
    return true
  }

  move(step) {
    const count = this.options.length
    const next = this.active < 0 ? (step > 0 ? 0 : count - 1) : (this.active + step + count) % count
    this.activate(next)
  }

  activate(index) {
    this.options.forEach((option, each) => option.setAttribute("aria-selected", each === index ? "true" : "false"))
    this.active = index
    const option = this.options[index]
    if (option) {
      this.field.setAttribute("aria-activedescendant", option.id)
      option.scrollIntoView({ block: "nearest" })
    } else {
      this.field.removeAttribute("aria-activedescendant")
    }
  }

  pointed(event) {
    const option = event.target.closest("[role='option']")
    const index = this.options.indexOf(option)
    if (index >= 0 && index !== this.active) this.activate(index)
  }

  pressed(event) {
    const index = this.options.indexOf(event.target.closest("[role='option']"))
    if (index < 0) return

    event.preventDefault()
    this.go(this.items[index].url)
  }

  // The popup hidden; the options stay, for Down to open them again.
  close() {
    if (!this.armed) return

    this.activate(-1)
    this.popup.hidden = true
    this.field.setAttribute("aria-expanded", "false")
    this.state = "closed"
  }

  // What was drawn, the options and the message, emptied.
  clear() {
    this.items = []
    this.drawnFor = null
    this.list.replaceChildren()
    this.list.removeAttribute("aria-busy")
    this.message.hidden = true
    this.message.textContent = ""
    this.loading.hidden = true
    this.status.textContent = ""
  }

  // To an address of this site only, by Turbo when it is on the page.
  // A suggestion's address as a URL of this site, or null: one that does
  // not parse or leads elsewhere is never drawn, so it is never followed.
  address(url) {
    if (typeof url !== "string") return null
    try {
      const address = new URL(url, window.location.href)
      return address.origin === window.location.origin ? address : null
    } catch (error) {
      return null
    }
  }

  go(url) {
    const address = this.address(url)
    if (!address) return

    this.close()
    if (window.Turbo) {
      window.Turbo.visit(address.href)
    } else {
      window.location.assign(address.href)
    }
  }
}
