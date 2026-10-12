# Pages in the Mind graph, step one

Date: 2026-10-12. Status: design; the plan follows once the open design questions at the end are answered.

## Why

The Mind graph shows posts and tags. It cannot show where a post appears on the site, because pages are not in it, and nothing in CS Studio shows a post that no page lists. The owner decided that pages join the graph (roadmap, version 1, item 5). The look and the behaviour were put to the design system's owner on 2026-10-12 (`.superpowers/design-answers/2026-10-12-pages-in-mind-graph.md` in the main checkout); every size, token and wording below that is not marked as this spec's own is that answer's, copied.

The answer's reason is the reason of this work: a graph of the tree alone repeats the Pages screen in a form that is harder to read. Pages earn their place through what they list. The graph is still read-only; moving and reordering pages stay in the tree.

The owner split the work in two on 2026-10-12. This is step one. Step two is links in the text as edges ("What this does not do").

## What a person gets

- Pages are nodes: a small card-shaped rectangle beside the posts' dots and the tags' squares, with Home at the centre.
- Two new kinds of line: **Tree** (a page to its parent) and **Lists** (a page to the tag, or the post type, a post-list block of it filters by).
- One status rule for pages and posts: live, draft, scheduled, live with changes.
- The legend is the filter: Pages, Posts, Tags and the four kinds of line are toggles with counts.
- Search finds pages too, grouped Pages / Posts / Tags, a page with its path.
- The list beside the canvas has a Pages group in tree order, and a filter "Not listed on any page".
- A page has a node card and a local view of its own.

## What changes in the graph as it is, for someone who never looks at a page

1. **Every post node is drawn differently.** Today a live post has a solid outline and a draft or scheduled post a dashed one with a small core. From now on: live filled, draft an outline, scheduled an outline with a centre, live with changes filled with a warn dot. "Draft" and "Scheduled" can be told apart for the first time, and a live post with unpublished changes is marked for the first time.
2. **The legend becomes controls.** Its type entries and line entries are checkboxes with counts. The three radios "Show connections: All / Related / Tags" are removed: the line toggles say the same and more (decision 8).
3. **A line turned off hides the line, not the nodes.** Today "Related" also hides every node without a related-post line. Nodes are hidden by their own toggle only.
4. **Search results are grouped** under "Pages", "Posts", "Tags", each row with its type's marker.
5. **Post labels are `--cs-dim`**, where they are ink today, so that a page's label (ink) reads first. Tags' labels are mono.
6. **A node's id in the data and in the tests' attributes is typed** (`post-7`, not `7`), and the screen opens for someone who may read pages and no post.
7. **A site with very many connections opens around Home**, with "Show everything" (decision 6).

## Decisions

The owner's and the design answer's are named as such. The others are this spec's, each with what it rejected.

1. **Step one is pages, tree lines, lists lines, the status looks, the legend as filter, search, the list, the card and the local view.** (Owner, 2026-10-12.)
2. **The look is the design answer's**, unchanged (§4).
3. **The graph shows the rows, not the published copies.** CS Studio is the editors' view: the tree, the posts list and the editors all show the rows. A live page with unpublished changes is drawn with its warn dot, and its lists lines follow the block settings as they are being edited, so a line can show what the public does not see yet; the dot is what says so. Rejected: reading the copies for live records (`Publishing.published_all`), which would draw two sources in one picture and hide the block someone has just added.
4. **A node's id is its kind and its database id: `page-12`, `post-12`, `tag-12`, `type-blog`.** One rule for every kind and every place: the payload's `id`, an edge's `source` and `target`, `data-selected`, `data-labelled`, `data-pinned`, a search row. Today a post's id is the bare number and only a tag's is prefixed. Rejected: leaving posts bare and prefixing pages, which keeps two rules and makes every `typeof id` in the script a branch. The address keeps one parameter per kind (`?page=12`, `?post=12`, `?tag=12`), read as decimal numbers as today; `page` wins over `post`, which wins over `tag`.
5. **Every readable page is drawn, always; the cap stays 2,000 posts.** Pages are few and are the frame the rest hangs on, and a tree with pages missing is not a tree. No cap on pages is built; the measurement (§9) is taken at 200.
6. **Above 3,000 lines the screen opens in the local view around Home**, with "Show everything" (design answer). The `data` read counts the lines it would answer before it builds any node, and above `PostGraph::OPEN_AROUND_HOME_ABOVE` (3,000) answers `{ open: "page-<home>", edges: N }` and no graph; the script then visits Home's local view with `replace`, where the focus bar offers "Show everything" (`?everything=1`, which is never redirected). Rejected: deciding in the page's own request, which holds no graph data and would have to run the graph's reads twice; and deciding in the script after the whole graph has arrived, which pays for half a megabyte to throw it away.
7. **No positions are saved.** The design answer asks that the graph "opens settled (only the last ~600ms animated)". That is what the worker does today for a graph above 300 nodes without storing anything: it computes fast and shows the last 600 ms (`FINAL_STRETCH_MS`). What a person waits for before that is the computing, 2.5 seconds at the cap today. Step one keeps this and measures it at 200 pages and 2,000 posts (§9). Rejected for now: saved positions, which need a store (per person or per site, invalidated by every change to the graph, in step with rights) for a wait that decision 6 already avoids on the sites where it is longest. If the measurement shows more than three seconds to rest, saved positions become their own piece of work, on the roadmap.
8. **The legend's toggles replace the radios**, and the state lives in the page: nothing is stored, a new visit starts from the defaults (everything on), and Back restores what the person had chosen, as it does for the radios today. Rejected: keeping both controls (two filters over the same lines), and remembering the choice per person (a preference store this screen does not have).
9. **A lists line is made from the block, never from the posts.** One line per distinct target of a page: the tag when the block names a tag, otherwise the post type. Two blocks of one page with the same target are one line.
10. **"Not listed on any page" is its own read**, not a filter over the drawn nodes. A post with no connection is not drawn today, and a post no page lists is very likely such a post: a filter over the nodes would miss the posts it is for.
11. **The module keeps its name, `PostGraph`.** Rejected: renaming it (`SiteGraph`) in the same change, which touches every file and test of the screen for no behaviour. It is renamed with step two or not at all.
12. **Hit testing and the label check stay as they are unless the measurement says otherwise.** The design answer names a quadtree for both. The hit test is a linear scan measured at 0.2 ms at the cap, and already includes the label boxes; d3's quadtree is inside the worker's bundle and is not importable in the page. A quadtree is built only if a frame is late at 2,200 nodes.

## 1. The data

**Today.** `PostGraph::Global` reads the readable posts' ids, the relations and the tag links, ranks, cuts at the cap and hands `PostGraph::Builder` the ids; `PostGraph::Local` walks outward from a focus and hands the builder the same. The builder answers `{ nodes, tags, edges }`. Six statements for the global view, three per depth level plus six for a local one.

**New.** The payload gains `pages` and `types` beside `nodes` (the posts) and `tags`, and two edge kinds:

- `pages: [{ id: "page-<id>", title, path, depth, home, parent, order, status, changes, url, degree, child_count, listed_count, open_notes }]`. `order` is the page's place in tree order (parent, then `position`), worked out in Ruby from `parent_id` and `position` of the pages already loaded; `depth` 0 is Home, the tree's one root. `path` is the page's current `public_paths` row in the editing language, else the default language's. `listed_count` is the readable posts its blocks list.
- `types: [{ id: "type-<name>", name, colour_index, count }]`: a post type that a drawn lists line points at. How it is drawn is open design question 1.
- `edges` gain `{ kind: "tree", source: "page-<child>", target: "page-<parent>" }` and `{ kind: "lists", source: "page-<id>", target: "tag-<id>" | "type-<name>" }`.
- A post gains `changes` and `listed` (whether a readable page lists it).

**What a lists line is computed from.** The blocks of the readable, kept pages whose type has the `lists_posts` capability (`BlockTypes.with_capability`, never the type's name), in sections or not: `owner` is the page either way. One statement for all pages. For each block, its typed settings' `content_type` and `tag`:

- a tag is named: the target is that tag, found by name as the listing does (`Tag.named`'s rule, one statement for all the names); a name no tag has makes no line, as it lists nothing;
- no tag, a content type: the target is that type;
- neither: the block lists every registered type; its target is part of open design question 1.

A listed tag is a node whenever its page is readable, also when fewer than two readable posts carry it: the viewer can read the page, and the block's settings name the tag. Its `count` stays the number of readable posts. `PostGraph::Focus` accepts a tag that a readable post carries or a readable page lists.

**Which posts a page lists** (`listed_count`, `listed`, the local view's depth 2, the unlisted read) is worked out in Ruby from what is already loaded: the readable posts' `(id, content_type, published_at, updated_at)`, the tag links, the blocks. One new object, `PostGraph::Listings`, owns it, and asks `BlockTypes::PostList` for the criteria (a function that takes the same settings and a post's type and tag names), so the listing, a post's address and the graph cannot come to disagree about which page lists which post. A parity test holds it against `BlockTypes::PostList.listed_posts(settings, include_unpublished: true)`.

**The cost** is a fixed number of statements whatever the size: twelve for the global view as designed (the six of today; the readable pages; the list blocks; the tags the blocks name; the pages' paths; the pages' open notes; and one more only if open design question 2 needs the pending copies). A local view pays the same fixed part; its walk stays three statements per depth level. Never one per page, per block or per post: a `capture_sql` test builds the graph for 3 pages and for 30, and for 3 posts and 30, and compares the counts.

**The global view's cut is as today**, among posts. A lists line is not a post's connection: a post with no related post and no shared tag is still left out and counted in the "isolated" sentence. A tag made a node by a lists line connects the posts that carry it, so some posts that were isolated are now drawn.

## 2. Rights and the trash

- A page is in the graph only through `AccessControl.scope(actor, "pages.read", Page.all)`, a post only through the posts' scope, as today. What is outside is not a node, not in a count, not a search row, not a list row, and no line is drawn to it: a tree line needs both pages readable, so a page whose parent is outside the scope is drawn without one.
- `listed_count`, `listed` and "Not listed on any page" are computed from readable pages and readable posts only. So "not listed" means "no page you can read lists it" (Risks).
- A focus on a page outside the scope, a trashed page or an id that names nothing is a 404, from the page and from `data` alike (`PostGraph::Focus`).
- The screen opens for someone who holds `pages.read` or `posts.read` anywhere; the legend names only the kinds and post types the viewer can read something of.
- Trashed pages and posts are left out by the scopes. The three reads (`data`, `search`, the new `unlisted`) and the page itself join `test/integration/trash_visibility_test.rb` for pages as they are there for posts: a trashed page is no node, its tree and lists lines are gone, it is no search row and its children are drawn without a line to it.
- The queries hand up data only. A page's editor URL is built by the `url_for:` callable the controller passes, as a post's is today; search rows and unlisted rows are `{ kind, id, label, … }` and the controller adds the URLs. No query names a route, a component or a colour (`test/lib/dependency_direction_test.rb`).

## 3. The reads

- `GET mind_graph` (the frame), `mind_graph/data`: as today, plus `page=` and `everything=1`.
- `mind_graph/search?q=`: up to ten pages by title in any language (`title_matching_any_locale`, in tree order), then posts, then tags, each row with its kind; a page's row carries its path.
- `mind_graph/unlisted` (new, JSON, the screen's permission and scope): the readable posts no readable page lists, newest first, the first 200 with the total. A row whose post is drawn selects its node; one that is not is a link to the post's local view, as a search result is.

## 4. The look (the design answer's values)

**Page nodes.** A rectangle 14×10 with the card's radius (`rounded-cs`, `--cs-radius`); Home 18×13. Fixed size, not scaled by links. Neutral ink: the `cat-n` colours mean post types.

**Status, one rule for pages and posts.**

| State | Look |
|---|---|
| Live | filled: `--cs-ink` for a page, the type's `cat-n` for a post |
| Draft | outline only, 1.5px `--cs-meta`, `--cs-surface` inside |
| Scheduled | outline in `--cs-dim` with a 3px filled centre |
| Live with changes | filled, with a 5px `--cs-warn` dot bottom-right |

The corners are then: notes badge top-left, pinned dot top-right, changes dot bottom-right.

The state is never worked out in the script or by comparing `published_at`. The builder asks `Publishing::State` for each record it has loaded: `status` and `changes?`, which cost no statement, as the tree and the posts list ask them. `Builder::COLUMNS` gains `unpublished_changes_at`. `Publishing::State` has five states and the design answer four looks: the fifth is open design question 2.

**Lines.** Tree: solid 1px `--cs-line-strong`. Lists: dotted 1px `--cs-dim`. Related: solid 1.5px ink, as now. Shares a tag: dashed `--cs-meta`, as now. On selection only the node's own lines brighten; accent stays for the selection ring. Lines are drawn in batches, one path per style; a line that cannot cross the view is skipped, as today; below 40% zoom "Shares a tag" is not drawn (a drawing rule only: the toggle, the counts and a selection's neighbours do not change with the zoom).

**Labels.** 12px sans `--cs-ink` for a page; tags keep mono; posts sans `--cs-dim`. Priority: Home, top-level pages, hubs by links, the rest; a page has a fixed bonus over a post with equal links. Home's and the top-level pages' labels do not count against the zoom's budget. The rules of today stay above all of it: the selection, the focus and the selection's neighbours place first, and no overlap wins over "always shown".

**The canvas reads tokens.** `mind_graph/theme.js` gains `dim` (`--cs-dim`), `warn` (`--cs-warn`) and the radius; the script holds no colour value (`test/lib/admin_design_rules_test.rb`). The legend's swatches use `.mg-*` classes on the same tokens.

## 5. The layout

All of it is in `mind_graph/layout_worker.js`; d3-force stays loaded by the worker alone, by URL, and both pins stay `preload: false` (`test/integration/public_javascript_test.rb`).

- `start` hands each edge its kind and each node its collision radius (a page's is half its diagonal). The link force reads distance and strength by kind: a tree line is short and stiff (distance 40, strength 0.9, this spec's starting values, tuned at the measurement), the others as today (distance 90, d3's default strength).
- **Home is held at the centre while the layout runs**: `start` marks it `anchor`, and the worker sets its `fx` / `fy` to 0, 0. It is not in the page's `state.pinned`, shows no pin dot and is not counted in "Release N pinned". A person who drags Home pins it where they drop it, like any node; releasing it puts it back at the centre.
- No pinning by depth, no rings by level (design answer).
- A type or kind that is toggled off is handed to the worker as today's filter is: the visible nodes and edges only; a hidden node keeps its last place.

## 6. The legend as filter

`Admin::MindGraphScreen::LegendComponent` draws, in this order: a group of node toggles (Pages, Posts, Tags), a group of line toggles (Tree, Lists, Related, Shares a tag), then the keys that are not controls: the post types' dots, the four status looks, "Retired type" when present, "Pinned", "Open notes". "Draft or scheduled" goes.

- A toggle is a native checkbox in a `<fieldset>` with a `<legend>`, its swatch and name in its `<label>`, wired through `data-action` on `admin--mind-graph--graph`. Space toggles it; its accessible name is one key with the name and the count ("Pages, 200").
- The legend stays where the radios are in the document: after the search and a local view's focus bar, before the zoom buttons and the canvas. The Tab order is still search, graph, list (`test/integration/admin/mind_graph_test.rb`).
- The counts are written by the script when the data arrives (the page holds no data): the number of each kind in this response, and of each line kind. They do not change when a toggle is switched: a toggle that is off still says what switching it on brings. `reset()` takes the counts back on a restored snapshot; the checkboxes' state is the person's and is kept, as the radios' is today.
- A node kind that is off: its nodes and every line that touches one are not drawn, its group leaves the list, the canvas's name (`script.summary`) counts what is drawn. Search is not filtered: it reaches what the graph does not draw, as it does past the cap.
- A change is announced by the canvas's summary in the polite status line the notice already uses.

## 7. Search, the list, the card, the local view

**Search.** Grouped Pages / Posts / Tags with the type's marker; a page's path in 11px mono under its title.

**The list.** Three groups. "Pages · N" comes first, in tree order with indents by depth, not by link count; Posts and Tags as today. Above the groups a checkbox "Not listed on any page": while on, the list shows the `unlisted` read's rows in place of the groups, with the total, and the canvas is left as it is.

**A page's card.** The path, the status pill, "4 child pages · lists 112 posts", the open notes under the title as on a post's card (`card_notes.js`, with a `data-page-notes-url` template beside the post's), then "Open page" (primary), "Focus", "Pin" / "Unpin". Enter on a selected page opens it, as for a post.

**The local view around a page.** Depth 1: its parent, its children, and the tags or post type its blocks list. Depth 2 adds the posts it lists, the 20 most recent (by `published_at`, a draft by `updated_at`) plus a "+N more" node. "The pages and posts that link to it" of the design answer's depth 1 are step two. Around a post or a tag the walk is as today and now also steps along a lists line, so a post's local view at depth 2 reaches the pages that list one of its tags.

## 8. Strings

All in `config/locales/admin/`: the legend's in `mind_graph_screen.en.yml`, the view's and the script's in `mind_graph.en.yml`, every script key written out in the view's `data-messages`. The design answer's words are marked (D); the others are this spec's.

- Legend: "Pages", "Posts", "Tags" (D); "Tree", "Lists", "Related", "Shares a tag" (D); "Live", "Draft", "Scheduled", "Live with changes" (D); group names "Show" and "Lines"; a toggle's name "%{name}, %{count}". Removed: "Draft or scheduled", "Related post", and the view's `filter.*`.
- View: intro "How your pages, posts and tags connect. Scroll or pinch to zoom, drag to move."; "No pages or posts yet."; search label and placeholder "Find a page, post or tag"; canvas label "Graph of pages, posts and tags"; list label "Pages, posts and tags in this graph"; focus bar "Around the page “%{title}”", "Show everything" (D).
- Script: summary "Graph of pages, posts and tags: %{pages} pages, %{posts} posts and tags, %{edges} connections."; search groups "Pages", "Posts", "Tags" (D), "No page, post or tag matches."; list "Pages · %{count}", "Not listed on any page" (D), "%{title}: page, %{count} connections. Shows it in the graph." (one / other); card "Open page" (D), "%{count} child page" / "%{count} child pages" (D), "lists %{count} post" / "lists %{count} posts" (D), status "Live with changes"; "+%{count} more" (D); notice "This site has %{figure} connections, so the graph opens around Home."

## What this does not do

- **Step two: links in the text as lines.** They must first be read out of every rich-text document and kept as derived rows. With them come the legend toggle "Links in text" (off by default, solid 1px `--cs-meta` with a 4px arrowhead), the list filter "Not linked from anywhere", and "the pages and posts that link to it" in a page's local view. On the roadmap.
- Editing structure in the graph: no moving, reordering or creating pages.
- Saved positions (decision 7), a remembered legend choice (decision 8), presence in the graph, WebGL.
- A cap on pages.

## Risks

- **"Not listed on any page" is true for the viewer, not for the site.** Someone who reads only part of the tree is told a post is unlisted when a page they cannot read lists it. Saying otherwise would disclose that page. The guide says so.
- **A line that is not public yet.** The rows are shown (decision 3), so a lists line on a live page with changes can be one visitors do not get. The warn dot is the only cue.
- **The existing graph changes for everyone** (the list near the top), post nodes above all. It ships as one visible change and the guide's page is rewritten with it.
- **The 3,000-line rule may be the normal case at the size the performance rule names.** 200 pages and 2,000 well-tagged posts can exceed 3,000 lines, and such a site would then always open around Home. Measured in §9 and reported before the build is called done.
- **A stiff tree against tag clusters.** A page that lists a tag is pulled toward that tag's posts and toward its parent at once. The starting values are a guess until seen.
- **Every system test of the graph reads ids**, and each waits about five seconds per layout; the suite's time grows with every new one.

## Testing

- `PostGraph::Listings`: the targets of a block (tag, type, a name no tag has, a block in a section), and parity with `BlockTypes::PostList.listed_posts`.
- `PostGraph::Global` and `Local`: pages, tree and lists lines; a page outside the scope is no node and takes its lines with it; the typed ids; the statement count at two sizes with `capture_sql`; the local view around a page at both depths, with the cap of 20 and the count behind "+N more"; the `open` answer above the threshold and never with `everything=1`.
- `PostGraph::Focus`: `page=`, the order of the three parameters, the 404s.
- `PostGraph::Search` and the unlisted read: scope, trash, order, the limit.
- Status: the builder's `status` and `changes` are `Publishing::State`'s for every combination the state's own test lists; a source guard that nothing under `app/queries/post_graph/` and `app/javascript/mind_graph/` compares `published_at`.
- `test/integration/trash_visibility_test.rb`: the page, `data`, `search` and `unlisted`, for a trashed page and a trashed post.
- The legend component: the toggles, their names, no type the viewer cannot read.
- Browser: each status look read from the canvas's pixels for a page and a post; each toggle hides its kind, leaves the counts, and changes the list; Home is at the centre at rest and has no pin; the Tab order; `reset()` after Back (counts gone, checkboxes kept); a page's card and its links (`click_frame_link`); the unlisted filter.
- Measurement, as the canvas spec's §7 did it, at 200 pages and 2,000 posts: the data's time and size, the time to rest, late frames while panning, the number of lines.

## Documentation

Guide, in `contentspiel-docs`: the Mind graph's page is rewritten (pages, the two new lines, the status looks, the legend as filter, "Not listed on any page" and what it means for someone with a partial read scope). Affected: the Pages page (a pointer) and the post-list block's page (where a post appears). In this repository: `docs/reference/cs-studio-shell-and-dashboard.md` (the Mind graph's part) and `CLAUDE.md` (the legend's counts in `reset()`; the graph reads rows, by decision); the roadmap gains step two and saved positions.

## Open design questions

For the design system's owner; none is decided here, and the plan waits for 1 to 3.

1. **A post type as the target of a lists line.** The answer says a page is joined to "the tags or post type its blocks list", and gives a shape for pages, posts and tags only. What is a post type on the canvas (a node of its own, with which shape, label and legend entry; counted under which toggle), and what does a block that filters by nothing, and so lists every type, point at?
2. **Live with a change scheduled.** `Publishing::State` has a fifth state, a live record with a copy waiting for its time. Which of the four looks does it take, or does it get its own? (Its own costs one more statement per response.)
3. **The status looks on posts that are rings.** Post types in colour slots 7 to 12 are drawn as a ring of their hue today, and a retired type as a grey ring with a stroke. "Live: filled" and "Draft: outline only" then differ by colour and a millimetre of width. What do the four looks mean for those posts?
4. **"+N more".** It "opens the list filtered to them": the list beside the canvas, which holds only what is drawn, or the Posts screen filtered by the block's type and tag?
5. **Depth 2 around a page.** Only the listed posts, as written, or also a second step along the tree (grandchildren, siblings)?
6. **What a listed post hangs on at depth 2** when its page lists by post type: the page, or the type's node? (Follows from 1.)
