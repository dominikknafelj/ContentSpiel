import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { enqueue } from "saving/queue"
import { orderErrorToast, sendOrder } from "saving/order_request"
import { TAB_HEADER } from "editing/requests"
import { TAB } from "live/connection"
import { loadSortable, makeCloneInert } from "editor/drag"
import { messages } from "i18n/messages"
import { idOf, isFolded, setFolded, setOpen } from "tree/open_set"

// How long a drag rests on a folded folder before it opens: the Pages
// tree's (`admin--pages--tree`).
const OPEN_ON_HOVER_MS = 600

// The Folders column's tree (`Admin::MediaLibrary::FolderTreeComponent::ID`).
const TREE_ID = "media-folder-tree"

// A press on a folder's handle that outlived its controller: set while a
// controller whose library left the page still holds it (`retire`), settled
// when that press ends (`release`). The next library's controller makes the
// column's Sortables only once it is settled, as two Sortables on one tree
// would both answer the press.
let heldColumn = null

// What a row that cannot take a folder says, by reason.
const REASONS = {
  this_folder: "components.media_library.drag.this_folder",
  too_deep: "components.media_library.drag.too_deep",
  name_taken: "components.media_library.drag.name_taken"
}

// Dragging onto the Folders column (the card StudioMediaFolders, D5 and D8),
// on the Media screen's `#media-library`.
//
// TWO DRAGS, ONE DROP. An image tile is dragged from the grid; a folder by the
// gutter handle of its row (`FolderTreeComponent#handle`, drawn for a
// viewer who may manage the library's folders). Either is dropped on a row of the column, which stands
// outside the content frame: this reaches the tree by its id, and makes the
// folders' Sortables again whenever the column is drawn again (a write's
// answer replaces its part), as long as this library is on the screen. Both
// drags are SortableJS's (`loadSortable`, the one loader, with
// `data-sortable` "pending" then "ready"), pointer-driven (`forceFallback`,
// for the reason `admin--pages--tree` gives) and with `sort: false`: nothing
// moves in the page until the server's answer says so. They are made only
// where the pointer is fine (`(pointer: fine)` as this connects): a coarse
// pointer moves by Move to… alone, and the stylesheet draws it no handle.
//
// WHAT IS DRAGGED. One tile, or, in selection mode
// (`admin--media--selection` on the same element), every ticked tile, and
// only from a ticked tile: a press on an unticked one stays a press. The
// clone SortableJS drags is hidden (`admin-media-drag-fallback`) and made
// inert (`makeCloneInert`: a tile's link and its selection target would
// otherwise exist twice); what follows the pointer is the ghost, the
// view's `<template>`, a pill with the tile's thumbnail and its title, or
// "3 images" and the count. A folder drags its row as the Pages tree does.
//
// THE TARGET is the row under the pointer, judged as `admin--pages--tree`
// judges its drop row: by the row's height inside the tree's width (the
// handle a drag holds stands in the gutter, outside its row), inside the
// column's own box, and never a row in a folded branch. An image is taken by
// a folder row or Not in a folder, but not the place shown (where it
// stands); a folder by a folder row (into it) or All
// media (to the top), but not by the row of the folder it is in now (it
// would go nowhere). A row that takes the drag carries the drop-into
// class (`TreeItemComponent::CLASSES[:drop_into]`, the `drop` class). A
// row that cannot take a folder says why, read from the rows'
// `data-media-folder-*` (depth, height, parent, name) and the tree's
// `data-media-drag-max-depth`: itself or a folder under it ("this folder"),
// one that would nest the folder's deepest folder past the deepest level
// ("too deep"), one holding a folder of its name ("name taken", the names
// compared in lower case). Such a row shows no target: it carries
// `data-media-drop-refused`, the reason stands where its count stood, and
// the polite status says "Can't move “Client A” there: too deep.". A drop
// there, or anywhere that is no target, sends nothing. The server judges
// again, and its refusal is an error toast.
//
// A FOLDED FOLDER under the pointer that takes the drag opens after
// `OPEN_ON_HOVER_MS`, stored open as a person's open (`tree/open_set.js`,
// the cookie the tree names), so its folders can be reached.
//
// THE DROP is sent through the screen's write queue (`enqueue`,
// `saving/queue.js`) and judged by `sendOrder`: images `POST /media/move`
// (`asset_ids[]`, `folder`), a folder `PATCH /media_folders/:id`
// (`parent_id`, empty for the top), each with the place and the search the
// content shows (`place`, `q`, `filter`), which the answer keeps; a folder
// dropped into a folder stores that folder open first. The
// answer's streams move the tiles, the counts and the column (and say a
// refusal); an images move that was answered with success is said in the
// polite status, "Moved 3 images to Events.". No answer at all is an error
// toast; nothing moved on screen, so nothing is put back.
//
// A FILE DROP NEVER SHOWS. `admin--media--drop`'s overlay answers only a
// drag that carries files, and a pointer-driven drag fires no drag event.
//
// WHILE A FIND NARROWS THE TREE ("Find a folder", `tree-find:filtered` on the
// tree) the folders' Sortables are disabled and the tree carries
// `data-filtered`, under which no handle is drawn; `tree-find:cleared` gives
// both back. An image can still be dropped on a row the find shows.
//
// THE CONTENT DRAWN AGAIN UNDER A FOLDER'S DRAG does not end it. This
// controller is on the library, inside the content frame, and the folder's
// drag is in the column, outside it; the content is drawn again on its own
// (a move's answer sends the frame to the place shown, `data-media-go` in
// `admin--media--folders`), and may land while the handle is still pressed.
// A controller disconnected during such a press keeps the column's
// Sortables, its follower and its drop until the press ends (`retire`), and
// only then lets go of them (`release`); the next library's controller makes
// the Sortables after that, `data-sortable` "pending" meanwhile. The column
// drawn again during that press ends the drag, as it ends any drag.
//
// Escape ends the drop for the rest of that drag (SortableJS has no Escape:
// the ghost follows until the release, which then sends nothing), and is
// taken: in selection mode it does not also leave the mode. Whatever a
// drag writes (the ghost, the marks, the reason, the timer) goes at its end,
// on `turbo:before-cache` and on disconnect.
export default class extends Controller {
  static targets = ["ghost", "status"]
  static values = { moveUrl: String, folderUrl: String }
  static classes = ["drop"]

  connect() {
    this.tileSortables = []
    this.folderSortables = []
    this.tree = null
    this.handlers = {
      "tree-find:filtered": (event) => this.narrowed(event, true),
      "tree-find:cleared": (event) => this.narrowed(event, false),
      "turbo:before-cache": () => this.endDrag()
    }
    Object.entries(this.handlers).forEach(([name, handler]) => document.addEventListener(name, handler))
    if (!matchMedia("(pointer: fine)").matches) return

    this.element.dataset.sortable = "pending"
    const token = this.loadToken = {}
    loadSortable().then(async (Sortable) => {
      if (heldColumn) await heldColumn
      // Disconnected (or connected again) before SortableJS arrived or the
      // held press ended.
      if (this.loadToken !== token) return

      this.Sortable = Sortable
      this.makeTileSortable()
      this.makeFolderSortables()
      const column = document.getElementById("tree-column")
      if (column) {
        this.columnObserver = new MutationObserver(() => this.columnChanged())
        this.columnObserver.observe(column, { childList: true, subtree: true })
      }
      this.element.dataset.sortable = "ready"
    })
  }

  disconnect() {
    this.loadToken = null
    if (this.pressing) this.retire()
    else this.teardown()
  }

  // Disconnected while a folder's handle is pressed: everything stays until
  // the press ends. Not even the tiles' Sortable is destroyed now: a
  // destroy ends whatever drag SortableJS holds, whichever Sortable holds it.
  retire() {
    this.retired = true
    heldColumn = new Promise((resolve) => { this.settleHeld = resolve })
  }

  release() {
    if (!this.retired) return

    this.retired = false
    this.teardown()
    heldColumn = null
    this.settleHeld()
  }

  teardown() {
    Object.entries(this.handlers).forEach(([name, handler]) => document.removeEventListener(name, handler))
    this.columnObserver?.disconnect()
    this.columnObserver = null
    this.endDrag()
    this.tileSortables.forEach((sortable) => sortable.destroy())
    this.destroyFolderSortables()
    this.tileSortables = []
    delete this.element.dataset.sortable
  }

  // ---- The Sortables ------------------------------------------------------

  makeTileSortable() {
    const grid = this.element.querySelector("ul.admin-media-grid")
    if (!grid) return

    this.tileSortables = [this.Sortable.create(grid, {
      ...this.dragOptions("admin-media-drag-fallback"),
      group: { name: "media-move", pull: "clone", put: false },
      draggable: "li[data-media-tile-id]",
      // In selection mode only a ticked tile lifts; any other press stays
      // the tile's own (`preventOnFilter: false`: it still ticks).
      filter: (event) => this.selecting && !this.ticked(event.target.closest?.("li[data-media-tile-id]")),
      preventOnFilter: false,
      onStart: (event) => this.startTiles(event.item),
      onEnd: () => this.drop()
    })]
  }

  makeFolderSortables() {
    const tree = document.getElementById(TREE_ID)
    this.tree = tree
    if (!tree) return

    this.markNarrowed(tree, this.findHoldsText())
    if (!tree.querySelector("[data-media-drag-handle]")) return

    const lists = [tree, ...tree.querySelectorAll("ul[data-tree-children]")]
    this.folderSortables = lists.map((list) => this.Sortable.create(list, {
      ...this.dragOptions("admin-drag-fallback"),
      group: { name: "media-folder", pull: "clone", put: false },
      draggable: "li[data-tree-node]",
      handle: "[data-media-drag-handle]",
      disabled: tree.hasAttribute("data-filtered"),
      onChoose: () => { this.pressing = true },
      // A retired controller lets go a turn later: SortableJS calls
      // `onEnd`, which drops, after this.
      onUnchoose: () => {
        this.pressing = false
        if (this.retired) setTimeout(() => this.release(), 0)
      },
      onStart: (event) => this.startFolder(event.item),
      onEnd: () => this.drop()
    }))
  }

  dragOptions(fallbackClass) {
    return {
      sort: false,
      forceFallback: true,
      fallbackOnBody: true,
      fallbackClass,
      fallbackTolerance: 3,
      // The tile or row taken stays where it is, as it is: the class has no
      // style on purpose, only so SortableJS's defaults are not written.
      ghostClass: "admin-media-drag-source",
      chosenClass: "admin-media-drag-source"
    }
  }

  // A Sortable destroyed during a press says no `onUnchoose`.
  destroyFolderSortables() {
    this.folderSortables.forEach((sortable) => sortable.destroy())
    this.folderSortables = []
    this.pressing = false
  }

  // The column was drawn again: the tree is a new element, so its
  // Sortables are made again, and a drag over the old rows ends.
  columnChanged() {
    const tree = document.getElementById(TREE_ID)
    if (tree === this.tree) return
    if (this.retired) return this.release()

    if (this.drag) this.endDrag()
    this.destroyFolderSortables()
    this.makeFolderSortables()
  }

  // ---- A find narrowing the tree -----------------------------------------

  narrowed(event, filtered) {
    if (event.target.id !== TREE_ID) return

    this.markNarrowed(event.target, filtered)
    this.folderSortables.forEach((sortable) => sortable.option("disabled", filtered))
  }

  markNarrowed(tree, filtered) {
    tree.toggleAttribute("data-filtered", filtered)
  }

  // A find that kept its text across a frame navigation narrows the tree
  // this connects to.
  findHoldsText() {
    const field = document.querySelector(`input[type=search][aria-controls='${TREE_ID}']`)
    return !!field && field.value.trim() !== ""
  }

  // ---- A drag -------------------------------------------------------------

  startTiles(item) {
    makeCloneInert(this.Sortable.ghost)
    const tiles = this.selecting ? this.tiles().filter((tile) => this.ticked(tile)) : [item]
    if (!tiles.includes(item)) tiles.unshift(item)
    const ids = tiles.map((tile) => tile.dataset.mediaTileId)
    this.drag = { kind: "images", ids, title: item.dataset.mediaTileTitle || "" }
    this.showGhost(item, ids.length)
    this.follow()
  }

  startFolder(item) {
    makeCloneInert(this.Sortable.ghost)
    const row = item.querySelector(":scope > [data-tree-row]")
    if (!row) return

    this.drag = {
      kind: "folder",
      id: row.dataset.mediaPlace,
      parent: row.dataset.mediaFolderParent || "",
      height: Number(row.dataset.mediaFolderHeight) || 1,
      name: row.dataset.mediaFolderName || "",
      title: row.dataset.treeTitle || "",
      node: item
    }
    this.follow()
  }

  follow() {
    this.pointerFollower = (event) => this.hover(event.clientX, event.clientY)
    // Captured on `window`, before every listener on the document, and
    // taken (`preventDefault`): Escape mid-drag cancels the drag and nothing
    // else, so selection mode's Escape (`admin--media--selection#escape`,
    // which leaves the mode) never hears it.
    this.escapeFollower = (event) => {
      if (event.key !== "Escape" || !this.drag) return
      event.preventDefault()
      this.drag.cancelled = true
      this.setRow(null)
    }
    document.addEventListener("pointermove", this.pointerFollower)
    window.addEventListener("keydown", this.escapeFollower, { capture: true })
  }

  hover(x, y) {
    this.placeGhost(x, y)
    if (!this.drag || this.drag.cancelled) return

    this.setRow(this.rowAt(x, y))
  }

  // The row whose box holds the pointer's height, the pointer inside the
  // tree's width and the column's box; never a row a fold or a find hides.
  rowAt(x, y) {
    const tree = document.getElementById(TREE_ID)
    const column = document.getElementById("tree-column")
    if (!tree || !column) return null

    const inside = (box) => x >= box.left && x <= box.right && y >= box.top && y <= box.bottom
    const treeBox = tree.getBoundingClientRect()
    if (!inside(column.getBoundingClientRect()) || x < treeBox.left || x > treeBox.right) return null

    return Array.from(tree.querySelectorAll("[data-tree-row][data-media-place]")).find((row) => {
      if (row.closest("[hidden]")) return false
      const box = row.getBoundingClientRect()
      return box.height > 0 && y >= box.top && y <= box.bottom
    }) ?? null
  }

  setRow(row) {
    if (row === this.row) return

    this.unmarkRow()
    this.row = row
    if (!row) return

    const { take, reason } = this.judge(row)
    if (take) {
      this.dropClasses.forEach((name) => row.classList.add(name))
      this.taking = true
      const node = row.closest("[data-tree-node]")
      if (node && isFolded(node)) this.hoverTimer = setTimeout(() => this.unfold(node), OPEN_ON_HOVER_MS)
    } else if (reason) {
      this.refuse(row, reason)
    }
  }

  // Whether `row` takes what is dragged, and if not, the reason it says
  // (none for a row that is simply no target).
  judge(row) {
    const place = row.dataset.mediaPlace
    // An image is taken by any place but All media and the place shown,
    // where the dragged images already stand.
    if (this.drag.kind === "images") return { take: place !== "all" && place !== this.shown().place }
    if (place === "none") return { take: false }

    const parent = place === "all" ? "" : place
    if (parent === this.drag.parent) return { take: false }
    if (place !== "all") {
      if (this.drag.node.contains(row)) return { take: false, reason: "this_folder" }
      const deepest = Number(this.tree?.dataset.mediaDragMaxDepth) || 4
      if ((Number(row.dataset.mediaFolderDepth) || 0) + this.drag.height > deepest) return { take: false, reason: "too_deep" }
    }
    const named = Array.from(this.tree?.querySelectorAll("[data-tree-row][data-media-folder-parent]") ?? [])
      .some((each) => each.dataset.mediaFolderParent === parent && each.dataset.mediaPlace !== this.drag.id && each.dataset.mediaFolderName === this.drag.name)
    if (named) return { take: false, reason: "name_taken" }

    return { take: true }
  }

  refuse(row, reason) {
    const words = messages(this.element)
    const why = words.t(REASONS[reason])
    row.setAttribute("data-media-drop-refused", "")
    const count = row.querySelector("[data-media-place-count]")
    if (count) count.hidden = true

    const said = document.createElement("span")
    said.className = "admin-tree-row__count"
    said.dataset.mediaDropReason = ""
    said.textContent = why
    let trailing = row.querySelector(":scope > .admin-tree-row__trailing")
    if (!trailing) {
      trailing = document.createElement("span")
      trailing.className = "admin-tree-row__trailing"
      trailing.dataset.mediaDropReason = ""
      row.querySelector(":scope > .admin-tree-row__state, :scope > .admin-tree-row__title")?.after(trailing)
    }
    trailing.append(said)
    this.announce(words.t("components.media_library.drag.refused", { name: this.drag.title, reason: why }))
  }

  unmarkRow() {
    clearTimeout(this.hoverTimer)
    this.hoverTimer = null
    this.taking = false
    const row = this.row
    this.row = null
    if (!row) return

    this.dropClasses.forEach((name) => row.classList.remove(name))
    row.removeAttribute("data-media-drop-refused")
    row.querySelectorAll("[data-media-drop-reason]").forEach((part) => part.remove())
    const count = row.querySelector("[data-media-place-count]")
    if (count) count.hidden = false
  }

  // Opens a folded folder as a person's open: drawn, stored, and told to
  // the tree's other scripts.
  unfold(node) {
    this.hoverTimer = null
    const tree = node.closest(`#${TREE_ID}`)
    if (!tree || !node.isConnected || !isFolded(node)) return

    setFolded(node, false)
    const id = idOf(node)
    if (id) setOpen(tree, id, true, { openByDefault: node.hasAttribute("data-tree-on-path") })
    tree.dispatchEvent(new CustomEvent("tree:changed", { bubbles: true }))
  }

  // ---- The ghost ----------------------------------------------------------

  showGhost(item, count) {
    const pill = this.hasGhostTarget ? this.ghostTarget.content.firstElementChild?.cloneNode(true) : null
    if (!pill) return

    const words = messages(this.element)
    const thumb = item.querySelector("img:not([aria-hidden])")
    const image = pill.querySelector("[data-media-drag-thumb]")
    if (thumb && image) image.src = thumb.currentSrc || thumb.src
    else image?.remove()
    pill.querySelector("[data-media-drag-label]").textContent = count === 1 ? this.drag.title : words.t("components.media_library.drag.count", { count })
    const badge = pill.querySelector("[data-media-drag-count]")
    badge.textContent = String(count)
    badge.hidden = count < 2
    const box = item.getBoundingClientRect()
    document.body.append(pill)
    this.ghost = pill
    this.placeGhost(box.left + box.width / 2, box.top + box.height / 2)
  }

  // Beside the pointer, never under it.
  placeGhost(x, y) {
    if (!this.ghost) return

    this.ghost.style.left = `${x + 12}px`
    this.ghost.style.top = `${y + 8}px`
  }

  // ---- The drop -----------------------------------------------------------

  drop() {
    const { drag, row, taking } = this
    this.endDrag()
    if (!drag) return

    this.swallowClick()
    if (!row || !taking || drag.cancelled) return

    if (drag.kind === "images") this.moveImages(drag, row)
    else this.moveFolder(drag, row)
  }

  moveImages(drag, row) {
    const folder = row.dataset.treeTitle || ""
    const moved = messages(this.element).t("components.media_library.drag.moved", { count: drag.ids.length, title: drag.title, folder })
    this.send(this.moveUrlValue, "POST", { asset_ids: drag.ids, folder: row.dataset.mediaPlace }, moved)
  }

  // The folder it goes into is stored open first, as the Pages tree's
  // move stores the new parent: the answer draws the column by the open
  // set, and a folder dropped into a folded one would vanish into the fold.
  moveFolder(drag, row) {
    const place = row.dataset.mediaPlace
    const node = row.closest("[data-tree-node]")
    if (node && this.tree) setOpen(this.tree, place, true, { openByDefault: node.hasAttribute("data-tree-on-path") })
    const url = this.folderUrlValue.replace("FOLDER_ID", encodeURIComponent(drag.id))
    this.send(url, "PATCH", { media_folder: { parent_id: place === "all" ? "" : place } }, null)
  }

  // Queued with every other write of the screen. `said` is what the polite
  // status says once the server took the move.
  send(url, method, fields, said) {
    const body = JSON.stringify({ ...fields, ...this.shown() })
    const headers = {
      "Content-Type": "application/json",
      Accept: "text/vnd.turbo-stream.html",
      "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
      [TAB_HEADER]: TAB
    }
    enqueue(async (isCurrent) => {
      const answer = await sendOrder(url, { method, headers, body })
      if (!isCurrent()) return

      if (answer.outcome !== "answered") {
        orderErrorToast(answer.outcome, "toast-media-drag-error")
        return
      }
      Turbo.renderStreamMessage(answer.text)
      if (answer.ok && said) this.announce(said)
    }).catch(() => {})
  }

  // The place and the search the content shows, which the answer keeps.
  shown() {
    const library = document.querySelector("#content [data-media-place]")
    let query = {}
    try {
      query = JSON.parse(library?.dataset.mediaQuery || "{}") || {}
    } catch {
      query = {}
    }
    const fields = { place: library?.dataset.mediaPlace ?? "" }
    for (const name of ["q", "filter"]) {
      if (typeof query[name] === "string" && query[name] !== "") fields[name] = query[name]
    }
    return fields
  }

  // A release over the tile it started on would be its click (the panel, or
  // a tick): a drag is not a press.
  swallowClick() {
    const swallow = (event) => {
      event.preventDefault()
      event.stopPropagation()
    }
    window.addEventListener("click", swallow, { capture: true, once: true })
    setTimeout(() => window.removeEventListener("click", swallow, { capture: true }), 0)
  }

  endDrag() {
    this.unmarkRow()
    this.ghost?.remove()
    this.ghost = null
    this.drag = null
    if (!this.pointerFollower) return

    document.removeEventListener("pointermove", this.pointerFollower)
    window.removeEventListener("keydown", this.escapeFollower, { capture: true })
    this.pointerFollower = null
    this.escapeFollower = null
  }

  // ---- Helpers ------------------------------------------------------------

  get selecting() {
    return this.element.matches("[data-controller~='admin--media--selection']")
  }

  tiles() {
    return Array.from(this.element.querySelectorAll("ul.admin-media-grid > li[data-media-tile-id]"))
  }

  ticked(tile) {
    return !!tile?.querySelector("[aria-pressed='true']")
  }

  announce(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
