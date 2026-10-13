// The selection card (mind graph canvas spec §5.3): what a click on a node
// opens, and the only place a selection leads anywhere. HTML over the canvas,
// standing beside its node (`card_placement.js`; `app.js` moves it), so its
// links are links -- reachable by keyboard, opened in a new tab like any other
// -- and a click on the canvas never navigates by itself.
//
// In order: the mark and the kind ("Blog", "Tag") with a post's status chip,
// and the Close button in the corner beside them (×, named for a screen
// reader; last in the document, so Tab meets the actions first); the title;
// one line of counts in the small label style ("3 related · 2 tags", or a
// tag's "2 posts"); then the actions, which LOOK like CS Studio's buttons and are what
// they do: "Open post", "Focus" and a tag's "Show posts with this tag" lead
// somewhere, so they are links; Pin / Unpin changes the graph, so it is a
// button. A post's card also has its notes (`card_notes.js`; notes spec §4.4;
// handoff, "Node card thread list"): "Open notes · N", the rows and the field
// that starts a note. They stand under the title and its counts and the
// actions follow them, ON SCREEN AND IN THE DOCUMENT alike (the notes
// handoff's decision 12: the document order follows the screen), so the Tab
// key walks the card as it reads. "Open post" is therefore no longer the
// first stop, and has a key of its own instead: Enter on the selected node
// -- on the canvas, or on the card as it takes the focus from the list --
// opens the post (`open()` below, which presses the link, so it is the same
// navigation). A tag has no notes, and no post to open.
//
// Built with `textContent` and `href` only: a title or a tag's name is the
// editor's text, whatever it contains. A URL comes from a template the server
// built with its route helpers (`__ID__`, `__NAME__`), never from a path
// written here; a post's own editor URL arrives with its node. The buttons'
// classes are `Admin::Ui::ButtonComponent`'s and a type's dot is
// `Admin::Ui::ContentTypeDotComponent`'s, both handed over by the view
// (`buttonClasses`, `dotClasses`), so neither is copied here.
//
// `createCard(container, { text, urls, typeLabels, dotClasses, buttonClasses,
// onClose, onPin, onChange })` answers `{ show(node, { pinned, pinnable }),
// setPinned(pinned), open(), hide() }` (`pinnable: false` leaves the Pin button out:
// with no layout there is nothing to hold). `text` is `messages(element)`,
// `urls` the four templates (`postFocus`, `tagFocus`, `tagPosts`, and
// `postNotes`, a post's notes as JSON), `typeLabels` a content type's human
// name by its stored name, `onClose` what the Close button does (the app
// clears the selection, which hides the card), `onPin` what Pin / Unpin
// does (the app pins or releases the node and says which with `setPinned`)
// and `onChange` what the notes call when they arrived or one was added: the
// card's height changed, and the node's count may have.
//
// The status chip is `Admin::Ui::StatusChipComponent`'s, class for class: a dot in
// the status's token colour AND the word, so the colour is never the only cue.
import { cardNotes } from "mind_graph/card_notes"
import { recordId } from "mind_graph/ids"

const STATUS_DOTS = { draft: "bg-meta", scheduled: "bg-warn", live: "bg-ok" }
// A URL template filled with one value: a function as the replacement, because
// a string would have its `$&` and `$1` read as patterns. (`encodeURIComponent`
// escapes `$` anyway; this does not rely on it.)
export const fill = (template, placeholder, value) => template.replace(placeholder, () => encodeURIComponent(value))

// A type's dot by its colour slot (`dotClasses` are slots 1-12 in order); a
// type that is no longer registered has no slot and gets the neutral ring, as
// `Admin::Ui::ContentTypeDotComponent` gives it. `node_list.js` marks its rows
// with the same two.
export const dotClass = (dotClasses, node) =>
  `h-[7px] w-[7px] shrink-0 rounded-full ${node.colour_index == null ? "border border-meta" : dotClasses[(node.colour_index - 1) % dotClasses.length]}`
export const TAG_MARK = "h-2 w-2 shrink-0 border border-meta bg-surface"

export function createCard(container, { text, urls, typeLabels, dotClasses, buttonClasses, onClose, onPin, onChange }) {
  let pin = null

  const element = (tag, className, content) => {
    const node = document.createElement(tag)
    if (className) node.className = className
    if (content != null) node.textContent = content
    return node
  }
  const mark = (className) => {
    const node = element("span", className)
    node.setAttribute("aria-hidden", "true")
    return node
  }
  const link = (className, label, href) => {
    const anchor = element("a", className, label)
    anchor.href = href
    return anchor
  }
  const label = (content) => element("span", "font-cs-mono text-label uppercase tracking-mono text-meta", content)
  // "Open post", marked so that Enter on the selected node can press it.
  const openLink = (node) => {
    const anchor = link(buttonClasses.primary, text.t("mind_graph.script.card.open_post"), node.url)
    anchor.dataset.mindGraphCardOpen = ""
    return anchor
  }

  function statusChip(status) {
    const chip = element("span", "admin-status-chip inline-flex shrink-0 items-center gap-1.5 rounded-cs border border-line-strong px-2 py-0.5 text-xs text-ink")
    chip.dataset.status = status
    chip.append(mark(`h-1.5 w-1.5 rounded-full ${STATUS_DOTS[status]}`), text.t(`mind_graph.script.card.status.${status}`))
    return chip
  }

  // The first row: what the node is. It keeps clear of the Close button,
  // which stands in the card's top-right corner.
  function heading(...what) {
    const row = element("div", "flex min-h-6 items-center gap-2 pr-6")
    row.append(...what)
    return row
  }

  // The way out: × in the card's corner, named for a screen reader. It is the
  // card's LAST child, so the Tab key meets the actions first -- a person who
  // came from the list wants "Open post", not the way back.
  function closeButton() {
    const close = element("button", "absolute right-1.5 top-1.5 cursor-pointer rounded-cs px-1.5 text-lg leading-none text-meta hover:bg-sunken hover:text-ink", "×")
    close.type = "button"
    close.setAttribute("aria-label", text.t("mind_graph.script.card.close"))
    close.title = text.t("mind_graph.script.card.close")
    close.dataset.mindGraphCardClose = ""
    close.addEventListener("click", onClose)
    return close
  }

  const title = (node) => {
    const heading = element("h2", "m-0 break-words text-base font-semibold leading-snug text-ink", node.title)
    heading.id = "mind-graph-card-title"
    return heading
  }

  function actions(...links) {
    const row = element("div", "mt-1 flex flex-wrap gap-1.5")
    pin = element("button", buttonClasses.secondary)
    pin.type = "button"
    pin.dataset.mindGraphCardPin = ""
    pin.addEventListener("click", onPin)
    row.append(...links, pin)
    return row
  }

  function post(node) {
    // A type that is no longer registered has no label: its stored name, as
    // the type dot shows it everywhere else. `hasOwn`, because a stored name
    // is data and `typeLabels.constructor` is not a label.
    const kind = element("span", "min-w-0 truncate text-sm text-dim", Object.hasOwn(typeLabels, node.type) ? typeLabels[node.type] : node.type)
    const counts = element("p", "m-0 flex flex-wrap gap-x-1.5")
    const separator = label("·")
    separator.setAttribute("aria-hidden", "true")
    counts.append(
      label(text.t("mind_graph.script.card.related", { count: node.related_count ?? 0 })), separator,
      label(text.t("mind_graph.script.card.tags", { count: node.tag_count ?? 0 }))
    )
    // A post added to the canvas from the list (`app.js`, `addPost`) was
    // read with no line counted: its two counts are null, and the card says
    // nothing of them rather than "0 related · 0 tags" of a post that may
    // have both.
    const known = node.related_count !== null && node.tag_count !== null
    return [
      heading(mark(dotClass(dotClasses, node)), kind, ...(Object.hasOwn(STATUS_DOTS, node.status) ? [ statusChip(node.status) ] : [])),
      title(node),
      ...(known ? [ counts ] : []),
      cardNotes(node, { text, url: fill(urls.postNotes, "__ID__", recordId(node.id)), postUrl: node.url, onChange }),
      actions(
        openLink(node),
        link(buttonClasses.secondary, text.t("mind_graph.script.card.focus"), fill(urls.postFocus, "__ID__", recordId(node.id)))
      )
    ]
  }

  function tag(node) {
    const counts = element("p", "m-0 flex")
    counts.append(label(text.t("mind_graph.script.card.tag_posts", { count: node.count })))
    return [
      heading(mark(TAG_MARK), element("span", "text-sm text-dim", text.t("mind_graph.script.card.tag"))),
      title(node),
      counts,
      actions(
        link(buttonClasses.primary, text.t("mind_graph.script.card.show_tagged"), fill(urls.tagPosts, "__NAME__", node.title)),
        link(buttonClasses.secondary, text.t("mind_graph.script.card.focus"), fill(urls.tagFocus, "__ID__", recordId(node.id)))
      )
    ]
  }

  // A page, a post type and "+N more" until each has its card (pages plan,
  // Task 8): its name, and Pin.
  const plain = (node) => [ heading(), title(node), actions() ]

  function setPinned(pinned) {
    if (!pin) return
    pin.textContent = text.t(pinned ? "mind_graph.script.card.unpin" : "mind_graph.script.card.pin")
  }

  return {
    show(node, { pinned = false, pinnable = true } = {}) {
      container.replaceChildren(...({ tag, post }[node.kind] || plain)(node), closeButton())
      setPinned(pinned)
      pin.hidden = !pinnable
      // Named by its title while it has one (the view's own name is the
      // general "Selected in the graph").
      container.setAttribute("aria-labelledby", "mind-graph-card-title")
      container.hidden = false
    },
    setPinned,
    // Enter on the selected node: the post's own "Open post", pressed. A
    // link's click, so it is the navigation a pointer would start. A tag's
    // card has no such link, and nothing happens.
    open() {
      if (!container.hidden) container.querySelector("a[data-mind-graph-card-open]")?.click()
    },
    hide() {
      pin = null
      container.hidden = true
      container.removeAttribute("aria-labelledby")
      container.replaceChildren()
    }
  }
}
