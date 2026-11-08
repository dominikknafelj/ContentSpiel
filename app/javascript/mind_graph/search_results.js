// The whole site's results, as the list draws them in the tree's place
// (`node_list.js`, `showResults`): the readable pages, posts and tags whose
// name holds the query, the graph's drawing them or not, each row a LINK to
// that row's local view -- so a result is opened like any other link, by
// click, Enter or a new tab, and Back returns. A row's URL is the server's
// (`href` from the response); a title, a path or a tag's name is written
// with `textContent`, never as markup.
//
// GROUPED: "Pages", "Posts", "Tags", in that order, each a list named by its
// heading and left out when it is empty. There is no fourth group: a row
// opens a local view, and a post type has none. A heading is drawn as the
// tree's group headings are, on the row's geometry with its kind's icon chip
// in the mark box and its words in the label style, but it is a heading and
// not an item: it folds nothing and is pressed by nobody.
//
// A ROW IS THE TREE'S ROW (`classes`, `Admin::Ui::TreeItemComponent::
// CLASSES`): flat, its kind's mark in the mark box -- a page the tree's page
// glyph, a post its type's dot, a tag the square -- and its title, with a
// page's ADDRESS under it in the small meta style: two pages may share a
// title. The link draws its own focus ring inside its box.
import { dotClass, TAG_MARK } from "mind_graph/card"

const GROUPS = [ [ "page", "icon-page" ], [ "post", "icon-post" ], [ "tag", "icon-tag" ] ]
const RING = "focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-accent"

// How many times results were drawn: a heading's id is unique in the page.
let drawn = 0

// Appends the groups of `rows` (the search's answer) to `list`.
export function renderResults(list, rows, { text, dotClasses, classes, parts }) {
  const element = (tag, className, content) => {
    const created = document.createElement(tag)
    if (className) created.className = className
    if (content != null) created.textContent = content
    return created
  }
  const markBox = (mark) => {
    const box = element("span", classes.mark)
    box.append(mark)
    return box
  }
  const markOf = (row) => {
    if (row.kind === "page") return parts.part("tree-page-mark")
    const mark = element("span", row.kind === "tag" ? TAG_MARK : dotClass(dotClasses, row))
    mark.setAttribute("aria-hidden", "true")
    return mark
  }
  const result = (row) => {
    const item = document.createElement("li")
    const link = element("a", `${classes.row} ${classes.row_flat} ${RING}`)
    link.href = row.url
    const title = element("span", classes.title, row.label)
    title.title = row.label
    if (row.kind === "page" && row.path) {
      const words = element("span", "flex min-w-0 flex-1 flex-col")
      words.append(title, element("span", "min-w-0 truncate text-small text-meta", row.path))
      link.append(markBox(markOf(row)), words)
    } else {
      link.append(markBox(markOf(row)), title)
    }
    item.append(link)
    return item
  }
  drawn += 1
  list.append(...GROUPS.flatMap(([ kind, icon ]) => {
    const found = rows.filter((row) => row.kind === kind)
    if (found.length === 0) return []

    const group = element("section", "not-first:mt-(--cs-sp-3)")
    group.dataset.searchGroup = kind
    const heading = element("h3", `m-0 ${classes.row} ${classes.row_flat}`)
    heading.id = `mind-graph-results-${drawn}-${kind}`
    const words = element("span", classes.title)
    words.append(element("span", "text-label text-meta", text.t(`mind_graph.script.search.groups.${kind}`)))
    heading.append(markBox(parts.part(icon)), words)
    const items = element("ul", "m-0 list-none p-0")
    items.setAttribute("role", "list")
    items.setAttribute("aria-labelledby", heading.id)
    items.append(...found.map(result))
    group.append(heading, items)
    return [ group ]
  }))
}
