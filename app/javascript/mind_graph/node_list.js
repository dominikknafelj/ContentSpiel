// Every node the graph draws, as a row beside the canvas: the path for a keyboard and a
// screen reader, since nothing on a canvas can take focus, and a way to find
// a node by name for everyone.
//
// A ROW IS A BUTTON, and it does to the graph what a click on the node does:
// it selects the node, and the app brings it to the middle of the canvas and
// opens its card -- whose "Open post" is what leads to the editor. A row
// never navigates. Its accessible name says all of that in one sentence
// ("Alpha: post, 2 connections. Shows it in the graph."), because the mark is
// decoration and the count alone is a bare number. Hovering or focusing a row
// lights its node up on the canvas (`onHover`), and the row of the selected
// node is marked (`aria-current`) and scrolled into view INSIDE the panel --
// never with `scrollIntoView`, which would scroll the page as well where the
// panel stands under the canvas.
//
// FOUR GROUPS: "Pages · N" first, in TREE order (not by connections: a
// tree is read by its order), then "Posts · N" and "Tags · N",
// best-connected first as on the canvas, then "Post types · N": a row for
// each post-type node and for "All posts", so each has a keyboard path to
// its card. Each group is a list named by its heading. A POST TYPE'S ROW has
// a small copy of the hub as its mark, and as its number the POSTS of that
// type the viewer can read (a tag's row has its connections there), in the
// order the data has them -- colour-slot order, then retired types, then
// "All posts" last.
//
// A ROW IS THE PAGES TREE'S ROW (`Admin::Ui::TreeItemComponent`): its
// classes are that component's `CLASSES`, handed in as `treeClasses` (the
// view's `data-tree-classes`), and its glyphs are the parts', so this file
// writes no class of a row, no indent and no tint of its own, and the two
// trees cannot drift apart (`tree_item_parity_test.rb` measures them). Left
// to right: the disclosure box, the mark box, the title, the chips under
// the title, and the figure at the row's end, shown at rest on every row. A
// page has a disclosure box, holding the disclosure part when its children
// have rows here, empty otherwise so the marks line up; a post's, a tag's
// and a post type's row is flat (no disclosure box), unless a pill hangs off
// it. The disclosure is drawn open and folds nothing: the row is the one
// control, a button, so the disclosure is a silent part and never a button
// inside it. The row of the selected node takes the tree's selected look.
//
// A GROUP'S HEADING is a row of the tree's too, 28px like any, and never
// selected: the disclosure part, its kind's icon chip (`Admin::Ui::
// IconChipComponent`, the sidebar's: a page the structure's, a post, a tag
// and a post type the lists') in the mark box, then the group's words in
// the label style with the figure after the middle dot in the count style.
// 12px stand above every heading but the first. A heading adds no step: the
// rows under it start at its left edge, and a page steps `--cs-tree-step`
// per level below Home, as in Pages.
//
// "+N MORE" HAS A ROW TOO (a pill pressed on the canvas opens the list,
// and nothing on a canvas can be pressed by a keyboard). Each pill in view
// is the CHILD ROW of what it hangs off -- the post type's, "All posts"' or
// the tag's, which draws a disclosure for it -- one step in, flat, in the
// pill's own words ("+92 more") in the accent, and named whole for a screen
// reader, beginning with those words ("+92 more: 92 more posts Blog lists,
// not in view. Activate to show them."). It is counted in no heading: it is
// no post type and no tag. A pill whose hub has no row (its kind is switched
// off) stands at the end of the posts, and with no post drawn either, after
// the groups: a pill in view is never without a row. Activating it asks the
// app for the pill's rows (`onMore(id)`), as a press on the pill does, and
// the focus goes to the first of them (the rule under "THE FOCUS IS NOT
// LOST").
//
// A PILL'S ROWS (`showRows` with `back`) stand under a heading that names
// them ("More from Blog · 92") with "Back to the list" beside it, a button,
// before the rows in the document; ESCAPE pressed anywhere in the rows is
// the same way back (`back.onBack`), and so it is on the error line of a
// pill's read that failed, which offers the button beside "Try again". The
// rows of "Not listed on any page" have neither: their checkbox is the way
// back, and Escape there is nobody's.
//
// THE PAGES' TREE IS A TREE FOR A SCREEN READER TOO, not an indent alone: a
// page's row stands in a list INSIDE its parent's item (by the data's
// `parent`), so the nesting is the document's and is announced as a level,
// and the step is the children list's (`CLASSES.children`). A page whose
// parent has no row here (not readable, or not in this view) stands at the
// top level of the group, with no step: nothing it could hang from is drawn.
//
// A ROW'S STATE is shown as the posts list shows it, by its rule: an
// exception stands out and a plain live row has nothing. Under the title, on
// a line of their own, a draft's and a scheduled record's row carries its
// `StatusChipComponent`,
// and any record whose unpublished mark is set (the data's `unpublished`)
// the `UnpublishedChipComponent`, each cloned from the parts and never
// changed after, in a wrapper hidden from a screen reader. The row's name
// says the same words after the title ("Soon, Scheduled: post, 3
// connections. ..."), read from the chips' own keys.
//
// A ROW'S MARK. A page's is the tree's page glyph, Home's the house, as in
// Pages (cloned from the parts). A post type's is a small canvas drawn by
// the renderer the graph is drawn by (`swatches.js`: `markCanvas`, painted
// once the rows are in the document), so a hub's row cannot show a look the
// canvas does not have. A post's is its type's dot and a tag's the square,
// CS Studio's own (`card.js`). NOTHING HERE IS LAZY, AND THE BOUND IS THE
// HUBS: one canvas and one drawing for each, made again with the rows on
// every redraw (a legend toggle, a post added, a theme change), never for a
// page, a post or a tag, of which there can be thousands.
//
// ABOVE THE GROUPS, "Not listed on any page", a checkbox:
// while it is on, the list shows the rows the app hands `showRows` IN PLACE
// OF the groups, and the canvas is left as it is. The same form serves the
// posts behind a page's "+N more", with "Open in Posts →" under them. The
// checkbox is there only when the app says so (`unlisted`): for a viewer who
// reads no page every post is one no page lists, and the filter says nothing.
//
// A ROW THAT IS NOT IN VIEW. A row of `showRows` whose post the canvas does
// not draw says "not in view" where its count would stand, and pressing it
// asks the app to ADD the post (`onAdd(row)`: the row is the post's node as
// the data has it, so no request is made). Its name says what it is and what
// a press does: "Small sites, long lives, blog post, not in view. Activate
// to add it to the graph." -- with the post TYPE's name, as the messages'
// language lowers it; a post of a RETIRED type has no label, and says "talk,
// retired type". One that is drawn selects, like any row.
//
// A READ THAT FAILED is said IN THE LIST, not in a toast, beside what it
// was for: the line and a small "Try again" button under it (`fail`), in a
// `role="alert"` so it is announced. The checkbox above stays, so the
// filter can be let go. When the focus was in the rows it is put on "Try
// again": the row or the button that was pressed is gone, and the keyboard
// is not left on nothing.
//
// WHILE A READ IS OUT the rows' region is `aria-busy` (`setBusy`, the
// app's to say): its rows are about to be replaced. No words: nobody gave
// any for a pending list.
//
// THE FOCUS IS NOT LOST when the rows are drawn again (a post was added, a
// kind was switched, "Try again" brought the rows): `render` and `showRows`
// replace the rows' own region and never the checkbox, and when the focus
// was in that region it is put on the row of the same node, else on the
// first row, else on the checkbox.
//
// Text goes in with `textContent`; no path is written here but the one the
// app hands in (`link`). `createList(container, { text, number, dotClasses,
// typeLabels, treeClasses, retryClass, parts, unlisted, onSelect, onHover,
// onAdd, onMore, onUnlisted })` answers `{ render(nodes), showRows({
// heading, rows, inView, link, back }), fail(line, { label, onRetry, focus,
// back }), clear(), setUnlisted(on), setBusy(on), mark(id), row(id),
// destroy() }`: `render` replaces the
// rows with the four groups (the app calls it once per load and once per
// filter change), `clear` empties the rows while another graph is loaded,
// `mark` moves the mark to the row of `id` (null for none). `back` is
// `{ label, onBack }`. `onSelect(id)`, `onMore(id)` and `onHover(id | null)`
// get a node's id as the data has it; `number` groups a figure as the
// messages' language does. A pill's node carries `of`, the name of what it
// hangs off. The listeners are on the rows' region, one of each, however
// many rows there are.
import { dotClass, TAG_MARK } from "mind_graph/card"
import { markCanvas, paintMarks } from "mind_graph/swatches"

const byDegree = (a, b) => b.degree - a.degree || String(a.title).localeCompare(String(b.title))
const byTree = (a, b) => a.order - b.order
// The order the data has them: colour-slot order, then the retired types,
// then "All posts" last.
const asGiven = () => 0
const LIST = "m-0 list-none p-0"
// A state's part and the key of its chip's own word (`ui.en.yml`), which the
// row's name says: the same words as the chip, from the same keys.
const STATE_WORDS = {
  "status-draft": "components.ui.status_chip.labels.draft",
  "status-scheduled": "components.ui.status_chip.labels.scheduled",
  unpublished: "components.ui.unpublished_chip.label"
}
const NAMES = { page: "mind_graph.script.list.select_page", post: "mind_graph.script.list.select_post", tag: "mind_graph.script.list.select_tag", type: "mind_graph.script.list.select_type" }
const LINK = "cursor-pointer rounded-cs text-sm text-accent underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
// Where a heading's figure stands in its words: the key is asked with this
// in place of the count and cut there, so the language keeps its own order
// and the figure alone takes the count style. No word holds the character.
const FIGURE = "\u0000"

export function createList(container, { text, number = String, dotClasses, typeLabels = {}, treeClasses: classes, retryClass = "", parts, unlisted: filterable = true, onSelect, onHover, onAdd, onMore = () => {}, onUnlisted }) {
  let rows = new Map()
  let absent = new Map()
  let marked = null
  let headings = 0
  // The way back from what is shown, while there is one (a pill's rows, or
  // the error line of a pill's read): what Escape in the rows' region does.
  let goBack = null

  const element = (tag, className, content) => {
    const created = document.createElement(tag)
    if (className) created.className = className
    if (content != null) created.textContent = content
    return created
  }
  // `role="list"`: a list styled without markers is not announced as one by
  // every screen reader, and here the nesting is what says a page's level.
  const listOf = (items = []) => {
    const list = element("ul", LIST)
    list.setAttribute("role", "list")
    list.append(...items)
    return list
  }

  // The filter and the rows' own region: `render` and `showRows` replace the
  // region and never the checkbox, so the focus stays on it while it is used.
  const filter = element("label", "flex cursor-pointer items-center gap-2 border-b border-line px-3 py-2 text-sm text-dim")
  const unlisted = document.createElement("input")
  unlisted.type = "checkbox"
  unlisted.className = "cs-checkbox"
  unlisted.dataset.mindGraphUnlisted = ""
  filter.append(unlisted, element("span", "", text.t("mind_graph.script.list.unlisted")))
  // The rows' region is the tree (`CLASSES.tree`), inside the column's gutter.
  const body = element("div", `${classes.tree} px-2 pt-2`)
  body.dataset.mindGraphRows = ""
  container.replaceChildren(...(filterable ? [ filter ] : []), body)
  const changed = () => onUnlisted(unlisted.checked)
  unlisted.addEventListener("change", changed)

  // "Back to the list": a button that reads as a link, as the legend's
  // "Status" does. It changes what the list shows and leads nowhere.
  const backButton = ({ label, onBack }) => {
    const button = element("button", `shrink-0 ${LINK}`, label)
    button.type = "button"
    button.dataset.mindGraphBack = ""
    button.addEventListener("click", onBack)
    return button
  }
  // A list named by `heading`, in a section that holds `head` (the heading,
  // or the heading with its way back) and the list.
  const named = (heading, list, { head = heading, wrapperClass = "" } = {}) => {
    const wrapper = element("section", wrapperClass)
    heading.id = `mind-graph-list-${(headings += 1)}`
    list.setAttribute("aria-labelledby", heading.id)
    wrapper.append(head, list)
    return wrapper
  }
  // A group of the four: its heading is a row of the tree, and its rows
  // the list it names, starting at the heading's left edge. `key` is the
  // group's words with `%{count}` where the figure stands.
  const group = (key, count, list, icon) => {
    const heading = element("h2", classes.row)
    const [ before, after = "" ] = text.t(key, { count: FIGURE }).split(FIGURE)
    const words = element("span", "text-label text-meta", before)
    words.append(element("span", "text-count", count), after)
    const title = element("span", classes.title)
    title.append(words)
    heading.append(parts.part("tree-disclosure"), markBox(parts.part(icon)), title)
    return named(heading, list, { wrapperClass: "not-first:mt-3" })
  }
  // The rows a filter or a pill brings, under a heading of their own. With
  // `back`, the way back stands beside the heading, before the rows.
  const section = (title, list, { back = null } = {}) => {
    const heading = element("h2", "m-0 flex min-w-0 items-center gap-2 px-1 pb-1 pt-1 text-label text-meta", title)
    if (!back) return named(heading, list)

    const head = element("div", "flex items-baseline justify-between gap-2 pr-1")
    head.append(heading, backButton(back))
    return named(heading, list, { head })
  }
  // The parts a page's or a post's row carries under its title, by the
  // posts list's own rule (`posts_screen/table_component.html.erb`): the
  // status chip unless the record is live, then the unpublished chip when
  // the data's `unpublished` (`Publishing::State#changes?`, the posts list's
  // `unpublished_changes?`) is set. So a scheduled record can carry both,
  // and a live record with a change scheduled carries the unpublished chip
  // only when it is marked too.
  const statesOf = (node) => {
    if (node.kind !== "page" && node.kind !== "post") return []
    return [ ...(Object.hasOwn(STATE_WORDS, `status-${node.status}`) ? [ `status-${node.status}` ] : []), ...(node.unpublished ? [ "unpublished" ] : []) ]
  }
  // The chips, in one wrapper hidden from a screen reader: the row's name
  // says the same words (`stated`).
  const stateChips = (node) => {
    const names = statesOf(node)
    if (!names.length) return []
    const held = element("span", "flex shrink-0 flex-wrap items-center gap-1")
    held.setAttribute("aria-hidden", "true")
    held.append(...names.map((name) => parts.part(name)))
    return [ held ]
  }
  // The tree's title box, the whole title in its tooltip as in Pages.
  const titleBox = (words) => {
    const title = element("span", classes.title, words)
    title.title = words
    return title
  }
  // A row's title, and on a line of their own under it its chips when it
  // has any: the title keeps the row's whole width and is cut only by the
  // row's edge, so in the list's narrow column a row with two chips, or a
  // page deep in the tree, still says which record it is. The chips wrap
  // rather than run past the row's figure.
  const titled = (node) => {
    const chips = stateChips(node)
    if (!chips.length) return titleBox(node.title)
    const stack = element("span", "flex min-w-0 flex-1 flex-col gap-0.5")
    stack.append(titleBox(node.title), ...chips)
    return stack
  }
  // The mark box, holding `mark` (a pill's is empty, so its words stand
  // under its hub's title).
  const markBox = (mark = null) => {
    const box = element("span", classes.mark)
    if (mark) box.append(mark)
    return box
  }
  // A row: the tree's row as a button, with its disclosure box. `opens`: a
  // row whose children have rows here, which draws the disclosure part;
  // `flat`: a row with no disclosure box. Any other row keeps the box
  // empty, so its mark lines up with its siblings'.
  const rowButton = (id, { opens = false, flat = false } = {}) => {
    const button = element("button", flat ? `${classes.row} ${classes.row_flat}` : classes.row)
    button.type = "button"
    button.dataset.nodeId = id
    if (opens) button.append(parts.part("tree-disclosure"))
    else if (!flat) button.append(element("span", classes.disclosure))
    return button
  }
  // The list a page's or a hub's children stand in, inside its item: the
  // tree's step.
  const childrenOf = (item) => {
    const held = item.querySelector(":scope > ul")
    if (held) return held
    const list = element("ul", classes.children)
    list.setAttribute("role", "list")
    list.dataset.treeChildren = ""
    return item.appendChild(list)
  }
  // The title as a row's name says it: followed by each chip's own word
  // ("Soon, Scheduled, Unpublished changes"), so what is seen is heard and
  // the name begins with what the row shows.
  const stated = (node) => statesOf(node).reduce((title, name) => text.t("mind_graph.script.list.stated", { title, state: text.t(STATE_WORDS[name]) }), node.title)
  // A post's type as a row that is not in view names it: the type's label
  // in lower case, as the messages' language lowers it ("blog post"); a
  // RETIRED type has no label, and is its stored name in lower case with its
  // own sentence ("talk, retired type"). `hasOwn`, because a stored name is
  // data.
  const lower = (words) => String(words ?? "").toLocaleLowerCase(text.locale())
  const addName = (node) => Object.hasOwn(typeLabels, node.type)
    ? text.t("mind_graph.script.list.add_post", { title: stated(node), type: lower(typeLabels[node.type]) })
    : text.t("mind_graph.script.list.add_retired_post", { title: stated(node), type: lower(node.type) })
  // What stands at a row's end, and what its name counts: a post type's is
  // its posts, every other row's its connections.
  const figure = (node) => (node.kind === "type" ? node.count ?? 0 : node.degree)
  const markFor = (node) => {
    if (node.kind === "page") return parts.part(node.home ? "tree-home-mark" : "tree-page-mark")
    if (node.kind === "type") return markCanvas(node)
    const mark = element("span", node.kind === "tag" ? TAG_MARK : dotClass(dotClasses, node))
    mark.setAttribute("aria-hidden", "true")
    return mark
  }
  // The same row while there is no graph to add its post to (the graph is
  // still being read, or its read failed): what it is, and that it is not
  // in view, with no word of activating it.
  const absentName = (node) => Object.hasOwn(typeLabels, node.type)
    ? text.t("mind_graph.script.list.absent_post", { title: stated(node), type: lower(typeLabels[node.type]) })
    : text.t("mind_graph.script.list.absent_retired_post", { title: stated(node), type: lower(node.type) })
  // `opens`: the row's children have rows here (a page's, or a pill that
  // hangs off it).
  const row = (node, { notInView = false, addable = true, opens = false } = {}) => {
    const item = document.createElement("li")
    const button = rowButton(node.id, { opens, flat: node.kind !== "page" && !opens })
    button.setAttribute("aria-label", notInView ? (addable ? addName(node) : absentName(node)) : text.t(NAMES[node.kind], { title: stated(node), count: figure(node) }))
    // At the row's end: the figure, or the words of a row that is not in view.
    const notShown = () => element("span", "text-label text-meta", text.t("mind_graph.script.list.not_in_view"))
    const trailing = element("span", classes.trailing)
    trailing.append(notInView ? notShown() : element("span", classes.count, figure(node)))
    button.append(markBox(markFor(node)), titled(node), trailing)
    item.append(button)
    rows.set(node.id, button)
    if (notInView) {
      button.dataset.notInView = ""
      // Without a graph the row adds nothing and says so: it is there to be
      // read, and is drawn again as one that adds once the graph has come.
      if (addable) absent.set(node.id, node)
      else button.setAttribute("aria-disabled", "true")
    }
    return item
  }
  // A pill's row: flat, the pill's own words in the accent, and its whole
  // name. No mark: the row it hangs off is its parent.
  const pillRow = (pill) => {
    const item = document.createElement("li")
    const button = rowButton(pill.id, { flat: true })
    button.dataset.more = ""
    // The name begins with the words the row shows, so someone who says
    // what they see names it (WCAG 2.5.3, label in name).
    button.setAttribute("aria-label", text.t("mind_graph.script.list.more_row", { count: pill.count, figure: number(pill.count), target: pill.of ?? "", words: pill.title }))
    const title = element("span", classes.title)
    title.append(element("span", "text-accent", pill.title))
    button.append(markBox(), title)
    item.append(button)
    rows.set(pill.id, button)
    return item
  }
  // The pages as the tree they are: a page's item holds the list of its
  // children. The pages come in tree order, so a parent is met before its
  // children; one whose parent has no row here stands at the top level.
  // `opens`: the ids whose rows draw the disclosure.
  const tree = (pages, opens) => {
    const top = listOf()
    const items = new Map()
    for (const page of pages) {
      const item = row(page, { opens: opens.has(page.id) })
      const parent = items.get(page.parent)
      if (parent) childrenOf(parent).append(item)
      else top.append(item)
      items.set(page.id, item)
    }
    return top
  }
  const forget = () => {
    rows = new Map()
    absent = new Map()
    marked = null
    goBack = null
  }
  // Replaces the rows, and keeps the focus where it was: on the row of the
  // same node, else on the first row, else on the checkbox. Only when the
  // focus WAS in the rows: a list drawn while the person is elsewhere takes
  // nothing from them. The marks are drawn once the rows are in the page.
  const put = (...pieces) => {
    const held = body.contains(document.activeElement) ? document.activeElement.dataset.nodeId ?? "" : null
    body.replaceChildren(...pieces)
    paintMarks(body)
    if (held == null) return
    const next = rows.get(held) || body.querySelector("button[data-node-id]") || (filterable ? unlisted : null)
    next?.focus()
  }

  const rowOf = (event) => event.target.closest?.("button[data-node-id]")
  const click = (event) => {
    const button = rowOf(event)
    if (!button || button.getAttribute("aria-disabled") === "true") return
    if (button.dataset.more != null) onMore(button.dataset.nodeId)
    else if (absent.has(button.dataset.nodeId)) onAdd(absent.get(button.dataset.nodeId))
    else onSelect(button.dataset.nodeId)
  }
  // Escape in the rows' region goes back where there is a way back, and is
  // nobody's otherwise (it is not taken, so whatever else listens hears it).
  const keydown = (event) => {
    if (event.key !== "Escape" || !goBack || event.ctrlKey || event.metaKey || event.altKey || event.shiftKey) return
    event.preventDefault()
    event.stopPropagation()
    goBack()
  }
  const over = (event) => {
    const button = rowOf(event)
    if (button && !absent.has(button.dataset.nodeId)) onHover(button.dataset.nodeId)
  }
  const out = (event) => {
    if (rowOf(event)) onHover(null)
  }
  const listeners = { click, keydown, pointerover: over, pointerout: out, focusin: over, focusout: out }
  Object.entries(listeners).forEach(([ name, handler ]) => body.addEventListener(name, handler))

  function mark(id) {
    marked?.removeAttribute("aria-current")
    marked?.classList.remove(classes.row_selected)
    marked = id == null ? null : rows.get(id) || null
    if (!marked) return

    marked.setAttribute("aria-current", "true")
    marked.classList.add(classes.row_selected)
    // Into view within the panel only, and only as far as needed.
    const box = container.getBoundingClientRect()
    const rowBox = marked.getBoundingClientRect()
    if (rowBox.top < box.top) container.scrollTop -= box.top - rowBox.top
    else if (rowBox.bottom > box.bottom) container.scrollTop += rowBox.bottom - box.bottom
  }

  const line = (content) => element("p", "m-0 px-1 py-1 text-sm text-meta", content)

  return {
    render(nodes) {
      forget()
      const of = (kind, order) => nodes.filter((node) => node.kind === kind).sort(order)
      const groups = [ [ "pages", of("page", byTree), "icon-page" ], [ "posts", of("post", byDegree), "icon-post" ], [ "tags", of("tag", byDegree), "icon-tag" ], [ "types", of("type", asGiven), "icon-type" ] ]
        .filter(([ , found ]) => found.length)
      const pills = of("more", asGiven)
      if (!groups.length && !pills.length) return put(line(text.t("mind_graph.script.list.empty")))

      // The rows that draw a disclosure: a page whose children have rows,
      // and a hub a pill hangs off.
      const pageIds = new Set(nodes.filter((node) => node.kind === "page").map((node) => node.id))
      const opens = new Set([ ...nodes.filter((node) => node.kind === "page" && pageIds.has(node.parent)).map((node) => node.parent), ...pills.map((pill) => pill.target) ])
      const lists = new Map()
      const drawn = groups.map(([ name, found, icon ]) => {
        const list = name === "pages" ? tree(found, opens) : listOf(found.map((node) => row(node, { opens: opens.has(node.id) })))
        lists.set(name, list)
        return group(`mind_graph.script.list.${name}`, found.length, list, icon)
      })
      // Each pill the child of the row it hangs off; one with no such row
      // at the end of the posts, or after the groups when no post is drawn.
      const loose = []
      for (const pill of pills) {
        const hub = rows.get(pill.target)?.closest("li")
        if (hub) childrenOf(hub).append(pillRow(pill))
        else loose.push(pillRow(pill))
      }
      if (loose.length && lists.has("posts")) lists.get("posts").append(...loose)
      else if (loose.length) drawn.push(listOf(loose))
      put(...drawn)
    },
    // `addable: false`: there is no graph to add a post to, and a row that
    // is not in view only says so.
    // A filter's rows in place of the groups. `inView(id)`: whether the
    // canvas draws that post now. `back`: the rows are a pill's, and this
    // is the way back to the groups.
    showRows({ heading, rows: given, inView, link = null, back = null, addable = true }) {
      forget()
      goBack = back?.onBack ?? null
      const shown = [ section(heading, listOf(given.map((node) => row({ ...node, kind: "post" }, { notInView: !inView(node.id), addable }))), { back }) ]
      if (link) {
        const anchor = element("a", "mx-1 mt-2 inline-block text-sm text-accent underline", link.label)
        anchor.href = link.href
        anchor.dataset.mindGraphPostsLink = ""
        shown.push(anchor)
      }
      put(...shown)
    },
    // A read that failed: the line and a small button
    // that asks again, in the list. `focus`: the press that asked was the
    // button's own, which this call has just removed, so the new one takes
    // the focus and the keyboard is not left on nothing.
    // `back`: the read was a pill's, and the error line keeps the way back
    // to the groups beside "Try again" (and Escape goes back).
    fail(content, { label, onRetry, focus = false, back = null }) {
      const held = body.contains(document.activeElement)
      forget()
      goBack = back?.onBack ?? null
      const said = element("div", "flex flex-col items-start gap-2 px-1 py-1")
      said.setAttribute("role", "alert")
      const again = element("button", retryClass, label)
      again.type = "button"
      again.dataset.mindGraphRetry = ""
      again.addEventListener("click", onRetry)
      const controls = element("div", "flex flex-wrap items-center gap-3")
      controls.append(again, ...(back ? [ backButton(back) ] : []))
      said.append(element("p", "m-0 text-sm text-meta", content), controls)
      body.replaceChildren(said)
      if (focus || held) again.focus()
    },
    // The rows of a graph that is being replaced: nothing, until `render`.
    clear() {
      forget()
      body.replaceChildren()
    },
    setUnlisted(on) { unlisted.checked = on },
    // A read of the rows is out: what the region holds is about to change.
    setBusy(on) {
      if (on) body.setAttribute("aria-busy", "true")
      else body.removeAttribute("aria-busy")
    },
    mark,
    row: (id) => rows.get(id) || null,
    destroy() {
      unlisted.removeEventListener("change", changed)
      Object.entries(listeners).forEach(([ name, handler ]) => body.removeEventListener(name, handler))
      container.replaceChildren()
    }
  }
}
