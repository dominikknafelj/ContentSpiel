import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"

// A note's field (notes spec §4.2, §7 "Unsent text"), on the form
// `Admin::NotesScreen::ComposerComponent` draws.
//
// - Enter adds a line; Ctrl/⌘+Enter sends the form.
// - Ctrl/⌘+Enter sends ONCE: a held key (`event.repeat`) and a second press
//   while the first submit is still out are ignored, and the submit button is
//   disabled for as long, or the same note would be saved twice.
// - What is typed is kept per person and per form (`user`, `key`) in
//   `sessionStorage` -- which belongs to the tab, so without the person in the
//   key the next one to sign in there would get this one's unsent text -- and put back
//   when the form is drawn again: the drawer is closed and reopened, the frame
//   is fetched again, the screen is left and come back to. It is dropped when
//   the form's own submit succeeds. Unsent note text never raises the leave
//   guard, which is about content.
// - AN EDIT THAT WAS LEFT (the handoff's decision 27; `edit`). An edit form
//   opens filled with the saved text, so "put back into an empty field"
//   never applied to it and its draft was stored and then lost. For an edit
//   the draft is what differs from the text the form was drawn with: typing
//   that text back removes it, and a form drawn while one exists gets the
//   draft IN PLACE of the saved text, with "Unsaved edit" above the field
//   (`unsaved`). That goes for a draft older than the saved text too (the
//   author saved a newer one from another tab): it is their own words, so it
//   is put back and said, never dropped in silence and never kept in
//   silence -- Cancel shows the newer text. Saving forgets the draft here
//   (`sent`); Cancel is a link beside the form, and `admin--note-unsaved`, on
//   the message, forgets it there and says "Unsaved edit" on the message
//   while its form is closed. Both read the one key (`draftKey`).
// - "@" opens the mention picker (six rows at most): the people who may read
//   this record, from the server (`mentionsUrl`). The field shows "@Dana
//   Smith"; the hidden `mention_names` field carries name -> id for the server
//   to turn into tokens. A name the picker did not insert is just text.
// - An emoji button puts its character in at the caret.
// - The submit is disabled while the field is empty. The server draws it
//   enabled (without this script the field's own `required` says so), and a
//   draft put back on connect enables it again.
//
// Text goes into the page with `textContent` only: a name is a person's.
const QUERY = /(?:^|\s)@([^\s@]{0,40})$/
const PREFIX = "cs-note-draft:"

// The one place a draft's key is made: `cs-note-draft:<user id>:<form key>`,
// the form key being "new", "thread-<id>" or, for an edit, "message-<id>".
export const draftKey = (user, key) => `${PREFIX}${user}:${key}`
const ROWS = 6
// A lookup waits for a pause in the typing, not for every letter.
const LOOKUP_DELAY_MS = 150

export default class extends Controller {
  static targets = [ "field", "names", "suggestions", "status", "emoji", "submit", "unsaved" ]
  static values = { key: String, mentionsUrl: String, user: String, edit: Boolean }

  connect() {
    this.names = this.parse(this.namesTarget.value)
    // What the form was drawn with: for an edit, the text a draft is measured against.
    this.drawn = this.fieldTarget.value
    const draft = this.stored()
    if (draft && (this.editValue ? draft.body !== this.drawn : !this.drawn)) {
      this.fieldTarget.value = draft.body
      this.names = { ...draft.names, ...this.names }
      this.namesTarget.value = JSON.stringify(this.names)
      if (this.hasUnsavedTarget) this.unsavedTarget.hidden = false
    }
    this.refresh()
  }

  disconnect() {
    clearTimeout(this.lookupTimer)
    this.aborter?.abort()
  }

  typed() {
    this.store()
    this.refresh()
    this.scheduleLookUp()
  }

  refresh() {
    if (this.hasSubmitTarget) this.submitTarget.disabled = this.out || this.fieldTarget.value.trim() === ""
  }

  key(event) {
    if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
      event.preventDefault()
      if (event.repeat || this.out) return

      this.closeSuggestions()
      // Marked out here, not only on `turbo:submit-start`: a second press in
      // the same task comes before anything of the first has started. An
      // invalid form submits nothing, so it marks nothing.
      if (this.element.checkValidity()) this.sending()
      this.element.requestSubmit()
      return
    }
    if (this.suggestionsTarget.hidden) return

    if (event.key === "Escape") {
      // The picker's Escape, not the drawer's.
      event.preventDefault()
      event.stopPropagation()
      this.closeSuggestions()
    } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      this.move(event.key === "ArrowDown" ? 1 : -1)
    } else if (event.key === "Enter" || event.key === "Tab") {
      const option = this.options[this.index]
      if (!option) return
      event.preventDefault()
      this.pick(option)
    }
  }

  // The list goes when the field loses the focus -- unless the focus went
  // into the list (a pointer press on a row).
  left(event) {
    if (!this.suggestionsTarget.contains(event.relatedTarget)) this.closeSuggestions()
  }

  // A pointer press on a row. Prevented, so the field keeps the focus and the
  // caret stays where the name goes.
  choose(event) {
    event.preventDefault()
    this.pick(event.currentTarget)
  }

  emoji(event) {
    this.insert(event.currentTarget.dataset.emoji, this.fieldTarget.selectionStart, this.fieldTarget.selectionEnd)
    this.emojiTarget.open = false
    this.store()
    this.refresh()
  }

  // The toolbar's at-sign button (handoff "Mention picker"): the same as
  // typing "@" at the caret, with a space before it when a word ends there.
  mention() {
    const field = this.fieldTarget
    const at = /(?:^|\s)$/.test(field.value.slice(0, field.selectionStart)) ? "@" : " @"
    this.insert(at, field.selectionStart, field.selectionEnd)
    this.typed()
  }

  // `turbo:submit-start` on the form (a press on the button comes this way):
  // a submit is out until its `turbo:submit-end`.
  sending() {
    this.out = true
    this.refresh()
  }

  // `turbo:submit-end` on the form: a note that went through leaves no draft.
  sent(event) {
    this.out = false
    this.refresh()
    if (event.detail.success) this.forget()
  }

  // --- the mention picker -----------------------------------------------------

  // What is being looked for: the text after an "@" that ends at the caret,
  // "" for a bare "@", null when the caret is not in a mention.
  get query() {
    const typed = this.fieldTarget.value.slice(0, this.fieldTarget.selectionStart).match(QUERY)
    return typed ? typed[1] : null
  }

  // No mention at the caret closes the list at once; a lookup waits
  // `LOOKUP_DELAY_MS` for the typing to pause, and each letter starts the
  // wait again.
  scheduleLookUp() {
    clearTimeout(this.lookupTimer)
    this.aborter?.abort()
    if (this.query == null || !this.mentionsUrlValue) return this.closeSuggestions()

    this.lookupTimer = setTimeout(() => this.lookUp(), LOOKUP_DELAY_MS)
  }

  async lookUp() {
    const query = this.query
    this.aborter?.abort()
    if (query == null || !this.mentionsUrlValue) return this.closeSuggestions()

    this.aborter = new AbortController()
    try {
      const url = new URL(this.mentionsUrlValue, window.location.origin)
      url.searchParams.set("q", query)
      const response = await fetch(url, { headers: { Accept: "application/json" }, signal: this.aborter.signal })
      if (!response.ok) return this.closeSuggestions()
      const people = await response.json()
      // An answer for what is no longer being asked (the text moved on while
      // it was on its way) is dropped: the lookup for the new text shows.
      if (this.query !== query) return
      this.show(people)
    } catch (error) {
      if (error.name !== "AbortError") this.closeSuggestions()
    }
  }

  show(people) {
    const text = messages(this.element)
    people = people.slice(0, ROWS)
    this.suggestionsTarget.replaceChildren(...people.map((person, index) => {
      const option = document.createElement("li")
      option.setAttribute("role", "option")
      option.id = `${this.fieldTarget.id}-person-${index}`
      option.dataset.id = person.id
      option.dataset.label = person.label
      option.dataset.action = "mousedown->admin--note-composer#choose"
      option.className = "flex cursor-pointer items-center gap-2 rounded-cs px-2 py-1.5 hover:bg-sunken aria-selected:bg-sunken"
      // The avatar is decoration, as everywhere (`Admin::NotesScreen::AvatarComponent`):
      // the first letters of the first two words of the name beside it.
      const avatar = document.createElement("span")
      avatar.setAttribute("aria-hidden", "true")
      avatar.className = "flex size-[22px] shrink-0 items-center justify-center rounded-full border border-line-strong bg-sunken font-cs-mono text-[8px] font-medium uppercase leading-none text-ink"
      avatar.textContent = String(person.label).split(/\s+/).filter(Boolean).slice(0, 2).map((word) => [ ...word ][0]).join("")
      const name = document.createElement("span")
      name.className = "truncate text-[13px] text-ink"
      name.textContent = person.label
      option.append(avatar, name)
      if (person.hint) {
        const hint = document.createElement("span")
        hint.className = "truncate text-[11px] text-meta"
        hint.textContent = person.hint
        option.append(hint)
      }
      return option
    }))
    this.suggestionsTarget.hidden = people.length === 0
    this.statusTarget.textContent = people.length === 0 ? text.t("notes.script.mentions.none") : text.t("notes.script.mentions.count", { count: people.length })
    this.index = -1
    if (people.length > 0) this.move(1)
  }

  get options() {
    return [ ...this.suggestionsTarget.children ]
  }

  move(step) {
    const options = this.options
    if (options.length === 0) return
    this.index = (this.index + step + options.length) % options.length
    options.forEach((option, index) => option.setAttribute("aria-selected", index === this.index ? "true" : "false"))
    this.fieldTarget.setAttribute("aria-activedescendant", options[this.index].id)
  }

  // "@que" before the caret becomes "@Label ", and the name is remembered.
  pick(option) {
    // Read again from the field, not kept from the lookup: a letter typed
    // while the list was on its way is part of what the name replaces.
    const caret = this.fieldTarget.selectionStart
    const typed = this.fieldTarget.value.slice(0, caret).match(QUERY)
    const start = typed ? caret - typed[1].length - 1 : caret
    this.names[option.dataset.label] = Number(option.dataset.id)
    this.namesTarget.value = JSON.stringify(this.names)
    this.insert(`@${option.dataset.label} `, start, caret)
    this.closeSuggestions()
    this.store()
  }

  closeSuggestions() {
    this.suggestionsTarget.hidden = true
    this.suggestionsTarget.replaceChildren()
    this.fieldTarget.removeAttribute("aria-activedescendant")
    this.statusTarget.textContent = ""
    this.index = -1
  }

  insert(text, from, to) {
    const field = this.fieldTarget
    field.value = field.value.slice(0, from) + text + field.value.slice(to)
    const caret = from + text.length
    field.focus()
    field.setSelectionRange(caret, caret)
  }

  // --- the draft --------------------------------------------------------------
  // `sessionStorage` can be absent or full (private windows): a draft is a
  // convenience, so every failure is the same as having none.

  get storageKey() {
    return draftKey(this.userValue, this.keyValue)
  }

  stored() {
    try {
      const draft = this.parse(window.sessionStorage.getItem(this.storageKey))
      return typeof draft.body === "string" && draft.body ? { body: draft.body, names: draft.names || {} } : null
    } catch {
      return null
    }
  }

  store() {
    try {
      const value = this.fieldTarget.value
      if (value && !(this.editValue && value === this.drawn)) window.sessionStorage.setItem(this.storageKey, JSON.stringify({ body: value, names: this.names }))
      else window.sessionStorage.removeItem(this.storageKey)
    } catch {
      // Nothing to do: the text is still in the field.
    }
  }

  forget() {
    try {
      window.sessionStorage.removeItem(this.storageKey)
    } catch {
      // As above.
    }
  }

  parse(source) {
    try {
      const value = JSON.parse(source || "{}")
      return value && typeof value === "object" && !Array.isArray(value) ? value : {}
    } catch {
      return {}
    }
  }
}
