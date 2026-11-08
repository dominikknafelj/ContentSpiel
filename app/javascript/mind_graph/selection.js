// The selection, its card and the pins.
//
// SELECTING. A click on a node -- its mark or its drawn label, which are one
// target (`hit_test.js`) -- selects it: it and its direct neighbours stay at
// full strength and are always labelled, the rest dims, and the card
// (`card.js`) opens BESIDE the node (`card_placement.js`) and stays beside it
// through a pan, a zoom and the layout's own movement: its place is worked
// out in the frame that draws the node (`positionCard`, the frame's
// `onDrawn`), and its size is read only when it was filled or its content
// changed (`measureCard`), never in a frame. A node the layout never placed
// (the worker failed, and the selection came from the list) has no place to
// stand beside: the card takes the canvas's corner. A click on empty space,
// Escape and the card's Close clear the selection. A click never navigates
// by itself; the card's links do. A row of the list (`node_list.js`) selects
// the same way (`reveal`), brings the node to the middle of the canvas and
// moves the focus to the card, so the keyboard reaches the actions; closing
// that card gives the focus back to the row, and otherwise to the canvas.
// "+N more" is not something to select (design answer F4): a press on it is
// `onMore`, and the selection stays as it was.
//
// Inside the card, Escape closes it too (`input.js` hears the canvas's keys
// alone), and Enter opens the selected post or page while the focus is on
// the card ITSELF, where the list hands it: on a control inside the card
// Enter is that control's own (a link, a button, a line break in the note's
// field).
//
// PINNING. A pinned node is held where the layout has it: one dropped after
// a drag (`gestures.js`) and one pinned from its card. It carries a mark
// (`renderer.js`), the card's button reads Unpin, and "Release N pinned"
// beside the zoom buttons, there only while something is pinned, lets all
// of them go. Pins live in this page only -- `state.pinned`, nothing stored
// -- so a reload or leaving the screen forgets them. A toggle of the legend
// does not: a pin is the layout's, and a toggle changes only what is drawn.
// Without a layout there is nothing to pin (the worker failed). What the
// pins are is said on the element (`data-pinned`), and what the selection
// is (`data-selected`, `data-neighbours`: the ids of the selection's direct
// neighbours by the lines shown, comma-separated, written when the
// selection or the filter changes, never per frame).
import { placeCard } from "mind_graph/card_placement"
import { selectIndex, screenOf } from "mind_graph/state"

export function createSelection({ element, canvas, state, card, cardElement, list, layout, release, text, request, moveCamera, onMore }) {
  // The card as measured when it was last filled, where it was last put (so
  // its style is written only when it moves), and the id of the row that
  // opened it, when one did.
  let cardSize = { width: 0, height: 0 }
  let cardPlace = null
  let openedFromRow = null

  function positionCard() {
    if (state.selected < 0 || cardElement.hidden) return
    const at = state.placed ? screenOf(state, state.selected) : { x: NaN, y: NaN }
    const { left, top, side } = placeCard({ ...at, radius: state.radii[state.selected], cardWidth: cardSize.width, cardHeight: cardSize.height, width: state.width, height: state.height })
    const place = `${Math.round(left)},${Math.round(top)},${side}`
    if (place === cardPlace) return

    cardPlace = place
    cardElement.style.left = `${Math.round(left)}px`
    cardElement.style.top = `${Math.round(top)}px`
    cardElement.dataset.side = side
  }

  function measureCard() {
    cardSize = { width: cardElement.offsetWidth, height: cardElement.offsetHeight }
    cardPlace = null
    positionCard()
  }

  function select(index) {
    if (index >= 0 && state.nodes[index].kind === "more") return onMore(state.nodes[index])

    openedFromRow = null
    // The node the card already shows: a second click on it, or a filter
    // change that keeps it, must not build the card again -- that would
    // throw away a note half typed in it and fetch its notes once more.
    const shown = index >= 0 && index === state.selected && cardElement.childElementCount > 0
    selectIndex(state, index)
    element.dataset.selected = index >= 0 ? state.nodes[index].id : ""
    element.dataset.neighbours = Array.from(state.neighbours, (neighbour) => state.nodes[neighbour].id).join(",")
    if (index >= 0) {
      if (!shown) card.show(state.nodes[index], { pinned: state.pinned.has(index), pinnable: Boolean(layout()) })
      measureCard()
    } else {
      card.hide()
    }
    list.mark(index >= 0 ? state.nodes[index].id : null)
    request()
  }

  // The camera with this node in the middle of the canvas, at the zoom it has.
  function centre(index) {
    if (!state.placed || state.width === 0) return
    const { k } = state.camera
    moveCamera({ k, tx: state.width / 2 - state.positions[index * 2] * k, ty: state.height / 2 - state.positions[index * 2 + 1] * k })
  }

  function reveal(index) {
    select(index)
    openedFromRow = state.nodes[index].id
    centre(index)
    cardElement.focus()
  }

  function closeCard() {
    // The row is the list's treeitem: it takes the tree's one tab stop
    // before the focus, so Tab out and back finds it again.
    const row = openedFromRow == null ? null : list.row(openedFromRow)
    select(-1)
    if (row) {
      row.setAttribute("tabindex", "0")
      row.focus()
    } else {
      canvas.focus()
    }
  }

  function pinsChanged() {
    const count = state.pinned.size
    element.dataset.pinned = count
    release.hidden = count === 0
    release.textContent = count === 0 ? "" : text.t("mind_graph.script.release_pinned", { count })
    if (state.selected >= 0) {
      card.setPinned(state.pinned.has(state.selected))
      measureCard()
    }
    request()
  }

  // Nothing moves, but the worker is asked, so the screen is "settled" again
  // only when it has answered.
  function pin(index) {
    const client = layout()
    if (!client || state.pinned.has(index)) return
    state.pinned.add(index)
    element.removeAttribute("data-settled")
    client.pin(state.nodes[index].id)
    pinsChanged()
  }

  // Gives nodes back to the forces: the layout warms up and eases to rest
  // with them free.
  function unpin(indexes) {
    const client = layout()
    const freed = indexes.filter((index) => state.pinned.has(index))
    if (!client || freed.length === 0) return
    freed.forEach((index) => state.pinned.delete(index))
    element.removeAttribute("data-settled")
    client.unpin(freed.map((index) => state.nodes[index].id))
    pinsChanged()
  }

  const cardKeydown = (event) => {
    if (event.ctrlKey || event.metaKey || event.altKey) return
    if (event.key === "Enter" && event.target === cardElement) {
      event.preventDefault()
      card.open()
    } else if (event.key === "Escape") {
      event.preventDefault()
      closeCard()
    }
  }
  cardElement.addEventListener("keydown", cardKeydown)

  return {
    select, reveal, closeCard, pin, unpin, pinsChanged, measureCard, positionCard,
    // The next frame places the card again: the canvas changed size, or the
    // layout's first positions arrived for a card opened before them.
    forgetPlace() {
      cardPlace = null
    },
    stop() {
      cardElement.removeEventListener("keydown", cardKeydown)
    }
  }
}
