import { Controller } from "@hotwired/stimulus"
import { openPathIn } from "tree/open_set"

// The Folders column's tree (`Admin::MediaLibrary::FolderTreeComponent`, on
// `ul#media-folder-tree`), beside `admin--tree--disclosure`, which folds it.
//
// THE SELECTED ROW IS THE PLACE SHOWN. The column is the shell's tree column,
// outside `#content`, and outlives a frame navigation; a frame answer carries
// no column (`admin/media/index`), so the server's drawing of the selection
// holds only for the place it was drawn with. The place shown is the one
// `#content` names (`[data-media-place]`, drawn by the Media screen), and
// this marks exactly that row, whoever drew it: as each row connects (a full
// visit, a restored snapshot, an answer's redrawn column) and after every
// load of the content frame (`follow`), as `admin--pages--tree#follow` does
// for the open page. The marks are the shared row's own (the selected class,
// `TreeItemComponent::CLASSES[:row_selected]`, handed over as a Stimulus
// class, which also swaps the folder mark for the open one, and the link's
// `aria-current="page"`). Arriving at a place opens the path to it
// (`openPathIn`, which stores nothing but forgets the folds on that path) and
// scrolls its row into view inside `#tree-column`.
//
// THE ROWS' LINKS KEEP THE SEARCH THE CONTENT SHOWS. A search typed in the
// grid is a frame navigation the column does not see, so after each load the
// rows' `href`s are written again with the content's `q` and `filter`
// (`data-media-query`, a JSON object), and never a `page`: page 3 of one
// place is no page of another.
//
// AN ANSWER NAMES WHERE TO GO. A folder write's answer replaces the column's
// part, which carries the place the screen goes to next (`data-media-go`): a
// stream cannot navigate, so this sends the content frame there (its `src`;
// `#content` advances the address) and takes the attribute away, so a
// snapshot restored later does not go again.
//
// What this writes into the page (the selection, the path, the links) is
// right for the address Turbo's snapshot keeps it under, and a restored
// snapshot is marked again as its rows connect.
export default class extends Controller {
  static targets = ["row"]
  static classes = ["selected"]

  connect() {
    this.go()
    this.arrive()
  }

  rowTargetConnected(row) {
    this.mark(row, row.dataset.mediaPlace === this.placeShown())
  }

  follow(event) {
    if (event.target.id !== "content") return

    this.arrive()
  }

  arrive() {
    const shown = this.placeShown()
    this.rowTargets.forEach((row) => this.mark(row, row.dataset.mediaPlace === shown))
    this.keepQuery()
    openPathIn(this.element, /^\d+$/.test(shown ?? "") ? shown : null)
    this.scrollToRow(shown)
  }

  go() {
    const part = this.element.closest("[data-media-go]")
    const url = part?.dataset.mediaGo
    if (!url) return

    part.removeAttribute("data-media-go")
    const frame = document.getElementById("content")
    if (frame) frame.src = url
  }

  // The place `#content` lists: "all", "none" or a folder's id; null on a
  // content that names none.
  placeShown() {
    return document.querySelector("#content [data-media-place]")?.dataset.mediaPlace ?? null
  }

  query() {
    const raw = document.querySelector("#content [data-media-query]")?.dataset.mediaQuery
    try {
      const query = JSON.parse(raw || "{}")
      return query && typeof query === "object" ? query : {}
    } catch {
      return {}
    }
  }

  keepQuery() {
    if (!document.querySelector("#content [data-media-query]")) return

    const query = this.query()
    this.rowTargets.forEach((row) => {
      const link = row.querySelector("a[data-tree-focus]")
      if (!link) return

      const url = new URL(link.href, window.location.origin)
      for (const name of ["q", "filter", "page", "selected", "select"]) url.searchParams.delete(name)
      for (const name of ["q", "filter"]) {
        if (typeof query[name] === "string" && query[name] !== "") url.searchParams.set(name, query[name])
      }
      const href = url.pathname + url.search
      if (link.getAttribute("href") !== href) link.setAttribute("href", href)
    })
  }

  mark(row, selected) {
    this.selectedClasses.forEach((name) => row.classList.toggle(name, selected))
    const link = row.querySelector("a[data-tree-focus]")
    if (selected) link?.setAttribute("aria-current", "page")
    else link?.removeAttribute("aria-current")
  }

  // Inside the column only (`#tree-column`'s `scrollTop`, at once), and only
  // when the row is out of its view, which it then stands inside with one
  // row's height to spare; never the window, so the grid stays where it is.
  scrollToRow(place) {
    const column = document.getElementById("tree-column")
    const row = place == null ? null : this.rowTargets.find((each) => each.dataset.mediaPlace === place)
    if (!column || !row || row.closest("[hidden]")) return

    const box = column.getBoundingClientRect()
    const rowBox = row.getBoundingClientRect()
    if (rowBox.top >= box.top && rowBox.bottom <= box.bottom) return

    const spare = rowBox.height
    if (rowBox.top < box.top) column.scrollTop -= box.top - rowBox.top + spare
    else column.scrollTop += rowBox.bottom - box.bottom + spare
  }
}
