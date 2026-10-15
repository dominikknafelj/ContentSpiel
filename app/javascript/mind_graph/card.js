// The selection card (mind graph canvas spec §5.3; pages in the mind graph,
// spec §7): what a click on a node opens, and the only place a selection
// leads anywhere. HTML over the canvas, standing beside its node
// (`card_placement.js`; `app.js` moves it), so its links are links --
// reachable by keyboard, opened in a new tab like any other -- and a click on
// the canvas never navigates by itself.
//
// FOUR CARDS, one per kind of node that can be selected ("+N more" is not
// selected: a press on it opens the list, `app.js`). Each reads top to
// bottom, ON SCREEN AND IN THE DOCUMENT alike (the notes handoff's decision
// 12), so the Tab key walks the card as it reads:
//
//   a POST   its type's dot and name with its status chip; the title; "3
//            related · 2 tags" (left out for a post added from the list,
//            whose lines nobody counted); its open notes; "Open post",
//            "Focus", Pin
//   a PAGE   (design answer, part one §5) its mark and its address in mono
//            with its status chip; the title; "4 child pages · lists 112
//            posts"; its open notes, as on a post's card; "Open page",
//            "Focus", Pin. Home's is the same card
//   a TAG    the square and "Tag"; its name; "2 posts"; "Show posts with
//            this tag", "Focus", Pin
//   a POST TYPE a page lists, and "All posts" (design answer F1) its hub's
//            mark and "Post type"; its name (a retired type's ends
//            "(retired)", `graph_data.js`); how many posts of it the viewer
//            reads; Pin. NO LINK: it leads nowhere, and the pages that list
//            it are its neighbours on the canvas
//
// then the Close button in the corner (×, named for a screen reader; LAST in
// the document, so Tab meets the actions first). The actions LOOK like CS
// Studio's buttons and are what they do: what leads somewhere is a link, and
// Pin / Unpin changes the graph, so it is a button. "Open post" and "Open
// page" have a key of their own: Enter on the selected node -- on the
// canvas, or on the card as it takes the focus from the list -- opens the
// record (`open()` below, which presses the link, so it is the same
// navigation). A tag and a post type have nothing to open.
//
// EVERY FIGURE IS THE DATA'S, which the server narrowed to what the viewer
// may read (`app/queries/post_graph.rb`): a page's `child_count` and
// `listed_count`, a type's `count`. Nothing is read a second time for a
// card but its notes, through the notes' own scoped endpoint. A page's
// "lists 112 posts" is of the page, not of this picture: a neighbour page
// says it with no line of its own on screen.
//
// THE STATUS CHIP is `Admin::Ui::StatusChipComponent`'s, class for class: a
// dot in the status's token colour AND the word, so the colour is never the
// only cue. A live record that has more to say carries its second state
// after the label (design answer G4, verbatim):
//   "● Live · Unpublished changes"          no second dot
//   "● Live · ● Change scheduled 14 Oct"    a warn dot: warn means "scheduled"
// A chip of two states is as wide as the card, so it stands in a row of its
// own under the first (a READING: the design drew the chip, not the card
// around it).
// Those two rows are for the eye, and hidden from a screen reader, which is
// given the Status key's own words in one sentence (H6: one set of words):
// "Live, unpublished changes", "Live, change scheduled 14 Oct". The state is
// the data's `status` and `changes` (`Publishing::State`'s), never worked
// out here, and the day is the server's (`change_on`, CS Studio's short
// date): this formats no date. `data-status` is the state's name.
//
// A MARK. A post's is its type's dot and a tag's the square, CS Studio's own
// classes. A page's and a post type's are small canvases drawn by the
// renderer the graph is drawn by (`swatches.js`: `markCanvas`, painted here
// once the card's content is in the document), so a card cannot show a hub
// the canvas does not have. A mark shows the KIND: the chip says the state.
//
// Built with `textContent` and `href` only: a title, a tag's name and a
// page's address are the editor's text, whatever they contain. A URL comes
// from a template the server built with its route helpers (`__ID__`,
// `__NAME__`), never from a path written here; a record's own editor URL
// arrives with its node. The buttons' classes are
// `Admin::Ui::ButtonComponent`'s and a type's dot is
// `Admin::Ui::ContentTypeDotComponent`'s, both handed over by the view
// (`buttonClasses`, `dotClasses`), so neither is copied here.
//
// `createCard(container, { text, number, urls, typeLabels, dotClasses, buttonClasses,
// onClose, onPin, onChange })` answers `{ show(node, { pinned, pinnable }),
// setPinned(pinned), open(), hide() }` (`pinnable: false` leaves the Pin button out:
// with no layout there is nothing to hold; `show` answers whether the node's
// kind has a card, and does nothing for one that has none). `text` is
// `messages(element)`, `number` groups a figure as the messages' language does,
// `urls` the six templates (`postFocus`, `tagFocus`, `tagPosts`, `pageFocus`,
// and `postNotes` and `pageNotes`, a record's notes as JSON), `typeLabels` a
// content type's human name by its stored name, `onClose` what the Close
// button does (the app clears the selection, which hides the card), `onPin`
// what Pin / Unpin does (the app pins or releases the node and says which
// with `setPinned`) and `onChange` what the notes call when they arrived or
// one was added: the card's height changed, and the node's count may have.
import { cardNotes } from "mind_graph/card_notes"
import { recordId } from "mind_graph/ids"
import { markCanvas, paintMarks } from "mind_graph/swatches"

const STATUS_DOTS = { draft: "bg-meta", scheduled: "bg-warn", live: "bg-ok" }
const DOT = "h-1.5 w-1.5 rounded-full"
// Which of the five states a node is in (`Publishing::State`'s, as the data
// says it in `status` and `changes`): the chip's `data-status`, and the key
// of the sentence a screen reader is given. Only a LIVE record has a second
// state.
const stateOf = (node) => (node.status === "live" && node.changes ? (node.changes === "scheduled" ? "live_change_scheduled" : "live_with_changes") : node.status)
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

export function createCard(container, { text, number = String, urls, typeLabels, dotClasses, buttonClasses, onClose, onPin, onChange }) {
  let pin = null

  const element = (tag, className, content) => {
    const node = document.createElement(tag)
    if (className) node.className = className
    if (content != null) node.textContent = content
    return node
  }
  // A mark is decoration: the words beside it say what the node is. A class
  // string makes one of CS Studio's own (a type's dot, the tag's square); a
  // page's and a post type's is the renderer's canvas (`markCanvas`).
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
  // A count in its sentence: the figure grouped as the messages' language
  // groups it ("lists 2,040 posts"); the number only chooses the form.
  const counted = (key, count) => text.t(key, { count, figure: number(count) })
  // "Open post" or "Open page", marked so that Enter on the selected node
  // can press it. The address is the node's own, which the server built.
  const openLink = (node, key) => {
    const anchor = link(buttonClasses.primary, text.t(key), node.url)
    anchor.dataset.mindGraphCardOpen = ""
    return anchor
  }
  // Two counts in the small label style with a "·" between them, which a
  // screen reader is not read.
  const pairOf = (first, second) => {
    const counts = element("p", "m-0 flex flex-wrap gap-x-1.5")
    const separator = label("·")
    separator.setAttribute("aria-hidden", "true")
    counts.append(label(first), separator, label(second))
    return counts
  }

  // The status chip (the header says how it reads). None for a status it
  // does not know.
  function statusChip(node) {
    if (!Object.hasOwn(STATUS_DOTS, node.status)) return []

    const chip = element("span", "admin-status-chip inline-flex shrink-0 items-center gap-1.5 rounded-cs bg-sunken px-2 py-0.5 text-xs text-ink")
    const state = stateOf(node)
    chip.dataset.status = state
    chip.append(mark(`${DOT} ${STATUS_DOTS[node.status]}`))
    if (state === node.status) {
      chip.append(text.t(`mind_graph.script.card.status.${node.status}`))
      return [ chip ]
    }

    // The second part is one piece, its dot with its words, so that where
    // the chip is too wide for the card it breaks before the piece and never
    // between a dot and what the dot is of.
    const date = node.change_on ?? ""
    const seen = element("span", "inline-flex flex-wrap items-center gap-x-1 gap-y-0.5")
    seen.setAttribute("aria-hidden", "true")
    seen.dataset.chipSeen = ""
    const second = element("span", "inline-flex items-center gap-1.5")
    if (node.changes === "scheduled") second.append(mark(`${DOT} ${STATUS_DOTS.scheduled}`), text.t("mind_graph.script.card.status.change_scheduled", { date }))
    else second.append(text.t("mind_graph.script.card.status.unpublished_changes"))
    seen.append(text.t("mind_graph.script.card.status.live"), element("span", "text-meta", "·"), second)
    chip.classList.replace("shrink-0", "max-w-full")
    chip.append(seen, element("span", "sr-only", text.t(`mind_graph.script.card.status.${state}`, { date })))
    return [ chip ]
  }

  // Where the chip stands. One that says one state is beside what the node
  // is, in the first row. One that says two is as wide as the card ("● Live
  // · ● Change scheduled 14 Oct" beside a page's address and the Close
  // button left the address no room, and ran under the button): it has the
  // row under the first to itself.
  const twoStates = (node) => Object.hasOwn(STATUS_DOTS, node.status) && stateOf(node) !== node.status
  const chipBeside = (node) => (twoStates(node) ? [] : statusChip(node))
  function chipBelow(node) {
    if (!twoStates(node)) return []
    const row = element("div", "flex")
    row.dataset.chipRow = ""
    row.append(...statusChip(node))
    return [ row ]
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
    // A post added to the canvas from the list (`app.js`, `addPost`) was
    // read with no line counted: its two counts are null, and the card says
    // nothing of them rather than "0 related · 0 tags" of a post that may
    // have both.
    const known = node.related_count !== null && node.tag_count !== null
    return [
      heading(mark(dotClass(dotClasses, node)), kind, ...chipBeside(node)),
      ...chipBelow(node),
      title(node),
      ...(known ? [ pairOf(counted("mind_graph.script.card.related", node.related_count ?? 0), counted("mind_graph.script.card.tags", node.tag_count ?? 0)) ] : []),
      cardNotes(node, { text, type: "post", url: fill(urls.postNotes, "__ID__", recordId(node.id)), recordUrl: node.url, onChange }),
      actions(
        openLink(node, "mind_graph.script.card.open_post"),
        link(buttonClasses.secondary, text.t("mind_graph.script.card.focus"), fill(urls.postFocus, "__ID__", recordId(node.id)))
      )
    ]
  }

  // A page (pages spec §7; design answer, part one §5): its address and its
  // state, its title, "4 child pages · lists 112 posts", its open notes as
  // on a post's card, then "Open page", "Focus" and Pin. A page with no
  // address in the editing language or the default has none written.
  function page(node) {
    return [
      heading(markCanvas(node), element("span", "min-w-0 truncate font-cs-mono text-label text-meta", node.path || ""), ...chipBeside(node)),
      ...chipBelow(node),
      title(node),
      pairOf(counted("mind_graph.script.card.child_pages", node.child_count ?? 0), counted("mind_graph.script.card.lists_posts", node.listed_count ?? 0)),
      cardNotes(node, { text, type: "page", url: fill(urls.pageNotes, "__ID__", recordId(node.id)), recordUrl: node.url, onChange }),
      actions(
        openLink(node, "mind_graph.script.card.open_page"),
        link(buttonClasses.secondary, text.t("mind_graph.script.card.focus"), fill(urls.pageFocus, "__ID__", recordId(node.id)))
      )
    ]
  }

  function tag(node) {
    const counts = element("p", "m-0 flex")
    counts.append(label(counted("mind_graph.script.card.tag_posts", node.count)))
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

  // A post type a page lists, and "All posts" (design answer F1): what it
  // is, its name, how many posts of it the viewer reads, and Pin. It leads
  // nowhere: the pages that list it are its neighbours on the canvas.
  function type(node) {
    const counts = element("p", "m-0 flex")
    counts.append(label(counted("mind_graph.script.card.tag_posts", node.count ?? 0)))
    return [ heading(markCanvas(node), element("span", "text-sm text-dim", text.t("mind_graph.script.card.post_type"))), title(node), counts, actions() ]
  }

  const CARDS = { post, page, tag, type }

  function setPinned(pinned) {
    if (!pin) return
    pin.textContent = text.t(pinned ? "mind_graph.script.card.unpin" : "mind_graph.script.card.pin")
  }

  return {
    show(node, { pinned = false, pinnable = true } = {}) {
      // A kind with no card (a "+N more" pill, which is not selected, or a
      // kind a later build draws before it has one) is answered false:
      // nothing is shown, the card that is open stays, and nothing throws.
      // `hasOwn`, because a kind is data and `CARDS.constructor` is no card.
      if (!Object.hasOwn(CARDS, node.kind)) return false
      container.replaceChildren(...CARDS[node.kind](node), closeButton())
      // A canvas has colours only once it is in the document.
      paintMarks(container)
      setPinned(pinned)
      pin.hidden = !pinnable
      // Named by its title while it has one (the view's own name is the
      // general "Selected in the graph").
      container.setAttribute("aria-labelledby", "mind-graph-card-title")
      container.hidden = false
      return true
    },
    setPinned,
    // Enter on the selected node: the record's own "Open post" or "Open
    // page", pressed. A link's click, so it is the navigation a pointer
    // would start. A tag's and a post type's card has no such link, and
    // nothing happens.
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
