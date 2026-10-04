import { Controller } from "@hotwired/stimulus"

// Same-page `#fragment` links in CS Studio (round 3, Task 1 fix round 2 and
// its deferred g1-g4; final wave B). On <body>, for every such link wherever
// it is: an error summary's links to its fields (a screen's own, or the New
// page / New post dialog's), Settings' in-page nav, the media panel's "See
// where it's used", and a ⌘K row that leads to a section of the screen that
// is already showing ("Settings › AI translation" used on Settings).
//
// Left to Turbo such a link is a NAVIGATION -- it tests the absolute
// `link.href`, which never begins with "#" (`findLinkFromClickTarget`): a
// frame navigation that fetches the screen again, without what was typed and
// without the errors the link belongs to; or, for a `_top` link, a visit to
// the page that is showing, which an unsaved form's leave guard then asks
// about ("Leave without saving?" for a jump that leaves nothing). Left to the
// BROWSER it adds a history entry (`…/new#user_email_address`) that Turbo
// didn't write and never adopts: after a save, Back to it found the next
// screen's document under the form's URL.
// So neither gets it. Turbo is kept out (cancelling `turbo:click` makes the
// session stand back; stopping it here, in the capture phase on `document`,
// keeps it from the frames' own interceptors), the click itself is cancelled,
// and the jump is made by hand: focus on the target (one that can't take it
// is made able to, as a skip link's target is) and the target in view. No
// `location.hash`, no history entry -- Back keeps meaning "the previous
// screen".
//
// - A link inside an open dialog whose target is outside it closes the dialog
//   first (the ⌘K palette): a modal would keep the focus from leaving.
// - A target that isn't there, or a hash that can't be decoded, is still no
//   navigation: nothing moves, and the console says which link it was, so
//   whoever wrote the id notices.
// `admin--save-bar` stands back from these links for the same reason (its
// `onFrameLink`); the two listeners may run in either order.
export default class extends Controller {
  connect() {
    this.onClick = (event) => this.jump(event)
    document.addEventListener("turbo:click", this.onClick, true)
  }

  disconnect() {
    document.removeEventListener("turbo:click", this.onClick, true)
  }

  jump(event) {
    const link = event.target
    if (event.defaultPrevented || !(link instanceof Element)) return
    const within = targetWithinThePage(event.detail.url)
    if (!within) return

    event.preventDefault()
    event.stopPropagation()
    event.detail.originalEvent?.preventDefault()
    if (!within.element) {
      console.warn("admin--fragment-links: the link's target is not on this screen", link)
      return
    }
    const dialog = link.closest("dialog[open]")
    if (dialog && !dialog.contains(within.element)) dialog.close()
    jumpTo(within.element)
  }
}

// A `#fragment` link to the page that is showing: `{ element }` -- the element
// it names, or null when there is none or the hash is malformed -- and null
// for every other URL.
export function targetWithinThePage(url) {
  let target
  try {
    target = new URL(url, document.baseURI)
  } catch {
    return null
  }
  if (target.hash.length < 2 || target.origin !== location.origin ||
      target.pathname !== location.pathname || target.search !== location.search) return null
  try {
    return { element: document.getElementById(decodeURIComponent(target.hash.slice(1))) }
  } catch {
    return { element: null }
  }
}

// What following the fragment would have done, without the history entry.
// `scrollIntoView` with no `behavior` jumps unless the page's CSS asks for
// smooth scrolling, so it is named: no animation for a reader who asked for
// reduced motion.
function jumpTo(element) {
  if (element.tabIndex < 0 && !element.hasAttribute("tabindex")) element.setAttribute("tabindex", "-1")
  element.focus({ preventScroll: true })
  const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches
  element.scrollIntoView({ block: "center", behavior: still ? "instant" : "auto" })
}
