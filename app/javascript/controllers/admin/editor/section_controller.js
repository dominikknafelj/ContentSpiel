import { Controller } from "@hotwired/stimulus"

// The setting a head word opens (its Stimulus param).
const FIELD = "data-admin--editor--section-field-param"

// One block's form open per section (sections spec §4.3).
//
// EVERY FORM IS ALREADY IN THE PAGE. A section renders each of its blocks'
// forms as a hidden panel under its lanes (`Admin::EditorScreen::BlockCardComponent`,
// `placement: :panel`), and this controller only shows one and hides the
// rest. That is the whole point of the design: a form that is never removed
// stays registered with the write queue (`saving/queue.js`), keeps its
// debounce timer, its queued or in-flight save and its save state -- paused
// by a 409, failed -- exactly as a card's does, so opening, closing and
// switching need no request and can lose nothing. Do not turn this into
// "fetch the form when its tile is pressed": the form leaving the document
// is what the queue's drain exists to guard against.
//
// CLOSING SENDS. A form being hidden is told to send what it holds now
// (`admin--saving--autosave#saveNow`): an edit inside its debounce is otherwise only
// sent by its timer, a second later, with nothing on screen to say so. An
// unchanged form sends nothing and a paused one refuses, as always. Hiding
// itself stops nothing: a save queued or on the wire is answered into the
// hidden form's status line and base field like any other.
//
// WHICH FORM IS OPEN IS READ FROM THE PAGE, NOT REMEMBERED HERE (`openId`):
// the open panel is the one that is not `hidden`. A section's card is moved
// in the DOM by a drag or the keyboard path of `admin--editor--blocks`, and Stimulus
// then disconnects every target and connects it again -- so anything this
// controller kept beside the DOM would have to be rebuilt or would be wrong:
// a remembered id cleared when "its panel left" forgot a form that was still
// showing, and the next tile pressed opened a second one beside it. The
// panel's own `hidden` moves with the panel, as a form's save state moves
// with the form (`saveStates` in `admin--saving--autosave`). For the same reason a
// panel that really does leave (its block deleted or moved out) needs no
// bookkeeping: with it gone, nothing is open.
//
// WHAT AN ANSWER REPLACES, AND WHERE THE FOCUS GOES THEN. Two parts of a
// section are redrawn from the server while it is on screen, and each may be
// holding the focus -- or have just lost it to a menu that closed on the pick
// -- so each has a rule, or a keyboard user would be at the top of the page:
// - the layout menu, by the answer to a saved layout. It is in the
//   section's settings region, whose own controller keeps the focus on the
//   menu's button (`admin--editor--section-settings`);
// - the lanes (`lanes`), by a save that changed the number of columns and by
//   an add the server refused because its column is gone. After the first
//   the focus is the layout button's, the region's to give (this asks it
//   whether its menu was replaced, `menuReplaced`). After the second the "+" that
//   was pressed no longer exists, and the focus goes to the "+" of the last
//   lane there is: the column the removed ones were folded into, so the
//   nearest thing to what was pressed.
// A panel is never replaced -- its form holds unsaved text and its place in
// the write queue -- only its heading's text, which names the column.
//
// THE SECTION'S OWN SETTINGS (`region`, `#section-<id>-settings`) are one
// region holding the section's autosave form, with a controller of its own
// (`admin--editor--section-settings`): its layout menu, its Close, Escape
// inside it and where the focus lands in it are that controller's, so the
// region works wherever it stands -- under the head, where the card draws
// it, or in the editor's rail. This controller finds it by its id
// (`settingsId`) wherever it is, never as a target, and keeps the head's
// side: a word (`words`, "3 columns ▾") opens the region on its own setting
// (`openSettings`). Before it opens, the cancelable
// `admin--editor--section:open-settings` is dispatched on the card with the
// region itself in its detail: a controller that shows the region somewhere
// else (the editor's rail at wide widths) cancels it, and with nobody
// cancelling the region opens where it stands. Whether it is open is read
// from the region's `hidden`, as a panel's is, and the word that opened it
// is remembered by its setting's name, not its element: a save's answer
// replaces the words (`wordsTargetConnected` says again what they control
// and where the focus was). The region says it closed with
// `admin--editor--section-settings:closed`, heard on the window
// (`settingsClosed`), because a region in the rail is outside the card. The
// region is never removed or copied here: it is the one element the form
// lives in.
export default class extends Controller {
  static targets = ["tile", "panel", "lanes", "words"]
  static values = { settingsId: String }

  // A block added to a column opens at once: the server marks its panel
  // `data-open`. Tile and panel arrive in one answer but as two streams, so
  // whichever connects second finds the other.
  //
  // A tile that arrives also takes its `aria-expanded` from the page, like
  // everything else here: the lanes are redrawn by a saved layout that
  // changed the number of columns and by a refused add (a column this screen
  // still offered was removed elsewhere), and the tiles either brings are
  // drawn closed, as a page load draws them -- while one of their forms may
  // be showing under the lanes. Its tile says so again as it connects.
  tileTargetConnected(tile) {
    const id = tile.dataset.blockId
    const panel = this.panelFor(id)
    if (panel && !panel.hasAttribute("data-open")) this.faceFor(id)?.setAttribute("aria-expanded", String(!panel.hidden))
    this.openIfNew(id)
  }
  panelTargetConnected(panel) { this.openIfNew(panel.dataset.blockId) }

  openIfNew(id) {
    const panel = this.panelFor(id)
    if (!panel || !this.tileFor(id) || !panel.hasAttribute("data-open")) return
    panel.removeAttribute("data-open")
    this.open(id, { focus: true })
  }

  // The lanes, redrawn. Told from the same element coming back (the card was
  // moved in the DOM, and every target disconnects and connects again) by
  // its being another element than the one that left. The lanes a page load
  // brings follow none, so a section never takes the focus as it appears.
  // Not while a layout's answer is being drawn: then the focus belongs to
  // the layout button, whichever of the two streams lands first.
  lanesTargetDisconnected(lanes) { this.lanesGone = lanes }
  lanesTargetConnected(lanes) {
    const replaced = this.lanesGone && this.lanesGone !== lanes
    this.lanesGone = null
    if (!replaced || this.settings?.menuReplaced || !this.nothingFocused) return

    const pickers = lanes.querySelectorAll("[id^='block-picker-'] [aria-haspopup=menu]")
    pickers[pickers.length - 1]?.focus()
  }

  get nothingFocused() { return !document.activeElement || document.activeElement === document.body }

  // ---- The section's own settings.

  // The region, wherever it stands: under the head, or in the rail. None on
  // a section whose type is gone.
  get region() { return document.getElementById(this.settingsIdValue) }

  // The region's own controller (`admin--editor--section-settings`).
  get settings() {
    const region = this.region
    return region ? this.application.getControllerForElementAndIdentifier(region, "admin--editor--section-settings") : null
  }

  get settingsOpen() { return Boolean(this.region) && !this.region.hidden }

  // A word pressed: a second press of the word that opened the settings
  // closes them; any other opens them (or keeps them open) on its setting.
  openSettings(event) {
    const field = event.params.field
    if (this.settingsOpen && this.openedBy === field) return this.closeSettings()

    this.showSettings(field)
  }

  // Shows the region wherever it ended up after the cancelable
  // `open-settings`: a listener that cancels it shows the region itself (in
  // the rail), and with nobody cancelling it opens where it stands. A
  // cancelled ask that left the region hidden opened nothing, and the words
  // stay closed. Also `admin--editing--hold#reveal`'s door, with no field: a
  // frozen form must be in sight, and the focus is left where it is, since
  // the person did not ask for the region. True when the region is shown.
  showSettings(field = null) {
    const region = this.region
    if (!region) return false
    const asked = this.dispatch("open-settings", { detail: { sectionId: this.element.dataset.blockId, region, field }, cancelable: true })
    if (!asked.defaultPrevented) region.hidden = false
    if (region.hidden) return false

    this.openedBy = field
    this.markWords(true)
    if (field) this.settings?.focus(field)
    return true
  }

  // The door for a second press of the word, Escape in the head and the card
  // collapsing (`collapsed`, and `admin--editing--hold` through it): the
  // region's own `close` sends what the form holds and hides it, and
  // `settingsClosed` follows from its event. The focus goes back to the word
  // that opened the region, what had it being about to be hidden -- not on a
  // collapse: the name just pressed has it.
  closeSettings({ refocus = true } = {}) {
    if (!this.settingsOpen) return
    this.refocusOnClose = refocus
    try {
      this.settings?.close()
    } finally {
      this.refocusOnClose = true
    }
  }

  // `admin--editor--section-settings:closed`, heard on the window: the
  // region closed (its Close, Escape in it, or `closeSettings`). The words
  // say so, and `closed` says the section's own form is closed, as a panel's
  // close does, so whoever holds the section for this tab lets it go
  // (`admin--editing--hold`) once the save the region just sent is over.
  settingsClosed(event) {
    if (event.detail.sectionId !== this.element.dataset.blockId) return
    this.dispatch("closed", { detail: { blockId: this.element.dataset.blockId } })
    this.markWords(false)
    if (this.refocusOnClose !== false) this.wordFor(this.openedBy)?.focus()
    this.openedBy = null
  }

  // `admin--editor--blocks:toggled`, heard on the window: a collapsed
  // section's settings close with its body, so nothing of it stays editable
  // under a head that says it is folded.
  collapsed(event) {
    if (event.detail.hidden && event.detail.blockId === this.element.dataset.blockId) this.closeSettings({ refocus: false })
  }

  markWords(open) {
    this.wordsTargets.forEach((words) => words.querySelectorAll("button").forEach((word) => word.setAttribute("aria-expanded", String(open))))
  }

  wordFor(field) {
    const words = this.hasWordsTarget ? [ ...this.wordsTarget.querySelectorAll("button") ] : []
    return words.find((word) => word.getAttribute(FIELD) === field) || words[0]
  }

  // The words a save's answer brought are drawn closed: they say again
  // whether the region is open, and a word that had the focus as the old
  // ones left gets it back (in the new words, by its setting), unless the
  // person has gone somewhere else meanwhile. Which word had it is noted as
  // the focus comes and goes (`wordFocused`, `wordLeft`), because by the
  // time a removed element's target disconnects the focus has already
  // fallen to <body>. Leaving for another element forgets it; the focus
  // falling with no new element (the words removed) does not.
  wordFocused(event) { this.focusedWord = event.target.getAttribute(FIELD) }
  wordLeft(event) { if (event.relatedTarget) this.focusedWord = null }

  wordsTargetDisconnected(words) { this.wordsGone = words }

  wordsTargetConnected(words) {
    words.querySelectorAll("button").forEach((word) => word.setAttribute("aria-expanded", String(this.settingsOpen)))
    const replaced = this.wordsGone && this.wordsGone !== words
    const field = this.focusedWord
    this.wordsGone = null
    this.focusedWord = null
    if (replaced && field && this.nothingFocused) this.wordFor(field)?.focus()
  }

  // The block whose form is showing, or undefined. A panel marked
  // `data-editing-gone` is not "the open one": `editing/merge` shows it because
  // its block went (deleted, or moved out) and its tile with it, and it holds
  // text nothing else leads to. Opening a tile does not close it, and only its
  // own Close button and Escape inside it do (`hide`).
  get openId() { return this.panelTargets.find((panel) => !panel.hidden && !panel.hasAttribute("data-editing-gone"))?.dataset.blockId }

  toggle(event) {
    const id = event.currentTarget.closest("[data-block-id]").dataset.blockId
    if (this.openId === id) this.close()
    else this.open(id)
  }

  open(id, { focus = false } = {}) {
    const panel = this.panelFor(id)
    if (!panel) return
    if (this.openId && this.openId !== id) this.close({ refocus: false })

    panel.hidden = false
    this.faceFor(id)?.setAttribute("aria-expanded", "true")
    if (focus) panel.querySelector("input:not([type=hidden]), textarea, select, [contenteditable=true]")?.focus()
  }

  // Also the panel's own Close button. Focus goes back to the tile: the
  // field or button that had it is about to be hidden, and focus would fall
  // to <body>, the top of the page for a keyboard user. Not when another
  // tile is being opened -- that tile was just pressed and has the focus.
  close({ refocus = true, currentTarget } = {}) {
    // The Close button of a panel that has no tile closes that panel.
    const orphan = currentTarget?.closest?.("[data-editing-gone]")
    if (orphan) return this.hide(orphan, { refocus: false })

    const id = this.openId
    if (!id) return

    this.hide(this.panelFor(id), { refocus })
  }

  hide(panel, { refocus }) {
    this.sendNow(panel)
    // The block's form is closed: whoever holds it for this tab lets it go
    // (`admin--editing--hold`), once the save `sendNow` has just started (and
    // any follow-up it has) is over.
    // Every way a panel closes comes through here (Close, a second press on
    // the tile, Escape, another tile opened).
    this.dispatch("closed", { detail: { blockId: panel.dataset.blockId } })
    panel.hidden = true
    const face = this.faceFor(panel.dataset.blockId)
    face?.setAttribute("aria-expanded", "false")
    if (refocus) face?.focus()
  }

  // Escape in the head closes the settings when they are open, by the
  // region's own rule (`admin--editor--section-settings#escape`, which also
  // hears Escape inside the region itself); anywhere else in the card (a
  // block's panel) it closes the open form -- unless it was meant for
  // something open inside it: a menu, a suggestion list or a dialog closes
  // itself on Escape, and the same key press must not also take the form
  // away. Their listeners sit on descendants of the card, so they have run by
  // the time this one does, and each marks the press as handled
  // (`admin--ui--menu#keydown`, the rich-text popover and
  // `admin--editor--blocks#key` for a picked-up card call `preventDefault`;
  // `admin--ui--chip-input` and the link search also stop it from getting
  // here at all). The checks after `defaultPrevented` are for a widget that
  // closes on Escape without saying so: the press is left alone while it
  // comes from inside a menu, a list or an open dialog, or while a suggestion
  // list of the open form is showing. A press from inside the region is the
  // region's alone, whether it is under the head or not: one it left alone
  // must not close a panel instead.
  escape(event) {
    const target = event.target
    if (this.region?.contains(target)) return
    const head = this.element.querySelector(":scope > .admin-section-card__head")
    if (this.settingsOpen && head?.contains(target)) return this.settings?.escape(event)

    const orphan = target.closest?.("[data-editing-gone]")
    const id = orphan ? orphan.dataset.blockId : this.openId
    if (!id || event.defaultPrevented) return
    if (target.closest("[role=menu], [role=listbox], dialog[open]")) return
    if (target.closest("[data-controller~='admin--ui--menu']")?.querySelector("[aria-expanded=true]")) return
    if (this.panelFor(id)?.querySelector("[role=listbox]:not([hidden])")) return

    event.preventDefault()
    if (orphan) this.hide(orphan, { refocus: false })
    else this.close()
  }

  sendNow(panel) {
    for (const form of panel.querySelectorAll("form[data-controller~='admin--saving--autosave']")) {
      this.application.getControllerForElementAndIdentifier(form, "admin--saving--autosave")?.saveNow()
    }
  }

  panelFor(id) { return this.panelTargets.find((panel) => panel.dataset.blockId === id) }
  tileFor(id) { return this.tileTargets.find((tile) => tile.dataset.blockId === id) }
  faceFor(id) { return this.tileFor(id)?.querySelector(".admin-block-tile__face") }
}
