import { holdTurboRequest } from "saving/queue"

// Add, Duplicate and Delete need no controller action of their own: each is
// a plain `button_to`/`form_with` submission, and Turbo Drive appends
// `Accept: text/vnd.turbo-stream.html` to every non-GET form request on its
// own (`FormSubmission#requestAcceptsTurboStreamResponse` in Turbo's source:
// true whenever the request isn't a GET, no `data-turbo-stream` attribute
// required), so the server's Turbo Stream answer for each is applied in
// place. What this module adds is their place in the write queue and, for a
// Duplicate, where the focus goes.
//
// Attaches the listeners to `host` (the blocks controller: its `element`,
// `reorderUrlValue` and `focusItem(item)`) and answers `stop`, which removes
// them, and `focusCopy`, for the containers' observer.
export function watchWrites(host) {
  let awaitingCopy = false
  let copyTimer

  // A write (never a GET) waits its turn in the page-level queue
  // (`saving/queue.js`): add, duplicate and delete are held until the
  // request before them has been answered, exactly as an autosave is.
  const holdWrite = (event) => {
    if (String(event.detail.fetchOptions.method).toUpperCase() === "GET") return

    holdTurboRequest(event)
  }
  // The Undo toast after a reorder lives in `#toasts`, outside the blocks
  // section, so its `button_to` request doesn't pass through the listener
  // above. It's recognised by its URL.
  const holdUndo = (event) => {
    if (host.element.contains(event.target)) return
    if (event.detail.url?.pathname === new URL(host.reorderUrlValue, window.location.origin).pathname) holdWrite(event)
  }
  // Duplicate is picked from a card's "⋯" menu, which closes on the pick:
  // the item that had focus is hidden, and focus falls to <body> -- a
  // keyboard user would be back at the top of the page with the copy
  // somewhere below. So a Duplicate that succeeded is remembered
  // (`turbo:submit-end` bubbles up from its form), and the card its answer's
  // stream then adds to the list gets focus on its handle (`focusCopy`, from
  // the containers' observer): the copy, where Space and the arrows move it
  // on. The same for a tile's Duplicate, whose copy arrives in the tile's
  // lane and takes the focus on its own "⋯" (`focusItem`). The note is
  // dropped after a moment in case no copy follows.
  const duplicated = (event) => {
    const action = event.detail.formSubmission?.formElement?.getAttribute("action") || ""
    if (!event.detail.success || !new URL(action, window.location.origin).pathname.endsWith("/duplicate")) return
    awaitingCopy = true
    clearTimeout(copyTimer)
    copyTimer = setTimeout(() => { awaitingCopy = false }, 2000)
  }

  host.element.addEventListener("turbo:before-fetch-request", holdWrite)
  document.addEventListener("turbo:before-fetch-request", holdUndo)
  host.element.addEventListener("turbo:submit-end", duplicated)

  // The first card added to the list, or tile added to a lane, after a
  // Duplicate is the copy. `mutations` are the containers' child-list changes.
  const focusCopy = (mutations) => {
    if (!awaitingCopy) return
    const copy = mutations.flatMap((mutation) => Array.from(mutation.addedNodes))
      .find((node) => node.nodeType === Node.ELEMENT_NODE && node.matches('[data-admin--editor--blocks-target="card"], [data-admin--editor--blocks-target="tile"]'))
    if (!copy) return

    awaitingCopy = false
    host.focusItem(copy)
  }

  const stop = () => {
    host.element.removeEventListener("turbo:before-fetch-request", holdWrite)
    document.removeEventListener("turbo:before-fetch-request", holdUndo)
    host.element.removeEventListener("turbo:submit-end", duplicated)
    clearTimeout(copyTimer)
  }

  return { stop, focusCopy }
}
