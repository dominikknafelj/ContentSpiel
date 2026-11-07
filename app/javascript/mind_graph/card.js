// The selection card: what a click on a node opens, and the only place a
// selection leads anywhere. HTML over the canvas, standing beside its node
// (`card_placement.js`; `selection.js` moves it), so its links are links --
// reachable by keyboard, opened in a new tab like any other -- and a click on
// the canvas never navigates by itself.
//
// FOUR CARDS, one per kind of node that can be selected ("+N more" is not
// selected: a press on it opens the list, `list_reads.js`). Each reads top to
// bottom, ON SCREEN AND IN THE DOCUMENT alike (the notes handoff's decision
// 12), so the Tab key walks the card as it reads:
//
//   a POST   its type's dot and name with its status chip; the title; "3
//            related · 2 tags" (left out for a post added from the list,
//            whose lines nobody counted); its open notes; "Open post",
//            "Focus", Pin
//   a PAGE   (design answer, part one §5) its mark and its address
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
// then Close in the corner (the shared icon button, named "Close"; LAST in
// the document, so Tab meets the actions first; the card's own classes in
// `show.html.erb` stand it in the corner). The actions LOOK like CS
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
// THE STATUS CHIP is `Admin::Ui::StatusChipComponent`'s own, cloned from
// the parts (`parts.js`), never drawn here: a record in one state has the
// chip of that state beside what it is, and the chip's `data-status`
// (`live`, `draft`, `scheduled`) names the state. A live record that has
// more to say carries its second state as the editor's header does: the
// Live chip, then the unpublished chip, or the words "Change scheduled 14
// Oct" with the server's day (`change_on`, CS Studio's short date; this
// formats no date). Two states are as wide as the card, so they stand in a
// row of their own under the first (`[data-chip-row]`), which may wrap and
// whose `data-status` (`live_with_changes`, `live_change_scheduled`) names
// the state: a chip is never changed after it is cloned. That row is for
// the eye, and hidden from a screen reader, which is given the legend's
// status words in one sentence (one set of words) at the end of the first
// row: "Live, unpublished changes", "Live, change scheduled 14 Oct". The
// state is the data's `status` and `changes` (`Publishing::State`'s), never
// worked out here.
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
// (`buttonClasses`, `dotClasses`), so neither is copied here; the chips and
// Close are the parts' clones.
//
// `createCard(container, { text, number, urls, typeLabels, dotClasses, buttonClasses,
// parts, onClose, onPin, onChange })` answers `{ show(node, { pinned, pinnable }),
// setPinned(pinned), open(), hide() }` (`pinnable: false` leaves the Pin button out:
// with no layout there is nothing to hold; `show` answers whether the node's
// kind has a card, and does nothing for one that has none). `text` is
// `messages(element)`, `number` groups a figure as the messages' language does,
// `urls` the six templates (`postFocus`, `tagFocus`, `tagPosts`, `pageFocus`,
// and `postNotes` and `pageNotes`, a record's notes as JSON), `typeLabels` a
// content type's human name by its stored name, `parts` the clones
// (`readParts`), `onClose` what the Close
// button does (the app clears the selection, which hides the card), `onPin`
// what Pin / Unpin does (the app pins or releases the node and says which
// with `setPinned`) and `onChange` what the notes call when they arrived or
// one was added: the card's height changed, and the node's count may have.
import { cardNotes } from "mind_graph/card_notes"
import { recordId } from "mind_graph/ids"
import { markCanvas, paintMarks } from "mind_graph/swatches"

// The states a chip is drawn for: a status the parts have no chip of has
// none on the card.
const STATUSES = [ "draft", "scheduled", "live" ]
// Which of the five states a node is in (`Publishing::State`'s, as the data
// says it in `status` and `changes`): the chip row's `data-status`, and the
// key of the sentence a screen reader is given. Only a LIVE record has a
// second state.
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
// A tag's square, edged in the tag hue as the canvas draws it (`drawTag`).
// The type dot and this square are CSS beside the canvas's own drawing:
// `mind_graph_guards_test` holds each to the token the canvas uses.
export const TAG_MARK = "h-2 w-2 shrink-0 border border-graph-tag bg-surface"

export function createCard(container, { text, number = String, urls, typeLabels, dotClasses, buttonClasses, parts, onClose, onPin, onChange }) {
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
  const label = (content) => element("span", "text-label text-meta", content)
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

  // Where the state stands (the header says how it reads). One state is its
  // chip, beside what the node is, in the first row. Two have the row under
  // the first to themselves, which wraps inside the card; the first row
  // then ends with the sentence a screen reader is given in their place.
  const known = (node) => STATUSES.includes(node.status)
  const twoStates = (node) => known(node) && stateOf(node) !== node.status
  const chipBeside = (node) => {
    if (!known(node)) return []
    if (!twoStates(node)) return [ parts.part(`status-${node.status}`) ]
    return [ element("span", "sr-only", text.t(`mind_graph.script.card.status.${stateOf(node)}`, { date: node.change_on ?? "" })) ]
  }
  function chipBelow(node) {
    if (!twoStates(node)) return []
    const row = element("div", "flex flex-wrap items-center gap-x-1.5 gap-y-1")
    row.dataset.chipRow = ""
    row.dataset.status = stateOf(node)
    row.setAttribute("aria-hidden", "true")
    const second = node.changes === "scheduled"
      ? element("span", "min-w-0 text-xs text-dim", text.t("mind_graph.script.card.status.change_scheduled", { date: node.change_on ?? "" }))
      : parts.part("unpublished")
    row.append(parts.part("status-live"), second)
    return [ row ]
  }

  // The first row: what the node is. It keeps clear of Close, which stands
  // in the card's top-right corner.
  function heading(...what) {
    const row = element("div", "flex min-h-6 items-center gap-2 pr-8")
    row.append(...what)
    return row
  }

  // The way out: the shared icon button, cloned, named "Close". It is the
  // card's LAST child, so the Tab key meets the actions first -- a person who
  // came from the list wants "Open post", not the way back.
  function closeButton() {
    const close = parts.part("close")
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
      cardNotes(node, { text, buttonClasses, type: "post", url: fill(urls.postNotes, "__ID__", recordId(node.id)), recordUrl: node.url, onChange }),
      actions(
        openLink(node, "mind_graph.script.card.open_post"),
        link(buttonClasses.secondary, text.t("mind_graph.script.card.focus"), fill(urls.postFocus, "__ID__", recordId(node.id)))
      )
    ]
  }

  // A page (design answer, part one §5): its address and its
  // state, its title, "4 child pages · lists 112 posts", its open notes as
  // on a post's card, then "Open page", "Focus" and Pin. A page with no
  // address in the editing language or the default has none written.
  function page(node) {
    return [
      heading(markCanvas(node), element("span", "min-w-0 truncate text-small text-meta", node.path || ""), ...chipBeside(node)),
      ...chipBelow(node),
      title(node),
      pairOf(counted("mind_graph.script.card.child_pages", node.child_count ?? 0), counted("mind_graph.script.card.lists_posts", node.listed_count ?? 0)),
      cardNotes(node, { text, buttonClasses, type: "page", url: fill(urls.pageNotes, "__ID__", recordId(node.id)), recordUrl: node.url, onChange }),
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
