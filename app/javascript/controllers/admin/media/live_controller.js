import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { listen, TAB } from "live/connection"
import { settle } from "live/state"

// At most one fetch of the part per this many milliseconds (the card's D13).
const SPACING_MS = 2000

// The ids of the two parts a fetch replaces: the Media screen's column
// (`FolderTreeComponent::PART_ID`) and the picker's places (`PICKER_PART_ID`).
const SCREEN_PART = "media-folder-tree-part"
const PICKER_PART = "media-picker-places"
// The tree inside either part, which a find narrows.
const TREES = "#media-folder-tree, #media-picker-folder-tree"

// When this document last fetched a part, kept across the screen's frame
// navigations, which connect this controller again on a new element.
let lastFetch = -Infinity

// What a tab does when ANOTHER tab changed the library (media-folders spec
// §11, the card's D13): on the Media screen's library (`#media-library`) and
// on the picker's `<dialog>` while it is open (`picker`, between the picker's
// `reset`, which it says as it opens, and the dialog's `close`).
//
// IT LISTENS to the library's one stream (`Media::LibraryChannel`, through
// `live/connection`), whose signal says only THAT the folders changed or
// images moved, and never which. A signal this tab caused (`origin` is its
// `TAB`) is its own answer's, already drawn, and is not fetched for: every
// write of this tab says which tab it is (`editing/requests` puts the tab
// header on each Turbo request, and the drag's own requests send it), which
// `Admin::BaseController` reads for every request.
//
// IT FETCHES THE PART, at most once per two seconds however many signals
// came (one trailing fetch waits for the rest of the two seconds): the
// column's part on the screen (`GET /media/folders`, the screen's gate and
// words: the place shown and its search), the picker's places in the
// picker (`picker=1`). The part is replaced silently: the server draws the
// folds (`cs_media_open` on the screen, the path to the place in the
// picker), the focus stays on the same control of the same row (by its id,
// or by its row's `data-media-place` and its place among the row's
// controls), the picker's list keeps its scroll, and a find typed over the
// folders runs again over the new rows (`tree:changed`).
//
// THE GRID IS NEVER REPLACED UNDER THE PERSON. The part carries the digest
// of the place shown (`Media::Place#digest`), and this holds the digest of
// what the grid shows: the one drawn with it (`data-media-place-digest` on
// `#media-library`, or on the picker's `#media-picker-place` inside its
// frame), then the one each of this tab's own answers drew -- a write's
// answer replaces the column's part with the digest on it (`answered`), and
// an upload's answer names its own (`adopt`) -- since those changed the grid
// in place. When the fetched digest differs, or the folder shown is gone
// (`data-media-place-gone`), one notice stands above the grid, from the
// `<template>` the view draws: "Images here changed since you opened this
// view." with "Show changes" (`show`), which reloads the place's frame (All
// media when the folder is gone) and takes the notice away. One notice,
// never stacked: a second difference finds it standing.
//
// The subscription is a live part of the page (`live/state.js`): the screen
// draws `data-live-part="waiting"` on its element, and the picker writes it
// as it opens and takes it off as it closes, since a closed picker listens
// to nothing.
export default class extends Controller {
  static targets = [ "notice", "slot" ]
  static values = { url: String, picker: Boolean }

  connect() {
    if (!this.pickerValue) this.start()
  }

  disconnect() {
    this.stop()
  }

  // The picker's `reset`, said as it opens.
  open() {
    this.stop()
    this.element.setAttribute("data-live-part", "waiting")
    this.start()
  }

  // The dialog's `close`.
  close() {
    if (this.element.open) return

    this.stop()
    this.element.removeAttribute("data-live-part")
    settle(document.body)
  }

  start() {
    this.running = true
    let dropped = false
    const listener = Object.assign((signal) => this.heard(signal), {
      connected: () => {
        // A socket that dropped missed what was said meanwhile.
        if (dropped) this.soon()
        dropped = false
        this.answered()
      },
      disconnected: () => {
        dropped = true
        this.answered()
      },
      rejected: () => this.answered()
    })
    this.unlisten = listen({ channel: "Media::LibraryChannel" }, listener)
    this.answered()
  }

  stop() {
    this.running = false
    clearTimeout(this.timer)
    this.timer = null
    this.request?.abort()
    this.request = null
    this.unlisten?.()
    this.unlisten = null
    settle(document.body)
  }

  answered() {
    if (!this.unlisten || !this.element.hasAttribute("data-live-part")) return

    this.element.setAttribute("data-live-part", this.unlisten.settled ? "answered" : "waiting")
    settle(document.body)
  }

  heard(signal) {
    if (signal?.kind !== "library" || signal.origin === TAB) return

    this.soon()
  }

  soon() {
    if (!this.running || this.timer) return

    const wait = Math.max(0, lastFetch + SPACING_MS - Date.now())
    this.timer = setTimeout(() => {
      this.timer = null
      this.fetchPart()
    }, wait)
  }

  // --- The place shown, and the digest this tab holds of it -----------------

  // The element that names the place the grid shows and the digest it was
  // drawn with: the library itself on the screen, the frame's marker in the
  // picker (none while its frame is loading).
  get marker() {
    return this.pickerValue ? this.element.querySelector("#media-picker-place") : this.element
  }

  // The digest of what the grid shows: the marker's own until one of this
  // tab's answers names another for the same place.
  held(marker) {
    if (this.heldMarker !== marker) {
      this.heldMarker = marker
      this.heldDigest = marker.dataset.mediaPlaceDigest
    }
    return this.heldDigest
  }

  // A digest this tab's own answer drew for `place`, when it is the place shown.
  adopt(place, digest) {
    const marker = this.marker
    if (!marker || !digest || marker.dataset.mediaPlace !== place) return

    this.heldMarker = marker
    this.heldDigest = digest
  }

  // An upload's answer (`admin--media--upload:uploaded`,
  // `admin--media--picker:digest`): the place it was sent to and its digest.
  uploaded(event) {
    this.adopt(event.detail?.place, event.detail?.digest)
  }

  // `turbo:before-stream-render` on the document: one of this tab's write
  // answers replacing the column's part, which carries the digest of the
  // place it was drawn for.
  answeredWrite(event) {
    const stream = event.target
    if (stream.getAttribute?.("target") !== SCREEN_PART) return

    const part = stream.templateContent?.querySelector(`#${SCREEN_PART}`)
    if (part) this.adopt(part.dataset.mediaPartPlace, part.dataset.mediaPlaceDigest)
  }

  // `turbo:before-cache` on the document: what this wrote into the page is
  // taken back, so a page restored from Turbo's snapshot holds no notice
  // that its fresh controller knows nothing of.
  reset() {
    this.gone = false
    if (this.hasSlotTarget) this.slotTarget.replaceChildren()
  }

  // --- The fetch -------------------------------------------------------------

  async fetchPart() {
    const marker = this.marker
    if (!this.running || !marker) return

    const url = new URL(this.urlValue, window.location.href)
    url.searchParams.set("folder", marker.dataset.mediaPlace)
    for (const [ name, value ] of Object.entries(this.query())) url.searchParams.set(name, value)
    if (this.pickerValue) url.searchParams.set("picker", "1")

    lastFetch = Date.now()
    this.request?.abort()
    const request = this.request = new AbortController()
    let html
    try {
      const response = await fetch(url, { headers: { Accept: "text/html" }, credentials: "same-origin", cache: "no-store", signal: request.signal })
      if (!response.ok) return
      html = await response.text()
    } catch {
      // Aborted, or the network failed: the next signal fetches again.
      return
    }
    if (this.request !== request || !this.running) return
    this.request = null

    const template = document.createElement("template")
    template.innerHTML = html
    const id = this.pickerValue ? PICKER_PART : SCREEN_PART
    const part = template.content.getElementById(id)
    const old = (this.pickerValue ? this.element : document).querySelector(`#${id}`)
    if (!part || !old) return

    this.replace(old, part)
    // A navigation meanwhile shows another place, drawn with its own digest.
    const gone = part.hasAttribute("data-media-place-gone")
    if (this.marker !== marker || (!gone && marker.dataset.mediaPlace !== part.dataset.mediaPartPlace)) return

    if (gone || part.dataset.mediaPlaceDigest !== this.held(marker)) this.notice(gone)
  }

  // The search the grid shows: the screen's `data-media-query`, the picker's
  // frame address.
  query() {
    const kept = {}
    if (this.pickerValue) {
      const frame = this.element.querySelector("turbo-frame#media-picker-grid")
      const address = frame?.src ? new URL(frame.src, window.location.href) : null
      for (const name of [ "q", "filter" ]) {
        const value = address?.searchParams.get(name)
        if (value) kept[name] = value
      }
      return kept
    }
    try {
      const query = JSON.parse(this.element.dataset.mediaQuery || "{}")
      for (const name of [ "q", "filter" ]) {
        if (typeof query?.[name] === "string" && query[name] !== "") kept[name] = query[name]
      }
    } catch {
      // No search named: the part's rows link to the place alone.
    }
    return kept
  }

  replace(old, part) {
    const focus = this.focusIn(old)
    const list = old.querySelector("nav")
    const scroll = list?.scrollTop ?? 0
    old.replaceWith(part)
    const newList = part.querySelector("nav")
    if (newList) newList.scrollTop = scroll
    part.querySelector(TREES)?.dispatchEvent(new CustomEvent("tree:changed", { bubbles: true }))
    if (focus) this.refocus(part, focus)
  }

  // What has the focus inside the old part: its id, or its row's place and
  // its place among the row's controls.
  focusIn(old) {
    const active = document.activeElement
    if (!active || active === document.body || !old.contains(active)) return null

    const row = active.closest("[data-media-place]")
    const index = row ? controls(row).indexOf(active) : -1
    return { id: active.id || null, place: row?.dataset.mediaPlace ?? null, index }
  }

  refocus(part, { id, place, index }) {
    let target = id ? part.querySelector(`[id="${CSS.escape(id)}"]`) : null
    if (!target && place != null) {
      const row = part.querySelector(`[data-media-place="${CSS.escape(place)}"]`)
      target = row ? controls(row)[Math.max(index, 0)] : null
    }
    target?.focus({ preventScroll: true })
  }

  // --- The notice -----------------------------------------------------------

  notice(gone) {
    this.gone = gone
    if (!this.hasSlotTarget || !this.hasNoticeTarget || this.slotTarget.childElementCount > 0) return

    this.slotTarget.append(this.noticeTarget.content.cloneNode(true))
  }

  // "Show changes": the place's frame loaded again (All media when its folder
  // is gone), and the notice taken away.
  show(event) {
    event?.preventDefault()
    const gone = this.gone
    this.gone = false
    if (this.hasSlotTarget) this.slotTarget.replaceChildren()

    if (this.pickerValue) {
      const frame = this.element.querySelector("turbo-frame#media-picker-grid")
      if (!frame) return
      if (!gone) return void frame.reload()

      const address = new URL(frame.src || window.location.href, window.location.href)
      address.searchParams.delete("folder")
      address.searchParams.delete("page")
      frame.src = address.toString()
      return
    }

    const address = new URL(window.location.href)
    if (gone) for (const name of [ "folder", "page", "selected", "select" ]) address.searchParams.delete(name)
    Turbo.visit(address.toString(), { frame: "content", action: gone ? "advance" : "replace" })
  }
}

// The controls of a row a person can reach, in document order.
function controls(row) {
  return [ ...row.querySelectorAll("a[href], button, select, [tabindex]") ]
}
