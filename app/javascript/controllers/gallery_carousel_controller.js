import { Controller } from "@hotwired/stimulus"

// The Gallery block's carousel (`Blocks::GalleryComponent`, gallery block
// spec §7.3 to §7.5): the APG's basic carousel with a slide picker. A
// controller of the site's own, which a visitor's page alone registers
// (`PUBLIC_ONLY` in controllers/index.js): a theme that replaces the
// template keeps the carousel by writing the same markup (the identifier,
// the targets `controls track slide previous next position pick status`,
// the `position` and `moved` values, the `previous`, `next` and `show`
// actions with a pick's `data-gallery-carousel-index-param`, and `keydown`
// on the track and the controls; docs/reference/theming.md, "The Gallery
// block").
//
// PROGRESSIVE ENHANCEMENT. Without this script the carousel is its track, a
// row the browser scrolls and snaps (touch, trackpad, scrollbar, the arrow
// keys on the focused track). What only the script makes work is `hidden`
// in the markup and shown at `connect`: the controls, the status, and the
// wrappers of the position and of the picks (in the default template the
// foot and the picker), which have no target of their own. A wrapper is an
// ancestor of the position or of a pick inside the carousel that does not
// hold the track, so a template that puts the position straight into the
// carousel's element has nothing of it hidden or shown.
//
// WHERE IT IS. An IntersectionObserver on the slides, the track its root,
// keeps how much of each slide is in view, and the slide most in view is
// the current one: a swipe, a scroll, a button and a key all end in that
// reading. A move by a button, a pick or a key is marked at once (the
// position, the picker's `aria-current`, the buttons' `disabled`, the
// state) and the track scrolls there; the readings on the way are not
// marked until the observer finds the slide moved to most in view, the
// scroll ends (`scrollend`), or the person takes the track by the pointer
// or the wheel, so a pick three slides on does not count up through the
// slides it passes. Previous and Next move one slide and are disabled at
// the ends: nothing wraps (a wrapping scroll row jumps across every slide)
// and nothing moves by itself (spec §7.6). When a move disables the focused
// button the focus goes to the other one, never to the page.
//
// KEYS, on the track and on the controls, only without a modifier (Alt+Left
// is the browser's Back): Left and Right one slide, Home and End the first
// and the last. In a right-to-left row the arrow keys follow the screen:
// Left is the next image, as the next image lies to the left, while
// Previous and Next keep their reading-order meaning. The direction is
// read at each key, from the track, so a page whose direction changes needs
// no new connect.
//
// THE SCROLL is the distance between the slide's rectangle and the
// track's, added to the track's own offset: no sign of `scrollLeft` is
// reasoned about, which differs in a right-to-left row. It is a `scrollTo`
// to that end and never a `scrollBy`: Chrome stops a relative scroll at the
// first slide it passes (`scroll-snap-stop: always`, gallery.css), so a
// pick or End two slides away would land one slide on.
//
// MOTION. A move scrolls smoothly only under
// `prefers-reduced-motion: no-preference`, and at once otherwise (an
// explicit `behavior` wins over the stylesheet's `scroll-behavior`).
//
// WORDS. The status, a polite live region, speaks only when a button, a
// pick or a key moved the carousel ("Image 3 of 12", the `moved` value); a
// swipe or a scroll is the person's own gesture and is not talked over: it
// empties the status instead, so the next press is heard even when its
// sentence is the one said before. The position is the `position` value.
// Both are the server's sentences in the visitor's language with
// `%{index}` and `%{count}` left in, so this file holds no English.
//
// STATE on the element, `data-gallery-carousel-state`: `first`, `middle`
// or `last`, which a theme's stylesheet may read (the default hides the
// track's scrollbar under it).
//
// WHAT IS TAKEN BACK, AND WHEN (the Code block's incident,
// code_copy_controller.js, and the Form block's, form_send_controller.js).
// Turbo copies a page at `turbo:before-cache`, also a page that is NOT left
// (an anchor of it, `site.js`), so nothing is taken back there: words or
// `hidden` changed under a visitor who never left would be a carousel that
// says or shows something else than where it is. Instead
//   - `connect` decides everything again: the status emptied, the current
//     slide read from the rectangles, and the position, the picker, the
//     buttons and the state written from it, so a copy Turbo shows again
//     on Back (put into the document, where `connect` runs before a frame
//     is drawn) never shows another copy's words;
//   - `disconnect` disconnects the observer, removes the listeners and puts
//     back what the server drew: `hidden` on what it showed, the status
//     empty, the position the first slide's, `aria-current` on the first
//     pick, neither button disabled, and no state.
// The elements are kept as fields at `connect`: a controller taken off its
// element finds no target any more, and `disconnect` has to reach them.
export default class extends Controller {
  static targets = [ "controls", "track", "slide", "previous", "next", "position", "pick", "status" ]
  static values = { position: String, moved: String }

  connect() {
    this.track = this.trackTarget
    this.slides = this.slideTargets
    this.buttons = [ this.previousTarget, this.nextTarget ]
    this.position = this.hasPositionTarget ? this.positionTarget : null
    this.picks = this.pickTargets
    this.status = this.hasStatusTarget ? this.statusTarget : null
    this.shown = this.revealed()
    this.heading = null
    this.ratios = new Map()

    if (this.status) this.status.textContent = ""
    this.mark(this.nearest())
    this.shown.forEach((element) => { element.hidden = false })

    this.observer = new IntersectionObserver((entries) => this.observed(entries), { root: this.track, threshold: [ 0, 0.25, 0.5, 0.75, 1 ] })
    this.slides.forEach((slide) => this.observer.observe(slide))
    this.ended = () => this.release()
    this.taken = () => { this.heading = null }
    this.track.addEventListener("scrollend", this.ended)
    this.track.addEventListener("pointerdown", this.taken, { passive: true })
    this.track.addEventListener("wheel", this.taken, { passive: true })
  }

  // Every field is asked for before it is used: a `connect` that threw
  // half-way (a theme's template without a required target) has kept only
  // some of them, and the take-back must not throw over that error.
  disconnect() {
    this.observer?.disconnect()
    this.track?.removeEventListener("scrollend", this.ended)
    this.track?.removeEventListener("pointerdown", this.taken)
    this.track?.removeEventListener("wheel", this.taken)

    this.shown?.forEach((element) => { element.hidden = true })
    if (this.status) this.status.textContent = ""
    if (this.position && this.slides) this.position.textContent = this.fill(this.positionValue, 0)
    this.picks?.forEach((pick, index) => {
      if (index === 0) pick.setAttribute("aria-current", "true")
      else pick.removeAttribute("aria-current")
    })
    this.buttons?.forEach((button) => { button.disabled = false })
    this.element.removeAttribute("data-gallery-carousel-state")
  }

  previous() {
    this.move(this.index - 1)
  }

  next() {
    this.move(this.index + 1)
  }

  show({ params: { index } }) {
    this.move(Number(index) - 1)
  }

  keydown(event) {
    if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return

    const forward = getComputedStyle(this.track).direction === "rtl" ? "ArrowLeft" : "ArrowRight"
    const back = forward === "ArrowLeft" ? "ArrowRight" : "ArrowLeft"
    const to = { [forward]: this.index + 1, [back]: this.index - 1, Home: 0, End: this.slides.length - 1 }[event.key]
    if (to === undefined) return

    event.preventDefault()
    this.move(to)
  }

  // A move asked for by a button, a pick or a key: marked and said at once,
  // then scrolled to. Past an end it does nothing.
  move(to) {
    const index = Math.max(0, Math.min(this.slides.length - 1, to))
    if (index === this.index) return

    const behavior = matchMedia("(prefers-reduced-motion: no-preference)").matches ? "smooth" : "instant"
    const box = this.track.getBoundingClientRect()
    const rect = this.slides[index].getBoundingClientRect()
    const rtl = getComputedStyle(this.track).direction === "rtl"
    const left = rtl ? rect.right - box.right : rect.left - box.left

    this.heading = index
    this.mark(index)
    if (this.status) this.status.textContent = this.fill(this.movedValue, index)
    this.track.scrollTo({ left: this.track.scrollLeft + left, behavior })
  }

  observed(entries) {
    entries.forEach((entry) => this.ratios.set(entry.target, entry.intersectionRatio))
    const best = this.mostInView()
    if (best === null) return
    if (this.heading !== null) {
      if (best === this.heading) this.heading = null
      return
    }
    this.settle(best)
  }

  // The scroll ended: where it is now is read from the rectangles, as the
  // observer's last readings may still be of a moment before the end.
  release() {
    this.heading = null
    this.settle(this.nearest())
  }

  // A reading of the person's own scroll: marked, and the status emptied,
  // never spoken.
  settle(index) {
    if (index === this.index) return

    this.mark(index)
    if (this.status) this.status.textContent = ""
  }

  mark(index) {
    const focused = document.activeElement
    const last = this.slides.length - 1
    this.index = index

    if (this.position) this.position.textContent = this.fill(this.positionValue, index)
    this.picks.forEach((pick, each) => {
      if (each === index) pick.setAttribute("aria-current", "true")
      else pick.removeAttribute("aria-current")
    })
    const [ previous, next ] = this.buttons
    previous.disabled = index === 0
    next.disabled = index === last
    this.element.setAttribute("data-gallery-carousel-state", index === 0 ? "first" : (index === last ? "last" : "middle"))

    if (focused === previous && previous.disabled && !next.disabled) next.focus()
    if (focused === next && next.disabled && !previous.disabled) previous.focus()
  }

  // The slide most in view by the observer's readings, the earlier one on a
  // tie, or null before the first reading.
  mostInView() {
    let best = null
    let most = 0
    this.slides.forEach((slide, index) => {
      const ratio = this.ratios.get(slide) || 0
      if (ratio > most) {
        best = index
        most = ratio
      }
    })
    return best
  }

  // The slide whose start stands nearest the track's start, from the
  // rectangles: where the carousel is before the observer has said.
  nearest() {
    const box = this.track.getBoundingClientRect()
    const rtl = getComputedStyle(this.track).direction === "rtl"
    let best = 0
    let distance = Infinity
    this.slides.forEach((slide, index) => {
      const rect = slide.getBoundingClientRect()
      const away = Math.abs(rtl ? rect.right - box.right : rect.left - box.left)
      if (away < distance) {
        best = index
        distance = away
      }
    })
    return best
  }

  // What this script shows: the controls, the status, and each wrapper of
  // the position and of the picks inside the carousel that does not hold
  // the track.
  revealed() {
    const wrappers = (element) => {
      const found = []
      for (let parent = element?.parentElement; parent && parent !== this.element && this.element.contains(parent); parent = parent.parentElement) {
        if (!parent.contains(this.track)) found.push(parent)
      }
      return found
    }
    const parts = [ this.controlsTarget, this.status, ...wrappers(this.position), ...wrappers(this.picks[0]) ]
    return [ ...new Set(parts.filter(Boolean)) ]
  }

  fill(pattern, index) {
    return pattern.replaceAll("%{index}", String(index + 1)).replaceAll("%{count}", String(this.slides.length))
  }
}
