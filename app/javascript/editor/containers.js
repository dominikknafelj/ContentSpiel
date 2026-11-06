// Pure reads of the page editor's containers (sections spec §3.1, §4.4). The
// page's list is one place a block can be; each column of each section is
// another -- a lane (`Admin::EditorScreen::SectionLanesComponent`), whose
// direct children are exactly its tiles (the lane's "+" sits after it, never
// in it), as the list's are exactly the cards. A block's element in its
// container is a card in the list and a tile in a lane; both carry
// `data-block-id`, which is all a move reads. Nothing here writes but
// `refreshMoveState`, and that only the `disabled` attribute.

// A container's blocks, in its order: its direct children that stand for
// one (a card, a tile -- and, for the moment between a drop and its answer,
// a card resting in a lane or a tile in the list).
export function itemsOf(container) {
  return Array.from(container.children).filter((child) => child.dataset.blockId)
}

// What the server calls a container (`ContentBlocks::Reorder`): a section
// and one of its columns, or neither for the page's own list.
export function placeOf(container) {
  return { section_id: container.dataset.sectionId || null, column: container.dataset.column || null }
}

// A LANE THAT TAKES NOTHING (sections spec §6): a lane of a section whose
// type is no longer registered, marked `data-no-drop` by
// `Admin::EditorScreen::SectionLanesComponent`. Such a section has no
// layout, so the server has no column of it to put a block in -- not even
// the column a block is already in: an order of one of its lanes is refused
// like a drop into it (`ContentBlocks::Reorder::NO_COLUMN`). The lane is
// there to show the blocks the section still holds and to say where each
// really is when it is moved OUT, which is the one move its tiles have. So
// every way into a closed lane, or along it, is shut in the browser and not
// left to the refusal, which would redraw the whole list:
// - no drop into it (`accepts`) and no sorting inside it (`sort: false` on
//   its Sortable, `admin--editor--blocks#laneTargetConnected`);
// - a tile in it has Move up, Move down and "Move to column…" disabled
//   (`refreshMoveState`), and "Move out of section" not;
// - it is no choice of the Move dialog, its section is not counted among
//   the sections the dialog numbers, and it does not enable a card's "Move
//   into section…" (`admin--editor--blocks#openLanes`, `MenuMoves#askWhere`).
export function isClosed(container) {
  return container.hasAttribute("data-no-drop")
}

// A lane does not accept a section (sections spec §3.2, §4.4): asked by
// SortableJS for every lane the pointer passes over, so a section's card
// dragged across another section's lanes never lands in one and the list
// goes on taking it. The markup's own word for "this card holds blocks"
// (`data-container`, `Admin::EditorScreen::SectionCardComponent`), not the
// type's name. The server refuses the same move
// (`ContentBlocks::Reorder::NESTED`). And a closed lane accepts nothing.
export function accepts(lane, dragged) {
  return !dragged.hasAttribute("data-container") && !isClosed(lane)
}

// Every container's order as it is now: what a caller takes BEFORE it moves
// an element, for the move to go back to (`MoveQueue#putBack`).
export function snapshot(containers) {
  return new Map(containers.map((container) => [ container, itemsOf(container) ]))
}

// Whether the LIST may put the dragged block before or after the card under
// the pointer (SortableJS `onMove`, asked on every sample of the pointer:
// `false` leaves the block where it is).
//
// A BLOCK OVER A SECTION'S CARD IS MORE OFTEN ON ITS WAY INTO IT THAN PAST
// IT. Left to itself the list sorts the dragged block to the other side of
// whatever card the pointer enters, at once -- and a section's card is
// entered through its edge on the way to a lane. A card dragged up from
// below would jump above the section the moment it touched it, pushing the
// section, and the lane being aimed at, down from under the pointer; chased
// there, the card goes into the lane, the section jumps back, and the
// pointer -- now in the section's lower edge -- has the list take the card
// out again. A tile crossing the gap between two lanes would be taken out
// into the list on the way. So over a section's card the list only does
// what the pointer's place says:
// - above the lanes (the header): the block may go BEFORE the section;
// - below them, in the card's lower edge: AFTER it;
// - level with them: nothing. A lane the pointer is over takes the block
//   itself, being asked first; between lanes it stays where it is.
// This is asked only where the list's Sortable has made the section's card
// its target, which is not everywhere inside it: with the pointer over a
// tile or over an open form SortableJS takes that element -- the nearest
// one with `data-block-id` -- for the target, finds it is no child of the
// list and does nothing, without asking. So an open form is a place where a
// dragged block simply stays, and of what lies below the lanes only the
// card's own edge sorts.
// A section's card being dragged is sorted as any card is (no lane takes
// it, `accepts`), and so is a block over a collapsed section, which has no
// lanes on screen.
export function besideSection(event, pointer) {
  const section = event.related
  if (!section.hasAttribute("data-container") || event.dragged.hasAttribute("data-container")) return true
  const lanes = section.querySelector('[data-admin--editor--section-target="lanes"]')?.getBoundingClientRect()
  if (!lanes || lanes.height === 0) return true

  if (pointer.clientY < lanes.top) return !event.willInsertAfter
  if (pointer.clientY > lanes.bottom) return event.willInsertAfter
  return false
}

// Which of a block's Move items have somewhere to go, for the blocks of
// `containers`; `openLanes` is every lane of the page that takes a block.
// Only the `disabled` attribute is touched, so it is idempotent and cheap to
// run on every child-list change. The button is the item's OWN: a section's
// card holds the blocks in it, and their Move items are not the section's.
// - Move up is disabled on the first block of a container, Move down on the
//   last.
// - "Move into section…" (a card's) needs a lane to go into: disabled while
//   the page has no section. The card is DRAWN with it disabled and this is
//   what enables it -- a section is added and removed without any other card
//   being drawn again, so only the screen can say.
// - "Move to column…" (a tile's) needs another column in its own section:
//   disabled in a section of one column.
// - In a closed lane (`isClosed`) nothing moves along it or to another
//   column: all three are disabled, whatever the tile's place.
// The caller asks the page for the lanes as it is, so the answer is right
// whichever of a section's parts arrived first.
export function refreshMoveState(containers, openLanes) {
  for (const container of containers) {
    const items = itemsOf(container)
    const stuck = isClosed(container)
    const columns = openLanes.filter((lane) => lane.dataset.sectionId === container.dataset.sectionId).length
    items.forEach((item, index) => {
      const own = (move) => Array.from(item.querySelectorAll(`[data-move="${move}"]`))
        .find((button) => button.closest("[data-block-id]") === item)
      const set = (move, disabled) => {
        const button = own(move)
        if (button) button.disabled = disabled
      }
      set("up", stuck || index === 0)
      set("down", stuck || index === items.length - 1)
      set("into", openLanes.length === 0)
      set("column", columns < 2)
    })
  }
}

// A block's name as its element shows it: the title button of a card, the
// first line of a tile's face.
export function titleOf(item) {
  return item.querySelector("[data-action$='admin--editor--blocks#toggle'], .admin-block-tile__face > span")?.textContent.trim() || "block"
}
