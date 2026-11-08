// Every node the graph draws, as a row in the tree column beside the
// canvas: the path for a keyboard and a screen reader, since nothing on a
// canvas can take focus, and a way to find a node by name for everyone.
//
// THE LIST IS ONE TREE, an ARIA tree (`ul#mind-graph-tree[role=tree]`,
// named by the region's own name) with ONE TAB STOP: one item holds
// `tabindex="0"`, the marked one or else the first, every other `-1`, and
// the stop follows the focus. On the tree, Up and Down move to the previous
// or next item that shows, Right opens a folded parent or goes to its first
// child, Left folds an open parent or goes to its parent, Home and End go to
// the first and the last item that shows, `*` opens the item's whole branch,
// and Enter or Space does what a click on the row does. The focus never
// rests inside a branch that folds: it goes to the parent that folded.
//
// A ROW IS A TREEITEM, and it does to the graph what a click on the node
// does: it selects the node, and the app brings it to the middle of the
// canvas and opens its card -- whose "Open post" is what leads to the
// editor. A row never navigates. Its accessible name (`aria-label` on the
// treeitem) says all of that in one sentence ("Alpha: post, 2 connections.
// Shows it in the graph."), because the mark is decoration and the count
// alone is a bare number. A click on its disclosure folds or opens it, and
// a click anywhere else on the row selects; a find's Enter is a `.click()`
// on the treeitem itself, and selects. Hovering or focusing a row lights
// its node up on the canvas (`onHover`), and the item of the selected node
// is `aria-selected`, takes the tree's selected look and is scrolled into
// view INSIDE the column (`scroller`, the column's `scrollTop`) -- never
// with `scrollIntoView`, which would scroll the page as well.
//
// THE FOLDS. A page's branch folds as it does in Pages and with the same
// open set (`tree/open_set.js`, the cookie both trees read): the first
// drawing takes it from the tree's `data-tree-open`, which the server parsed
// from the cookie for the pages this viewer reads, and every later one from
// the cookie: the first drawing takes the attribute off the graph's element
// (and `destroy` does, if none was drawn), so a page Turbo restores from its
// snapshot draws the folds as the cookie has them now, not as they were. A
// person's fold or open is written through `setOpen`, relative
// to the node's default (Home, `data-tree-root`, and the selected node's
// path, `data-tree-on-path`, are open by default). Selecting a node opens
// the path to it (`openPathIn`, which forgets that path's folds). A group
// heading's fold and a hub's (the row a pill hangs off) are a view state,
// open at first and never stored (`data-tree-view-fold`): kept while the
// list is on the screen, through every redraw.
//
// FOUR GROUPS: "Pages · N" first, in TREE order (not by connections: a
// tree is read by its order), then "Posts · N" and "Tags · N",
// best-connected first as on the canvas, then "Post types · N": a row for
// each post-type node and for "All posts", so each has a keyboard path to
// its card. Each group is a branch of the tree under its heading. A POST TYPE'S ROW has
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
// have rows here, empty otherwise so the marks line up; so does a tag's and
// a post type's, holding the disclosure where a pill hangs off it, so a
// group's marks line up; a post's row is flat (no disclosure box). The
// disclosure is a part hidden from a screen reader and never a button: the
// treeitem is the one control, and says whether it is open
// (`aria-expanded`). The row of the selected node takes the tree's selected
// look.
//
// A GROUP'S HEADING is an item of the tree's too, at the first level, 28px
// like any and never selected: Enter, Space and a click fold or open it. Its
// row holds the disclosure part, its kind's icon chip (`Admin::Ui::
// IconChipComponent`, the sidebar's: a page the structure's, a post, a tag
// and a post type the lists') in the mark box, then the group's words in
// the label style with the figure after the middle dot in the count style.
// `--cs-sp-3` stands above every heading but the first. A heading adds no step: the
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
// A PILL'S ROWS (`showRows` with `back`) are a tree of their own, of one level,
// under a heading that names them ("More from Blog · 92") with "Back to the
// list" beside it, a button, before the rows in the document; ESCAPE pressed anywhere in the rows is
// the same way back (`back.onBack`), and so it is on the error line of a
// pill's read that failed, which offers the button beside "Try again". The
// rows of "Not listed on any page" have neither: their checkbox is the way
// back, and Escape there is nobody's.
//
// THE PAGES ARE A TREE FOR A SCREEN READER TOO, not an indent alone: a
// page's item stands in a group INSIDE its parent's item (by the data's
// `parent`), so the nesting is the document's and is announced as a level
// (`aria-level`), and the step is the children list's (`CLASSES.children`). A page whose
// parent has no row here (not readable, or not in this view) stands at the
// top level of the group, with no step and no guide: nothing it could hang
// from is drawn. Under its title it says where it stands, its ancestors'
// titles from Home (the data's `ancestors`, which name only pages the viewer
// reads), and its tooltip and its name say the same.
//
// EVERY FIGURE in the list, a row's and a heading's, is written by `number`,
// as the messages' language groups it ("Pages · 1,204").
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
// while it is on, the list shows the rows the app hands `showRows`, a tree
// of one level, IN PLACE OF the groups, and the canvas is left as it is. The same form serves the
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
// was for: the line in the danger ink and a small "Try again" button under
// it (`fail`, the tertiary button's classes the app hands in), in a
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
// replace the rows' own region and never the checkbox, the tab stop stays
// on the item of the same node, else on the first, and when the focus was
// in that region it is put there, else on the checkbox. A redraw is told
// to the tree's other scripts as `tree:changed` on the tree. A find that
// hides the stop's item (`tree-find:filtered`) moves the stop off it, to the
// nearest ancestor that still shows, else to the first item that shows.
// There is no type-ahead: the find is the way to a row by its name.
//
// THE WHOLE SITE'S RESULTS (`showResults({ query, rows, failed, back })`)
// stand in the region in place of the checkbox and the rows, which are
// hidden and kept as they are (a redraw while the results show goes on
// under them): "Back to the list" first, a tertiary small button that
// takes the focus, then the heading that names the query, then the groups
// `search_results.js` draws, or one line that nothing matched, or the failure
// in the danger ink (`role="alert"`). Back, and Escape anywhere in the
// results, take them away (`closeResults`) and call `back.onBack`.
//
// Text goes in with `textContent`; no path is written here but the one the
// app hands in (`link`). `createList(container, { text, number, dotClasses,
// typeLabels, treeClasses, retryClass, parts, unlisted, treeData, onSelect,
// onHover, onAdd, onMore, onUnlisted })` answers `{ render(nodes),
// showRows({ heading, rows, inView, link, back }), fail(line, { label,
// onRetry, focus, back }), showResults(…), closeResults(), clear(),
// setUnlisted(on), setBusy(on), mark(id), row(id), destroy() }`: `render`
// replaces the rows with the four groups (the app calls it once per load
// and once per filter change), `clear`
// empties the rows while another graph is loaded, `mark` moves the mark to
// the item of `id` (null for none), and `row` answers the treeitem of `id`.
// `treeData` is the graph's element, whose `data-tree-open-path`,
// `data-tree-locale` and `data-tree-open` the tree carries (the last a seed
// the list uses up). `scroller` is the element that scrolls the rows into
// view, the container's by default. The list puts its parts before what the
// container already holds (the last line, the app's) and takes back only its
// own. `back` is
// `{ label, onBack }`. `onSelect(id)`, `onMore(id)` and `onHover(id | null)`
// get a node's id as the data has it; `number` groups a figure as the
// messages' language does. A pill's node carries `of`, the name of what it
// hangs off. The listeners are on the rows' region, one of each, however
// many rows there are. A row's node id is its treeitem's `data-node-id`; its
// row's `data-tree-id` is the open set's bare page id for a page and the
// node's id for any other, so the two never meet.
import { dotClass, TAG_MARK } from "mind_graph/card"
import { recordId } from "mind_graph/ids"
import { renderResults } from "mind_graph/search_results"
import { markCanvas, paintMarks } from "mind_graph/swatches"
import { expanderOf, idOf, openByRule, openPathIn, readOpenSet, setFolded, setOpen } from "tree/open_set"

const byDegree = (a, b) => b.degree - a.degree || String(a.title).localeCompare(String(b.title))
const byTree = (a, b) => a.order - b.order
// The order the data has them: colour-slot order, then the retired types,
// then "All posts" last.
const asGiven = () => 0
const LIST = "m-0 list-none p-0"
// The tree's id, which a find names (`aria-controls`). Whichever tree the
// list shows carries it (the four groups' or the rows of `showRows`): the
// region holds one tree at a time, so the find narrows the one in view.
const TREE_ID = "mind-graph-tree"
const ITEM = '[role="treeitem"]'
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
// A heading's key is therefore never a plural: a plural is chosen by the
// count, and the key is asked with this character in the count's place.
const FIGURE = "\u0000"
// Between two ancestors' titles in the line under a page whose parent is
// not drawn: the breadcrumb's mark, no word.
const PATH_JOIN = " › "
// The open set's id of a node's row: a page's bare id, any other node's own.
const treeIdOf = (node) => (node.kind === "page" ? recordId(node.id) : node.id)

export function createList(container, { text, number = String, dotClasses, typeLabels = {}, treeClasses: classes, retryClass = "", parts, unlisted: filterable = true, treeData = null, scroller = container, onSelect, onHover, onAdd, onMore = () => {}, onUnlisted }) {
  let rows = new Map()
  let absent = new Map()
  let marked = null
  let headings = 0
  // The way back from what is shown, while there is one (a pill's rows, or
  // the error line of a pill's read): what Escape in the rows' region does.
  let goBack = null
  // The group headings and hubs the person folded: a view state, never
  // stored, kept through every redraw while the list is on the screen.
  const viewFolded = new Set()

  const element = (tag, className, content) => {
    const created = document.createElement(tag)
    if (className) created.className = className
    if (content != null) created.textContent = content
    return created
  }

  // The filter and the rows' own region: `render` and `showRows` replace the
  // region and never the checkbox, so the focus stays on it while it is used.
  const filter = element("label", "flex cursor-pointer items-center gap-2 px-1 py-2 text-sm text-ink")
  const unlisted = document.createElement("input")
  unlisted.type = "checkbox"
  unlisted.className = "cs-checkbox"
  unlisted.dataset.mindGraphUnlisted = ""
  filter.append(unlisted, element("span", "", text.t("mind_graph.script.list.unlisted")))
  // The rows' region. It has no gutter of its own: a row stands where a
  // Pages row stands, inside the column's padding, and the region's other
  // lines (the filter, a heading, the last line) stand `px-1` in, where a
  // row's disclosure column starts. The trees in it are the tree's block
  // (`CLASSES.tree`).
  const body = element("div", "pt-2")
  body.dataset.mindGraphRows = ""
  container.prepend(...(filterable ? [ filter ] : []), body)
  // The whole site's results, in the place of the filter and the rows while
  // they show.
  const results = element("div", "pt-2")
  results.dataset.mindGraphResults = ""
  results.hidden = true
  body.after(results)
  const changed = () => onUnlisted(unlisted.checked)
  unlisted.addEventListener("change", changed)

  // A tree: the tree's block, a list with no markers. The four groups' tree
  // carries what the open set reads from it, copied from the graph.
  const treeOf = ({ main = false } = {}) => {
    const tree = element("ul", `${classes.tree} ${LIST}`)
    tree.setAttribute("role", "tree")
    tree.id = TREE_ID
    const given = treeData?.dataset ?? {}
    if (given.treeLocale != null) tree.dataset.treeLocale = given.treeLocale
    if (!main) return tree
    const label = container.getAttribute("aria-label")
    if (label) tree.setAttribute("aria-label", label)
    for (const name of [ "treeOpenPath", "treeOpen" ]) {
      if (given[name] != null) tree.dataset[name] = given[name]
    }
    return tree
  }
  // A group inside an item: its children, a step in (`CLASSES.children`)
  // under a row, none under a group's heading.
  const groupOf = (className) => {
    const group = element("ul", className)
    group.setAttribute("role", "group")
    group.dataset.treeChildren = ""
    return group
  }
  // An item of the tree at `level`, out of the Tab order until it is the
  // stop. It is its own focus (`data-tree-focus`), which a find moves to.
  const itemAt = (level) => {
    const item = element("li")
    item.setAttribute("role", "treeitem")
    item.setAttribute("aria-level", String(level))
    item.tabIndex = -1
    item.dataset.treeNode = ""
    item.dataset.treeFocus = ""
    return item
  }
  // The item's own row: its first child, before its group.
  const rowIn = (item) => item.firstElementChild

  // "Back to the list": a button that reads as a link, as the legend's
  // "Status" does. It changes what the list shows and leads nowhere.
  const backButton = ({ label, onBack }) => {
    const button = element("button", `shrink-0 ${LINK}`, label)
    button.type = "button"
    button.dataset.mindGraphBack = ""
    button.addEventListener("click", onBack)
    return button
  }
  // The rows a filter or a pill brings, a tree named by a heading of their
  // own. With `back`, the way back stands beside the heading, before the
  // rows.
  const section = (title, tree, { back = null } = {}) => {
    const wrapper = element("section")
    const heading = element("h2", "m-0 flex min-w-0 items-center gap-2 px-1 pb-1 pt-1 text-label text-meta", title)
    heading.id = `mind-graph-list-${(headings += 1)}`
    tree.setAttribute("aria-labelledby", heading.id)
    if (!back) {
      wrapper.append(heading, tree)
      return wrapper
    }
    const head = element("div", "flex items-baseline justify-between gap-2 pr-1")
    head.append(heading, backButton(back))
    wrapper.append(head, tree)
    return wrapper
  }
  // The mark box, holding `mark` (a pill's is empty, so its words stand
  // under its hub's title).
  const markBox = (mark = null) => {
    const box = element("span", classes.mark)
    if (mark) box.append(mark)
    return box
  }
  // A group of the four: its heading is an item at the first level, its
  // row the tree's row, and its nodes the group under it, starting at the
  // heading's left edge. `key` is the group's words with `%{count}` where
  // the figure stands.
  const group = (name, key, count, items, icon) => {
    const item = itemAt(1)
    item.className = "not-first:mt-(--cs-sp-3)"
    item.dataset.treeGroup = name
    item.setAttribute("aria-label", text.t(key, { count: number(count) }))
    const heading = element("div", classes.row)
    const [ before, ...rest ] = text.t(key, { count: FIGURE }).split(FIGURE)
    const words = element("span", "text-label text-meta", before)
    rest.forEach((after) => words.append(element("span", "text-count", number(count)), after))
    const title = element("span", classes.title)
    title.append(words)
    heading.append(parts.part("tree-disclosure"), markBox(parts.part(icon)), title)
    const children = groupOf(LIST)
    children.append(...items)
    item.append(heading, children)
    return viewFold(item, `group:${name}`)
  }
  // A fold that is a view state: drawn as the person left it.
  const viewFold = (item, key) => {
    item.dataset.viewKey = key
    item.dataset.treeViewFold = viewFolded.has(key) ? "folded" : "open"
    return item
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
  // The tree's title box, the whole title in its tooltip as in Pages
  // (`tooltip`, where the row says more than its title).
  const titleBox = (words, tooltip = words) => {
    const title = element("span", classes.title, words)
    title.title = tooltip
    return title
  }
  // A page whose parent has no row here stands at the top with no step, so
  // it says where it is: its ancestors' titles from Home (the data's
  // `ancestors`), joined, on a line under its title cut at the end; the
  // tooltip and the name carry the whole path.
  // A blank title is left out, so the line never holds a bare mark.
  const pathOf = (node) => {
    const titles = (node.ancestors ?? []).filter((title) => String(title ?? "").trim())
    return titles.length ? titles.join(PATH_JOIN) : null
  }
  const placed = (title, path) => (path ? text.t("mind_graph.script.list.under", { title, path }) : title)
  // A row's title, and on a line of their own under it its chips when it
  // has any: the title keeps the row's whole width and is cut only by the
  // row's edge, so in the list's narrow column a row with two chips, or a
  // page deep in the tree, still says which record it is. The chips wrap
  // rather than run past the row's figure.
  const titled = (node, path = null) => {
    const chips = stateChips(node)
    const title = titleBox(node.title, placed(node.title, path))
    if (!chips.length && !path) return title
    const stack = element("span", "flex min-w-0 flex-1 flex-col gap-0.5")
    const where = path ? [ element("span", "min-w-0 truncate text-small text-meta", text.t("mind_graph.script.list.ancestors", { path })) ] : []
    stack.append(title, ...where, ...chips)
    return stack
  }
  // A node's item and its row, with the row's disclosure box. `opens`: a
  // row whose children have rows here, which draws the disclosure part;
  // `flat`: a row with no disclosure box. Any other row keeps the box
  // empty, so its mark lines up with its siblings'. The row carries what a
  // find and the open set read: its id, its whole title and a page's
  // address.
  const nodeItem = (node, level, { opens = false, flat = false } = {}) => {
    const item = itemAt(level)
    item.dataset.nodeId = node.id
    const row = element("div", flat ? `${classes.row} ${classes.row_flat}` : classes.row)
    row.dataset.treeRow = ""
    row.dataset.treeId = treeIdOf(node)
    row.dataset.treeTitle = node.title ?? ""
    if (node.kind === "page" && node.path) row.dataset.treePath = node.path
    if (opens) row.append(parts.part("tree-disclosure"))
    else if (!flat) row.append(element("span", classes.disclosure))
    item.append(row)
    rows.set(node.id, item)
    return item
  }
  // The group a page's or a hub's children stand in, inside its item: the
  // tree's step.
  const childrenOf = (item) => item.querySelector(":scope > [data-tree-children]") ?? item.appendChild(groupOf(`${classes.children} ${LIST}`))
  const levelOf = (item) => Number(item.getAttribute("aria-level"))
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
  // hangs off it). `path`: a page whose parent has no row here, and the
  // titles it stands under. A post's row is flat; a tag's and a post type's
  // keep the disclosure box, so their marks line up with a hub's that a
  // pill hangs off.
  const row = (node, { level, notInView = false, addable = true, opens = false, path = null } = {}) => {
    const item = nodeItem(node, level, { opens, flat: node.kind === "post" && !opens })
    item.setAttribute("aria-label", notInView ? (addable ? addName(node) : absentName(node)) : text.t(NAMES[node.kind], { title: placed(stated(node), path), count: figure(node), figure: number(figure(node)) }))
    if (node.kind === "page" && node.home) item.dataset.treeRoot = ""
    // At the row's end: the figure, or the words of a row that is not in view.
    const notShown = () => element("span", "text-label text-meta", text.t("mind_graph.script.list.not_in_view"))
    const trailing = element("span", classes.trailing)
    trailing.append(notInView ? notShown() : element("span", classes.count, number(figure(node))))
    rowIn(item).append(markBox(markFor(node)), titled(node, path), trailing)
    if (notInView) {
      item.dataset.notInView = ""
      // Without a graph the row adds nothing and says so: it is there to be
      // read, and is drawn again as one that adds once the graph has come.
      if (addable) absent.set(node.id, node)
      else item.setAttribute("aria-disabled", "true")
    }
    return item
  }
  // A pill's row: flat, the pill's own words in the accent, and its whole
  // name. No mark: the row it hangs off is its parent.
  const pillRow = (pill, level) => {
    const item = nodeItem(pill, level, { flat: true })
    item.dataset.more = ""
    // The name begins with the words the row shows, so someone who says
    // what they see names it (WCAG 2.5.3, label in name).
    item.setAttribute("aria-label", text.t("mind_graph.script.list.more_row", { count: pill.count, figure: number(pill.count), target: pill.of ?? "", words: pill.title }))
    const title = element("span", classes.title)
    title.append(element("span", "text-accent", pill.title))
    rowIn(item).append(markBox(), title)
    return item
  }
  // The pages as the tree they are: a page's item holds the group of its
  // children. The pages come in tree order, so a parent is met before its
  // children; one whose parent has no row here stands at the top level of
  // the group. `opens`: the ids whose rows draw the disclosure.
  const pageItems = (pages, opens) => {
    const top = []
    const items = new Map()
    for (const page of pages) {
      const parent = items.get(page.parent)
      const item = row(page, { level: parent ? levelOf(parent) + 1 : 2, opens: opens.has(page.id), path: parent ? null : pathOf(page) })
      if (parent) childrenOf(parent).append(item)
      else top.push(item)
      items.set(page.id, item)
    }
    return top
  }
  const useSeed = () => treeData?.removeAttribute("data-tree-open")
  const forget = () => {
    rows = new Map()
    absent = new Map()
    marked = null
    goBack = null
  }

  // THE TREE'S WALK. An item shows when nothing between it and its tree is
  // `hidden` (a folded branch, or a find's narrowing).
  const treeAround = (item) => item.closest('[role="tree"]')
  const shows = (item) => {
    const tree = treeAround(item)
    for (let at = item; at && at !== tree; at = at.parentElement) if (at.hidden) return false
    return true
  }
  const shown = (tree) => Array.from(tree.querySelectorAll(ITEM)).filter(shows)
  const parentItem = (item) => item.parentElement?.closest(ITEM) ?? null
  // The nearest item that shows: `item`, or the parent that folded over it.
  const showing = (item) => {
    let at = item
    while (at && !shows(at)) at = parentItem(at)
    return at
  }
  // The tab stop: `item` alone in its tree holds `tabindex="0"`.
  const rove = (item) => {
    treeAround(item)?.querySelectorAll(`${ITEM}[tabindex="0"]`).forEach((other) => { if (other !== item) other.tabIndex = -1 })
    item.tabIndex = 0
  }
  const keyOf = (item) => item?.dataset.nodeId ?? item?.dataset.viewKey ?? null
  const byKey = (key) => (key == null ? null : rows.get(key) ?? body.querySelector(`[data-view-key="${CSS.escape(key)}"]`))
  const told = (tree) => tree.dispatchEvent(new CustomEvent("tree:changed", { bubbles: true }))

  // A fold or an open of `item`'s branch by the person: drawn, and kept,
  // a page's in the open set and a heading's or a hub's in this list alone.
  // The stop and the focus never stay inside a branch that folds.
  const store = (item, open) => {
    if (item.dataset.viewKey) {
      item.dataset.treeViewFold = open ? "open" : "folded"
      if (open) viewFolded.delete(item.dataset.viewKey)
      else viewFolded.add(item.dataset.viewKey)
      return
    }
    const id = idOf(item)
    if (id) setOpen(treeAround(item), id, open, { openByDefault: item.hasAttribute("data-tree-root") || item.hasAttribute("data-tree-on-path") })
  }
  const fold = (item, open) => {
    if (!expanderOf(item) || !item.hasAttribute("aria-expanded")) return
    setFolded(item, !open)
    store(item, open)
    if (!open) {
      const inside = item.querySelector(`[data-tree-children] ${ITEM}[tabindex="0"]`)
      if (inside) rove(item)
      if (item.querySelector("[data-tree-children]")?.contains(document.activeElement)) item.focus()
    }
    told(treeAround(item))
  }
  // `item` and every branch under it, opened.
  const openBranch = (item) => {
    [ item, ...item.querySelectorAll(ITEM) ].filter((each) => each.hasAttribute("aria-expanded")).forEach((each) => {
      setFolded(each, false)
      store(each, true)
    })
    told(treeAround(item))
  }
  // Draws every branch of `tree` by the rule: the open set as it stands,
  // a view fold as the person left it.
  const drawFolds = (tree, set) => {
    tree.querySelectorAll(`${ITEM}[data-tree-node]`).forEach((item) => {
      if (item.querySelector(":scope > [data-tree-children]")) setFolded(item, !openByRule(item, set))
    })
  }

  // Replaces the rows. The stop stays on the item of the same node, else
  // goes to the first; when the focus WAS in the rows it is put there, else
  // on the checkbox. A list drawn while the person is elsewhere takes
  // nothing from them. The marks are drawn once the rows are in the page.
  const put = (...pieces) => {
    const focused = body.contains(document.activeElement)
    const key = keyOf((focused ? document.activeElement : body.querySelector(`${ITEM}[tabindex="0"]`))?.closest?.(ITEM))
    body.replaceChildren(...pieces)
    paintMarks(body)
    const kept = byKey(key)
    const next = kept ? showing(kept) : null
    body.querySelectorAll('[role="tree"]').forEach((tree) => {
      const stop = next && tree.contains(next) ? next : tree.querySelector(ITEM)
      if (stop) rove(stop)
      told(tree)
    })
    if (!focused) return
    const target = next ?? body.querySelector(`${ITEM}[tabindex="0"]`) ?? (filterable ? unlisted : null)
    target?.focus()
  }

  // The item an event is about: the treeitem itself (a find's `.click()`),
  // or the item whose own row holds the target; never a parent for its
  // children's group.
  const itemOf = (event) => {
    const item = event.target.closest?.(ITEM)
    if (!item || !body.contains(item)) return null
    return event.target === item || rowIn(item).contains(event.target) ? item : null
  }
  // What a press on an item does: a heading folds or opens, a pill asks for
  // its rows, a row that is not in view adds its post, any other selects.
  const activate = (item) => {
    if (item.dataset.viewKey?.startsWith("group:")) return fold(item, item.getAttribute("aria-expanded") === "false")
    if (item.getAttribute("aria-disabled") === "true") return
    const id = item.dataset.nodeId
    if (item.dataset.more != null) onMore(id)
    else if (absent.has(id)) onAdd(absent.get(id))
    else onSelect(id)
  }
  const click = (event) => {
    const item = itemOf(event)
    if (!item) return
    const disclosure = rowIn(item).querySelector(`:scope > .${classes.disclosure}`)
    if (disclosure?.contains(event.target) && item.hasAttribute("aria-expanded")) fold(item, item.getAttribute("aria-expanded") === "false")
    else activate(item)
  }
  // The tree's keys, on an item that has the focus. Escape in the rows'
  // region goes back where there is a way back, and is nobody's otherwise
  // (it is not taken, so whatever else listens hears it).
  const keydown = (event) => {
    // A key a find took first (Up on its first match goes back to the
    // field: `admin--tree--find#treeKey`, heard in the capture phase).
    if (event.defaultPrevented || event.ctrlKey || event.metaKey || event.altKey) return
    if (event.key === "Escape") {
      if (!goBack || event.shiftKey) return
      event.preventDefault()
      event.stopPropagation()
      goBack()
      return
    }
    const item = event.target.matches?.(ITEM) ? event.target : null
    if (!item || !body.contains(item) || (event.shiftKey && event.key !== "*")) return
    const items = shown(treeAround(item))
    const at = items.indexOf(item)
    const expanded = item.getAttribute("aria-expanded")
    const go = (to) => { if (to) { rove(to); to.focus() } }
    switch (event.key) {
      case "ArrowDown": go(items[at + 1]); break
      case "ArrowUp": go(items[at - 1]); break
      case "Home": go(items[0]); break
      case "End": go(items[items.length - 1]); break
      case "ArrowRight":
        if (expanded === "false") fold(item, true)
        else if (expanded === "true") go(shown(treeAround(item)).find((each) => parentItem(each) === item))
        break
      case "ArrowLeft":
        if (expanded === "true") fold(item, false)
        else go(parentItem(item))
        break
      case "*": openBranch(item); break
      case "Enter": case " ": activate(item); break
      default: return
    }
    event.preventDefault()
  }
  const over = (event) => {
    const item = itemOf(event)
    if (item?.dataset.nodeId && !absent.has(item.dataset.nodeId)) onHover(item.dataset.nodeId)
  }
  const out = (event) => {
    if (itemOf(event)?.dataset.nodeId) onHover(null)
  }
  // The stop follows the focus, however it came (a click, a find's Down,
  // the card giving it back).
  const focusin = (event) => {
    if (event.target.matches?.(ITEM) && body.contains(event.target)) rove(event.target)
    over(event)
  }
  // A find narrowed the tree, or gave it back: the stop moves off an item
  // the find hid, to its nearest ancestor that still shows, else to the
  // first item that shows, so Tab still enters the tree.
  const restop = (event) => {
    const tree = event.target.closest?.('[role="tree"]')
    if (!tree || !body.contains(tree)) return
    const stop = tree.querySelector(`${ITEM}[tabindex="0"]`)
    const next = (stop && showing(stop)) || shown(tree)[0]
    if (next && next !== stop) rove(next)
  }
  const listeners = { click, keydown, pointerover: over, pointerout: out, focusin, focusout: out, "tree-find:filtered": restop, "tree-find:cleared": restop }
  Object.entries(listeners).forEach(([ name, handler ]) => body.addEventListener(name, handler))

  function mark(id) {
    marked?.removeAttribute("aria-selected")
    if (marked) rowIn(marked).classList.remove(classes.row_selected)
    marked = id == null ? null : rows.get(id) || null
    body.querySelectorAll('[role="tree"]').forEach((tree) => { if (!marked || !tree.contains(marked)) openPathIn(tree, null) })
    if (!marked) return

    // The path to it opens, and a heading or a hub on it forgets its fold
    // as a page on it does (`openPathIn`).
    const tree = treeAround(marked)
    openPathIn(tree, rowIn(marked).dataset.treeId)
    for (let above = parentItem(marked); above; above = parentItem(above)) {
      if (above.dataset.viewKey) store(above, true)
    }
    marked.setAttribute("aria-selected", "true")
    rowIn(marked).classList.add(classes.row_selected)
    // The stop goes to it, unless the person is on another item of the tree.
    if (!tree.contains(document.activeElement)) rove(marked)
    // Its row into view within the column only, and only as far as needed;
    // not while the whole site's results stand in the rows' place, where
    // the row has no box to measure.
    if (body.hidden) return
    const box = scroller.getBoundingClientRect()
    const rowBox = rowIn(marked).getBoundingClientRect()
    if (rowBox.top < box.top) scroller.scrollTop -= box.top - rowBox.top
    else if (rowBox.bottom > box.bottom) scroller.scrollTop += rowBox.bottom - box.bottom
  }

  const line = (content) => element("p", "m-0 px-1 py-1 text-small text-dim", content)

  // The whole site's results go, and the filter and the rows show again.
  let resultsBack = null
  const closeResults = () => {
    if (results.hidden) return
    results.hidden = true
    results.replaceChildren()
    resultsBack = null
    filter.hidden = false
    body.hidden = false
  }
  const leaveResults = () => {
    const back = resultsBack
    closeResults()
    back?.()
  }
  const resultsKey = (event) => {
    if (event.key !== "Escape" || event.defaultPrevented || event.shiftKey || event.ctrlKey || event.metaKey || event.altKey) return
    event.preventDefault()
    event.stopPropagation()
    leaveResults()
  }
  results.addEventListener("keydown", resultsKey)

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
      const tree = treeOf({ main: true })
      const groupItems = new Map()
      const drawn = groups.map(([ name, found, icon ]) => {
        const items = name === "pages" ? pageItems(found, opens) : found.map((node) => row(node, { level: 2, opens: opens.has(node.id) }))
        const item = group(name, `mind_graph.script.list.${name}`, found.length, items, icon)
        groupItems.set(name, item)
        return item
      })
      // Each pill the child of the row it hangs off; one with no such row
      // at the end of the posts, or after the groups when no post is drawn.
      const loose = []
      for (const pill of pills) {
        const hub = rows.get(pill.target)
        if (hub) {
          childrenOf(viewFold(hub, hub.dataset.nodeId)).append(pillRow(pill, levelOf(hub) + 1))
        } else {
          loose.push(pill)
        }
      }
      const posts = groupItems.get("posts")
      if (posts) childrenOf(posts).append(...loose.map((pill) => pillRow(pill, 2)))
      else drawn.push(...loose.map((pill) => pillRow(pill, 1)))
      tree.append(...drawn)
      // The open set the server handed the page (`data-tree-open`) is a seed,
      // used up by the first drawing: every later one, and a page Turbo
      // restores from its snapshot, reads the cookie, which this list and
      // the Pages tree write.
      drawFolds(tree, readOpenSet(tree.dataset.treeOpen ?? null))
      useSeed()
      put(tree)
    },
    // `addable: false`: there is no graph to add a post to, and a row that
    // is not in view only says so.
    // A filter's rows in place of the groups, a tree of one level. `inView(id)`: whether the
    // canvas draws that post now. `back`: the rows are a pill's, and this
    // is the way back to the groups.
    showRows({ heading, rows: given, inView, link = null, back = null, addable = true }) {
      forget()
      goBack = back?.onBack ?? null
      const tree = treeOf()
      tree.append(...given.map((node) => row({ ...node, kind: "post" }, { level: 1, notInView: !inView(node.id), addable })))
      const shownRows = [ section(heading, tree, { back }) ]
      // "Not listed on any page" with nothing to show says so under its heading.
      if (!given.length && !back) shownRows.push(line(text.t("mind_graph.script.list.unlisted_none")))
      if (link) {
        const anchor = element("a", "mx-1 mt-2 inline-block text-sm text-accent underline", link.label)
        anchor.href = link.href
        anchor.dataset.mindGraphPostsLink = ""
        shownRows.push(anchor)
      }
      put(...shownRows)
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
      said.append(element("p", "m-0 text-small text-danger-ink", content), controls)
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
    // The whole site's results for `query`: `rows` the search's answer, or
    // `failed`. Back takes the focus.
    showResults({ query, rows: found = [], failed = false, back }) {
      resultsBack = back?.onBack ?? null
      const backButton = element("button", retryClass, back?.label ?? "")
      backButton.type = "button"
      backButton.dataset.mindGraphBack = ""
      backButton.addEventListener("click", leaveResults)
      const heading = element("h2", "m-0 mt-2 px-1 text-sm font-semibold text-ink", text.t("mind_graph.script.list.search_site_heading", { query }))
      const backLine = element("div", "flex px-1")
      backLine.append(backButton)
      const pieces = [ backLine, heading ]
      if (failed) {
        const said = element("p", "m-0 mt-2 px-1 text-small text-danger-ink", text.t("mind_graph.script.search.failed"))
        said.setAttribute("role", "alert")
        pieces.push(said)
      } else if (!found.length) {
        pieces.push(line(text.t("mind_graph.script.search.none")))
      }
      results.replaceChildren(...pieces)
      if (!failed && found.length) {
        const groups = element("div", `mt-2 ${classes.tree}`)
        renderResults(groups, found, { text, dotClasses, classes, parts })
        results.append(groups)
      }
      filter.hidden = true
      body.hidden = true
      results.hidden = false
      backButton.focus()
    },
    closeResults,
    mark,
    row: (id) => rows.get(id) || null,
    destroy() {
      useSeed()
      unlisted.removeEventListener("change", changed)
      results.removeEventListener("keydown", resultsKey)
      Object.entries(listeners).forEach(([ name, handler ]) => body.removeEventListener(name, handler))
      filter.remove()
      body.remove()
      results.remove()
    }
  }
}
