import { messages } from "i18n/messages"
import { itemsOf, snapshot, titleOf } from "editor/containers"

// EVERY MOVE IS ALSO IN A MENU (sections spec §1, §4.4; plan D9, D10), which
// is the keyboard's way to everything a drag does. A card keeps its handle's
// keyboard path along the list (`editor/keyboard_moves.js`); a TILE has no
// other: its grip is for the pointer, so its "⋯" menu is where a keyboard
// user moves it -- Move up and Move down along its lane (`up`, `down`),
// "Move to column…" (`askWhere`, `moveTo`) and "Move out of section"
// (`out`). A top-level card's menu has "Move into section…" (`askWhere`
// again). All of them make the DOM move a drop would have made and then call
// the one sender, `admin--editor--blocks#move` (`relocate`): a menu move is queued, held
// still, refused and put back exactly as a drag is. What a menu move adds is
// the FOCUS (`MoveQueue#focusMoved`): the item that was picked is hidden
// with its menu, so without a rule the focus would be on <body>, the top of
// the page for a keyboard user. And it SAYS what it did, in the live region
// the handle's keyboard path speaks in (`relocate`): the focus lands on a
// button every block names the same ("Block actions", on a card as on a
// tile), so the announcement is what tells a screen reader which block went
// where.
//
// `host` is the blocks controller: its `destinationTarget`, `cardTargets`,
// `openLanes()`, `containers()`, `element`, `move(…)`, `focusItem(item)` and
// `announce(text)`.
export class MenuMoves {
  constructor(host) {
    this.host = host
  }

  // Swaps the block with its immediate neighbour in its container's own
  // order (`itemsOf`: the list for a card, its lane for a tile), then sends
  // it as a drop is sent. A disabled item (first card's Move up, last card's
  // Move down) never gets here; the index guards are a belt for a
  // programmatic call. The menu has closed by the time the block moves, so
  // focus goes to the block itself rather than being lost with the DOM move
  // (`relocate`).
  up(item) {
    const items = itemsOf(item.parentElement)
    const index = items.indexOf(item)
    if (index <= 0) return
    this.relocate(item, () => item.parentElement.insertBefore(item, items[index - 1]), "up")
  }

  down(item) {
    const items = itemsOf(item.parentElement)
    const index = items.indexOf(item)
    if (index < 0 || index >= items.length - 1) return
    // The block itself is what moves, not the neighbour past it: its menu is
    // closed by being moved (`admin--ui--menu#disconnect`), and by nothing else
    // here -- the menu's own close on a pick stands back from a disabled
    // item, which is what Move down has just become on a block that is now
    // the last.
    this.relocate(item, () => items[index + 1].after(item), "down")
  }

  // "Move to column…" on a tile and "Move into section…" on a card open the
  // one Move dialog (sections spec §4.4; `Admin::EditorScreen
  // ::MoveDialogComponent`). Its choices are read from the screen as it is
  // NOW -- sections are added, removed and given other layouts without the
  // other cards being redrawn, so a list the server rendered would go stale:
  // - for a tile, the other columns of its own section: "Column 2";
  // - for a card, every column of every section: "Section 2 · column 3". A
  //   section has no name of its own, so it is told from the others by its
  //   place: the sections are numbered as they stand in the page's list, top
  //   to bottom, which is what the person sees beside the dialog.
  // Only lanes that take a block are offered, and only sections that have
  // one are numbered (`isClosed`): a section whose type is gone reads
  // "Unavailable type" on the screen, not "Section", and is not counted.
  // A choice's value is its lane's id, looked up again when Move is pressed.
  //
  // This only FILLS the dialog and notes whose move it is. Showing it is
  // `admin--ui--dialog#open`, the next action of the same click (the item names
  // both, in this order): the focus goes to the select, and comes back to
  // the block's "⋯" when the dialog is closed without a move.
  askWhere(item) {
    const own = item.closest('[data-admin--editor--blocks-target="lane"]')
    const open = this.host.openLanes()
    const lanes = own ? open.filter((lane) => lane.dataset.sectionId === own.dataset.sectionId && lane !== own) : open
    const sections = this.host.cardTargets.filter((card) => open.some((lane) => card.contains(lane))).map((card) => card.dataset.blockId)
    const text = messages(this.host.element)

    this.asking = item
    this.askingSections = sections
    this.host.destinationTarget.replaceChildren(...lanes.map((lane) => {
      const option = document.createElement("option")
      option.value = lane.id
      option.textContent = own
        ? text.t("components.editor_screen.move_dialog.column", { column: lane.dataset.column })
        : text.t("components.editor_screen.move_dialog.section_column", { section: sections.indexOf(lane.dataset.sectionId) + 1, column: lane.dataset.column })
      return option
    }))
  }

  // The dialog's Move: to the END of the chosen lane, as a block added to a
  // column goes. The lane is found by the id the choice holds, so one that
  // was redrawn while the dialog was open is the lane that is there now, and
  // one that is gone moves nothing. A section that is collapsed is opened
  // first: the block would otherwise vanish into a card that shows one line,
  // with nothing left on screen to take the focus.
  moveTo() {
    const item = this.asking
    const destination = this.host.destinationTarget
    const lane = document.getElementById(destination.value)
    this.asking = null
    destination.closest("dialog").close()
    if (!item?.isConnected || !this.host.openLanes().includes(lane) || item.parentElement === lane) return

    // Said as the choice read: "column 2" to a tile, which stays in its
    // section, and "column 2 of section 1" to a card.
    const within = item.matches('[data-admin--editor--blocks-target="tile"]')
    const section = this.askingSections.indexOf(lane.dataset.sectionId) + 1
    this.expand(lane.closest('[data-admin--editor--blocks-target="card"]'))
    this.relocate(item, () => lane.append(item), within ? "column" : "into", { column: lane.dataset.column, section })
  }

  // Out of its section: directly after the section's card in the page's list.
  out(item) {
    const section = item.closest('[data-admin--editor--blocks-target="card"]')
    this.relocate(item, () => section.after(item), "out")
  }

  // A MENU'S MOVE: the DOM move a drop would have made, then the same request
  // (`admin--editor--blocks#move`). The focus goes to the moved block at once -- the item
  // that was picked is hidden with its menu, and a DOM move takes the focus
  // off whatever it moves. For a move along one container that is where it
  // stays. A block that changes containers is then held still by the queue
  // (`hold`: inert until its answer is drawn), which takes the focus off
  // again, and gets it back when its turn has ended (`focusMoved`).
  //
  // `said` is which sentence announces it (`block_moves.<said>` in the locale
  // file), spoken as the block moves -- as the keyboard path says "Dropped"
  // when the card is dropped, not when the request is answered. Every one
  // names the block and its place where it now is; `vars` adds what only the
  // caller knows (the column, the section's number). A move that does not
  // stand is then announced as put back (`MoveQueue#sendMove`).
  relocate(item, place, said, vars = {}) {
    const from = item.parentElement
    const before = snapshot(this.host.containers())
    place()
    this.host.focusItem(item)
    const items = itemsOf(item.parentElement)
    this.host.announce(messages(this.host.element).t(`components.editor_screen.block_moves.${said}`,
      { block: titleOf(item), position: items.indexOf(item) + 1, count: items.length, ...vars }))
    this.host.move(item, from, before, { focus: true })
  }

  // Shows a card's body if `admin--editor--blocks#toggle` has hidden it.
  expand(card) {
    const body = card.querySelector("[data-block-body]")
    if (!body.classList.contains("hidden")) return

    body.classList.remove("hidden")
    card.querySelector(`[aria-controls="${body.id}"]`)?.setAttribute("aria-expanded", "true")
  }
}
