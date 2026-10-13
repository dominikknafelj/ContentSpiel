// Every node the graph draws, as a row beside the canvas (mind graph canvas
// spec §5.7; pages in the mind graph, spec §7): the path for a keyboard and a
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
// FOUR GROUPS: "Pages · N" first, in TREE order with an indent per level
// (not by connections: a tree is read by its order), then "Posts · N" and
// "Tags · N", best-connected first as on the canvas, then "Post types · N":
// a row for each post-type node and for "All posts", so each has a keyboard
// path to its card (the owner's decision of 2026-10-12). Each group is a
// list named by its heading. A ROW OF "POST TYPES" is the design answer's
// (H2): its mark a small copy of the hub, its number the POSTS of that type
// the viewer can read (a tag's row has its connections there), in the order
// the data has them -- colour-slot order, then retired types, then "All
// posts" last.
//
// "+N MORE" HAS A ROW TOO (the ruling on the review of the pages plan's Task
// 7: a pill pressed on the canvas opens the list, and nothing on a canvas
// can be pressed by a keyboard). Each pill in view has a row UNDER THE ROW
// OF WHAT IT HANGS OFF -- the post type's, "All posts"' or the tag's --
// indented one step, in the pill's own words ("+92 more"), and named whole
// for a screen reader, beginning with those words ("+92 more: 92 more posts
// Blog lists, not in view. Activate to show them."). It is counted in no heading: it is no post type and no tag.
// A pill whose hub has no row (its kind is switched off) stands at the end
// of the posts, and with no post drawn either, after the groups: a pill in
// view is never without a row. Activating it asks the app for the pill's
// rows (`onMore(id)`), as a press on the pill does, and the focus goes to
// the first of them (the rule under "THE FOCUS IS NOT LOST").
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
// `parent`), so the nesting is the document's and is announced as a level.
// A page whose parent is not among the rows (not readable, or not in this
// view) stands at the top level, indented by its depth as the eye sees it.
//
// A ROW'S MARK. A page's and a post type's are small canvases drawn by the
// renderer the graph is drawn by (`swatches.js`: `markCanvas`, painted once
// the rows are in the document), so a hub's row cannot show a look the
// canvas does not have. A post's is its type's dot and a tag's the square,
// CS Studio's own (`card.js`). NOTHING HERE IS LAZY, AND THE BOUND IS THE
// PAGES AND THE HUBS: one canvas and one drawing for each, made again with
// the rows on every redraw (a legend toggle, a post added, a theme change),
// never for a post or a tag, of which there can be two thousand. Measured
// on 2026-10-13 at 204 pages and 4 hubs: 208 canvases painted in 1.4 to
// 1.8 ms, inside a redraw of the whole list (2,202 rows) of about 30 ms.
// A site of several thousand pages is where this would be looked at again.
//
// ABOVE THE GROUPS, "Not listed on any page" (pages spec §7), a checkbox:
// while it is on, the list shows the rows the app hands `showRows` IN PLACE
// OF the groups, and the canvas is left as it is. The same form serves the
// posts behind a page's "+N more", with "Open in Posts →" under them. The
// checkbox is there only when the app says so (`unlisted`): for a viewer who
// reads no page every post is one no page lists, and the filter says nothing.
//
// A ROW THAT IS NOT IN VIEW. A row of `showRows` whose post the canvas does
// not draw says "not in view" where its count would stand, and pressing it
// asks the app to ADD the post (`onAdd(row)`: the row is the post's node as
// the data has it, so no request is made). Its name is the design answer's
// (G5): "Small sites, long lives, blog post, not in view. Activate to add
// it to the graph." -- with the post TYPE's name, as the messages' language
// lowers it; a post of a RETIRED type says "talk, retired type" (H7). One
// that is drawn selects, like any row.
//
// A READ THAT FAILED (G5) is said IN THE LIST, not in a toast: the line and
// a small "Try again" button under it (`fail`), in a `role="alert"` so it
// is announced. The checkbox above stays, so the filter can be let go. When
// the focus was in the rows it is put on "Try again": the row or the button
// that was pressed is gone, and the keyboard is not left on nothing.
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
// typeLabels, retryClass, unlisted, onSelect, onHover, onAdd, onMore,
// onUnlisted })` answers `{ render(nodes), showRows({ heading, rows, inView,
// link, back }), fail(line, { label, onRetry, focus, back }), clear(),
// setUnlisted(on), setBusy(on), mark(id), row(id), destroy() }`: `render` replaces the
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
// The order the data has them (design answer H2): colour-slot order, then
// the retired types, then "All posts" last.
const asGiven = () => 0
const ROW = "flex w-full cursor-pointer items-center gap-2 px-3 py-1 text-left text-sm text-ink hover:bg-sunken focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-accent aria-[current]:bg-accent-tint aria-[current]:font-semibold"
const LIST = "m-0 list-none p-0"
const NAMES = { page: "mind_graph.script.list.select_page", post: "mind_graph.script.list.select_post", tag: "mind_graph.script.list.select_tag", type: "mind_graph.script.list.select_type" }
// A page's indent per level of the tree, in pixels, on top of the row's own
// (a READING: the design answer says "with indents" and no figure).
const INDENT = 12
const ROW_PADDING = 12
// A pill's row stands one step in from the row it hangs off, beyond that
// row's mark (a READING: nobody drew it).
const PILL_INDENT = 16
const LINK = "cursor-pointer rounded-cs text-sm text-accent underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"

export function createList(container, { text, number = String, dotClasses, typeLabels = {}, retryClass = "", unlisted: filterable = true, onSelect, onHover, onAdd, onMore = () => {}, onUnlisted }) {
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
  const body = element("div")
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
  // A group: its heading, and its rows in a list the heading names. With
  // `back`, the way back stands beside the heading, before the rows.
  const section = (title, list, { back = null } = {}) => {
    const wrapper = document.createElement("section")
    const heading = element("h2", "m-0 min-w-0 px-3 pb-1 pt-3 font-cs-mono text-label uppercase tracking-mono text-meta", title)
    heading.id = `mind-graph-list-${(headings += 1)}`
    list.setAttribute("aria-labelledby", heading.id)
    if (back) {
      const head = element("div", "flex items-baseline justify-between gap-2 pr-3")
      head.append(heading, backButton(back))
      wrapper.append(head, list)
    } else {
      wrapper.append(heading, list)
    }
    return wrapper
  }
  // A post's type as a row that is not in view names it (design answers G5,
  // H7): the type's label in lower case, as the messages' language lowers
  // it ("blog post"); a RETIRED type has no label, and is its stored name in
  // lower case with its own sentence ("talk, retired type"). `hasOwn`,
  // because a stored name is data.
  const lower = (words) => String(words ?? "").toLocaleLowerCase(text.locale())
  const addName = (node) => Object.hasOwn(typeLabels, node.type)
    ? text.t("mind_graph.script.list.add_post", { title: node.title, type: lower(typeLabels[node.type]) })
    : text.t("mind_graph.script.list.add_retired_post", { title: node.title, type: lower(node.type) })
  // What stands at a row's end, and what its name counts: a post type's is
  // its posts (H2), every other row's its connections.
  const figure = (node) => (node.kind === "type" ? node.count ?? 0 : node.degree)
  const markFor = (node) => {
    if (node.kind === "page" || node.kind === "type") return markCanvas(node)
    const mark = element("span", node.kind === "tag" ? TAG_MARK : dotClass(dotClasses, node))
    mark.setAttribute("aria-hidden", "true")
    return mark
  }
  const row = (node, { notInView = false } = {}) => {
    const item = document.createElement("li")
    const button = element("button", ROW)
    button.type = "button"
    button.dataset.nodeId = node.id
    button.setAttribute("aria-label", notInView ? addName(node) : text.t(NAMES[node.kind], { title: node.title, count: figure(node) }))
    // A page stands under its parent: indented by its depth in the tree.
    if (node.kind === "page") button.style.paddingInlineStart = `${ROW_PADDING + (node.depth || 0) * INDENT}px`
    const trailing = notInView ? element("span", "shrink-0 text-label text-meta", text.t("mind_graph.script.list.not_in_view")) : element("span", "shrink-0 font-cs-mono text-label text-meta", figure(node))
    button.append(markFor(node), element("span", "min-w-0 flex-1 truncate", node.title), trailing)
    item.append(button)
    rows.set(node.id, button)
    if (notInView) {
      button.dataset.notInView = ""
      absent.set(node.id, node)
    }
    return item
  }
  // A pill's row: the pill's own words, in the small mono style they have
  // on the canvas, and its whole name. No mark: the row above is what it
  // hangs off.
  const pillRow = (pill) => {
    const item = document.createElement("li")
    const button = element("button", ROW)
    button.type = "button"
    button.dataset.nodeId = pill.id
    button.dataset.more = ""
    // The name begins with the words the row shows, so someone who says
    // what they see names it (WCAG 2.5.3, label in name).
    button.setAttribute("aria-label", text.t("mind_graph.script.list.more_row", { count: pill.count, figure: number(pill.count), target: pill.of ?? "", words: pill.title }))
    button.style.paddingInlineStart = `${ROW_PADDING + PILL_INDENT}px`
    button.append(element("span", "min-w-0 flex-1 truncate font-cs-mono text-label text-dim", pill.title))
    item.append(button)
    rows.set(pill.id, button)
    return item
  }
  // The pages as the tree they are: a page's item holds the list of its
  // children. The pages come in tree order, so a parent is met before its
  // children; one whose parent has no row here stands at the top level.
  const tree = (pages) => {
    const top = listOf()
    const items = new Map()
    for (const page of pages) {
      const item = row(page)
      const parent = items.get(page.parent)
      if (parent) (parent.querySelector(":scope > ul") || parent.appendChild(listOf())).append(item)
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
  const put = (...parts) => {
    const held = body.contains(document.activeElement) ? document.activeElement.dataset.nodeId ?? "" : null
    body.replaceChildren(...parts)
    paintMarks(body)
    if (held == null) return
    const next = rows.get(held) || body.querySelector("button[data-node-id]") || (filterable ? unlisted : null)
    next?.focus()
  }

  const rowOf = (event) => event.target.closest?.("button[data-node-id]")
  const click = (event) => {
    const button = rowOf(event)
    if (!button) return
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
    marked = id == null ? null : rows.get(id) || null
    if (!marked) return

    marked.setAttribute("aria-current", "true")
    // Into view within the panel only, and only as far as needed.
    const box = container.getBoundingClientRect()
    const rowBox = marked.getBoundingClientRect()
    if (rowBox.top < box.top) container.scrollTop -= box.top - rowBox.top
    else if (rowBox.bottom > box.bottom) container.scrollTop += rowBox.bottom - box.bottom
  }

  const line = (content) => element("p", "m-0 px-3 py-3 text-sm text-meta", content)

  return {
    render(nodes) {
      forget()
      const of = (kind, order) => nodes.filter((node) => node.kind === kind).sort(order)
      const groups = [ [ "pages", of("page", byTree) ], [ "posts", of("post", byDegree) ], [ "tags", of("tag", byDegree) ], [ "types", of("type", asGiven) ] ].filter(([ , found ]) => found.length)
      const pills = of("more", asGiven)
      if (!groups.length && !pills.length) return put(line(text.t("mind_graph.script.list.empty")))

      const lists = new Map()
      const parts = groups.map(([ name, found ]) => {
        const list = name === "pages" ? tree(found) : listOf(found.map((node) => row(node)))
        lists.set(name, list)
        return section(text.t(`mind_graph.script.list.${name}`, { count: found.length }), list)
      })
      // Each pill under the row of what it hangs off; one with no such row
      // at the end of the posts, or after the groups when no post is drawn.
      const loose = []
      for (const pill of pills) {
        const hub = rows.get(pill.target)?.closest("li")
        if (hub) hub.after(pillRow(pill))
        else loose.push(pillRow(pill))
      }
      if (loose.length && lists.has("posts")) lists.get("posts").append(...loose)
      else if (loose.length) parts.push(listOf(loose))
      put(...parts)
    },
    // A filter's rows in place of the groups. `inView(id)`: whether the
    // canvas draws that post now. `back`: the rows are a pill's, and this
    // is the way back to the groups.
    showRows({ heading, rows: given, inView, link = null, back = null }) {
      forget()
      goBack = back?.onBack ?? null
      const parts = [ section(heading, listOf(given.map((node) => row({ ...node, kind: "post" }, { notInView: !inView(node.id) }))), { back }) ]
      if (link) {
        const anchor = element("a", "mx-3 mt-2 inline-block text-sm text-accent underline", link.label)
        anchor.href = link.href
        anchor.dataset.mindGraphPostsLink = ""
        parts.push(anchor)
      }
      put(...parts)
    },
    // A read that failed (design answer G5): the line and a small button
    // that asks again, in the list. `focus`: the press that asked was the
    // button's own, which this call has just removed, so the new one takes
    // the focus and the keyboard is not left on nothing.
    // `back`: the read was a pill's, and the error line keeps the way back
    // to the groups beside "Try again" (and Escape goes back).
    fail(content, { label, onRetry, focus = false, back = null }) {
      const held = body.contains(document.activeElement)
      forget()
      goBack = back?.onBack ?? null
      const said = element("div", "flex flex-col items-start gap-2 px-3 py-3")
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
