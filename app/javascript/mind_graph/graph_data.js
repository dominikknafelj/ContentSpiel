// The graph's data as the page holds it (pages in the mind graph, spec §1,
// §4): plain functions over the payload, with no canvas and no element, so
// each can be asked directly by a test.
//
// A node is `{ …what the server sent, kind, title }`; `kind` is "page",
// "post", "tag", "type" (a post type a page lists, and the one "All posts"
// node) or "more" (a "+N more" pill of a page's local view, one per
// target). The payload has no `kind`: a node's is the array it came in
// (`app/queries/post_graph.rb`). Pages come first, in tree order as the
// server sends them.

// A page's fixed bonus over a post with as many links, in links (design
// answer, part one §6: "a fixed bonus"; half a link is a READING).
const PAGE_BONUS = 0.5

// A type that is no longer registered has no colour slot, and is not "All
// posts" (design answer G1): its hub is drawn as an outline (`marks.js`) and
// its label ends "(retired)", in the messages' words.
const retiredType = (type) => type.id !== "all-posts" && type.colour_index == null

// `allPosts` is the one "All posts" node's name, `more(count)` a pill's
// words and `retired(name)` a retired type's label: the page's messages,
// handed in so that no word is written here.
export function nodesOf(data, { allPosts, more, retired }) {
  return [
    ...(data.pages || []).map((page) => ({ ...page, kind: "page" })),
    ...data.nodes.map((node) => ({ ...node, kind: "post" })),
    ...data.tags.map((tag) => ({ ...tag, title: tag.name, kind: "tag" })),
    ...(data.types || []).map((type) => ({ ...type, title: type.id === "all-posts" ? allPosts : retiredType(type) ? retired(type.label) : type.label, kind: "type" })),
    ...(data.more || []).map((pill) => ({ ...pill, title: more(pill.count), kind: "more", degree: 1 }))
  ]
}

// Whose label comes first (design answer, part one §6 and F1): Home, then
// the top-level pages and the type nodes, then everything else by its links.
export const rank = (node) => (node.kind === "page" && node.home ? 0 : (node.kind === "page" && node.depth === 1) || node.kind === "type" ? 1 : 2)

const weight = (node) => (node.degree ?? 0) + (node.kind === "page" ? PAGE_BONUS : 0)

// "+N more" is a pill with its words inside it (design answer G2): it has
// no label beside it and takes no place in the order.
const labelled = (node) => node.kind !== "more"

// The given indexes, best first: the order labels are placed in and the
// order the label rule's budget is spent in.
export const orderOf = (nodes, indexes) =>
  indexes.filter((index) => labelled(nodes[index])).sort((a, b) => rank(nodes[a]) - rank(nodes[b]) || weight(nodes[b]) - weight(nodes[a]) || a - b)

// The nodes whose label is always shown and uses up none of the budget.
export const freeOf = (nodes, indexes) => new Set(indexes.filter((index) => labelled(nodes[index]) && rank(nodes[index]) < 2))
