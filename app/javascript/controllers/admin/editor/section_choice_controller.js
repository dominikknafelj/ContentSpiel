import { Controller } from "@hotwired/stimulus"

// Choosing a section (`admin--editor--section-choice`), on the page editor's
// rail grid beside `admin--ui--rail`. Where the rail docks, pressing a
// section head's words ("3 columns ▾") shows that section's settings region
// (`#section-<id>-settings`) in the rail's Section panel (`slot`) and marks
// the section's card chosen (`data-chosen`, its accent outline); with no
// section chosen the panel says "Choose a section" (`empty`). Below the
// threshold nothing here acts, and the words open the region in place, under
// its head, as the card does on its own.
//
// THE WORDS ARE THE ONLY TARGET THAT SELECTS. This hears one event,
// `admin--editor--section:open-settings`, which the card dispatches when a
// word is pressed (or `admin--editing--hold#reveal` must show a frozen form)
// and which nothing else of the card sends: its ground, a tile, a handle, a
// lane and "+ Add" choose nothing, so a drag never selects.
//
// IT MOVES ONE ELEMENT AND NEVER CLONES. The region is the element the
// section's form is registered with in the write queue (`saving/queue.js`):
// its id, its base, its debounce and its save state go where it goes. Taking
// it (`take`) cancels the card's event, so the card opens nothing in place,
// appends the region to the slot, shows it and marks it `data-editing-away`
// (what live editing reads, below). A Stimulus controller keeps its instance
// across a move, and an autosave form that comes back with an edit inside
// its debounce sends it (`admin--saving--autosave`, `saveStates`), so a move
// loses no text and no save.
//
// FOUR MOMENTS PUT IT BACK (`release`), as the card's child after its home
// marker (`[data-section-settings-home]`, where `SectionCardComponent` draws
// the region), and never at any other:
// - the region closing (its Close, Escape in it, a second press of the word:
//   `admin--editor--section-settings:closed`), and the rail goes back to the
//   tab the person last left (`admin--ui--rail:conceal`);
// - the rail undocking (`admin--ui--rail:docked` with `docked: false`: a
//   narrowed window, an unfolded tree): the region stays open under its head,
//   and the control that had the focus has it again, with its selection;
// - Turbo's snapshot (`turbo:before-cache`), so a restored page has it where
//   the server draws it;
// - this controller disconnecting.
// Choosing another section closes the first one, as its card does, which
// puts it back, before taking the next.
//
// A MERGE DOES NOT MOVE IT. A colleague's change fetches the block list, and
// putting the region back for each merge would move a form under someone
// typing. Live editing's list merge instead merges an element marked
// `data-editing-away` where it stands (`editing/merge.js`, "WHAT A SCRIPT
// MOVED AWAY"), keeps `data-editing-away` and the card's `data-chosen` (its
// RUNTIME set) and leaves `hidden` to this controller. Nothing else is
// written on the region; its look in the rail is the stylesheet's, keyed on
// where it stands. Two things can take the section away under it:
// - a list merge whose answer has no such section returns a clean region in
//   `awayGone` (`admin--editing--live:merged`, `merged`), and this removes it;
// - a stream that removes or redraws the card ("Remove section", a list
//   redrawn by a refused move) leaves the chosen card disconnected
//   (`streamed`), and the region in the rail belongs to nothing: it is
//   removed, since a redrawn card brings a region of its own.
// Either way the panel says "Choose a section" again. A region that holds
// unsaved text when its section goes is kept by the merge with its unit
// marked gone, as everywhere; closing it puts it nowhere and removes it.
export default class extends Controller {
  static targets = [ "slot", "empty" ]

  disconnect() {
    this.release()
  }

  get docked() { return this.element.hasAttribute("data-rail-docked") }

  // The region in the slot, if any.
  get chosen() { return this.slotTarget.querySelector("[data-editing-away]") }

  // The card of the chosen region's section, wherever the list has it.
  cardOf(region) {
    return region ? document.querySelector(`.admin-section-card[data-block-id="${CSS.escape(region.dataset.sectionId)}"]`) : null
  }

  // `admin--editor--section:open-settings`, from a card: a word pressed.
  take(event) {
    if (!this.docked) return
    const region = event.detail?.region
    if (!region) return
    event.preventDefault()

    const current = this.chosen
    if (current && current !== region) this.closeChosen(current)
    const card = event.target.closest(".admin-section-card")

    if (region.parentElement !== this.slotTarget) this.slotTarget.append(region)
    region.setAttribute("data-editing-away", "")
    region.hidden = false
    card?.setAttribute("data-chosen", "")
    this.emptyTarget.hidden = true
    this.dispatch("reveal", { target: region, prefix: "admin--ui--rail" })
  }

  // Another section's words were pressed: the chosen one closes as its own
  // card closes it (its form sends what it holds, its words say closed, its
  // hold is let go), with the focus left for the section being chosen, and
  // `closed` puts it home without the rail going back a tab.
  closeChosen(region) {
    const card = this.cardOf(region)
    const section = card && this.application.getControllerForElementAndIdentifier(card, "admin--editor--section")
    this.switching = true
    try {
      if (section) section.closeSettings({ refocus: false })
      else this.application.getControllerForElementAndIdentifier(region, "admin--editor--section-settings")?.close()
    } finally {
      this.switching = false
    }
    if (this.chosen === region) this.release()
  }

  // Puts the chosen region back under its head. `open` keeps it shown there
  // (the rail undocked under it); otherwise it goes home hidden. `refocus`
  // gives the focus back to the control inside it that had it, which the
  // move took away.
  release({ open = false, refocus = false } = {}) {
    if (!this.hasSlotTarget) return
    const region = this.chosen
    if (!region) return
    const card = this.cardOf(region)
    const home = card?.querySelector(":scope > [data-section-settings-home]")
    const fallen = !document.activeElement || document.activeElement === document.body
    const active = region.contains(document.activeElement) ? document.activeElement : (fallen && region.contains(this.lastFocus) ? this.lastFocus : null)
    const focused = refocus ? active : null
    const selection = focused ? (this.lastFocus === focused && this.lastSelection) || selectionOf(focused) : null
    this.lastFocus = null

    region.removeAttribute("data-editing-away")
    if (home) {
      if (!open) region.hidden = true
      home.after(region)
    } else {
      region.remove()
    }
    card?.removeAttribute("data-chosen")
    if (this.hasEmptyTarget) this.emptyTarget.hidden = false

    if (focused?.isConnected && !region.hidden) {
      focused.focus({ preventScroll: true })
      if (selection) try { focused.setSelectionRange(...selection) } catch { /* a control without a selection */ }
    }
  }

  // Which control in the slot has the focus, and its selection, as the focus
  // comes and goes: leaving for another element forgets it, the focus
  // falling to nothing (the panel no longer drawn) does not.
  noteFocus(event) {
    this.lastFocus = event.target
    this.lastSelection = null
  }

  noteBlur(event) {
    if (event.relatedTarget) this.lastFocus = null
    else if (event.target === this.lastFocus) this.lastSelection = selectionOf(event.target)
  }

  // `admin--editor--section-settings:closed`: the chosen region closed in
  // the rail. Home, and the rail back to where the person was.
  closed(event) {
    const region = this.chosen
    if (!region || event.detail?.sectionId !== region.dataset.sectionId) return
    this.release()
    if (!this.switching) this.dispatch("conceal", { target: this.emptyTarget, prefix: "admin--ui--rail" })
  }

  // `admin--ui--rail:docked`: undocked, the region goes back open under its
  // head with the focus it had, and the rail goes back to its other tab for
  // when it docks again. By the time the rail says so the Section panel is
  // no longer drawn and the browser has let the focus fall, so the control
  // that had it is the one noted as the focus came and went (`noteFocus`,
  // `noteBlur`), and it takes the focus back only while nothing else has it.
  undocked(event) {
    if (event.detail?.docked !== false || !this.chosen) return
    this.release({ open: true, refocus: true })
    this.dispatch("conceal", { target: this.emptyTarget, prefix: "admin--ui--rail" })
  }

  // `turbo:before-cache` on the document.
  cache() {
    this.release()
  }

  // `admin--editing--live:merged`: a list merge whose answer lacked the
  // chosen section handed back its clean region.
  merged(event) {
    const region = this.chosen
    if (!region || !(event.detail?.awayGone || []).includes(region)) return
    this.forget(region)
  }

  // `turbo:before-stream-render` on the document: after the stream is drawn,
  // a chosen card that left the document takes its region with it.
  streamed(event) {
    const render = event.detail.render
    event.detail.render = async (stream) => {
      await render(stream)
      const region = this.chosen
      if (!region) return
      const card = this.cardOf(region)
      if (!card || !card.hasAttribute("data-chosen")) this.forget(region)
    }
  }

  forget(region) {
    this.cardOf(region)?.removeAttribute("data-chosen")
    region.remove()
    this.emptyTarget.hidden = false
  }
}

function selectionOf(element) {
  try {
    return typeof element.selectionStart === "number" ? [ element.selectionStart, element.selectionEnd ] : null
  } catch {
    return null
  }
}
