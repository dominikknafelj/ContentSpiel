import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"

// Notes on an editor screen (notes spec §4.1, §4.3). Lives on <body>, like
// `admin--dialog`: the header's button, the markers on the block cards and
// the drawer are far apart in the document, and cards come and go by Turbo
// Stream without the screen being drawn again.
//
// THE DRAWER (`drawer` target, `Admin::NotesScreen::DrawerComponent`). Opening
// sets the notes frame's `src` -- the record's list of notes, the list at a
// block's group, the list with a new note ready to type, or one thread, which
// is the frame's other view -- shows the drawer and moves the focus into it
// once the frame has loaded; closing gives the focus back to what opened it.
// A thread replaces the list and Back replaces the thread; the list's scroll
// position is kept for the way back. It is NOT a modal: nothing is made inert,
// there is no scrim, and Escape closes it only while the focus is inside (the
// `keydown.esc` action sits on the drawer itself). "Open" is remembered per
// browser in `localStorage`, a convenience: the next editor opens with its
// notes showing. A shell drawer opening closes this one, and this one opening
// tells the shell's to stand aside (`admin--notes:opened`).
//
// THE FOCUS stays where the person put it. The frame's answers move it only
// when an opener asked (a press on the header's button, a marker, a link with
// `?notes=open`), or when it was inside the drawer as the request left and the
// answer removed what held it (a row followed, a note sent): then it goes to
// the thread, or to the drawer, never out to the page. A drawer that opens by
// itself because it was open on the last editor takes no focus at all, and
// neither does an answer that arrives while the person types in the editor.
//
// THE COUNTS (`counts` target). One record's open-thread counts,
// `{ total, subjects: { "<key>": n }, unread: [ "<key>" ] }`, written by the
// server into the page and into every answer of the notes frame; whichever
// copy arrived last is the truth. From it this fills the header's number
// (`total`), every marker (`marker`: a count pill; without notes nothing at
// rest, and the same control as "add a note" on hover or focus of its card)
// and the warning in a block's delete dialog (`warning`). A card drawn again
// by a stream connects its marker and is filled like the rest, which is why
// the server never renders a count into a card.
//
// A SELECTION. With text selected in a rich-text field, that block's marker
// reads "Note on selection" and a press starts a note quoting the text (cut
// to 500 characters; a copy, decision D4). The selection is noted at
// `mousedown` on the marker, because the press itself may move it. The
// passage travels to the frame as `note_quote`, the one name a quote has in a
// URL (it is filtered from the log under that name).
//
// Nothing here writes a record or touches an editor form; note forms are
// ordinary Turbo forms inside the frame.
const REMEMBER = "cs-notes-open"
const MAX_QUOTE = 500
const FOCUSABLE = "a, button, input, textarea, select, [tabindex]"

export default class extends Controller {
  static targets = [ "drawer", "frame", "opener", "total", "marker", "counts", "warning" ]

  initialize() {
    this.counts = { total: 0, subjects: {}, unread: [] }
    this.pending = null
    this.selection = null
    this.held = null
    this.listScroll = null
    this.fromList = false
    this.inside = false
  }

  // --- targets coming and going ----------------------------------------------

  // "Open" from memory is for the drawer BESIDE an editor. Below 1024px the
  // notes are a sheet over the whole editor: reopened by itself it would
  // cover the page a person has just picked (from the tree drawer, which
  // closed the sheet to be seen at all). There only an explicit ask opens it
  // -- a press, or a link with `?notes=open`. The choice stays remembered
  // for a wider window.
  drawerTargetConnected(drawer) {
    if (drawer.dataset.openOnLoad === "true") this.show({ thread: drawer.dataset.thread || null })
    else if (this.remembered && this.beside) this.show({ focus: false })
  }

  // The editor was replaced (another record in `#content`, another screen):
  // what was asked of the old drawer is nobody's any more.
  drawerTargetDisconnected() {
    this.pending = null
    this.returnTo = null
    this.listScroll = null
    this.fromList = false
    this.inside = false
  }

  countsTargetConnected(element) {
    this.refreshCounts(JSON.parse(element.dataset.counts))
  }

  markerTargetConnected() { this.schedulePaint() }
  markerTargetDisconnected() { this.schedulePaint() }
  warningTargetConnected() { this.schedulePaint() }
  totalTargetConnected() { this.schedulePaint() }

  // --- actions ----------------------------------------------------------------

  toggle(event) {
    if (this.isOpen) this.close()
    else this.show({ trigger: event.currentTarget })
  }

  // `mousedown` on a marker: what is selected NOW, before the press moves it.
  hold() {
    this.held = this.selection
  }

  // A marker, or "Add note" in a block's menu (`data-notes-compose`). With a
  // selection in that block: a new note quoting it. A marker with open
  // threads: the drawer at that block's group. Otherwise: a new note on the
  // block, ready to type.
  open(event) {
    const marker = event.currentTarget
    const key = marker.dataset.notesKey
    const quote = this.held?.key === key ? this.held.text : null
    this.held = null
    if (quote) this.show({ compose: key, quote, trigger: marker })
    else if (!marker.hasAttribute("data-notes-compose") && (this.counts.subjects[key] || 0) > 0) this.show({ group: key, trigger: marker })
    else this.show({ compose: key, trigger: marker })
  }

  // "New note" in the drawer's header: a note on the record itself.
  compose() {
    this.show({ compose: this.containerKey })
  }

  close(event) {
    if (!this.hasDrawerTarget || !this.isOpen) return
    // An Escape something inside already used (a menu's).
    if (event?.type === "keydown" && event.defaultPrevented) return

    this.drawerTarget.hidden = true
    this.syncOpeners()
    this.forget()
    this.trigger?.focus()
    this.returnTo = null
  }

  // Where the focus goes on close (spec §4.1: back to the trigger): what
  // opened the drawer, or the header's button when nothing a person pressed
  // did (a link with `?notes=open`, the drawer remembered from the last
  // editor) or when what they pressed is gone (a marker on a card a stream
  // has drawn again). Never left to fall to <body>.
  get trigger() {
    if (this.returnTo?.isConnected) return this.returnTo
    return this.hasOpenerTarget ? this.openerTarget : null
  }

  // A shell drawer opened (`admin--drawer:opened`): this one makes room, and
  // the focus is the shell drawer's. Not a "Close": the choice stays
  // remembered.
  shellOpened() {
    if (!this.hasDrawerTarget || !this.isOpen) return
    this.drawerTarget.hidden = true
    this.syncOpeners()
  }

  // `turbo:before-fetch-request` on the notes frame: its view is about to be
  // replaced (a row was followed, a form was sent). Where the list stood is
  // kept for the way back, and whether the focus was in the drawer, for the
  // answer. The event bubbles, so the resolved rows' own frame loading inside
  // the list is heard here too, and is not this frame leaving.
  leaving(event) {
    if (event.target.closest("turbo-frame") !== this.frameTarget) return

    this.inside = this.drawerTarget.contains(document.activeElement)
    this.fromList = this.frameTarget.querySelector("[data-notes-view='list']") !== null
    if (this.fromList) this.listScroll = this.scroller?.scrollTop ?? null
  }

  // `turbo:frame-load` on the notes frame (or called by `show` when the frame
  // already holds what was asked for): put the focus where the opener asked,
  // keep it in the drawer if the answer took away what held it, and bring
  // the list back to where it was left.
  loaded(event) {
    if (event && event.target !== this.frameTarget) return

    const pending = this.pending
    const inside = this.inside
    const fromList = this.fromList
    this.pending = null
    this.inside = false
    this.fromList = false
    const view = this.frameTarget.querySelector("[data-notes-view]")
    if (!view || !this.isOpen) return

    const lost = inside && !this.drawerTarget.contains(document.activeElement)

    if (view.dataset.notesView === "thread") {
      // A thread opened from far down the list starts at its top; one drawn
      // again after a note was sent from it stays where it is. The list's
      // own position (`listScroll`) is kept until the list is back.
      if (fromList && this.scroller) this.scroller.scrollTop = 0
      if (pending?.thread || pending?.focus || lost) this.focus(view)
      return
    }

    if (pending?.compose) {
      this.focus(view.querySelector("#notes-new textarea"), { reveal: true })
    } else if (pending?.group) {
      this.focus(view.querySelector(`[data-notes-group="${CSS.escape(pending.group)}"]`), { reveal: true })
    } else {
      if (pending?.focus || lost) this.focus(this.drawerTarget)
      if (this.listScroll != null && this.scroller) this.scroller.scrollTop = this.listScroll
    }
    this.listScroll = null
  }

  get scroller() {
    return this.hasDrawerTarget ? this.drawerTarget.querySelector("[data-notes-scroller]") : null
  }

  // `selectionchange` on the document.
  selected() {
    const selection = document.getSelection()
    const text = selection && !selection.isCollapsed ? selection.toString().trim() : ""
    const editor = text ? this.elementOf(selection.anchorNode)?.closest("[contenteditable='true']") : null
    const key = editor ? this.blockKey(editor) : null
    const next = key ? { key, text: text.slice(0, MAX_QUOTE) } : null
    if (next?.key === this.selection?.key && next?.text === this.selection?.text) return
    this.selection = next
    this.schedulePaint()
  }

  // --- the drawer ---------------------------------------------------------------

  get isOpen() {
    return this.hasDrawerTarget && !this.drawerTarget.hidden
  }

  // Whether the drawer is a drawer beside the editor (from 1024px, Tailwind's
  // `lg`, where its classes make it one) and not the full-screen sheet.
  get beside() {
    return window.matchMedia("(min-width: 1024px)").matches
  }

  get containerKey() {
    return this.hasDrawerTarget ? this.drawerTarget.dataset.key : null
  }

  show({ thread = null, group = null, compose = null, quote = null, trigger = null, focus = true } = {}) {
    if (!this.hasDrawerTarget) return

    if (trigger) this.returnTo = trigger
    // The list, or -- its other view -- one thread: `<src>/threads/<id>`.
    const url = new URL(this.drawerTarget.dataset.src, window.location.origin)
    if (thread) url.pathname = `${url.pathname}/threads/${encodeURIComponent(thread)}`
    if (compose) url.searchParams.set("compose", compose)
    if (quote) url.searchParams.set("note_quote", quote)
    this.listScroll = null
    this.fromList = false
    this.inside = false
    this.pending = { thread, group, compose, focus }

    const wasOpen = this.isOpen
    this.drawerTarget.hidden = false
    this.syncOpeners()
    this.remember()
    if (!wasOpen) this.dispatch("opened")

    // The frame already holds what was asked for: nothing to fetch. It was
    // asked for and holds no view: that load failed (the network, an error
    // page) or was emptied, and the same address is fetched again, or the
    // drawer would stay on "Loading notes…" for good. Otherwise: go there.
    const frame = this.frameTarget
    const next = url.pathname + url.search
    const there = this.address(frame.getAttribute("src")) === next
    if (there && frame.querySelector("[data-notes-view]")) this.loaded()
    else if (there) frame.reload()
    else frame.src = next
  }

  // A frame's `src` as a path and query: Turbo writes the whole URL there
  // after a redirect, a link wrote its own `href`.
  address(src) {
    if (!src) return null
    const url = new URL(src, window.location.origin)
    return url.pathname + url.search
  }

  // `reveal` scrolls the element into view (a block's group far down the
  // list, the field for a new note); without it nothing scrolls, so the
  // list's own position can be put back afterwards.
  focus(element, { reveal = false } = {}) {
    if (!element) return
    if (!element.matches(FOCUSABLE)) element.setAttribute("tabindex", "-1")
    element.focus({ preventScroll: !reveal })
    if (reveal) element.scrollIntoView({ block: "nearest" })
  }

  syncOpeners() {
    // The header's button is a toggle: pressed while the drawer is open.
    this.openerTargets.forEach((opener) => {
      opener.setAttribute("aria-expanded", this.isOpen ? "true" : "false")
      opener.setAttribute("aria-pressed", this.isOpen ? "true" : "false")
    })
  }

  // --- the counts -----------------------------------------------------------------

  refreshCounts(counts) {
    this.counts = { total: counts?.total || 0, subjects: counts?.subjects || {}, unread: counts?.unread || [] }
    this.schedulePaint()
  }

  // Several targets connect in one render: paint once, after them.
  schedulePaint() {
    if (this.painting) return
    this.painting = true
    queueMicrotask(() => {
      this.painting = false
      this.paint()
    })
  }

  paint() {
    const text = messages(this.element)
    const { total, subjects } = this.counts
    // "Unread for you" turns a count accent (spec §4.5): the keys whose open
    // threads hold a delivery the viewer has not read.
    const unread = new Set(this.counts.unread)

    // The header button's number and the one beside the drawer's title.
    this.totalTargets.forEach((element) => {
      element.textContent = String(total)
      element.hidden = total === 0
      element.toggleAttribute("data-unread", unread.size > 0)
      element.closest("[data-admin--notes-target~='opener']")?.setAttribute("aria-label", text.t("notes.script.total", { count: total }))
    })
    // A button that connected after the drawer opened (a header drawn again).
    this.syncOpeners()

    this.markerTargets.forEach((marker) => {
      const key = marker.dataset.notesKey
      const count = subjects[key] || 0
      const selecting = this.selection?.key === key
      const name = marker.dataset.notesName
      const number = marker.querySelector("[data-notes-count]")
      const quoting = marker.querySelector("[data-notes-selection]")
      number.textContent = count > 0 ? String(count) : ""
      number.hidden = count === 0 || selecting
      quoting.hidden = !selecting
      marker.toggleAttribute("data-has-notes", count > 0 || selecting)
      marker.toggleAttribute("data-unread", unread.has(key))
      marker.setAttribute("aria-label", selecting ? text.t("notes.script.marker.selection", { name })
        : count > 0 ? text.t("notes.script.marker.open", { count, name }) : text.t("notes.script.marker.add", { name }))
    })

    // A delete dialog's warning: the open notes on everything inside the card
    // or tile it names (a section's own and its blocks').
    this.warningTargets.forEach((warning) => {
      const within = document.getElementById(warning.dataset.notesWithin)
      const keys = new Set([ ...(within?.querySelectorAll("[data-admin--notes-target~='marker']") || []) ].map((marker) => marker.dataset.notesKey))
      const count = [ ...keys ].reduce((sum, key) => sum + (subjects[key] || 0), 0)
      warning.hidden = count === 0
      warning.textContent = count === 0 ? "" : text.t("notes.script.delete_warning", { count })
    })
  }

  // --- small things ---------------------------------------------------------------

  elementOf(node) {
    return node?.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement
  }

  // The block an element belongs to, as a notes key: a card or tile is
  // `#content_block_<id>`, an open form in a section `#block-<id>-panel`.
  blockKey(element) {
    const holder = element.closest("[id^='content_block_'], [id^='block-'][id$='-panel']")
    const id = holder?.id.match(/\d+/)?.[0]
    return id ? `ContentBlock-${id}` : null
  }

  get remembered() {
    try {
      return window.localStorage.getItem(REMEMBER) === "1"
    } catch {
      return false
    }
  }

  remember() {
    try {
      window.localStorage.setItem(REMEMBER, "1")
    } catch {
      // A convenience only.
    }
  }

  forget() {
    try {
      window.localStorage.removeItem(REMEMBER)
    } catch {
      // As above.
    }
  }
}
