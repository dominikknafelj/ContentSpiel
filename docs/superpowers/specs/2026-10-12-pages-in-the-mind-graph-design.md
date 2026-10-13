# Pages in the Mind graph, step one

Date: 2026-10-12. Status: **approved by the owner on 2026-10-12** ("Yes go"), the design answers folded in; the plan is `docs/superpowers/plans/2026-10-12-pages-in-the-mind-graph.md`. What the owner confirmed with the approval is listed under "Approved" below. The design questions that stay open are at the end; none holds the plan, which builds a named provisional value for each.

> **Revised 2026-10-12: the third design answers are folded in** ("The drawing, and third answers" of the answers file, which arrived after the approval), and one decision of the owner. What changed in this text:
> - the status looks: warn now means "scheduled" everywhere. Unpublished changes are a DIM corner dot, a scheduled change a WARN corner dot, a scheduled record a WARN centre dot (§4; this replaces F2);
> - a ring type is a filled-type mark inside a 1.5px ring, so the five looks are the same on every mark (this replaces F3's first lines); the exact readings of the dots, the hub's inner ring and the Lists line; a retired type's hub; the "+N more" pill (§4);
> - in a page's local view a hub draws faint lines to the posts it brings in, in place of a lists line from the page to each post (§1, §4, §7);
> - status is not a filter: a "Status" link in the legend opens the key as a popover (§6); the canvas's summary for a screen reader has three forms (§6);
> - the card's status chip names the second state; the not-in-view row's accessible name and the list's error line (§7, §8); "Show everything" is not remembered after a reload (decision 6);
> - the owner's decision: the list has a fourth group, "Post types" (§7). Its rows' look is an open design question.
>
> **The reference for anything these words leave open is the designer's drawing**, `Studio Mind Graph Pages.dc.html` in the "Content Spiel design system" project (eight boards, with a Theme tweak for light and dark). Where this text and the drawing differ, the drawing is asked first.

## Why

The Mind graph shows posts and tags. It cannot show where a post appears on the site, because pages are not in it, and nothing in CS Studio shows a post that no page lists. The owner decided that pages join the graph (roadmap, version 1, item 5). The look and the behaviour were put to the design system's owner on 2026-10-12 (`.superpowers/design-answers/2026-10-12-pages-in-mind-graph.md` in the main checkout); every size, token and wording below that is not marked as this spec's own is that answer's, copied, the follow-up answers of the same day (F1 to F6) and the third answers with the drawing (the correction, G1 to G6 and what the boards added) included. Where a later answer replaces an earlier one, this text holds the later.

The answer's reason is the reason of this work: a graph of the tree alone repeats the Pages screen in a form that is harder to read. Pages earn their place through what they list. The graph is still read-only; moving and reordering pages stay in the tree.

The owner split the work in two on 2026-10-12. This is step one. Step two is links in the text as edges ("What this does not do").

## What a person gets

- Pages are nodes: a small card-shaped rectangle beside the posts' dots and the tags' squares, with Home at the centre.
- A post type a page lists is a node too, a hub in the type's colour; a block that filters by nothing points at one "All posts" node.
- Two new kinds of line: **Tree** (a page to its parent) and **Lists** (a page to the tag, the post type or "All posts" a post-list block of it filters by).
- One status rule for pages and posts: live, draft, scheduled, live with changes, live with a change scheduled. Warn means "scheduled", as on the status chip.
- The legend is the filter: Pages, Posts, Tags, Post types and the four kinds of line are toggles with counts, everything on. Status is not a filter: a "Status" link in the legend opens the key.
- Search finds pages too, grouped Pages / Posts / Tags, a page with its path.
- The list beside the canvas has four groups: Pages in tree order, Posts, Tags and Post types; and a filter "Not listed on any page".
- A page has a node card and a local view of its own; its "+N more" opens the list with the posts that are not drawn.

## What changes in the graph as it is, for someone who never looks at a page

1. **Every post node is drawn differently.** Today a live post has a solid outline and a draft or scheduled post a dashed one with a small core. From now on: live filled, draft a DASHED outline, scheduled a solid outline with a warn centre, live with changes filled with a dim corner dot, live with a change scheduled filled with a warn corner dot. A draft is dashed on every mark, so no status depends on colour alone. "Draft" and "Scheduled" can be told apart for the first time, and a live post with unpublished changes is marked for the first time. A post of a ring type is its type's mark inside a thin ring, and shows the same five looks (§4).
2. **The legend becomes controls.** Its type entries and line entries are checkboxes with counts, everything on by default. The status looks leave the legend's row: a "Status" link opens them as a popover. The three radios "Show connections: All / Related / Tags" are removed completely: the line toggles say the same and more (decision 8). There is no "Links in text" toggle in this step: it is not drawn, not even disabled.
3. **A line turned off hides the line, not the nodes.** Today "Related" also hides every node without a related-post line. Nodes are hidden by their own toggle only.
4. **Search results are grouped** under "Pages", "Posts", "Tags", each row with its type's marker, and the list beside the canvas is grouped Pages, Posts, Tags, Post types.
5. **Post labels are `--cs-dim`**, where they are ink today, so that a page's label (ink) reads first; a hovered or selected post's label turns full ink. Tags' labels are mono.
6. **A node's id in the data and in the tests' attributes is typed** (`post-7`, not `7`), and the screen opens for someone who may read pages and no post.
7. **A site with very many connections opens around Home**, with "Show everything" (decision 6).
8. **The canvas's name for a screen reader is a sentence of its own** ("Mind graph: 9 pages, 3 post types, 13 posts and 4 tags, 27 connections. Showing everything."), where it was "Post relationship graph: N posts and tags, N connections." (§6).

## Approved (the owner, 2026-10-12)

The owner approved this spec as a whole on 2026-10-12 ("Yes go"), and with it these six points, each of which changes what a person sees or is told:

1. **The graph shows content as it is being edited**: the rows, not the published copies (decision 3).
2. **The screen opens with `pages.read` or `posts.read`** (§2).
3. **A line kind switched off hides only the lines**, never a node ("What changes", 3; §6).
4. **Above about 3,000 lines the graph opens around Home, with "Show everything"** (decision 6).
5. **No layout is saved**, unless the measurement (under "Testing") shows more than three seconds to rest; then saved positions go on the roadmap as their own piece of work, and are not built here (decision 7).
6. **"Not listed on any page" is true only within the viewer's read scope** (§2, Risks).

After the approval the owner decided one more thing, on 2026-10-12: **the list beside the canvas has a fourth group, "Post types"** (§7), so a post type's node and "All posts" have a row and a keyboard path to their card.

Not the owner's to answer, and listed under "Open design questions": the look of a row of that fourth group, and the readings this text had to make of the third answers. The plan builds each behind a named constant or a named rule, and the design system's owner confirms or replaces it.

## Decisions

The owner's and the design answer's are named as such. The others are this spec's, each with what it rejected.

1. **Step one is pages, tree lines, lists lines, the status looks, the legend as filter, search, the list, the card and the local view.** (Owner, 2026-10-12.)
2. **The look is the design answer's**, unchanged (§4).
3. **The graph shows the rows, not the published copies.** CS Studio is the editors' view: the tree, the posts list and the editors all show the rows. A live page with unpublished changes is drawn with its dim corner dot, and its lists lines follow the block settings as they are being edited, so a line can show what the public does not see yet; the dot is what says so. Rejected: reading the copies for live records (`Publishing.published_all`), which would draw two sources in one picture and hide the block someone has just added.
4. **A node's id is its kind and its database id: `page-12`, `post-12`, `tag-12`, `type-blog`, `all-posts`.** One rule for every kind and every place: the payload's `id`, an edge's `source` and `target`, `data-selected`, `data-labelled`, `data-pinned`, a search row. Today a post's id is the bare number and only a tag's is prefixed. The "All posts" node is the one node of its kind, so it has no name to add. Rejected: leaving posts bare and prefixing pages, which keeps two rules and makes every `typeof id` in the script a branch. The address keeps one parameter per kind (`?page=12`, `?post=12`, `?tag=12`), read as decimal numbers as today; `page` wins over `post`, which wins over `tag`.
5. **Every readable page is drawn, always; the cap stays 2,000 posts.** Pages are few and are the frame the rest hangs on, and a tree with pages missing is not a tree. No cap on pages is built; the measurement ("Testing") is taken at 200.
6. **Above 3,000 lines the screen opens in the local view around Home**, with "Show everything" (design answer). The `data` read counts the lines it would answer before it builds any node, and above `PostGraph::OPEN_AROUND_HOME_ABOVE` (3,000) answers `{ open: "page-<home>", edges: N }` and no graph; the script then visits Home's local view with `replace`, where the focus bar offers "Show everything" (`?everything=1`, which is never redirected). **The choice is not remembered after a reload** (third answers): once the whole graph is drawn the script takes `everything=1` out of the address (replaced, never pushed, through Turbo's own history, as the notes drawer does its parameters), so a reload asks again and opens around Home; Back to the screen restores what was on it, as it does the legend's checkboxes. Nothing is stored. Rejected: deciding in the page's own request, which holds no graph data and would have to run the graph's reads twice; and deciding in the script after the whole graph has arrived, which pays for half a megabyte to throw it away.
7. **No positions are saved.** The design answer asks that the graph "opens settled (only the last ~600ms animated)". That is what the worker does today for a graph above 300 nodes without storing anything: it computes fast and shows the last 600 ms (`FINAL_STRETCH_MS`). What a person waits for before that is the computing, 2.5 seconds at the cap today. Step one keeps this and measures it at 200 pages and 2,000 posts ("Testing"). Rejected for now: saved positions, which need a store (per person or per site, invalidated by every change to the graph, in step with rights) for a wait that decision 6 already avoids on the sites where it is longest. If the measurement shows more than three seconds to rest, saved positions become their own piece of work, on the roadmap.
8. **The legend's toggles replace the radios**, and the state lives in the page: nothing is stored, a new visit starts from the defaults (everything on), and Back restores what the person had chosen, as it does for the radios today. Rejected: keeping both controls (two filters over the same lines), and remembering the choice per person (a preference store this screen does not have).
9. **A lists line is made from the block, never from the posts.** One line per distinct target of a page: the tag when the block names a tag, else the post type, else (no filter) the single "All posts" node. Two blocks of one page with the same target are one line.
10. **"Not listed on any page" is its own read**, not a filter over the drawn nodes. A post with no connection is not drawn today, and a post no page lists is very likely such a post: a filter over the nodes would miss the posts it is for.
11. **The module keeps its name, `PostGraph`.** Rejected: renaming it (`SiteGraph`) in the same change, which touches every file and test of the screen for no behaviour. It is renamed with step two or not at all.
12. **Hit testing and the label check stay as they are unless the measurement says otherwise.** The design answer names a quadtree for both. The hit test is a linear scan measured at 0.2 ms at the cap, and already includes the label boxes; d3's quadtree is inside the worker's bundle and is not importable in the page. A quadtree is built only if a frame is late at 2,200 nodes.

## 1. The data

**Today.** `PostGraph::Global` reads the readable posts' ids, the relations and the tag links, ranks, cuts at the cap and hands `PostGraph::Builder` the ids; `PostGraph::Local` walks outward from a focus and hands the builder the same. The builder answers `{ nodes, tags, edges }`. Six statements for the global view, three per depth level plus six for a local one.

**New.** The payload gains `pages` and `types` beside `nodes` (the posts) and `tags`, and three edge kinds. In the whole graph a type node joins only the pages that list it, never the posts of its type; a page's local view is the one exception (below):

- `pages: [{ id: "page-<id>", title, path, depth, home, parent, order, status, changes, url, degree, child_count, listed_count, open_notes }]`. `order` is the page's place in tree order (parent, then `position`), worked out in Ruby from `parent_id` and `position` of the pages already loaded; `depth` 0 is Home, the tree's one root. `path` is the page's current `public_paths` row in the editing language, else the default language's. `listed_count` is the readable posts its blocks list.
- `types: [{ id: "type-<name>" | "all-posts", name, colour_index, count }]`: a post type that a drawn lists line points at, and the one "All posts" node (`colour_index` nil, drawn `--cs-dim`) when a block lists everything. `count` is the readable posts of the type (of all types for "All posts"); it is a number on the card, never an edge. A type that is no longer registered has no `colour_index` either and is not "All posts": that is how the page knows a retired type's hub.
- `edges` gain `{ kind: "tree", source: "page-<child>", target: "page-<parent>" }` and `{ kind: "lists", source: "page-<id>", target: "tag-<id>" | "type-<name>" | "all-posts" }`.
- A post and a page gain `changes` and `change_at` (the time a scheduled change comes into force, for the card's chip; nil otherwise), a post also `listed` (whether a readable page lists it).
- **In a page's local view only, a hub draws faint lines to the posts it brings in** (third answers, "Also added on the boards"): `{ kind: "brings", source: "type-<name>" | "all-posts", target: "post-<id>" }` for each post the view draws at depth 2 (§7), from the target of the first list block of the page that lists the post; and "+N more" hangs off the same way, `{ kind: "brings", source: <the target of the page's first list block that has one>, target: "more" }`. Without them the listed posts would float loose: no lists line is drawn from the page to a post. A post a block brings in by a TAG already has its "Shares a tag" line to that tag, which is its hub, so no second line is drawn between the two. (This replaces the first text's rule, this spec's own, that joined each listed post to the page by a lists line.) The whole graph has no such line: there a type node joins only pages.

**What a lists line is computed from.** The blocks of the readable, kept pages whose type has the `lists_posts` capability (`BlockTypes.with_capability`, never the type's name), in sections or not: `owner` is the page either way. One statement for all pages. For each block, its typed settings' `content_type` and `tag`:

- a tag is named: the target is that tag, found by name as the listing does (`Tag.named`'s rule, one statement for all the names); a name no tag has makes no line, as it lists nothing;
- no tag, a content type: the target is that type;
- neither: the block lists every registered type; its target is the "All posts" node, one for the whole graph however many pages list everything.

A listed tag is a node whenever its page is readable, also when fewer than two readable posts carry it: the viewer can read the page, and the block's settings name the tag. Its `count` stays the number of readable posts. `PostGraph::Focus` accepts a tag that a readable post carries or a readable page lists.

**Which posts a page lists** (`listed_count`, `listed`, the local view's depth 2 and which hub brings each post in, the unlisted read) is worked out in Ruby from what is already loaded: the readable posts' `(id, content_type, published_at, updated_at)`, the tag links, the blocks. One new object, `PostGraph::Listings`, owns it, and asks `BlockTypes::PostList` for the criteria (a function that takes the same settings and a post's type and tag names), so the listing, a post's address and the graph cannot come to disagree about which page lists which post. A parity test holds it against `BlockTypes::PostList.listed_posts(settings, include_unpublished: true)`.

**The cost** is a fixed number of statements whatever the size: thirteen for the global view (the six of today; the readable pages; the list blocks; the tags the blocks name; the pages' paths; the pages' open notes; and the pending copies of pages and of posts, one statement each, which the fifth state needs). A local view pays the same fixed part; its walk stays three statements per depth level. Never one per page, per block or per post: a `capture_sql` test builds the graph for 3 pages and for 30, and for 3 posts and 30, and compares the counts.

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
- `mind_graph/unlisted` (new, JSON, the screen's permission and scope): the readable posts no readable page lists, newest first, the first 200 with the total. A row whose post is drawn selects its node; one that is not is marked "not in view" and is added to the canvas by a click (§7).
- `mind_graph/listed?page=<id>` (new, JSON, same rules): the readable posts that page lists and the local view left out, with the total; the rows of "+N more". Each row says which hub brings it in (`via`), so a row added to the canvas gets its line.

## 4. The look (the design answer's values)

**Page nodes.** A rectangle 14×10 with the card's radius (`rounded-cs`, `--cs-radius`); Home 18×13. Fixed size, not scaled by links. Neutral ink: the `cat-n` colours mean post types.

**Status, one rule for pages and posts.** Warn means "scheduled" everywhere, as on the status chip (third answers; this replaces the first answer's warn dot for changes and F2's dim dot for a scheduled change).

| State | Look |
|---|---|
| Live | filled: `--cs-ink` for a page, the type's `cat-n` for a post |
| Draft | outline only, DASHED, 1.5px `--cs-meta`, `--cs-surface` inside |
| Scheduled | outline in `--cs-dim`, 1.5px, with a centre dot 4px across in `--cs-warn` |
| Live with changes | filled, with a corner dot in `--cs-dim` |
| Live with a change scheduled | filled, with a corner dot in `--cs-warn` |

The corner dot is 5px across, its centre 1px in from the mark's bottom-right corner (on the 45° line for a circle), with a 1.5px `--cs-surface` ring round it. The two corner dots share the corner and never occur together. The corners are then: notes badge top-left, pinned dot top-right, changes dot bottom-right. Draft is dashed on every mark; no status depends on colour alone.

**Ring types** (colour slots 7 to 12, and a retired type's grey ring with its stroke). A ring type is drawn as a filled-type mark inside a 1.5px ring in the type's colour, so all five looks carry over unchanged: the inner mark is filled when live, a dashed `--cs-meta` outline as a draft, a `--cs-dim` outline with the warn centre dot when scheduled, and the corner dots sit on the whole mark's corner. Live, at the smallest size: the ring at radius 7 with a filled radius-4 disk inside it (8px across). (This replaces F3's "status shows in the middle".)

**Post-type nodes.** A 12px filled circle (radius 6) in the type's `cat-n` colour with a `--cs-surface` inner ring 1.5px wide, its outer edge 1.5px inside the hub's radius; fixed size: a hub, not one more post. Label: the type's name, 12px sans `--cs-ink`, always shown, at the priority of the top-level pages. "All posts" is the same shape filled with `--cs-dim`, labelled "All posts". **A retired type's hub** (a type no longer registered that a block still names) is an outline circle in `--cs-dim`, 1.5px, on surface, with a 4px dim centre dot, and "(retired)" at the end of its label: it and "All posts" differ by fill, not by shade.

**"+N more".** A pill 60×16: `--cs-surface` fill, a 1px `--cs-line-strong` border, "+92 more" inside it in 10px mono `--cs-dim`. It carries its words itself and has no label beside it. In the local view it hangs off its hub by a faint 1px `--cs-line` line.

The state is never worked out in the script or by comparing `published_at`. The builder asks `Publishing::State` for each record it has loaded: `status` and `changes?`, which cost no statement of their own once the pending copies are read, as the tree and the posts list ask them. `Builder::COLUMNS` gains `unpublished_changes_at`. `Publishing::State` has five states and the graph now has five looks.

**Lines.** Tree: solid 1px `--cs-line-strong`. Lists: dotted in `--cs-dim`, drawn 1.5px with round caps and a dash of 0.1 / 3.5, which gives dots 1.5px across, 3.6px apart. Related: solid 1.5px ink, as now. Shares a tag: dashed `--cs-meta`, as now. A hub's lines to the posts it brings in and to "+N more" (a page's local view only): faint, solid 1px `--cs-line`; they have no toggle of their own and go with "Lists". On selection only the node's own lines brighten; accent stays for the selection ring. Lines are drawn in batches, one path per style; a line that cannot cross the view is skipped, as today; below 40% zoom "Shares a tag" is not drawn (a drawing rule only: the toggle, the counts and a selection's neighbours do not change with the zoom).

**Labels.** 12px sans `--cs-ink` for a page; tags keep mono; posts sans `--cs-dim`, full ink when hovered or selected. Priority: Home, top-level pages and type nodes, hubs by links, the rest; a page has a fixed bonus over a post with equal links. Home's, the top-level pages' and the type nodes' labels do not count against the zoom's budget. The rules of today stay above all of it: the selection, the focus and the selection's neighbours place first, and no overlap wins over "always shown".

**The canvas reads tokens.** `mind_graph/theme.js` gains `dim` (`--cs-dim`), `warn` (`--cs-warn`), `faint` (`--cs-line`) and the radius; the script holds no colour value (`test/lib/admin_design_rules_test.rb`). The legend's swatches use `.mg-*` classes on the same tokens.

## 5. The layout

All of it is in `mind_graph/layout_worker.js`; d3-force stays loaded by the worker alone, by URL, and both pins stay `preload: false` (`test/integration/public_javascript_test.rb`).

- `start` hands each edge its kind and each node its collision radius (a page's and the "+N more" pill's is half its diagonal). The link force reads distance and strength by kind: a tree line is short and stiff (distance 40, strength 0.9, this spec's starting values, tuned at the measurement), the others as today (distance 90, d3's default strength).
- **Home is held at the centre while the layout runs**: `start` marks it `anchor`, and the worker sets its `fx` / `fy` to 0, 0. It is not in the page's `state.pinned`, shows no pin dot and is not counted in "Release N pinned". A person who drags Home pins it where they drop it, like any node; releasing it puts it back at the centre.
- No pinning by depth, no rings by level (design answer).
- A type or kind that is toggled off is handed to the worker as today's filter is: the visible nodes and edges only; a hidden node keeps its last place.

## 6. The legend as filter

`Admin::MindGraphScreen::LegendComponent` draws, in this order: a group of node toggles (Pages, Posts, Tags, Post types), a group of line toggles (Tree, Lists, Related, Shares a tag), the "Status" link, then the keys that are not controls: the post types' dots, "Retired type" when present, "Pinned", "Open notes". "Draft or scheduled" goes.

- **Status is not a filter** (third answers). The five status looks are not in the legend's row and are no toggles: a "Status" link in the legend opens the key as a popover, the five looks each with its name, drawn on a filled mark (a ring type's are the same looks, §4). It is `Admin::Ui::MenuComponent` in its `list` form, the popover CS Studio already has for a panel that lists things and offers nothing to pick: a button that looks like a link, Enter or Space opens the key and moves the focus into it as one list a screen reader reads through, Escape closes it and gives the focus back, and it closes when neither the pointer nor the focus is on it. It is that component's own controller that opens and closes it, so the graph's script writes nothing there and `reset()` has nothing to take back.
- A toggle is a native checkbox in a `<fieldset>` with a `<legend>`, its swatch and name in its `<label>`, wired through `data-action` on `admin--mind-graph--graph`. Space toggles it; its accessible name is one key with the name and the count ("Pages, 200").
- The legend stays where the radios are in the document: after the search and a local view's focus bar, before the zoom buttons and the canvas. The Tab order is still search, graph, list (`test/integration/admin/mind_graph_test.rb`).
- The counts are written by the script when the data arrives (the page holds no data): the number of each kind in this response ("Post types" counts the type nodes and "All posts"), and of each line kind. They do not change when a toggle is switched: a toggle that is off still says what switching it on brings. `reset()` takes the counts back on a restored snapshot; the checkboxes' state is the person's and is kept, as the radios' is today.
- Everything is on when the screen opens. "Post types" off hides the type nodes and "All posts", and with them every lists line that points at one; the lists line toggle alone hides those lines and the lines to tags. There is no "Links in text" toggle in this step.
- A node kind that is off: its nodes and every line that touches one are not drawn, its group leaves the list, the canvas's summary counts what is drawn and says what is hidden. Search is not filtered: it reaches what the graph does not draw, as it does past the cap.
- A change is announced by the canvas's summary in the polite status line the notice already uses.

**The canvas's summary for a screen reader** (third answers, G6) is the canvas's name once the data has come: the counts in view by type, then the lines, then the scope. Three forms, the designer's words:

- the whole graph: "Mind graph: 9 pages, 3 post types, 13 posts and 4 tags, 27 connections. Showing everything."
- a local view: "Mind graph around Blog, depth 2: 7 pages, 1 post type and 20 of 112 posts. 92 more are in the list."
- a kind switched off adds, for each: "Tags hidden."

A kind with nothing in view is left out of the counts; "N of M posts" and the "more" sentence are said only around a page that lists more than the view draws. Until the data has come the canvas is named "Mind graph". This spec's own, where the designer's three forms say nothing: with every kind off the first sentence is "Mind graph: nothing in view."; and where the whole graph is cut at the cap, the cap's own sentence (which the notice shows) stands where "Showing everything." would.

## 7. Search, the list, the card, the local view

**Search.** Grouped Pages / Posts / Tags with the type's marker; a page's path in 11px mono under its title. Three groups, not the list's four: a search row opens its row's local view, and a post type has none (a focus is a page, a post or a tag).

**The list.** Four groups (the fourth by the owner's decision of 2026-10-12). "Pages · N" comes first, in tree order with indents by depth, not by link count; then Posts and Tags as today; then "Post types · N": a row for each post-type node and for "All posts", in the order the data has them ("All posts" first, then the types in the registry's order), so each has a keyboard path to its card. The designer's file gives no look for a row of that group ("Open design questions", 1); until it is answered a row has the shape of a Tags row: the mark, the name, the number of connections. Above the groups a checkbox "Not listed on any page": while on, the list shows the `unlisted` read's rows in place of the groups, with the total, and the canvas is left as it is. A read that fails says so in the list, not in a toast: "The list couldn't be loaded." with a small "Try again" button.

**Rows that are not drawn.** A row for a post the canvas does not draw (past the cap, an unlisted post, a post behind a "+N more") is marked "not in view" in 11px `text-meta`. Its accessible name is the designer's: "Small sites, long lives, blog post, not in view. Activate to add it to the graph.", with the post TYPE's name, not just "post". Clicking one adds the post to the canvas and selects it: the row carries the post's node payload, so no request is made, and in a page's local view the post gets the line of the hub that brings it in (the row's `via`: a faint line from a type hub or "All posts", a "Shares a tag" line to a tag).

**A page's card.** The path, the status chip, "4 child pages · lists 112 posts", the open notes under the title as on a post's card (`card_notes.js`, with a `data-page-notes-url` template beside the post's), then "Open page" (primary), "Focus", "Pin" / "Unpin". Enter on a selected page opens it, as for a post.

**The status chip on a card** (a page's and a post's; third answers, G4) keeps its three dots and adds the second state after the label: live with unpublished changes reads "● Live · Unpublished changes", with no second dot; live with a change scheduled reads "● Live · ● Change scheduled 14 Oct", with a warn dot before the second part. The date is the day the change comes into force, in CS Studio's short date format (`admin.short`), put on by the controller from the data's `change_at`.

**The local view around a page.** Depth 1: its parent, its children, and the tags or post type its blocks list. Depth 2 adds, besides the posts it lists, one more step along the tree: the grandparent, the grandchildren and the siblings (the parent's other children), each with its tree line. The posts it lists are the 20 most recent (by `published_at`, a draft by `updated_at`), each joined by a faint line to the hub that brings it in (§1), plus a "+N more" pill that hangs off the hub the same way. "+N more" opens the list beside the canvas filtered to the posts left out, which the list shows as rows "not in view" (above), with "Open in Posts →" at the bottom of the filtered list. Those rows come from a read like `unlisted` (`mind_graph/listed?page=`, same scope and trash rules, newest first, the first 200 with the total); "Open in Posts →" is a link the controller builds to the Posts screen filtered as far as its filters go by the block's type and tag. "The pages and posts that link to it" of the design answer's depth 1 are step two. Around a post or a tag the walk is as today and now also steps along a lists line, so a post's local view at depth 2 reaches the pages that list one of its tags.

## 8. Strings

All in `config/locales/admin/`: the legend's in `mind_graph_screen.en.yml`, the view's and the script's in `mind_graph.en.yml`, every script key written out in the view's `data-messages`. The design answer's words are marked (D); the others are this spec's.

- Legend: "Pages", "Posts", "Tags", "Post types" (D); "Tree", "Lists", "Related", "Shares a tag" (D); the link "Status" (D) and its key's name "Status key"; in the key "Live", "Draft", "Scheduled", "Live with changes" (D), "Live with a change scheduled"; group names "Show" and "Lines"; a toggle's name "%{name}, %{count}". Removed: "Draft or scheduled", "Related post", and the view's `filter.*`.
- View: intro "How your pages, posts and tags connect. Scroll or pinch to zoom, drag to move."; "No pages or posts yet."; search label and placeholder "Find a page, post or tag"; canvas label "Mind graph" (the first words of the summary); list label "Pages, posts, tags and post types in this graph"; focus bar "Around the page “%{title}”", "Show everything" (D).
- Script, the summary (D, G6): "Mind graph: %{kinds}, %{connections}." and "Showing everything."; "Mind graph around %{title}, depth %{depth}: %{kinds}."; "%{count} more are in the list."; "Tags hidden." and its like for the other kinds ("Pages hidden.", "Posts hidden.", "Post types hidden."); the counts "%{count} pages", "%{count} post types", "%{count} posts", "%{count} of %{total} posts", "%{count} tags", "%{count} connections", each with its singular; a pair "%{first} and %{last}" and a series "%{first}, %{rest}" (no comma before "and", as the designer writes it). This spec's own: "Mind graph: nothing in view."; "%{count} more is in the list." for one.
- Script, the rest: search groups "Pages", "Posts", "Tags" (D), "No page, post or tag matches."; list "Pages · %{count}", "Post types · %{count}", "Not listed on any page" (D), "%{title}: page, %{count} connections. Shows it in the graph." and "%{title}: post type, %{count} connections. Shows it in the graph." (one / other), "%{title}, %{type} post, not in view. Activate to add it to the graph." (D, G5), "The list couldn't be loaded." and "Try again" (D, G5); card "Open page" (D), "%{count} child page" / "%{count} child pages" (D), "lists %{count} post" / "lists %{count} posts" (D), the chip's second part "Unpublished changes" and "Change scheduled %{date}" (D, G4); "+%{count} more" (D), "not in view" (D), "Open in Posts →" (D); the node name "All posts" (D), with its card line "%{count} posts"; a retired type's label "%{name} (retired)" (D, G1); notice "This site has %{figure} connections, so the graph opens around Home."

## What this does not do

- **Step two: links in the text as lines.** They must first be read out of every rich-text document and kept as derived rows. With them come the legend toggle "Links in text" (hidden until it ships, never shown disabled; off by default, solid 1px `--cs-meta` with a 4px arrowhead), the list filter "Not linked from anywhere", and "the pages and posts that link to it" in a page's local view. On the roadmap.
- Editing structure in the graph: no moving, reordering or creating pages.
- Saved positions (decision 7), a remembered legend choice (decision 8), a remembered "Show everything" (decision 6), status as a filter (§6), a post type as a focus or a search row (§7), presence in the graph, WebGL.
- A cap on pages.

## Risks

- **"Not listed on any page" is true for the viewer, not for the site.** Someone who reads only part of the tree is told a post is unlisted when a page they cannot read lists it. Saying otherwise would disclose that page. The guide says so.
- **A line that is not public yet.** The rows are shown (decision 3), so a lists line on a live page with changes can be one visitors do not get. The dim corner dot is the only cue.
- **The existing graph changes for everyone** (the list near the top), post nodes above all. It ships as one visible change and the guide's page is rewritten with it.
- **The 3,000-line rule may be the normal case at the size the performance rule names.** 200 pages and 2,000 well-tagged posts can exceed 3,000 lines, and such a site would then always open around Home. Measured as "Testing" says and reported before the build is called done.
- **A stiff tree against tag clusters.** A page that lists a tag is pulled toward that tag's posts and toward its parent at once. The starting values are a guess until seen.
- **The hub's faint lines are read from the designer's words, not from the drawing** (which this text's author could not open): that they replace the page's line to each listed post, and that a tag's own line serves where a block lists by tag, are to be checked against the board before Task 3 of the plan is built ("Open design questions", 2).
- **The pill is 60 pixels wide whatever its figure.** "+92 more" fits; a page that lists two thousand posts says "+1980 more", which in 10px mono is the pill's whole width ("Open design questions", 4).
- **Every system test of the graph reads ids**, and each waits about five seconds per layout; the suite's time grows with every new one.

## Testing

- `PostGraph::Listings`: the targets of a block (tag, type, a name no tag has, a block in a section), and parity with `BlockTypes::PostList.listed_posts`.
- `PostGraph::Global` and `Local`: pages, tree and lists lines; a page outside the scope is no node and takes its lines with it; the typed ids; the statement count at two sizes with `capture_sql`; the local view around a page at both depths, with the cap of 20, the count behind "+N more", and each drawn post and the pill joined to the hub that brings it in and not to the page; no such line in the whole graph; the `open` answer above the threshold and never with `everything=1`.
- `PostGraph::Focus`: `page=`, the order of the three parameters, the 404s.
- `PostGraph::Search` and the unlisted read: scope, trash, order, the limit.
- Status: the builder's `status` and `changes` are `Publishing::State`'s for every combination the state's own test lists; a source guard that nothing under `app/queries/post_graph/` and `app/javascript/mind_graph/` compares `published_at`.
- `test/integration/trash_visibility_test.rb`: the page, `data`, `search` and `unlisted`, for a trashed page and a trashed post.
- The legend component: the toggles (two groups, all on, no "Links in text"), their names, no type the viewer cannot read; the "Status" button and its key of five looks, which holds no control.
- Type nodes: a type node joins only pages; one "All posts" node however many pages list everything; a block with a tag, a type and neither; "Post types" off hides them and their lines; `listed` rows and the click that adds a post.
- Browser: each of the five status looks read from the canvas's pixels for a page, a filled post and a ring post, a draft dashed on all three, warn for both scheduled looks and dim for unpublished changes; a retired type's hub and the pill; each toggle hides its kind, leaves the counts, and changes the list; the summary's three forms; the "Status" key by keyboard (opened, read, closed with Escape, the focus back on the link); Home is at the centre at rest and has no pin; the Tab order; `reset()` after Back (counts gone, checkboxes kept); a page's card, its chip in the two new states and its links (`click_frame_link`); the list's four groups; the unlisted filter, a row not in view by its accessible name, and the error line with "Try again"; "Show everything" gone from the address once drawn.
- Measurement, as the canvas spec's §7 did it, at 200 pages and 2,000 posts: the data's time and size, the time to rest, late frames while panning, the number of lines.

## Documentation

Guide, in `contentspiel-docs`: the Mind graph's page is rewritten (pages, the two new lines, the status looks and where their key is, the legend as filter, the list's four groups, "Not listed on any page" and what it means for someone with a partial read scope). Affected: the Pages page (a pointer) and the post-list block's page (where a post appears). In this repository: `docs/reference/cs-studio-shell-and-dashboard.md` (the Mind graph's part) and `CLAUDE.md` (the legend's counts in `reset()`; the graph reads rows, by decision); the roadmap gains step two and saved positions.

## Design answers folded in (2026-10-12)

The first two parts of the answers file:

1. A post type a page lists is a node of its own (12px hub, `cat-n`, a surface inner ring, label always shown, edges only to its pages, one legend entry "Post types"); a block with no filter points at the one "All posts" node (`--cs-dim`).
2. "+N more" opens the list beside the canvas with the left-out posts as rows "not in view"; a click adds the post and selects it; "Open in Posts →" at the bottom.
3. Depth 2 around a page adds grandparent, grandchildren and siblings to the listed posts; the cap of 20 plus "+N more" stays.
4. Post labels `--cs-dim` (ink when hovered or selected); the toggles replace the radios, all on, and no "Links in text" toggle (hidden, not disabled) until step two.

The third part ("The drawing, and third answers"), which replaces what F2, F3's first lines and the first answer's status looks said:

5. The correction: unpublished changes a DIM corner dot, a scheduled change a WARN corner dot, a scheduled record a WARN centre dot.
6. Ring types: a filled-type mark inside a 1.5px ring, the five looks unchanged; draft dashed on every mark.
7. G1, a retired type's hub; G2, the "+N more" pill; G3, the exact readings (the 4px centre dot, the 5px corner dot 1px in with its surface ring, the hub's inner ring, the Lists line's dash, the live ring post).
8. G4, the card's status chip; G5, the not-in-view row's accessible name and the list's error line; G6, the canvas's summary in three forms.
9. On the boards: in the local view a hub's faint lines to the posts it brings in; status not a filter, behind a "Status" link; "Show everything" not remembered after a reload.

And the owner's, 2026-10-12: the list's fourth group, "Post types".

## Open design questions

For the design system's owner, put to them by the controller; none holds the plan. The drawing (`Studio Mind Graph Pages.dc.html`) is looked at first for each: this text's author worked from the words alone.

1. **A row of the list's "Post types" group.** The owner decided the group; the designer's file gives no look for its rows. What is a row's mark (the hub as the canvas draws it, the type's dot, "All posts" in dim, a retired type's outline), what stands where a tag's row has its number, and in which order do the rows come? Until answered: the shape of a Tags row, the type's dot (`ContentTypeDotComponent`'s classes; "All posts" a dim dot), the number of connections, "All posts" first and then the registry's order.
2. **The hub's faint lines.** Read here as: in a page's local view each drawn post is joined to the type hub or "All posts" that brings it in, in place of a line from the page; a post a block lists by tag keeps its "Shares a tag" line to that tag and gets no second line; "+N more" hangs off the hub of the page's first list block; the faint lines are 1px `--cs-line` like the pill's and go with the "Lists" toggle. Is each of the four so on the board?
3. **A ring type's readings.** The inner mark is 4/7 of the mark's radius at every size (4 in 7 is the designer's); the 1.5px ring stays solid on a draft, whose inner mark is dashed; the corner dot sits on the outer ring's corner, not the inner mark's. And a type HUB of a ring type (slots 7 to 12) is filled with its hue like slots 1 to 6.
4. **The pill's width.** Fixed at 60 with any figure, or wider from four digits on?
5. **The summary beyond its three forms.** Nothing in view at all; the whole graph cut at the cap (is "Showing everything." still said?); whether "Showing everything." stands beside "Tags hidden."; a LINE kind switched off (it changes the number of connections and is not named).
6. **The status key's own name** for a screen reader ("Status key" here), and whether the key's five names stay "Live with changes" and "Live with a change scheduled" beside the chip's "Unpublished changes" and "Change scheduled".
7. **The not-in-view row's type name**: the type's label in lower case ("blog post"), and for a type that is retired its stored name.
