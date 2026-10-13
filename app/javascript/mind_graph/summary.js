// What the canvas says of itself (pages in the mind graph, spec §6; design
// answers G6 and H5). The canvas is one image to a screen reader, and its
// name says what is on it NOW: the counts in view by type, then the lines,
// then the scope. A plain function over what the page holds, with no canvas
// and no element, so a test can ask it for every form.
//
//   the whole graph   "Mind graph: 9 pages, 3 post types, 13 posts and 4 tags, 27 connections. Showing everything."
//   a local view      "Mind graph around Blog, depth 2: 7 pages, 1 post type and 20 of 112 posts. 92 more are in the list."
//   opened by the 3,000-line rule, that view adds
//                     "Showing the area around Home. The site has 212 pages, 2,040 posts and 64 tags."
//   a kind that is off adds "Tags hidden.", a kind of line "Shares-a-tag lines hidden.";
//     "Showing everything. Tags hidden." are both said, in that order:
//     "everything" means no cap, not no filters
//   nothing in view   "Mind graph: nothing to show. All types are hidden." (every kind is off)
//                     "Mind graph: nothing to show. No pages, posts or tags yet." (there is nothing)
//
// A kind with nothing in view is left out. "N of M posts" and the "more"
// sentence are a page's that lists more than its view draws: M is the
// page's `listed_count`, and "more" counts every pill in view together (a
// pill goes with the posts, so with Posts off neither is said).
//
// "Showing everything." IS NEVER SAID AT A CAP (H5). A whole graph cut at
// the posts' cap says the notice's own cap sentence in its place; a local
// view never says it at all, and `capped_local` is not said here either:
// around a page `shown` and `total` are the posts drawn and always equal.
//
// Every word is the page's (`text`, `i18n/messages.js`): a sentence is one
// message, two sentences are joined by one space and nothing else, and the
// counts are joined by the messages' own `pair` and `series`, so another
// language can join them otherwise. `number` groups a figure as the
// sentence's language does; `count` only chooses a plural's form.
//
//   nodes         every node of the response (`graph_data.js`, `nodesOf`)
//   visibleNodes  the indexes of those in view
//   lines         how many lines are in view
//   data          the response: `focus`, `shown`, `total`, and `site` in a local view
//   off           { nodes, lines }: the names of the toggles that are switched off, in the legend's order
//   toggles       how many kinds of node the viewer has a toggle for
//   aroundHome    whether this view was opened by the 3,000-line rule
export function summaryOf({ nodes, visibleNodes, lines, data, off, toggles, aroundHome = false }, { text, number }) {
  // Every key is written out whole where it is asked for (a `${...}` stands
  // for one segment): `test/lib/script_messages_test.rb` reads them here.
  const counted = (key, count, extra = {}) => text.t(`mind_graph.script.summary.${key}`, { count, figure: number(count), ...extra })
  // "a, b, c and d", in the messages' own words for a pair and a series.
  const series = (items) => items.slice(0, -2).reduceRight((rest, first) => text.t("mind_graph.script.summary.series", { first, rest }),
    items.length > 1 ? text.t("mind_graph.script.summary.pair", { first: items.at(-2), last: items.at(-1) }) : items[0])

  const inView = visibleNodes.map((index) => nodes[index])
  const drawn = (kind) => inView.filter((node) => node.kind === kind).length
  const focus = data.focus
  const more = inView.filter((node) => node.kind === "more").reduce((sum, pill) => sum + pill.count, 0)
  const listed = more > 0 && focus?.kind === "page" ? nodes.find((node) => node.id === focus.node_id)?.listed_count ?? null : null
  const kinds = [ [ "pages", drawn("page") ], [ "types", drawn("type") ], [ listed == null ? "posts" : "posts_of", drawn("post"), { total: number(listed ?? 0) } ], [ "tags", drawn("tag") ] ]
    .filter(([ , count ]) => count > 0).map(([ key, count, extra ]) => counted(key, count, extra))
  const allOff = toggles > 0 && off.nodes.length === toggles

  const sentences = []
  if (kinds.length === 0) {
    sentences.push(text.t("mind_graph.script.summary.nothing"))
    if (nodes.length === 0) sentences.push(text.t("mind_graph.script.summary.none_yet"))
    else if (allOff) sentences.push(text.t("mind_graph.script.summary.all_hidden"))
  } else if (focus) {
    sentences.push(text.t("mind_graph.script.summary.local", { title: focus.title, depth: focus.depth, kinds: series(kinds) }))
    if (more > 0) sentences.push(counted("more", more))
    // The view the 3,000-line rule opened: where it is, and what the site holds.
    if (aroundHome && data.site) {
      const site = [ [ "pages", data.site.pages ], [ "posts", data.site.posts ], [ "tags", data.site.tags ] ].filter(([ , count ]) => count > 0).map(([ key, count ]) => counted(key, count))
      sentences.push(text.t("mind_graph.script.summary.around_home"))
      if (site.length > 0) sentences.push(text.t("mind_graph.script.summary.site", { kinds: series(site) }))
    }
  } else {
    sentences.push(text.t("mind_graph.script.summary.whole", { kinds: series(kinds), connections: counted("connections", lines) }))
    sentences.push(data.shown < data.total ? text.t("mind_graph.script.capped", { shown: number(data.shown), total: number(data.total) }) : text.t("mind_graph.script.summary.everything"))
  }
  // What is switched off, unless that has been said already: with nothing
  // drawn at all there is nothing to hide, and "All types are hidden." names
  // every kind at once.
  if (nodes.length > 0 && !(kinds.length === 0 && allOff)) {
    for (const kind of off.nodes) sentences.push(text.t(`mind_graph.script.summary.hidden.${kind}`))
    for (const kind of off.lines) sentences.push(text.t(`mind_graph.script.summary.hidden_lines.${kind}`))
  }
  return sentences.join(" ")
}
