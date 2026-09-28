import { Controller } from "@hotwired/stimulus"

// The post editor's related-posts picker (`Admin::RelatedPostsComponent`,
// design spec §6.1). Searches `<admin>/link_targets?type=post` (the URL
// arrives as a value, built server-side by the route helper) and keeps one
// hidden `post[related_post_ids][]` input per related post inside the post
// form, next to the component's always-present blank sentinel -- see that
// component's class comment for the contract. Adding or removing fires a
// bubbling `change` on this element, which the form's own `admin--autosave`
// already listens for, so the whole list saves the same way every other
// field does.
//
// The search box itself has no `name` (it's never submitted) and swallows
// its own `input`/`change`/Enter so typing a query doesn't queue an
// autosave or submit the form.
export default class extends Controller {
  static targets = ["list", "empty", "query", "results"]
  static values = { searchUrl: String, locale: String, postId: Number, name: String }

  disconnect() {
    clearTimeout(this.timer)
    this.aborter?.abort()
  }

  swallow(event) {
    event.stopPropagation()
    if (event.type === "keydown") event.preventDefault()
  }

  search(event) {
    event.stopPropagation()
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.fetchResults(this.queryTarget.value), 200)
  }

  async fetchResults(query) {
    this.aborter?.abort()
    this.aborter = new AbortController()

    const url = new URL(this.searchUrlValue, window.location.origin)
    url.searchParams.set("q", query)
    if (this.localeValue) url.searchParams.set("locale", this.localeValue)

    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, signal: this.aborter.signal })
      if (!response.ok) throw new Error(`link_targets answered ${response.status}`)
      this.showResults(await response.json())
    } catch (error) {
      if (error.name !== "AbortError") this.showMessage("Search failed — try again.")
    }
  }

  showResults(targets) {
    const chosen = this.chosenIds()
    const candidates = targets.filter((target) => target.type === "post" && target.id !== this.postIdValue && !chosen.has(target.id))

    if (candidates.length === 0) return this.showMessage("No matching posts.")

    this.resultsTarget.replaceChildren(...candidates.map((target) => {
      const item = document.createElement("li")
      item.setAttribute("role", "option")
      const button = document.createElement("button")
      button.type = "button"
      button.className = "block w-full px-3 py-1.5 text-left hover:bg-sunken"
      button.textContent = target.title || "Untitled"
      button.dataset.postId = target.id
      button.addEventListener("click", () => this.add(target))
      item.appendChild(button)
      return item
    }))
    this.open(true)
  }

  showMessage(message) {
    const item = document.createElement("li")
    item.className = "px-3 py-1.5 text-sm text-meta"
    item.textContent = message
    this.resultsTarget.replaceChildren(item)
    this.open(true)
  }

  open(isOpen) {
    this.resultsTarget.hidden = !isOpen
    this.queryTarget.setAttribute("aria-expanded", String(isOpen))
  }

  add(target) {
    if (this.chosenIds().has(target.id)) return

    const item = document.createElement("li")
    item.className = "flex items-center justify-between gap-2 rounded-cs border border-line px-3 py-1.5"
    item.dataset.postId = target.id

    const title = document.createElement("span")
    title.className = "truncate text-ink"
    title.textContent = target.title || "Untitled"

    const input = document.createElement("input")
    input.type = "hidden"
    input.name = this.nameValue
    input.value = target.id
    input.autocomplete = "off"

    const remove = document.createElement("button")
    remove.type = "button"
    remove.className = "text-sm text-meta underline hover:text-ink"
    remove.dataset.action = "admin--related-posts#remove"
    remove.textContent = "Remove"

    item.append(title, input, remove)
    this.listTarget.appendChild(item)

    this.queryTarget.value = ""
    this.open(false)
    this.changed()
  }

  remove(event) {
    event.target.closest("li")?.remove()
    this.changed()
  }

  chosenIds() {
    return new Set(Array.from(this.listTarget.querySelectorAll("li[data-post-id]"), (item) => Number(item.dataset.postId)))
  }

  changed() {
    this.emptyTarget.hidden = this.listTarget.children.length > 0
    this.element.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
