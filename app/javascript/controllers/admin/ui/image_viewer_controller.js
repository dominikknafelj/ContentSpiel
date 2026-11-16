import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"

// The image viewer (`Admin::Ui::ImageViewerComponent`), on its dialog, which
// the admin layout draws once and EMPTY. This fills it from a pressed
// picture and takes it all back again; nothing of a note is in the dialog
// before an opening or after a close.
//
// OPENING. A click anywhere in the document is heard here (`open`), and
// only a plain primary click on an `a[data-image-viewer-item]` is taken:
// button 0, no ⌘, Ctrl, Shift or Alt, not already handled. Any other click
// is the browser's, and the link opens its picture in a new tab, as it does
// without this script. Enter on a focused link is such a click. The pictures
// to step through are the trigger's own group, its nearest
// `[data-image-viewer-group]` (a note's message), in document order, READ
// ONCE at the opening: a live refresh that adds or drops files while the
// viewer is open changes nothing here until the next opening, and a group
// drawn twice on one page is never counted twice.
//
// A STEP (`show`) writes the head (the name, which is also the picture's
// alt, and the facts), the position, both links and the download's file
// name, and the GIF part's values on the frame: `gif` first, then `src`
// (`admin--ui--gif`, whose `src` is the one writer of the picture's address,
// and whose new address starts still, so each opening and each step starts
// a GIF still). The previous picture leaves the stage at once: the frame is
// hidden until `load` (`loaded`) or `error` (`failed`, the notice). If
// neither came 400 ms after the step, Loading shows (`LOADING_DELAY`); a
// picture already there when the timer runs (the thumbnail's own, from the
// browser's cache) never shows it, so nothing flickers.
//
// THE KEYS. ← and → step from anything in the dialog (the component's
// `keydown.left` and `keydown.right`), never with a modifier: Alt+← and ⌘←
// are the browser's Back. The arrows are disabled at the ends, never
// wrapped, and when a step disables the arrow that has the focus, the focus
// moves to the other arrow of the pair that is drawn (the stage's, or the
// phone's in the foot), never to <body>.
//
// THE FOCUS. On opening: Next when it can be pressed, else Previous, else
// Close. On close (`closed`, the dialog's `close`: Escape, Close, the
// backdrop): the picture that opened it, as an element (a live refresh keeps
// a message's pictures as the elements they were), else the first viewer
// item with its address, else the nearest element around it that takes the
// focus by script (a note's thread, `tabindex="-1"` with an id), looked up
// again by id. Given explicitly, because Safari does not focus a clicked
// link, so the browser's own return would land nowhere.
//
// THE TAKE-BACK (`takeBack`, at `turbo:before-cache` and `disconnect`):
// the dialog closed, the picture's address removed (through the GIF part,
// whose own `cache` puts its still back), the head, the position, the links
// and the live region emptied, the notice and Loading hidden, the group and
// the opener dropped. Turbo's snapshot therefore never holds an open or a
// stale viewer, and Back shows none.
const LOADING_DELAY = 400
const ARROWS = { previous: "next", next: "previous", phonePrevious: "phoneNext", phoneNext: "phonePrevious" }

export default class extends Controller {
  static targets = [ "title", "facts", "stage", "frame", "picture", "notice", "loading", "previous", "next", "phonePrevious", "phoneNext", "position", "original", "download", "announcer" ]

  connect() {
    this.opening = (event) => this.open(event)
    this.caching = () => this.takeBack()
    document.addEventListener("click", this.opening)
    document.addEventListener("turbo:before-cache", this.caching)
  }

  disconnect() {
    document.removeEventListener("click", this.opening)
    document.removeEventListener("turbo:before-cache", this.caching)
    this.takeBack()
  }

  get words() {
    return messages(this.element)
  }

  open(event) {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.defaultPrevented) return
    const trigger = event.target.closest?.("a[data-image-viewer-item]")
    const group = trigger?.closest("[data-image-viewer-group]")
    if (!group || this.element.open) return

    event.preventDefault()
    const links = [ ...group.querySelectorAll("a[data-image-viewer-item]") ]
    this.items = links.map((link) => ({ href: link.href, name: link.dataset.name ?? "", facts: link.dataset.facts ?? "", gif: "imageViewerGif" in link.dataset }))
    this.opener = trigger
    this.openerHref = trigger.getAttribute("href")
    this.returnId = trigger.parentElement?.closest("[tabindex='-1'][id]")?.id
    this.show(links.indexOf(trigger))
    this.element.showModal()
    const first = [ "next", "phoneNext", "previous", "phonePrevious" ].map((name) => this[`${name}Target`]).find((arrow) => this.pressable(arrow))
    ;(first ?? this.closeButton)?.focus()
  }

  show(index, { announce = false } = {}) {
    const item = this.items[index]
    const count = this.items.length
    this.index = index

    this.clearLoading()
    this.noticeTarget.hidden = true
    this.frameTarget.hidden = true
    this.titleTarget.textContent = item.name
    this.factsTarget.textContent = item.facts
    const position = this.words.t("components.ui.image_viewer.position", { index: index + 1, count })
    this.positionTarget.textContent = position
    this.originalTarget.href = item.href
    this.downloadTarget.href = item.href
    this.downloadTarget.download = item.name
    this.pictureTarget.alt = item.name
    this.frameTarget.setAttribute("data-admin--ui--gif-gif-value", String(item.gif))
    this.frameTarget.setAttribute("data-admin--ui--gif-src-value", item.href)

    for (const name of Object.keys(ARROWS)) {
      const arrow = this[`${name}Target`]
      arrow.hidden = count < 2
      arrow.disabled = name.toLowerCase().includes("previous") ? index === 0 : index === count - 1
    }
    this.announcerTarget.textContent = announce ? this.words.t("components.ui.image_viewer.stepped", { name: item.name, position }) : ""

    this.loadingTimer = setTimeout(() => {
      this.loadingTimer = null
      if (!this.pictureTarget.complete) this.loadingTarget.hidden = false
    }, LOADING_DELAY)
  }

  previous(event) {
    this.step(-1, event)
  }

  next(event) {
    this.step(1, event)
  }

  step(by, event) {
    if (event.type === "keydown") {
      if (event.altKey || event.metaKey || event.ctrlKey || event.shiftKey) return
      event.preventDefault()
    }
    if (!this.items) return
    const index = this.index + by
    if (index < 0 || index >= this.items.length) return

    const focused = Object.keys(ARROWS).find((name) => this[`${name}Target`] === document.activeElement)
    this.show(index, { announce: true })
    if (focused && this[`${focused}Target`].disabled) this[`${ARROWS[focused]}Target`].focus()
  }

  // `load` on the picture.
  loaded() {
    if (!this.items) return
    this.clearLoading()
    this.noticeTarget.hidden = true
    this.frameTarget.hidden = false
  }

  // `error` on the picture: gone (a 404, the right lost while the page was
  // open) or not drawable. The name, the facts and both links stay.
  failed() {
    if (!this.items) return
    this.clearLoading()
    this.frameTarget.hidden = true
    this.noticeTarget.hidden = false
  }

  closed() {
    const { opener, openerHref, returnId } = this
    this.takeBack()
    if (!opener) return

    const twin = openerHref && document.querySelector(`a[data-image-viewer-item][href="${CSS.escape(openerHref)}"]`)
    const back = opener.isConnected ? opener : twin ?? (returnId && document.getElementById(returnId))
    back?.focus()
  }

  takeBack() {
    this.items = null
    this.opener = null
    this.openerHref = null
    this.returnId = null
    this.clearLoading()
    if (this.element.open) this.element.close()

    this.frameTarget.setAttribute("data-admin--ui--gif-src-value", "")
    this.frameTarget.setAttribute("data-admin--ui--gif-gif-value", "false")
    this.frameTarget.hidden = false
    this.pictureTarget.alt = ""
    for (const target of [ this.titleTarget, this.factsTarget, this.positionTarget, this.announcerTarget ]) target.textContent = ""
    for (const link of [ this.originalTarget, this.downloadTarget ]) link.removeAttribute("href")
    this.downloadTarget.download = ""
    this.noticeTarget.hidden = true
  }

  clearLoading() {
    clearTimeout(this.loadingTimer)
    this.loadingTimer = null
    this.loadingTarget.hidden = true
  }

  // An arrow a person can press now: drawn at this width (the stage's pair
  // off a phone, the foot's on one) and not at its end.
  pressable(arrow) {
    return !arrow.hidden && !arrow.disabled && arrow.checkVisibility()
  }

  get closeButton() {
    return this.element.querySelector("header form[method=dialog] button")
  }
}
