# Pages in the Mind graph, step one

**BUILT on branch `pages-in-graph`, 2026-10-13. THE TEXT BELOW IS THE SPEC AS APPROVED AND IS NOT CORRECTED: where the build left it, "As built" at the end says where and why, and holds the measurement. What the code does today is in `docs/reference/cs-studio-shell-and-dashboard.md`, "Mind graph".**

Date: 2026-10-12. Status: **approved by the owner on 2026-10-12** ("Yes go"), the design answers folded in; the plan is `docs/superpowers/plans/2026-10-12-pages-in-the-mind-graph.md`. What the owner confirmed with the approval is listed under "Approved" below. What is still open is at the end: two small points, neither of which holds the plan.

> **Revised again 2026-10-12: the fourth design answers (H1 to H7) are folded in.** They answered the seven questions this text had left open, and changed it in these places: "+N more" is one pill PER TARGET, each with its own count (§1, §3, §4, §7); a "Post types" row is a small copy of the hub with the number of the type's POSTS, "All posts" last (§7); a ring type's hub is a ring round a centre and the retired hub's ring is dashed (§4); the pill grows to fit, its figure grouped (§4); the summary's other forms (§6); the status key is a dialog in the chip's words (§6, §7); a retired type's row name (§7).
>
> **Revised 2026-10-12: the third design answers are folded in** ("The drawing, and third answers" of the answers file, which arrived after the approval), and one decision of the owner. What changed in this text:
> - the status looks: warn now means "scheduled" everywhere. Unpublished changes are a DIM corner dot, a scheduled change a WARN corner dot, a scheduled record a WARN centre dot (§4; this replaces F2);
> - a ring type is a filled-type mark inside a 1.5px ring, so the five looks are the same on every mark (this replaces F3's first lines); the exact readings of the dots, the hub's inner ring and the Lists line; a retired type's hub; the "+N more" pill (§4);
> - in a page's local view a hub draws faint lines to the posts it brings in, in place of a lists line from the page to each post (§1, §4, §7);
> - status is not a filter: a "Status" link in the legend opens the key (§6); the canvas's summary for a screen reader has three forms (§6);
> - the card's status chip names the second state; the not-in-view row's accessible name and the list's error line (§7, §8); "Show everything" is not remembered after a reload (decision 6);
> - the owner's decision: the list has a fourth group, "Post types" (§7). Its rows' look is an open design question.
>
> **The reference for anything these words leave open is the designer's drawing**, `Studio Mind Graph Pages.dc.html` in the "Content Spiel design system" project (eight boards, with a Theme tweak for light and dark). Where this text and the drawing differ, the drawing is asked first.

## Why

The Mind graph shows posts and tags. It cannot show where a post appears on the site, because pages are not in it, and nothing in CS Studio shows a post that no page lists. The owner decided that pages join the graph (roadmap, version 1, item 5). The look and the behaviour were put to the design system's owner on 2026-10-12 (`.superpowers/design-answers/2026-10-12-pages-in-mind-graph.md` in the main checkout); every size, token and wording below that is not marked as this spec's own is that answer's, copied, the follow-up answers of the same day (F1 to F6) and the third answers with the drawing (the correction, G1 to G6 and what the boards added) and the fourth answers (H1 to H7) included. Where a later answer replaces an earlier one, this text holds the later.

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
2. **The legend becomes controls.** Its type entries and line entries are checkboxes with counts, everything on by default. The status looks leave the legend's row: a "Status" link opens their key, a dialog. The three radios "Show connections: All / Related / Tags" are removed completely: the line toggles say the same and more (decision 8). There is no "Links in text" toggle in this step: it is not drawn, not even disabled.
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

The design system's owner has since answered what a row of that group looks like, and the six other points the third answers left open (the fourth answers, H1 to H7); this text holds them. Two small points remain, under "Still open".

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
- **In a page's local view only, a hub draws faint lines to the posts it brings in** (third answers, "Also added on the boards"; confirmed by H1): `{ kind: "brings", source: "type-<name>" | "all-posts", target: "post-<id>" }` for each post the view draws at depth 2 (§7), from the target of the first list block of the page that lists the post. Each drawn post joins the hub that brings it in, NOT the page; the page keeps its dotted Lists line to the hub. A post a block lists by TAG keeps only its "Shares a tag" line to that tag, which is its hub. (This replaces the first text's rule, this spec's own, that joined each listed post to the page by a lists line.) The whole graph has no such line: there a type node joins only pages.
- **"+N more" is ONE PILL PER TARGET** (H1): `more: [{ id: "more-<target>", count, page: "page-<id>", target }]`, one for each hub or tag a list block of the page points at that brings in more than the view draws, each counting only what that target brings in, and each hanging off its own target by a `brings` line. A page with two list blocks can have two pills. A post two blocks list is counted with the first that lists it, so the pills' counts add up to what the view leaves out. Not one pill on the first block's hub.

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
- `mind_graph/listed?page=<id>&target=<target>` (new, JSON, same rules): the readable posts that ONE TARGET of that page brings in and the local view left out, with the total; the rows of that target's "+N more" pill. Each row says which hub brings it in (`via`), so a row added to the canvas gets its line. `target` is only compared with the page's own targets: a junk one answers no rows.

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

**Ring types** (colour slots 7 to 12, and a retired type's grey ring with its stroke). A ring type is drawn as a filled-type mark inside a 1.5px ring in the type's colour, so all five looks carry over unchanged: the inner mark is filled when live, a dashed `--cs-meta` outline as a draft, a `--cs-dim` outline with the warn centre dot when scheduled. The inner mark is 4/7 of the outer radius at every size, rounded to the nearest 0.5px (live, at the smallest size: the ring at radius 7 with a filled radius-4 disk, 8px across); as a draft the outer ring stays solid and only the inner mark is dashed; the corner dot is on the outer ring, at the 45° point (H3). (This replaces F3's "status shows in the middle".)

**Post-type nodes.** A 12px filled circle (radius 6) in the type's `cat-n` colour with a `--cs-surface` inner ring 1.5px wide, its outer edge 1.5px inside the hub's radius; fixed size: a hub, not one more post. Label: the type's name, 12px sans `--cs-ink`, always shown, at the priority of the top-level pages. "All posts" is the same shape filled with `--cs-dim`, labelled "All posts". **The hub of a ring type** (slots 7 to 12) is NOT filled like slots 1 to 6: a 1.5px ring in the hue around a filled centre 6px across (H3). **A retired type's hub** (a type no longer registered that a block still names) is an outline circle in `--cs-dim`, 1.5px and DASHED (H3: so it stays apart from a ring type's hub), on surface, with a 4px dim centre dot, and "(retired)" at the end of its label: it and "All posts" differ by fill, not by shade.

**"+N more".** A pill 16px high that grows to fit its words: 8px of padding each side, never under 60px wide (H4). `--cs-surface` fill, a 1px `--cs-line-strong` border, "+92 more" inside it in 10px mono `--cs-dim`, the figure with a thousands separator ("+1,980 more"). It carries its words itself and has no label beside it. One per target (§1); each hangs off its hub or tag by a faint 1px `--cs-line` line.

The state is never worked out in the script or by comparing `published_at`. The builder asks `Publishing::State` for each record it has loaded: `status` and `changes?`, which cost no statement of their own once the pending copies are read, as the tree and the posts list ask them. `Builder::COLUMNS` gains `unpublished_changes_at`. `Publishing::State` has five states and the graph now has five looks.

**Lines.** Tree: solid 1px `--cs-line-strong`. Lists: dotted in `--cs-dim`, drawn 1.5px with round caps and a dash of 0.1 / 3.5, which gives dots 1.5px across, 3.6px apart. Related: solid 1.5px ink, as now. Shares a tag: dashed `--cs-meta`, as now. A hub's lines to the posts it brings in and to its "+N more" (a page's local view only): faint, solid 1px `--cs-line`; they follow the "Lists" toggle (H1). On selection only the node's own lines brighten; accent stays for the selection ring. Lines are drawn in batches, one path per style; a line that cannot cross the view is skipped, as today; below 40% zoom "Shares a tag" is not drawn (a drawing rule only: the toggle, the counts and a selection's neighbours do not change with the zoom).

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

- **Status is not a filter** (third answers). The five status looks are not in the legend's row and are no toggles: a "Status" link in the legend opens the key, **a dialog with the accessible name "Status key"** (H6), the five looks each with its name, drawn on a filled mark (a ring type's are the same looks, §4). The key uses THE CHIP'S WORDING, one set of words: "Live", "Draft", "Scheduled", "Live, unpublished changes" and "Live, change scheduled" (the date stands only on the chip, §7). It is CS Studio's one dialog (`Admin::Ui::DialogComponent`, the native modal `<dialog>`: Escape and its Close button close it, the focus cannot leave it while it is open and goes back to "Status"), a component of its own rendered outside the graph's element, so the graph's script writes nothing there and `reset()` has nothing to take back. (The third answers said "popover", the fourth "a dialog"; CS Studio has one kind of dialog and this is it.)
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

A kind with nothing in view is left out of the counts; "N of M posts" and the "more" sentence are said only around a page that lists more than the view draws, and "more" counts every pill in view together. Until the data has come the canvas is named "Mind graph". The other forms, the designer's (H5):

- nothing in view: "Mind graph: nothing to show. All types are hidden." when every kind is switched off, "Mind graph: nothing to show. No pages, posts or tags yet." when there is nothing;
- "Showing everything. Tags hidden.": both, in that order ("everything" means no cap, not no filters);
- a kind of LINE switched off is named the same way: "Shares-a-tag lines hidden.";
- at the cap, never "Showing everything.": the view the 3,000-line rule opened says "Showing the area around Home." and the full counts, "The site has 212 pages, 2,040 posts and 64 tags." (what the viewer can read of the site; the local view's answer carries those three counts).

## 7. Search, the list, the card, the local view

**Search.** Grouped Pages / Posts / Tags with the type's marker; a page's path in 11px mono under its title. Three groups, not the list's four: a search row opens its row's local view, and a post type has none (a focus is a page, a post or a tag).

**The list.** Four groups (the fourth by the owner's decision of 2026-10-12). "Pages · N" comes first, in tree order with indents by depth, not by link count; then Posts and Tags as today; then "Post types · N": a row for each post-type node and for "All posts", so each has a keyboard path to its card. A row of that group is the designer's (H2): its mark is a smaller copy of the hub as drawn, 10px with the inner ring, not the type's dot ("All posts" filled dim; a retired type a dim outline with a centre dot); its number, 11px mono `--cs-meta` where a tag's row has its number, is the count of POSTS of that type on the site ("All posts" shows the site's total), as far as the viewer can read them; the order is the types in their colour-slot order (the order in Settings), then the retired types, then "All posts" last. Above the groups a checkbox "Not listed on any page": while on, the list shows the `unlisted` read's rows in place of the groups, with the total, and the canvas is left as it is. A read that fails says so in the list, not in a toast: "The list couldn't be loaded." with a small "Try again" button.

**Rows that are not drawn.** A row for a post the canvas does not draw (past the cap, an unlisted post, a post behind a "+N more") is marked "not in view" in 11px `text-meta`. Its accessible name is the designer's: "Small sites, long lives, blog post, not in view. Activate to add it to the graph.", with the post TYPE's name, not just "post": the type's label in lower case, and for a post of a retired type its stored name in lower case followed by "retired type" ("talk, retired type") (H7). Clicking one adds the post to the canvas and selects it: the row carries the post's node payload, so no request is made, and in a page's local view the post gets the line of the hub that brings it in (the row's `via`, the pill's own target: a faint line from a type hub or "All posts", a "Shares a tag" line to a tag).

**A page's card.** The path, the status chip, "4 child pages · lists 112 posts", the open notes under the title as on a post's card (`card_notes.js`, with a `data-page-notes-url` template beside the post's), then "Open page" (primary), "Focus", "Pin" / "Unpin". Enter on a selected page opens it, as for a post.

**The status chip on a card** (a page's and a post's; G4, H6) keeps its three dots and adds the second state after the label, in the status key's own words, one set: "Live, unpublished changes" and "Live, change scheduled 14 Oct", the date only here. To the eye it is G4's row: "● Live · unpublished changes" with no second dot, "● Live · ● change scheduled 14 Oct" with a warn dot before the second part; a screen reader is given H6's sentence. The date is the day the change comes into force, in CS Studio's short date format (`admin.short`), put on by the controller from the data's `change_at`.

**The local view around a page.** Depth 1: its parent, its children, and the tags or post type its blocks list. Depth 2 adds, besides the posts it lists, one more step along the tree: the grandparent, the grandchildren and the siblings (the parent's other children), each with its tree line. The posts it lists are the 20 most recent (by `published_at`, a draft by `updated_at`), each joined by a faint line to the hub that brings it in (§1), plus a "+N more" pill for each target that brings in more, hanging off its hub or tag the same way (§1). A "+N more" opens the list beside the canvas filtered to the posts ITS target left out, which the list shows as rows "not in view" (above), with "Open in Posts →" at the bottom of the filtered list. Those rows come from a read like `unlisted` (`mind_graph/listed?page=&target=`, same scope and trash rules, newest first, the first 200 with the total); "Open in Posts →" is a link the controller builds to the Posts screen filtered as far as its filters go by the type and tag of the block that points at that target. "The pages and posts that link to it" of the design answer's depth 1 are step two. Around a post or a tag the walk is as today and now also steps along a lists line, so a post's local view at depth 2 reaches the pages that list one of its tags.

## 8. Strings

All in `config/locales/admin/`: the legend's in `mind_graph_screen.en.yml`, the view's and the script's in `mind_graph.en.yml`, every script key written out in the view's `data-messages`. The design answer's words are marked (D); the others are this spec's.

- Legend: "Pages", "Posts", "Tags", "Post types" (D); "Tree", "Lists", "Related", "Shares a tag" (D); the link "Status" (D); the key's name "Status key" (D, H6) and in it "Live", "Draft", "Scheduled", "Live, unpublished changes", "Live, change scheduled" (D, H6: the chip's wording, which replaces "Live with changes" and "Live with a change scheduled" everywhere); group names "Show" and "Lines"; a toggle's name "%{name}, %{count}". Removed: "Draft or scheduled", "Related post", and the view's `filter.*`.
- View: intro "How your pages, posts and tags connect. Scroll or pinch to zoom, drag to move."; "No pages or posts yet."; search label and placeholder "Find a page, post or tag"; canvas label "Mind graph" (the first words of the summary); list label "Pages, posts, tags and post types in this graph"; focus bar "Around the page “%{title}”", "Show everything" (D).
- Script, the summary (D: G6, H5): "Mind graph: %{kinds}, %{connections}." and "Showing everything."; "Mind graph around %{title}, depth %{depth}: %{kinds}."; "%{count} more are in the list."; "Tags hidden."; "Shares-a-tag lines hidden."; "Mind graph: nothing to show.", "All types are hidden.", "No pages, posts or tags yet."; "Showing the area around Home." and "The site has %{kinds}."; the counts "%{count} pages", "%{count} post types", "%{count} posts", "%{count} of %{total} posts", "%{count} tags", "%{count} connections"; a pair "%{first} and %{last}" and a series "%{first}, %{rest}" (no comma before "and", as the designer writes it). This spec's own, by the designer's pattern: "Pages hidden.", "Posts hidden.", "Post types hidden."; "Tree lines hidden.", "Lists lines hidden.", "Related lines hidden."; the singulars of the counts and "%{count} more is in the list.".
- Script, the rest: search groups "Pages", "Posts", "Tags" (D), "No page, post or tag matches."; list "Pages · %{count}", "Post types · %{count}", "Not listed on any page" (D), "%{title}: page, %{count} connections. Shows it in the graph." and "%{title}: post type, %{count} posts. Shows it in the graph." (one / other), "%{title}, %{type} post, not in view. Activate to add it to the graph." (D, G5) and "%{title}, %{type}, retired type, not in view. Activate to add it to the graph." (D, H7, in the first's frame), "The list couldn't be loaded." and "Try again" (D, G5); card "Open page" (D), "%{count} child page" / "%{count} child pages" (D), "lists %{count} post" / "lists %{count} posts" (D), the chip "Live, unpublished changes" and "Live, change scheduled %{date}" (D, H6) with, for the eye, the second parts "unpublished changes" and "change scheduled %{date}" after the "·" (D, G4); "+%{count} more" (D), "not in view" (D), "Open in Posts →" (D); the node name "All posts" (D), with its card line "%{count} posts"; a retired type's label "%{name} (retired)" (D, G1); notice "This site has %{figure} connections, so the graph opens around Home."

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
- **Two pills, and a post two blocks list.** A page whose blocks overlap (a tag's block and a type's that both list a post) counts that post with the first block: the second pill is smaller than its block's own listing, and "Open in Posts" from it shows more posts than the pill counted.
- **Every system test of the graph reads ids**, and each waits about five seconds per layout; the suite's time grows with every new one.

## Testing

- `PostGraph::Listings`: the targets of a block (tag, type, a name no tag has, a block in a section), and parity with `BlockTypes::PostList.listed_posts`.
- `PostGraph::Global` and `Local`: pages, tree and lists lines; a page outside the scope is no node and takes its lines with it; the typed ids; the statement count at two sizes with `capture_sql`; the local view around a page at both depths, with the cap of 20, a "+N more" pill per target with its own count, and each drawn post and each pill joined to the hub that brings it in and not to the page; no such line in the whole graph; the `open` answer above the threshold and never with `everything=1`.
- `PostGraph::Focus`: `page=`, the order of the three parameters, the 404s.
- `PostGraph::Search` and the unlisted read: scope, trash, order, the limit.
- Status: the builder's `status` and `changes` are `Publishing::State`'s for every combination the state's own test lists; a source guard that nothing under `app/queries/post_graph/` and `app/javascript/mind_graph/` compares `published_at`.
- `test/integration/trash_visibility_test.rb`: the page, `data`, `search` and `unlisted`, for a trashed page and a trashed post.
- The legend component: the toggles (two groups, all on, no "Links in text"), their names, no type the viewer cannot read; the "Status" button; the status key, a dialog named "Status key" with five looks in the chip's words and no control.
- Type nodes: a type node joins only pages; one "All posts" node however many pages list everything; a block with a tag, a type and neither; "Post types" off hides them and their lines; `listed` rows and the click that adds a post.
- Browser: each of the five status looks read from the canvas's pixels for a page, a filled post and a ring post, a draft dashed on all three, warn for both scheduled looks and dim for unpublished changes; a ring type's hub, a retired type's dashed hub and a pill that grows to fit; each toggle hides its kind, leaves the counts, and changes the list; the summary's three forms; the "Status" key by keyboard (opened as a dialog, read, closed with Escape, the focus back on the link); two pills on one page, each with its own rows; Home is at the centre at rest and has no pin; the Tab order; `reset()` after Back (counts gone, checkboxes kept); a page's card, its chip in the two new states and its links (`click_frame_link`); the list's four groups; the unlisted filter, a row not in view by its accessible name, and the error line with "Try again"; "Show everything" gone from the address once drawn.
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

The fourth part ("Fourth answers", H1 to H7), on the seven points the third left open:

10. H1: each drawn post joins its hub, not the page; a tag-listed post keeps only its tag line; ONE PILL PER TARGET; the faint lines follow the Lists toggle.
11. H2: a "Post types" row: a 10px copy of the hub, the number of the type's posts, colour-slot order, retired types, "All posts" last.
12. H3: a ring type's inner mark at 4/7 rounded to 0.5px, a solid outer ring on a draft, the corner dot on the outer ring; a ring type's HUB a ring round a filled centre; the retired hub's ring dashed.
13. H4: the pill grows to fit, 8px each side, at least 60px, with a thousands separator.
14. H5: the summary's remaining forms.
15. H6: the key is a dialog named "Status key" and uses the chip's wording.
16. H7: the not-in-view row's type name, and a retired type's.

## Still open

Two small points, for the controller to put to the design system's owner; neither holds the plan, which builds the plain reading of each and reports it.

1. **A type name "capitalised by design".** H7: "a name capitalised by design (a brand) stays as stored; only Studio's own type labels are lowered." Nothing in the data says which label is a brand, so every type's label is lowered as the messages' language lowers it. Is a mark on the type's definition wanted for it?
2. **The whole graph cut at the 2,000 posts.** H5's "at the cap" is the view the 3,000-line rule opens around Home. A site so large that `everything=1` is itself cut at 2,000 posts is neither that view nor "everything": there the summary says the notice's own sentence, "Showing the 2,000 best-connected of 2,040 posts.", where "Showing everything." would stand. And two pairs of words that are the designer's in substance and this text's in form: the chip is drawn as G4 wrote it ("Live · unpublished changes", dots and all) and read out as H6 wrote it ("Live, unpublished changes"); and the key is CS Studio's modal dialog where the third answers said "popover".

## As built

Built on 2026-10-13 on the branch `pages-in-graph`, in nine tasks by the plan, each reviewed. This section is the only part of this file written after the approval. It says what was measured, what the measurement decided, and every place the build left the text above, each with its reason. The description of the screen as it is lives in `docs/reference/cs-studio-shell-and-dashboard.md`.

### The measurement (2026-10-13)

**The site.** 204 pages and 2,005 posts in a database of its own, built through the services by `script/dev/mind_graph_posts.rb 2000` (the canvas spec's site: 1,933 connected posts and 72 with no connection, 3,162 related-post links, 2,770 tag links, 62 tags) and `script/dev/mind_graph_pages.rb 200` (Home, eight sections under it, every later page under one of the first sixty; every third page with a post-list block, by one of the tags, by the "blog" type or by nothing in turn), on top of the seeds' five pages: 70 list blocks. Two more shapes were made of it inside a transaction that was rolled back, because the review of the listings named them as its worst cases: **every page lists everything** (an unfiltered block added to each of the 204 pages: 274 blocks) and **every page has a filter of its own** (a block added to each page with a pair of tag and type that no other page has: 274 blocks, 204 distinct filters beside the site's own).

**The server's reads.** Median and range of eleven calls. "Before" is the code as the eighth task left it; "now" is with the fix under "What the measurement changed".

| Read | The site | Every page lists everything | Every page its own filter |
|---|---|---|---|
| The whole graph (`everything`), time | 144 ms (139 to 148); before 313 | 147 ms (127 to 158); before 580 | 393 ms (389 to 402); before 885 |
| The whole graph, size | 844 kB; 55 kB gzipped | 855 kB; 55 kB | 855 kB; 56 kB |
| The whole graph, what it holds | 2,202 nodes (204 pages, 1,933 posts, 61 tags, 4 post types) and 6,204 lines (3,162 related, 2,769 shared tags, 203 tree, 70 lists) | 6,385 lines (251 lists) | 6,408 lines (274 lists) |
| The whole graph, statements | 13 | 13 | 13 |
| The answer that says where to open (the default) | 49 ms (43 to 52); 6 statements; 30 bytes | 53 ms | 55 ms |
| Of both: the site loaded (`PostGraph::Site`) | 36 ms; 5 statements | 39 ms | 40 ms |
| Of the whole graph: the listings worked through for every page | 42 ms; before 176 | 48 ms; before 476 | 286 ms; before 777 |
| Around Home, depth 1 | 43 ms (34 to 44); 8 statements; 4 kB (13 pages, 1 hub) | 46 ms | 63 ms; 9 statements |
| Around Home, depth 2 | 58 ms (48 to 80), before 193; 12 statements; 34 kB (84 pages, 20 posts, 1 hub, 114 lines, one pill of 1,985) | 64 ms; before 495 | 303 ms, before 801; 13 statements |
| Around the page that lists most, depth 1 / depth 2 | 42 ms / 54 ms (before 190) | 46 ms / 59 ms | 49 ms / 298 ms |
| Search: "a", "gr" | 16 ms (14 to 19), 14 ms; 6 statements; ten rows of each kind | 16 ms | 13 ms |
| Search: "Graph page 12"; a long text nothing matches (so 7 to 23 ms over the four texts and three shapes) | 20 ms (7 to 21); 7 ms (6 to 20), 5 statements | 22 ms; 21 ms | 23 ms; 22 ms |
| The list: `unlisted` | 42 ms (39 to 44), before 177; 5 statements; no row (Home lists everything on this site) | 45 ms; before 479 | 281 ms; before 774 |
| The list: `listed` (the page that lists most, its "All posts" pill) | 57 ms (55 to 58), before 192; 8 statements; 200 rows of 1,985; 49 kB | 58 ms; before 494 | 296 ms; before 787 |

**The browser, on the same site.**

| What | Figure |
|---|---|
| Lines drawn with everything shown | 6,204, on 2,202 nodes |
| Whether the site opens around Home | Yes: 6,204 lines against the 3,000 of the rule |
| Navigation to the first frame with nodes, the whole graph | 78 to 138 ms (four loads) |
| Navigation to settled, the whole graph | 3.36 s (3.31 to 3.42; four loads) |
| Navigation to settled, the view around Home the site opens in (14 nodes) | 6.4 to 6.5 s (four loads), the first frame after 30 to 68 ms: 300 ticks at one a frame, a tick every 21.5 ms (95th percentile 23.5, worst 24.4) |
| The same at depth 2 (106 nodes) | 6.5 to 6.6 s |
| Frames while panning, the whole graph in view (240 frames) | median 16.7 ms, worst 16.8: none over 17.5 ms, none over 34 ms |
| Frames while panning at the largest zoom (4.0; 240 frames) | median 16.7 ms, worst 16.8: none late |
| Frames while zooming (60 wheel events in, 60 out) | median 16.7 ms, worst 16.8: none late |
| The frame callback's own time | up to 1.7 ms with the whole graph in view (95th percentile 1.5); up to 0.7 ms at the largest zoom; up to 12.8 ms on a frame in which the zoom changed (the label rule runs again) |
| The node under the pointer: a pointer move's handler, 300 moves across the canvas | under 0.1 ms, worst 0.3 ms |
| A legend toggle, until its handler returns | 28 to 33 ms (Tags, Tree, Shares a tag, each off and on three times: the list's 2,202 rows are drawn again); Posts off 11 to 13 ms, on again 29 ms. Nothing is laid out, so there is no "until at rest" |
| The list's row marks | 208 canvases (204 pages, 4 hubs) painted in 1.4 to 1.8 ms (seven passes) |

**How each was taken.**
- **The machine:** an Apple M4 Pro (12 cores, 48 GB), macOS 27.0.1, Postgres 17 in Docker; one-minute load between 2 and 3.5 at each run.
- **The server's reads:** `bin/rails runner` in the development environment against the measurement's own database (`DATABASE_URL`), the query cache switched off (a runner is wrapped in the executor, which caches; the first run of this measurement had every later call answered from it), `Current` reset and the garbage collected before each call. Timed: the query object's `call` (`PostGraph::Global`, `Local` with its `Focus.find`, `Search`, `Rows`), not a request: no session, no controller, no JSON written to a socket. The size is `to_json` of the answer and the same through gzip. Statements are `sql.active_record` events without the schema's and the transaction's; the figures above leave out the settings row every request reads once, and for a local view the focus's own lookup. **These are NOT the canvas spec's endpoint figures taken again, and are not to be set beside them as if they were**: those were eleven `curl` requests against a running development server, which is what the plan asked for here too; no server could be started for this measurement, so no request was made, and what a request adds (the session, the user, the controller, writing 844 kB to a socket) is not in these times. The output of the run was not kept (the method is the probe script in the build's workspace, the database is dropped, and the "before" column needs the code as the eighth task left it), so the table stands as it was written down.
- **The browser:** the system-test browser (Google Chrome 155, headless, driven by Cuprite), window 1400 by 1400 (the suite's; the canvas spec's and the plan's was 1440 by 900), the canvas 810 by 1165 CSS pixels, device pixel ratio 1. The browser's raw figures are kept in the build's workspace; the tick intervals of the unfold were read off one run and not kept. The endpoint's saved answers for the site were replayed into the page by a `fetch` stub (the canvas spec's second table was taken the same way), so "navigation" is a click on the sidebar's link to the frame the event is seen in and leaves out the endpoint's own time. Headless figures say whether a frame was late, not what a person sees on a screen.
- **Navigation:** `performance.now()` in a frame loop: the first frame the app drew after the data came, and the frame on which `data-settled` appeared.
- **Frames:** the differences between successive `requestAnimationFrame` timestamps over a scripted drag on empty canvas, one pointer event a frame, and over wheel events, one a frame. The frame callback's time is `requestAnimationFrame` wrapped before the app loaded; with one event dispatched per frame half the callbacks are the measurement's own, which is why the median says nothing and the upper figures are given.
- **The toggle and the pointer:** `performance.now()` around the checkbox's `click()` and around `dispatchEvent` of a `pointermove`, whose handlers run before they return.
- The scripts that took it are not in the repository (a runner script and a throwaway system test); the two that build the site are.

### What the measurement decided

1. **Saved positions: "Should" on the roadmap, with the figure.** Decision 7's bar was three seconds to rest with everything shown; it is 3.36 s here (2.8 s for the posts alone in the canvas spec), before the endpoint's own time. That is 12% over the bar, from another window than the plan's and with the answers replayed, and is to be taken with that: it says the wait is about three seconds, not that it is certainly more. Nothing is built: the site of this size opens around Home, where the wait does not occur until "Show everything" is pressed.
2. **The 3,000-line rule IS the normal case at this size**, as "Risks" feared: 6,204 lines, and the posts' own lines (5,931) are twice the threshold before a page is counted. A site of 200 pages and 2,000 well-connected posts always opens around Home. The threshold was not moved; whether it should count the lines differently (for example not the shared tags', which are not drawn below 40% zoom anyway) is the owner's and the designer's question, on the roadmap.
3. **No quadtree** (decision 12): no frame was late at 2,202 nodes, the hit test's handler is 0.3 ms at worst, and the per-node dash calls the review of the canvas expected to cost under a millisecond do (the whole frame is 1.7 ms).
4. **The tree's spring was not tuned** (distance 40, strength 0.9 stay; no other value was tried). The plan's reason to tune was a subtree torn apart or a page drawn into a tag's cluster, and neither was seen: with everything shown the pages are one cluster beside the posts, Home at the centre with its sections round it, a page of 56 children a dense clump. What IS wrong in that picture is the designer's: at the zoom that fits 2,202 nodes (35%) the marks, which keep their size on screen, lie on one another, the pages as much as the posts.
5. **The unfold of a small graph takes 6.2 s here, not "about five seconds"**: 300 ticks at one a frame, and a tick came every 21.5 ms where the canvas spec measured 18. The code is unchanged; the worker's 16 ms timer comes out later in this browser. It is the motion the owner asked for and the view is usable from its first frame, so nothing was changed; it is on the roadmap as a figure to look at again, since the view a large site opens in is exactly such a small graph.

### What the measurement changed

**What a page lists is worked out once, not per page and per post** (`PostGraph::Listings`). As built by the plan, every page's posts were sorted for that page by a two-part key, and the listing's criteria were asked once per distinct filter AND post. No statement shows either, so the statement tests were green, and every read that loads the site paid it: 0.58 s for the graph's data where every page lists everything (200 sorts of 2,000 posts) and 0.89 s where every page has its own filter (400,000 calls of `matches?`), and as much again for a local view at depth 2 and for each of the list's reads. The bar was the canvas spec's: one second for the endpoint, and a read that only fills a list should be far below it. Now the posts are put in order once, the criteria are asked once per distinct filter and distinct kind of post (its stored type and which of the named tags it carries, which is all the criteria read), every post some page lists is the union over the distinct filters, and pages whose blocks say the same share one frozen list. The same shapes: 0.15 s and 0.39 s. Held by two counting tests in `test/queries/post_graph/listings_test.rb` (calls of the criteria at two sizes; the identity of a shared list); no test asserts a time. What is left, 0.29 s of Ruby where 200 pages have 200 different filters over posts of 836 kinds, is on the roadmap.

### Where the build left the text, and why

**The legend is a filter that moves nothing (§5, last point; §6).** §5 hands a toggle "to the worker as today's filter is: the visible nodes and edges only". As first built that is what happened, and every toggle re-ran the layout at alpha 0.8: with eight toggles, four of them of lines alone, nodes the toggle did not touch moved and could leave the view, and "comes back where it was" held only as "has a position". The ruling on the review: a toggle is a filter on what is DRAWN. The layout is computed once over everything the data holds; a toggle sends the worker nothing and moves no node; the worker's `filter` message is removed. Three things follow that the text does not say: a toggle touches no pin (a hidden pinned node stays held and counted, where the radios forgot it), `data-settled` and the camera stay through a toggle, and a cluster does not close up when what held it apart is hidden. The last is the price and is on the designer's list.

**Which toggles a viewer gets (§2, §6).** The text gives a viewer the toggles of "the kinds … the viewer can read something of". A tag needs either right: someone who reads pages and no post is shown the tags their pages list, so they get "Tags" with its swatch. One rule, `PostGraph::Kinds`. And a kind is hidden only by a toggle that is switched off, never by a toggle the viewer has none of.

**The swatches are canvases, not `.mg-*` classes (§4, last sentence).** A swatch, and a PAGE's and a POST TYPE's mark in a list row, a search result and a card, are small canvases drawn by the graph's own renderer from a scene of one node or one line, so the key cannot drift from the canvas. Every `.mg-*` rule left the stylesheet. A row's mark in the "Post types" group is therefore the hub itself at 10/12, not a CSS copy; a page's is its card at 10/14, always in the live look (a row's mark says the kind, not the state). A post's dot and a tag's square in a row stay CS Studio's own marks: a list can hold two thousand posts. One more controller file exists for it (`admin--mind-graph--swatches`), against the plan's "no controller file is added": the key is outside the graph's element.

**A large site opens around Home without navigating (decision 6, §3, §8).** The text has the script VISIT Home's local view with `replace`, the focus bar offer "Show everything" as `?everything=1`, and the script take that parameter out of the address afterwards through Turbo's history. Built: nothing navigates and the address is never touched. The data's `open` answer makes the script read Home's local view INTO THE SAME PAGE (`data-open-url`) and show a bar of its own, with "Show everything" as a real button that reads `data-everything-url` into the same page. `everything=1` is a parameter of the data alone; the page takes none, so "not remembered after a reload" needs no history code. **Back differs from the text**: the text says Back restores what was on the screen; here `reset()` takes the choice back, so Back opens around Home again, as a reload does. The opened view is at depth 1 and has no depth switch (the text's bar was the ordinary focus bar); a page's card's "Focus" leads to the ordinary local view. The notice's figure reaches the bar from the data (`data-opened-lines`), never from the address. And one case the text does not name: over the threshold with no Home the viewer reads, the whole graph is answered, since there is nowhere to open.

**The focus rests at the centre of a local view (§5).** The text holds Home at the centre "while the layout runs". Built: Home in the whole graph, THE FOCUS in a local view (a page's, a post's and a tag's alike), where Home is a page like any other. As first built Home was held in every view that contained it and the focus hung off-centre. Holding a post's or a tag's focus is new: before this build nothing held it. A released anchor EASES back to the centre (the text says "puts it back"). The spring's and the ease's figures are values the page hands the worker (`mind_graph/layout_parameters.js`), not constants in it, so that a test can lower them.

**A mark's size is its outer size (§4).** The text gives sizes and outline widths and not where a stroke lies. As first built strokes were centred on the edge, so every outlined mark was 1.5px larger than its filled twin. Built: an outline is traced inside the mark's edge, and a draft page is 14 by 10. Left as they were, being older than the rule: a live filled post's own outline in its hue, and a tag's square.

**Readings of the look, each behind a named constant and none tuned by eye (§4).** "Dashed" is a dash of 3 and a gap of 2.5, the dash a draft had before. A ring type's hub's "filled centre 6px across" is read as 6px ACROSS (radius 3). The corner dot of a ring type is 1px inside the outer ring on the 45 degree line, not on the ring. "A fixed bonus" for a page over a post with equal links is half a link. The pin and the notes badge on a card and on the pill stand on the box's own top corners (the answers place them only on dots), and a ring follows its mark: a box for a card, a pill's shape for the pill. A selected tag's label is mono semibold (the first build drew it sans; "tags keep mono"). The status key shows the five looks on a post's dot in ink. A page's indent in the list is 12px a level, a pill's row 16px.

**Hit testing (decision 12).** Still a linear scan, as decided. Two things changed that the text does not ask for: a page's card and the pill are pressed ON THE BOX, and a press inside a drawn mark selects that mark whatever nearer centre reaches the point with its slack (a pill is 60 wide or more, and a post resting against it took presses on its words).

**The data (§1).** `changes` is `nil`, `"unpublished"` or `"scheduled"`, not a boolean (`changes?`, §4): with `status` it names the fifth state, which a boolean could not, and `Publishing::State.of` takes `pending_at:`. A search row and a list row carry `record_id` beside the typed `id`; a post's search row carries `colour_index`. A type carries `label` and `degree`; a pill `page` and `target`. A post's row inside the queries is `[id, content_type, recency, updated_at]`, where the text has `published_at`: the time is turned into a number on the line that loads it, so that the guard which refuses every mention of the column cannot be walked round by a place in an array. "A page's first list block" is the first as a person READS the page (`BlockOutline`), where the first build took the first by id. "All posts" counts EVERY readable post, one of a retired type included (H2's "the site total"), where the text says "of all types": it is then not what a block with no filter lists. The site's tag count in a local view is the tags a readable post carries OR a readable page lists. A tag that only a page lists is found by the search and is a focus.

**The statement counts (§1, "The cost").** Thirteen for the whole graph is a CEILING, not a figure: twelve where no list block names a tag, fewer where there is no page or no post, one more for a viewer who is not an owner (their grants). The text's "a local view pays the same fixed part; its walk stays three statements per depth level" holds around a post or a tag; **around a page the walk asks nothing** (it is the site's rows), so nine at depth 1 and thirteen at depth 2. The `open` answer costs six. A pill's rows at most eight and the unlisted posts nine (one more since the review of the eighth task: the relations that touch its rows, so that each row says whether its post has no connection and the notice stays exact at the cap), the search six.

**A focus (§2, §3).** An id is decimal digits only (`1_0`, a sign and spaces name nothing, as a prefixed form does). A focus that went between the request's finding it and the site's being loaded is not found, whatever its kind, before the graph is built. `listed` for a page that went answers 404, and for a junk or unlisted `target` an empty answer (the text says "answers no rows"; a 404 would hide nothing more).

**"+N more" (§4, §7).** Built as the text has it, one pill per target, with what the text does not have. **Each pill has a row in the list** (under the row of what it hangs off, in the pill's own words, named whole) and its rows have a heading with **"Back to the list"**, with Escape in the rows as the same way back: the plan said "+N more has no row", which left a keyboard and a screen reader no way to the rows the summary tells them of, and nothing on screen said how to get the four groups back. **After a row is added the figures are true**: the pill counts one fewer and goes at none, the summary and the notice follow, from one source. **With "Posts" switched off** a not-in-view row's press switches it back on first, since the row says "Activate to add it to the graph". A post added from the list has no "N related · N tags" line on its card: the row was read with no line counted. In a page's local view a post a block lists by TAG has no faint line (its "Shares a tag" line to that tag is the line), as the text says; a row added from a pill gets its hub's line through `via`.

**The card (§7).** The chip's second part is capitalised, as G4 has it ("Unpublished changes", "Change scheduled 14 Oct"), where the text writes it in lower case. A chip of two states stands in a row of its own under the address: it is 217 pixels wide in English on a 240-pixel card. A post type's card says "Post type" as its kind word, also for "All posts". The note field on a page's card says "Write a note on this page".

**The status key (§6).** It is CS Studio's modal dialog, as H6 and the text say (the third answers said "popover"), 420 pixels wide, with its swatches drawn by the renderer.

**The summary (§6).** As the text has it, with one form more: with nothing drawn because every post is unconnected, neither of the designer's two "nothing to show" sentences is true, and it says the notice's own, "Mind graph: nothing to show. 2 posts have no connections yet." "All types are hidden." is said when every toggle the VIEWER HAS is off. At the 2,000-post cap of the whole graph it says the notice's cap sentence in place of "Showing everything." ("Still open", 2: still open). The canvas is named "Mind graph" before its data has come, as §6 says.

**The list (§7).** The Pages group is nested lists (a page's row inside its parent's item), so a screen reader hears the level; the text asks only for indents. A read of the list is given up after fifteen seconds like the graph's own, and the rows' region is `aria-busy` while one is out; a failed read's line stays through a toggle. The heading of a read's rows says the whole total over at most 200 rows ("Posts · 431").

**Strings (§8).** Every designer's sentence is in the locale files verbatim. The words nobody gave are listed for the designer with their keys (the build's `designer-questions.md`, "Wording nobody designed"): among them the three other "… hidden." sentences and the three other "… lines hidden.", the singular of "more", the two group names "Show" and "Lines", "Post types · %{count}" and the type rows' names, the opened view's sentence and its button's name, the pill's row, "More from %{target} · %{count}" and "Back to the list". The text's focus-bar "Show everything" is the opened view's button.

**Decision 8.** "A new visit starts from the defaults": every toggle carries `autocomplete="off"`, since Firefox puts a form's state back on a reload.

**Testing.** The text asks for each of the five looks read from the canvas's pixels on three marks, a ring type's hub, a retired hub and a pill that grows. Built: every mark, size, dash and theme key is held against a RECORDING context in the module tests (one test walks five marks by five states against a second copy of the table and asserts the 25 drawings differ), and pixels are read in the browser for a few looks only. The recording context is the stronger check for sizes and dashes. "'Show everything' gone from the address once drawn" has no test: it is never in the address. Two rules the text does not have, from tests that broke: no test pins a measured layout figure, and no script call waits more than about two seconds (the worker's parameters are lowered by a value instead). And two findings of the reviews about tests of rights: twice an assertion held nothing because its viewer could read everything; the tests that hold the scope now use a real partial scope and search the whole answer.

**What was cleaned up with the last task, beyond the text.** The order of a page's children is one value, `TreeOrder`, asked by the public branch, the Pages screen's tree, the New page dialog and the graph: the key was written four times, the fourth by this build. The worker's unused `filter` message is gone.

### Still open after the build

The two points of "Still open" above stand as they were (a type name "capitalised by design"; the summary at the 2,000-post cap). The design points the build raised, each with the screenshot that shows it and the reading that was built meanwhile, are one list for the design system's owner (`designer-questions.md` in the build's workspace, not in this repository). What the build left to do is in `docs/roadmap.md`, under "Known gaps", "Pages in the Mind graph".

