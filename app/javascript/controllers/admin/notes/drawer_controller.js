import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"

// Notes on an editor screen. Lives on <body>, like
// `admin--ui--dialog`: the header's button, the markers on the block cards and
// the rail's Notes tab are far apart in the document, and cards come and go by
// Turbo Stream without the screen being drawn again.
//
// THE PANEL (`drawer` target, `Admin::NotesScreen::RailPanelComponent`, the
// content of the rail's Notes tab). The notes are shown while that tab is
// the rail's current one, and the rail's controller (`admin--ui--rail`) owns
// that state: opening dispatches `admin--ui--rail:reveal` from the panel,
// which makes the Notes tab current and remembers the tab it leaves, and
// closing dispatches `admin--ui--rail:conceal`, which goes back to the tab
// the person last left. Nothing here names a tab or a panel of the rail's.
// The rail says which panel it showed (`admin--ui--rail:shown`, heard on
// <body> as `shown`): the Notes tab pressed is an opening like the header's
// button, and another tab pressed while the notes were shown is a closing.
// Where the rail docks the notes are its Notes tab; below its threshold the
// stylesheet makes the same element a slide-over over the canvas, and under
// 640px a sheet (content-spiel.tailwind.css, "THE NOTES PANEL"). Either way
// it is one element that is never moved, cloned or drawn again, so a note
// being typed keeps its text and its focus through a tab switch, the rail
// docking or undocking and a live merge.
//
// Opening sets the notes frame's `src` -- the record's list of notes, the
// list at a block's group, the list with a new note ready to type, or one
// thread, which is the frame's other view -- and moves the focus into it once
// the frame has loaded; closing gives the focus back to what opened it. A
// thread replaces the list and Back replaces the thread; the list's scroll
// position is kept for the way back. It is NOT a modal: nothing is made
// inert, there is no scrim, and Escape closes it only while the focus is
// inside (the `keydown.esc` action sits on the panel itself). "Open" is
// remembered per browser in `localStorage`, a convenience: the next editor
// opens its Notes tab where the rail docks (`beside`), and never puts the
// slide-over over an editor by itself. A shell drawer opening closes the
// slide-over, and the notes opening tells the shell's drawers to stand aside
// (`admin--notes--drawer:opened`).
//
// THE HEADER'S HEIGHT. Docked, the notes stick with the rail's panel under
// the editor's sticky header, and below the threshold the slide-over starts
// under it: both read `--admin-editor-header-height`, which `admin--ui--rail`
// measures onto the grid the notes stand in.
//
// THE FOCUS stays where the person put it. The frame's answers move it only
// when an opener asked (a press on the header's button, a marker, a link with
// `?notes=open`), or when it was inside the notes as the request left and the
// answer removed what held it (a row followed, a note sent): then it goes to
// the thread, or to the panel, never out to the page. Notes that open by
// themselves because they were open on the last editor take no focus, and
// neither does an answer that arrives while the person types in the editor
// -- the first answer after an opener's press included, when the person has
// moved into the editor before it is in (`focusStayed`).
//
// THE COUNTS (`counts` target). One record's open-thread counts,
// `{ total, subjects: { "<key>": n }, unread: [ "<key>" ] }`, written by the
// server into the page and into every answer of the notes frame; whichever
// copy arrived last is the truth. From it this fills every `total` (the
// header's number, the panel's "4 open" and the Notes tab's number, which a
// save's answer draws into the tab again with its number hidden), every marker
// (`marker`: a count pill; without notes nothing at rest, and the same
// control as "add a note" on hover or focus of its card) and the warning in a block's delete dialog (`warning`). A card or a tab
// drawn again by a stream connects its marker or its number and is filled
// like the rest, which is why the server never renders a count into a card.
//
// THE ACTIVE BLOCK. While one thread is the notes' view, the card or tile
// of the block it is on carries `data-notes-active` (an accent edge,
// handoff "Block card marker"): `markActive`, after every load of the frame,
// on close, and when a marker connects.
//
// A SELECTION. With text selected in a rich-text field, that block's marker
// reads "Note on selection" and a press starts a note quoting the text (cut
// to 500 characters; a copy). The selection is noted at
// `mousedown` on the marker, because the press itself may move it, and is
// good for the click of that same press only: any later press anywhere lets
// it go first (`release`, heard in the capture phase, before a marker's own
// `hold`), a click that no press began (the keyboard's) never reads it, and
// neither does a note started after something else was selected. The
// passage travels to the frame as `note_quote`, the one name a quote has in a
// URL (it is filtered from the log under that name).
//
// THE ADDRESS FOLLOWS THE NOTES (`syncAddress`).
// While the notes are shown the page's address carries `notes=open`, and
// `thread=<id>` while a thread is their view; closed, neither. So the address
// says what is on screen, a reload keeps it (the server opens the Notes tab
// for those two parameters), and a copied link opens what its sender saw. It is
// REPLACED, never pushed: Back still leaves the page. The entry is Turbo's,
// whose state (`history.state.turbo`: its restoration identifier and index)
// and whose own record of where the document is must both survive, so the
// replacing is done by Turbo's history with the identifier it has; a bare
// `replaceState` would leave Turbo believing in the old address. It is
// written only while the address IS this panel's editor (`data-path`): an
// editor reached by a link into `#content` is drawn, and its remembered
// notes opened, a moment before Turbo makes the address its own, and the
// page before it must not be handed `notes=open`. `turbo:load` is when that
// has happened, and is heard for it.
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
    this.revealing = false
    this.concealing = false
    // Whether the notes were shown when this last said so (`sync`).
    this.showing = false
  }

  // --- targets coming and going ----------------------------------------------

  // What the panel asks for as it arrives (`arrive`) waits for the rail's
  // controller, whose events open the Notes tab and whose docked state
  // decides what "open" from memory means: the controllers are registered as
  // their modules load, in no fixed order, so the rail may connect after this
  // target does (`admin--ui--rail:connected`, heard as `railConnected`). A
  // microtask first, so that within one render the rail is asked after every
  // controller of that render has connected.
  //
  // "Open" from memory is for the Notes tab of a docked rail. Below the
  // threshold the notes are a slide-over, or a sheet over the whole editor:
  // reopened by itself it would cover the page a person has just picked.
  // There only an explicit ask opens it -- a press, or a link with
  // `?notes=open`. The choice stays remembered for a wider window.
  drawerTargetConnected(drawer) {
    this.arriving = drawer
    queueMicrotask(() => this.arrive())
  }

  // `admin--ui--rail:connected` on <body>.
  railConnected(event) {
    if (this.arriving && event.target instanceof Element && event.target.contains(this.arriving)) this.arrive()
  }

  arrive() {
    const drawer = this.arriving
    if (!drawer || !drawer.isConnected || !this.hasDrawerTarget || this.drawerTarget !== drawer) return
    const rail = drawer.closest("[data-controller~='admin--ui--rail']")
    if (rail && !this.application.getControllerForElementAndIdentifier(rail, "admin--ui--rail")) return

    this.arriving = null
    if (drawer.dataset.openOnLoad === "true") this.show({ thread: drawer.dataset.thread || null })
    else if (this.remembered && this.beside) this.show({ focus: false })
    else this.sync()
  }

  // The editor was replaced (another record in `#content`, another screen):
  // what was asked of the old panel is nobody's any more.
  drawerTargetDisconnected() {
    this.arriving = null
    this.pending = null
    this.returnTo = null
    this.listScroll = null
    this.fromList = false
    this.inside = false
    // The next panel starts closed, so its first show is an opening.
    this.showing = false
  }

  countsTargetConnected(element) {
    this.refreshCounts(JSON.parse(element.dataset.counts))
  }

  // A card or tile drawn by a stream (an add, a move, a duplicate, a
  // section's lanes): its marker is filled from the counts this tab holds,
  // and marked if its block's thread is the one showing. One that left takes
  // its part of a delete dialog's sum with it.
  markerTargetConnected() {
    this.schedulePaint()
    this.markActive()
  }

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

  // Every `mousedown` in the document, in the capture phase, so before a
  // marker's own `hold`: what an earlier press held is let go. A press that
  // began on a marker and was dragged off it never became a click, and its
  // selection must not be quoted by whatever is pressed next.
  release() {
    this.held = null
  }

  // A marker, or "Add note" in a block's menu (`data-notes-compose`). With a
  // selection in that block: a new note quoting it. A marker with open
  // threads: the notes at that block's group. Otherwise: a new note on the
  // block, ready to type.
  open(event) {
    const marker = event.currentTarget
    const key = marker.dataset.notesKey
    // `detail` is the number of presses behind a click: 0 for the keyboard's
    // and a script's, which no `mousedown` on this element began.
    const quote = event.detail > 0 && this.held?.key === key ? this.held.text : null
    this.held = null
    if (quote) this.show({ compose: key, quote, trigger: marker })
    else if (!marker.hasAttribute("data-notes-compose") && (this.counts.subjects[key] || 0) > 0) this.show({ group: key, trigger: marker })
    else this.show({ compose: key, trigger: marker })
  }

  // "New note" in the panel's header: a note on the record itself.
  compose() {
    this.show({ compose: this.containerKey })
  }

  close(event) {
    if (!this.hasDrawerTarget || !this.isOpen) return
    // An Escape something inside already used (a menu's).
    if (event?.type === "keydown" && event.defaultPrevented) return

    this.conceal()
    this.forget()
    this.trigger?.focus()
    this.returnTo = null
  }

  // `admin--ui--rail:shown` on <body>: the rail showed one of its panels. The
  // Notes tab, by a press or a key of the person's, is an opening like the
  // header's button's (the focus stays on the tab); another tab, while the
  // notes were shown, is a closing like Close's, but the focus is the tab's.
  // What this controller's own reveal and conceal cause is theirs.
  //
  // Below the threshold the rail has no tabs to press, so a show of the
  // notes' panel there that this controller did not ask for is a side effect
  // (another panel concealed, the rail going back to the tab last left) and
  // never an opening: the panel is concealed again, to the rail's first tab,
  // and nothing slides over the editor that the person did not open.
  shown(event) {
    if (!this.hasDrawerTarget || this.revealing || this.concealing) return
    if (event.target instanceof Element && event.target.contains(this.drawerTarget)) {
      if (!this.beside) return this.conceal({ home: true })
      const from = document.activeElement
      this.show({ focus: false, keep: true, trigger: from && from !== document.body && !this.drawerTarget.contains(from) ? from : null })
    } else if (this.showing && !this.isOpen) {
      this.forget()
      this.returnTo = null
      this.sync()
    }
  }

  // Where the focus goes on close (back to the trigger): what
  // opened the notes, or the header's button when nothing a person pressed
  // did (a link with `?notes=open`, the notes remembered from the last
  // editor) or when what they pressed is gone (a marker on a card a stream
  // has drawn again). Never left to fall to <body>.
  //
  // What they pressed may also be there and have no box to take the focus:
  // "Add note" in a block's "⋯" menu is hidden again with its menu, and a
  // focus sent to it lands on <body> all the same. It counts as gone, and
  // the focus goes to what stands for that block and can be seen: its marker
  // when it shows a count, or else the "⋯" button of the menu the item is
  // in. (A marker that was itself pressed is given the focus back even at
  // rest: it has a box, and the focus inside its card is what shows it.)
  get trigger() {
    const from = this.returnTo
    if (from?.isConnected) {
      if (this.laidOut(from)) return from
      const key = from.dataset.notesKey
      const marker = key ? this.markerTargets.find((candidate) => candidate.dataset.notesKey === key) : null
      if (marker && this.laidOut(marker) && window.getComputedStyle(marker).opacity !== "0") return marker
      const menu = from.closest("[data-controller~='admin--ui--menu']")?.querySelector("[aria-haspopup='menu']")
      if (menu && this.laidOut(menu)) return menu
    }
    return this.hasOpenerTarget ? this.openerTarget : null
  }

  // Whether the element has a box and can take the focus: nothing above it
  // is `hidden` or `display: none`, and it is not `visibility: hidden`.
  laidOut(element) {
    return element.getClientRects().length > 0 && window.getComputedStyle(element).visibility !== "hidden"
  }

  // A shell drawer opened (`admin--shell--drawer:opened`): the slide-over
  // makes room, and the focus is the shell drawer's. Not a "Close": the
  // choice stays remembered. The Notes tab of a docked rail is beside the
  // editor, not over it, and stays.
  shellOpened() {
    if (!this.hasDrawerTarget || !this.isOpen || this.beside) return
    this.conceal()
  }

  // `turbo:before-fetch-request` on the notes frame: its view is about to be
  // replaced (a row was followed, a form was sent). Where the list stood is
  // kept for the way back, and whether the focus was in the notes, for the
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
  // keep it in the notes if the answer took away what held it, and bring
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
    this.markActive()
    this.syncAddress()
    if (!view || !this.isOpen) return

    const lost = inside && !this.drawerTarget.contains(document.activeElement)
    // What an opener asked for is given only while the focus is where it was
    // at the ask (the button that was pressed, or nowhere) or already in the
    // notes. The view is on screen a few frames before this runs -- Turbo
    // repaints between drawing a frame and saying it has loaded, and on a
    // slow machine that is long -- and a person who has clicked into the
    // editor meanwhile keeps the focus there: taken into the notes, their
    // typing went to the wrong place and Escape closed them. (CI's
    // browser suite met exactly that.)
    const asked = Boolean(pending) && this.focusStayed(pending.from)

    if (view.dataset.notesView === "thread") {
      // A thread opened from far down the list starts at its top; one drawn
      // again after a note was sent from it stays where it is. The list's
      // own position (`listScroll`) is kept until the list is back.
      if (fromList && this.scroller) this.scroller.scrollTop = 0
      if ((asked && (pending.thread || pending.focus)) || lost) this.focus(view)
      return
    }

    if (pending?.compose) {
      if (asked) this.focus(view.querySelector("#notes-new textarea"), { reveal: true })
    } else if (pending?.group) {
      if (asked) this.focus(view.querySelector(`[data-notes-group="${CSS.escape(pending.group)}"]`), { reveal: true })
    } else {
      if ((asked && pending.focus) || lost) this.focus(this.drawerTarget)
      if (this.listScroll != null && this.scroller) this.scroller.scrollTop = this.listScroll
    }
    this.listScroll = null
  }

  // Whether the focus is still where it was when the notes were asked for
  // (`from`), or nowhere, or inside them: then nobody has put it
  // anywhere else since.
  focusStayed(from) {
    const active = document.activeElement
    return !active || active === document.body || active === from || !active.isConnected || this.drawerTarget.contains(active)
  }

  // The block whose thread is showing (handoff: its card's border is accent
  // while the thread is open). One at a time; none in the list view or with
  // the notes closed. An attribute, taken back here: nothing a redrawn
  // card could keep by mistake, and nothing Turbo's snapshot of the page
  // keeps past the next editor's first load.
  markActive() {
    const view = this.isOpen ? this.frameTarget.querySelector("[data-notes-view='thread']") : null
    const key = view?.dataset.notesSubject
    this.markerTargets.forEach((marker) => {
      const holder = marker.closest(".admin-block-tile, .admin-block-card")
      holder?.toggleAttribute("data-notes-active", Boolean(key) && marker.dataset.notesKey === key)
    })
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
    // Something else is selected now: what a press held is not what
    // the person means. (A selection that only went away is the press's own
    // doing, and is why it was held.)
    if (next) this.held = null
    this.selection = next
    this.schedulePaint()
  }

  // --- the panel ----------------------------------------------------------------

  // The rail's panel the notes stand in: asked for by the target name the
  // rail's controller gives it, and by nothing of its look.
  get panel() {
    return this.hasDrawerTarget ? this.drawerTarget.closest("[data-admin--ui--rail-target~='panel']") : null
  }

  // Shown: the Notes tab is the rail's current one (docked, the tab; below,
  // the slide-over or the sheet).
  get isOpen() {
    return Boolean(this.panel?.hasAttribute("data-current"))
  }

  // Whether the notes stand beside the editor, as the docked rail's Notes
  // tab (`data-rail-docked`, `admin--ui--rail`'s), and not over it.
  get beside() {
    return this.hasDrawerTarget && this.drawerTarget.closest("[data-rail-docked]") !== null
  }

  get containerKey() {
    return this.hasDrawerTarget ? this.drawerTarget.dataset.key : null
  }

  // `keep`: the Notes tab pressed shows what the frame holds, the list or a
  // thread, and loads the list only into a frame that holds neither.
  show({ thread = null, group = null, compose = null, quote = null, trigger = null, focus = true, keep = false } = {}) {
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
    // `from`: where the focus is as the notes are asked for (`loaded`).
    this.pending = { thread, group, compose, focus, from: document.activeElement }

    // The drawer's own state, not the rail's: a press of the Notes tab has
    // made the panel current before this runs, and is an opening all the same.
    const wasOpen = this.showing
    this.reveal()
    this.remember()
    if (!wasOpen) this.dispatch("opened")

    // The frame already holds what was asked for: nothing to fetch. It was
    // asked for and holds no view: that load failed (the network, an error
    // page) or was emptied, and the same address is fetched again, or the
    // notes would stay on "Loading notes…" for good. Otherwise: go there.
    const frame = this.frameTarget
    const next = url.pathname + url.search
    const there = this.address(frame.getAttribute("src")) === next || (keep && frame.hasAttribute("src"))
    if (there && frame.querySelector("[data-notes-view]")) this.loaded()
    else if (there) frame.reload()
    else frame.src = next
  }

  // The Notes tab made current, or taken back to the tab the person last
  // left, by the rail's own events dispatched from inside the panel; then
  // everything that follows from "shown" is said again. The rail's `shown`
  // that each causes is this controller's own (`revealing`, `concealing`).
  reveal() {
    this.revealing = true
    try {
      this.drawerTarget.dispatchEvent(new CustomEvent("admin--ui--rail:reveal", { bubbles: true }))
    } finally {
      this.revealing = false
    }
    this.sync()
  }

  // `home`: to the rail's first tab, not to the tab last left.
  conceal({ home = false } = {}) {
    this.concealing = true
    try {
      this.drawerTarget.dispatchEvent(new CustomEvent("admin--ui--rail:conceal", { bubbles: true, detail: { home } }))
    } finally {
      this.concealing = false
    }
    this.sync()
  }

  // Everything that follows from whether the notes are shown: the openers'
  // pressed state, the active block and the address. One place, so they
  // can't disagree.
  sync() {
    this.showing = this.isOpen
    this.syncOpeners()
    this.markActive()
    this.syncAddress()
  }

  // The address as the notes are now (see "THE ADDRESS FOLLOWS THE NOTES"):
  // called whenever that changes -- opened, closed, a view loaded -- and on
  // `turbo:load`, when the address has become this editor's. The thread is
  // the one asked for while its view is still on its way, else the one in
  // the frame. Everything else in the address stays as it is.
  syncAddress() {
    if (!this.hasDrawerTarget) return
    const url = new URL(window.location.href)
    if (url.pathname !== this.drawerTarget.dataset.path) return

    const open = this.isOpen
    const thread = !open ? null : this.pending ? this.pending.thread : this.frameTarget.querySelector("[data-notes-view='thread']:not(:has([data-note-gone]))")?.dataset.noteThread
    if (open) url.searchParams.set("notes", "open")
    else url.searchParams.delete("notes")
    if (thread) url.searchParams.set("thread", thread)
    else url.searchParams.delete("thread")
    if (url.href === window.location.href) return

    const history = window.Turbo?.session?.history
    if (history?.restorationIdentifier) history.replace(url, history.restorationIdentifier)
    else window.history.replaceState(window.history.state, "", url.href)
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
    // The header's button is a toggle: pressed while the notes are shown.
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
    // "Unread for you" turns a count accent: the keys whose open
    // threads hold a delivery the viewer has not read.
    const unread = new Set(this.counts.unread)

    // The header button's number, the one beside the panel's title and the
    // Notes tab's.
    this.totalTargets.forEach((element) => {
      element.textContent = String(total)
      element.hidden = total === 0
      element.toggleAttribute("data-unread", unread.size > 0)
      element.closest("[data-admin--notes--drawer-target~='opener']")?.setAttribute("aria-label", text.t("notes.script.total", { count: total }))
    })
    // A button that connected after the notes opened (a header drawn again).
    this.syncOpeners()

    this.markerTargets.forEach((marker) => {
      const key = marker.dataset.notesKey
      const count = subjects[key] || 0
      const selecting = this.selection?.key === key
      const name = marker.dataset.notesName
      const number = marker.querySelector("[data-notes-count]")
      const quoting = marker.querySelector("[data-notes-selection]")
      const isUnread = unread.has(key)
      // Unread says "3 new" in words, beside the stylesheet's filled glyph.
      number.textContent = count === 0 ? "" : isUnread ? text.t("notes.script.marker.new", { count }) : String(count)
      number.hidden = count === 0 || selecting
      quoting.hidden = !selecting
      marker.toggleAttribute("data-has-notes", count > 0 || selecting)
      marker.toggleAttribute("data-unread", isUnread)
      marker.setAttribute("aria-label", selecting ? text.t("notes.script.marker.selection", { name })
        : count > 0 ? text.t(isUnread ? "notes.script.marker.open_unread" : "notes.script.marker.open", { count, name })
        : text.t("notes.script.marker.add", { name }))
    })

    // A delete dialog's warning. A block's: its own open notes; its key is
    // read from the card's or tile's id, so a card without a marker (a block
    // whose type is gone) still warns. A section's
    // (`data-notes-warning="section"`): the open notes on the blocks inside
    // it, by the markers of its tiles, in a sentence of its own. A section
    // takes no notes itself (it has no marker and
    // no "Add note"), so its own key is not counted.
    this.warningTargets.forEach((warning) => {
      const within = document.getElementById(warning.dataset.notesWithin)
      const section = warning.dataset.notesWarning === "section"
      const keys = new Set([ ...(within?.querySelectorAll("[data-admin--notes--drawer-target~='marker']") || []) ].map((marker) => marker.dataset.notesKey))
      const own = within && !section ? this.blockKey(within) : null
      if (own) keys.add(own)
      const count = [ ...keys ].reduce((sum, key) => sum + (subjects[key] || 0), 0)
      const key = section ? "notes.script.delete_section_warning" : "notes.script.delete_warning"
      warning.hidden = count === 0
      warning.textContent = count === 0 ? "" : text.t(key, { count })
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
