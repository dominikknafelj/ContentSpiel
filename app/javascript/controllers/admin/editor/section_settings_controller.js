import { Controller } from "@hotwired/stimulus"

// A SECTION'S OWN SETTINGS (`#section-<id>-settings`, `data-section-id`):
// the one region that holds the section's autosave form `#section-<id>-form`,
// drawn under the section's head and hidden until a word of the head opens it
// (`admin--editor--section#openSettings`). Everything a person does INSIDE
// the region is this controller's -- the layout menu, Close, Escape, where
// the focus lands -- so it works wherever the region stands: under its head,
// or in the editor's rail, outside the card. Nothing here reaches for the
// card. The card finds the region by its id (`admin--editor--section#region`)
// and opens it; the region says it closed with
// `admin--editor--section-settings:closed` (`{ sectionId }`, bubbling), which
// the card hears on the window, wherever the region is, to mark its words
// closed, give the focus back to the word that opened them and let the
// section's hold go.
//
// THE REGION IS NEVER REMOVED, COPIED OR STREAMED HERE: it is the element the
// form is registered with in the write queue (`saving/queue.js`). A region
// that is moved keeps this controller's instance (Stimulus keeps one context
// per element and identifier), so what it remembers (`pickedIn`) survives a
// move into the rail and back; its targets disconnect and connect again with
// the move, which `layoutMenuTargetConnected` tells from an answer's menu.
//
// CLOSING SENDS (`close`): the form is told to send what it holds now
// (`admin--saving--autosave#saveNow`), as closing a block's panel does -- an
// edit inside its debounce would otherwise go a second later with nothing on
// screen to say so. An unchanged form sends nothing and a paused one refuses.
export default class extends Controller {
  static targets = ["layoutMenu"]

  get sectionId() { return this.element.dataset.sectionId }

  // The layout menu's pick (sections spec §4.1). The menu is a widget over a
  // hidden input of the section's own autosave form, so the pick is saved the
  // way every field is -- with the section's `base_updated_at`, through the
  // write queue -- and sent at once rather than after the debounce: a layout
  // is one deliberate choice, and its answer redraws the lanes.
  //
  // The item pressed is in a menu that closes on the pick (`admin--ui--menu
  // #select`, which runs after this on the same click), and a hidden button
  // cannot keep the focus: it goes to the menu's button here, whether or not
  // anything is sent.
  //
  // "No change" is a pick of the layout the section HAS -- the choice the
  // menu marks as current, which is what the server last saved -- while the
  // form holds it too. The input alone does not say: after a layout save
  // that was refused (no permission, an invalid answer) it still holds the
  // layout that was picked, and the menu the one the section has. Picking
  // the refused layout again is then asking again, and picking the current
  // one puts the form back to what is stored; both write the input and
  // send, which a form whose last save failed always does.
  //
  // A pick that is sent and saved is answered with a new menu, so the menu
  // the pick was made in is remembered (`pickedIn`) for
  // `layoutMenuTargetConnected` to carry the focus over from. The element,
  // not a flag: a save that is refused brings no menu, and a flag left set
  // would claim the focus for a menu that never comes.
  chooseLayout(event) {
    const layout = event.params.layout
    const form = event.currentTarget.closest("form")
    const input = form?.querySelector("input[name='block[settings][layout]']")
    const menu = event.currentTarget.closest("[data-admin--editor--section-settings-target~='layoutMenu']")
    menu?.querySelector("[aria-haspopup=menu]")?.focus()
    const current = event.currentTarget.getAttribute("aria-current") === "true"
    if (!input || (current && input.value === layout)) return

    input.value = layout
    this.pickedIn = menu
    this.application.getControllerForElementAndIdentifier(form, "admin--saving--autosave")?.saveNow()
  }

  // Whether the menu a pick was made in has been replaced by its answer. The
  // card asks it too: while a layout's answer is being drawn, the focus
  // belongs to the layout button and not to the lanes the same answer redraws.
  get menuReplaced() { return Boolean(this.pickedIn) && !this.pickedIn.isConnected }

  // The menu a saved layout's answer brought (not the same menu coming back
  // with a region or a card that was moved). It takes the focus only when
  // nothing has it: it was on the button this one replaced. A person who has
  // moved on is left where they are.
  layoutMenuTargetConnected(menu) {
    if (!this.menuReplaced || this.pickedIn === menu) return
    this.pickedIn = null
    if (this.nothingFocused) menu.querySelector("[aria-haspopup=menu]")?.focus()
  }

  get nothingFocused() { return !document.activeElement || document.activeElement === document.body }

  // Also the region's own Close button, and the card's door for a collapse,
  // a second press of the word and Escape in the head
  // (`admin--editor--section#closeSettings`). A region already hidden is
  // left alone: nothing is sent and nothing is said.
  close() {
    if (this.element.hidden) return
    const form = this.element.querySelector("form[data-controller~='admin--saving--autosave']")
    if (form) this.application.getControllerForElementAndIdentifier(form, "admin--saving--autosave")?.saveNow()
    this.element.hidden = true
    this.dispatch("closed", { detail: { sectionId: this.sectionId } })
  }

  // Escape inside the open region closes it -- unless it was meant for
  // something open inside it: a menu, a suggestion list or a dialog closes
  // itself on Escape, and the same key press must not also take the settings
  // away. Their listeners sit on descendants of the region, so they have run
  // by the time this one does, and each marks the press as handled
  // (`admin--ui--menu#keydown` calls `preventDefault`; `admin--ui--chip-input`
  // and the link search stop it from getting here at all). The checks after
  // `defaultPrevented` are for a widget that closes on Escape without saying
  // so: the press is left alone while it comes from inside a menu, a list or
  // an open dialog, or while a suggestion list of the form is showing.
  //
  // The card hands Escape in its head here too, so the head and the region
  // close by the same rule. A press this leaves alone is left alone by the
  // card as well (`admin--editor--section#escape` ignores what comes from
  // inside the region), so it never closes a block's panel instead.
  escape(event) {
    if (this.element.hidden || event.defaultPrevented) return
    const target = event.target
    if (target.closest?.("[role=menu], [role=listbox], dialog[open]")) return
    if (target.closest?.("[data-controller~='admin--ui--menu']")?.querySelector("[aria-expanded=true]")) return
    if (this.element.querySelector("[role=listbox]:not([hidden])")) return

    event.preventDefault()
    this.close()
  }

  // The named setting's control, or the layout menu's button for the layout
  // (its input is hidden). A reader's controls are disabled and take no
  // focus: the region's Close button has it then.
  focus(field) {
    const control = field === "layout"
      ? this.element.querySelector("[data-admin--editor--section-settings-target~='layoutMenu'] [aria-haspopup=menu]")
      : this.element.querySelector(`[name='block[settings][${CSS.escape(field)}]']`)
    const target = control && !control.matches(":disabled") ? control : this.element.querySelector("[data-action~='admin--editor--section-settings#close']")
    target?.focus()
  }
}
