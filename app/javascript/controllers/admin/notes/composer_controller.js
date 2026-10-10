import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"

// A note's field (notes spec §4.2, §7 "Unsent text"), on the form
// `Admin::NotesScreen::ComposerComponent` draws.
//
// - Enter adds a line; Ctrl/⌘+Enter sends the form.
// - Ctrl/⌘+Enter sends ONCE: a held key (`event.repeat`) and a second press
//   while the first submit is still out are ignored, and the submit button is
//   disabled for as long, or the same note would be saved twice. The field
//   is read-only for as long too, so nothing typed after Send is lost
//   (`sending`).
// - What is typed is kept per person and per form (`user`, `key`) in
//   `sessionStorage` -- which belongs to the tab, so without the person in the
//   key the next one to sign in there would get this one's unsent text -- and put back
//   when the form is drawn again: the drawer is closed and reopened, the frame
//   is fetched again, the screen is left and come back to. It is dropped when
//   the form's own submit succeeds. Unsent note text never raises the leave
//   guard, which is about content. It does not outlive the person either:
//   signing out removes every draft from the tab, and a page loaded for
//   someone else removes what is not theirs (`forgetDrafts`).
// - AN EDIT THAT WAS LEFT (the handoff's decision 27; `edit`). An edit form
//   opens filled with the saved text, so "put back into an empty field"
//   never applied to it and its draft was stored and then lost. For an edit
//   the draft is what differs from the text the form was drawn with: typing
//   that text back removes it, and a form drawn while one exists gets the
//   draft IN PLACE of the saved text; that it is unsaved is said in the
//   message's meta line (`admin--notes--unsaved`), never above the field
//   (decision 29). That goes for a draft older than the saved text too (the
//   author saved a newer one from another tab): it is their own words, so it
//   is put back and said, never dropped in silence and never kept in
//   silence -- Cancel shows the newer text. Saving forgets the draft here
//   (`sent`); Cancel is a link beside the form, and `admin--notes--unsaved`, on
//   the message, forgets it there and says "Unsaved edit" on the message
//   while its form is closed. Both read the one key (`draftKey`).
// - "@" opens the mention picker (six rows at most): the people who may read
//   this record, from the server (`mentionsUrl`). The field shows "@Dana
//   Smith"; the hidden `mention_names` field carries name -> id for the server
//   to turn into tokens. A name the picker did not insert is just text.
// - An emoji button puts its character in at the caret.
// - The send key is said by the submit button's tooltip and its
//   `aria-keyshortcuts` (decision 30). The server writes the Ctrl form;
//   on an Apple platform it is written again here: "Send (⌘↵)", `Meta+Enter`.
// - The submit is disabled while the field is empty. The server draws it
//   enabled (without this script the field's own `required` says so), and a
//   draft put back on connect enables it again.
//
// - FILES (notes spec §3.6; `files`, on every form but an edit's). The
//   paperclip opens the form's one file field, and what is chosen travels
//   with the note as one multipart post. The chosen files are the file
//   field's own -- a `DataTransfer` rebuilds its list when one is added or
//   removed, so several rounds of choosing add up -- and the rows above the
//   field only show them, each cloned from the server's `<template>` with a
//   remove button. A sixth file, and one over the limit, are refused here in
//   a line under the rows, before anything is sent; the server checks the
//   same again, and what a file IS only the server can tell. A DRAFT HOLDS
//   TEXT, AND THE NAMES OF THE FILES CHOSEN WITH IT: a script cannot put a
//   file back into a file field, so chosen files are gone when the form is
//   drawn again. A draft that comes back therefore says so above the field
//   (`lost`, the handoff's decision 33): "Choose the files again:
//   press-kit.pdf, about.png". After a note that was refused the server
//   draws the same line with the names it was just sent. The line goes, and
//   the names with it, once files are chosen or the note is sent. While a note
//   with files is on its way the one-send guard holds for as long as the
//   upload takes: `out` is set at the press and cleared at
//   `turbo:submit-end`, however long that is.
//
// Text goes into the page with `textContent` only: a name is a person's,
// and a file's name is whatever its owner called it.
const QUERY = /(?:^|\s)@([^\s@]{0,40})$/
const PREFIX = "cs-note-draft:"

// The one place a draft's key is made: `cs-note-draft:<user id>:<form key>`,
// the form key being `new-<container key>-<subject key>` for a new note (the
// subject's is empty for the record itself: "new-Page-3-",
// "new-Page-3-ContentBlock-12"), "thread-<id>" for a reply, "message-<id>"
// for an edit and, in the mind graph's card, "graph-Post-<id>".
export const draftKey = (user, key) => `${PREFIX}${user}:${key}`

// Every note draft of this tab is removed, except those of `person` (with no
// person: all of them). `sessionStorage` belongs to the TAB and outlives the
// session: the person in the key keeps the next one's forms from showing the
// last one's text, but the text, and the names of the files chosen with it,
// would stay readable in the tab until it is closed -- and a note's text is
// kept out of every log for a reason. So `admin--notes--live` calls this when
// the person signs out (all), and when a page loads for someone (all but
// theirs: a session can end without the button). A draft is a convenience;
// a failure here is the same as having none.
export function forgetDrafts(person = null) {
  try {
    const own = person ? draftKey(person, "") : null
    Object.keys(window.sessionStorage)
      .filter((name) => name.startsWith(PREFIX) && !(own && name.startsWith(own)))
      .forEach((name) => window.sessionStorage.removeItem(name))
  } catch {
    // Nothing to forget.
  }
}
const APPLE = /mac|iphone|ipad|ipod/i
const ROWS = 6
// A lookup waits for a pause in the typing, not for every letter.
const LOOKUP_DELAY_MS = 150
// How long a send must be out before the form says so (decision 41): a send
// that is answered sooner shows nothing, so the state never flashes.
const SENDING_AFTER_MS = 300

export default class extends Controller {
  static targets = [ "field", "names", "suggestions", "status", "emoji", "submit", "files", "chosen", "fileError", "row", "lost", "tool" ]
  static values = { key: String, mentionsUrl: String, user: String, edit: Boolean, saved: String }

  connect() {
    // A form that is not sending carries nothing of a send. It can: Turbo's
    // snapshot of a record's notes page, taken while a note was on its way,
    // holds the field read-only and "Sending…", and Back would hand that to
    // a controller that knows of no send. (A form that IS sending and was
    // only moved keeps its state: `out` is this controller's, and it is the
    // same controller.)
    if (!this.out) this.settled()
    this.names = this.parse(this.namesTarget.value)
    // What the SERVER drew the form with: for an edit, the saved text a draft
    // is measured against. The field's `defaultValue`, never its `value`:
    // this runs again whenever the element is MOVED (an open edit is moved
    // into the thread's new messages part by every live refresh and every
    // merged answer, `admin--notes--live#redrawThread`), and a baseline read
    // from `value` there was the text typed so far -- from then on the edit
    // looked unchanged, its draft was removed by the next keystroke that
    // left the field as it was, and "Unsaved edit" no longer protected it.
    //
    // One form is drawn with something else in its field: an edit that was
    // REFUSED comes back holding the refused text. The server then hands the
    // saved text beside it (`saved`), or that typed text would be the
    // baseline in the same way.
    this.drawn = this.hasSavedValue ? this.savedValue : this.fieldTarget.defaultValue
    // The files a form drawn again no longer holds: the server's, after a refusal.
    this.lost = this.hasLostTarget ? this.list(this.lostTarget.dataset.names) : []
    const draft = this.stored()
    // A draft is put back into a field as the server drew it, never over one
    // that already holds typing (the moved element again: what is in the
    // field is newer than anything stored).
    const untouched = this.fieldTarget.value === this.fieldTarget.defaultValue
    if (draft && untouched && (this.editValue ? draft.body !== this.drawn : !this.drawn)) {
      this.fieldTarget.value = draft.body
      this.names = { ...draft.names, ...this.names }
      this.namesTarget.value = JSON.stringify(this.names)
      if (draft.files.length > 0) this.lost = draft.files
    } else if (!this.editValue && untouched && this.drawn && !draft) {
      // A new note or a reply the server drew WITH text and that has no
      // draft: the reply to a thread that went, handed back in the list's
      // new-note field (`Admin::NoteContainer#reply_gone!`), whose draft is
      // under the thread's key. It is this form's draft from now on, or
      // closing the drawer would lose it.
      this.store()
    }
    this.sayLost()
    if (this.hasSubmitTarget && APPLE.test(navigator.userAgentData?.platform || navigator.platform || "")) {
      this.submitTarget.title = messages(this.element).t("notes.script.send_apple")
      this.submitTarget.setAttribute("aria-keyshortcuts", "Meta+Enter")
    }
    this.refresh()
  }

  disconnect() {
    clearTimeout(this.sendingTimer)
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
      // No button to send with, no send: the form of a thread that is gone
      // has its submit taken away (`admin--notes--live#gone`), and a note
      // marked "out" that nothing sends would leave its field read-only.
      if (event.repeat || this.out || !this.hasSubmitTarget) return

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
    if (this.out) return
    this.insert(event.currentTarget.dataset.emoji, this.fieldTarget.selectionStart, this.fieldTarget.selectionEnd)
    this.emojiTarget.open = false
    this.store()
    this.refresh()
  }

  // The toolbar's at-sign button (handoff "Mention picker"): the same as
  // typing "@" at the caret, with a space before it when a word ends there.
  mention() {
    if (this.out) return
    const field = this.fieldTarget
    const at = /(?:^|\s)$/.test(field.value.slice(0, field.selectionStart)) ? "@" : " @"
    this.insert(at, field.selectionStart, field.selectionEnd)
    this.typed()
  }

  // `submit` and `turbo:submit-start` on the form (a press on the button
  // comes this way): a submit is out until its `turbo:submit-end`.
  //
  // THE FIELD IS READ-ONLY FOR AS LONG. Turbo took the form's data at the
  // press, and the answer replaces the form with an empty one and forgets
  // the draft: whatever was typed in between was in neither, and was lost.
  // That window is as long as a file's upload, and as long as the write
  // queue holds the note behind an autosave -- which is BEFORE Turbo says
  // `turbo:submit-start`, hence `submit` too. The text stays in view; the
  // emoji, the at-sign and the paperclip do nothing meanwhile. (Read-only,
  // not disabled: a disabled field is left out of the form's data when Turbo
  // builds the request, and loses the focus.)
  //
  // WHAT IT LOOKS LIKE (the handoff's decision 41), once the send has been
  // out for `SENDING_AFTER_MS`: the field's text dim, the submit reading
  // "Sending…" with `aria-busy` (it is disabled already, with the button's
  // own disabled look), and the paperclip, emoji and at-sign disabled (the
  // emoji set is a <details>: `inert`, its <summary> `aria-disabled` with
  // the same look as the other two, decision 45). No
  // spinner. All of it is taken back in one place (`settled`), on every way
  // a send ends -- `turbo:submit-end` follows an answer of any status, a
  // network error and an aborted or stopped submission alike -- and when a
  // form connects that is not sending.
  sending() {
    if (this.out) return
    this.out = true
    this.fieldTarget.readOnly = true
    this.refresh()
    clearTimeout(this.sendingTimer)
    this.sendingTimer = setTimeout(() => { if (this.out) this.saySending() }, SENDING_AFTER_MS)
  }

  saySending() {
    this.fieldTarget.classList.replace("text-ink", "text-dim")
    this.toolTargets.forEach((tool) => { tool.disabled = true })
    this.emojiTarget.open = false
    this.emojiTarget.inert = true
    this.emojiTarget.querySelector("summary")?.setAttribute("aria-disabled", "true")
    if (!this.hasSubmitTarget) return
    // The button's own words are kept on it, for whoever puts them back.
    this.submitTarget.dataset.label ??= this.submitTarget.textContent
    this.submitTarget.textContent = messages(this.element).t("notes.script.sending")
    this.submitTarget.setAttribute("aria-busy", "true")
  }

  // Nothing is being sent: the field, the submit and the three controls as
  // they are at rest. Read from the elements, not from what this controller
  // remembers, so it also undoes a state it did not set (`connect`).
  settled() {
    clearTimeout(this.sendingTimer)
    this.out = false
    this.fieldTarget.readOnly = false
    this.fieldTarget.classList.replace("text-dim", "text-ink")
    this.toolTargets.forEach((tool) => { tool.disabled = false })
    this.emojiTarget.inert = false
    this.emojiTarget.querySelector("summary")?.removeAttribute("aria-disabled")
    if (this.hasSubmitTarget) {
      if (this.submitTarget.dataset.label != null) this.submitTarget.textContent = this.submitTarget.dataset.label
      delete this.submitTarget.dataset.label
      this.submitTarget.removeAttribute("aria-busy")
    }
    this.refresh()
  }

  // `turbo:submit-end` on the form: a note that went through leaves no draft.
  sent(event) {
    this.settled()
    if (event.detail.success) this.forget()
  }

  // --- files --------------------------------------------------------------------

  browse() {
    if (this.out) return
    this.filesTarget.click()
  }

  // `change` on the file field: what was just picked, added to what was
  // chosen before. What does not fit is left out and said.
  filesChosen() {
    const text = messages(this.element)
    const limit = Number(this.filesTarget.dataset.maxCount)
    const bytes = Number(this.filesTarget.dataset.maxBytes)
    const all = [ ...(this.kept || []), ...this.filesTarget.files ]
    const fitting = all.filter((file) => file.size <= bytes)
    const errors = all.filter((file) => file.size > bytes).map((file) => text.t("notes.script.files.too_big", { name: file.name, size: this.filesTarget.dataset.maxSize }))
    if (fitting.length > limit) errors.push(text.t("notes.script.files.too_many", { count: limit }))
    this.setFiles(fitting.slice(0, limit))
    this.fileErrorTarget.textContent = errors.join(" ")
    this.fileErrorTarget.hidden = errors.length === 0
  }

  removeFile(event) {
    const index = Number(event.currentTarget.dataset.index)
    this.setFiles(this.kept.filter((_file, at) => at !== index))
    this.fileErrorTarget.hidden = true
    this.fileErrorTarget.textContent = ""
    // The row with the focus is gone: the next one's button, or the field.
    const next = this.chosenTarget.querySelectorAll("button")[Math.min(index, this.kept.length - 1)]
    ;(next || this.fieldTarget).focus()
  }

  // The file field's list and the rows that show it, from one array.
  setFiles(files) {
    const text = messages(this.element)
    this.kept = files
    const transfer = new DataTransfer()
    files.forEach((file) => transfer.items.add(file))
    this.filesTarget.files = transfer.files
    this.chosenTarget.replaceChildren(...files.map((file, index) => {
      const row = this.rowTarget.content.firstElementChild.cloneNode(true)
      row.querySelector("[data-name]").textContent = file.name
      row.querySelector("[data-facts]").textContent = this.facts(file)
      const remove = row.querySelector("button")
      remove.dataset.index = index
      remove.setAttribute("aria-label", text.t("notes.script.files.remove", { name: file.name }))
      return row
    }))
    this.chosenTarget.hidden = files.length === 0
    // Chosen again: nothing is lost any more. The draft learns the names either way.
    if (files.length > 0) this.lost = []
    this.sayLost()
    this.store()
  }

  // "Choose the files again: a.pdf, b.png", or nothing.
  sayLost() {
    if (!this.hasLostTarget) return
    this.lostTarget.hidden = this.lost.length === 0
    this.lostTarget.textContent = this.lost.length === 0 ? "" : messages(this.element).t("notes.script.files.again", { names: this.lost.join(", ") })
  }

  // The names beside a draft: of the files chosen now, or of those that
  // were and are still to be chosen again.
  get fileNames() {
    return this.kept?.length > 0 ? this.kept.map((file) => file.name) : this.lost || []
  }

  // "PDF · 1.2 MB", as a sent file's row says it -- but the kind is only the
  // name's ending here, a guess the row shows until the server has looked
  // at the bytes.
  facts(file) {
    const ending = /\.([A-Za-z0-9]{1,5})$/.exec(file.name)?.[1].toUpperCase()
    const size = file.size < 1048576 ? `${Math.max(1, Math.round(file.size / 1024))} KB` : `${(file.size / 1048576).toFixed(1)} MB` // i18n-ok: unit symbols, written the same in every language CS Studio has
    return [ ending, size ].filter(Boolean).join(" · ")
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
      option.dataset.action = "mousedown->admin--notes--composer#choose"
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
    if (this.out) return
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
      return typeof draft.body === "string" && draft.body ? { body: draft.body, names: draft.names || {}, files: this.list(draft.files) } : null
    } catch {
      return null
    }
  }

  store() {
    try {
      const value = this.fieldTarget.value
      if (value && !(this.editValue && value === this.drawn)) window.sessionStorage.setItem(this.storageKey, JSON.stringify({ body: value, names: this.names, files: this.fileNames }))
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

  // A list of names, from JSON or from a draft: strings only, a handful at most.
  list(source) {
    try {
      const value = typeof source === "string" ? JSON.parse(source || "[]") : source
      return Array.isArray(value) ? value.filter((name) => typeof name === "string" && name).slice(0, 10) : []
    } catch {
      return []
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
