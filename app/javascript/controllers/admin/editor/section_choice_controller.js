import { Controller } from "@hotwired/stimulus"

const AUTOSAVE = "form[data-controller~='admin--saving--autosave']"

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
// word is pressed, with the word's setting as `field`; nothing else of the
// card sends it with a field, so its ground, a tile, a handle, a lane and
// "+ Add" choose nothing and a drag never selects. The one other sender,
// `admin--editing--hold#reveal`, shows a frozen form with no field: that is
// not a press, so it is left alone and the region opens in place under its
// head, with no tab switched and no focus moved under someone typing
// elsewhere in the rail.
//
// IT MOVES ONE ELEMENT AND NEVER CLONES. The region is the element the
// section's form is registered with in the write queue (`saving/queue.js`):
// its id, its base and its save state go where it goes. Taking it (`take`)
// cancels the card's event, so the card opens nothing in place, appends the
// region to the slot, shows it and marks it `data-editing-away` (what live
// editing reads, below). A move disconnects the form's autosave controller
// and connects it again on the same instance, and that reconnect sends an
// edit still inside its debounce (`admin--saving--autosave`, `saveStates`),
// so a move loses no text and no save.
//
// FOUR MOMENTS PUT IT BACK (`release`), as the card's child after its home
// marker (`[data-section-settings-home]`, where `SectionCardComponent` draws
// the region), and never at any other:
// - the region closing (its Close, Escape in it, a second press of the word:
//   `admin--editor--section-settings:closed`), and the rail goes back to the
//   tab the person last left (`admin--ui--rail:conceal`);
// - the rail undocking (`admin--ui--rail:docked` with `docked: false`: a
//   narrowed window, an unfolded tree): the region stays open under its head,
//   and the control that had the focus has it again, with its selection. A
//   rail that docks again says "Choose a section" while that region stays
//   open in place, where its word closes it;
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
// written on the region; the stylesheet keys its look in the rail on
// `[data-editing-away]`. A list a refused move would redraw counts the
// region's form among the list's (`editor/move_queue.js`, `listForms`).
//
// NOTHING TYPED IN IT IS LOST. What can take the section away under it:
// - a stream that redraws the card (a reorder's Undo, a list redrawn after a
//   refusal) brings a fresh region of the same id inside the new card
//   (`streamed`): the fresh one is removed and the new card marked chosen,
//   so the region in the rail stays the one registered form;
// - a list merge whose answer has no such section: a clean region comes back
//   in `awayGone` (`merged`) and is removed, and one holding text is kept by
//   the merge with its unit marked gone. It is given its own strip slot
//   (`#block-<id>-hold`), which its card took away with it, so the
//   "deleted, copy your text" notice is drawn in the rail.
// A region with no card left is never removed while it holds text
// (`holdsText`): Close and Escape leave it shown, an undock parks it, open,
// under the blocks' alert, and it goes only by the strip's Remove
// (`admin--editing--hold#remove`). A section removed while its region is
// clean takes the region with it, and the panel says "Choose a section".
export default class extends Controller {
  static targets = [ "slot", "empty" ]

  slotTargetConnected(slot) {
    // The panel says "Choose a section" again whenever its region goes, by
    // this controller or by the strip's Remove.
    this.observer = new MutationObserver(() => { if (!this.chosen && this.hasEmptyTarget) this.emptyTarget.hidden = false })
    this.observer.observe(slot, { childList: true })
  }

  slotTargetDisconnected() {
    this.observer?.disconnect()
    this.observer = null
  }

  disconnect() {
    this.release()
  }

  get docked() { return this.element.hasAttribute("data-rail-docked") }

  // The region in the slot, if any.
  get chosen() { return this.hasSlotTarget ? this.slotTarget.querySelector(":scope > [data-editing-away]") : null }

  // The card of a region's section, wherever the list has it.
  cardOf(region) {
    return region ? document.querySelector(`.admin-section-card[data-block-id="${CSS.escape(region.dataset.sectionId)}"]`) : null
  }

  // Whether the region's form holds text the server does not have, or its
  // unit is marked gone (its section deleted under unsaved text).
  holdsText(region) {
    if (region.matches("[data-editing-gone]") || region.querySelector("[data-editing-gone]")) return true
    return [ ...region.querySelectorAll(AUTOSAVE) ]
      .map((form) => this.application.getControllerForElementAndIdentifier(form, "admin--saving--autosave"))
      .some((form) => form && (!form.clean() || form.outstanding() || !form.unchanged()))
  }

  // `admin--editor--section:open-settings`, from a card: a word pressed.
  take(event) {
    if (!this.docked || !event.detail?.field) return
    const region = event.detail.region
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
  // `closed` puts it home without the rail going back a tab. A region whose
  // card is gone and that holds text is parked, with its text.
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
    if (this.chosen === region) this.release({ orphan: "park" })
  }

  // Puts the chosen region back under its head. `open` keeps it shown there
  // (the rail undocked under it); otherwise it goes home hidden. `refocus`
  // gives the focus back to the control inside it that had it, which the
  // move took away. A region whose card is gone is removed only when clean;
  // one that holds text stays shown where it is (`orphan: "stay"`) or is
  // parked, open and still away, under the blocks' alert (`"park"`). True
  // when the region left the slot.
  release({ open = false, refocus = false, orphan = "stay" } = {}) {
    const region = this.chosen
    if (!region) return false
    const card = this.cardOf(region)
    const home = card?.querySelector(":scope > [data-section-settings-home]")
    const fallen = !document.activeElement || document.activeElement === document.body
    const active = region.contains(document.activeElement) ? document.activeElement : (fallen && region.contains(this.lastFocus) ? this.lastFocus : null)
    const focused = refocus ? active : null
    const selection = focused ? (this.lastFocus === focused && this.lastSelection) || selectionOf(focused) : null
    this.lastFocus = null

    if (!home && this.holdsText(region)) {
      region.hidden = false
      if (orphan !== "park") return false
      document.getElementById("content-blocks-alert")?.after(region)
    } else if (home) {
      region.removeAttribute("data-editing-away")
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
    return true
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

  // `admin--editor--section-settings:closed`: an away region closed (in the
  // rail, or parked in the blocks column). Home, and the rail back to where
  // the person was; a region with no card that holds text stays shown.
  closed(event) {
    const region = event.target
    if (!(region instanceof Element) || !region.hasAttribute("data-editing-away")) return
    if (!this.cardOf(region) && this.holdsText(region)) {
      region.hidden = false
      return
    }
    if (region !== this.chosen) return region.remove()
    if (this.release() && !this.switching) this.dispatch("conceal", { target: this.emptyTarget, prefix: "admin--ui--rail" })
  }

  // `admin--ui--rail:docked`: undocked, the region goes back open under its
  // head with the focus it had, and the rail goes back to its other tab for
  // when it docks again. By the time the rail says so the Section panel is
  // no longer drawn and the browser has let the focus fall, so the control
  // that had it is the one noted as the focus came and went (`noteFocus`,
  // `noteBlur`), and it takes the focus back only while nothing else has it.
  undocked(event) {
    if (event.detail?.docked !== false || !this.chosen) return
    this.release({ open: true, refocus: true, orphan: "park" })
    this.dispatch("conceal", { target: this.emptyTarget, prefix: "admin--ui--rail" })
  }

  // `turbo:before-cache` on the document.
  cache() {
    this.release()
  }

  // `admin--editing--live:merged`: a list merge whose answer lacked the
  // chosen section. Its clean region comes back in `awayGone` and goes; one
  // whose unit the merge marked gone gets the strip slot its card took away,
  // before the notice that is fetched for it is drawn (`deleted` came first).
  merged(event) {
    const region = this.chosen
    if (!region) return
    if ((event.detail?.awayGone || []).includes(region)) return this.forget(region)
    if (!(event.detail?.gone || []).some((unit) => region.contains(unit))) return
    this.cardOf(region)?.removeAttribute("data-chosen")
    const slotId = `block-${region.dataset.sectionId}-hold`
    if (region.querySelector(`#${CSS.escape(slotId)}`)) return
    const slot = document.createElement("div")
    slot.id = slotId
    slot.setAttribute("data-editing-strip-slot", "")
    region.prepend(slot)
  }

  // `turbo:before-stream-render` on the document: after the stream is drawn,
  // a chosen card that was redrawn is marked chosen again and its fresh
  // region taken out, so the one in the rail stays the section's; a chosen
  // card that left the document takes a clean region with it.
  streamed(event) {
    const render = event.detail.render
    event.detail.render = async (stream) => {
      await render(stream)
      const region = this.chosen
      if (!region) return
      const card = this.cardOf(region)
      if (card && !card.hasAttribute("data-chosen")) {
        card.querySelector(`:scope > #${CSS.escape(region.id)}`)?.remove()
        card.setAttribute("data-chosen", "")
      } else if (!card && !this.holdsText(region)) {
        this.forget(region)
      }
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
