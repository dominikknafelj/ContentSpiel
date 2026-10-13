# Pages in the Mind graph, step one — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pages join the Mind graph as nodes, with tree lines and "lists" lines to the tag, the post type or "All posts" a page's post-list blocks filter by; every node shows one of five publishing looks; the legend becomes the filter, with the status key behind a "Status" link; search, the list (four groups: Pages, Posts, Tags, Post types), the card and the local view know pages.

**Architecture:** The `PostGraph` queries keep their name and gain one loader, `PostGraph::Site` (the readable posts, tag links and pages, and `PostGraph::Listings`, which works out in Ruby which page lists what), so the global view costs thirteen statements whatever the size. `PostGraph::Builder` is split into `plan` (which lines, no statement: what the 3,000-line rule counts) and `build` (the nodes). In the browser every node has a typed id (`post-12`), the marks move into `mind_graph/marks.js`, what is shown is decided by one pure function in `mind_graph/graph_data.js` from the legend's checkboxes, and the layout worker reads a line's kind and holds Home at the centre.

**Tech Stack:** Rails 8.1, Postgres (jsonb), Minitest + fixtures, ViewComponent, Stimulus via importmap (no npm), a 2D canvas, d3-force in a module Web Worker, Capybara on Cuprite.

**Spec:** `docs/superpowers/specs/2026-10-12-pages-in-the-mind-graph-design.md` (approved 2026-10-12, revised the same day). Every look value is the design answer's: `/Users/dknafelj/src/ContentSpiel/.superpowers/design-answers/2026-10-12-pages-in-mind-graph.md` (read-only, in the main checkout; binding). Read all three of its parts: **the third, "The drawing, and third answers", replaces what F2, F3's first lines and the first answer's status looks said**, and this plan holds the third part's values. The designer's drawing, `Studio Mind Graph Pages.dc.html` in the "Content Spiel design system" project, is the reference for anything the words leave open; an implementer does not open it but asks the controller, who does.

**Revised again 2026-10-12** for the fourth design answers (H1 to H7), which answered the seven questions the third left open: a "+N more" pill PER TARGET, each with its own count and its own rows (Tasks 2, 3, 4, 5, 6, 8); a "Post types" row's mark, number and order (Tasks 3, 7); a ring type's hub and a retired hub's dashed ring (Task 5); a pill that grows to fit, with a grouped figure (Task 5); the summary's remaining forms (Task 6, and the site's counts in Task 6's step for `Local`); the status key as a dialog in the chip's words (Tasks 6, 8); a retired type's row name (Task 7).

**Revised 2026-10-12** for the third design answers and the owner's decision of a fourth list group. What moved: the status looks (warn means "scheduled": Tasks 5, 6, 8); ring types, the hub's ring, a retired type's hub, the "+N more" pill and the Lists line's dash (Task 5); a hub's faint lines in a page's local view, in place of a lists line from the page to each post (Tasks 2, 3, 4, 5, 7, 8); the scheduled change's date in the data (Task 3) and on the card's chip (Task 8); the "Status" popover and the summary's three forms (Task 6); the list's "Post types" group, the not-in-view row's name and the error line with "Try again" (Task 7); "Show everything" out of the address once drawn (Task 8).

## Global Constraints

- Work only in the worktree `/Users/dknafelj/src/ContentSpiel-graph`, branch `pages-in-graph`. Read `CLAUDE.md` first; its rules bind. Read `docs/reference/cs-studio-shell-and-dashboard.md` ("Mind graph") before any task, `docs/reference/publishing.md` before Task 2, `docs/reference/design-system.md` and `docs/reference/i18n.md` before Tasks 5 to 8. A step names a place by its content, never by a line number.
- Every test command is prefixed `PGGSSENCMODE=disable`. One file, a system test included, is `bin/rails test <path>` (never `bin/rails test:system <path>`). A browser test needs `bin/rails tailwindcss:build` first. Never two test runners at once on this machine (the worktrees share the test databases), and check `sysctl -n vm.loadavg` before a browser run.
- **A node's id is its kind and its database id**: `page-12`, `post-12`, `tag-12`, `type-blog`, `all-posts` (and a page's local view's pills, `more-<target>`: `more-type-blog`, `more-tag-12`, `more-all-posts`). One rule in the payload's `id`, an edge's `source` and `target`, `data-selected`, `data-labelled`, `data-neighbours`, `data-hovered`, `data-node-id` and a search row. The address keeps one parameter per kind (`?page=12`, `?post=12`, `?tag=12`), read as decimal numbers; `page` wins over `post`, which wins over `tag`.
- **The graph reads the rows, not the published copies** (spec decision 3, approved). No `Publishing.published`, `published_all` or `Publishing::Listing` in `app/queries/post_graph/`.
- A page is read only through `AccessControl.scope(actor, "pages.read", Page.all)`, a post only through `AccessControl.scope(actor, "posts.read", Post.all)`. What is outside is no node, no count, no row, and no line is drawn to it. A focus outside the scope, in the trash or unknown is a 404, never a 403. Every query takes `actor:` with no default.
- **The statement count never grows with the number of pages or posts.** Never one statement per page, per block or per post. Every read that is new has a `capture_sql` test at two sizes.
- **A node's state is `Publishing::State`'s.** Nothing under `app/queries/post_graph/` or `app/javascript/mind_graph/` compares `published_at` with a clock or with nil (Task 2 adds the source guard).
- **No colour in any source.** The canvas reads token values from the page through `mind_graph/theme.js`; a module names a theme KEY (`"dim"`), never a value. No hex, `rgb()` or `hsl()` (`test/lib/admin_design_rules_test.rb`).
- **Every look value is the design answer's**, copied: page 14×10 (Home 18×13) with the card's radius; type hub 12px with a `--cs-surface` inner ring 1.5px wide whose outer edge is 1.5px inside the hub's radius; the status table of spec §4 (**warn means "scheduled"**: a scheduled record's centre dot, 4px across, and a scheduled change's corner dot are `--cs-warn`; unpublished changes' corner dot is `--cs-dim`; a corner dot is 5px across, its centre 1px in from the corner, with a 1.5px surface ring); a ring type as its filled-type mark inside a 1.5px ring; a ring type's HUB a 1.5px ring in the hue round a filled centre 6px across; a retired type's hub a DASHED outline in `--cs-dim` with a 4px dim centre dot; "+N more" a 16px-high pill that grows to fit its words (8px each side, at least 60px), one per target, its figure grouped; Tree solid 1px `--cs-line-strong`, Lists `--cs-dim` at 1.5px with round caps and a dash of 0.1 / 3.5, Related solid 1.5px ink, Shares a tag dashed `--cs-meta`, a hub's faint lines 1px `--cs-line`; labels 12px sans `--cs-ink` for a page, mono for a tag, sans `--cs-dim` for a post.
- **A design question that comes up while building is not decided by the implementer.** Stop, build the value this plan names (or the nearest value of the design answer) behind a named constant, and report the question to the controller, who puts it to the design system's owner. Tasks 5 to 8 each list the readings this plan already made, to be reported with a screenshot.
- Every new CS Studio string is a locale key: the legend's in `config/locales/admin/mind_graph_screen.en.yml`, the view's and the script's in `config/locales/admin/mind_graph.en.yml`, and every script key is written out in the view's `messages_data(...)` call (`test/lib/admin_i18n_test.rb`, `test/lib/script_messages_test.rb`). A name or a title reaches the page as text (`textContent`), never as markup.
- `d3-force` and `pin_all_from "app/javascript/mind_graph"` stay `preload: false`; nothing but the worker imports d3-force, by URL (`test/integration/public_javascript_test.rb`).
- Whatever the script writes into the page is taken back in `graph_controller.js`'s `reset()`: Turbo's snapshot keeps it. (The "Status" key is a dialog, `Admin::Ui::DialogComponent`, opened by the one `admin--ui--dialog` controller on `<body>` and closed natively: the graph's script writes nothing there, and it stands outside the graph's element.)
- The document order of the box stays search, graph, list (the Tab order).
- The Stimulus identifier stays `admin--mind-graph--graph`; no controller file is added, moved or renamed (`test/lib/source_layout_test.rb`).
- Queries hand up data and ids, never a URL, a route helper, a component or a colour (`test/lib/dependency_direction_test.rb`). A URL is built by the controller, or by the `url_for:` callable it passes.
- Never define `Admin::PostGraph` (`test/lib/admin_namespace_shadow_test.rb`).
- Queries are Active Record first, then Arel through `SqlNodes`; no SQL string (`test/lib/sql_strings_test.rb`).
- System tests: no fixed `sleep`; wait with `await_graph` (the existing helper: about five seconds per layout), `await_js`, `await_frames`, `click_frame_link`. A test that resizes the window puts the size back in an `ensure`. Any JavaScript error fails the test. **Keep new browser tests few**: what a mark looks like is asserted in `test/system/admin/mind_graph_modules_test.rb` against a recording context (no layout, no five-second wait), and what the app shows is read from its element's `data-*` and from `element.mindGraph`.
- Commits: conventional subject, one per task, ending with exactly:

  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
  ```

  Do not push. Scratch files only in a directory made with `mktemp -d` and deleted by name. Do not open `.kamal/secrets*`, `.env*`, `config/master.key` or the credentials.

## Review Focus

What the spec implies and its own "Testing" list does not name, most likely first. Each line names the test that pins it and the task that owns the code.

1. **A viewer who reads only part of the tree.** A page whose parent they cannot read must be drawn without a tree line, must not carry the parent's id, and must still have a place in the list's order; a tag or type only an unreadable page lists must be no node (Task 2: `"a page whose parent is outside the scope is drawn without a tree line and names no parent"`, `"a tag only an unreadable page lists is no node, and the page's lines are gone with it"`; Task 7: `"list: four groups: Pages first, in tree order and indented by depth, then posts and tags by their connections, then the post types as the data has them"`, whose data holds such a page).
2. **A list block whose settings name what is not there.** A tag in another case or with spaces round it, a tag no row has, a content type that is retired, two blocks with one target, a block inside a section, a block with a tag AND a type: one line or none, never an error (Task 2: `"a block names its tag whatever the case and the spaces, and a name no tag has makes no line"`, `"a retired type a block names is still a target, and lists no post"`, `"two blocks with one target are one line, and two targets are two"`; Task 3: `"a retired type a block names is a type node with no colour"`).
3. **The 3,000-line rule with nowhere to open.** Over the threshold with no readable Home, or with no page at all, the whole graph is answered, never `open` to an address that would be a 404; `everything=1` is never redirected; a junk `lines=` in the address shows no notice and is never echoed (Task 3: `"over the threshold without a readable Home the whole graph is answered"`, `"everything=1 answers the whole graph whatever its size"`; Task 8: `"lines= is read as a decimal number and nothing else, and is never written into the page as it came"`).
4. **Switching a kind off under something that is in use.** The selected node's kind, a pinned node's kind, the hovered row's kind, every kind at once: the card closes, the pin is forgotten, the canvas is empty and says so, nothing throws, and switching it on again brings the node back where it was (Task 6: `"a kind switched off takes the selection, the pins and the hover of its nodes with it, and switched on again brings the node back unpinned"`, `"with every kind off nothing is drawn and the list says so"`).
5. **A row for a post the canvas does not draw, pressed twice or already drawn.** A "not in view" row adds its post once; a second press selects it; a row whose post IS drawn selects and adds nothing; a row added in a page's local view is joined by one line to the hub that brings it in (Task 7: `"Not listed on any page shows the posts no page lists in place of the groups, and a row that is not in view adds its post once"`, `"list: a row that is not in view is named with its type and asks to be added, one in view selects, and the checkbox reports its change"`; Task 8: `"around a page, more opens the list with the posts that are not drawn, a row adds its post to its hub, and Open in Posts leads there"`).
6. **A junk focus.** `page=010`, `page=0x1A`, `page[]=1`, a negative number, a trashed page, a page outside the scope: 404 from the page, `data`, `listed` alike, never a 500 (Task 4: `"a page focus that is a list, hexadecimal, trashed or out of scope is not found, and 010 is page 10"` for the query and `"a page focus that is a list, hexadecimal, trashed or out of scope is 404, and 010 is page 10"` for the three requests).
7. **A title with markup in it**, a page's, a type's stored name, a path: text in the list, the card, the search rows and the focus bar (Task 7: `"the list's Pages group is the tree, a page's title and path with markup in them are text in the list, the search and the card"`; Task 4: `"a focus title with markup in it is escaped"`, with a page).
8. **A row that is not in view, for someone who does not see the canvas.** Its name must say what the post is and that pressing adds it ("…, blog post, not in view. Activate to add it to the graph."), with the type's name and never a bare "post"; pressing it must leave the focus somewhere that says what happened (the card of the post it added), and the row itself must then read as an ordinary row; a retired type's stored name with markup in it is text. And a read that fails must say so IN THE LIST with a button that tries again, which takes the focus nowhere unexpected and works a second time (Task 7: `"list: a row that is not in view is named with its type and asks to be added, one in view selects, and the checkbox reports its change"` (a retired type's row says "…, retired type"), `"list: a failed read says so in the list with Try again, and pressing it asks again"`, `"a failed read of the unlisted posts says so in the list, and Try again loads them"`).
9. **The "Status" key by keyboard.** "Status" is a button in the Tab order between the toggles and the zoom buttons; Enter or Space opens the key, a dialog named "Status key" (design answer H6); the focus is inside it and cannot leave it while it is open; Escape or its Close button closes it and the focus is back on "Status"; it holds no control but Close, so nothing in it can be switched; and it uses the chip's words, "Live, unpublished changes" and "Live, change scheduled", with no date (Task 6: `"the status key is a dialog named Status key that holds the five looks in the chip's words and no control"`, `"the legend's Status button opens the key and is no filter"`, `"the Status key opens from the keyboard as a dialog, and Escape gives the focus back"`, and the two Tab-order tests).
10. **A local view's faint lines in the wrong place.** A hub's line to a post is drawn only around a page: none in the whole graph, none around a post or a tag; a post a block lists by tag gets no second line beside its tag's; a row added from the list gets the line of ITS hub (`via`), not of the first hub on the canvas; and with "Lists" or "Post types" off the faint lines go too, every pill included (Task 3: `"a type node joins only the pages that list it, never a post of its type"`; Task 4: `"depth 2 around a page draws the twenty newest posts it lists, each joined to the hub that brings it in, and counts the rest behind more"`, `"a post the page lists through a tag is joined to the tag by its own line and by no other"`; Task 6: `"graph data: a line switched off hides only the lines, and a kind switched off hides its nodes and every line that touches one"`; Task 8: `"around a page, more opens the list with the posts that are not drawn, a row adds its post to its hub, and Open in Posts leads there"`).
11. **"Show everything" and the address.** Once the whole graph is drawn `everything=1` leaves the address, replaced through Turbo's history and never pushed (Back must still leave the screen, not step through two addresses), and only on the address that asked for everything (Task 8: `"a site with too many lines opens around Home, says why, and Show everything draws the whole graph and is not kept in the address"`).
12. **Two pills on one page.** A page with two list blocks has a pill per target, each on its own hub or tag, each counting only what its target brings in beyond the twenty the view draws; a target that brings in nothing more has none; a press on one lists ITS posts and none of the other's, and "Open in Posts" filters by that block; a post two blocks list is counted once, with the first block that lists it; a junk `target=` answers no rows and is never echoed (Task 2: `"what is left out is counted per target, by the target that brings each post in, and each target has its own block's filter"`; Task 4: `"a page with two list blocks has a pill per target, each on its own hub or tag with its own count, and a target that brings in nothing more has none"`, `"listed is the posts one target of a page brings in beyond the twenty its local view draws, each with that target, and the filter of the target's block"`; Task 8: `"a page with two list blocks has two pills, and each opens the list with its own posts and its own way to Posts"`).
13. **A figure of four digits in the pill.** "+1,980 more" does not fit sixty pixels: the pill is as wide as its measured words and 8px each side, the figure has its thousands separator in the pill and in the summary, the layout keeps the wider box clear, and a press near its end is the pill's (Task 5: `"marks: a type hub is a 12px circle in its colour with a surface ring, a ring type's a ring round a centre, All posts filled in dim, a retired type's a dashed outline in dim, a tag a square, more a pill with its words"`, `"marks: a page's, a type's and the pill's size does not follow its connections, the pill is as wide as its words need and never under 60, and the layout keeps a box's diagonal clear"`; Task 8: `"a pill with a figure of four digits is wider than sixty pixels, is pressed anywhere on it, and its figure is grouped"`).

## File Map

| File | Responsibility |
|---|---|
| `app/queries/post_graph.rb` | The constants (`CAP`, `MIN_TAGGED_POSTS`, `OPEN_AROUND_HOME_ABOVE`, `LISTED_IN_VIEW`, `ROW_LIMIT`, `ALL_POSTS`, `MORE`) and `PostGraph.node_id` |
| `app/queries/post_graph/site.rb` (new) | What every view loads once: readable posts, tag links, pages, the tree, the listings (five statements) |
| `app/queries/post_graph/tree.rb` (new) | Tree order, depth, readable parent and children, from `(id, parent_id, position)` rows; no statement |
| `app/queries/post_graph/listings.rb` (new) | A page's lists targets, the posts it lists and which target brings each in, "listed", "unlisted"; two statements |
| `app/queries/post_graph/builder.rb` | `plan` (the lines, no statement) and `build` (the nodes, seven statements) |
| `app/queries/post_graph/global.rb`, `local.rb`, `focus.rb`, `search.rb` | The two views, the focus (`page=`), search with pages |
| `app/queries/post_graph/rows.rb` (new) | The two list reads: `unlisted` and `listed` |
| `app/models/block_types/post_list.rb` | `matches?(settings, content_type:, tag_names:)`: the one criteria function, which `lists?` now calls |
| `app/values/publishing/state.rb` | A state can be handed the pending time it would otherwise read |
| `app/controllers/admin/mind_graph_controller.rb`, `config/routes.rb` | The permission (`pages.read` or `posts.read`), `page=`, `everything=1`, `lines=`, `unlisted`, `listed`; a scheduled change's short date (`change_on`) |
| `app/views/admin/mind_graph/show.html.erb` | The frame: the legend in place of the radios, the new templates and messages |
| `app/components/admin/mind_graph_screen/legend_component.rb`, `.html.erb` | The toggles, the "Status" link, and the keys |
| `app/components/admin/mind_graph_screen/status_key_component.rb`, `.html.erb` (new) | The status key: a dialog named "Status key" with the five looks, in the chip's words |
| `app/assets/tailwind/content-spiel.tailwind.css` | The legend's `.mg-*` swatches, on tokens |
| `config/locales/admin/mind_graph.en.yml`, `mind_graph_screen.en.yml` | Every string |
| `app/javascript/mind_graph/ids.js` (new) | `nodeId(kind, id)`, `recordId(id)` |
| `app/javascript/mind_graph/graph_data.js` (new) | Payload to nodes; what the toggles show; the label order; the counts. Pure |
| `app/javascript/mind_graph/marks.js` (new) | Every mark and its size: post, ring-type post, page, type hub, retired hub, tag, the "+N more" pill; the corner dot |
| `app/javascript/mind_graph/renderer.js` | The frame: lines by style, culling, labels, rings |
| `app/javascript/mind_graph/theme.js`, `labels.js`, `hit_test.js`, `layout_worker.js`, `layout_client.js` | `dim`, `warn`, `faint`, the radius, the mono font; labels outside the budget; a box's own target; a line's kind and Home's anchor |
| `app/javascript/mind_graph/app.js`, `card.js`, `card_notes.js`, `node_list.js`, `search_box.js` | The app, the card, the list, the search |
| `app/javascript/controllers/admin/mind_graph/graph_controller.js` | `reset()` takes the legend's counts back |
| `script/dev/mind_graph_posts.rb`, `script/dev/mind_graph_pages.rb` (new) | The measurement's data |
| `test/queries/post_graph/*`, `test/integration/admin/mind_graph*_test.rb`, `test/integration/trash_visibility_test.rb`, `test/components/admin/mind_graph_screen/legend_component_test.rb`, `test/system/admin/mind_graph_test.rb`, `test/system/admin/mind_graph_modules_test.rb`, `test/lib/mind_graph_guards_test.rb` (new) | The tests |

---

### Task 1: typed node ids, and nothing a person sees changes

Every node's id becomes `<kind>-<id>` everywhere at once. No page appears, no look changes, no string changes. This task touches every existing graph test and nothing else, so that every later task's diff is about pages.

**Files:**
- Create: `app/javascript/mind_graph/ids.js`
- Modify: `app/queries/post_graph.rb`, `app/queries/post_graph/builder.rb`, `app/queries/post_graph/focus.rb`, `app/queries/post_graph/search.rb`, `app/controllers/admin/mind_graph_controller.rb`, `app/javascript/mind_graph/card.js`, `app/javascript/mind_graph/card_notes.js`, `app/javascript/mind_graph/node_list.js`, `test/lib/admin_i18n_test.rb` (`ids.js` joins the converted list)
- Test: `test/queries/post_graph/global_test.rb`, `local_test.rb`, `focus_test.rb`, `search_test.rb`, `test/integration/admin/mind_graph_data_test.rb`, `test/integration/admin/mind_graph_test.rb`, `test/integration/trash_visibility_test.rb`, `test/system/admin/mind_graph_test.rb`, `test/system/admin/mind_graph_modules_test.rb`

**Interfaces:**
- Consumes: nothing.
- Produces:

```ruby
PostGraph.node_id(kind, id)   # => "post-12", "tag-3", "page-7", "type-blog"; kind a String or Symbol
PostGraph::Focus#node_id      # => PostGraph.node_id(kind, id)
# Builder: nodes[][:id] "post-<id>", tags[][:id] "tag-<id>", edges[][:source] / [:target] typed.
# Search row: { kind: "post" | "tag", id: "post-12", record_id: 12, label: "…" }
```

```js
// app/javascript/mind_graph/ids.js
nodeId(kind, id)   // "post-12"
recordId(id)       // "12" for "post-12", "blog" for "type-blog", "posts" for "all-posts"
```

In the system test: `nid(record_or_id)` answers the node id of a `Post`, a `Tag`, a `Page`, or an `Integer` (read as a post's id: this file's bare numbers are all posts' ids).

- [ ] **Step 1: the failing query tests.** In `test/queries/post_graph/global_test.rb`, `local_test.rb` and `focus_test.rb` every expected node id, edge end and `node_id` becomes typed. The rule, applied to every assertion in the three files: a post's id in `nodes`, in `edges` and in `focus[:node_id]` is `"post-#{post.id}"`; `focus[:id]` stays the number. Add to each test class:

```ruby
  def pid(post) = "post-#{post.id}"
```

  and, as the three assertions that carry the change, rewrite these (the rest follow the same rule):

```ruby
  # global_test.rb
  test "each PostRelation row is exactly one edge" do
    a = create_post(title: "A")
    b = create_post(title: "B")
    relate(a, b)

    assert_equal [ { source: pid(a), target: pid(b), kind: "related" } ], graph[:edges]
  end

  # local_test.rb, inside "depth 1 from a post: …"
    assert_equal [ pid(@centre), pid(@near) ].sort, ids(result)
    assert_equal({ kind: "post", id: @centre.id, node_id: pid(@centre), title: "Centre", depth: 1 }, result[:focus])

  # focus_test.rb
  test "a readable post is a focus with its title" do
    post = create_post(title: "Alpha")

    focus = PostGraph::Focus.find(actor: nil, post: post.id.to_s)

    assert_equal [ "post", post.id, "Alpha", "post-#{post.id}" ], [ focus.kind, focus.id, focus.title, focus.node_id ]
  end
```

  In `global_test.rb` the lookups `graph[:nodes].find { |n| n[:id] == a.id }` and `index_by { |n| n[:id] }` followed by `nodes[a.id]` become `== pid(a)` and `nodes[pid(a)]`. In `search_test.rb`:

```ruby
  test "posts by title and tags by name, posts first" do
    post = create_post(title: "Ruby notes", tags: [ "ruby" ])
    create_post(title: "Unrelated")
    tag = Tag.find_by!(name: "ruby")

    assert_equal [ { kind: "post", id: "post-#{post.id}", record_id: post.id, label: "Ruby notes" },
                   { kind: "tag", id: "tag-#{tag.id}", record_id: tag.id, label: "ruby" } ], search("rub")
  end
```

  And one new test in `global_test.rb`:

```ruby
  test "every id in the data is its kind and its database id: nodes, tags and both ends of every edge" do
    a = create_post(title: "A", tags: [ "shared" ])
    b = create_post(title: "B", tags: [ "shared" ])
    relate(a, b)

    result = graph
    ids = result[:nodes].map { |n| n[:id] } + result[:tags].map { |t| t[:id] }

    assert ids.all? { |id| id.match?(/\A(post|tag)-\d+\z/) }, ids.inspect
    assert_equal ids.sort, result[:edges].flat_map { |e| [ e[:source], e[:target] ] }.uniq.sort
    assert_equal "post-12", PostGraph.node_id("post", 12)
    assert_equal "type-blog", PostGraph.node_id(:type, "blog")
  end
```

- [ ] **Step 2: run them and see them fail.**

  Run: `PGGSSENCMODE=disable bin/rails test test/queries/post_graph`
  Expected: FAIL, among others `NoMethodError: undefined method 'node_id' for module PostGraph` and `Expected: [{source: "post-…` against the bare numbers.

- [ ] **Step 3: the queries.** In `app/queries/post_graph.rb`, inside the module, after `CAP`:

```ruby
  # A node's id in the graph's data and everywhere the page writes one (pages
  # spec, decision 4): its kind and its database id, "post-12", "tag-3",
  # "page-7"; a post type's is its stored name, "type-blog". One rule, so no
  # script asks what type an id has.
  def self.node_id(kind, id) = "#{kind}-#{id}"
```

  and in the header comment's "Shape" the ids read `"post-<id>"` and `"tag-<id>"`. In `builder.rb`, the three places that write an id:

```ruby
        tags: by_tag.map { |tag_id, rows| { id: PostGraph.node_id(:tag, tag_id), name: names[tag_id], count: tag_counts.fetch(tag_id, rows.size), degree: rows.size } }
                    .sort_by { |tag| [ tag[:name].to_s.downcase, tag[:id] ] },
        edges: related.map { |post_id, related_id| { source: PostGraph.node_id(:post, post_id), target: PostGraph.node_id(:post, related_id), kind: "related" } } +
               by_tag.flat_map { |tag_id, rows| rows.map { |_tag_id, post_id| { source: PostGraph.node_id(:post, post_id), target: PostGraph.node_id(:tag, tag_id), kind: "tag" } } }
```

  and in `nodes`, `id: PostGraph.node_id(:post, post.id),`. In `focus.rb`:

```ruby
    # The id the node carries in the graph's data.
    def node_id = PostGraph.node_id(kind, id)
```

  In `search.rb` the last two lines of `call`:

```ruby
      posts.map { |post| { kind: "post", id: PostGraph.node_id(:post, post.id), record_id: post.id, label: Locales.read(post, :title, locale: @locale) } } +
        tags.map { |id, name| { kind: "tag", id: PostGraph.node_id(:tag, id), record_id: id, label: name } }
```

  In `Admin::MindGraphController#search` the URL is built from the record's own id:

```ruby
      render json: rows.map { |row| row.merge(url: admin_mind_graph_path(row[:kind] => row[:record_id], **admin_url_options)) }
```

- [ ] **Step 4: run the query tests.**

  Run: `PGGSSENCMODE=disable bin/rails test test/queries/post_graph`
  Expected: PASS.

- [ ] **Step 5: the integration tests.** In `test/integration/admin/mind_graph_data_test.rb` and the Mind graph part of `test/integration/trash_visibility_test.rb` every `n["id"]`, edge `source` / `target` and `focus["node_id"]` compared with a post's id is compared with `"post-#{post.id}"`; `focus["id"]` stays the number. In `"search answers rows with the url of each row's local view"` the rows are `{ "kind" => "post", "id" => "post-#{post.id}", "record_id" => post.id, "label" => …, "url" => "/cs-studio/mind_graph?post=#{post.id}" }` and the tag's likewise with `?tag=#{tag.id}`. `test/integration/admin/mind_graph_test.rb` reads no node id and needs no change; run it to see that.

  Run: `PGGSSENCMODE=disable bin/rails test test/integration/admin/mind_graph_data_test.rb test/integration/admin/mind_graph_test.rb test/integration/trash_visibility_test.rb`
  Expected: PASS.

- [ ] **Step 6: the script's one place for ids.** Create `app/javascript/mind_graph/ids.js`:

```js
// A node's id (pages spec, decision 4): its kind and its database id,
// "post-12", "tag-3", "page-7", and a post type's stored name, "type-blog".
// The server writes them (`PostGraph.node_id`); the page never takes one
// apart except here, where a URL template or a notes key needs the record's
// own id back.
export const nodeId = (kind, id) => `${kind}-${id}`

// What follows the kind: "12" for "post-12", "blog" for "type-blog". A type's
// name may hold a dash or a slash of its own ("owner/thing"), so only the
// FIRST dash is the separator.
export function recordId(id) {
  const text = String(id)
  return text.slice(text.indexOf("-") + 1)
}
```

  In `card.js` add `import { recordId } from "mind_graph/ids"` and use it in the three places a template is filled:

```js
      cardNotes(node, { text, url: fill(urls.postNotes, "__ID__", recordId(node.id)), postUrl: node.url, onChange }),
      actions(
        openLink(node),
        link(buttonClasses.secondary, text.t("mind_graph.script.card.focus"), fill(urls.postFocus, "__ID__", recordId(node.id)))
      )
```

```js
        link(buttonClasses.secondary, text.t("mind_graph.script.card.focus"), fill(urls.tagFocus, "__ID__", recordId(node.id)))
```

  In `card_notes.js` add the same import; the section names the RECORD, and the draft's key keeps its form (a draft typed before this change is still found):

```js
  section.dataset.notesId = recordId(node.id)
```

```js
  const key = draftKey(document.body.getAttribute("data-admin--notes--inbox-person-value") || "", `graph-Post-${recordId(node.id)}`)
```

  In `node_list.js` the two maps keyed by `String(node.id)` stay as they are (an id is a string now, and `String` of one is itself); change only the comment above them to say so. Add `app/javascript/mind_graph/ids.js` to `CONVERTED` in `test/lib/admin_i18n_test.rb`, after `app/javascript/mind_graph/theme.js`.

- [ ] **Step 7: the system test's helpers.** In `test/system/admin/mind_graph_test.rb`, beside `screen_position`:

```ruby
  # A node's id as the data and the page write it (pages spec, decision 4). A
  # bare number in this file is always a post's id.
  def nid(record)
    case record
    when Integer then "post-#{record}"
    when String then record
    when Tag then "tag-#{record.id}"
    else "#{record.class.name.underscore}-#{record.id}"
    end
  end
```

  and the helpers that take an id convert through it, so the calls that hand them `post.id` stay as they are:

```ruby
  def screen_position(id)
    page.evaluate_script("document.querySelector(#{GRAPH.to_json}).mindGraph.screenPosition(#{nid(id).to_json})")
  end
```

  In `click_node`, `drag_node` and `assert_card_beside` the `id` reaches `screen_position` (converted there); in `drag_node`'s `await_js` the literal is `#{nid(id).to_json}`. `pin_pixel`, `notes_badge_pixel` and `pixels_of` call `screen_position(post.id)` and need no change.

- [ ] **Step 8: the system test's own comparisons.** Every place the file compares an attribute, or writes an id into JavaScript itself, changes by this table. Find them with `grep -n '\.id' test/system/admin/mind_graph_test.rb | grep -v 'screen_position(\|click_node(\|drag_node(\|assert_card_beside('`:

| As it is | As it becomes |
|---|---|
| `assert_equal a.id.to_s, graph["data-selected"]` (also `c.id.to_s`, `last.id.to_s`) | `assert_equal nid(a), graph["data-selected"]` |
| `[ hub.id, spokes[28].id ].map(&:to_s).sort` against `data-neighbours` | `[ hub, spokes[28] ].map { \|post\| nid(post) }.sort` |
| `[ c.id.to_s, tag_id ].sort` and `[ c.id.to_s ]` | `[ nid(c), tag_id ].sort` and `[ nid(c) ]` |
| `.dataset.labelled \|\| '').split(',').includes('#{a.id}')` (also `last.id`) | `.includes('#{nid(a)}')` |
| `graph["data-labelled"].split(",").first` against `last.id.to_s` | against `nid(last)` |
| `.dataset.hovered === '#{a.id}'` (also `hidden.id`) | `=== '#{nid(a)}'` |
| `labelled.exclude?(post.id.to_s)` | `labelled.exclude?(nid(post))` |
| `.mindGraph.screenPosition(#{a.id})`, `.mindGraph.labelBox(#{a.id})` inside a JavaScript string | `#{nid(a).to_json}` |
| `button[data-node-id=\"#{last.id}\"]`, `[data-node-id='#{last.id}']` | `#{nid(last)}` |
| `first_id = Post.order(:id).first.id` handed to `screen_position` | unchanged (the helper converts) |
| `[data-notes-id='#{a.id}']`, `graph-Post-#{a.id}`, `/posts/#{a.id}?notes=open`, `mind_graph\?post=#{a.id}` | unchanged: these are the RECORD's id |

  The three payloads the file plays itself are typed too. `CAPPED_GRAPH` and `CAPPED_LOCAL_GRAPH`: `id: "post-1"`, `id: "post-2"`, `edges: [ { source: "post-1", target: "post-2", kind: "related" } ]`, and the focus `{ kind: "post", id: 1, node_id: "post-1", title: "One", depth: 2 }`. `BIG_GRAPH`:

```js
      const nodes = Array.from({ length: 1500 }, (_, index) => ({ id: `post-${index + 1}`, title: `Post ${index + 1}`, type: "blog", colour_index: 1, status: "live", url: "/post", degree: 3, related_count: 2, tag_count: 1 }))
      const tags = Array.from({ length: 30 }, (_, index) => ({ id: `tag-${index + 1}`, name: `tag ${index + 1}`, count: 50, degree: 50 }))
      const edges = [
        ...nodes.slice(1).map((node, index) => ({ source: `post-${index + 1}`, target: node.id, kind: "related" })),
        ...nodes.map((node, index) => ({ source: node.id, target: `tag-${((index + 1) % 30) + 1}`, kind: "tag" }))
      ]
```

  In `test/system/admin/mind_graph_modules_test.rb` the worker's and the renderer's tests hand over ids of their own making (numbers) and read none back from the app: no change. Add one test there:

```ruby
  test "ids: a node's id is its kind and its record's id, and only the first dash separates them" do
    assert_equal [ "post-12", "12", "blog", "owner/a-b", "posts" ],
      js_module("mind_graph/ids", '[m.nodeId("post", 12), m.recordId("post-12"), m.recordId("type-blog"), m.recordId("type-owner/a-b"), m.recordId("all-posts")]')
  end
```

- [ ] **Step 9: run every graph test.**

  Run: `bin/rails tailwindcss:build && PGGSSENCMODE=disable bin/rails test test/queries/post_graph test/integration/admin/mind_graph_data_test.rb test/integration/admin/mind_graph_test.rb test/integration/trash_visibility_test.rb test/lib/admin_i18n_test.rb test/lib/script_messages_test.rb`
  Expected: PASS.
  Run: `sysctl -n vm.loadavg` (a load near the core count is not quiet), then `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/mind_graph_test.rb test/system/admin/mind_graph_modules_test.rb`
  Expected: PASS, every test that passed before, and the one new module test. A failure that reads `node post-… is not on screen` or an empty `data-selected` is a comparison Step 8's table missed.

- [ ] **Step 10: commit.**

```bash
git add app/queries/post_graph.rb app/queries/post_graph app/controllers/admin/mind_graph_controller.rb app/javascript/mind_graph test/queries/post_graph test/integration/admin/mind_graph_data_test.rb test/integration/trash_visibility_test.rb test/system/admin/mind_graph_test.rb test/system/admin/mind_graph_modules_test.rb test/lib/admin_i18n_test.rb
git commit -m "ref: the mind graph's ids are typed — post-12, tag-3 — in the data, the page and the tests"
```

---
### Task 2: what a page lists — the criteria, the tree, the listings, and a state that is handed its pending time

Four small pieces with no caller yet, each tested by itself; the graph is untouched. They are one task because `PostGraph::Site` is the one object the next two tasks consume, and a reviewer judges its five statements as a whole.

**Files:**
- Create: `app/queries/post_graph/tree.rb`, `app/queries/post_graph/listings.rb`, `app/queries/post_graph/site.rb`, `test/queries/post_graph/tree_test.rb`, `test/queries/post_graph/listings_test.rb`, `test/queries/post_graph/site_test.rb`, `test/lib/mind_graph_guards_test.rb`
- Modify: `app/models/block_types/post_list.rb`, `app/values/publishing/state.rb`, `app/queries/post_graph.rb`
- Test: `test/models/block_types/post_list_test.rb` (new: `lists?` is tested through `ContentBlock` in `test/models/content_block_test.rb` today, which stays as it is), `test/values/publishing/state_test.rb`

**Interfaces:**
- Consumes: `PostGraph.node_id` (Task 1).
- Produces:

```ruby
BlockTypes::PostList.matches?(settings, content_type:, tag_names:)   # => true | false; `lists?(settings, post)` is this
Publishing::State.of(record, now: Time.current, pending_at: <not given>) # given (a Time or nil), `pending_at` and `state` ask the database nothing

PostGraph::OPEN_AROUND_HOME_ABOVE  # 3_000
PostGraph::LISTED_IN_VIEW          # 20
PostGraph::ROW_LIMIT               # 200
PostGraph::ALL_POSTS               # "all-posts"
PostGraph::MORE                    # "more": the kind of a pill's id, PostGraph.node_id(MORE, target) => "more-type-blog"
PostGraph.paths(page_ids, locale:) # => { page_id => "/about" }: the current path in `locale`, else the default language's; one statement

PostGraph::Tree.new(rows)          # rows: [[id, parent_id, position], …] of the READABLE pages
  #home_id          # the id of the page with no parent, or nil when it is not among the rows
  #order            # every id, in tree order (Home, then each branch by position, then id); a page whose parent is not among the rows follows, by id
  #rank(id)         # its index in `order`
  #depth(id)        # 0 for Home; 1 + its parent's; 1 for a page whose parent is not among the rows
  #parent(id)       # the parent's id when the parent is among the rows, else nil
  #children(id)     # ids, in order
  #neighbours(id)   # [parent, *children], without nil

PostGraph::Listings.blocks(page_ids)   # the list blocks of these pages (an Array of ids or a relation selecting them), one statement
PostGraph::Listings.new(page_ids:, post_rows:, tag_links:)
  #edges               # [[page_id, target], …]; target is "tag-<id>", "type-<name>" or "all-posts"; one per distinct target of a page
  #targets(page_id)    # [target, …]
  #pages_of(target)    # [page_id, …]
  #tag_ids             # Set of the ids of the tags a block names (and that exist)
  #posts_of(page_id)   # [post_id, …] newest first (published_at, a draft by updated_at), then by id descending
  #target_of(page_id, post_id) # the target of the FIRST list block of the page that lists the post, or nil: the hub that brings it in
  #listed_count(page_id)
  #listed?(post_id)
  #unlisted            # [post_id, …] newest first
  #left_out(page_id)   # { target => count }: what each target brings in BEYOND the LISTED_IN_VIEW newest posts of the page; a target with none is not in it
  #left_out_of(page_id, target) # [post_id, …] newest first: those posts, of one target
  #filter_of(page_id, target = nil)  # { type: "blog" | nil, tag: "ruby" | nil } of the page's first list block (with `target`: the first that points at it); {} with none
  #type_count(name)    # readable posts whose stored type is `name`
  #post_count          # readable posts a block with no filter lists

PostGraph::Site.load(actor:)       # five statements
  #readable_posts   # the relation
  #post_rows        # [[id, content_type, published_at, updated_at], …]
  #stamps           # { post_id => updated_at }
  #tag_links        # [[tag_id, post_id], …] ordered by tag, then post
  #tag_counts       # { tag_id => readable posts carrying it }
  #pages            # [Page, …] in tree order, loaded with Site::PAGE_COLUMNS
  #page(id)         # the Page, or nil
  #home             # the Page with no parent, or nil
  #tree             # PostGraph::Tree
  #listings         # PostGraph::Listings
```

- [ ] **Step 1: the criteria's failing test.** Create `test/models/block_types/post_list_test.rb`:

```ruby
require "test_helper"

# `BlockTypes::PostList`'s criteria by themselves: what a list block with
# these settings lists, asked for a type and tag names with no record.
class BlockTypes::PostListTest < ActiveSupport::TestCase
  Criteria = Struct.new(:content_type, :tag)

  test "matches? is the listing's criteria for a type and tag names, with no record" do
    assert BlockTypes::PostList.matches?(Criteria.new(nil, nil), content_type: "blog", tag_names: [])
    assert BlockTypes::PostList.matches?(Criteria.new("blog", " Rails "), content_type: "blog", tag_names: %w[rails other])
    assert_not BlockTypes::PostList.matches?(Criteria.new("blog", nil), content_type: "resume_entry", tag_names: [])
    assert_not BlockTypes::PostList.matches?(Criteria.new(nil, "rails"), content_type: "blog", tag_names: %w[ruby])
    assert_not BlockTypes::PostList.matches?(Criteria.new(nil, nil), content_type: "gone/thing", tag_names: []), "a post of a type that is not registered is listed nowhere"
  end

  test "lists? and matches? are one answer" do
    post = create_post(title: "A", tags: [ "Rails" ])
    [ Criteria.new(nil, nil), Criteria.new("blog", "rails"), Criteria.new("resume_entry", nil), Criteria.new(nil, "ruby") ].each do |criteria|
      assert_equal BlockTypes::PostList.lists?(criteria, post),
        BlockTypes::PostList.matches?(criteria, content_type: post.content_type, tag_names: post.tags.map(&:name)), criteria.to_a.inspect
    end
  end
end
```

  Run: `PGGSSENCMODE=disable bin/rails test test/models/block_types/post_list_test.rb`; expected FAIL with `undefined method 'matches?'`.

- [ ] **Step 2: the criteria.** In `app/models/block_types/post_list.rb`, replace the body of `lists?` and add `matches?` above it, keeping every comment that is there:

```ruby
    # The same criteria for a caller that holds a post's stored type and its
    # tags' names and no record: the mind graph asks for every readable post
    # at once (`PostGraph::Listings`), from rows it has already loaded. THE
    # ONE PLACE the per-post test is written: `lists?` below is this, so the
    # listing, a post's address and the graph cannot come to disagree about
    # which page lists which post. Still in lockstep with `listed_posts`.
    def self.matches?(settings, content_type:, tag_names:)
      return false if ContentTypes.find(content_type).nil?
      return false if settings.content_type.present? && settings.content_type.to_s != content_type.to_s

      tag = settings.tag.to_s.strip
      tag.blank? || tag_names.any? { |name| name.to_s.downcase == tag.downcase }
    end

    def self.lists?(settings, post)
      matches?(settings, content_type: post.content_type, tag_names: post.tags.map(&:name))
    end
```

  Run the file again, then `PGGSSENCMODE=disable bin/rails test test/models/content_block_test.rb test/models/public_site/paths_test.rb` (`lists?` itself, and the addresses derived through it); expected PASS, all three.

- [ ] **Step 3: the state's failing test.** In `test/values/publishing/state_test.rb`:

```ruby
  test "a state that is handed its pending time asks the database nothing, and is the state it would have read" do
    TABLE.each do |(time, pending, mark), (state, _changes, _actions)|
      record = record_with(time, pending, mark)
      at = Publishing.pending(record)&.live_at

      statements = capture_sql { assert_equal state, Publishing::State.of(record, pending_at: at).state, "#{time} pending=#{pending} mark=#{mark}" }

      assert_empty statements
    end
  end

  test "handed nil, a live record has no change scheduled, whatever its copies say" do
    record = record_with(:past, true, false)

    assert_equal :live, Publishing::State.of(record, pending_at: nil).state
    assert_equal :live_change_scheduled, Publishing::State.of(record).state
  end
```

  Run: `PGGSSENCMODE=disable bin/rails test test/values/publishing/state_test.rb`; expected FAIL with `unknown keyword: :pending_at`.

- [ ] **Step 4: the state.** In `app/values/publishing/state.rb`, replace `self.of` and `initialize`:

```ruby
    # `pending_at:` hands over the answer to the one question that costs a
    # statement (fact 2 above), for a caller that has read the pending copies
    # of many records at once: the mind graph draws the fifth state on every
    # node, and asks once for all of them. Given (a time, or nil for "none"),
    # `pending_at` and `state` ask the database nothing. Not given, they read
    # it the first time, as before. A draft's is ignored either way.
    NOT_READ = Object.new.freeze
    private_constant :NOT_READ

    def self.of(record, now: Time.current, pending_at: NOT_READ) = new(record, now: now, pending_at: pending_at)

    def initialize(record, now: Time.current, pending_at: NOT_READ)
      @record = record
      @now = now
      @pending_at = pending_at unless pending_at.equal?(NOT_READ)
    end
```

  (`pending_at` below already answers `@pending_at` when it is defined.) Run the file; expected PASS.

- [ ] **Step 5: the tree's failing test.** Create `test/queries/post_graph/tree_test.rb`:

```ruby
require "test_helper"

# `PostGraph::Tree`: the page tree as far as the viewer can read it, from
# plain rows. No statement, no record.
class PostGraph::TreeTest < ActiveSupport::TestCase
  #   1 Home
  #   ├─ 2 About (position 1)
  #   │   └─ 5 Team
  #   └─ 3 Blog (position 0)
  #   9 Stray: its parent, 8, is not among the rows
  ROWS = [ [ 9, 8, 0 ], [ 5, 2, 0 ], [ 2, 1, 1 ], [ 3, 1, 0 ], [ 1, nil, nil ] ].freeze

  setup { @tree = PostGraph::Tree.new(ROWS) }

  test "the order is Home, then each branch by position, and a page whose parent is not there comes after" do
    assert_equal 1, @tree.home_id
    assert_equal [ 1, 3, 2, 5, 9 ], @tree.order
    assert_equal [ 0, 1, 3 ], [ 1, 3, 5 ].map { |id| @tree.rank(id) }
  end

  test "depth 0 is Home, and a page whose parent is not there is at depth 1" do
    assert_equal({ 1 => 0, 3 => 1, 2 => 1, 5 => 2, 9 => 1 }, @tree.order.to_h { |id| [ id, @tree.depth(id) ] })
  end

  test "a parent that is not among the rows is no parent" do
    assert_nil @tree.parent(9)
    assert_nil @tree.parent(1)
    assert_equal 2, @tree.parent(5)
    assert_equal [ 3, 2 ], @tree.children(1)
    assert_equal [ 1, 5 ], @tree.neighbours(2)
    assert_empty @tree.neighbours(9)
  end

  test "siblings without a position come after those with one, by id" do
    tree = PostGraph::Tree.new([ [ 1, nil, nil ], [ 4, 1, nil ], [ 2, 1, nil ], [ 3, 1, 0 ] ])

    assert_equal [ 1, 3, 2, 4 ], tree.order
  end

  test "no rows, and rows without Home" do
    assert_equal [ nil, [] ], [ PostGraph::Tree.new([]).home_id, PostGraph::Tree.new([]).order ]
    assert_equal [ nil, [ 5, 9 ] ], [ PostGraph::Tree.new([ [ 9, 8, 0 ], [ 5, 2, 0 ] ]).home_id, PostGraph::Tree.new([ [ 9, 8, 0 ], [ 5, 2, 0 ] ]).order ]
  end
end
```

  Run: `PGGSSENCMODE=disable bin/rails test test/queries/post_graph/tree_test.rb`; expected FAIL with `uninitialized constant PostGraph::Tree`.

- [ ] **Step 6: the tree.** Create `app/queries/post_graph/tree.rb`:

```ruby
# The page tree as far as THIS viewer can read it (pages in the mind graph,
# spec §1, §2), from `(id, parent_id, position)` rows the caller has already
# narrowed by the read scope. No statement and no record: the graph needs a
# page's place in tree order, its depth and its readable neighbours for two
# hundred pages at once, and closure_tree would ask per page.
#
# WHAT IS NOT AMONG THE ROWS DOES NOT EXIST HERE. A page whose parent the
# viewer cannot read has no parent (so no tree line is drawn to it and its
# id is never handed out), stands at depth 1 and comes after the tree proper
# in `order`, by id. Home is the one page with no `parent_id`; when it is not
# among the rows there is no `home_id`.
#
# Siblings are ordered by `position`, one without a position after those
# with one, then by id: the order the Pages screen shows.
module PostGraph
  class Tree
    attr_reader :order, :home_id

    def initialize(rows)
      @parent = {}
      position = {}
      rows.each do |id, parent_id, place|
        @parent[id] = parent_id
        position[id] = place
      end
      @children = {}
      @parent.each { |id, parent_id| (@children[parent_id] ||= []) << id if @parent.key?(parent_id) }
      @children.each_value { |ids| ids.sort_by! { |id| [ position[id] || Float::INFINITY, id ] } }
      @home_id = @parent.find { |_id, parent_id| parent_id.nil? }&.first
      @order = []
      @depth = {}
      roots = @parent.keys.select { |id| parent(id).nil? }.sort_by { |id| [ id == @home_id ? 0 : 1, id ] }
      roots.each { |id| visit(id, id == @home_id ? 0 : 1) }
      @rank = @order.each_with_index.to_h
    end

    def parent(id) = @parent.key?(@parent[id]) ? @parent[id] : nil
    def children(id) = @children.fetch(id, [])
    def neighbours(id) = [ parent(id), *children(id) ].compact
    def depth(id) = @depth.fetch(id)
    def rank(id) = @rank.fetch(id)

    private

    def visit(id, depth)
      @order << id
      @depth[id] = depth
      children(id).each { |child| visit(child, depth + 1) }
    end
  end
end
```

  Run the file; expected PASS.

- [ ] **Step 7: the listings' failing tests.** Create `test/queries/post_graph/listings_test.rb`. Its helpers, and the tests in full:

```ruby
require "test_helper"

# `PostGraph::Listings` (pages in the mind graph, spec §1): which page lists
# what, from the list blocks' settings, and which posts that is.
class PostGraph::ListingsTest < ActiveSupport::TestCase
  def list_block(page, **settings)
    ContentBlock.create!(owner: page, block_type: :post_list, position: page.content_blocks.count, settings: settings.stringify_keys)
  end

  def listings(pages = Page.all)
    posts = Post.kept.pluck(:id, :content_type, :published_at, :updated_at)
    links = PostTag.where(post_id: Post.kept.select(:id)).order(:tag_id, :post_id).pluck(:tag_id, :post_id)
    PostGraph::Listings.new(page_ids: pages.map(&:id), post_rows: posts, tag_links: links)
  end

  def tag(name) = "tag-#{Tag.find_by!(name: name).id}"

  setup do
    @ruby = create_post(title: "Ruby", tags: [ "ruby" ])
    @plain = create_post(title: "Plain")
    @entry = create_post(title: "Entry", content_type: "resume_entry", tags: [ "ruby" ])
    @draft = create_post(title: "Draft", published: false)
    @page = create_page(title: "Listing")
  end

  test "a block's target is its tag, else its type, else All posts" do
    by_tag = create_page(title: "By tag")
    by_type = create_page(title: "By type")
    list_block(@page)
    list_block(by_tag, tag: "ruby", content_type: "blog")
    list_block(by_type, content_type: "blog")

    result = listings

    assert_equal [ "all-posts" ], result.targets(@page.id)
    assert_equal [ tag("ruby") ], result.targets(by_tag.id), "a block with a tag and a type points at the tag"
    assert_equal [ "type-blog" ], result.targets(by_type.id)
    assert_equal [ by_tag.id ], result.pages_of(tag("ruby"))
    assert_equal Set[Tag.find_by!(name: "ruby").id], result.tag_ids
  end

  test "a block names its tag whatever the case and the spaces, and a name no tag has makes no line" do
    list_block(@page, tag: "  RUBY ")
    other = create_page(title: "Other")
    list_block(other, tag: "nothing-has-this")

    result = listings

    assert_equal [ tag("ruby") ], result.targets(@page.id)
    assert_empty result.targets(other.id)
    assert_empty result.posts_of(other.id)
    assert_equal [ [ @page.id, tag("ruby") ] ], result.edges
  end

  test "two blocks with one target are one line, and two targets are two" do
    list_block(@page, content_type: "blog")
    list_block(@page, content_type: "blog")
    list_block(@page, tag: "ruby")

    assert_equal [ "type-blog", tag("ruby") ].sort, listings.targets(@page.id).sort
  end

  test "a block in a section belongs to its page" do
    section = ContentBlock.create!(owner: @page, block_type: :section, position: 0, settings: { "layout" => "two" })
    ContentBlock.create!(owner: @page, block_type: :post_list, position: 0, section_id: section.id, section_column: 1, settings: { "content_type" => "blog" })

    assert_equal [ "type-blog" ], listings.targets(@page.id)
  end

  test "a retired type a block names is still a target, and lists no post" do
    list_block(@page, content_type: "gone/thing")
    @plain.update_column(:content_type, "gone/thing")

    result = listings

    assert_equal [ "type-gone/thing" ], result.targets(@page.id)
    assert_empty result.posts_of(@page.id)
    assert_equal 1, result.type_count("gone/thing")
  end

  test "a block of another type and a page that is not asked for make no line" do
    other = create_page(title: "Other")
    list_block(other, content_type: "blog")
    ContentBlock.create!(owner: @page, block_type: :rich_text, position: 0)

    assert_empty listings([ @page ]).edges
  end

  # The parity the spec asks for: for every shape of settings, the posts
  # this object says a page lists are the posts the listing itself lists.
  test "the posts a page lists are the listing's own, for every shape of settings" do
    @plain.update_column(:content_type, "gone/thing")
    shapes = [ {}, { content_type: "blog" }, { tag: "ruby" }, { tag: " Ruby " }, { content_type: "resume_entry", tag: "ruby" },
               { content_type: "blog", tag: "nothing-has-this" }, { content_type: "gone/thing" } ]
    pages = shapes.each_with_index.map { |shape, index| create_page(title: "Shape #{index}").tap { |page| list_block(page, **shape) } }

    result = listings

    pages.zip(shapes).each do |page, shape|
      expected = BlockTypes::PostList.listed_posts(page.content_blocks.first.settings_object, include_unpublished: true).pluck(:id)
      assert_equal expected.sort, result.posts_of(page.id).sort, shape.inspect
      assert_equal expected.size, result.listed_count(page.id), shape.inspect
    end
  end

  test "a page's posts come newest first, a draft by when it was last changed" do
    list_block(@page)
    @ruby.update_columns(published_at: 3.days.ago)   # version: none (a test sets a time) # changes: none (a test sets a time)
    @entry.update_columns(published_at: 1.day.ago)   # version: none (a test sets a time) # changes: none (a test sets a time)
    @plain.update_columns(published_at: 2.days.ago)  # version: none (a test sets a time) # changes: none (a test sets a time)
    @draft.update_columns(updated_at: 1.hour.ago)    # version: none (a test sets a time) # changes: none (a test sets a time)

    assert_equal [ @draft.id, @entry.id, @plain.id, @ruby.id ], listings.posts_of(@page.id)
  end

  # Third design answers: in a page's local view the hub that brings a post
  # in draws a line to it. Which hub that is, is the first block's that lists it.
  test "the target that brings a post in is the first list block's that lists it, and none for a post the page does not list" do
    list_block(@page, tag: "nothing-has-this")
    list_block(@page, tag: "ruby")
    list_block(@page, content_type: "blog")
    list_block(@page)

    result = listings

    assert_equal tag("ruby"), result.target_of(@page.id, @ruby.id), "the tag's block comes before the type's"
    assert_equal "type-blog", result.target_of(@page.id, @plain.id)
    assert_equal tag("ruby"), result.target_of(@page.id, @entry.id)
    assert_nil result.target_of(create_page(title: "Other").id, @ruby.id)
    @plain.update_column(:content_type, "resume_entry")
    assert_equal "all-posts", listings.target_of(@page.id, @plain.id), "only the block with no filter lists it now"
  end

  # Design answer H1: one pill per target, each counting only what that
  # target brings in beyond the posts the view draws.
  test "what is left out is counted per target, by the target that brings each post in, and each target has its own block's filter" do
    list_block(@page, tag: "pill")
    list_block(@page, content_type: "resume_entry")
    pills = 15.times.map { |index| create_post(title: "Pill #{index}", tags: [ "pill" ]) }
    entries = 15.times.map { |index| create_post(title: "Entry #{index}", content_type: "resume_entry") }
    pills.each_with_index { |post, index| post.update_columns(published_at: (2 * index + 1).hours.ago) }   # version: none (a test sets a time) # changes: none (a test sets a time)
    entries.each_with_index { |post, index| post.update_columns(published_at: (2 * index + 2).hours.ago) } # version: none (a test sets a time) # changes: none (a test sets a time)

    result = listings

    # The setup's @entry, published a moment ago, is the newest; then the
    # hours alternate. The twenty newest: @entry, ten pills, nine entries.
    assert_equal 31, result.listed_count(@page.id)
    assert_equal({ tag("pill") => 5, "type-resume_entry" => 6 }, result.left_out(@page.id))
    assert_equal pills.last(5).map(&:id), result.left_out_of(@page.id, tag("pill"))
    assert_equal entries.last(6).map(&:id), result.left_out_of(@page.id, "type-resume_entry")
    assert_empty result.left_out_of(@page.id, "type-blog")
    assert_empty result.left_out(create_page(title: "Other").id)
    assert_equal({ type: nil, tag: "pill" }, result.filter_of(@page.id, tag("pill")))
    assert_equal({ type: "resume_entry", tag: nil }, result.filter_of(@page.id, "type-resume_entry"))
    assert_equal({ type: nil, tag: "pill" }, result.filter_of(@page.id), "with no target, the first block's")
    assert_equal({}, result.filter_of(@page.id, "type-blog"))
  end

  test "listed and unlisted are each other's rest, and with no list block every post is unlisted" do
    assert_equal [ @ruby, @plain, @entry, @draft ].map(&:id).sort, listings.unlisted.sort

    list_block(@page, content_type: "blog")
    result = listings

    assert result.listed?(@ruby.id)
    assert_not result.listed?(@entry.id)
    assert_equal [ @entry.id ], result.unlisted
    assert_equal({ type: "blog", tag: nil }, result.filter_of(@page.id))
    assert_equal({}, result.filter_of(create_page(title: "None").id))
    assert_equal [ 3, 1, 4 ], [ result.type_count("blog"), result.type_count("resume_entry"), result.post_count ]
  end

  test "it costs two statements whatever the number of pages, blocks and posts" do
    list_block(@page, tag: "ruby")
    12.times { |index| list_block(create_page(title: "More #{index}"), tag: "ruby", content_type: "blog") }
    12.times { |index| create_post(title: "Post #{index}", tags: [ "ruby" ]) }
    posts = Post.kept.pluck(:id, :content_type, :published_at, :updated_at)
    links = PostTag.pluck(:tag_id, :post_id)
    page_ids = Page.pluck(:id)

    many = capture_sql do
      result = PostGraph::Listings.new(page_ids: page_ids, post_rows: posts, tag_links: links)
      page_ids.each { |id| result.posts_of(id) }
      page_ids.each { |id| result.target_of(id, posts.first.first) }
      result.unlisted
    end

    assert_equal 2, many.size, many.join("\n")
  end
end
```

  (`section`'s settings key: check `app/models/block_types/section.rb` for the layout field's name and a valid value, and use those.)

  Run: `PGGSSENCMODE=disable bin/rails test test/queries/post_graph/listings_test.rb`; expected FAIL with `uninitialized constant PostGraph::Listings`.

- [ ] **Step 8: the constants and the listings.** In `app/queries/post_graph.rb`, after `node_id`:

```ruby
  # Above this many lines the screen opens in the local view around Home,
  # with "Show everything" (pages spec, decision 6; the design answer's
  # "about 3,000 visible edges").
  OPEN_AROUND_HOME_ABOVE = 3_000

  # How many of the posts a page lists its local view draws; the rest are
  # behind "+N more" (design answer F4, F5).
  LISTED_IN_VIEW = 20

  # The most rows one of the list's reads answers (`unlisted`, `listed`).
  ROW_LIMIT = 200

  # The one node a list block with no filter points at: no record, so no
  # database id to add. And the kind of a "+N more" pill of a page's local
  # view, ONE PER TARGET (design answer H1): its id is the kind and the
  # target it hangs off, `node_id(MORE, "type-blog")` => "more-type-blog".
  ALL_POSTS = "all-posts"
  MORE = "more"

  # Each page's current address in `locale`, else in the default language:
  # `{ page_id => "/about" }`. One statement.
  def self.paths(page_ids, locale:)
    wanted = [ locale.to_s, Locales.default.to_s ].uniq
    rows = PublicPath.current.where(record_type: "Page", record_id: page_ids, locale: wanted).pluck(:record_id, :locale, :path)
    rows.group_by(&:first).transform_values { |found| (found.find { |_id, language, _path| language == locale.to_s } || found.first).last }
  end
```

  Create `app/queries/post_graph/listings.rb`:

```ruby
# Which page lists what (pages in the mind graph, spec §1, decisions 9 and
# 10): the "lists" lines, and the posts behind them.
#
# A LINE IS MADE FROM THE BLOCK, NEVER FROM THE POSTS. For each list block
# (a block whose type has the `lists_posts` capability; in a section or not,
# its owner is the page) of the pages handed in, its typed settings say the
# target: the tag when it names one (found by name whatever the case, as the
# listing finds it; a name no tag has makes no line, as it lists nothing),
# else the content type, else the one "All posts" node. One line per distinct
# target of a page.
#
# WHICH POSTS A PAGE LISTS is worked out here in Ruby, from rows the caller
# has loaded, by asking `BlockTypes::PostList.matches?` -- the listing's own
# criteria -- so the graph cannot come to disagree with the public page and
# with a post's address (`test/queries/post_graph/listings_test.rb` holds
# the parity). Blocks with the same settings share one pass over the posts.
#
# WHICH TARGET BRINGS A POST IN (`target_of`): the first list block of the
# page (by id, as `blocks` orders them) that has a target and lists the post. A page's
# local view draws a faint line from that hub to the post (pages spec §1,
# the third design answers), so a post has one such line however many
# blocks of the page list it.
#
# It knows nothing of rights: `page_ids` and `post_rows` are what the viewer
# may read, narrowed by the caller, so "listed" means "a page YOU can read
# lists it" (spec §2, Risks).
#
# Two statements: the blocks, and the tags their settings name. (With no
# name to look up the second is not made: `Tag.named_any` answers `none`.)
module PostGraph
  class Listings
    def self.blocks(page_ids)
      types = BlockTypes.with_capability(:lists_posts).map { |definition| definition.name.to_s }
      ContentBlock.where(owner_type: "Page", owner_id: page_ids, block_type: types)
                  .select(:id, :owner_id, :owner_type, :block_type, :settings, :translated_settings).order(:owner_id, :id)
    end

    def self.key(settings) = [ settings.content_type.presence&.to_s, settings.tag.to_s.strip.downcase.presence ]

    # `post_rows`: `[[id, content_type, published_at, updated_at], …]`;
    # `tag_links`: `[[tag_id, post_id], …]`.
    def initialize(page_ids:, post_rows:, tag_links:)
      @post_rows = post_rows
      @recency = post_rows.to_h { |id, _type, published_at, updated_at| [ id, (published_at || updated_at).to_f ] }
      @tags_of = {}
      tag_links.each { |tag_id, post_id| (@tags_of[post_id] ||= []) << tag_id }
      @settings = {}
      self.class.blocks(page_ids).each do |block|
        settings = block.settings_object or next
        (@settings[block.owner_id] ||= []) << settings
      end
      names = @settings.values.flatten.filter_map { |settings| self.class.key(settings).last }.uniq
      @tag_id = Tag.named_any(names).pluck(:name, :id).to_h { |name, id| [ name.downcase, id ] }
      @tag_name = @tag_id.invert
    end

    def edges
      @edges ||= @settings.flat_map { |page_id, all| all.filter_map { |settings| target(settings) }.uniq.map { |target| [ page_id, target ] } }
    end

    def targets(page_id) = (@targets ||= edges.group_by(&:first).transform_values { |rows| rows.map(&:last) }).fetch(page_id, [])
    def pages_of(target) = (@pages_of ||= edges.group_by(&:last).transform_values { |rows| rows.map(&:first) }).fetch(target, [])

    def tag_ids
      @tag_ids ||= edges.filter_map { |_page_id, target| target.delete_prefix("tag-").to_i if target.start_with?("tag-") }.to_set
    end

    def posts_of(page_id)
      (@posts_of ||= {})[page_id] ||= newest_first(@settings.fetch(page_id, []).flat_map { |settings| matching(settings) }.uniq)
    end

    def target_of(page_id, post_id)
      @settings.fetch(page_id, []).each do |settings|
        found = target(settings) or next
        return found if matching(settings).include?(post_id)
      end
      nil
    end

    def listed_count(page_id) = posts_of(page_id).size
    def listed?(post_id) = listed.include?(post_id)
    def unlisted = newest_first(@post_rows.map(&:first).reject { |id| listed?(id) })

    # What each target of the page brings in beyond the `shown` newest posts
    # the local view draws (design answer H1: one "+N more" pill per target,
    # each counting only its own): `{ target => count }`.
    def left_out(page_id, shown: LISTED_IN_VIEW)
      posts_of(page_id).drop(shown).group_by { |post_id| target_of(page_id, post_id) }.transform_values(&:size)
    end

    def left_out_of(page_id, target, shown: LISTED_IN_VIEW)
      posts_of(page_id).drop(shown).select { |post_id| target_of(page_id, post_id) == target }
    end

    # The filter of the page's first list block, or of the first that points
    # at `target`: what "Open in Posts" filters the Posts screen by.
    def filter_of(page_id, target = nil)
      all = @settings.fetch(page_id, [])
      settings = (target ? all.find { |candidate| target(candidate) == target } : all.first) or return {}
      { type: settings.content_type.presence&.to_s, tag: settings.tag.to_s.strip.presence }
    end

    def type_count(name) = (@type_counts ||= @post_rows.map { |_id, type, *| type }.tally).fetch(name.to_s, 0)
    def post_count = @post_count ||= @post_rows.count { |_id, type, *| ContentTypes.find(type) }

    private

    def target(settings)
      type, tag = self.class.key(settings)
      if tag then (id = @tag_id[tag]) && PostGraph.node_id(:tag, id)
      elsif type then PostGraph.node_id(:type, type)
      else ALL_POSTS
      end
    end

    def listed = @listed ||= @settings.keys.flat_map { |page_id| posts_of(page_id) }.to_set

    def matching(settings)
      (@matching ||= {})[self.class.key(settings)] ||= @post_rows.filter_map do |id, content_type, *|
        names = @tags_of.fetch(id, []).filter_map { |tag_id| @tag_name[tag_id] }
        id if BlockTypes::PostList.matches?(settings, content_type: content_type, tag_names: names)
      end
    end

    def newest_first(ids) = ids.sort_by { |id| [ -@recency.fetch(id), -id ] }
  end
end
```

  (`@tag_name` holds only the tags a block names, lower-cased: all the criteria compare a post's tags with.) Run the file; expected PASS.

- [ ] **Step 9: the site's failing test.** Create `test/queries/post_graph/site_test.rb`:

```ruby
require "test_helper"

# `PostGraph::Site`: what every view of the mind graph loads once.
class PostGraph::SiteTest < ActiveSupport::TestCase
  def limit_author_to(page)
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ page.id ] })
  end

  test "it holds the readable posts, their tag links, the readable pages in tree order, and the listings" do
    blog = create_page(title: "Blog")
    child = create_page(title: "Child", parent: blog)
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 0, settings: { "tag" => "ruby" })
    post = create_post(title: "A", tags: [ "ruby" ])
    tag = Tag.find_by!(name: "ruby")

    site = PostGraph::Site.load(actor: nil)

    assert_equal [ [ post.id, "blog" ] ], site.post_rows.map { |row| row.first(2) }
    assert_equal [ [ tag.id, post.id ] ], site.tag_links
    assert_equal({ tag.id => 1 }, site.tag_counts)
    assert_equal [ root_page.id, blog.id, child.id ], site.pages.map(&:id)
    assert_equal root_page, site.home
    assert_equal blog.id, site.tree.parent(child.id)
    assert_equal [ [ blog.id, "tag-#{tag.id}" ] ], site.listings.edges
    assert_equal post.updated_at.to_i, site.stamps[post.id].to_i
    assert_nil site.page(0)
  end

  test "a trashed page, a trashed post and what is outside the viewer's scope are not in it" do
    kept = create_page(title: "Kept")
    hidden = create_page(title: "Hidden")
    gone = create_page(title: "Gone")
    gone.update_column(:trashed_at, Time.current)
    ContentBlock.create!(owner: hidden, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    create_post(title: "Binned").update_column(:trashed_at, Time.current)
    limit_author_to(kept)

    site = as(users(:author)) { PostGraph::Site.load(actor: users(:author)) }

    assert_equal [ kept.id ], site.pages.map(&:id)
    assert_nil site.home, "Home is outside the branch this viewer reads"
    assert_nil site.tree.parent(kept.id)
    assert_empty site.listings.edges, "a line of a page the viewer cannot read"
    assert_empty site.post_rows.map(&:first) & Post.trashed.pluck(:id)
  end

  test "it costs five statements, with 3 pages and posts and with 30" do
    viewer = users(:one)
    build = ->(count) do
      count.times do |index|
        page = create_page(title: "Page #{count}-#{index}")
        ContentBlock.create!(owner: page, block_type: :post_list, position: 0, settings: { "tag" => "ruby" })
        create_post(title: "Post #{count}-#{index}", tags: [ "ruby" ])
      end
    end

    build.call(3)
    few = capture_sql { PostGraph::Site.load(actor: viewer) }
    build.call(27)
    many = capture_sql { PostGraph::Site.load(actor: viewer) }

    assert_equal 5, few.size, few.join("\n")
    assert_equal 5, many.size, many.join("\n")
  end
end
```

  Run it; expected FAIL with `uninitialized constant PostGraph::Site`. (If the fixtures' `author` group reads posts only as their owner, the second test's last line still holds; read `test/fixtures/access_control/grants.yml` and say in the test's comment what the author reads.)

- [ ] **Step 10: the site.** Create `app/queries/post_graph/site.rb`:

```ruby
# What every view of the mind graph loads once (pages in the mind graph, spec
# §1): the posts and pages THIS viewer may read, and what follows from them
# without another statement.
#
# Everything the graph shows is derived from these rows, so nothing can count
# or name a page or a post outside the scope, or a trashed one, which
# `AccessControl.scope` leaves out. THE ROWS, NOT THE PUBLISHED COPIES (spec
# decision 3): CS Studio is the editors' view, and a line a live page's
# unpublished block adds is drawn, with the page's own mark saying so.
#
# Five statements whatever the size: the readable posts (four columns, never
# a body), their tag links, the readable pages (`PAGE_COLUMNS`), and
# `Listings`' two.
module PostGraph
  class Site
    PAGE_COLUMNS = %i[id title parent_id position published_at unpublished_changes_at].freeze

    attr_reader :readable_posts, :post_rows, :tag_links, :tag_counts, :pages, :tree, :listings

    def self.load(actor:) = new(actor)

    def initialize(actor)
      @readable_posts = AccessControl.scope(actor, "posts.read", Post.all)
      @post_rows = @readable_posts.pluck(:id, :content_type, :published_at, :updated_at)
      @tag_links = PostTag.where(post_id: @readable_posts.select(:id)).order(:tag_id, :post_id).pluck(:tag_id, :post_id)
      @tag_counts = @tag_links.group_by(&:first).transform_values(&:size)
      pages = AccessControl.scope(actor, "pages.read", Page.all).select(*PAGE_COLUMNS).to_a
      @tree = Tree.new(pages.map { |page| [ page.id, page.parent_id, page.position ] })
      @pages = pages.sort_by { |page| @tree.rank(page.id) }
      @by_id = @pages.index_by(&:id)
      @listings = Listings.new(page_ids: @pages.map(&:id), post_rows: @post_rows, tag_links: @tag_links)
    end

    def page(id) = @by_id[id]
    def home = @by_id[@tree.home_id]
    def stamps = @stamps ||= @post_rows.to_h { |id, _type, _published_at, updated_at| [ id, updated_at ] }
  end
end
```

  Run: `PGGSSENCMODE=disable bin/rails test test/queries/post_graph`; expected PASS.

- [ ] **Step 11: the source guard.** Create `test/lib/mind_graph_guards_test.rb`:

```ruby
require "test_helper"

# Two rules of the mind graph that nothing else would catch (pages in the
# mind graph, spec §4 and decision 3). A node's publishing state is
# `Publishing::State`'s: no query and no script compares `published_at` with
# a clock or with nothing. And the graph shows the rows: no query reads a
# published copy.
class MindGraphGuardsTest < ActiveSupport::TestCase
  FILES = (Dir[Rails.root.join("app/queries/post_graph.rb")] + Dir[Rails.root.join("app/queries/post_graph/**/*.rb")] +
           Dir[Rails.root.join("app/javascript/mind_graph/**/*.js")]).freeze
  COMPARES = /published_?at\s*(?:[<>]=?|[!=]==?|\.(?:nil|present|blank|past|future|before|after)\?)|published_?at\s*\)?\s*(?:<|>)|Date\.now\(\)\s*[<>]/i
  COPIES = /Publishing\.published\b|published_all|Publishing::Listing|Publishing\.current\b/

  def code_lines
    FILES.flat_map do |path|
      File.readlines(path).each_with_index.reject { |line, _| line.match?(%r{\A\s*(#|//)}) }
          .map { |line, index| [ "#{Pathname(path).relative_path_from(Rails.root)}:#{index + 1}", line ] }
    end
  end

  test "no query and no script of the mind graph compares published_at: a node's state is Publishing::State's" do
    assert_operator FILES.size, :>, 10
    assert_empty code_lines.select { |_where, line| line.match?(COMPARES) }.map(&:first)
  end

  test "the mind graph reads the rows: no query of it reads a published copy" do
    assert_empty code_lines.select { |_where, line| line.match?(COPIES) }.map(&:first)
  end

  test "the patterns can fail" do
    [ "post.published_at.nil?", "if page.published_at > now", "node.publishedAt < Date.now()", "record.published_at == nil" ].each { |line| assert_match COMPARES, line }
    assert_no_match COMPARES, "(published_at || updated_at).to_f"
    [ "Publishing.published(page)", "Publishing.published_all(records)", "Publishing::Listing.call" ].each { |line| assert_match COPIES, line }
  end
end
```

  Run: `PGGSSENCMODE=disable bin/rails test test/lib/mind_graph_guards_test.rb`; expected PASS (the builder asks `post.status` today and compares nothing).

- [ ] **Step 12: the guards that read every source.**

  Run: `PGGSSENCMODE=disable bin/rails test test/lib test/services/service_contract_test.rb && bin/rubocop app/queries/post_graph app/models/block_types/post_list.rb app/values/publishing/state.rb test/queries/post_graph test/lib/mind_graph_guards_test.rb && bin/rails zeitwerk:check`
  Expected: PASS, no offences, "All is good!".

- [ ] **Step 13: commit.**

```bash
git add app/queries/post_graph.rb app/queries/post_graph app/models/block_types/post_list.rb app/values/publishing/state.rb test/queries/post_graph test/lib/mind_graph_guards_test.rb test/values/publishing/state_test.rb test/models/block_types
git commit -m "feat: what a page lists, worked out once for the mind graph — the tree, the listings and the site in five statements"
```

---

### Task 3: the global graph holds pages, post types, the two new lines and every node's state

The data changes; the screen draws what it drew. The script is told to leave out a line whose end it does not know (one line, removed again in Task 5).

**Files:**
- Modify: `app/queries/post_graph/builder.rb` (rewritten), `app/queries/post_graph/global.rb`, `app/queries/post_graph/local.rb` (it calls the new builder; its walk is Task 4's), `app/queries/post_graph.rb` (the header's shape), `app/controllers/admin/mind_graph_controller.rb`, `app/views/admin/mind_graph/show.html.erb` (one condition), `app/javascript/mind_graph/app.js` (one line)
- Test: `test/queries/post_graph/global_test.rb`, `test/queries/post_graph/local_test.rb`, `test/integration/admin/mind_graph_data_test.rb`, `test/integration/admin/mind_graph_test.rb`, `test/integration/trash_visibility_test.rb`

**Interfaces:**
- Consumes: `PostGraph::Site`, `Tree`, `Listings`, `PostGraph.paths`, the constants, `Publishing::State.of(record, now:, pending_at:)` (Task 2).
- Produces:

```ruby
PostGraph::Builder.new(site:, locale:, url_for:, now: Time.current)
  #plan(post_ids:, relations:, tag_links:, tag_counts:, min_tag_edges:, page_ids: [], lists: [], brought: [], keep_tag: nil, more: [])
       # => Builder::Plan; NO statement. plan.edges is every line of the response.
       #    lists: [[page_id, target], …]   brought: [[target, post_id], …]   more: [{ page_id:, target:, count: }, …]
  #build(plan)   # => { nodes:, tags:, pages:, types:, edges: } (+ more: [ … ] when there is a pill); seven statements
  #post_nodes(post_ids, degree: {}, related_count: {}, tag_count: {})   # => [post node, …] by id; three statements

PostGraph::Global.call(actor:, url_for:, locale: Locales.default, cap: CAP, everything: false, open_above: OPEN_AROUND_HOME_ABOVE)
  # => { nodes:, tags:, pages:, types:, edges:, total:, shown:, isolated: }
  #    or { open: "page-<home id>", edges: N } when the plan holds more than `open_above` lines, a readable Home exists and `everything` is false
```

The payload, exactly:

```
nodes[]:  { id: "post-<id>", title, type, colour_index, status: "draft"|"scheduled"|"live", changes: nil|"unpublished"|"scheduled",
            change_at: Time|nil, listed: true|false, url, degree, related_count, tag_count, open_notes }
tags[]:   { id: "tag-<id>", name, count, degree }
pages[]:  { id: "page-<id>", title, path: "/about"|nil, depth, home: true|false, parent: "page-<id>"|nil, order, status, changes, change_at,
            url, degree, child_count, listed_count, open_notes }                      in tree order
types[]:  { id: "type-<name>"|"all-posts", name: "<stored name>"|nil, label: "<the type's label, or its stored name>"|nil,
            colour_index: Integer|nil, count, degree }                                colour-slot order, then retired types by name, "all-posts" LAST (design answer H2: the list's order)
edges[]:  { source, target, kind: "related"|"tag"|"tree"|"lists"|"brings" }
          tree: child -> parent; lists: page -> tag | type | all-posts
          brings: type | all-posts -> post, and type | all-posts | tag -> its "more-<target>"   only in a page's local view (Task 4)
more:     [{ id: "more-<target>", count, page: "page-<id>", target: "type-<name>"|"all-posts"|"tag-<id>" }, …]
          one pill PER TARGET that brings in more than the view draws; only in a page's local view (Task 4), and no key at all without one
```

`changes` is `"unpublished"` for `Publishing::State#state == :live_with_changes`, `"scheduled"` for `:live_change_scheduled`, nil otherwise: with `status` it names each of the five looks. `change_at` is the time the scheduled change comes into force (the pending copy's `live_at`) in that last state and nil in every other; the query hands up the time and no words, and the controller adds `change_on`, the same day as CS Studio's short date ("14 Oct"), to every node that has one, for the card's chip (design answer G4). A type with no `colour_index` that is not "all-posts" is a retired one: the script draws its hub by that (design answer G1), and no key says so twice. `url_for:` is called with a `Post` or a `Page`.

**A `brings` line** (the third design answers, "Local view lines"): in a page's local view the hub that brings a post in draws a faint line to it, and each "+N more" hangs off its own hub the same way, one pill per target (design answer H1); no lists line joins the page to a post. The whole graph has none: there a type node joins only pages.

- [ ] **Step 1: the failing tests of the global view.** In `test/queries/post_graph/global_test.rb` add the helper

```ruby
  def list_block(page, **settings)
    ContentBlock.create!(owner: page, block_type: :post_list, position: page.content_blocks.count, settings: settings.stringify_keys)
  end

  def page_id(page) = "page-#{page.id}"
```

  change `graph` to pass the new options through (`def graph(actor: nil, cap: PostGraph::CAP, **options) = PostGraph::Global.call(actor: actor, cap: cap, url_for: ->(record) { "/cs-studio/#{record.class.name.underscore.pluralize}/#{record.id}" }, **options)`), add `changes: nil, change_at: nil, listed: false` to the expected hash of `"a connected post is a node with its title, …"`, and add these tests:

```ruby
  test "every readable page is a node, in tree order, with its path, depth, parent and counts" do
    home = root_page
    blog = create_page(title: "Blog")
    child = create_page(title: "Child", parent: blog)
    list_block(blog, content_type: "blog")
    create_post(title: "A")
    as(users(:two)) { Notes::Start.call(blog, body: "A note") }

    pages = graph[:pages]

    assert_equal [ page_id(home), page_id(blog), page_id(child) ], pages.map { |page| page[:id] }
    assert_equal({ id: page_id(blog), title: "Blog", path: "/blog", depth: 1, home: false, parent: page_id(home), order: 1, status: "live",
                   url: "/cs-studio/pages/#{blog.id}", degree: 3, child_count: 1, listed_count: 1, open_notes: 1 }, pages[1].except(:changes, :change_at))
    assert_equal [ true, nil, 0, 1 ], pages[0].values_at(:home, :parent, :depth, :child_count)
  end
```

  (`degree: 3`: its tree line to Home, its child's, its lists line. `changes` and `change_at` are left out here, since whether a block created around the services marks its page is not this test's business; the test of the five states below sets the facts itself. If `create_page` gives "Blog" another address than `/blog`, read it from `PublicPath.current.where(record: blog).pick(:path)`.)

```ruby
  test "a tree line joins a page to its parent, and a lists line a page to its tag, its type or All posts" do
    home = root_page
    by_tag = create_page(title: "By tag")
    by_type = create_page(title: "By type")
    list_block(home)
    list_block(by_tag, tag: "ruby")
    list_block(by_type, content_type: "resume_entry")
    create_post(title: "A", tags: [ "ruby" ])
    tag = "tag-#{Tag.find_by!(name: "ruby").id}"

    result = graph
    lines = result[:edges].reject { |edge| %w[related tag].include?(edge[:kind]) }

    assert_equal [ { source: page_id(by_tag), target: page_id(home), kind: "tree" }, { source: page_id(by_type), target: page_id(home), kind: "tree" },
                   { source: page_id(home), target: "all-posts", kind: "lists" }, { source: page_id(by_tag), target: tag, kind: "lists" },
                   { source: page_id(by_type), target: "type-resume_entry", kind: "lists" } ].sort_by(&:to_s), lines.sort_by(&:to_s)
    assert_equal [ "type-resume_entry", "all-posts" ], result[:types].map { |type| type[:id] }, "All posts is last"
    assert_equal({ id: "type-resume_entry", name: "resume_entry", label: ContentTypes.fetch("resume_entry").label,
                   colour_index: ContentTypes.fetch("resume_entry").colour_index, count: 0, degree: 1 }, result[:types].first)
    assert_equal({ id: "all-posts", name: nil, label: nil, colour_index: nil, count: 1, degree: 1 }, result[:types].last)
  end

  test "a type node joins only the pages that list it, never a post of its type" do
    list_block(create_page(title: "Blog"), content_type: "blog")
    a = create_post(title: "A")
    relate(a, create_post(title: "B"))

    result = graph
    ends = result[:edges].select { |edge| [ edge[:source], edge[:target] ].include?("type-blog") }

    assert_equal [ "lists" ], ends.map { |edge| edge[:kind] }
    assert ends.all? { |edge| edge[:source].start_with?("page-") }
    assert_empty result[:edges].select { |edge| edge[:kind] == "brings" }, "a hub's lines to its posts are a page's local view's, never the whole graph's"
  end

  test "one All posts node however many pages list everything" do
    3.times { |index| list_block(create_page(title: "All #{index}")) }

    result = graph

    assert_equal 1, result[:types].count { |type| type[:id] == "all-posts" }
    assert_equal 3, result[:types].last[:degree]
  end

  test "a listed tag is a node whenever its page is readable, and the one post that carries it is drawn" do
    list_block(create_page(title: "Ruby"), tag: "ruby")
    post = create_post(title: "Only one", tags: [ "ruby" ])
    tag = Tag.find_by!(name: "ruby")

    result = graph

    assert_equal [ { id: "tag-#{tag.id}", name: "ruby", count: 1, degree: 2 } ], result[:tags], "one readable post carries it: the count stays the readable posts"
    assert_equal [ pid(post) ], result[:nodes].map { |node| node[:id] }
    assert_equal 0, result[:isolated]
  end

  test "a listed tag no readable post carries is still a node, with a count of nothing" do
    list_block(create_page(title: "Empty"), tag: "empty")
    tag = Tag.create!(name: "empty")

    assert_equal [ { id: "tag-#{tag.id}", name: "empty", count: 0, degree: 1 } ], graph[:tags]
  end

  test "a lists line is not a post's connection: a post only a page lists is still isolated, and a drawn post says whether a page lists it" do
    list_block(create_page(title: "Blog"), content_type: "blog")
    a = create_post(title: "A")
    relate(a, create_post(title: "B"))
    create_post(title: "Alone")
    entry = create_post(title: "Entry", content_type: "resume_entry")
    relate(entry, a)

    result = graph

    assert_equal 1, result[:isolated]
    assert_equal({ pid(a) => true, pid(entry) => false }, result[:nodes].to_h { |node| [ node[:id], node[:listed] ] }.slice(pid(a), pid(entry)))
  end

  test "a retired type a block names is a type node with no colour" do
    list_block(create_page(title: "Old"), content_type: "gone/thing")

    assert_equal [ { id: "type-gone/thing", name: "gone/thing", label: "gone/thing", colour_index: nil, count: 0, degree: 1 } ], graph[:types]
  end

  # Design answer H2: the order the list's "Post types" group shows.
  test "post types come in colour-slot order, then the retired ones, then All posts last" do
    page = create_page(title: "Lists")
    list_block(page)
    list_block(page, content_type: "zz/gone")
    list_block(page, content_type: "aa/gone")
    ContentTypes.names.each { |name| list_block(page, content_type: name.to_s) }

    registered = ContentTypes.names.map(&:to_s).sort_by { |name| ContentTypes.fetch(name).colour_index }.map { |name| "type-#{name}" }

    assert_equal registered + [ "type-aa/gone", "type-zz/gone", "all-posts" ], graph[:types].map { |type| type[:id] }
  end
```

  The state, for every combination the state's own test lists, on a page and on a post:

```ruby
  test "status and changes are Publishing::State's, for a page and a post, in each of the five states, and only a scheduled change has its time" do
    looks = { draft: [ "draft", nil ], scheduled: [ "scheduled", nil ], live: [ "live", nil ],
              live_with_changes: [ "live", "unpublished" ], live_change_scheduled: [ "live", "scheduled" ] }
    facts = { draft: [ nil, false, false ], scheduled: [ 3.days.from_now, false, false ], live: [ 1.day.ago, false, false ],
              live_with_changes: [ 1.day.ago, false, true ], live_change_scheduled: [ 1.day.ago, true, true ] }
    records = facts.to_h do |state, (time, pending, mark)|
      page = create_page(title: "Page #{state}")
      post = create_post(title: "Post #{state}", tags: [ "t" ])
      [ page, post ].each do |record|
        Publishing::Version.take!(record, live_at: 2.days.from_now) if pending
        record.update_columns(published_at: time, unpublished_changes_at: (Time.current if mark)) # version: none (a test sets the facts a state is derived from) # changes: none (a test sets the facts a state is derived from)
      end
      [ state, [ page, post ] ]
    end

    result = graph

    records.each do |state, (page, post)|
      assert_equal state, Publishing::State.of(page.reload).state
      assert_equal looks[state], result[:pages].find { |node| node[:id] == page_id(page) }.values_at(:status, :changes), "page #{state}"
      assert_equal looks[state], result[:nodes].find { |node| node[:id] == pid(post) }.values_at(:status, :changes), "post #{state}"
      times = [ result[:pages].find { |node| node[:id] == page_id(page) }, result[:nodes].find { |node| node[:id] == pid(post) } ].map { |node| node[:change_at] }
      if state == :live_change_scheduled
        times.each { |at| assert_in_delta 2.days.from_now.to_f, at.to_f, 60, "the pending copy's live_at" }
      else
        assert_equal [ nil, nil ], times, state.to_s
      end
    end
  end
```

  Rights and the trash:

```ruby
  test "a page whose parent is outside the scope is drawn without a tree line and names no parent" do
    hidden = create_page(title: "Hidden")
    seen = create_page(title: "Seen", parent: hidden)
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ seen.id ] })

    result = as(users(:author)) { graph(actor: users(:author)) }

    assert_equal [ page_id(seen) ], result[:pages].map { |page| page[:id] }
    assert_equal [ nil, 1, false ], result[:pages].first.values_at(:parent, :depth, :home)
    assert_empty result[:edges].select { |edge| edge[:kind] == "tree" }
    assert_no_match(/page-#{hidden.id}\b/, result.to_json)
  end

  test "a tag only an unreadable page lists is no node, and the page's lines are gone with it" do
    hidden = create_page(title: "Hidden")
    seen = create_page(title: "Seen")
    list_block(hidden, tag: "secret")
    list_block(hidden, content_type: "resume_entry")
    Tag.create!(name: "secret")
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ seen.id ] })

    result = as(users(:author)) { graph(actor: users(:author)) }

    assert_empty result[:tags]
    assert_empty result[:types]
    assert_empty result[:edges]
  end

  test "a trashed page is no node, its lines are gone, and its child is drawn without a line to it" do
    gone = create_page(title: "Gone")
    child = create_page(title: "Child", parent: gone)
    list_block(gone, content_type: "blog")
    Page.where(id: gone.id).update_all(trashed_at: Time.current) # version: none (a test trashes one page and leaves its child) # changes: none (a test trashes one page)

    result = graph

    assert_equal [ page_id(root_page), page_id(child) ], result[:pages].map { |page| page[:id] }
    assert_nil result[:pages].last[:parent]
    assert_empty result[:edges]
    assert_empty result[:types]
  end
```

  The 3,000-line rule and the cost (the old `"the global graph costs six statements"` is replaced by the first of these):

```ruby
  test "the global graph costs thirteen statements" do
    page = create_page(title: "Blog")
    list_block(page, tag: "shared")
    a = create_post(title: "A", tags: %w[shared])
    relate(a, create_post(title: "B", tags: %w[shared]))
    as(users(:two)) { Notes::Start.call(a, body: "A note"); Notes::Start.call(page, body: "A note") }
    viewer = users(:one) # loaded here, so the fixture's own read is not counted

    statements = capture_sql { graph(actor: viewer) }

    # The site's five (posts, tag links, pages, list blocks, the tags they
    # name), the relations, and the builder's seven (the tags' names; the
    # pages' paths, notes and pending copies; the posts' notes, pending
    # copies and rows).
    assert_equal 13, statements.size, statements.join("\n")
  end

  test "the statement count is the same for 3 pages and for 30, and for 3 posts and for 30" do
    viewer = users(:one)
    pages = ->(count) { count.times { |index| list_block(create_page(title: "Page #{count}-#{index}"), tag: "shared") } }
    posts = ->(count) { count.times { |index| create_post(title: "Post #{count}-#{index}", tags: %w[shared]) } }
    pages.call(3)
    posts.call(3)
    few = capture_sql { graph(actor: viewer) }.size

    pages.call(27)
    more_pages = capture_sql { graph(actor: viewer) }.size
    posts.call(27)
    more_posts = capture_sql { graph(actor: viewer) }.size

    assert_equal [ few, few ], [ more_pages, more_posts ]
  end

  test "above the threshold the answer is where to open, with the number of lines, and no graph" do
    home = root_page
    3.times { |index| create_page(title: "Page #{index}") }
    Tag.create!(name: "listed")
    list_block(home, tag: "listed")

    statements = capture_sql { @answer = graph(open_above: 3) }

    assert_equal({ open: page_id(home), edges: 4 }, @answer, "three tree lines and one lists line")
    assert_equal 6, statements.size, "the site's five and the relations: no node is built"
    assert_equal 4, graph(open_above: 4)[:edges].size, "exactly the threshold is not above it"
  end

  test "everything=1 answers the whole graph whatever its size" do
    3.times { |index| create_page(title: "Page #{index}") }

    assert_equal 4, graph(open_above: 2, everything: true)[:pages].size
  end

  test "over the threshold without a readable Home the whole graph is answered" do
    branch = create_page(title: "Branch")
    3.times { |index| create_page(title: "Leaf #{index}", parent: branch) }
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ branch.id ] })

    result = as(users(:author)) { graph(actor: users(:author), open_above: 2) }

    assert_nil result[:open]
    assert_equal 4, result[:pages].size
  end

  test "over the threshold with no page at all the graph of posts is answered" do
    assert_not Page.exists?, "this test is about a site with no page: `create_post` makes none"
    a = create_post(title: "A")
    relate(a, create_post(title: "B"))

    result = graph(open_above: 0)

    assert_nil result[:open]
    assert_equal [ [], 1 ], [ result[:pages], result[:edges].size ]
  end
```

  Run: `PGGSSENCMODE=disable bin/rails test test/queries/post_graph/global_test.rb`; expected FAIL: `unknown keyword: :open_above`, and `nil` for `graph[:pages]`.

- [ ] **Step 2: the builder.** Replace `app/queries/post_graph/builder.rb`. Keep its header comment and add what is new to it (the five kinds of node, `plan` and `build`, seven statements, the two halves of a post's degree, and that a `brings` line is a page's local view's alone):

```ruby
module PostGraph
  class Builder
    COLUMNS = %i[id title content_type published_at unpublished_changes_at].freeze
    # The two looks of a live record that the cheap status does not tell
    # apart (spec §4): the rows have moved on, or a change is scheduled.
    CHANGES = { live_with_changes: "unpublished", live_change_scheduled: "scheduled" }.freeze

    Plan = Struct.new(:post_ids, :page_ids, :related, :by_tag, :tag_counts, :lists, :more, :edges, keyword_init: true)

    def initialize(site:, locale:, url_for:, now: Time.current)
      @site = site
      @locale = locale
      @url_for = url_for
      @now = now
    end

    # WHICH LINES the response holds, from what the caller has loaded: no
    # statement. `Global` counts `plan.edges` before any node is built (spec
    # decision 6). The callers decide which posts, pages and lists lines;
    # this decides nothing about access.
    # - `lists`: `[[page_id, target], …]`, already narrowed to the pages
    #   drawn and, in a local view, to the targets the walk reached. A tag a
    #   lists line points at is a node whatever its count.
    # - `brought`: `[[target, post_id], …]`, a page's local view only: the hub
    #   (a post type or "All posts") that brings a drawn post in draws a
    #   faint line to it, so the post does not float loose (third design
    #   answers). The caller leaves out a post a TAG brings in: its "tag"
    #   line to that tag is among `tag_links` already, and two lines between
    #   the same two nodes would be one drawn twice.
    # - `more`: `[{ page_id:, target:, count: }, …]`, ONE "+N more" PILL PER
    #   TARGET (design answer H1), each hanging off its own hub or tag by the
    #   same faint line and counting only what that target brings in.
    # - a tree line needs both pages drawn, and the parent readable (`Tree`).
    def plan(post_ids:, relations:, tag_links:, tag_counts:, min_tag_edges:, page_ids: [], lists: [], brought: [], keep_tag: nil, more: [])
      drawn = post_ids.to_set
      pages = page_ids.to_set
      related = relations.select { |post_id, related_id| drawn.include?(post_id) && drawn.include?(related_id) }
      kept_tags = lists.filter_map { |_page_id, target| target.delete_prefix("tag-").to_i if target.start_with?("tag-") }.to_set
      kept_tags << keep_tag if keep_tag
      by_tag = tag_links.select { |_tag_id, post_id| drawn.include?(post_id) }.group_by(&:first)
      by_tag.select! { |tag_id, rows| kept_tags.include?(tag_id) || (tag_counts.fetch(tag_id, 0) >= MIN_TAGGED_POSTS && rows.size >= min_tag_edges) }
      kept_tags.each { |tag_id| by_tag[tag_id] ||= [] }
      tree = page_ids.filter_map { |id| (parent = @site.tree.parent(id)) && pages.include?(parent) ? [ id, parent ] : nil }

      post = ->(id) { PostGraph.node_id(:post, id) }
      page = ->(id) { PostGraph.node_id(:page, id) }
      edges = related.map { |post_id, related_id| { source: post.call(post_id), target: post.call(related_id), kind: "related" } } +
              by_tag.flat_map { |tag_id, rows| rows.map { |_tag_id, post_id| { source: post.call(post_id), target: PostGraph.node_id(:tag, tag_id), kind: "tag" } } } +
              tree.map { |id, parent| { source: page.call(id), target: page.call(parent), kind: "tree" } } +
              lists.map { |page_id, target| { source: page.call(page_id), target: target, kind: "lists" } } +
              brought.map { |target, post_id| { source: target, target: post.call(post_id), kind: "brings" } } +
              more.map { |pill| { source: pill[:target], target: PostGraph.node_id(MORE, pill[:target]), kind: "brings" } }
      Plan.new(post_ids: post_ids, page_ids: page_ids, related: related, by_tag: by_tag, tag_counts: tag_counts, lists: lists, more: more, edges: edges)
    end

    def build(plan)
      names = Tag.where(id: plan.by_tag.keys).pluck(:id, :name).to_h
      # A tag deleted between the two statements: no node, and no line to it.
      gone = (plan.by_tag.keys - names.keys).to_set { |tag_id| PostGraph.node_id(:tag, tag_id) }
      edges = gone.empty? ? plan.edges : plan.edges.reject { |edge| gone.include?(edge[:target]) || gone.include?(edge[:source]) }
      degree = Hash.new(0)
      edges.each { |edge| degree[edge[:source]] += 1; degree[edge[:target]] += 1 }
      related_count = Hash.new(0)
      plan.related.each { |post_id, related_id| related_count[post_id] += 1; related_count[related_id] += 1 }
      tag_count = Hash.new(0)
      plan.by_tag.each { |tag_id, rows| rows.each { |_tag_id, post_id| tag_count[post_id] += 1 } if names.key?(tag_id) }

      graph = {
        nodes: post_nodes(plan.post_ids, degree: degree, related_count: related_count, tag_count: tag_count),
        tags: names.map { |tag_id, name| tag_node(tag_id, name, plan, degree) }.sort_by { |tag| [ tag[:name].to_s.downcase, tag[:id] ] },
        pages: page_nodes(plan.page_ids, degree),
        types: type_nodes(plan.lists, degree),
        edges: edges
      }
      pills = plan.more.reject { |pill| gone.include?(pill[:target]) }
      graph[:more] = pills.map { |pill| { id: PostGraph.node_id(MORE, pill[:target]), count: pill[:count], page: PostGraph.node_id(:page, pill[:page_id]), target: pill[:target] } } if pills.any?
      graph
    end

    # A post's node, for each id handed in (already narrowed by the read
    # scope, which leaves the trash out). Three statements whatever the
    # number: the posts' open threads, their pending copies, and the posts
    # with the columns a node is made from. `PostGraph::Rows` asks for it
    # with no counts: a row that is not drawn has no line yet.
    def post_nodes(post_ids, degree: {}, related_count: {}, tag_count: {})
      notes = Notes::Counts.by_container("Post", post_ids.to_a)
      pending = pending_copies("Post", post_ids)
      Post.where(id: post_ids).select(*COLUMNS).order(:id).map do |post|
        id = PostGraph.node_id(:post, post.id)
        state = Publishing::State.of(post, now: @now, pending_at: pending[post.id])
        {
          id: id,
          title: Locales.read(post, :title, locale: @locale),
          type: post.content_type,
          colour_index: post.definition&.colour_index,
          status: state.status,
          changes: CHANGES[state.state],
          change_at: (pending[post.id] if state.state == :live_change_scheduled),
          listed: @site.listings.listed?(post.id),
          url: @url_for.call(post),
          degree: degree.fetch(id, 0),
          related_count: related_count.fetch(post.id, 0),
          tag_count: tag_count.fetch(post.id, 0),
          open_notes: notes.fetch(post.id, 0)
        }
      end
    end

    private

    def tag_node(tag_id, name, plan, degree)
      id = PostGraph.node_id(:tag, tag_id)
      { id: id, name: name, count: plan.tag_counts.fetch(tag_id, plan.by_tag[tag_id].size), degree: degree.fetch(id, 0) }
    end

    # The pages are the site's own, loaded once; what is read here is their
    # address, their open threads and their pending copies: three statements.
    def page_nodes(page_ids, degree)
      paths = PostGraph.paths(page_ids, locale: @locale)
      notes = Notes::Counts.by_container("Page", page_ids)
      pending = pending_copies("Page", page_ids)
      tree = @site.tree
      page_ids.sort_by { |page_id| tree.rank(page_id) }.map do |page_id|
        record = @site.page(page_id)
        id = PostGraph.node_id(:page, page_id)
        parent = tree.parent(page_id)
        state = Publishing::State.of(record, now: @now, pending_at: pending[page_id])
        {
          id: id,
          title: Locales.read(record, :title, locale: @locale),
          path: paths[page_id],
          depth: tree.depth(page_id),
          home: page_id == tree.home_id,
          parent: parent && PostGraph.node_id(:page, parent),
          order: tree.rank(page_id),
          status: state.status,
          changes: CHANGES[state.state],
          change_at: (pending[page_id] if state.state == :live_change_scheduled),
          url: @url_for.call(record),
          degree: degree.fetch(id, 0),
          child_count: tree.children(page_id).size,
          listed_count: @site.listings.listed_count(page_id),
          open_notes: notes.fetch(page_id, 0)
        }
      end
    end

    # A post type a drawn lists line points at, and the one "All posts"
    # node. No statement: the counts are the site's readable posts. In the
    # order the list shows them (design answer H2): the types by their
    # colour slot (the order in Settings), then the retired ones by name,
    # then "All posts" last.
    def type_nodes(lists, degree)
      targets = lists.map(&:last).uniq.reject { |target| target.start_with?("tag-") }
      place = ->(target) do
        next [ 2, 0, "" ] if target == ALL_POSTS

        slot = ContentTypes.find(target.delete_prefix("type-"))&.colour_index
        slot ? [ 0, slot, target ] : [ 1, 0, target ]
      end
      targets.sort_by(&place).map do |target|
        if target == ALL_POSTS
          { id: ALL_POSTS, name: nil, label: nil, colour_index: nil, count: @site.listings.post_count, degree: degree.fetch(target, 0) }
        else
          name = target.delete_prefix("type-")
          definition = ContentTypes.find(name)
          { id: target, name: name, label: definition&.label || name, colour_index: definition&.colour_index, count: @site.listings.type_count(name), degree: degree.fetch(target, 0) }
        end
      end
    end

    # `{ record_id => live_at }` of the copies waiting for their time: the
    # fifth state, asked once for every node of a kind, and the time a node
    # in that state hands up as `change_at` (the card's chip says the day).
    def pending_copies(type, ids) = Publishing::Version.pending(@now).where(record_type: type, record_id: ids.to_a).pluck(:record_id, :live_at).to_h
  end
end
```

  Notes for the implementer: (a) `Notes::Counts.by_container` answers `{}` without a statement for no ids; the thirteen is counted with a page and a post, which every site with a graph has. (b) The retired type's test expects `count: 0` because that test creates no post of the stored type; `type_count` counts the readable posts whose stored type it is.

- [ ] **Step 3: the global view.** Replace the class body of `app/queries/post_graph/global.rb` and bring its header comment up to date (thirteen statements, named; the pages; the listed tags in the ranking; the `open` answer):

```ruby
module PostGraph
  class Global
    def self.call(...) = new(...).call

    def initialize(actor:, url_for:, locale: Locales.default, cap: CAP, everything: false, open_above: OPEN_AROUND_HOME_ABOVE)
      @actor = actor
      @locale = locale
      @url_for = url_for
      @cap = cap
      @everything = everything
      @open_above = open_above
    end

    def call
      site = Site.load(actor: @actor)
      readable = site.readable_posts.select(:id)
      relations = PostRelation.where(post_id: readable, related_post_id: readable).order(:id).pluck(:post_id, :related_post_id)
      listed_tags = site.listings.tag_ids

      # A tag a readable page lists connects the posts that carry it, however
      # few: it is a node (spec §1), so the post has a line to draw.
      weight = Hash.new(0)
      relations.each { |post_id, related_id| weight[post_id] += 1; weight[related_id] += 1 }
      site.tag_links.each { |tag_id, post_id| weight[post_id] += 1 if site.tag_counts[tag_id] >= MIN_TAGGED_POSTS || listed_tags.include?(tag_id) }

      kept = weight.keys.sort_by { |id| [ -weight[id], -site.stamps[id].to_f, id ] }.first(@cap)
      builder = Builder.new(site: site, locale: @locale, url_for: @url_for)
      plan = builder.plan(post_ids: kept, relations: relations, tag_links: site.tag_links, tag_counts: site.tag_counts, min_tag_edges: MIN_TAGGED_POSTS,
                          page_ids: site.pages.map(&:id), lists: site.listings.edges)
      # Too many lines to read as one picture: the page is told where to open
      # instead (Home's local view), and nothing more is read. Without a
      # readable Home there is nowhere to open, and the whole graph it is.
      return { open: PostGraph.node_id(:page, site.home.id), edges: plan.edges.size } if !@everything && site.home && plan.edges.size > @open_above

      builder.build(plan).merge(total: weight.size, shown: kept.size, isolated: site.post_rows.size - weight.size)
    end
  end
end
```

  In `local.rb`, so that it still runs with the new builder (its walk gains pages in Task 4), `call` becomes:

```ruby
    def call
      @site = Site.load(actor: @actor)
      @readable = @site.readable_posts.select(:id)
      walk

      post_ids = @posts.keys
      relations = PostRelation.where(post_id: post_ids, related_post_id: post_ids).order(:id).pluck(:post_id, :related_post_id)
      tag_links = @site.tag_links.select { |tag_id, post_id| @tags.key?(tag_id) && @posts.key?(post_id) }

      kept = cut(post_ids, relations, tag_links)
      builder = Builder.new(site: @site, locale: @locale, url_for: @url_for)
      plan = builder.plan(post_ids: kept, relations: relations, tag_links: tag_links, tag_counts: @site.tag_counts,
                          min_tag_edges: 1, keep_tag: (@focus.id if @focus.kind == "tag"))
      builder.build(plan).merge(total: post_ids.size, shown: kept.size,
                                focus: { kind: @focus.kind, id: @focus.id, node_id: @focus.node_id, title: @focus.title, depth: @depth })
    end
```

  (The tag links and the readable counts are the site's now, in Ruby: two statements fewer in the walk's tail, five more for the site.) In `local_test.rb` every expected node gains `changes`, `change_at` and `listed` where a whole node is compared, the result gains `pages: []` and `types: []`, and `"the number of statements depends on the depth, not on the neighbourhood's size"` needs no change: it compares two sizes and names no figure. The header comment's figure does change: three statements per depth level plus the global view's thirteen.

- [ ] **Step 4: run the query tests.**

  Run: `PGGSSENCMODE=disable bin/rails test test/queries/post_graph`
  Expected: PASS. A count other than thirteen: print the statements (the assertion's message) and compare them with the list in the test's comment before changing either.

- [ ] **Step 5: the controller, the frame's condition and the script's one line.** In `app/controllers/admin/mind_graph_controller.rb`:

```ruby
    # The screen opens for someone who may read a page or a post anywhere
    # (pages spec §2): a graph of pages alone is a graph. Each kind is then
    # narrowed by its own scope in the queries.
    before_action :require_graph_access
```

  in `show`, after `@content_types`:

```ruby
      @pages = AccessControl.scope(Current.actor, "pages.read", Page.all).exists?
```

  in `data`, the global call (the comment is part of the step):

```ruby
          # `everything: true` until the script knows the `open` answer and a
          # page's local view is drawn (pages plan, Task 8): until then the
          # whole graph is what this screen can show.
          PostGraph::Global.call(actor: Current.actor, locale: admin_locale, url_for: editor_url, everything: true)
```

  `data` ends with `render json: with_dates(graph)` where it ended with `render json: graph`, and the private part:

```ruby
    def require_graph_access
      forbidden! unless can?("pages.read") || can?("posts.read")
    end

    # A scheduled change's day as CS Studio writes a short date ("14 Oct"),
    # for the card's chip (pages spec §7, design answer G4). Wording, so it
    # is put on HERE: the queries hand up the time (`change_at`) and no words.
    # `nodes` and `pages` are the graph's, `rows` the list's two reads'; an
    # answer that holds none of them (`open`) is left as it is.
    def with_dates(answer)
      answer.merge(answer.slice(:nodes, :pages, :rows).transform_values { |nodes| nodes.map { |node| dated(node) } })
    end

    def dated(node)
      node[:change_at] ? node.merge(change_on: I18n.l(node[:change_at], format: :"admin.short")) : node
    end

    def editor_url
      ->(record) { record.is_a?(Page) ? admin_page_path(record, **admin_url_options) : admin_post_path(record, **admin_url_options) }
    end
```

  Bring the class's header comment up to date (who may open it; what `url_for` is called with). In `show.html.erb` the two places that ask `@content_types.any?` / `@content_types.empty?` ask whether there is anything to draw:

```erb
<div class="<%= "flex min-h-[560px] flex-col min-[1100px]:h-[calc(100vh_-_3rem_-_var(--admin-top-offset))]" if @content_types.any? || @pages %>">
```

```erb
<% if @content_types.empty? && !@pages %>
```

  In `app/javascript/mind_graph/app.js`, in `show`, the line that makes `state.edges`:

```js
    // A line to a node this script does not make yet (a page, a post type:
    // pages plan, Task 5) is left out, so the graph of posts and tags is the
    // one it was.
    state.edges = data.edges.map((edge) => ({ kind: edge.kind, source: indexOf.get(edge.source), target: indexOf.get(edge.target) }))
      .filter((edge) => edge.source != null && edge.target != null)
```

- [ ] **Step 6: the integration tests.** In `test/integration/admin/mind_graph_data_test.rb`:
  - `"with no focus: the global graph, with totals"`: add `assert_equal [ [], [] ], data.values_at("pages", "types")` (no page exists in that test).
  - new `"pages, post types and the two new lines are in the data, with a page's editor url"`: sign in as `users(:one)`; `blog = create_page(title: "Blog")`, a list block with `"content_type" => "blog"` (`ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })`, asserted `ok?`); `get "/cs-studio/mind_graph/data"`; assert `data["pages"].map { |page| page["id"] }` is `[ "page-#{root_page.id}", "page-#{blog.id}" ]`, `data["pages"].last["url"]` is `"/cs-studio/pages/#{blog.id}"`, `data["types"].map { |type| type["id"] }` is `[ "type-blog" ]`, and the edges hold `{ "source" => "page-#{blog.id}", "target" => "page-#{root_page.id}", "kind" => "tree" }` and `{ "source" => "page-#{blog.id}", "target" => "type-blog", "kind" => "lists" }`.
  - `"a viewer without posts.read is refused, as on the screen itself"` becomes `"a viewer with neither pages.read nor posts.read is refused, and one with pages.read alone is answered"`: remove the viewer's `pages.read` and `posts.read` grants (the test removes `posts.read` today: do the same for both) and expect 403 from the page, `data` and `search`; then with `pages.read` put back and `posts.read` still removed, `data` is a success whose `nodes` are empty and whose `pages` are not.
  - `"editor urls keep the editing language"`: also for a page (`"/cs-studio/pages/#{page.id}?lang=de"`, in the form the test already uses for a post).
  - new, in full:

```ruby
  # Design answer G4: the card's chip says the day a scheduled change comes
  # into force. The query hands up the time; the controller writes the day.
  test "a scheduled change's day is in the data as CS Studio's short date, and a node without one has no such key" do
    sign_in_as(users(:one))
    blog = create_page(title: "Blog")
    at = 3.days.from_now
    Publishing::Version.take!(blog, live_at: at)
    blog.update_columns(unpublished_changes_at: Time.current) # version: none (a test sets the facts a state is derived from) # changes: none (a test sets the facts a state is derived from)

    get "/cs-studio/mind_graph/data"
    page = data["pages"].find { |node| node["id"] == "page-#{blog.id}" }

    assert_equal [ "live", "scheduled", I18n.l(at, format: :"admin.short") ], page.values_at("status", "changes", "change_on")
    assert(data["pages"].reject { |node| node == page }.none? { |node| node.key?("change_on") })
  end
```

  In `test/integration/admin/mind_graph_test.rb`:
  - `"a viewer who can read no post sees 'No posts yet.' and no canvas, however many exist"`: the viewer of that test must also read no page; and a new test `"a viewer who reads pages and no post gets the canvas"` (pages only: `assert_select "[data-controller='admin--mind-graph--graph'] canvas"`, `assert_select "[data-mind-graph-empty]", count: 0`).

  In `test/integration/trash_visibility_test.rb`, in the Mind graph test (its setup has `@blog` with a list block, `@kept_page`, `@gone_page`): after `get "/cs-studio/mind_graph/data"` add

```ruby
    pages = response.parsed_body["pages"].map { |page| page["id"] }
    assert_includes pages, "page-#{@kept_page.id}"
    assert_not_includes pages, "page-#{@gone_page.id}"
    assert_no_match(/page-#{@gone_page.id}\b/, response.body, "a line to a trashed page, or its id as a parent")
    assert_not_includes response.body, "Gone page"
```

  and the two assertions `assert_empty response.parsed_body["edges"]` / `assert_empty data["edges"]` there and in `"the mind graph's tag nodes count kept posts only"` become assertions about the kinds they mean: `assert_empty data["edges"].select { |edge| %w[related tag].include?(edge["kind"]) }`. Add a test of its own:

```ruby
  test "a trashed page's child is drawn in the mind graph without a line to it, and a trashed page lists nothing" do
    sign_in_as users(:one)
    child = create_page(title: "Child of gone", parent: @kept_page)
    Page.where(id: @kept_page.id).update_all(trashed_at: Time.current) # version: none (a test trashes one page and leaves its child) # changes: none (a test trashes one page)
    Page.where(id: @blog.id).update_all(trashed_at: Time.current)      # version: none (a test trashes one page) # changes: none (a test trashes one page)

    get "/cs-studio/mind_graph/data"
    data = response.parsed_body

    assert_nil data["pages"].find { |page| page["id"] == "page-#{child.id}" }.fetch("parent")
    assert_empty data["edges"].select { |edge| edge["kind"] == "lists" }
    assert_empty data["types"]
    assert(data["nodes"].none? { |node| node["listed"] })
  end
```

  Run: `PGGSSENCMODE=disable bin/rails test test/integration/admin/mind_graph_data_test.rb test/integration/admin/mind_graph_test.rb test/integration/trash_visibility_test.rb test/lib`
  Expected: PASS.

- [ ] **Step 7: the browser, unchanged.**

  Run: `bin/rails tailwindcss:build && sysctl -n vm.loadavg`, then `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/mind_graph_test.rb`
  Expected: PASS with no test changed in this task: no test of that file creates a page, and a line to a page is left out.

- [ ] **Step 8: commit.**

```bash
git add app/queries/post_graph.rb app/queries/post_graph app/controllers/admin/mind_graph_controller.rb app/views/admin/mind_graph/show.html.erb app/javascript/mind_graph/app.js test/queries/post_graph test/integration/admin/mind_graph_data_test.rb test/integration/admin/mind_graph_test.rb test/integration/trash_visibility_test.rb
git commit -m "feat: the mind graph's data holds pages, post types, tree and lists lines and every node's state, in thirteen statements"
```

---

### Task 4: a page as the focus — the local view's data, and the list's two reads

**Files:**
- Create: `app/queries/post_graph/rows.rb`, `test/queries/post_graph/rows_test.rb`
- Modify: `app/queries/post_graph/focus.rb`, `app/queries/post_graph/local.rb`, `app/queries/post_graph.rb` (the header names the new queries), `app/controllers/admin/mind_graph_controller.rb`, `config/routes.rb`, `app/views/admin/mind_graph/show.html.erb` (the data URL and the focus bar's name), `config/locales/admin/mind_graph.en.yml` (one key)
- Test: `test/queries/post_graph/focus_test.rb`, `test/queries/post_graph/local_test.rb`, `test/integration/admin/mind_graph_data_test.rb`, `test/integration/admin/mind_graph_test.rb`, `test/integration/trash_visibility_test.rb`

**Interfaces:**
- Consumes: `PostGraph::Site`, `Builder#plan` / `#build` / `#post_nodes`, `Listings`, `Tree` (Tasks 2, 3).
- Produces:

```ruby
PostGraph::Focus.find(actor:, page: nil, post: nil, tag: nil, locale: Locales.default)   # kind "page" | "post" | "tag"; page wins over post, post over tag
PostGraph::Local.call(actor:, focus:, url_for:, depth: 1, locale: Locales.default, cap: CAP)
  # around a page: depth 1 its parent, its children and its lists targets; depth 2 adds the grandparent, the siblings, the
  # grandchildren, the LISTED_IN_VIEW newest posts it lists (each joined by a `brings` line to the type hub or "All posts" that
  # brings it in; one a tag brings in has its tag line) and one `more` pill per target that brings in others, each hanging off its own hub or tag
PostGraph::Rows.new(actor:, url_for:, locale: Locales.default, limit: ROW_LIMIT)
  #unlisted          # => { total:, rows: [post node, …] } newest first
  #listed(page_id, target)   # => { total:, rows: [post node + via: target, …], filter: { type:, tag: } }: the posts THAT TARGET brings in beyond the page's first
                     #    LISTED_IN_VIEW (the rows of one pill); `via` is the target, for the line a row gets when it is added to the canvas;
                     #    `filter` is the filter of the block that points at the target. A target the page does not list answers no rows
```

Routes: `GET mind_graph/unlisted` and `GET mind_graph/listed?page=<id>&target=<target>`, JSON by default. `listed` answers `{ total, rows, posts_url }`; `posts_url` is the Posts screen filtered by the type and tag of the block that points at the target. Both go through the controller's `with_dates` (Task 3), so a row with a scheduled change carries `change_on`.

- [ ] **Step 1: the focus's failing tests.** In `test/queries/post_graph/focus_test.rb`:

```ruby
  test "a readable page is a focus with its title" do
    page = create_page(title: "About")

    focus = PostGraph::Focus.find(actor: nil, page: page.id.to_s)

    assert_equal [ "page", page.id, "About", "page-#{page.id}" ], [ focus.kind, focus.id, focus.title, focus.node_id ]
  end

  test "page wins over post, and post over tag" do
    page = create_page(title: "About")
    post = create_post(title: "A", tags: [ "ruby" ])
    tag = Tag.find_by!(name: "ruby")

    assert_equal "page", PostGraph::Focus.find(actor: nil, page: page.id, post: post.id, tag: tag.id).kind
    assert_equal "post", PostGraph::Focus.find(actor: nil, post: post.id, tag: tag.id).kind
  end

  test "a page focus that is a list, hexadecimal, trashed or out of scope is not found, and 010 is page 10" do
    page = create_page(title: "About")
    hidden = create_page(title: "Hidden")
    gone = create_page(title: "Gone")
    gone.update_column(:trashed_at, Time.current)
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ page.id ] })

    [ [ "1" ], "0x1A", "about", "-#{page.id}", "0", gone.id, Page.maximum(:id) + 1 ].each do |value|
      assert_raises(ActiveRecord::RecordNotFound, value.inspect) { PostGraph::Focus.find(actor: nil, page: value) }
    end
    assert_raises(ActiveRecord::RecordNotFound) { as(users(:author)) { PostGraph::Focus.find(actor: users(:author), page: hidden.id) } }
    assert_equal page.id, PostGraph::Focus.find(actor: nil, page: "0#{page.id}").id
  end

  test "a tag only a readable page lists is a focus, and one only an unreadable page lists is not" do
    seen = create_page(title: "Seen")
    hidden = create_page(title: "Hidden")
    ContentBlock.create!(owner: seen, block_type: :post_list, position: 0, settings: { "tag" => " Listed " })
    ContentBlock.create!(owner: hidden, block_type: :post_list, position: 0, settings: { "tag" => "secret" })
    listed = Tag.create!(name: "listed")
    secret = Tag.create!(name: "secret")
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ seen.id ] })

    assert_equal "tag", PostGraph::Focus.find(actor: nil, tag: listed.id).kind
    as(users(:author)) do
      assert_equal "tag", PostGraph::Focus.find(actor: users(:author), tag: listed.id).kind
      assert_raises(ActiveRecord::RecordNotFound) { PostGraph::Focus.find(actor: users(:author), tag: secret.id) }
    end
  end
```

  Run: `PGGSSENCMODE=disable bin/rails test test/queries/post_graph/focus_test.rb`; expected FAIL with `unknown keyword: :page`.

- [ ] **Step 2: the focus.** In `app/queries/post_graph/focus.rb`, `find` becomes (and the header comment says a page, and the tag's second way in):

```ruby
    def self.find(actor:, page: nil, post: nil, tag: nil, locale: Locales.default)
      readable = AccessControl.scope(actor, "posts.read", Post.all)
      if page.present?
        record = AccessControl.scope(actor, "pages.read", Page.all).find_by(id: id_from(page)) or raise ActiveRecord::RecordNotFound
        new("page", record.id, Locales.read(record, :title, locale: locale))
      elsif post.present?
        record = readable.find_by(id: id_from(post)) or raise ActiveRecord::RecordNotFound
        new("post", record.id, Locales.read(record, :title, locale: locale))
      elsif tag.present?
        record = Tag.find_by(id: id_from(tag)) or raise ActiveRecord::RecordNotFound
        raise ActiveRecord::RecordNotFound unless PostTag.where(tag_id: record.id, post_id: readable.select(:id)).exists? || listed?(record, actor)

        new("tag", record.id, record.name)
      end
    end

    # A tag is a node also when a page the viewer can read lists it (pages
    # spec §1): the viewer can read the page, and its block names the tag.
    # Asked only when no readable post carries it: one statement.
    def self.listed?(tag, actor)
      pages = AccessControl.scope(actor, "pages.read", Page.all).select(:id)
      Listings.blocks(pages).any? { |block| block.settings_object&.tag.to_s.strip.casecmp?(tag.name) }
    end
    private_class_method :listed?
```

  Run the file; expected PASS.

- [ ] **Step 3: the local view's failing tests.** In `test/queries/post_graph/local_test.rb` add `def page_focus(page, actor: nil) = PostGraph::Focus.find(actor: actor, page: page.id)`, `def page_ids(result) = result[:pages].map { |page| page[:id] }`, the `list_block` helper of Task 3, and a second `describe`-free group of tests with its own pages (created in each test, since the file's `setup` is about posts):

```ruby
  #   Home ── Docs ── Guide ── Intro
  #        │       └─ Reference
  #        └─ Blog
  def tree
    @docs = create_page(title: "Docs")
    @guide = create_page(title: "Guide", parent: @docs)
    @intro = create_page(title: "Intro", parent: @guide)
    @reference = create_page(title: "Reference", parent: @docs)
    @blog = create_page(title: "Blog")
  end

  test "depth 1 around a page: its parent, its children and what its blocks list, and no post" do
    tree
    list_block(@docs, tag: "shared")
    list_block(@docs, content_type: "resume_entry")

    result = local(page_focus(@docs))

    assert_equal [ root_page, @docs, @guide, @reference ].map { |page| "page-#{page.id}" }, page_ids(result)
    assert_equal [ "tag-#{Tag.find_by!(name: "shared").id}" ], result[:tags].map { |tag| tag[:id] }
    assert_equal [ "type-resume_entry" ], result[:types].map { |type| type[:id] }
    assert_empty result[:nodes]
    assert_equal({ kind: "page", id: @docs.id, node_id: "page-#{@docs.id}", title: "Docs", depth: 1 }, result[:focus])
    assert_equal 3, result[:edges].count { |edge| edge[:kind] == "tree" }
    assert_equal 2, result[:edges].count { |edge| edge[:kind] == "lists" }
    assert_nil result[:more]
  end

  test "depth 2 around a page adds the grandparent, the siblings and the grandchildren, each with its tree line" do
    tree

    result = local(page_focus(@guide), depth: 2)

    assert_equal [ root_page, @docs, @guide, @intro, @reference ].map { |page| "page-#{page.id}" }, page_ids(result)
    assert_not_includes page_ids(result), "page-#{@blog.id}", "the grandparent's other child is three steps away"
    assert_equal 4, result[:edges].count { |edge| edge[:kind] == "tree" }
  end

  # Third design answers, "Local view lines": the hub that brings a post in
  # draws the line to it, and more hangs off the hub. No lists line joins
  # the page to a post.
  test "depth 2 around a page draws the twenty newest posts it lists, each joined to the hub that brings it in, and counts the rest behind more" do
    tree
    list_block(@blog, content_type: "resume_entry")
    posts = 23.times.map { |index| create_post(title: "Entry #{index}", content_type: "resume_entry") }
    posts.each_with_index { |post, index| post.update_columns(published_at: (index + 1).hours.ago) } # version: none (a test sets a time) # changes: none (a test sets a time)

    result = local(page_focus(@blog), depth: 2)

    assert_equal posts.first(20).map { |post| "post-#{post.id}" }.sort, ids(result)
    assert_equal [ { id: "more-type-resume_entry", count: 3, page: "page-#{@blog.id}", target: "type-resume_entry" } ], result[:more]
    lists = result[:edges].select { |edge| edge[:kind] == "lists" }
    brings = result[:edges].select { |edge| edge[:kind] == "brings" }
    assert_equal [ { source: "page-#{@blog.id}", target: "type-resume_entry", kind: "lists" } ], lists, "the page's one lists line, and none to a post"
    assert_equal 21, brings.size, "twenty posts and the pill"
    assert brings.all? { |edge| edge[:source] == "type-resume_entry" }
    assert_includes brings, { source: "type-resume_entry", target: "more-type-resume_entry", kind: "brings" }
    assert_equal ids(result), (brings.map { |edge| edge[:target] } - [ "more-type-resume_entry" ]).sort
    assert_equal [ 20, 20 ], result.values_at(:total, :shown)
    assert_empty local(page_focus(@blog), depth: 1)[:nodes]
    assert_empty local(page_focus(@blog), depth: 1)[:edges].select { |edge| edge[:kind] == "brings" }
  end

  test "a post the page lists through a tag is joined to the tag by its own line and by no other" do
    tree
    list_block(@blog, tag: "shared")

    result = local(page_focus(@blog), depth: 2)
    tag = "tag-#{Tag.find_by!(name: "shared").id}"

    assert_equal [ @centre, @cousin ].map { |post| "post-#{post.id}" }.sort, ids(result)
    assert_includes result[:edges], { source: "post-#{@centre.id}", target: tag, kind: "tag" }
    assert_empty result[:edges].select { |edge| edge[:kind] == "brings" }, "the tag is the hub, and its own line is the line"
    assert_empty result[:edges].select { |edge| edge[:kind] == "lists" && edge[:target].start_with?("post-") }
    assert_nil result[:more]
  end

  # Design answer H1: ONE PILL PER TARGET, each counting only what its own
  # target brings in. Not one pill on the first block's hub.
  test "a page with two list blocks has a pill per target, each on its own hub or tag with its own count, and a target that brings in nothing more has none" do
    tree
    list_block(@docs, tag: "pill")
    list_block(@docs, content_type: "resume_entry")
    list_block(@docs, tag: "few")
    pills = 15.times.map { |index| create_post(title: "Pill #{index}", tags: [ "pill" ]) }
    entries = 15.times.map { |index| create_post(title: "Entry #{index}", content_type: "resume_entry") }
    create_post(title: "Few", tags: [ "few" ]).update_columns(published_at: 1.minute.ago)                  # version: none (a test sets a time) # changes: none (a test sets a time)
    pills.each_with_index { |post, index| post.update_columns(published_at: (2 * index + 1).hours.ago) }   # version: none (a test sets a time) # changes: none (a test sets a time)
    entries.each_with_index { |post, index| post.update_columns(published_at: (2 * index + 2).hours.ago) } # version: none (a test sets a time) # changes: none (a test sets a time)
    pill = "tag-#{Tag.find_by!(name: "pill").id}"

    result = local(page_focus(@docs), depth: 2)

    # The twenty newest: "Few", ten pills and nine entries. Left out: five
    # pills and six entries.
    assert_equal [ { id: "more-#{pill}", count: 5, page: "page-#{@docs.id}", target: pill },
                   { id: "more-type-resume_entry", count: 6, page: "page-#{@docs.id}", target: "type-resume_entry" } ], result[:more], "in the order of the page's targets; the tag few has no pill"
    to_pills = result[:edges].select { |edge| edge[:target].start_with?("more-") }
    assert_equal [ { source: pill, target: "more-#{pill}", kind: "brings" }, { source: "type-resume_entry", target: "more-type-resume_entry", kind: "brings" } ], to_pills
    assert_equal 9, result[:edges].count { |edge| edge[:kind] == "brings" && edge[:target].start_with?("post-") }, "the nine entries hang off the type; the tagged posts have their tag lines"
  end

  test "a page that lists by nothing brings its posts in through All posts, pill included" do
    tree
    list_block(@blog)
    21.times { |index| create_post(title: "Many #{index}") }

    all = local(page_focus(@blog), depth: 2)
    brings = all[:edges].select { |edge| edge[:kind] == "brings" }

    assert brings.all? { |edge| edge[:source] == "all-posts" }
    assert_equal ids(all), (brings.map { |edge| edge[:target] } - [ "more-all-posts" ]).sort
    assert_equal [ "more-all-posts" ], all[:more].map { |more| more[:id] }
    assert all[:more].first[:count].positive?
  end

  test "around a page nothing outside the viewer's scope is drawn: not the parent, not a child, not a post it lists" do
    tree
    list_block(@docs, content_type: "blog")
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ @guide.id ] })
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })

    result = as(users(:author)) { local(page_focus(@guide, actor: users(:author)), depth: 2, actor: users(:author)) }

    assert_equal [ @guide, @intro ].map { |page| "page-#{page.id}" }, page_ids(result)
    assert_empty result[:nodes]
    assert_no_match(/page-#{@docs.id}\b/, result.to_json)
  end

  test "from a tag the walk steps along a lists line: the pages that list it are depth 1" do
    tree
    list_block(@blog, tag: "shared")

    result = local(tag_focus("shared"))

    assert_equal [ "page-#{@blog.id}" ], page_ids(result)
    assert_includes result[:edges], { source: "page-#{@blog.id}", target: "tag-#{Tag.find_by!(name: "shared").id}", kind: "lists" }
  end

  test "from a post, depth 2 reaches the pages that list one of its tags, and depth 1 does not" do
    tree
    list_block(@blog, tag: "shared")

    assert_empty page_ids(local(post_focus(@centre)))
    assert_equal [ "page-#{@blog.id}" ], page_ids(local(post_focus(@centre), depth: 2))
  end

  test "a page's local view costs the same with 3 listed posts and with 30: twelve statements at depth 1, thirteen at depth 2" do
    tree
    list_block(@blog, tag: "many")
    3.times { |index| create_post(title: "Few #{index}", tags: [ "many" ]) }
    as(users(:two)) { Notes::Start.call(@blog, body: "A note") }
    viewer = users(:one)
    focus = page_focus(@blog, actor: viewer)
    count = ->(depth) { capture_sql { local(focus, depth: depth, actor: viewer) }.size }

    few = [ count.call(1), count.call(2) ]
    27.times { |index| create_post(title: "Many #{index}", tags: [ "many" ]) }

    # The site's five, the relations among the posts drawn, and the builder's:
    # at depth 1 no post is drawn, so no post's notes are asked for.
    assert_equal [ 12, 13 ], few
    assert_equal [ 12, 13 ], [ count.call(1), count.call(2) ]
  end
```

  Run: `PGGSSENCMODE=disable bin/rails test test/queries/post_graph/local_test.rb`; expected FAIL: a page focus walks nothing yet.

- [ ] **Step 4: the local view.** In `app/queries/post_graph/local.rb` replace `call` and `walk`, and add the two page walks. The header comment gains the page's rule (the two depths, word for word from spec §7) and the cost (the global view's thirteen, plus three per depth level around a post or a tag; around a page the walk asks nothing):

```ruby
    def call
      @site = Site.load(actor: @actor)
      @readable = @site.readable_posts.select(:id)
      @posts = {}
      @tags = {}
      @pages = {}
      @types = Set.new
      @listed = []
      @more = []
      @focus.kind == "page" ? walk_around_page : walk

      post_ids = @posts.keys
      relations = PostRelation.where(post_id: post_ids, related_post_id: post_ids).order(:id).pluck(:post_id, :related_post_id)
      tag_links = @site.tag_links.select { |tag_id, post_id| @tags.key?(tag_id) && @posts.key?(post_id) }

      kept = cut(post_ids, relations, tag_links)
      lists = @site.listings.edges.select { |page_id, target| @pages.key?(page_id) && reached?(target) }
      builder = Builder.new(site: @site, locale: @locale, url_for: @url_for)
      plan = builder.plan(post_ids: kept, relations: relations, tag_links: tag_links, tag_counts: @site.tag_counts, min_tag_edges: 1,
                          page_ids: @pages.keys, lists: lists, brought: brought(kept),
                          keep_tag: (@focus.id if @focus.kind == "tag"), more: @more)
      builder.build(plan).merge(total: post_ids.size, shown: kept.size,
                                focus: { kind: @focus.kind, id: @focus.id, node_id: @focus.node_id, title: @focus.title, depth: @depth })
    end

    private

    def reached?(target)
      target.start_with?("tag-") ? @tags.key?(target.delete_prefix("tag-").to_i) : @types.include?(target)
    end

    # The hub that brings each drawn post of the page in, for its faint line
    # (third design answers, "Local view lines"): the target of the first
    # list block of the page that lists it. A post a TAG brings in is left
    # out: its tag line to that tag is among the tag links, and is the line.
    def brought(kept)
      @listed.filter_map do |page_id, post_id|
        target = @site.listings.target_of(page_id, post_id)
        [ target, post_id ] if kept.include?(post_id) && target && !target.start_with?("tag-")
      end
    end

    # A page's own rule (pages spec §7; design answers 4 and F5, and the
    # third answers), from what the site has loaded: no statement. Depth 1:
    # its parent, its children and what its blocks list. Depth 2 adds one
    # more step along the tree (the grandparent, the siblings, the
    # grandchildren) and the newest LISTED_IN_VIEW posts it lists; the
    # others are counted behind "+N more", ONE PILL PER TARGET (design
    # answer H1), each on its own hub or tag with what that target brings
    # in, in the order of the page's targets. No line joins the page to a
    # post: `brought`.
    def walk_around_page
      tree = @site.tree
      id = @focus.id
      @pages[id] = 0
      near = tree.neighbours(id)
      near.each { |page_id| @pages[page_id] = 1 }
      step_onto_targets(id, 1)
      return if @depth < 2

      (near.flat_map { |page_id| tree.neighbours(page_id) } - @pages.keys).uniq.each { |page_id| @pages[page_id] = 2 }
      listed = @site.listings.posts_of(id)
      listed.first(LISTED_IN_VIEW).each do |post_id|
        @posts[post_id] = 2
        @listed << [ id, post_id ]
      end
      left = @site.listings.left_out(id)
      @more = @site.listings.targets(id).filter_map { |target| { page_id: id, target: target, count: left[target] } if left[target] }
    end

    def step_onto_targets(page_id, level)
      @site.listings.targets(page_id).each do |target|
        if target.start_with?("tag-") then @tags[target.delete_prefix("tag-").to_i] ||= level
        else @types << target
        end
      end
    end

    # `@posts`, `@tags` and `@pages`: id => the depth it was first reached at.
    def walk
      post_frontier = []
      tag_frontier = []
      page_frontier = []
      if @focus.kind == "post"
        @posts[@focus.id] = 0
        post_frontier = [ @focus.id ]
      else
        @tags[@focus.id] = 0
        tag_frontier = [ @focus.id ]
      end

      1.upto(@depth) do |level|
        reached_posts = []
        reached_tags = []
        # No `any?` guards: an empty frontier is a cheap `IN (NULL)` statement, and
        # skipping it would make the statement count depend on the shape.
        touching = PostRelation.where(post_id: post_frontier).or(PostRelation.where(related_post_id: post_frontier))
        reached_posts.concat(touching.where(post_id: @readable, related_post_id: @readable).pluck(:post_id, :related_post_id).flatten)
        reached_tags.concat(PostTag.where(post_id: post_frontier).distinct.pluck(:tag_id))
        reached_posts.concat(PostTag.where(tag_id: tag_frontier, post_id: @readable).distinct.pluck(:post_id))

        # Along the pages' lines, from what the site has loaded (no
        # statement): a tag leads to the pages that list it, a page to its
        # parent and children and to what it lists.
        reached_pages = tag_frontier.flat_map { |tag_id| @site.listings.pages_of(PostGraph.node_id(:tag, tag_id)) }
        before = @tags.keys
        page_frontier.each do |page_id|
          reached_pages.concat(@site.tree.neighbours(page_id))
          step_onto_targets(page_id, level)
        end

        post_frontier = reached_posts.uniq - @posts.keys
        tag_frontier = (reached_tags.uniq - before) | (@tags.keys - before)
        page_frontier = reached_pages.uniq - @pages.keys
        post_frontier.each { |id| @posts[id] = level }
        tag_frontier.each { |id| @tags[id] ||= level }
        page_frontier.each { |id| @pages[id] = level }
      end
    end
```

  `cut` stays as it is. Run the file, then the whole directory: `PGGSSENCMODE=disable bin/rails test test/queries/post_graph`; expected PASS.

- [ ] **Step 5: the two list reads, test first.** Create `test/queries/post_graph/rows_test.rb`:

```ruby
require "test_helper"

# `PostGraph::Rows` (pages in the mind graph, spec §3, decision 10): the rows
# of the list's two filters, each a post's node as the graph's data has it.
class PostGraph::RowsTest < ActiveSupport::TestCase
  def rows(actor: nil, limit: PostGraph::ROW_LIMIT) = PostGraph::Rows.new(actor: actor, limit: limit, url_for: ->(post) { "/cs-studio/posts/#{post.id}" })

  def list_block(page, **settings)
    ContentBlock.create!(owner: page, block_type: :post_list, position: page.content_blocks.count, settings: settings.stringify_keys)
  end

  setup do
    @blog = create_page(title: "Blog")
    list_block(@blog, content_type: "blog", tag: "news")
    @listed = create_post(title: "Listed", tags: [ "news" ])
    @old = create_post(title: "Old").tap { |post| post.update_columns(published_at: 2.days.ago) } # version: none (a test sets a time) # changes: none (a test sets a time)
    @new = create_post(title: "New", published: false)
  end

  test "unlisted is the readable posts no readable page lists, newest first, each a whole post node with no line" do
    result = rows.unlisted

    assert_equal 2, result[:total]
    assert_equal [ "post-#{@new.id}", "post-#{@old.id}" ], result[:rows].map { |row| row[:id] }
    assert_equal({ id: "post-#{@new.id}", title: "New", type: "blog", colour_index: ContentTypes.fetch("blog").colour_index, status: "draft", changes: nil,
                   change_at: nil, listed: false, url: "/cs-studio/posts/#{@new.id}", degree: 0, related_count: 0, tag_count: 0, open_notes: 0 }, result[:rows].first)
  end

  test "the first rows up to the limit, with the whole total" do
    assert_equal [ 2, [ "post-#{@new.id}" ] ], [ rows(limit: 1).unlisted[:total], rows(limit: 1).unlisted[:rows].map { |row| row[:id] } ]
  end

  # The fixtures' author reads every post and, here, one branch of the tree
  # that does not hold the page that lists "Listed".
  test "unlisted is true for the viewer: a post only a page they cannot read lists is a row, and a trashed post is none" do
    other = create_page(title: "Other")
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ other.id ] })
    @old.update_column(:trashed_at, Time.current)

    result = as(users(:author)) { rows(actor: users(:author)).unlisted }

    assert_equal [ @listed, @new ].map { |post| "post-#{post.id}" }.sort, result[:rows].map { |row| row[:id] }.sort
    assert_equal 2, result[:total]
    assert_equal [ "post-#{@new.id}" ], rows.unlisted[:rows].map { |row| row[:id] }, "to someone who reads the whole tree it is listed"
  end

  test "listed is the posts one target of a page brings in beyond the twenty its local view draws, each with that target, and the filter of the target's block" do
    posts = 22.times.map { |index| create_post(title: "News #{index}", tags: [ "news" ]) }
    posts.each_with_index { |post, index| post.update_columns(published_at: (index + 1).minutes.from_now) } # version: none (a test sets a time) # changes: none (a test sets a time)

    news = "tag-#{Tag.find_by!(name: "news").id}"
    result = rows.listed(@blog.id, news)

    assert_equal 3, result[:total], "twenty-three listed, twenty drawn"
    assert_equal [ posts[1], posts[0], @listed ].map { |post| "post-#{post.id}" }, result[:rows].map { |row| row[:id] }
    assert_equal({ type: "blog", tag: "news" }, result[:filter])
    assert result[:rows].all? { |row| row[:listed] }
    assert_equal [ news ], result[:rows].map { |row| row[:via] }.uniq, "a block with a tag and a type points at the tag"
    assert(rows.unlisted[:rows].none? { |row| row.key?(:via) })
    assert_equal({ total: 0, rows: [], filter: {} }, rows.listed(@blog.id, "type-blog"), "a target the page does not list has no pill and no rows")
    assert_equal({ total: 0, rows: [], filter: {} }, rows.listed(@blog.id, "<junk>"))
  end

  test "a page that lists twenty or fewer has no rows, and a page with no list block an empty filter" do
    assert_equal({ total: 0, rows: [], filter: { type: "blog", tag: "news" } }, rows.listed(@blog.id, "tag-#{Tag.find_by!(name: "news").id}"))
    assert_equal({ total: 0, rows: [], filter: {} }, rows.listed(root_page.id, "all-posts"))
  end

  test "each read costs eight statements, with a few rows and with thirty more" do
    viewer = users(:one)
    22.times { |index| create_post(title: "News #{index}", tags: [ "news" ]) } # so that `listed` has rows: a read with none asks for no notes
    count = -> { [ capture_sql { rows(actor: viewer).unlisted }.size, capture_sql { rows(actor: viewer).listed(@blog.id, "tag-#{Tag.find_by!(name: "news").id}") }.size ] }

    few = count.call
    30.times { |index| create_post(title: "More #{index}", tags: ([ "news" ] if index.even?).to_a) }

    assert_equal [ 8, 8 ], few
    assert_equal [ 8, 8 ], count.call
  end
end
```

  Run it; expected FAIL with `uninitialized constant PostGraph::Rows`.

- [ ] **Step 6: the rows.** Create `app/queries/post_graph/rows.rb`:

```ruby
# The rows of the list's two filters (pages in the mind graph, spec §3, §7,
# decision 10), each its own read and neither a filter over the drawn nodes:
# a post no page lists is very likely a post with no connection, which the
# global view does not draw.
#
# - `unlisted`: the readable posts NO READABLE PAGE lists. True for the
#   viewer, not for the site: someone who reads part of the tree is told a
#   post is unlisted when a page they cannot read lists it, since saying
#   otherwise would disclose that page (spec, Risks).
# - `listed(page_id, target)`: the posts ONE TARGET of that page brings in
#   beyond the LISTED_IN_VIEW its local view draws: the rows behind that
#   target's "+N more" pill (design answer H1: a pill per target). The
#   caller has found the page through `Focus`, so it is readable; `target`
#   is compared with the page's own targets and nothing else is done with
#   it, so a junk one answers no rows.
#
# Newest first, the first `limit` with the whole `total`. A row is a post's
# node exactly as the graph's data has it (`Builder#post_nodes`), with no
# line counted: the page adds a row that is not drawn to the canvas without
# another request. A row of `listed` also says which hub brings its post in
# (`via`, `Listings#target_of`): added to the canvas it gets that hub's line
# (third design answers). Eight statements each: the site's five and the
# nodes' three.
module PostGraph
  class Rows
    def initialize(actor:, url_for:, locale: Locales.default, limit: ROW_LIMIT)
      @actor = actor
      @url_for = url_for
      @locale = locale
      @limit = limit
    end

    def unlisted
      site = Site.load(actor: @actor)
      answer(site, site.listings.unlisted)
    end

    def listed(page_id, target)
      site = Site.load(actor: @actor)
      listings = site.listings
      target = target.to_s
      answer(site, listings.left_out_of(page_id, target), via: ->(_post_id) { target }).merge(filter: listings.filter_of(page_id, target))
    end

    private

    def answer(site, ids, via: nil)
      shown = ids.first(@limit)
      nodes = Builder.new(site: site, locale: @locale, url_for: @url_for).post_nodes(shown).index_by { |node| node[:id] }
      rows = shown.filter_map do |id|
        node = nodes[PostGraph.node_id(:post, id)] or next
        via ? node.merge(via: via.call(id)) : node
      end
      { total: ids.size, rows: rows }
    end
  end
end
```

  Run: `PGGSSENCMODE=disable bin/rails test test/queries/post_graph/rows_test.rb`; expected PASS.

- [ ] **Step 7: the routes, the controller, the frame's address.** In `config/routes.rb`:

```ruby
    # `data`, `search`, `unlisted` and `listed` are the mind graph screen's
    # own JSON reads (mind graph canvas spec §3.1; pages spec §3): the graph,
    # global or around `page=` / `post=` / `tag=`; the search field's rows;
    # the posts no page lists; and the posts `page=` lists beyond the ones
    # its local view draws.
    resource :mind_graph, only: :show, controller: :mind_graph do
      get :data, defaults: { format: :json }
      get :search, defaults: { format: :json }
      get :unlisted, defaults: { format: :json }
      get :listed, defaults: { format: :json }
    end
```

  In the controller, `show` and `data` find the focus with `page: params[:page]` as well; add a private `focus` both use:

```ruby
    def focus = PostGraph::Focus.find(actor: Current.actor, page: params[:page], post: params[:post], tag: params[:tag], locale: admin_locale)
```

  and the two reads:

```ruby
    def unlisted
      render json: with_dates(list_rows.unlisted)
    end

    # The rows behind one of a page's "+N more" pills (`target=`: a pill per
    # target, design answer H1), and where the Posts screen shows the same
    # posts as far as its filters go: by the type and the tag of the block
    # that points at the target. `target` is only ever compared: a junk one
    # answers no rows.
    def listed
      page = PostGraph::Focus.find(actor: Current.actor, page: params[:page], locale: admin_locale) or raise ActiveRecord::RecordNotFound
      rows = list_rows.listed(page.id, params[:target].to_s)
      render json: with_dates(rows.except(:filter)).merge(posts_url: admin_posts_path(**admin_url_options, **rows[:filter].compact))
    end
```

```ruby
    def list_rows = PostGraph::Rows.new(actor: Current.actor, locale: admin_locale, url_for: editor_url)
```

  In `show.html.erb` the data URL carries the page: `data_admin_mind_graph_path(**admin_url_options, page: params[:page].presence, post: params[:post].presence, tag: params[:tag].presence, depth: (@depth if @focus))`. The focus bar's name is `t(".focus.around_#{@focus.kind}", …)` already; add to `config/locales/admin/mind_graph.en.yml`, under `show.focus`, after `around_tag`:

```yaml
          around_page: "Around the page “%{title}”"
```

- [ ] **Step 8: the integration tests.** In `test/integration/admin/mind_graph_data_test.rb`:
  - `"page= and depth= answer that page's neighbourhood"`: a page with a child and a list block; `get "/cs-studio/mind_graph/data", params: { page: page.id, depth: 2 }`; `data["focus"]` is `{ "kind" => "page", "id" => page.id, "node_id" => "page-#{page.id}", "title" => …, "depth" => 2 }`; the child and Home are in `data["pages"]`.
  - `"a page focus that is a list, hexadecimal, trashed or out of scope is 404, and 010 is page 10"`: for the page, `data` and `listed`, each of `page[]=1`, `page=0x1A`, a trashed page's id, an unknown id → `:not_found`; `page=0<id>` → success with that page as the focus. (Follow `"an id with a leading zero is that id, and a hexadecimal one is not found"` in the same file.)
  - `"unlisted answers the posts no page lists, with the total"` and `"listed answers the rows behind more and the Posts screen's address"`: `get "/cs-studio/mind_graph/unlisted"` → `data.keys.sort == %w[rows total]`, the rows' ids; `get "/cs-studio/mind_graph/listed", params: { page: blog.id, target: "tag-#{Tag.find_by!(name: "news").id}" }` with 22 listed posts and a block of `"content_type" => "blog", "tag" => "news"` → `data["total"] == 2`, every row's `"via"` is `"tag-#{Tag.find_by!(name: "news").id}"`, and `data["posts_url"] == "/cs-studio/posts?tag=news&type=blog"` (compare the query as a Hash: `Rack::Utils.parse_query(URI(data["posts_url"]).query)`), and no key `filter`.
  - `"listed without a page, and both reads without a session or a permission"`: `listed` with no `page` → 404; `listed` with a page and no `target`, `target[]=x` or `target=<script>` → success with `"total" => 0`, no rows and nothing of the junk in the body; signed out → redirect to sign-in for both; a viewer with neither permission → 403 for both.

  In `test/integration/admin/mind_graph_test.rb`: `"a page focus is named as a page, and its depth links keep the page"` (`get "/cs-studio/mind_graph", params: { page: page.id }` → the bar holds `Around the page “About”`, the depth-2 link is `/cs-studio/mind_graph?depth=2&page=#{page.id}` in the form the tag's test compares, and `data-url` carries `page=#{page.id}`); and `"a focus title with markup in it is escaped"` gains a page titled `<b>x</b>`.

  In `test/integration/trash_visibility_test.rb`, in the Mind graph test: `get "/cs-studio/mind_graph", params: { page: @gone_page.id }` and `get "/cs-studio/mind_graph/data", params: { page: @gone_page.id }` and `get "/cs-studio/mind_graph/listed", params: { page: @gone_page.id }` are `:not_found`; `get "/cs-studio/mind_graph/unlisted"` holds `"post-#{@kept_post.id}"` only when the kept post is unlisted (it is a blog post and `@blog` lists blog posts, so here assert the opposite: no row for it and no row for `@gone_post`; then `@blog.update_column(:trashed_at, Time.current)` and the kept post IS a row while the trashed one still is not); and `get "/cs-studio/mind_graph/data", params: { page: @kept_page.id, depth: 2 }` names neither `Gone page` nor `Gone post`.

  Run: `PGGSSENCMODE=disable bin/rails test test/queries/post_graph test/integration/admin/mind_graph_data_test.rb test/integration/admin/mind_graph_test.rb test/integration/trash_visibility_test.rb test/lib && bin/rubocop app/queries/post_graph app/controllers/admin/mind_graph_controller.rb config/routes.rb && bin/brakeman -q`
  Expected: PASS, no offences, no warnings.

- [ ] **Step 9: commit.**

```bash
git add app/queries/post_graph.rb app/queries/post_graph app/controllers/admin/mind_graph_controller.rb config/routes.rb app/views/admin/mind_graph/show.html.erb config/locales/admin/mind_graph.en.yml test/queries/post_graph test/integration/admin/mind_graph_data_test.rb test/integration/admin/mind_graph_test.rb test/integration/trash_visibility_test.rb
git commit -m "feat: a page is a focus of the mind graph — its neighbourhood to depth 2, and the list's two reads"
```

---
### Task 5: the canvas draws every kind of node and line — the marks, the five looks, the label order, Home at the centre

After this task a page is on the canvas. The radios still filter (Task 6 replaces them); a page's, a type's and "+N more"'s card is its title and Pin until Task 8.

**The design answer's values, and the readings to report.** The third design answers (G1 to G3, the correction and "Ring types") give most sizes as numbers; those are built as given and are not readings. What is left is in the second table: build each as written here, behind the constant named, and **report the list to the controller with a screenshot of each look in both themes; do not tune one by eye**. The controller checks each against the drawing (`Studio Mind Graph Pages.dc.html`).

| The answer gives | Built as | Constant (`marks.js` unless said) |
|---|---|---|
| a scheduled record: a centre dot 4px across, in warn | radius 2, `theme.warn` | `CENTRE_DOT` |
| a corner dot 5px across, its centre 1px in from the mark's bottom-right corner (on the 45° line for a circle), with a 1.5px surface ring; dim for unpublished changes, warn for a scheduled change | radius 2.5 on a surface disk of radius 4; a page's at its corner less 1 each way, a circle's at `(radius - 1) / √2` right and down | `CORNER_DOT`, `CORNER_INSET`, `CORNER_RING` |
| the hub's inner ring: 1.5px wide, its outer edge 1.5px inside the hub's 6px radius | a 1.5px surface stroke centred at radius 3.75 (from 3 to 4.5) | `TYPE_RING` |
| a ring type: a filled-type mark inside a 1.5px ring; live, the ring at radius 7 with a filled radius-4 disk | the ring at the mark's radius, the type's mark at 4/7 of it, drawn by the same rule as a filled post's | `OUTLINE`, `INNER` |
| a retired type's hub: an outline circle in dim, 1.5px, DASHED (H3), on surface, with a 4px dim centre dot; "(retired)" at the end of its label | surface disk of radius 6, 1.5px dashed `dim` stroke, a dot of radius 2; the label through the message `retired_type` | `drawType`, `CENTRE_DOT` |
| the hub of a ring type (slots 7 to 12; H3): a 1.5px ring in the hue around a filled 6px centre, not filled | surface disk of radius 6, 1.5px solid stroke in the hue, a filled disk of radius 3 | `drawType`, `RING_HUB_CENTRE` |
| a ring type's inner mark (H3): 4/7 of the outer radius at every size, rounded to the nearest 0.5px; a draft's outer ring solid; the corner dot on the outer ring | 4, 5.5, 7.5 and 9 for the radii 7, 10, 13 and 16 | `innerRadius` |
| "+N more": a 16px-high pill, surface, a 1px line-strong border, the words in 10px mono dim; it GROWS TO FIT, 8px padding each side, at least 60px wide; the figure with a thousands separator, "+1,980 more" (H4) | a round-ended box (corner radius 8) as wide as its measured words plus 16, never under 60; `theme.line`, `theme.countFont` (the 10px mono the notes badge has), `theme.dim`; the figure through `number()` | `MORE_HEIGHT`, `MORE_MIN_WIDTH`, `MORE_PADDING`, `moreWidth` |
| the Lists line: 1.5px, round caps, dash 0.1 / 3.5 | as given | `LINE_STYLES.lists` (`renderer.js`) |
| a hub's faint line to "+N more": 1px `--cs-line` | as given, `theme.faint` | `LINE_STYLES.brings` (`renderer.js`) |

| A reading this plan makes | Built as | Constant |
|---|---|---|
| "DASHED, 1.5px" | dashes of 3 and gaps of 2.5, the dash a draft has today | `DRAFT_DASH`, `OUTLINE` |
| "a filled 6px centre" of a ring type's hub | 6px ACROSS (radius 3): a centre of radius 6 would be the whole hub | `RING_HUB_CENTRE` |
| a retired hub's dashed ring | the draft's dash (3 / 2.5), a stroke centred on the hub's radius like every other outline here | `drawType` |
| "a fixed bonus over a post with equal links" | half a link | `PAGE_BONUS` (`graph_data.js`) |

**Files:**
- Create: `app/javascript/mind_graph/marks.js`, `app/javascript/mind_graph/graph_data.js`
- Modify: `app/javascript/mind_graph/theme.js`, `renderer.js`, `labels.js`, `hit_test.js`, `layout_worker.js`, `layout_client.js` (its comment only), `app.js`, `card.js`, `app/views/admin/mind_graph/show.html.erb` (three messages), `config/locales/admin/mind_graph.en.yml` (three keys), `test/lib/admin_i18n_test.rb` (the two new modules join `CONVERTED`)
- Test: `test/system/admin/mind_graph_modules_test.rb`, `test/system/admin/mind_graph_test.rb`, `test/integration/admin/mind_graph_test.rb` (the list of message keys)

**Interfaces:**
- Consumes: the payload of Task 3 (`pages`, `types`, `more`, `status`, `changes`, the five edge kinds); `ids.js` (Task 1).
- Produces:

```js
// mind_graph/marks.js
radiusFor(node)          // half a page's width (7; Home 9), half the pill's (30 at the least), 6 for a type hub, else one of the four steps by degree
collisionRadius(node)    // half a box's diagonal (a page, the pill), else radiusFor(node): what the layout keeps clear
boxOf(node)              // { width, height } for a page and for "+N more" (its `node.width`, else the least, 60), null for anything else
moreWidth(wordsWidth)    // a pill's width for its measured words: 8px each side, never under 60
drawMark(context, theme, node, x, y, radius)

// mind_graph/graph_data.js
nodesOf(data, { allPosts, more, retired })   // payload -> [{ …, kind: "page"|"post"|"tag"|"type"|"more", title }]; `more(count)` answers a pill's words (one node per pill),
                                     // `retired(name)` a retired type's label ("Old type (retired)")
rank(node)                           // 0 Home, 1 a top-level page or a type node, 2 the rest
orderOf(nodes, indexes)              // indexes sorted: rank, then degree (a page half a link ahead), then index; "more" is left out: the pill carries its words
freeOf(nodes, indexes)               // Set of the indexes of rank 0 and 1: labelled outside the zoom's budget

// mind_graph/labels.js
chooseLabels({ order, positions, widths, radii, camera, width, height, always, free = new Set() })

// mind_graph/hit_test.js
nodeAt({ …, boxes = [] })            // boxes[index]: { width, height } | null; a box's target is the box, not a circle round it

// mind_graph/renderer.js
draw(context, state)                 // as before; re-exports radiusFor
LINE_STYLES, HIDE_TAG_LINES_BELOW    // 0.4

// layout worker, `start`:  nodes: [{ id, radius, anchor }]   edges: [{ source, target, kind }]
// element.mindGraph.graphPosition(id)   // { x, y } in GRAPH units as the layout has them, or null: for the test of the anchor
// theme: + dim, warn, faint, radius (a number of pixels), monoFont
```

- [ ] **Step 1: the failing tests of the marks.** In `test/system/admin/mind_graph_modules_test.rb`, the helper (beside `notes_badges`) and the tests. The helper draws the given nodes 100 pixels apart against a context that records, with a theme whose values are their own names, and answers per node what was filled, stroked and written: `[ "fill", shape, sizes…, colour ]`, `[ "stroke", shape, sizes…, colour, width, dash ]` and `[ "text", words, font, colour ]`, where a circle's size is its radius and a box's its width, height and corner radius.

```ruby
  def marks_drawn(nodes)
    drawn = page.evaluate_async_script(<<~JS, nodes)
      const [given, done] = arguments
      import("mind_graph/renderer").then(({ draw, radiusFor }) => {
        const round = (value) => Math.round(value * 100) / 100
        const log = []
        const set = { dash: [] }
        let shape = null
        const context = new Proxy({}, {
          get: (_, name) => {
            if (name === "beginPath") return () => { shape = null }
            if (name === "arc") return (x, y, radius) => { shape = [round(x), "circle", round(radius)] }
            if (name === "rect") return (x, y, width, height) => { shape = [round(x), "box", width, height] }
            if (name === "roundRect") return (x, y, width, height, radius) => { shape = [round(x), "box", width, height, radius] }
            if (name === "moveTo") return (x) => { shape = [round(x), "line"] }
            if (name === "setLineDash") return (dash) => { set.dash = dash }
            if (name === "fillRect") return (x, y, width, height) => { log.push([round(x), "fill", "box", width, height, set.fillStyle]) }
            if (name === "strokeRect") return (x, y, width, height) => { log.push([round(x), "stroke", "box", width, height, set.strokeStyle, set.lineWidth, set.dash]) }
            if (name === "fillText") return (words, x) => { log.push([round(x), "text", words, set.font, set.fillStyle]) }
            if (name === "fill") return () => { if (shape) log.push([shape[0], "fill", ...shape.slice(1), set.fillStyle]) }
            if (name === "stroke") return () => { if (shape) log.push([shape[0], "stroke", ...shape.slice(1), set.strokeStyle, set.lineWidth, set.dash]) }
            return () => {}
          },
          set: (_, name, value) => { set[name] = value; return true }
        })
        const nodes = given.map((node, index) => ({ id: `n-${index}`, kind: "post", degree: 1, colour_index: 1, status: "live", label: "", ...node }))
        draw(context, {
          width: 100 * nodes.length, height: 100, ratio: 1, camera: { k: 1, tx: 0, ty: 0 },
          theme: { ink: "ink", meta: "meta", dim: "dim", warn: "warn", surface: "surface", sunken: "sunken", accent: "accent", line: "line", faint: "faint", radius: 4,
                   categories: [1, 2, 3, 4, 5, 6].map((slot) => `cat-${slot}`), font: "sans", strongFont: "strong", monoFont: "mono", countFont: "count" },
          nodes, edges: [], positions: Float32Array.from(nodes.flatMap((_, index) => [ 50 + index * 100, 50 ])),
          radii: nodes.map(radiusFor), widths: nodes.map(() => 0), visibleNodes: nodes.map((_, index) => index), visibleEdges: [],
          labels: [], selected: -1, neighbours: new Set(), focusIndex: -1, hovered: -1, pinned: new Set()
        })
        done(log)
      }).catch((error) => done({ error: String(error) }))
    JS
    flunk "renderer: #{drawn["error"]}" if drawn.is_a?(Hash)
    by_node = drawn.group_by { |x, *| (x / 100).floor }
    nodes.each_index.map { |index| by_node.fetch(index, []).map { |_x, *rest| rest } }
  end

  SOLID = [].freeze
  DASHED = [ 3, 2.5 ].freeze
```

```ruby
  # Pages spec §4, the status table: one rule for a page and a post, and warn
  # means "scheduled" (third design answers). Read from what the renderer
  # asks of the context: a dashed outline cannot be told from a solid one by
  # one pixel. A corner dot is a surface disk (its 1.5px ring) under a dot.
  CORNER = ->(colour) { [ [ "fill", "circle", 4, "surface" ], [ "fill", "circle", 2.5, colour ] ] }

  test "marks: a page is a 14 by 10 card, Home 18 by 13, in each of the five looks" do
    live, draft, scheduled, changed, pending, home = marks_drawn([
      { kind: "page" }, { kind: "page", status: "draft" }, { kind: "page", status: "scheduled" },
      { kind: "page", changes: "unpublished" }, { kind: "page", changes: "scheduled" }, { kind: "page", home: true }
    ])

    assert_equal [ [ "fill", "box", 14, 10, 4, "ink" ] ], live
    assert_equal [ [ "fill", "box", 14, 10, 4, "surface" ], [ "stroke", "box", 14, 10, 4, "meta", 1.5, DASHED ] ], draft
    assert_equal [ [ "fill", "box", 14, 10, 4, "surface" ], [ "stroke", "box", 14, 10, 4, "dim", 1.5, SOLID ], [ "fill", "circle", 2, "warn" ] ], scheduled
    assert_equal live + CORNER.call("dim"), changed, "unpublished changes: a dim corner dot"
    assert_equal live + CORNER.call("warn"), pending, "a change scheduled: a warn corner dot"
    assert_equal [ [ "fill", "box", 18, 13, 4, "ink" ] ], home
  end

  test "marks: a filled post in each of the five looks, a draft dashed in meta" do
    live, draft, scheduled, changed, pending = marks_drawn([
      {}, { status: "draft" }, { status: "scheduled" }, { changes: "unpublished" }, { changes: "scheduled" }
    ])

    assert_equal [ [ "fill", "circle", 7, "cat-1" ], [ "stroke", "circle", 7, "cat-1", 1.5, SOLID ] ], live
    assert_equal [ [ "fill", "circle", 7, "surface" ], [ "stroke", "circle", 7, "meta", 1.5, DASHED ] ], draft
    assert_equal [ [ "fill", "circle", 7, "surface" ], [ "stroke", "circle", 7, "dim", 1.5, SOLID ], [ "fill", "circle", 2, "warn" ] ], scheduled
    assert_equal live + CORNER.call("dim"), changed
    assert_equal live + CORNER.call("warn"), pending
  end

  # Third design answers, "Ring types": the type's mark inside a 1.5px ring,
  # so the five looks are a filled post's, drawn at 4/7 of the radius.
  test "marks: a ring type is its type's mark inside a thin ring, in the same five looks, a retired type's has its stroke, and the inner mark is 4/7 rounded to half a pixel" do
    ring = [ [ "fill", "circle", 7, "surface" ], [ "stroke", "circle", 7, "cat-1", 1.5, SOLID ] ]
    live, draft, scheduled, changed, pending, retired, retired_draft = marks_drawn([
      { colour_index: 7 }, { colour_index: 7, status: "draft" }, { colour_index: 7, status: "scheduled" }, { colour_index: 7, changes: "unpublished" },
      { colour_index: 7, changes: "scheduled" }, { colour_index: nil }, { colour_index: nil, status: "draft" }
    ])

    assert_equal ring + [ [ "fill", "circle", 4, "cat-1" ] ], live, "the ring at radius 7 with a filled radius-4 disk"
    assert_equal ring + [ [ "fill", "circle", 4, "surface" ], [ "stroke", "circle", 4, "meta", 1.5, DASHED ] ], draft
    assert_equal ring + [ [ "fill", "circle", 4, "surface" ], [ "stroke", "circle", 4, "dim", 1.5, SOLID ], [ "fill", "circle", 2, "warn" ] ], scheduled
    assert_equal live + CORNER.call("dim"), changed
    assert_equal live + CORNER.call("warn"), pending
    grey = [ [ "fill", "circle", 7, "surface" ], [ "stroke", "circle", 7, "meta", 1.5, SOLID ] ]
    assert_equal grey + [ [ "fill", "circle", 4, "meta" ], [ "stroke", "line", "meta", 1.5, SOLID ] ], retired
    assert_equal grey + [ [ "fill", "circle", 4, "surface" ], [ "stroke", "circle", 4, "meta", 1.5, DASHED ], [ "stroke", "line", "meta", 1.5, SOLID ] ], retired_draft
    # Design answer H3: at every size, to the nearest half pixel.
    inner = marks_drawn([ { colour_index: 7, degree: 1 }, { colour_index: 7, degree: 4 }, { colour_index: 7, degree: 9 }, { colour_index: 7, degree: 20 } ]).map { |drawn| [ drawn[0][2], drawn[2][2] ] }
    assert_equal [ [ 7, 4 ], [ 10, 5.5 ], [ 13, 7.5 ], [ 16, 9 ] ], inner
  end

  # Design answers G1 to G3, H3 and H4: the hub's inner ring; a ring type's
  # hub, a ring in the hue round a filled centre; a retired type's hub, the
  # same shape in dim with a DASHED ring, so the two differ by more than
  # colour; "All posts" filled; and the pill, which grows to fit its words.
  test "marks: a type hub is a 12px circle in its colour with a surface ring, a ring type's a ring round a centre, All posts filled in dim, a retired type's a dashed outline in dim, a tag a square, more a pill with its words" do
    type, ring_type, all, retired, tag, more, long = marks_drawn([
      { kind: "type", id: "type-blog" }, { kind: "type", id: "type-b", colour_index: 8 }, { kind: "type", id: "all-posts", colour_index: nil },
      { kind: "type", id: "type-gone", colour_index: nil }, { kind: "tag" }, { kind: "more", title: "+92 more" }, { kind: "more", title: "+1,980 more", width: 82 }
    ])

    assert_equal [ [ "fill", "circle", 6, "cat-1" ], [ "stroke", "circle", 3.75, "surface", 1.5, SOLID ] ], type
    assert_equal [ [ "fill", "circle", 6, "surface" ], [ "stroke", "circle", 6, "cat-2", 1.5, SOLID ], [ "fill", "circle", 3, "cat-2" ] ], ring_type
    assert_equal [ [ "fill", "circle", 6, "dim" ], [ "stroke", "circle", 3.75, "surface", 1.5, SOLID ] ], all
    assert_equal [ [ "fill", "circle", 6, "surface" ], [ "stroke", "circle", 6, "dim", 1.5, DASHED ], [ "fill", "circle", 2, "dim" ] ], retired
    assert_equal [ [ "fill", "box", 9, 9, "surface" ], [ "stroke", "box", 9, 9, "meta", 1.5, SOLID ] ], tag
    assert_equal [ [ "fill", "box", 60, 16, 8, "surface" ], [ "stroke", "box", 60, 16, 8, "line", 1, SOLID ], [ "text", "+92 more", "count", "dim" ] ], more
    assert_equal [ [ "fill", "box", 82, 16, 8, "surface" ], [ "stroke", "box", 82, 16, 8, "line", 1, SOLID ], [ "text", "+1,980 more", "count", "dim" ] ], long
  end

  test "marks: a page's, a type's and the pill's size does not follow its connections, the pill is as wide as its words need and never under 60, and the layout keeps a box's diagonal clear" do
    sizes = js_module("mind_graph/marks", <<~JS)
      [ { kind: "page", degree: 1 }, { kind: "page", degree: 40 }, { kind: "page", home: true, degree: 2 }, { kind: "type", degree: 30 }, { kind: "more", degree: 1 }, { kind: "more", width: 82 } ]
        .map((node) => [ m.radiusFor(node), Math.round(m.collisionRadius(node) * 100) / 100 ])
    JS

    assert_equal [ [ 7, 8.6 ], [ 7, 8.6 ], [ 9, 11.1 ], [ 6, 6 ], [ 30, 31.05 ], [ 41, 41.77 ] ], sizes
    assert_equal [ { "width" => 60, "height" => 16 }, { "width" => 82, "height" => 16 }, nil ], js_module("mind_graph/marks", '[m.boxOf({ kind: "more" }), m.boxOf({ kind: "more", width: 82 }), m.boxOf({ kind: "type" })]')
    assert_equal [ 60, 60, 82, 83 ], js_module("mind_graph/marks", "[m.moreWidth(20), m.moreWidth(44), m.moreWidth(66), m.moreWidth(66.2)]"), "8px each side, a whole number of pixels, never under 60 (design answer H4)"
  end

  test "hit test: a box is pressed on the box, not on a circle as wide as it" do
    hits = js_module("mind_graph/hit_test", <<~JS)
      (() => {
        const at = (sx, sy) => m.nodeAt({ positions: Float32Array.from([ 100, 100, 300, 100 ]), indexes: [ 0, 1 ], radii: [ 30, 7 ], boxes: [ { width: 60, height: 16 }, null ],
                                          camera: { k: 1, tx: 0, ty: 0 }, sx, sy })
        return [ at(100, 100), at(128, 106), at(100, 124), at(140, 100), at(300, 109), at(100, 111) ]
      })()
    JS

    assert_equal [ 0, 0, -1, -1, 1, 0 ], hits, "inside the pill; 24px above its centre is not on it though its radius is 30; a dot keeps its circle; the least target is still 24px high"
  end
```

  The lines, with a second helper that answers each stroked pass that holds a line as `[colour, width, dash, strength, cap]`:

```ruby
  def lines_drawn(kinds, k: 1, selected: -1)
    drawn = page.evaluate_async_script(<<~JS, kinds, k, selected)
      const [kinds, k, selected, done] = arguments
      import("mind_graph/renderer").then(({ draw, radiusFor }) => {
        const log = []
        const set = { dash: [] }
        let lines = 0
        const context = new Proxy({}, {
          get: (_, name) => {
            if (name === "beginPath") return () => { lines = 0 }
            if (name === "lineTo") return () => { lines += 1 }
            if (name === "setLineDash") return (dash) => { set.dash = dash }
            if (name === "stroke") return () => { if (lines) log.push([set.strokeStyle, set.lineWidth, set.dash, Math.round(set.globalAlpha * 1000) / 1000, set.lineCap]); lines = 0 }
            return () => {}
          },
          set: (_, name, value) => { set[name] = value; return true }
        })
        const nodes = [0, 1, 2].map((id) => ({ id, kind: "tag", degree: 1, label: "" }))
        draw(context, {
          width: 400, height: 100, ratio: 1, camera: { k, tx: 0, ty: 0 },
          theme: { ink: "ink", meta: "meta", dim: "dim", warn: "warn", surface: "surface", sunken: "sunken", accent: "accent", line: "line", faint: "faint", radius: 4, categories: Array(6).fill("hue"), font: "", strongFont: "", monoFont: "" },
          nodes, edges: kinds.map((kind) => ({ source: 0, target: 1, kind })), positions: Float32Array.from([ 10 / k, 10 / k, 60 / k, 10 / k, 300 / k, 80 / k ]),
          radii: nodes.map(radiusFor), widths: [0, 0, 0], visibleNodes: [0, 1, 2], visibleEdges: kinds.map((_, index) => index),
          labels: [], selected, neighbours: new Set(selected === 0 ? [1] : []), focusIndex: -1, hovered: -1, pinned: new Set()
        })
        done(log)
      }).catch((error) => done({ error: String(error) }))
    JS
    flunk "renderer: #{drawn["error"]}" if drawn.is_a?(Hash)
    drawn
  end

  # Design answer G3: the Lists line is 1.5px with round caps and a dash of
  # 0.1 / 3.5, which is what makes its dots round. A hub's line to what it
  # brings in is the faint 1px line of G2.
  LINES = { "tag" => [ "meta", 1, [ 4, 3 ], 0.8, "butt" ], "related" => [ "ink", 1.5, [], 0.35, "butt" ], "brings" => [ "faint", 1, [], 1, "butt" ],
            "lists" => [ "dim", 1.5, [ 0.1, 3.5 ], 1, "round" ], "tree" => [ "line", 1, [], 1, "butt" ] }.freeze

  test "renderer: each kind of line has its style, one path per style, and below 40 percent zoom a shared tag's is not drawn" do
    kinds = %w[tree lists related tag brings]

    assert_equal LINES.values, lines_drawn(kinds), "in the order they are drawn: a shared tag's first, the tree's on top"
    assert_equal LINES.except("tag").values, lines_drawn(kinds, k: 0.39)
    assert_equal 5, lines_drawn(kinds, k: 0.4).size
    assert_equal 1, lines_drawn(%w[tree tree tree]).size, "three lines of one style are one path"
  end

  test "renderer: a selection brightens its own lines in ink, half a pixel wider, and keeps each kind's dash and cap" do
    assert_equal LINES.values.map { |_colour, width, dash, _alpha, cap| [ "ink", width + 0.5, dash, 0.9, cap ] }, lines_drawn(%w[tree lists related tag brings], selected: 0)
  end
```

  The order of the labels, and the labels that are outside the budget:

```ruby
  test "graph data: the payload becomes nodes of five kinds, All posts, more and a retired type named by the page's own words" do
    nodes = js_module("mind_graph/graph_data", <<~JS)
      m.nodesOf({ nodes: [ { id: "post-1", title: "P" } ], tags: [ { id: "tag-1", name: "t" } ], pages: [ { id: "page-1", title: "Home", home: true } ],
                  types: [ { id: "all-posts", label: null, colour_index: null }, { id: "type-blog", label: "Blog", colour_index: 1 }, { id: "type-gone/thing", label: "gone/thing", colour_index: null } ],
                  more: [ { id: "more-type-blog", count: 3, page: "page-1", target: "type-blog" }, { id: "more-tag-1", count: 1980, page: "page-1", target: "tag-1" } ] },
                { allPosts: "All posts", more: (count) => `+${count} more`, retired: (name) => `${name} (retired)` }).map((node) => [ node.id, node.kind, node.title ])
    JS

    assert_equal [ [ "page-1", "page", "Home" ], [ "post-1", "post", "P" ], [ "tag-1", "tag", "t" ], [ "all-posts", "type", "All posts" ],
                   [ "type-blog", "type", "Blog" ], [ "type-gone/thing", "type", "gone/thing (retired)" ], [ "more-type-blog", "more", "+3 more" ], [ "more-tag-1", "more", "+1980 more" ] ], nodes,
      "a pill per target; the figure's separator is the caller's (`more`), which the app gives it"
    assert_equal [ "post-1" ], js_module("mind_graph/graph_data", 'm.nodesOf({ nodes: [ { id: "post-1", title: "P" } ], tags: [], edges: [] }, {}).map((node) => node.id)'),
      "a payload without pages, types or more is the graph of posts and tags"
  end

  test "graph data: labels go to Home, then top-level pages and type nodes, then hubs, a page ahead of a post with as many links" do
    order = js_module("mind_graph/graph_data", <<~JS)
      (() => {
        const nodes = [ { kind: "post", degree: 9 }, { kind: "page", depth: 2, degree: 3 }, { kind: "post", degree: 3 }, { kind: "type", degree: 1 },
                        { kind: "page", depth: 1, degree: 1 }, { kind: "page", depth: 0, home: true, degree: 0 }, { kind: "tag", degree: 4 }, { kind: "more", degree: 1 } ]
        const all = nodes.map((_, index) => index)
        return { order: m.orderOf(nodes, all), free: Array.from(m.freeOf(nodes, all)).sort(), some: m.orderOf(nodes, [ 2, 1 ]) }
      })()
    JS

    assert_equal [ 5, 4, 3, 0, 6, 1, 2 ], order["order"], "Home; the top-level page ahead of the type by its bonus; then by links, the page of three ahead of the post of three; the pill has its words in it and is never labelled"
    assert_equal [ 3, 4, 5 ], order["free"]
    assert_equal [ 1, 2 ], order["some"]
  end

  test "labels: the free set is labelled at any zoom and uses up none of the budget, and no overlap still wins" do
    labelled = js_module("mind_graph/labels", <<~JS)
      (() => {
        const n = 100
        const positions = new Float32Array(n * 2)
        for (let i = 0; i < n; i++) { positions[i * 2] = (i % 10) * 400; positions[i * 2 + 1] = Math.floor(i / 10) * 400 }
        positions[198] = positions[196] + 2; positions[199] = positions[197]
        const order = Array.from({ length: n }, (_, i) => i)
        const args = { order, positions, widths: new Array(n).fill(20), radii: new Array(n).fill(8), camera: { k: 0.1, tx: 0, ty: 0 }, width: 100000, height: 100000, always: new Set() }
        return { plain: m.chooseLabels(args).map((label) => label.index), free: m.chooseLabels({ ...args, free: new Set([ 97, 98, 99 ]) }).map((label) => [ label.index, label.alpha ]) }
      })()
    JS

    assert_equal [ 0 ], labelled["plain"], "at this zoom the budget is one label"
    assert_equal [ [ 97, 1 ], [ 98, 1 ], [ 0, 1 ] ], labelled["free"], "97 and 98 are free; 99 would lie on 98's and gives way; the budget's one label is still placed"
  end
```

  And the worker:

```ruby
  test "the layout holds the anchor at the centre, keeps a tree line shorter than another, and gives a dragged anchor back to the centre when it is released" do
    result = using_wait_time(40) do
      page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"), ActionController::Base.helpers.asset_path("d3-force.js"))
        const [workerUrl, d3Url, done] = arguments
        import("mind_graph/layout_client").then(({ createLayout }) => {
          let last = null
          const seen = []
          const layout = createLayout({
            workerUrl, d3Url,
            onTick: (positions) => { last = Array.from(positions) },
            onSettled: () => {
              seen.push(last)
              if (seen.length === 1) { layout.drag("page-1", 200, -100); layout.drop("page-1") }
              else if (seen.length === 2) layout.unpin([ "page-1" ])
              else { layout.stop(); done({ seen }) }
            },
            onError: (message) => done({ error: message })
          })
          layout.start([ { id: "page-1", radius: 11, anchor: true }, { id: "page-2", radius: 9 }, { id: "post-1", radius: 7 } ],
                       [ { source: "page-2", target: "page-1", kind: "tree" }, { source: "post-1", target: "page-1", kind: "lists" } ], { reducedMotion: true })
        })
      JS
    end

    assert_nil result["error"]
    rest, dragged, released = result["seen"]
    assert_equal [ 0, 0 ], rest.first(2)
    assert_operator Math.hypot(rest[2], rest[3]), :<, Math.hypot(rest[4], rest[5]) - 20, "the tree line is not the shorter one"
    assert_in_delta 200, dragged[0], 0.01
    assert_in_delta(-100, dragged[1], 0.01)
    assert_equal [ 0, 0 ], released.first(2), "a released anchor did not go back to the centre"
  end
```

  Run: `bin/rails tailwindcss:build && PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/mind_graph_modules_test.rb`
  Expected: the new tests FAIL (`Failed to resolve module specifier "mind_graph/marks"`, a page drawn as a circle, one style for the new lines, the pill pressed 24px above itself, `free` ignored, the anchor not at 0, 0); every test that was there PASSES.

- [ ] **Step 2: the theme.** In `app/javascript/mind_graph/theme.js`:

```js
// `line` is the border of the notes badge and of the "+N more" pill, and the
// tree's lines; `faint` a hub's lines to what it brings in; `dim` the lists
// lines, a scheduled record's outline, a post's label and the dot of a live
// record with unpublished changes; `warn` means "scheduled", as on the
// status chip: a scheduled record's centre dot and a scheduled change's.
const TOKENS = { ink: "--cs-ink", meta: "--cs-meta", dim: "--cs-dim", warn: "--cs-warn", surface: "--cs-surface", sunken: "--cs-sunken", accent: "--cs-accent", line: "--cs-line-strong", faint: "--cs-line" }
```

  and in `readTheme`, before `return theme`:

```js
  // A tag's label: mono, like a tag everywhere else in CS Studio.
  theme.monoFont = `12px ${read("--cs-mono") || style.fontFamily}`
  // The card's corner radius, for a page's mark: a length in pixels.
  theme.radius = Number.parseFloat(read("--cs-radius")) || 0
```

  (`--cs-radius` is `2px` in `app/assets/tailwind/content-spiel.css`; `parseFloat` reads a pixel length and nothing else, which the comment says.)

- [ ] **Step 3: the marks.** Create `app/javascript/mind_graph/marks.js`:

```js
// Every mark of the mind graph and its size (mind graph canvas spec §5.1;
// pages in the mind graph, spec §4, whose values are the design answer's --
// its third part where that replaces the earlier ones).
// Everything is in SCREEN pixels, the same at every zoom.
//
// THE KINDS, each a shape of its own so none is told by colour alone:
// - a POST is a dot filled with its type's hue (colour slots 1-6). A RING
//   TYPE (7-12; 13+ cycle) is the same mark, smaller, inside a thin ring of
//   the hue; a post of a type that is no longer registered is a ring type
//   in `meta` with a stroke through it;
// - a PAGE is a small card, 14 by 10 with the card's corner radius, Home 18
//   by 13, in neutral ink (the hues mean post types). Fixed: a page's size
//   does not follow its connections;
// - a POST TYPE a page lists is a hub: a 12px circle in the type's hue with a
//   surface ring inside it, so it is not one more post. "All posts" is the
//   same, filled in `dim`. A RING TYPE's hub is a ring in the hue round a
//   filled centre; a RETIRED type's is a DASHED ring in `dim` round a small
//   `dim` centre: it differs from "All posts" by fill, not by shade, and
//   from a ring type's hub by its dashes;
// - a TAG is a square; "+N more" is a pill with its words inside it.
//
// THE STATE, one rule for a page and a post (spec §4; never worked out
// here: `status` and `changes` are `Publishing::State`'s, from the data).
// WARN MEANS "SCHEDULED", as on CS Studio's status chip:
//   live                       filled
//   draft                      a DASHED outline, 1.5px `meta`, surface inside
//   scheduled                  an outline in `dim`, with a `warn` centre dot
//   live with changes          filled, with a `dim` dot at the bottom right
//   live, a change scheduled   filled, with a `warn` dot at the bottom right
// A ring type's inner mark carries the same five, unchanged. A draft is
// dashed on every mark, so no state rests on colour alone. The corners are
// then: notes top-left, pin top-right (`renderer.js`), changes bottom-right.
//
// Nothing here is a colour: every one comes in with `theme` (`theme.js`).
// Up to this many connections: a post's radius, a tag's half side.
const STEPS = [ [ 2, 7, 4.5 ], [ 5, 10, 6 ], [ 12, 13, 8.25 ], [ Infinity, 16, 10.5 ] ]
const PAGE_BOX = { width: 14, height: 10 }
const HOME_BOX = { width: 18, height: 13 }
// "+N more" (design answers G2, H4): a pill that grows to fit its words,
// 8px each side, and is never narrower than 60.
const MORE_HEIGHT = 16
const MORE_MIN_WIDTH = 60
const MORE_PADDING = 8
// A ring type's hub (H3): a ring in the hue round a filled centre 6px across.
const RING_HUB_CENTRE = 3
const TYPE_RADIUS = 6
// The design answer's exact readings (G3). The hub's inner ring is 1.5px
// wide with its outer edge 1.5px inside the hub's radius: from 3 to 4.5.
const TYPE_RING = { radius: 3.75, width: 1.5 }
// A scheduled record's centre dot, 4px across (and a retired hub's, G1).
const CENTRE_DOT = 2
// The corner dot: 5px across, its centre 1px in from the mark's bottom-right
// corner (on the 45° line for a circle), with a 1.5px surface ring.
const CORNER_DOT = 2.5
const CORNER_INSET = 1
const CORNER_RING = 1.5
const OUTLINE = 1.5
// A ring type's inner mark: 4/7 of the outer radius at every size, rounded
// to the nearest half pixel (G3, H3): 4 in 7, 5.5 in 10, 7.5 in 13, 9 in 16.
const innerRadius = (radius) => Math.round((radius * 4 / 7) * 2) / 2
// A reading: the dash a draft has today.
const DRAFT_DASH = [ 3, 2.5 ]

// A pill's width for its words as the canvas measures them (`app.js` writes
// the answer on the node as `width`).
export const moreWidth = (wordsWidth) => Math.max(MORE_MIN_WIDTH, Math.ceil(wordsWidth) + MORE_PADDING * 2)

export const boxOf = (node) =>
  node.kind === "page" ? (node.home ? HOME_BOX : PAGE_BOX) : node.kind === "more" ? { width: node.width ?? MORE_MIN_WIDTH, height: MORE_HEIGHT } : null

// Four sizes by degree for a post and a tag: small differences in size can't
// be read, so a hub is one of four steps, not a point on a scale. A box's
// is half its width (a page's label starts beside it), a type hub's is fixed.
export function radiusFor(node) {
  const box = boxOf(node)
  if (box) return box.width / 2
  if (node.kind === "type") return TYPE_RADIUS
  const [ , post, tag ] = STEPS.find(([ upTo ]) => (node.degree ?? 0) <= upTo)
  return node.kind === "tag" ? tag : post
}

// What the layout keeps clear around a node: a box's is half its diagonal.
export function collisionRadius(node) {
  const box = boxOf(node)
  return box ? Math.hypot(box.width, box.height) / 2 : radiusFor(node)
}

export function drawMark(context, theme, node, x, y, radius) {
  context.setLineDash([])
  if (node.kind === "tag") return drawTag(context, theme, x, y, radius)
  if (node.kind === "type") return drawType(context, theme, node, x, y)
  if (node.kind === "more") return drawMore(context, theme, node, x, y)

  if (node.kind === "page") drawPage(context, theme, node, x, y)
  else drawPost(context, theme, node, x, y, radius)
  if (node.status !== "live" || !node.changes) return

  // The corner dot, on the WHOLE mark's corner (a ring type's is the ring's):
  // `dim` for changes nobody has published, `warn` for a change that is
  // scheduled. Its surface ring is a disk under it.
  const box = boxOf(node)
  const reach = (radius - CORNER_INSET) * Math.SQRT1_2
  const cornerX = box ? x + box.width / 2 - CORNER_INSET : x + reach
  const cornerY = box ? y + box.height / 2 - CORNER_INSET : y + reach
  dot(context, theme.surface, cornerX, cornerY, CORNER_DOT + CORNER_RING)
  dot(context, node.changes === "scheduled" ? theme.warn : theme.dim, cornerX, cornerY, CORNER_DOT)
}

// Strokes the path that is open, and leaves no dash behind.
function outline(context, colour, { dashed = false, width = OUTLINE } = {}) {
  context.strokeStyle = colour
  context.lineWidth = width
  context.setLineDash(dashed ? DRAFT_DASH : [])
  context.stroke()
  context.setLineDash([])
}

function dot(context, colour, x, y, radius) {
  context.beginPath()
  context.arc(x, y, radius, 0, Math.PI * 2)
  context.fillStyle = colour
  context.fill()
}

function fill(context, colour) {
  context.fillStyle = colour
  context.fill()
}

// The state of the mark whose path is open, centred on x, y: filled with
// `colour` when live (the path stays open, for a caller that outlines it),
// a dashed `meta` outline as a draft, a `dim` outline with the `warn`
// centre dot when scheduled. One rule for a page, a post and a ring type's
// inner mark.
function look(context, theme, node, colour, x, y) {
  if (node.status === "live") return fill(context, colour)

  fill(context, theme.surface)
  if (node.status === "draft") return outline(context, theme.meta, { dashed: true })

  outline(context, theme.dim)
  dot(context, theme.warn, x, y, CENTRE_DOT)
}

function drawPage(context, theme, node, x, y) {
  const { width, height } = boxOf(node)
  context.beginPath()
  // A card where the canvas can round one; a plain rectangle where it can't
  // (a missing method would throw inside the draw and take the canvas with it).
  if (typeof context.roundRect === "function") context.roundRect(x - width / 2, y - height / 2, width, height, theme.radius ?? 0)
  else context.rect(x - width / 2, y - height / 2, width, height)
  look(context, theme, node, theme.ink, x, y)
}

function drawPost(context, theme, node, x, y, radius) {
  const retired = node.colour_index == null
  const slot = retired ? null : (node.colour_index - 1) % 12
  const hue = retired ? theme.meta : theme.categories[slot % 6]
  const ring = retired || slot >= 6

  context.beginPath()
  context.arc(x, y, radius, 0, Math.PI * 2)
  if (ring) {
    // A ring type (third design answers): the ring, thin and always solid,
    // and inside it the type's mark in whichever of the five looks.
    fill(context, theme.surface)
    outline(context, hue)
    context.beginPath()
    context.arc(x, y, innerRadius(radius), 0, Math.PI * 2)
    look(context, theme, node, hue, x, y)
  } else {
    look(context, theme, node, hue, x, y)
    // A live post's own outline, as it has today.
    if (node.status === "live") outline(context, hue)
  }
  if (!retired) return

  const reach = radius * 0.72
  context.beginPath()
  context.moveTo(x - reach, y + reach)
  context.lineTo(x + reach, y - reach)
  outline(context, hue)
}

function drawType(context, theme, node, x, y) {
  const retired = node.id !== "all-posts" && node.colour_index == null
  const slot = node.colour_index == null ? null : (node.colour_index - 1) % 12
  // A RING TYPE's hub (slots 7-12; design answer H3) is not filled: a ring
  // in the hue round a filled centre. A RETIRED type's (G1, H3) is the same
  // shape in `dim` with a DASHED ring and a smaller centre, so the two
  // differ by more than colour; and "All posts" is FILLED in `dim`, so it
  // differs from a retired hub by fill, not by shade.
  if (retired || slot >= 6) {
    const hue = retired ? theme.dim : theme.categories[slot % 6]
    context.beginPath()
    context.arc(x, y, TYPE_RADIUS, 0, Math.PI * 2)
    fill(context, theme.surface)
    outline(context, hue, { dashed: retired })
    return dot(context, hue, x, y, retired ? CENTRE_DOT : RING_HUB_CENTRE)
  }

  dot(context, node.id === "all-posts" ? theme.dim : theme.categories[slot], x, y, TYPE_RADIUS)
  context.beginPath()
  context.arc(x, y, TYPE_RING.radius, 0, Math.PI * 2)
  outline(context, theme.surface, { width: TYPE_RING.width })
}

// "+N more" (design answer G2): a pill on surface with a strong line round
// it and its words inside, in the small mono style the notes badge has.
// `save` and `restore` leave the text settings as the labels expect them.
function drawMore(context, theme, node, x, y) {
  const { width, height } = boxOf(node)
  context.save()
  context.beginPath()
  if (typeof context.roundRect === "function") context.roundRect(x - width / 2, y - height / 2, width, height, height / 2)
  else context.rect(x - width / 2, y - height / 2, width, height)
  fill(context, theme.surface)
  outline(context, theme.line, { width: 1 })
  context.font = theme.countFont
  context.textAlign = "center"
  context.textBaseline = "middle"
  context.fillStyle = theme.dim
  context.fillText(node.title, x, y)
  context.restore()
}

function drawTag(context, theme, x, y, half) {
  context.fillStyle = theme.surface
  context.strokeStyle = theme.meta
  context.lineWidth = 1.5
  context.fillRect(x - half, y - half, half * 2, half * 2)
  context.strokeRect(x - half, y - half, half * 2, half * 2)
}
```

- [ ] **Step 4: the renderer.** In `app/javascript/mind_graph/renderer.js`:
  - Delete `STEPS`, `radiusFor`, `drawTag` and `drawPost`; add at the top `import { drawMark, boxOf, radiusFor } from "mind_graph/marks"` and `export { radiusFor }` (the app and the module tests import it from here).
  - The header comment's part about the mark ("A node's mark carries two cues …" down to "A tag is a square. A related edge is solid, a shared tag's dashed.") becomes two lines: the marks and the states are `marks.js`'s; the lines are the five styles below.
  - The lines:

```js
// One path per style (pages spec §4): Shares a tag dashed `meta`, Related
// solid ink, a hub's line to what it brings in faint, Lists dotted `dim`,
// Tree solid in the strong line colour. Drawn in this order, so a tree line
// is on top of a tag's. A value of `colour` is a theme key.
//
// LISTS (design answer G3): 1.5px with ROUND caps and a dash of 0.1 / 3.5.
// A dash that short is its two caps, so each is a round dot 1.5px across,
// 3.6px from the next; with a butt cap it would be a hairline.
// BRINGS (the third answers' "Local view lines", G2): a page's local view
// only, the hub's line to each post it brings in and to "+N more".
export const LINE_STYLES = {
  tag: { colour: "meta", width: 1, dash: [ 4, 3 ], alpha: 0.8, cap: "butt" },
  related: { colour: "ink", width: 1.5, dash: [], alpha: 0.35, cap: "butt" },
  brings: { colour: "faint", width: 1, dash: [], alpha: 1, cap: "butt" },
  lists: { colour: "dim", width: 1.5, dash: [ 0.1, 3.5 ], alpha: 1, cap: "round" },
  tree: { colour: "line", width: 1, dash: [], alpha: 1, cap: "butt" }
}
// Below this zoom the lines of shared tags are not drawn: zoomed out they
// are most of the ink and say the least. A DRAWING rule only: the legend's
// toggle, its counts and a selection's neighbours do not change with it.
export const HIDE_TAG_LINES_BELOW = 0.4
```

    and the loop `for (const kind of [ "tag", "related" ])` becomes

```js
  for (const [ kind, style ] of Object.entries(LINE_STYLES)) {
    if (kind === "tag" && camera.k < HIDE_TAG_LINES_BELOW) continue
    for (const pass of selected < 0 ? [ "plain" ] : [ "faded", "bright" ]) {
      context.beginPath()
      for (const edgeIndex of visibleEdges) {
        const edge = edges[edgeIndex]
        if (edge.kind !== kind) continue
        const touchesSelection = edge.source === selected || edge.target === selected
        if (pass !== "plain" && touchesSelection !== (pass === "bright")) continue
        const fromX = x(edge.source), fromY = y(edge.source), toX = x(edge.target), toY = y(edge.target)
        if (beyond(fromX, fromY, EDGE_MARGIN) & beyond(toX, toY, EDGE_MARGIN)) continue
        context.moveTo(fromX, fromY)
        context.lineTo(toX, toY)
      }
      const bright = pass === "bright"
      context.globalAlpha = bright ? 0.9 : style.alpha * (pass === "faded" ? DIM : 1)
      context.strokeStyle = bright ? theme.ink : theme[style.colour]
      context.lineWidth = style.width + (bright ? 0.5 : 0)
      context.lineCap = style.cap
      context.setLineDash(style.dash)
      context.stroke()
    }
  }
  // The marks, the pin and the rings are drawn with the cap they expect.
  context.lineCap = "butt"
```

  - The nodes' loop draws through `drawMark`, and the notes badge is a post's and a page's:

```js
    drawMark(context, theme, nodes[index], x(index), y(index), radii[index])
    if (pinned.has(index)) drawPin(context, theme, x(index), y(index), radii[index])
    if ((nodes[index].open_notes ?? 0) > 0 && (nodes[index].kind === "post" || nodes[index].kind === "page")) drawNotes(context, theme, nodes[index], x(index), y(index), radii[index])
```

    (the old condition was `kind !== "tag"`: a type and "more" carry no `open_notes`, and the condition now says what it means). A label that is empty is not drawn at all, hovered or not: the first line of the labels' loop becomes `if (!node.label) continue` after `const node = nodes[label.index]` (the pill's words are inside it, and its hover would otherwise draw an empty backing beside it).
  - The labels' font and colour, in place of the two lines that set `context.font` and, further down, `context.fillStyle = node.kind === "tag" ? theme.meta : theme.ink`:

```js
// A label's colour by kind, as a theme key (pages spec §4): a page's and a
// type's read first, a post's is `dim` until it is hovered or selected.
const LABEL_COLOURS = { page: "ink", type: "ink", tag: "meta", post: "dim", more: "dim" }
```

```js
    const chosen = label.index === selected
    context.font = chosen ? theme.strongFont : node.kind === "tag" ? theme.monoFont : theme.font
```

```js
    context.fillStyle = chosen ? theme.ink : theme[LABEL_COLOURS[node.kind]]
```

  - A ring follows its mark's shape (a page's card and the pill are boxes):

```js
  const ring = (index, distance) => {
    const box = boxOf(nodes[index])
    const reach = radii[index] + distance
    context.beginPath()
    if (nodes[index].kind === "tag") context.rect(x(index) - reach, y(index) - reach, reach * 2, reach * 2)
    else if (box) context.rect(x(index) - box.width / 2 - distance, y(index) - box.height / 2 - distance, box.width + distance * 2, box.height + distance * 2)
    else context.arc(x(index), y(index), reach, 0, Math.PI * 2)
    context.stroke()
  }
```

  - **The hit test knows a box.** In `app/javascript/mind_graph/hit_test.js`, the header's paragraph "The dot." gains: "A BOX (a page's card, the "+N more" pill: `boxes`, from `marks.js`'s `boxOf`) is pressed on the box itself, grown by the same slack and never less than MIN_TARGET either way: the pill is 60 wide and 16 high, and a circle as wide as it would take every press 25 pixels above and below it." The signature gains `boxes = []`, and the first loop's test becomes:

```js
    const box = boxes[index]
    const hit = box
      ? Math.abs(dx) <= Math.max(box.width / 2 + slack, MIN_TARGET / 2) && Math.abs(dy) <= Math.max(box.height / 2 + slack, MIN_TARGET / 2)
      : distance <= Math.max(radii[index] + slack, MIN_TARGET / 2)
    if (hit && distance < bestDistance) {
```

- [ ] **Step 5: the label rule.** In `app/javascript/mind_graph/labels.js`, rule 3 of the header gains a sentence and `chooseLabels` a parameter:

```js
// 4. `free` -- Home, the top-level pages and the post-type nodes (pages spec
//    §4) -- is labelled at any zoom and does NOT count against the budget of
//    rule 1. It places after `always` and before the ranked rest, in the
//    order of `order`. Rule 2 still holds: no overlap wins over "always
//    shown".
```

```js
export function chooseLabels({ order, positions, widths, radii, camera, width, height, always, free = new Set() }) {
```

  and after the loop over `always`:

```js
  for (const index of order) if (free.has(index) && !always.has(index) && onCanvas(index)) place(index, 1)

  let rank = 0
  for (const index of order) {
    if (rank >= reach) break
    if (free.has(index) || !onCanvas(index)) continue
    const alpha = rank < fadeFrom ? 1 : 1 - (rank - fadeFrom + 1) / (reach - fadeFrom + 1)
    rank += 1
    if (!always.has(index)) place(index, alpha)
  }
```

- [ ] **Step 6: the graph's data in the page.** Create `app/javascript/mind_graph/graph_data.js`:

```js
// The graph's data as the page holds it (pages in the mind graph, spec §1,
// §4): plain functions over the payload, with no canvas and no element, so
// each can be asked directly by a test.
//
// A node is `{ …what the server sent, kind, title }`; `kind` is "page",
// "post", "tag", "type" (a post type a page lists, and the one "All posts"
// node) or "more" (a "+N more" pill of a page's local view, one per target). Pages come
// first, in tree order as the server sends them.

// A page's fixed bonus over a post with as many links, in links.
const PAGE_BONUS = 0.5

// A type that is no longer registered has no colour slot, and is not "All
// posts" (design answer G1): its hub is drawn as an outline (`marks.js`) and
// its label ends "(retired)", in the messages' words.
const retiredType = (type) => type.id !== "all-posts" && type.colour_index == null

export function nodesOf(data, { allPosts, more, retired }) {
  return [
    ...(data.pages || []).map((page) => ({ ...page, kind: "page" })),
    ...data.nodes.map((node) => ({ ...node, kind: "post" })),
    ...data.tags.map((tag) => ({ ...tag, title: tag.name, kind: "tag" })),
    ...(data.types || []).map((type) => ({ ...type, title: type.id === "all-posts" ? allPosts : retiredType(type) ? retired(type.label) : type.label, kind: "type" })),
    ...(data.more || []).map((pill) => ({ ...pill, title: more(pill.count), kind: "more", degree: 1 }))
  ]
}

// Whose label comes first: Home, then the top-level pages and the type
// nodes, then everything else by its links.
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
```

- [ ] **Step 7: the worker.** In `app/javascript/mind_graph/layout_worker.js`:
  - The header's "Messages in" line for `start` reads `nodes: [{ id, radius, anchor }], edges: [{ source, target, kind }]`, and gains a paragraph:

```js
// LINES AND THE ANCHOR (pages in the mind graph, spec §5). A line's `kind`
// chooses its spring: a tree line is short and stiff (`LINKS.tree`), so a
// subtree stays together; every other kind is as before. The node marked
// `anchor` (Home) is HELD AT THE CENTRE while the layout runs: `fx` / `fy`
// are 0. It is not a pin: the page shows none and counts none. Dragged or
// pinned it is held where the person put it, like any node (`held`), and
// `unpin` gives it back to the centre, not to the forces. No pinning by
// depth and no rings by level: they would fight the post clusters.
```

  - Below `HELD_ALPHA`:

```js
// A line's spring by kind: its length at rest and how hard it pulls. A kind
// that is not named here has d3's own (90, and a strength that falls with
// the number of lines at its ends). The tree's are the spec's starting
// values, tuned at the measurement.
const DISTANCE = 90
const LINKS = { tree: { distance: 40, strength: 0.9 } }
```

  - `start` becomes:

```js
function start(givenNodes, givenEdges) {
  nodes = givenNodes.map((node) => ({ id: node.id, radius: node.radius, anchor: Boolean(node.anchor), held: false }))
  edges = givenEdges.map((edge, index) => ({ source: edge.source, target: edge.target, kind: edge.kind, index }))
  nodes.forEach(rest)
  shown = null
  const link = d3.forceLink(edges.slice()).id((node) => node.id).distance((edge) => LINKS[edge.kind]?.distance ?? DISTANCE)
  // d3's own strength, kept for every kind that names none: it reads the
  // force's own count of lines per node, which `links()` refreshes.
  const ordinary = link.strength()
  link.strength((edge, index, all) => LINKS[edge.kind]?.strength ?? ordinary(edge, index, all))
  simulation = d3.forceSimulation(nodes)
    // `distanceMax` bounds each node's repulsion to its surroundings: without
    // it every node pushes every other, which is what makes a large graph slow
    // and flings its outer nodes away.
    .force("charge", d3.forceManyBody().strength(-250).distanceMax(600))
    .force("link", link)
    .force("x", d3.forceX(0).strength(0.04))
    .force("y", d3.forceY(0).strength(0.04))
    .force("collide", d3.forceCollide((node) => node.radius + 10))
    .stop()
  pace = nodes.length <= SMALL_GRAPH ? "frame" : "fast"
  run()
}

// Where a node that nobody holds is kept: the anchor at the centre, every
// other node nowhere.
function rest(node) {
  node.held = false
  node.fx = node.anchor ? 0 : null
  node.fy = node.anchor ? 0 : null
}
```

  - In `handle`: under `drag`, after `node.fy = message.y`, add `node.held = true`; under `pin`, inside `if (node)`, add `node.held = true`; under `unpin`, `freed.forEach(rest)` replaces the loop that sets `fx` and `fy` to null.
  - In `filter`, a hidden node is let go as before and a shown anchor nobody holds is at the centre again:

```js
  nodes.forEach((node) => {
    if (nodeIds.has(node.id)) {
      if (node.anchor && !node.held) rest(node)
      return
    }
    node.held = false
    node.fx = null
    node.fy = null
  })
```

  In `layout_client.js` only the comment above `start` changes: a node may carry `anchor`, an edge carries `kind`; both are passed on as given.

- [ ] **Step 8: the app.** In `app/javascript/mind_graph/app.js`:
  - Imports: `import { draw, radiusFor } from "mind_graph/renderer"` stays; add `import { collisionRadius } from "mind_graph/marks"` and `import { nodesOf, orderOf, freeOf } from "mind_graph/graph_data"`.
  - `state` gains `free: new Set()` and `boxes: []`.
  - In `show`, the nodes, the edges (the filter of Task 3 goes: every end is a node now), the boxes and the widths:

```js
    state.nodes = nodesOf(data, {
      allPosts: text.t("mind_graph.script.all_posts"),
      more: (count) => text.t("mind_graph.script.more", { count: number(count) }),
      retired: (name) => text.t("mind_graph.script.retired_type", { name })
    })
    indexOf = new Map(state.nodes.map((node, index) => [ node.id, index ]))
    state.edges = data.edges.map((edge) => ({ kind: edge.kind, source: indexOf.get(edge.source), target: indexOf.get(edge.target) }))
```

    BEFORE `state.radii = state.nodes.map(radiusFor)`, each pill is given its width from its words as the canvas measures them (design answer H4; import `moreWidth` and `boxOf` with `collisionRadius`):

```js
    // A pill grows to fit its words: measured in the font they are drawn in.
    context.font = state.theme.countFont
    for (const node of state.nodes) if (node.kind === "more") node.width = moreWidth(context.measureText(node.title).width)
```

    after the radii, `state.boxes = state.nodes.map(boxOf)`; and in the loop that sets each node's label, the pill has none, since its words are inside it:

```js
      node.label = node.kind === "more" ? "" : labelFor(node)
```

    The hit test is handed the boxes: in the function that calls `nodeAt`, `boxes: state.boxes` joins its arguments.

```js
    // Each label is measured in the font it is drawn in: a tag's is mono.
    state.widths = state.nodes.map((node) => {
      context.font = node.kind === "tag" ? state.theme.monoFont : state.theme.font
      return context.measureText(node.label).width
    })
```

  - In `applyFilter`, `state.order = orderOf(state.nodes, state.visibleNodes)` replaces the sort by degree, followed by `state.free = freeOf(state.nodes, state.visibleNodes)`; in `requestDraw` the call reads `chooseLabels({ …, always, free: state.free })`.
  - In `startLayout`, what the worker is handed:

```js
    layout.start(state.nodes.map((node) => ({ id: node.id, radius: collisionRadius(node), anchor: node.kind === "page" && Boolean(node.home) })),
      state.edges.map((edge) => ({ source: state.nodes[edge.source].id, target: state.nodes[edge.target].id, kind: edge.kind })),
      { reducedMotion: reducedMotion.matches })
```

  - On `element.mindGraph`, for the test of the anchor (and listed in the header comment beside `screenPosition`):

```js
    // Where the layout has a node, in GRAPH units (the camera not applied):
    // Home's is 0, 0 while nobody holds it.
    graphPosition(id) {
      const index = indexOf.get(id)
      return index == null || !state.placed ? null : { x: state.positions[index * 2], y: state.positions[index * 2 + 1] }
    },
```

  In `card.js`, a kind without a card of its own yet shows what it is called, and Pin:

```js
  // A page, a post type and "+N more" until each has its card (pages plan,
  // Task 8): its name, and Pin.
  const plain = (node) => [ heading(), title(node), actions() ]
```

  and in `show`: `container.replaceChildren(...({ tag, post }[node.kind] || plain)(node), closeButton())`.

  The three strings. In `config/locales/admin/mind_graph.en.yml`, under `script`, after `summary`:

```yaml
        all_posts: "All posts"
        more: "+%{count} more"
        retired_type: "%{name} (retired)"
```

  (`more` takes `count` as a figure the script has already grouped, "+1,980 more" (design answer H4), not as a plural: it has one form; `retired_type` is a retired type's hub's whole label, the design answer's "(retired)" at its end), and the three keys join the `messages_data(...)` call in `show.html.erb` (`"mind_graph.script.all_posts", "mind_graph.script.more", "mind_graph.script.retired_type"`) and the list of keys in `"the script's messages ride on the element"` in `test/integration/admin/mind_graph_test.rb`. Add `app/javascript/mind_graph/marks.js` and `app/javascript/mind_graph/graph_data.js` to `CONVERTED` in `test/lib/admin_i18n_test.rb`.

- [ ] **Step 9: run the module tests and the guards.**

  Run: `bin/rails tailwindcss:build && PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/mind_graph_modules_test.rb && PGGSSENCMODE=disable bin/rails test test/lib test/integration/admin/mind_graph_test.rb test/integration/public_javascript_test.rb`
  Expected: PASS. `admin_design_rules_test` passes because no module holds a colour; `public_javascript_test` because nothing new is preloaded.

- [ ] **Step 10: two browser tests.** In `test/system/admin/mind_graph_test.rb`, add `def graph_position(id) = page.evaluate_script("document.querySelector(#{GRAPH.to_json}).mindGraph.graphPosition(#{nid(id).to_json})")` and:

```ruby
  # Pages spec §4, §5: pages, the post type a page lists and All posts are on
  # the canvas; Home rests at the centre of the layout and is no pin; dragged,
  # it is pinned where it is dropped, and released it goes back.
  test "pages and what they list are drawn, and Home rests at the centre without being pinned" do
    home = root_page
    blog = create_page(title: "Blog")
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    ContentBlock.create!(owner: home, block_type: :post_list, position: 0, settings: {})
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))

    visit admin_mind_graph_path
    await_graph

    assert_equal [ "6", "4" ], [ graph["data-nodes"], graph["data-edges"] ], "two pages, two posts, the type and All posts; a tree line, two lists lines and one related"
    [ home, blog, a, "type-blog", "all-posts" ].each { |node| assert screen_position(nid(node)), "#{nid(node)} is not drawn" }
    at = graph_position(home)
    assert_in_delta 0, at["x"], 0.5
    assert_in_delta 0, at["y"], 0.5
    assert_equal "0", graph["data-pinned"]
    assert_no_button "Release 1 pinned"
    assert_includes graph["data-labelled"].split(","), nid(home), "Home's label is placed first and always"

    drag_node(nid(home), by: [ 90, 60 ])
    assert_equal "1", graph["data-pinned"]
    await_graph
    assert_operator Math.hypot(graph_position(home)["x"], graph_position(home)["y"]), :>, 20, "a dragged Home is held where it was dropped"

    press "Release 1 pinned"
    await_graph
    assert_in_delta 0, graph_position(home)["x"], 0.5, "a released Home did not go back to the centre"
    assert_in_delta 0, graph_position(home)["y"], 0.5
  end
```

  and replace `"a live post is a filled dot, a draft a ring with a core: the status is a shape, not a colour"` with the one pixel test the looks keep (every look's detail is in the module tests of Step 1):

```ruby
  # One look read from the canvas's own pixels, so that "it draws at all" and
  # "a draft is dashed" are seen on the real canvas, not only asked of a
  # recording one: a live post is filled to its edge; a draft is empty inside,
  # and its outline is there at some points round it and not at others.
  test "a live post is filled and a draft is an empty, dashed outline" do
    live = create_post(title: "Live one")
    draft = create_post(title: "Draft one")
    draft.update_column(:published_at, nil)
    PostRelation.create!(post: live, related_post: draft)
    visit admin_mind_graph_path
    await_graph

    live_centre, live_inside = pixels_of(live)
    draft_centre, = pixels_of(draft)
    point = screen_position(draft.id)
    round = 48.times.map { |step| pixel_at(point["x"] + 7 * Math.cos(step * Math::PI / 24), point["y"] + 7 * Math.sin(step * Math::PI / 24)) }

    assert_equal 255, live_centre[3], "nothing is drawn where the live post is"
    assert_equal live_centre, live_inside, "a live post is filled out to its edge"
    assert_not_equal live_centre, draft_centre, "a draft is empty inside"
    assert_operator round.count { |pixel| pixel == draft_centre }, :>, 6, "the outline has no gaps: it is not dashed"
    assert_operator round.count { |pixel| pixel != draft_centre }, :>, 6, "no outline is drawn round the draft"
  end
```

  (`pixel_at` waits three frames each time; 48 of them are about two and a half seconds. If the suite's time matters more, read the 48 pixels in one `evaluate_script` with the helper's own arithmetic.)

  Run: `sysctl -n vm.loadavg`, then `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/mind_graph_test.rb`
  Expected: PASS. A test that reads a label's or a mark's colour from a pixel and fails now is reading a look this task changed on purpose (a post's label is `dim`; a draft has no core): correct its expectation to the spec's §4 and name it in the commit body.

- [ ] **Step 11: look at it, and report.** `bin/dev`, sign in, create three pages (one a draft, one scheduled, one live with a block added since) with a post-list block each (a tag, a type, no filter), a post of a type in colour slot 7 or above in each state if the site has such a type, and a block that names a type which is then taken out of the registry; open the Mind graph in the light and the dark theme, and a page's local view at depth 2 with more than twenty listed posts (the pill, and the faint lines from the hub). Take a screenshot of each. Report to the controller: the screenshots, the second table at the head of this task (the readings), and anything that looks wrong beside the designer's drawing. **Change no value.**

- [ ] **Step 12: commit.**

```bash
git add app/javascript/mind_graph app/views/admin/mind_graph/show.html.erb config/locales/admin/mind_graph.en.yml test/system/admin/mind_graph_modules_test.rb test/system/admin/mind_graph_test.rb test/integration/admin/mind_graph_test.rb test/lib/admin_i18n_test.rb
git commit -m "feat: the mind graph draws pages, post types and their lines, one status look for every node, and Home at the centre"
```

---

### Task 6: the legend is the filter

The three radios go. Four toggles for the kinds of node and four for the kinds of line, each with its count, everything on. A line switched off hides the line; a kind switched off hides its nodes and every line that touches one. **Status is not a filter** (third design answers): the five looks leave the legend's row, and a "Status" link opens the key, a dialog named "Status key" in the chip's own words (H6). The canvas's name becomes the designer's summary (G6, H5).

**Design readings to report** (with a screenshot of the legend in both themes, at 1,440 and at 1,000 pixels of width, and of the open Status key): the order and wrapping of the two groups, the "Status" link and the keys in one row; the swatch of each toggle; the place of the count (after the name, in the small mono label style); the key as CS Studio's one dialog (`Admin::Ui::DialogComponent`, modal, at its narrowest width), a row per look with the canvas's mark at its smallest size. **Wording the designer did not give**: "Tree lines hidden.", "Lists lines hidden." and "Related lines hidden." after the designer's "Shares-a-tag lines hidden."; "Pages hidden.", "Posts hidden." and "Post types hidden." after "Tags hidden."; one "more", "%{figure} more is in the list.". **A choice to report**: where the whole graph is cut at the 2,000-post cap (`everything=1` on a very large site) the summary never says "Showing everything." (H5) and says the notice's own cap sentence in its place; the designer's "Showing the area around Home." is said in the view the 3,000-line rule opened, with the site's counts.

**Files:**
- Create: `app/components/admin/mind_graph_screen/status_key_component.rb`, `status_key_component.html.erb`, `test/components/admin/mind_graph_screen/status_key_component_test.rb`
- Modify: `app/queries/post_graph/local.rb` (the site's counts, for the summary), `app/components/admin/mind_graph_screen/legend_component.rb`, `legend_component.html.erb`, `app/assets/tailwind/content-spiel.tailwind.css`, `config/locales/admin/mind_graph_screen.en.yml`, `config/locales/admin/mind_graph.en.yml`, `app/views/admin/mind_graph/show.html.erb`, `app/controllers/admin/mind_graph_controller.rb` (nothing but the comment: `@pages` is already set), `app/javascript/mind_graph/graph_data.js`, `app/javascript/mind_graph/app.js`, `app/javascript/controllers/admin/mind_graph/graph_controller.js`, `test/components/previews/admin/mind_graph_screen/legend_component_preview.rb`
- Test: `test/components/admin/mind_graph_screen/legend_component_test.rb`, `test/integration/admin/mind_graph_test.rb`, `test/integration/trash_visibility_test.rb`, `test/system/admin/mind_graph_modules_test.rb`, `test/system/admin/mind_graph_test.rb`

**Interfaces:**
- Consumes: `nodesOf`, `orderOf`, `freeOf` (Task 5).
- Produces:

```ruby
Admin::MindGraphScreen::LegendComponent.new(content_types:, pages: false)
# markup: [data-mind-graph-legend]
#   fieldset[data-legend-group="nodes"]  label[data-legend-toggle="page"|"post"|"tag"|"type"]  input[type=checkbox][name="mind_graph_nodes"][value][data-name]
#   fieldset[data-legend-group="lines"]  label[data-legend-toggle="tree"|"lists"|"related"|"tag"]  input[type=checkbox][name="mind_graph_lines"][value][data-name]
#   each label holds span[data-legend-count] (empty until the script writes it)
#   button[data-legend-status] "Status" [aria-haspopup="dialog"], a trigger of the dialog "mind-graph-status-key"
#   ul[aria-label="Legend"]: li[data-legend-type=<name>]…, li[data-legend="retired"|"pinned"|"notes"]
Admin::MindGraphScreen::StatusKeyComponent.new
# markup: dialog#mind-graph-status-key (Admin::Ui::DialogComponent, title "Status key"): ul > li[data-legend-state=<state>] ×5, no control but the dialog's Close
PostGraph::Local.call(…)   # its answer gains site: { pages:, posts:, tags: }: what the viewer can read of the whole site, from PostGraph::Site (no statement)
```

```js
// mind_graph/graph_data.js
visible({ nodes, edges, on })   // on: { nodes: Set<"page"|"post"|"tag"|"type">, lines: Set<"tree"|"lists"|"related"|"tag"> }
                                // => { visibleNodes, visibleEdges, order, free }; "more" goes with "post", a "brings" line with "lists"
counts(nodes, edges)            // => { nodes: { page, post, tag, type }, lines: { tree, lists, related, tag } }: what the response holds ("brings" lines are not counted)
```

- [ ] **Step 1: the failing tests of the pure part.** In `test/system/admin/mind_graph_modules_test.rb`:

```ruby
  GRAPH_DATA = <<~JS.freeze
    (() => {
      const nodes = [ { kind: "page", home: true, depth: 0, degree: 2 }, { kind: "page", depth: 1, degree: 2 }, { kind: "post", degree: 2 }, { kind: "post", degree: 2 },
                      { kind: "tag", degree: 2 }, { kind: "type", degree: 1 }, { kind: "more", degree: 1 } ]
      const edges = [ { kind: "tree", source: 1, target: 0 }, { kind: "lists", source: 1, target: 5 }, { kind: "brings", source: 5, target: 6 },
                      { kind: "related", source: 2, target: 3 }, { kind: "tag", source: 2, target: 4 }, { kind: "tag", source: 3, target: 4 }, { kind: "brings", source: 5, target: 2 } ]
      const all = { nodes: [ "page", "post", "tag", "type" ], lines: [ "tree", "lists", "related", "tag" ] }
      const shown = (off) => {
        const on = { nodes: new Set(all.nodes.filter((name) => !off.includes(name))), lines: new Set(all.lines.filter((name) => !off.includes(`line-${name}`))) }
        const result = m.visible({ nodes, edges, on })
        return [ result.visibleNodes, result.visibleEdges ]
      }
      return { everything: shown([]), noRelated: shown([ "line-related" ]), noTagLines: shown([ "line-tag" ]), noLists: shown([ "line-lists" ]), noTags: shown([ "tag" ]), noTypes: shown([ "type" ]),
               noPages: shown([ "page" ]), noPosts: shown([ "post" ]), nothing: shown(all.nodes), counts: m.counts(nodes, edges) }
    })()
  JS

  test "graph data: a line switched off hides only the lines, and a kind switched off hides its nodes and every line that touches one" do
    shown = js_module("mind_graph/graph_data", GRAPH_DATA)

    assert_equal [ (0..6).to_a, (0..6).to_a ], shown["everything"]
    assert_equal [ (0..6).to_a, [ 0, 1, 2, 4, 5, 6 ] ], shown["noRelated"], "every node stays"
    assert_equal [ (0..6).to_a, [ 0, 1, 2, 3, 6 ] ], shown["noTagLines"], "the tag stays, without its lines"
    assert_equal [ (0..6).to_a, [ 0, 3, 4, 5 ] ], shown["noLists"], "a hub's faint lines to its posts and to the pill go with Lists: they have no toggle of their own"
    assert_equal [ [ 0, 1, 2, 3, 5, 6 ], [ 0, 1, 2, 3, 6 ] ], shown["noTags"]
    assert_equal [ [ 0, 1, 2, 3, 4, 6 ], [ 0, 3, 4, 5 ] ], shown["noTypes"], "the type, the lists line that points at it and its faint lines; the pill stays, loose"
    assert_equal [ [ 2, 3, 4, 5, 6 ], [ 2, 3, 4, 5, 6 ] ], shown["noPages"]
    assert_equal [ [ 0, 1, 4, 5 ], [ 0, 1 ] ], shown["noPosts"], "more goes with the posts"
    assert_equal [ [], [] ], shown["nothing"]
  end

  test "graph data: the counts are what the response holds, whatever is switched off, and a hub's faint lines are no Lists lines" do
    assert_equal({ "nodes" => { "page" => 2, "post" => 2, "tag" => 1, "type" => 1 }, "lines" => { "tree" => 1, "lists" => 1, "related" => 1, "tag" => 2 } },
      js_module("mind_graph/graph_data", GRAPH_DATA)["counts"])
  end
```

  Run that file; expected FAIL with `m.visible is not a function`.

- [ ] **Step 2: the pure part.** In `app/javascript/mind_graph/graph_data.js`, add:

```js
// WHAT THE LEGEND SHOWS (pages spec §6). `on.nodes` and `on.lines` are the
// names of the toggles that are switched on. A kind of node that is off:
// its nodes are not shown, nor any line that touches one. A kind of line
// that is off: its lines are not shown, AND NOTHING ELSE -- a node is hidden
// by its own toggle only. "+N more" stands for posts and goes with them. A
// hub's faint line to what it brings in (`brings`, a page's local view) is
// part of how a page lists: it has no toggle of its own and goes with
// "Lists" (a reading of the third design answers: pages plan, Task 6).
const toggleOf = (node) => (node.kind === "more" ? "post" : node.kind)
const lineToggleOf = (edge) => (edge.kind === "brings" ? "lists" : edge.kind)

export function visible({ nodes, edges, on }) {
  const visibleNodes = nodes.flatMap((node, index) => (on.nodes.has(toggleOf(node)) ? [ index ] : []))
  const shown = new Set(visibleNodes)
  const visibleEdges = edges.flatMap((edge, index) => (on.lines.has(lineToggleOf(edge)) && shown.has(edge.source) && shown.has(edge.target) ? [ index ] : []))
  return { visibleNodes, visibleEdges, order: orderOf(nodes, visibleNodes), free: freeOf(nodes, visibleNodes) }
}

// How many of each kind THIS RESPONSE holds: what a toggle says beside its
// name, on or off, so that one that is off still says what switching it on
// brings. "Post types" counts the type nodes and "All posts"; "+N more" is
// not a post, and a hub's faint line is not a Lists line.
export function counts(nodes, edges) {
  const tally = (names, items, key) => Object.fromEntries(names.map((name) => [ name, items.filter((item) => item[key] === name).length ]))
  return { nodes: tally([ "page", "post", "tag", "type" ], nodes, "kind"), lines: tally([ "tree", "lists", "related", "tag" ], edges, "kind") }
}
```

  Run the file; expected PASS.

- [ ] **Step 3: the component's failing tests.** Replace `test/components/admin/mind_graph_screen/legend_component_test.rb`'s `"always names the tag node, draft, and both edge kinds, as text"` and add (the tests about types, the retired entry, the pin and the notes badge stay, with `ul[aria-label='Legend']` as the list they look in):

```ruby
  def legend(content_types: %w[blog], pages: true) = render_inline(Admin::MindGraphScreen::LegendComponent.new(content_types: content_types, pages: pages))

  test "the kinds of node and of line are checkboxes in two named groups, all on, each with its name and an empty count" do
    legend

    assert_selector "fieldset[data-legend-group=nodes] legend", text: "Show", visible: :all
    assert_selector "fieldset[data-legend-group=lines] legend", text: "Lines", visible: :all
    assert_equal %w[page post tag type], page.all("fieldset[data-legend-group=nodes] input[type=checkbox][name=mind_graph_nodes]").map { |input| input["value"] }
    assert_equal %w[tree lists related tag], page.all("fieldset[data-legend-group=lines] input[type=checkbox][name=mind_graph_lines]").map { |input| input["value"] }
    assert_equal 8, page.all("input[type=checkbox][checked]").size
    assert_equal [ "Pages", "Posts", "Tags", "Post types", "Tree", "Lists", "Related", "Shares a tag" ], page.all("label[data-legend-toggle]").map { |label| label.text.squish }
    assert_equal [ "Pages", "Shares a tag" ], [ page.first("input[name=mind_graph_nodes]")["data-name"], page.all("input[name=mind_graph_lines]").last["data-name"] ]
    assert_selector "label[data-legend-toggle] [data-legend-count]", count: 8, text: "", visible: :all
    assert_selector "input[data-action='change->admin--mind-graph--graph#filter']", count: 8
    assert_no_selector "input[type=radio]"
    assert_no_text "Links in text"
  end

  test "every toggle has a swatch on the tokens' classes" do
    legend

    assert_selector "label[data-legend-toggle=page] svg.mg-key rect.mg-key-page"
    assert_selector "label[data-legend-toggle=type] svg.mg-key circle.mg-key-type"
    assert_selector "label[data-legend-toggle=tree] .mg-edge-tree"
    assert_selector "label[data-legend-toggle=lists] .mg-edge-lists"
    assert_selector "label[data-legend-toggle=related] .mg-edge-related"
    assert_selector "fieldset[data-legend-group=lines] label[data-legend-toggle=tag] .mg-edge-tag"
  end

  # Third design answers: status is not a filter. The five looks are a key
  # behind a "Status" link (H6: a dialog), not in the legend's row.
  test "the legend's Status button opens the key and is no filter" do
    legend

    assert_selector "button[type=button][data-legend-status][aria-haspopup=dialog][data-action='admin--ui--dialog#open'][data-admin--ui--dialog-id-param='mind-graph-status-key']", text: "Status"
    assert_no_selector "[data-legend-state]", visible: :all
    assert_no_selector "dialog", visible: :all
    assert_no_text "Draft or scheduled"
  end

  test "a viewer who reads no page has no toggle for pages, post types, the tree or lists; one who reads no post none for posts, tags, related or shared tags" do
    legend(pages: false)
    assert_equal %w[post tag related tag], page.all("label[data-legend-toggle]").map { |label| label["data-legend-toggle"] }

    legend(content_types: [], pages: true)
    assert_equal %w[page type tree lists], page.all("label[data-legend-toggle]").map { |label| label["data-legend-toggle"] }
  end
```

  And a new file, `test/components/admin/mind_graph_screen/status_key_component_test.rb`:

```ruby
require "test_helper"

# The Mind graph's status key (pages in the mind graph, spec §6; design
# answer H6): a dialog named "Status key" with the five looks, in the words
# the card's chip uses.
class Admin::MindGraphScreen::StatusKeyComponentTest < ViewComponent::TestCase
  def key = render_inline(Admin::MindGraphScreen::StatusKeyComponent.new)

  test "the status key is a dialog named Status key that holds the five looks in the chip's words and no control" do
    key
    dialog = "dialog#mind-graph-status-key[aria-labelledby='mind-graph-status-key-title']"

    assert_selector "#{dialog} h2#mind-graph-status-key-title", text: "Status key", visible: :all
    assert_equal [ "Live", "Draft", "Scheduled", "Live, unpublished changes", "Live, change scheduled" ], page.all("#{dialog} li[data-legend-state]", visible: :all).map { |item| item.text(:all).squish }
    assert_equal %w[live draft scheduled live_with_changes live_change_scheduled], page.all("#{dialog} li[data-legend-state]", visible: :all).map { |item| item["data-legend-state"] }
    assert_no_selector "#{dialog} .admin-dialog__body input, #{dialog} .admin-dialog__body button, #{dialog} .admin-dialog__body a", visible: :all
  end

  test "each status look's swatch is the canvas's mark on the tokens' classes: a centre for scheduled, a corner dot with its ring for the two looks of a live record" do
    key

    assert_selector "[data-legend-state] svg.mg-key.mg-state circle.mg-state-mark[r='7']", count: 5, visible: :all
    assert_selector "[data-legend-state=draft] svg.mg-state-draft", visible: :all
    assert_selector "[data-legend-state=scheduled] svg.mg-state-scheduled circle.mg-state-centre[r='2']", visible: :all
    assert_selector "[data-legend-state=live_with_changes] svg.mg-state-live-with-changes circle.mg-state-corner[r='2.5']", visible: :all
    assert_selector "[data-legend-state=live_change_scheduled] svg.mg-state-live-change-scheduled circle.mg-state-corner-ring[r='4']", visible: :all
  end
end
```

  (If the directory's other component tests subclass something else than `ViewComponent::TestCase`, subclass that.)

  Run: `PGGSSENCMODE=disable bin/rails test test/components/admin/mind_graph_screen`; expected FAIL with `unknown keyword: :pages` and `uninitialized constant Admin::MindGraphScreen::StatusKeyComponent`.

- [ ] **Step 4: the strings.** `config/locales/admin/mind_graph_screen.en.yml`'s `legend` becomes (the header comment says what each group is; the `notes` key stays where it is, in `notes.en.yml`):

```yaml
        legend:
          label: "Legend"
          show: "Show"
          lines: "Lines"
          nodes:
            page: "Pages"
            post: "Posts"
            tag: "Tags"
            type: "Post types"
          edges:
            tree: "Tree"
            lists: "Lists"
            related: "Related"
            tag: "Shares a tag"
          status: "Status"
          retired: "Retired type"
          pinned: "Pinned"
        status_key:
          title: "Status key"
          states:
            live: "Live"
            draft: "Draft"
            scheduled: "Scheduled"
            live_with_changes: "Live, unpublished changes"
            live_change_scheduled: "Live, change scheduled"
```

  (`legend.status` is the link that opens the key; `status_key` is the new component's scope, beside `legend` in the same file: `title` the dialog's name and `states` its five rows. All the designer's (H6): the key uses the CHIP's wording, one set of words, and the date stands only on the chip.)

  (`tag`, `hollow`, `related` and `tag_edge` go.) In `config/locales/admin/mind_graph.en.yml`: under `show`, `intro`, `no_posts` (renamed `no_content`), `canvas_label`, `list_label` and the search's two change, and the whole `filter:` block goes:

```yaml
        intro: "How your pages, posts and tags connect. Scroll or pinch to zoom, drag to move."
        no_content: "No pages or posts yet."
        canvas_label: "Mind graph"
        list_label: "Pages, posts, tags and post types in this graph"
        search:
          label: "Find a page, post or tag"
          placeholder: "Find a page, post or tag…"
```

  and under `script`, `summary` becomes a group (the designer's three forms, G6) and `legend` is new:

```yaml
        summary:
          whole: "Mind graph: %{kinds}, %{connections}."
          local: "Mind graph around %{title}, depth %{depth}: %{kinds}."
          everything: "Showing everything."
          nothing: "Mind graph: nothing to show."
          all_hidden: "All types are hidden."
          none_yet: "No pages, posts or tags yet."
          around_home: "Showing the area around Home."
          site: "The site has %{kinds}."
          more:
            one: "%{figure} more is in the list."
            other: "%{figure} more are in the list."
          pages:
            one: "%{figure} page"
            other: "%{figure} pages"
          types:
            one: "%{figure} post type"
            other: "%{figure} post types"
          posts:
            one: "%{figure} post"
            other: "%{figure} posts"
          posts_of: "%{figure} of %{total} posts"
          tags:
            one: "%{figure} tag"
            other: "%{figure} tags"
          connections:
            one: "%{figure} connection"
            other: "%{figure} connections"
          pair: "%{first} and %{last}"
          series: "%{first}, %{rest}"
          hidden:
            page: "Pages hidden."
            post: "Posts hidden."
            tag: "Tags hidden."
            type: "Post types hidden."
          hidden_lines:
            tree: "Tree lines hidden."
            lists: "Lists lines hidden."
            related: "Related lines hidden."
            tag: "Shares-a-tag lines hidden."
        legend:
          toggle: "%{name}, %{count}"
```

  Bring the file's header comment up to date: `show.canvas_label` names the canvas until the data has arrived and is the summary's first words; `script.summary.*` are WHOLE SENTENCES and the parts of one, and the script puts one space between two sentences and nothing else of its own: "Mind graph: 9 pages, 3 post types, 13 posts and 4 tags, 27 connections. Showing everything." is `whole`, then `everything`; "Mind graph around Blog, depth 2: 7 pages, 1 post type and 20 of 112 posts. 92 more are in the list." is `local`, then `more`; a kind that is switched off adds its `hidden` sentence and a kind of line its `hidden_lines` one ("Showing everything. Tags hidden." are both said, in that order: "everything" means no cap, not no filters). With nothing in view the name is `nothing`, then `all_hidden` when every kind is switched off or `none_yet` when the site has nothing to draw. In the view the 3,000-line rule opened, `around_home` and `site` follow ("Showing the area around Home. The site has 212 pages, 2,040 posts and 64 tags."). `%{kinds}` is the counts of what is in view, joined by `pair` and `series` (so there is no comma before "and", and another language can join otherwise); `%{figure}` is a count as the sentence's language groups it, `count` only chooses the form. `script.legend.toggle` is a toggle's whole accessible name once its count is known.

- [ ] **Step 5: the component, its swatches and the frame.** `legend_component.rb` (keep `retired?` and `type_names`, and rewrite the class comment: the legend is the filter; which toggles a viewer gets; the counts are the script's; status is not a filter, and its key is a dialog of its own, `StatusKeyComponent`, which the "Status" link opens). `STATES` is not this component's any more: it is the key's.

```ruby
      NODES = %i[page post tag type].freeze
      LINES = %i[tree lists related tag].freeze
      # What hangs on pages, and what on posts: a viewer who can read none of
      # a kind gets no toggle for it (pages spec §2).
      OF_PAGES = %i[page type tree lists].freeze

      # `content_types:` the type names of the viewer's posts, in any order, with
      # repeats allowed; `pages:` whether the viewer can read a page at all.
      def initialize(content_types:, pages: false)
        @content_types = content_types.map(&:to_s).uniq
        @pages = pages
      end

      def node_toggles = NODES.select { |kind| shown?(kind) }
      def line_toggles = LINES.select { |kind| shown?(kind) }

      private

      def shown?(kind) = OF_PAGES.include?(kind) ? @pages : @content_types.any?
```

  `legend_component.html.erb`:

```erb
<%# The legend is the filter (pages in the mind graph, spec §6): two groups of
    native checkboxes, everything on, then the "Status" link, then the keys
    that are not controls.
    A toggle's count is the script's: the page holds no graph data. Until it
    is written the toggle's name is its label; then the script gives the
    input one name with the count in it ("Pages, 200"), which the
    controller's `reset` takes back.

    STATUS IS NOT A FILTER (the third design answers): the five looks are a
    key of their own, a dialog (`StatusKeyComponent`, design answer H6),
    and here is only the "Status" link that opens it: a button that reads as
    a link, wired to the one dialog controller on <body>. %>
<div data-mind-graph-legend class="admin-mind-graph-legend flex min-w-0 flex-wrap items-center gap-x-6 gap-y-2 text-sm text-dim">
  <% [ [ :nodes, node_toggles, t(".show") ], [ :lines, line_toggles, t(".lines") ] ].each do |group, kinds, name| %>
    <% next if kinds.empty? %>
    <fieldset data-legend-group="<%= group %>" class="m-0 flex min-w-0 flex-wrap items-center gap-x-4 gap-y-1.5 border-0 p-0">
      <legend class="sr-only"><%= name %></legend>
      <% kinds.each do |kind| %>
        <% label = t(group == :nodes ? ".nodes.#{kind}" : ".edges.#{kind}") %>
        <label data-legend-toggle="<%= kind %>" class="inline-flex cursor-pointer items-center gap-1.5">
          <%= render Admin::Ui::CheckboxComponent.new(name: "mind_graph_#{group}", value: kind, checked: true, id: "mind-graph-#{group}-#{kind}",
                data: { action: "change->admin--mind-graph--graph#filter", name: label }) %>
          <%= swatch(group, kind) %>
          <span><%= label %></span>
          <span data-legend-count aria-hidden="true" class="font-cs-mono text-label text-meta"></span>
        </label>
      <% end %>
    </fieldset>
  <% end %>
  <%= tag.button t(".status"), type: "button", aria: { haspopup: "dialog" },
        class: "cursor-pointer rounded-cs text-sm text-accent underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent",
        data: { legend_status: true, **dialog_trigger(Admin::MindGraphScreen::StatusKeyComponent::ID) } %>
  <ul class="m-0 flex list-none flex-wrap items-center gap-x-5 gap-y-1.5 p-0" aria-label="<%= t(".label") %>">
    <% type_names.each do |name| %>
      <li data-legend-type="<%= name %>"><%= render Admin::Ui::ContentTypeDotComponent.new(content_type: name) %></li>
    <% end %>
    <% if retired? %>
      <li class="inline-flex items-center gap-1.5" data-legend="retired">
        <svg class="mg-key" width="12" height="12" viewBox="0 0 12 12" aria-hidden="true"><circle class="mg-key-retired" cx="6" cy="6" r="4"/><line class="mg-key-retired" x1="2.5" y1="9.5" x2="9.5" y2="2.5"/></svg>
        <%= t(".retired") %>
      </li>
    <% end %>
    <li class="inline-flex items-center gap-1.5" data-legend="pinned">
      <svg class="mg-key" width="12" height="12" viewBox="0 0 12 12" aria-hidden="true"><circle class="mg-key-pinned-node" cx="5" cy="7" r="4"/><circle class="mg-key-pin" cx="8.5" cy="3.5" r="2.5"/></svg>
      <%= t(".pinned") %>
    </li>
    <%# A post or a page with open notes (notes spec §4.4): the count badge the
        canvas draws on the mark's top-left corner, opposite the pin. %>
    <li class="inline-flex items-center gap-1.5" data-legend="notes">
      <svg class="mg-key" width="14" height="12" viewBox="0 0 14 12" aria-hidden="true"><circle class="mg-key-pinned-node" cx="9" cy="7" r="4"/><rect class="mg-key-notes" x="0.5" y="0.5" width="9" height="6" rx="3"/></svg>
      <%= t(".notes") %>
    </li>
  </ul>
</div>
```

  with, in the component (public, below `line_toggles`):

```ruby
      # A toggle's swatch: the mark or the line it switches, on the legend's
      # own token classes (`.mg-*`), never a colour.
      def swatch(group, kind)
        if group == :lines
          tag.svg(tag.line(class: "mg-edge mg-edge-#{kind}", x1: 0, y1: 4, x2: 22, y2: 4), class: "mg-key", width: 22, height: 8, viewBox: "0 0 22 8", "aria-hidden": true)
        else
          shape = { page: tag.rect(class: "mg-key-page", x: 0, y: 1, width: 14, height: 10, rx: 2), post: tag.circle(class: "mg-key-post", cx: 6, cy: 6, r: 4.5),
                    tag: tag.rect(class: "mg-key-tag", x: 1.5, y: 1.5, width: 9, height: 9), type: tag.circle(class: "mg-key-type", cx: 6, cy: 6, r: 6) + tag.circle(class: "mg-key-type-ring", cx: 6, cy: 6, r: 3.75) }.fetch(kind)
          tag.svg(shape, class: "mg-key", width: 14, height: 12, viewBox: "0 0 14 12", "aria-hidden": true)
        end
      end
```

  (If `tag.svg` / `tag.circle` are refused by Action View's tag builder in this version, write the eight swatches out in the template with a `case`; the classes and sizes are the contract, not the helper.)

  The key. `status_key_component.rb`:

```ruby
module Admin
  module MindGraphScreen
    # The Mind graph's status key (pages in the mind graph, spec §6; design
    # answers "Status in the legend" and H6): the five looks a page or a post
    # can have on the canvas, each with its name. Status is NOT a filter, so
    # the looks are no toggles and not in the legend's row: the legend's
    # "Status" link opens this, CS Studio's one dialog, named "Status key".
    #
    # The names are THE CHIP'S WORDS (H6: one set of words): "Live,
    # unpublished changes" and "Live, change scheduled"; the day of a
    # scheduled change stands only on a card's chip. A swatch is the
    # canvas's mark at its smallest size, in the same pixels (`marks.js`),
    # on the legend's token classes (`.mg-state-*`).
    #
    # It is rendered once, by the screen's view, OUTSIDE the graph's element:
    # the Tab order of the box is the search, the graph and the list, and a
    # closed dialog's Close button is no stop in it.
    class StatusKeyComponent < AdminComponent
      ID = "mind-graph-status-key".freeze
      STATES = %i[live draft scheduled live_with_changes live_change_scheduled].freeze
    end
  end
end
```

  `status_key_component.html.erb`:

```erb
<%= render Admin::Ui::DialogComponent.new(id: Admin::MindGraphScreen::StatusKeyComponent::ID, title: t(".title")) do %>
  <ul class="m-0 flex list-none flex-col gap-2 p-0">
    <% Admin::MindGraphScreen::StatusKeyComponent::STATES.each do |state| %>
      <li class="flex items-center gap-2 text-sm text-ink" data-legend-state="<%= state %>">
        <svg class="mg-key mg-state mg-state-<%= state.to_s.dasherize %>" width="18" height="18" viewBox="0 0 18 18" aria-hidden="true">
          <circle class="mg-state-mark" cx="8" cy="8" r="7"/>
          <circle class="mg-state-centre" cx="8" cy="8" r="2"/>
          <circle class="mg-state-corner-ring" cx="12.24" cy="12.24" r="4"/>
          <circle class="mg-state-corner" cx="12.24" cy="12.24" r="2.5"/>
        </svg>
        <%= t(".states.#{state}") %>
      </li>
    <% end %>
  </ul>
<% end %>
```

  In `show.html.erb`, after the box's closing `</div>` and inside the `else` branch: `<%= render Admin::MindGraphScreen::StatusKeyComponent.new %>`, with a comment that says why it stands outside the graph's element.

  In `app/assets/tailwind/content-spiel.tailwind.css`, beside the other `.mg-*` rules (`.mg-tag rect` and `.mg-key-hollow` go with the entries that used them):

```css
.mg-key-page { fill: var(--cs-ink); }
.mg-key-post { fill: var(--cs-dim); }
.mg-key-tag { fill: var(--cs-surface); stroke: var(--cs-meta); stroke-width: 1.5; }
.mg-key-type { fill: var(--cs-dim); }
.mg-key-type-ring { fill: none; stroke: var(--cs-surface); stroke-width: 1.5; }
.mg-edge-tree { stroke: var(--cs-line-strong); stroke-width: 1; }
/* The canvas's own dots (design answer G3): 1.5px, round caps, 0.1 / 3.5. */
.mg-edge-lists { stroke: var(--cs-dim); stroke-width: 1.5; stroke-linecap: round; stroke-dasharray: 0.1 3.5; }
/* The five status looks (pages spec §4), drawn on a neutral filled mark, in
   the Status key. Warn means "scheduled": the scheduled record's centre dot
   and the scheduled change's corner dot; unpublished changes are dim. A
   corner dot stands on a surface disk, its ring. */
.mg-state-mark { fill: var(--cs-ink); stroke: none; }
.mg-state-centre, .mg-state-corner, .mg-state-corner-ring { display: none; }
.mg-state-draft .mg-state-mark { fill: var(--cs-surface); stroke: var(--cs-meta); stroke-width: 1.5; stroke-dasharray: 3 2.5; }
.mg-state-scheduled .mg-state-mark { fill: var(--cs-surface); stroke: var(--cs-dim); stroke-width: 1.5; }
.mg-state-scheduled .mg-state-centre { display: inline; fill: var(--cs-warn); }
.mg-state-live-with-changes .mg-state-corner-ring, .mg-state-live-change-scheduled .mg-state-corner-ring { display: inline; fill: var(--cs-surface); }
.mg-state-live-with-changes .mg-state-corner { display: inline; fill: var(--cs-dim); }
.mg-state-live-change-scheduled .mg-state-corner { display: inline; fill: var(--cs-warn); }
```

  In `show.html.erb`: the legend's row holds the legend alone (the `<fieldset>` of radios and everything in it goes; the comment above the box says "the legend, which is the filter: checkboxes, applied client-side" where it said three radios):

```erb
      <div class="border-b border-line px-3.5 py-2.5">
        <%= render Admin::MindGraphScreen::LegendComponent.new(content_types: @content_types, pages: @pages) %>
      </div>
```

  the empty state reads `t(".no_content")` with `data-mind-graph-empty="no-content"`; and in the `messages_data(...)` call `"mind_graph.script.summary"` goes (it is a group now) and these join: `"mind_graph.script.legend.toggle"`, `"mind_graph.script.summary.whole"`, `"mind_graph.script.summary.local"`, `"mind_graph.script.summary.everything"`, `"mind_graph.script.summary.nothing"`, `"mind_graph.script.summary.all_hidden"`, `"mind_graph.script.summary.none_yet"`, `"mind_graph.script.summary.around_home"`, `"mind_graph.script.summary.site"`, `"mind_graph.script.summary.hidden_lines.tree"`, `"mind_graph.script.summary.hidden_lines.lists"`, `"mind_graph.script.summary.hidden_lines.related"`, `"mind_graph.script.summary.hidden_lines.tag"`, `"mind_graph.script.summary.more"`, `"mind_graph.script.summary.pages"`, `"mind_graph.script.summary.types"`, `"mind_graph.script.summary.posts"`, `"mind_graph.script.summary.posts_of"`, `"mind_graph.script.summary.tags"`, `"mind_graph.script.summary.connections"`, `"mind_graph.script.summary.pair"`, `"mind_graph.script.summary.series"`, `"mind_graph.script.summary.hidden.page"`, `"mind_graph.script.summary.hidden.post"`, `"mind_graph.script.summary.hidden.tag"`, `"mind_graph.script.summary.hidden.type"`. Update the preview (`legend_component_preview.rb`) to pass `pages: true`, and add a preview without pages.

  Run: `PGGSSENCMODE=disable bin/rails test test/components/admin/mind_graph_screen/legend_component_test.rb`; expected PASS.

  The site's counts, for the summary of the view the 3,000-line rule opens (design answer H5: "The site has 212 pages, 2,040 posts and 64 tags."). In `app/queries/post_graph/local.rb`, the answer's `merge(...)` gains one key, from what the site has loaded and with no statement:

```ruby
                                site: { pages: @site.pages.size, posts: @site.post_rows.size, tags: @site.tag_counts.size },
```

  (what the VIEWER can read of the site: the pages and posts of their scope, and the tags a readable post carries), the header comment says so, and in `test/queries/post_graph/local_test.rb` the test `"depth 1 around a page: its parent, its children and what its blocks list, and no post"` gains `assert_equal({ pages: Page.count, posts: Post.count, tags: PostTag.distinct.count(:tag_id) }, result[:site])`; where that file compares a whole answer, the answer gains `site:`. Run `PGGSSENCMODE=disable bin/rails test test/queries/post_graph/local_test.rb`; expected PASS.

- [ ] **Step 6: the app follows the checkboxes.** In `app/javascript/mind_graph/app.js`:
  - Import `visible, counts` with the others from `mind_graph/graph_data`. `mode` goes. In its place:

```js
  // The legend's toggles that are switched on (pages spec §6): the state is
  // the checkboxes' own, so Back restores what the person had chosen.
  const switchedOn = (name) => new Set(Array.from(element.querySelectorAll(`input[name="${name}"]:checked`), (input) => input.value))
```

  - `applyFilter` begins:

```js
  // What the legend shows (`graph_data.js`): a kind of node that is off takes
  // its nodes and their lines; a kind of line that is off takes its lines
  // and nothing else.
  function applyFilter() {
    const shown = visible({ nodes: state.nodes, edges: state.edges, on: { nodes: switchedOn("mind_graph_nodes"), lines: switchedOn("mind_graph_lines") } })
    state.visibleNodes = shown.visibleNodes
    state.visibleEdges = shown.visibleEdges
    state.order = shown.order
    state.free = shown.free
```

    and the rest of it stays (the selection, the pins, the hover, `data-nodes`, `data-edges`, the list), followed by `summarise()` as its last line.
  - The canvas's name is the designer's summary (G6), and a change of it is announced:

```js
  // "a, b, c and d", in the messages' own words for a pair and a series.
  const series = (items) => items.slice(0, -2).reduceRight((rest, first) => text.t("mind_graph.script.summary.series", { first, rest }),
    items.length > 1 ? text.t("mind_graph.script.summary.pair", { first: items.at(-2), last: items.at(-1) }) : items[0])

  // The canvas is one image to a screen reader, and its name says what is on
  // it NOW (design answers G6 and H5): the counts in view by type, then the
  // lines, then the scope.
  //   the whole graph   "Mind graph: 9 pages, 3 post types, 13 posts and 4 tags, 27 connections. Showing everything."
  //   a local view      "Mind graph around Blog, depth 2: 7 pages, 1 post type and 20 of 112 posts. 92 more are in the list."
  //   opened by the 3,000-line rule, that view adds
  //                     "Showing the area around Home. The site has 212 pages, 2,040 posts and 64 tags."
  //   a kind that is off adds "Tags hidden.", a kind of line "Shares-a-tag lines hidden.";
  //     "Showing everything. Tags hidden." are both said: "everything" means no cap, not no filters
  //   nothing in view   "Mind graph: nothing to show. All types are hidden." (every kind is off)
  //                     "Mind graph: nothing to show. No pages, posts or tags yet." (there is nothing)
  // A kind with nothing in view is left out. "N of M posts" and the "more"
  // sentence are a page's that lists more than its view draws; "more"
  // counts every pill in view together. "Showing everything." is NEVER said
  // at the cap: a whole graph cut at the 2,000 posts says the notice's own
  // cap sentence there. After a toggle the same words are put into the
  // notice's polite live region, hidden from the eye: that is how a change
  // of the legend is announced.
  function summarise({ announce = false } = {}) {
    const inView = state.visibleNodes.map((index) => state.nodes[index])
    const drawn = (kind) => inView.filter((node) => node.kind === kind).length
    const focus = state.data.focus
    const more = inView.filter((node) => node.kind === "more").reduce((sum, pill) => sum + pill.count, 0)
    const listed = more > 0 && focus?.kind === "page" ? state.nodes[state.focusIndex]?.listed_count : null
    const counted = (key, count, extra = {}) => text.t(`mind_graph.script.summary.${key}`, { count, figure: number(count), ...extra })
    const kinds = [ [ "pages", drawn("page") ], [ "types", drawn("type") ], [ listed ? "posts_of" : "posts", drawn("post"), { total: number(listed ?? 0) } ], [ "tags", drawn("tag") ] ]
      .filter(([ , count ]) => count > 0).map(([ key, count, extra ]) => counted(key, count, extra))
    const off = (name) => Array.from(element.querySelectorAll(`input[name="${name}"]:not(:checked)`), (input) => input.value)
    const kindsOff = off("mind_graph_nodes")
    const allOff = kindsOff.length > 0 && kindsOff.length === element.querySelectorAll('input[name="mind_graph_nodes"]').length

    const sentences = []
    if (kinds.length === 0) {
      sentences.push(text.t("mind_graph.script.summary.nothing"))
      if (state.nodes.length === 0) sentences.push(text.t("mind_graph.script.summary.none_yet"))
      else if (allOff) sentences.push(text.t("mind_graph.script.summary.all_hidden"))
    } else if (focus) {
      sentences.push(text.t("mind_graph.script.summary.local", { title: focus.title, depth: focus.depth, kinds: series(kinds) }))
      if (more > 0) sentences.push(counted("more", more))
      // The view the 3,000-line rule opened: where it is, and what the site holds.
      if (element.dataset.openedLines && state.data.site) {
        const site = [ [ "pages", state.data.site.pages ], [ "posts", state.data.site.posts ], [ "tags", state.data.site.tags ] ].filter(([ , count ]) => count > 0).map(([ key, count ]) => counted(key, count))
        sentences.push(text.t("mind_graph.script.summary.around_home"), text.t("mind_graph.script.summary.site", { kinds: series(site) }))
      }
    } else {
      sentences.push(text.t("mind_graph.script.summary.whole", { kinds: series(kinds), connections: counted("connections", state.visibleEdges.length) }))
      const cut = state.data.shown < state.data.total
      sentences.push(cut ? text.t("mind_graph.script.capped", { shown: number(state.data.shown), total: number(state.data.total) }) : text.t("mind_graph.script.summary.everything"))
    }
    if (state.nodes.length > 0 && !(kinds.length === 0 && allOff)) {
      for (const kind of kindsOff) sentences.push(text.t(`mind_graph.script.summary.hidden.${kind}`))
      for (const kind of off("mind_graph_lines")) sentences.push(text.t(`mind_graph.script.summary.hidden_lines.${kind}`))
    }
    const summary = sentences.join(" ")
    canvas.setAttribute("aria-label", summary)
    if (!announce) return

    notice.querySelector("[data-mind-graph-announced]")?.remove()
    const line = document.createElement("p")
    line.className = "sr-only"
    line.dataset.mindGraphAnnounced = ""
    line.textContent = summary
    notice.append(line)
  }
```

    The line in `show` that set the canvas's `aria-label` goes (`applyFilter` has just written it), and the returned `filter()` calls `summarise({ announce: true })` after `applyFilter()`.
  - The counts, written once per load, in `show` after `applyFilter()`:

```js
  // Each toggle's count beside its name, and its whole name for a screen
  // reader ("Pages, 200"). What the RESPONSE holds, so switching a toggle
  // changes none of them. The controller's `reset` takes both back.
  function writeCounts() {
    const held = counts(state.nodes, state.edges)
    for (const input of element.querySelectorAll("input[name=mind_graph_nodes], input[name=mind_graph_lines]")) {
      const count = number(held[input.name === "mind_graph_nodes" ? "nodes" : "lines"][input.value] ?? 0)
      input.closest("label").querySelector("[data-legend-count]").textContent = count
      input.setAttribute("aria-label", text.t("mind_graph.script.legend.toggle", { name: input.dataset.name, count }))
    }
  }
```

  - In `startLayout`, `if (mode() !== "all") sendFilter()` becomes `if (state.visibleNodes.length < state.nodes.length || state.visibleEdges.length < state.edges.length) sendFilter()`.
  - The header comment's and the returned `filter()`'s words "the filter" / "the control" stay true; where they say "under All every node" say what `graph_data.js` says.

  In `graph_controller.js`, in `reset()`, after the canvas's name is put back:

```js
    // The legend's counts and the names made of them are the visit that was
    // left. The checkboxes themselves are the person's choice and are kept:
    // the graph shows what the legend says.
    for (const count of this.element.querySelectorAll("[data-legend-count]")) count.replaceChildren()
    for (const input of this.element.querySelectorAll("[data-mind-graph-legend] input")) input.removeAttribute("aria-label")
```

  and the header comment's "(The filter's radios are restored too …)" says checkboxes, and gains one sentence: the "Status" key is `admin--ui--menu`'s, which closes its own panel when it is disconnected, so nothing of it is reset here.

- [ ] **Step 7: the integration tests.** In `test/integration/admin/mind_graph_test.rb`:
  - `"the filter is All, Related and Tags, with All chosen"` becomes `"the legend's toggles are checkboxes in two groups, all on, and the radios are gone"`: with a post and a page, `assert_select "fieldset[data-legend-group=nodes] input[type=checkbox][name=mind_graph_nodes][checked]", count: 4`, the same for `lines`, `assert_select "input[type=radio]", count: 0`, `assert_select "input[name=mind_graph_filter]", count: 0`, and the body does not include `"Links in text"`.
  - `"the tab order is the search, the filter, the zoom buttons, then the canvas"`: the selector's `input[type=radio]` becomes `input[type=checkbox]`, and with only a post created the expected order is `[ "input", "input", "input", "input", "input", "Status", "hidden", "Zoom out", "Zoom in", "Fit all", "canvas" ]` (the search, then Posts, Tags, Related, Shares a tag, then the "Status" button, which has no `aria-label` and is named by its text). Its last assertion stays `[ "aside" ]`: the key's dialog is outside the graph's element.
  - `"in a local view the tab order is the search, the bar's links, the filter, the zoom buttons, the canvas"`: `input[type=radio]` becomes `input[type=checkbox]`, the mapping of a button becomes `node["aria-label"] || (node["hidden"] ? "hidden" : node.text.strip)`, and the expected order is `[ "search", "link:2", "link:Whole graph", "checkbox", "checkbox", "checkbox", "checkbox", "Status", "hidden", "Zoom out", "Zoom in", "Fit all", "canvas" ]`.
  - new `"the status key is in the page once, a closed dialog outside the graph's element"`: with a post, `assert_select "dialog#mind-graph-status-key", count: 1`, `assert_select "dialog#mind-graph-status-key[open]", count: 0`, `assert_select "[data-controller='admin--mind-graph--graph'] dialog", count: 0`, `assert_select "dialog#mind-graph-status-key li[data-legend-state]", count: 5`, and `assert_select "[data-mind-graph-legend] button[data-legend-status][data-admin--ui--dialog-id-param='mind-graph-status-key']", text: "Status"`; and for a viewer who can read neither a page nor a post (the empty state) no such dialog is in the page.
  - `"the legend names only the content types of the viewer's posts, plus the shapes"` and its two neighbours look for the types in `ul[aria-label='Legend'] [data-legend-type]`; the shapes they name are now `pinned` and `notes` (the five states are in the Status key, which the test above reads).
  - new `"a viewer who reads pages and no post gets the toggles of pages only"` (`label[data-legend-toggle]` values `%w[page type tree lists]`).
  - `"the script's messages ride on the element"`: `summary` is gone from the key list, and `legend.toggle` and every `summary.*` key of Step 5 are in it; where the test reads a sentence, `summary.whole` is `"Mind graph: %{kinds}, %{connections}."`.
  - the tests that read `"No posts yet."` read `"No pages or posts yet."`, and `[data-mind-graph-empty='no-content']`.
  - `"the canvas carries its own name twice …"` and `"the list comes last and empty"`: the new names (`Mind graph`, `Pages, posts, tags and post types in this graph`); the search's label in its test.

  In `test/integration/trash_visibility_test.rb` the legend assertions keep their selectors (`[data-legend-type=…]`).

  Run: `PGGSSENCMODE=disable bin/rails test test/integration/admin/mind_graph_test.rb test/integration/trash_visibility_test.rb test/components/admin/mind_graph_screen test/lib`
  Expected: PASS (`admin_i18n_test`, `script_messages_test`, `admin_design_rules_test`, `inline_handlers_test` among them).

- [ ] **Step 8: the browser tests.** In `test/system/admin/mind_graph_test.rb` add

```ruby
  # A toggle of the legend, by the name on it. No `await_graph` is needed to
  # read what it shows: `data-nodes`, `data-edges`, the list and the canvas's
  # name are written by the change itself, before the layout moves.
  def toggle(name) = find("#{GRAPH} [data-mind-graph-legend] label", text: name).click

  def legend_counts = all("#{GRAPH} label[data-legend-toggle]").map { |label| label.text.squish }
```

  and change the canvas's name wherever it is asserted: in `"the graph loads, settles, and the first view fits every node inside the canvas"` (six posts and the tag they share) `'Post relationship graph: 7 posts and tags, 7 connections.'` is `'Mind graph: 6 posts and 1 tag, 7 connections. Showing everything.'`, and the server's own name is `'Mind graph'`. The tests that pressed a radio are rewritten as follows; each keeps its data and its other assertions.

  `"the filter hands the layout only what is shown"` is replaced by:

```ruby
  # Pages spec §6: each toggle hides its kind and only its kind, the counts
  # stay what the graph holds, and the list follows.
  test "each toggle of the legend hides its kind and only its kind, and the counts stay" do
    home = root_page
    blog = create_page(title: "Blog")
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    a, b, c = 3.times.map { |i| create_post(title: "P#{i}") }
    PostRelation.create!(post: a, related_post: b)
    [ b, c ].each { |post| PostTag.create!(post: post, tag: Tag.find_or_create_by!(name: "t")) }
    tag = Tag.find_by!(name: "t")
    visit admin_mind_graph_path
    await_graph
    counts = [ "Pages 2", "Posts 3", "Tags 1", "Post types 1", "Tree 1", "Lists 1", "Related 1", "Shares a tag 2" ]
    shows = ->(nodes, edges) { assert_selector "#{GRAPH}[data-nodes='#{nodes}'][data-edges='#{edges}']"; assert_equal counts, legend_counts }

    shows.call(7, 5)
    assert_selector "#{GRAPH} input[name=mind_graph_nodes][value=page][aria-label='Pages, 2']", visible: :all
    assert_selector "#{CANVAS}[aria-label='Mind graph: 2 pages, 1 post type, 3 posts and 1 tag, 5 connections. Showing everything.']"

    toggle "Related"
    shows.call(7, 4)
    assert screen_position(a.id), "a line switched off hid a node"
    assert_selector "#{CANVAS}[aria-label='Mind graph: 2 pages, 1 post type, 3 posts and 1 tag, 4 connections. Showing everything. Related lines hidden.']"
    toggle "Related"

    toggle "Tags"
    shows.call(6, 3)
    assert_nil screen_position(nid(tag))
    within(LIST) { assert_no_selector "h2", text: /tags/i }
    toggle "Tags"

    toggle "Post types"
    shows.call(6, 4)
    assert_nil screen_position("type-blog")
    within(LIST) { assert_no_selector "h2", text: /post types/i }
    toggle "Post types"

    toggle "Lists"
    shows.call(7, 4)
    assert screen_position("type-blog"), "the type stays, without its line"
    toggle "Tree"
    shows.call(7, 3)
    toggle "Lists"
    toggle "Tree"

    toggle "Pages"
    shows.call(5, 3)
    assert_nil screen_position(nid(home))
    assert_selector "#{CANVAS}[aria-label='Mind graph: 1 post type, 3 posts and 1 tag, 3 connections. Showing everything. Pages hidden.']"
    assert_selector "#{GRAPH} [role=status] p.sr-only", text: "Mind graph: 1 post type, 3 posts and 1 tag, 3 connections. Showing everything. Pages hidden.", visible: :all
    toggle "Pages"

    shows.call(7, 5)
    await_graph
    assert screen_position(nid(home))
  end
```

  The others, by what replaces the press:

| Test | Was | Becomes | And its figures |
|---|---|---|---|
| `"Back to the graph draws it once, with the filter the control shows"` | "Related" | `toggle "Tags"` | before: `data-nodes` 3 and the name `Mind graph: 2 posts and 1 tag, 3 connections. Showing everything.`; after the toggle 2 nodes, 1 line, `Mind graph: 2 posts, 1 connection. Showing everything. Tags hidden.`; in the restored page before its data: the canvas is named `Mind graph`, every `[data-legend-count]` is empty, no legend input has an `aria-label`, `input[name=mind_graph_nodes][value=tag]` is still unchecked (`assert_no_selector "… [value=tag]:checked", visible: :all`); after the data 2 nodes and 1 line again, the name with `Tags hidden.` again, and `legend_counts` reads `Tags 1` |
| `"a filter change with a node selected recomputes its neighbours"` | "Related", then "All" | `toggle "Shares a tag"` twice | off: the selection stays and the neighbours are `[ nid(c) ]`; on: `[ nid(c), tag_id ].sort` |
| `"a filter that hides the selected node clears the selection and closes the card"` | "Related" | `toggle "Tags"` | unchanged |
| `"a filter change keeps the pins of the nodes that remain and forgets the others"` | "Related", then "All" | `toggle "Tags"` twice | unchanged: one pin left, and none comes back |
| `"the worker can't start: the filter still narrows the list and the counts"` | "Related" | `toggle "Tags"` | `data-nodes='3'`, `data-edges='1'`; three rows, Alpha, Beta and Gamma, and no row "shared" |
| `"the list beside the canvas holds every drawn node as a row, grouped and counted, and follows the filter"` | "Related" | `toggle "Tags"` | headings `[ "POSTS · 3" ]`, rows `%w[Alpha Beta Gamma]` |

  In `"the Tab key meets the search first and the list last"` the classifier's line `if (element.name === "mind_graph_filter") return "filter"` becomes `if (element.closest("[data-mind-graph-legend]")) return "legend"` (it must stand before the line that reads `data-action`; the toggles and the "Status" button are both the legend's), and the expected order is `[ "search", "focus bar", "legend", "zoom", "canvas", "card", "list" ]`.

  The Status key, the Review Focus's ninth line:

```ruby
  # Third design answers and H6: status is not a filter. The key is a dialog
  # named "Status key" behind the legend's "Status" link, in the chip's words.
  test "the Status key opens from the keyboard as a dialog, and Escape gives the focus back" do
    create_post(title: "Alpha", tags: [ "t" ])
    create_post(title: "Beta", tags: [ "t" ])
    visit admin_mind_graph_path
    await_graph
    key = "dialog#mind-graph-status-key"
    assert_no_selector "#{key}[open]", visible: :all
    before = [ graph["data-nodes"], graph["data-edges"] ]

    button = find("#{GRAPH} [data-mind-graph-legend] button", text: "Status")
    button.execute_script("this.focus()")
    page.driver.browser.keyboard.type(:Enter)

    assert_selector "#{key}[open] h2", text: "Status key"
    assert_equal [ "Live", "Draft", "Scheduled", "Live, unpublished changes", "Live, change scheduled" ], all("#{key} li[data-legend-state]").map { |item| item.text.squish }
    await_js("document.querySelector('#mind-graph-status-key').contains(document.activeElement)")
    assert_no_selector "#{key} .admin-dialog__body input, #{key} .admin-dialog__body button, #{key} .admin-dialog__body a"
    assert_equal before, [ graph["data-nodes"], graph["data-edges"] ], "the key filters nothing"

    page.driver.browser.keyboard.type(:Escape)

    assert_no_selector "#{key}[open]", visible: :all
    await_js("document.activeElement?.textContent.trim() === 'Status'")
    assert_equal before, [ graph["data-nodes"], graph["data-edges"] ], "Escape closed the key and nothing of the graph"
  end
```

  Two more new tests, the Review Focus's fourth line:

```ruby
  test "a kind switched off takes the selection, the pins and the hover of its nodes with it, and switched on again brings the node back unpinned" do
    blog = create_page(title: "Blog")
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))
    visit admin_mind_graph_path
    await_graph
    drag_node(nid(blog), by: [ 60, 40 ])
    await_graph
    click_node(nid(blog))
    assert_equal [ nid(blog), "1" ], [ graph["data-selected"], graph["data-pinned"] ]

    toggle "Pages"

    assert_selector "#{GRAPH}[data-selected=''][data-pinned='0'][data-hovered='']"
    assert_no_selector "[data-mind-graph-card]", visible: :visible
    assert_no_button "Release 1 pinned"

    toggle "Pages"
    await_graph
    assert screen_position(nid(blog)), "the page did not come back"
    assert_equal "0", graph["data-pinned"], "a pin came back with the node"
  end

  test "with every kind off nothing is drawn and the list says so" do
    create_page(title: "Blog")
    a = create_post(title: "Alpha", tags: [ "t" ])
    create_post(title: "Beta", tags: [ "t" ])
    visit admin_mind_graph_path
    await_graph

    [ "Pages", "Posts", "Tags", "Post types" ].each { |name| toggle name }

    assert_selector "#{GRAPH}[data-nodes='0'][data-edges='0']"
    assert_selector "#{LIST} p", text: "Nothing is drawn yet."
    assert_selector "#{CANVAS}[aria-label='Mind graph: nothing to show. All types are hidden.']"
    assert_nil screen_position(a.id)
    toggle "Posts"
    assert_selector "#{GRAPH}[data-nodes='2']"
    assert_selector "#{CANVAS}[aria-label='Mind graph: 2 posts, 0 connections. Showing everything. Pages hidden. Tags hidden. Post types hidden.']"
    await_graph
  end
```

  ("Post types" has no node in the second test and is a toggle all the same: the viewer reads pages.)

  Run: `bin/rails tailwindcss:build && sysctl -n vm.loadavg`, then `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/mind_graph_test.rb test/system/admin/mind_graph_modules_test.rb`
  Expected: PASS.

- [ ] **Step 9: look at it, and report.** The legend in both themes at 1,440 and 1,000 pixels of width, with one and with eight toggles; Space on a focused toggle switches it; a screen reader's name for one (the accessibility tree in the browser's inspector: "Pages, 2"); the Status key open as a dialog, in both themes, its five swatches beside the same five looks on the canvas, and its words beside a card's chip; the canvas's name in the accessibility tree for the whole graph, for a page's local view at depth 2 with a pill, and with "Tags" off. Report the screenshots, the readings and the added wording named at the head of this task. Change no value.

- [ ] **Step 10: commit.**

```bash
git add app/components/admin/mind_graph_screen app/assets/tailwind/content-spiel.tailwind.css config/locales/admin app/views/admin/mind_graph/show.html.erb app/controllers/admin/mind_graph_controller.rb app/javascript test/components test/integration/admin/mind_graph_test.rb test/integration/trash_visibility_test.rb test/system/admin
git commit -m "feat: the mind graph's legend is its filter — eight toggles with counts in place of the three radios, the status key in a dialog behind a link, and a summary that says what is in view"
```

---
### Task 7: search finds pages, and the list has four groups, "Not listed on any page" and rows that are not in view

**The list has four groups** (the owner's decision of 2026-10-12): Pages, Posts, Tags, Post types. The search keeps three: a search row opens its local view, and a post type has none.

**Design readings to report** (screenshots of the open results and of the list, both themes): the group headings of the results in the list's own heading style; a page's marker in a row as a 10 by 7 ink card (`PAGE_MARK`); a page's indent of 12 pixels per level; the place of "Not listed on any page" as a checkbox row above the groups; "not in view" where a row's count stands; the error line as a paragraph with a small secondary button under it, in the list. From the designer, verbatim (G5, H7): a row's accessible name when its post is not drawn, `"%{title}, %{type} post, not in view. Activate to add it to the graph."`, with the type's label in lower case ("blog post"), and for a post of a RETIRED type its stored name in lower case followed by "retired type" ("talk, retired type"); `"The list couldn't be loaded."` with `"Try again"`.

**A row of the "Post types" group is the designer's** (H2): its mark is a smaller copy of the hub as the canvas draws it, 10px with the inner ring ("All posts" filled dim, a ring type's a ring round a centre, a retired type's a dim dashed outline with a centre dot); its number is the count of POSTS of that type on the site, where a tag's row has its number ("All posts" shows the site's total); the rows come in colour-slot order, then the retired types, then "All posts" last, which is the order the data has them in (Task 3). **Readings to report**: the hub's parts at 10px are the canvas's scaled by 10/12 (`.mg-hub`); "on the site" is what the viewer can read of it, as every count of this screen is. **Strings nobody gave**: the group's heading `"Post types · %{count}"` (the legend's own words for the kind) and a row's name `"%{title}: post type, %{count} posts. Shows it in the graph."` (the other rows' sentence, with what its number counts). **Still open, and built the plain way**: H7's "a name capitalised by design (a brand) stays as stored" cannot be told from the data, so every type's label is lowered as the messages' language lowers it.

**Files:**
- Modify: `app/queries/post_graph/search.rb`, `app/controllers/admin/mind_graph_controller.rb` (no code: `search` already builds the URL from `kind` and `record_id`), `app/views/admin/mind_graph/show.html.erb`, `config/locales/admin/mind_graph.en.yml`, `app/javascript/mind_graph/search_box.js`, `node_list.js`, `card.js` (one constant and `hubMark`), `app.js`, `layout_worker.js`, `layout_client.js`, `app/assets/tailwind/content-spiel.tailwind.css` (`.mg-hub`)
- Test: `test/queries/post_graph/search_test.rb`, `test/integration/admin/mind_graph_data_test.rb`, `test/integration/admin/mind_graph_test.rb`, `test/integration/trash_visibility_test.rb`, `test/system/admin/mind_graph_modules_test.rb`, `test/system/admin/mind_graph_test.rb`

**Interfaces:**
- Consumes: `PostGraph::Tree`, `PostGraph.paths` (Task 2); `GET mind_graph/unlisted` (Task 4); `visible`, `counts` (Task 6).
- Produces:

```ruby
PostGraph::Search.call(actor:, text:, locale: Locales.default, limit: 10)
# => [ { kind: "page", id: "page-3", record_id: 3, label: "About", path: "/about" | nil }, …   up to `limit`, in tree order
#      { kind: "post", id: "post-12", record_id: 12, label: "…", colour_index: 1 | nil }, …
#      { kind: "tag",  id: "tag-4",  record_id: 4,  label: "ruby" }, … ]
```

```js
// node_list.js
createList(container, { text, dotClasses, typeLabels, retryClass, onSelect, onHover, onAdd, onUnlisted })
  // => { render(nodes), showRows({ heading, rows, inView, link }), fail(line, { label, onRetry, focus }), focus(), setUnlisted(on), mark(id), row(id), destroy() }
  //    onAdd(row): a row that is not in view was pressed; onUnlisted(on): the checkbox changed
  //    rows: post nodes as the data has them (a row of `listed` with `via`); inView(id) => boolean; link: { href, label } | null
  //    typeLabels: a type's human name by its stored name (the view's `data-type-labels`); retryClass: the small secondary button's classes
// card.js
PAGE_MARK        // the class string of a page's small mark in a row and a card
hubMark(node)    // an element: the small copy of a post type's hub (10px) for a row and a card; "All posts", a ring type's and a retired type's each as the canvas has it
// layout worker: { type: "add", node: { id, radius, x, y }, edges: [{ source, target, kind }] };  layout.add(node, edges)
// view: data-unlisted-url on the controller's element
```

- [ ] **Step 1: the search's failing tests.** In `test/queries/post_graph/search_test.rb`:

```ruby
  test "pages come first, in tree order, each with its path; then posts with their type's colour; then tags" do
    docs = create_page(title: "Ruby docs")
    guide = create_page(title: "Ruby guide", parent: docs)
    early = create_page(title: "A Ruby page")
    post = create_post(title: "Ruby notes", tags: [ "ruby" ])
    tag = Tag.find_by!(name: "ruby")

    assert_equal [
      { kind: "page", id: "page-#{docs.id}", record_id: docs.id, label: "Ruby docs", path: "/ruby-docs" },
      { kind: "page", id: "page-#{guide.id}", record_id: guide.id, label: "Ruby guide", path: "/ruby-docs/ruby-guide" },
      { kind: "page", id: "page-#{early.id}", record_id: early.id, label: "A Ruby page", path: "/a-ruby-page" },
      { kind: "post", id: "post-#{post.id}", record_id: post.id, label: "Ruby notes", colour_index: ContentTypes.fetch("blog").colour_index },
      { kind: "tag", id: "tag-#{tag.id}", record_id: tag.id, label: "ruby" }
    ], search("ruby")
  end

  test "at most `limit` pages, the first of the tree" do
    pages = 3.times.map { |index| create_page(title: "Many #{index}") }

    assert_equal pages.first(2).map { |page| "page-#{page.id}" }, search("many", limit: 2).select { |row| row[:kind] == "page" }.map { |row| row[:id] }
  end

  test "a page outside the viewer's scope and a trashed page are not listed" do
    seen = create_page(title: "Plan seen")
    create_page(title: "Plan hidden")
    create_page(title: "Plan gone").update_column(:trashed_at, Time.current)
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ seen.id ] })

    assert_equal [ "Plan seen" ], as(users(:author)) { search("plan", actor: users(:author)) }.select { |row| row[:kind] == "page" }.map { |row| row[:label] }
    assert_equal [ "Plan seen", "Plan hidden" ], search("plan").map { |row| row[:label] }
  end

  test "it costs five statements whatever the number of pages, and loads no page whole" do
    3.times { |index| create_page(title: "Count #{index}") }
    few = capture_sql { search("count") }
    27.times { |index| create_page(title: "Count more #{index}") }
    many = capture_sql { search("count") }

    assert_equal [ 5, 5 ], [ few.size, many.size ], many.join("\n")
    assert many.none? { |sql| sql.include?('"pages".*') }, "a whole page row was loaded"
  end
```

  Update `"posts by title and tags by name, posts first"` (a post's row gains `colour_index`) and `"posts are loaded with only the id and the title"` (the columns are now `"posts"."id", "posts"."title", "posts"."content_type"`; rename the test to say "the id, the title and the type"). The first test's paths assume the slug a title gets; if `create_page` derives another, read `PublicPath.current.where(record: docs).pick(:path)` in the test instead of writing the literal.

  Run: `PGGSSENCMODE=disable bin/rails test test/queries/post_graph/search_test.rb`; expected FAIL: no page row.

- [ ] **Step 2: the search.** In `app/queries/post_graph/search.rb`, `call` becomes (and the header says pages, the tree order, and that a page is loaded with its id and title only):

```ruby
    def call
      return [] if @text.empty?

      readable_pages = AccessControl.scope(@actor, "pages.read", Page.all)
      tree = Tree.new(readable_pages.pluck(:id, :parent_id, :position))
      pages = readable_pages.title_matching_any_locale(@text).select(:id, :title).sort_by { |page| tree.rank(page.id) }.first(@limit)
      paths = PostGraph.paths(pages.map(&:id), locale: @locale)

      readable = AccessControl.scope(@actor, "posts.read", Post.all)
      posts = readable.title_matching_any_locale(@text).select(:id, :title, :content_type).order(:id).limit(@limit)
      tags = Tag.name_containing(@text).where(id: PostTag.where(post_id: readable.select(:id)).select(:tag_id))
                .name_starting_first(@text).by_name.limit(@limit).pluck(:id, :name)

      pages.map { |page| { kind: "page", id: PostGraph.node_id(:page, page.id), record_id: page.id, label: Locales.read(page, :title, locale: @locale), path: paths[page.id] } } +
        posts.map { |post| { kind: "post", id: PostGraph.node_id(:post, post.id), record_id: post.id, label: Locales.read(post, :title, locale: @locale), colour_index: post.definition&.colour_index } } +
        tags.map { |id, name| { kind: "tag", id: PostGraph.node_id(:tag, id), record_id: id, label: name } }
    end
```

  Run the file; expected PASS. In `test/integration/admin/mind_graph_data_test.rb`, `"search answers rows with the url of each row's local view"` gains a page whose row is `{ "kind" => "page", …, "path" => …, "url" => "/cs-studio/mind_graph?page=#{page.id}" }`; in `test/integration/trash_visibility_test.rb`, the search for `"gone"` already expects no row at all, and now covers `Gone page` too (say so in its comment). Run both; expected PASS.

- [ ] **Step 3: the strings and the address.** In `config/locales/admin/mind_graph.en.yml`, under `script`, `search` and `list` become:

```yaml
        list:
          pages: "Pages · %{count}"
          posts: "Posts · %{count}"
          tags: "Tags · %{count}"
          types: "Post types · %{count}"
          empty: "Nothing is drawn yet."
          unlisted: "Not listed on any page"
          not_in_view: "not in view"
          open_in_posts: "Open in Posts →"
          failed: "The list couldn't be loaded."
          try_again: "Try again"
          select_page:
            one: "%{title}: page, %{count} connection. Shows it in the graph."
            other: "%{title}: page, %{count} connections. Shows it in the graph."
          select_post:
            one: "%{title}: post, %{count} connection. Shows it in the graph."
            other: "%{title}: post, %{count} connections. Shows it in the graph."
          select_tag:
            one: "%{title}: tag, %{count} connection. Shows it in the graph."
            other: "%{title}: tag, %{count} connections. Shows it in the graph."
          select_type:
            one: "%{title}: post type, %{count} post. Shows it in the graph."
            other: "%{title}: post type, %{count} posts. Shows it in the graph."
          add_post: "%{title}, %{type} post, not in view. Activate to add it to the graph."
          add_retired_post: "%{title}, %{type}, retired type, not in view. Activate to add it to the graph."
        search:
          count:
            one: "%{count} result"
            other: "%{count} results"
          none: "No page, post or tag matches."
          failed: "Search failed — check your connection."
          groups:
            page: "Pages"
            post: "Posts"
            tag: "Tags"
```

  (`search.post` and `search.tag` go: the group's heading names the kind.) In `show.html.erb`'s `messages_data(...)`: remove `"mind_graph.script.search.post"` and `"mind_graph.script.search.tag"`; add `"mind_graph.script.search.groups.page"`, `"mind_graph.script.search.groups.post"`, `"mind_graph.script.search.groups.tag"`, `"mind_graph.script.list.pages"`, `"mind_graph.script.list.types"`, `"mind_graph.script.list.unlisted"`, `"mind_graph.script.list.not_in_view"`, `"mind_graph.script.list.open_in_posts"`, `"mind_graph.script.list.failed"`, `"mind_graph.script.list.try_again"`, `"mind_graph.script.list.select_page"`, `"mind_graph.script.list.select_type"`, `"mind_graph.script.list.add_post"`, `"mind_graph.script.list.add_retired_post"`. (`add_post` is the designer's sentence, G5: `%{type}` is the post TYPE's name, so the row says "blog post" and never a bare "post"; `add_retired_post` is its form for a post of a retired type, H7: "talk, retired type". `select_type`'s `count` is the type's posts, the number its row shows. `failed` and `try_again` are the designer's too.) Say in the locale file's header comment that `script.list.add_post` and the `select_*` keys are a row's whole accessible name. On the controller's element, beside the other templates:

```erb
       data-unlisted-url="<%= unlisted_admin_mind_graph_path(**admin_url_options) %>"
```

  Update `"the script's messages ride on the element"` (the key list) and `"the card's URL templates and the type labels ride on the element"` (the new attribute) in `test/integration/admin/mind_graph_test.rb`.

- [ ] **Step 4: the search box.** In `app/javascript/mind_graph/card.js`, beside `TAG_MARK`:

```js
// A page's mark where a mark is an element (a row of the list, a search
// result, the card): a small card in ink, as the canvas draws it.
export const PAGE_MARK = "h-[7px] w-[10px] shrink-0 rounded-cs bg-ink"
// A post type's hub where a mark is an element (a row of the list's "Post
// types" group, the type's card; design answer H2): a smaller copy of the
// hub as the canvas draws it, 10px, with its inner ring. The shapes are the
// stylesheet's (`.mg-hub`, on tokens); the hue comes in as a token's NAME,
// never a value. "All posts" is filled dim, a ring type's (slots 7-12) a
// ring round a centre, a retired type's a dashed dim outline with a centre.
export function hubMark(node) {
  const mark = document.createElement("span")
  mark.setAttribute("aria-hidden", "true")
  const slot = node.colour_index == null ? null : (node.colour_index - 1) % 12
  mark.className = `mg-hub${node.id === "all-posts" ? " mg-hub-all" : slot == null ? " mg-hub-retired" : slot >= 6 ? " mg-hub-ring" : ""}`
  if (slot != null) mark.style.setProperty("--mg-hue", `var(--cs-cat-${(slot % 6) + 1})`)
  return mark
}
```

  and in `app/assets/tailwind/content-spiel.tailwind.css`, beside the legend's `.mg-*` rules:

```css
/* A post type's hub as an element, 10px (design answer H2): the canvas's hub
   scaled by 10/12, so its inner ring is 1.25px wide, 1.25px in. */
.mg-hub { position: relative; display: inline-block; flex: none; box-sizing: border-box; width: 10px; height: 10px; border-radius: var(--cs-radius-pill); background: var(--mg-hue); }
.mg-hub::after { content: ""; position: absolute; inset: 1.25px; box-sizing: border-box; border: 1.25px solid var(--cs-surface); border-radius: var(--cs-radius-pill); }
.mg-hub-all { --mg-hue: var(--cs-dim); }
/* A ring type's: a ring in the hue round a filled centre 5px across. */
.mg-hub-ring { background: var(--cs-surface); border: 1.25px solid var(--mg-hue); }
.mg-hub-ring::after { inset: 1.25px; border: 0; background: var(--mg-hue); }
/* A retired type's: a dashed dim ring round a small dim centre. */
.mg-hub-retired { background: var(--cs-surface); border: 1.25px dashed var(--cs-dim); }
.mg-hub-retired::after { inset: 2.1px; border: 0; background: var(--cs-dim); }
```

  In `app/javascript/mind_graph/search_box.js`: `attachSearch(field, list, { url, text, status, dotClasses })` (the app passes its `dotClasses`), `KIND_KEYS` goes, and `onRows` draws groups. The header comment says: grouped Pages / Posts / Tags, each row with its kind's mark, a page with its path under its title; the rows are still plain links.

```js
import { createSuggestions } from "search/suggestions"
import { dotClass, TAG_MARK, PAGE_MARK } from "mind_graph/card"

const GROUPS = [ "page", "post", "tag" ]
const LINK = "flex items-center gap-2 rounded-cs px-2 py-1.5 text-sm text-ink hover:bg-sunken focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-accent"
```

```js
    onRows: (_query, rows) => {
      if (rows.length === 0) return say(text.t("mind_graph.script.search.none"))

      const element = (tag, className, content) => {
        const created = document.createElement(tag)
        if (className) created.className = className
        if (content != null) created.textContent = content
        return created
      }
      const result = (row) => {
        const item = document.createElement("li")
        const link = element("a", LINK)
        link.href = row.url
        const mark = element("span", row.kind === "page" ? PAGE_MARK : row.kind === "tag" ? TAG_MARK : dotClass(dotClasses, row))
        mark.setAttribute("aria-hidden", "true")
        const words = element("span", "flex min-w-0 flex-col")
        words.append(element("span", "truncate", row.label))
        // A page's address under its title: two pages may share a title.
        if (row.kind === "page" && row.path) words.append(element("span", "truncate font-cs-mono text-label text-meta", row.path))
        link.append(mark, words)
        item.append(link)
        return item
      }
      list.replaceChildren(...GROUPS.flatMap((kind) => {
        const found = rows.filter((row) => row.kind === kind)
        if (found.length === 0) return []

        const group = document.createElement("li")
        group.dataset.searchGroup = kind
        const heading = element("p", "m-0 px-2 pb-0.5 pt-1.5 font-cs-mono text-label uppercase tracking-mono text-meta", text.t(`mind_graph.script.search.groups.${kind}`))
        heading.id = `mind-graph-results-${kind}`
        const items = element("ul", "m-0 list-none p-0")
        items.setAttribute("aria-labelledby", heading.id)
        items.append(...found.map(result))
        group.append(heading, items)
        return [ group ]
      }))
      list.hidden = false
      status.textContent = text.t("mind_graph.script.search.count", { count: rows.length })
    },
```

  (A row's text and path go in with `textContent`; `href` is the server's.) In `app.js` the call gains `dotClasses`.

- [ ] **Step 5: the list.** Replace `app/javascript/mind_graph/node_list.js`. Its header keeps what is still true (a row is a button and never navigates; the accessible name; hover; the mark; scrolling inside the panel) and says what is new:

```js
// FOUR GROUPS: "Pages · N" first, in TREE order with an indent per level
// (not by connections: a tree is read by its order), then "Posts · N" and
// "Tags · N", best-connected first as on the canvas, then "Post types · N":
// a row for each post-type node and for "All posts", so each has a keyboard
// path to its card (the owner's decision of 2026-10-12). A ROW OF THAT
// GROUP is the design answer's (H2): its mark a small copy of the hub
// (`hubMark`), its number the POSTS of that type the viewer can read (a
// tag's row has its connections there), in the order the data has them --
// colour-slot order, then retired types, then "All posts" last. "+N more"
// has no row: pressed on the canvas, it IS the list.
//
// ABOVE THE GROUPS, "Not listed on any page" (pages spec §7): while it is
// on, the list shows the rows the app hands `showRows` IN PLACE OF the
// groups, and the canvas is left as it is. The same form serves the posts
// behind a page's "+N more", with "Open in Posts →" under them.
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
// is announced. The checkbox above stays, so the filter can be let go.
//
// `createList(container, { text, dotClasses, typeLabels, retryClass,
// onSelect, onHover, onAdd, onUnlisted })` answers `{ render(nodes),
// showRows({ heading, rows, inView, link }), fail(line, { label, onRetry,
// focus }), focus(), setUnlisted(on), mark(id), row(id), destroy() }`.
import { dotClass, hubMark, TAG_MARK, PAGE_MARK } from "mind_graph/card"

const byDegree = (a, b) => b.degree - a.degree || String(a.title).localeCompare(String(b.title))
const byTree = (a, b) => a.order - b.order
// The order the data has them (design answer H2): colour-slot order, then
// the retired types, then "All posts" last.
const asGiven = () => 0
const ROW = "flex w-full cursor-pointer items-center gap-2 px-3 py-1 text-left text-sm text-ink hover:bg-sunken focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-accent aria-[current]:bg-accent-tint aria-[current]:font-semibold"
const NAMES = { page: "mind_graph.script.list.select_page", post: "mind_graph.script.list.select_post", tag: "mind_graph.script.list.select_tag", type: "mind_graph.script.list.select_type" }
// A page's indent per level of the tree, in pixels, on top of the row's own.
const INDENT = 12
const ROW_PADDING = 12

export function createList(container, { text, dotClasses, typeLabels = {}, retryClass = "", onSelect, onHover, onAdd, onUnlisted }) {
  let rows = new Map()
  let absent = new Map()
  let marked = null

  const element = (tag, className, content) => {
    const created = document.createElement(tag)
    if (className) created.className = className
    if (content != null) created.textContent = content
    return created
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
  container.replaceChildren(filter, body)
  const changed = () => onUnlisted(unlisted.checked)
  unlisted.addEventListener("change", changed)

  const section = (title, items) => {
    const wrapper = document.createElement("section")
    const list = element("ul", "m-0 list-none p-0")
    list.append(...items)
    wrapper.append(element("h2", "m-0 px-3 pb-1 pt-3 font-cs-mono text-label uppercase tracking-mono text-meta", title), list)
    return wrapper
  }
  const markOf = (node) => (node.kind === "page" ? PAGE_MARK : node.kind === "tag" ? TAG_MARK : dotClass(dotClasses, node))
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
  const row = (node, { notInView = false } = {}) => {
    const item = document.createElement("li")
    const button = element("button", ROW)
    button.type = "button"
    button.dataset.nodeId = node.id
    button.setAttribute("aria-label", notInView ? addName(node) : text.t(NAMES[node.kind], { title: node.title, count: figure(node) }))
    // A page stands under its parent: indented by its depth in the tree.
    if (node.kind === "page") button.style.paddingInlineStart = `${ROW_PADDING + (node.depth || 0) * INDENT}px`
    const mark = node.kind === "type" ? hubMark(node) : element("span", markOf(node))
    mark.setAttribute("aria-hidden", "true")
    const trailing = notInView ? element("span", "shrink-0 text-label text-meta", text.t("mind_graph.script.list.not_in_view")) : element("span", "shrink-0 font-cs-mono text-label text-meta", figure(node))
    button.append(mark, element("span", "min-w-0 flex-1 truncate", node.title), trailing)
    item.append(button)
    rows.set(node.id, button)
    if (notInView) {
      button.dataset.notInView = ""
      absent.set(node.id, node)
    }
    return item
  }
  const forget = () => {
    rows = new Map()
    absent = new Map()
    marked = null
  }

  const rowOf = (event) => event.target.closest?.("button[data-node-id]")
  const click = (event) => {
    const button = rowOf(event)
    if (!button) return
    if (absent.has(button.dataset.nodeId)) onAdd(absent.get(button.dataset.nodeId))
    else onSelect(button.dataset.nodeId)
  }
  const over = (event) => {
    const button = rowOf(event)
    if (button && !absent.has(button.dataset.nodeId)) onHover(button.dataset.nodeId)
  }
  const out = (event) => {
    if (rowOf(event)) onHover(null)
  }
  const listeners = { click, pointerover: over, pointerout: out, focusin: over, focusout: out }
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
      if (!groups.length) return body.replaceChildren(line(text.t("mind_graph.script.list.empty")))

      body.replaceChildren(...groups.map(([ name, found ]) => section(text.t(`mind_graph.script.list.${name}`, { count: found.length }), found.map((node) => row(node)))))
    },
    // A filter's rows in place of the groups. `inView(id)`: whether the
    // canvas draws that post now.
    showRows({ heading, rows: given, inView, link = null }) {
      forget()
      const parts = [ section(heading, given.map((node) => row({ ...node, kind: "post" }, { notInView: !inView(node.id) }))) ]
      if (link) {
        const anchor = element("a", "mx-3 mt-2 inline-block text-sm text-accent underline", link.label)
        anchor.href = link.href
        anchor.dataset.mindGraphPostsLink = ""
        parts.push(anchor)
      }
      body.replaceChildren(...parts)
    },
    // A read that failed (design answer G5): the line and a small button
    // that asks again, in the list. `focus`: the press that asked was the
    // button's own, which this call has just removed, so the new one takes
    // the focus and the keyboard is not left on nothing.
    fail(content, { label, onRetry, focus = false }) {
      forget()
      const said = element("div", "flex flex-col items-start gap-2 px-3 py-3")
      said.setAttribute("role", "alert")
      const again = element("button", retryClass, label)
      again.type = "button"
      again.dataset.mindGraphRetry = ""
      again.addEventListener("click", onRetry)
      said.append(element("p", "m-0 text-sm text-meta", content), again)
      body.replaceChildren(said)
      if (focus) again.focus()
    },
    // The first row, or the checkbox when there is none: where the focus
    // goes when "Try again" has brought the rows.
    focus() { (body.querySelector("button[data-node-id]") || unlisted).focus() },
    setUnlisted(on) { unlisted.checked = on },
    mark,
    row: (id) => rows.get(id) || null,
    destroy() {
      unlisted.removeEventListener("change", changed)
      Object.entries(listeners).forEach(([ name, handler ]) => body.removeEventListener(name, handler))
      container.replaceChildren()
    }
  }
}
```

  (An id is a string now, so the second map of ids the old file kept is gone; the group's heading reads `"mind_graph.script.list.pages"`, `…posts`, `…tags` and `…types`, which `test/lib/script_messages_test.rb` accepts as `list.${…}` against the served keys. `sort` with `asGiven` keeps the given order, which is the server's and the design answer's (H2): the sort is stable. `line` is still used by `render` for the empty list.)

- [ ] **Step 6: the worker learns `add`.** In `layout_worker.js`, the header's "Messages in" gains `{ type: "add", node: { id, radius, x, y }, edges: [{ source, target, kind }] }   one more node, placed where the page says, with its lines`; in `handle`:

```js
  } else if (message.type === "add") {
    add(message.node, message.edges)
```

```js
// One more node after the layout began (a post added from the list): it
// starts where the page put it, its lines (to the hub that brings it in,
// when it has one) join the others, and the layout
// warms up enough to make room. `positions` covers it from the next `tick`.
function add(node, givenEdges) {
  if (find(node.id)) return idle()
  const added = { id: node.id, radius: node.radius, anchor: false, held: false, x: node.x, y: node.y }
  nodes.push(added)
  const lines = givenEdges.map((edge) => ({ source: edge.source, target: edge.target, kind: edge.kind, index: edges.length + givenEdges.indexOf(edge) }))
  edges.push(...lines)
  shown = null
  simulation.nodes([ ...simulation.nodes(), added ])
  simulation.force("link").links([ ...simulation.force("link").links(), ...lines ])
  simulation.alphaTarget(0).alpha(Math.max(simulation.alpha(), HELD_ALPHA))
  pace = "frame"
  run()
}
```

  In `layout_client.js`: `add(node, edges) { send({ type: "add", node, edges }) },`. A module test:

```ruby
  test "the layout takes one more node with its line after it has come to rest, places it where it is told, and settles again" do
    result = using_wait_time(40) do
      page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"), ActionController::Base.helpers.asset_path("d3-force.js"))
        const [workerUrl, d3Url, done] = arguments
        import("mind_graph/layout_client").then(({ createLayout }) => {
          let last = null
          let first = null
          const layout = createLayout({
            workerUrl, d3Url,
            onTick: (positions) => { last = Array.from(positions) },
            onSettled: () => {
              if (!first) { first = last; layout.add({ id: "post-9", radius: 7, x: last[2] + 30, y: last[3] + 30 }, [ { source: "type-blog", target: "post-9", kind: "brings" } ]); layout.add({ id: "post-9", radius: 7, x: 0, y: 0 }, []) }
              else { layout.stop(); done({ first, last }) }
            },
            onError: (message) => done({ error: message })
          })
          layout.start([ { id: "page-1", radius: 9, anchor: true }, { id: "type-blog", radius: 6 } ], [ { source: "page-1", target: "type-blog", kind: "lists" } ], { reducedMotion: true })
        })
      JS
    end

    assert_nil result["error"]
    assert_equal [ 4, 6 ], [ result["first"].size, result["last"].size ], "the second add of the same node added nothing"
    assert_equal [ 0, 0 ], result["last"].first(2)
    assert_operator Math.hypot(result["last"][4] - result["last"][2], result["last"][5] - result["last"][3]), :<, 200, "the added node is joined to the hub that brings it in"
  end
```

- [ ] **Step 7: the app.** In `app/javascript/mind_graph/app.js`:
  - `createList(…)` gains `typeLabels` (the app's own, from `data-type-labels`), `retryClass: buttonClasses.secondary`, `onAdd: addPost` and `onUnlisted: (on) => { if (on) showRowsFrom(element.dataset.unlistedUrl); else showGroups() }`; `onSelect` and `onHover` get the id as it is (`indexOf.get(id)`), as before.
  - What the list shows is one function, called where `applyFilter` called `list.render` and `list.mark`:

```js
  // The list shows the groups of what is drawn, or -- while "Not listed on
  // any page" is on, or after "+N more" -- a read's rows in their place.
  // `rowsShown` is that read's answer, kept so that the rows can be drawn
  // again when what is in view changes (a post was added, a kind switched).
  let rowsShown = null

  function drawList() {
    if (rowsShown) list.showRows({ ...rowsShown, inView: (id) => state.visibleNodes.includes(indexOf.get(id)) })
    else list.render(state.visibleNodes.map((index) => state.nodes[index]))
    list.mark(state.selected >= 0 ? state.nodes[state.selected].id : null)
  }

  function showGroups() {
    rowsShown = null
    list.setUnlisted(false)
    drawList()
  }

  // One of the list's reads (`unlisted`, or a page's `listed`). A plain
  // `fetch`, ended with everything else when the screen is left. A read
  // that fails says so in the list with "Try again" (design answer G5),
  // which asks for the same read; `again` says the ask came from that
  // button, which is gone by then, so the focus is put where the answer is.
  async function showRowsFrom(url, { postsLink = false, again = false } = {}) {
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, signal: aborter.signal })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const answer = await response.json()
      if (destroyed) return
      rowsShown = {
        heading: text.t("mind_graph.script.list.posts", { count: number(answer.total) }),
        rows: answer.rows,
        link: postsLink && answer.posts_url ? { href: answer.posts_url, label: text.t("mind_graph.script.list.open_in_posts") } : null
      }
      drawList()
      if (again) list.focus()
    } catch (error) {
      if (destroyed || error.name === "AbortError") return
      rowsShown = null
      list.fail(text.t("mind_graph.script.list.failed"), { label: text.t("mind_graph.script.list.try_again"), focus: again, onRetry: () => showRowsFrom(url, { postsLink, again: true }) })
    }
  }
```

    In `show` (a new load): `rowsShown = null` and `list.setUnlisted(false)` before `applyFilter()`.
  - A row that is not in view:

```js
  // A post the canvas does not draw, added from its row (pages spec §7): the
  // row IS the post's node, so nothing is fetched. Added once: pressed again,
  // or for a post that is drawn after all, it selects. A row of a page's
  // "+N more" says which hub brings its post in (`via`), and the post gets
  // that hub's line, as the posts the view drew have theirs: a faint line
  // from a post type or "All posts", its own "Shares a tag" line to a tag.
  // A row of "Not listed on any page" has no hub, and its post no line.
  function addPost(row) {
    const known = indexOf.get(row.id)
    if (known != null) return state.visibleNodes.includes(known) ? reveal(known) : undefined

    const node = { ...row, kind: "post" }
    node.label = labelFor(node)
    node.cut = !node.label.startsWith(String(node.title))
    const index = state.nodes.push(node) - 1
    indexOf.set(node.id, index)
    state.radii.push(radiusFor(node))
    state.boxes.push(boxOf(node))
    context.font = state.theme.font
    state.widths.push(context.measureText(node.label).width)

    const hub = row.via == null ? -1 : indexOf.get(row.via) ?? -1
    const at = hub >= 0 && state.placed ? [ state.positions[hub * 2] + 30, state.positions[hub * 2 + 1] + 30 ] : [ 30, 30 ]
    const positions = new Float32Array(state.nodes.length * 2)
    positions.set(state.positions)
    positions.set(at, index * 2)
    state.positions = positions
    const lines = hub < 0 ? [] : state.nodes[hub].kind === "tag" ? [ { kind: "tag", source: index, target: hub } ] : [ { kind: "brings", source: hub, target: index } ]
    state.edges.push(...lines)

    applyFilter()
    writeCounts()
    if (layout) {
      element.removeAttribute("data-settled")
      layout.add({ id: node.id, radius: collisionRadius(node), x: at[0], y: at[1] }, lines.map((line) => ({ source: state.nodes[line.source].id, target: state.nodes[line.target].id, kind: line.kind })))
      if (state.visibleNodes.length < state.nodes.length || state.visibleEdges.length < state.edges.length) sendFilter()
    }
    if (state.visibleNodes.includes(index)) reveal(index)
  }

  // What a row does to its node: select it, bring it to the middle, and
  // hand the focus to its card.
  function reveal(index) {
    select(index)
    openedFromRow = state.nodes[index].id
    centre(index)
    cardElement.focus()
  }
```

    and the list's `onSelect` becomes `(id) => { const index = indexOf.get(id); if (index != null) reveal(index) }`.

- [ ] **Step 8: the module tests of the list.** In `test/system/admin/mind_graph_modules_test.rb` (the list is built in the page the test is on, in a detached element, and read back):

```ruby
  LIST_SCRIPT = <<~JS.freeze
    (() => {
      const container = document.createElement("div")
      const calls = []
      const text = { t: (key, values = {}) => `${key.split(".").slice(-2).join(".")}(${Object.values(values).join(",")})`, locale: () => "en" }
      const list = m.createList(container, { text, dotClasses: Array(12).fill("dot"), typeLabels: { blog: "Blog" }, retryClass: "retry", onSelect: (id) => calls.push([ "select", id ]), onHover: () => {},
                                             onAdd: (row) => calls.push([ "add", row.id ]), onUnlisted: (on) => calls.push([ "unlisted", on ]) })
      const read = () => Array.from(container.querySelectorAll("h2, button")).map((item) => item.tagName === "H2" ? item.textContent : [ item.querySelector(".truncate").textContent, item.lastChild.textContent, item.style.paddingInlineStart, item.getAttribute("aria-label") ])
      return { container, calls, list, read }
    })()
  JS

  test "list: four groups: Pages first, in tree order and indented by depth, then posts and tags by their connections, then the post types as the data has them" do
    rows = js_module("mind_graph/node_list", <<~JS)
      (() => {
        const { list, read } = #{LIST_SCRIPT}
        list.render([ { id: "post-1", kind: "post", title: "Post", degree: 1, colour_index: 1 }, { id: "tag-1", kind: "tag", title: "tag", degree: 2 },
                      { id: "page-3", kind: "page", title: "Child", degree: 9, depth: 2, order: 2 }, { id: "page-1", kind: "page", title: "Home", degree: 1, depth: 0, order: 0 },
                      { id: "page-2", kind: "page", title: "Docs", degree: 2, depth: 1, order: 1 }, { id: "page-9", kind: "page", title: "Stray", degree: 0, depth: 1, order: 3 },
                      { id: "type-blog", kind: "type", title: "Blog", degree: 4, count: 112, colour_index: 1 }, { id: "type-talk", kind: "type", title: "Talk", degree: 9, count: 1, colour_index: 8 },
                      { id: "type-gone", kind: "type", title: "gone (retired)", degree: 1, count: 0, colour_index: null }, { id: "all-posts", kind: "type", title: "All posts", degree: 1, count: 2040, colour_index: null },
                      { id: "more-type-blog", kind: "more", title: "+3 more", degree: 1 } ])
        return { rows: read(), marks: Array.from(list.row("all-posts").closest("ul").querySelectorAll("button > span[aria-hidden]"), (mark) => [ mark.className, mark.style.getPropertyValue("--mg-hue") ]) }
      })()
    JS

    assert_equal [ "list.pages(4)", [ "Home", "1", "12px", "list.select_page(Home,1)" ], [ "Docs", "2", "24px", "list.select_page(Docs,2)" ],
                   [ "Child", "9", "36px", "list.select_page(Child,9)" ], [ "Stray", "0", "24px", "list.select_page(Stray,0)" ],
                   "list.posts(1)", [ "Post", "1", "", "list.select_post(Post,1)" ], "list.tags(1)", [ "tag", "2", "", "list.select_tag(tag,2)" ],
                   "list.types(4)", [ "Blog", "112", "", "list.select_type(Blog,112)" ], [ "Talk", "1", "", "list.select_type(Talk,1)" ],
                   [ "gone (retired)", "0", "", "list.select_type(gone (retired),0)" ], [ "All posts", "2040", "", "list.select_type(All posts,2040)" ] ], rows["rows"],
      "a page whose parent is not in the data is listed after the tree, indented once; a post type's number is its POSTS, not its connections, and the rows keep the data's order; a pill has no row"
    assert_equal [ [ "mg-hub", "var(--cs-cat-1)" ], [ "mg-hub mg-hub-ring", "var(--cs-cat-2)" ], [ "mg-hub mg-hub-retired", "" ], [ "mg-hub mg-hub-all", "" ] ], rows["marks"],
      "a small copy of the hub: a ring type's a ring, a retired type's dashed, All posts dim; the hue is a token's name"
  end

  test "list: a row that is not in view is named with its type and asks to be added, one in view selects, and the checkbox reports its change" do
    result = js_module("mind_graph/node_list", <<~JS)
      (() => {
        const { container, calls, list, read } = #{LIST_SCRIPT}
        document.body.append(container) // a checkbox outside the document changes without saying so
        list.showRows({ heading: "Posts · 3", rows: [ { id: "post-1", title: "Drawn", degree: 3, colour_index: 1, type: "blog" }, { id: "post-2", title: "<b>Absent</b>", degree: 0, colour_index: 1, type: "blog" },
                                                      { id: "post-3", title: "Old", degree: 0, colour_index: null, type: "<i>Gone</i>" } ],
                        inView: (id) => id === "post-1", link: { href: "/posts?type=blog", label: "Open in Posts" } })
        const rows = read()
        container.querySelectorAll("button").forEach((button) => button.click())
        const box = container.querySelector("input[type=checkbox]")
        box.click()
        const link = container.querySelector("a[data-mind-graph-posts-link]")
        return { rows, calls, link: [ link.getAttribute("href"), link.textContent ], markup: container.querySelectorAll("b, i").length, checked: box.checked, label: box.closest("label").textContent }
      })()
    JS

    assert_equal [ "Posts · 3", [ "Drawn", "3", "", "list.select_post(Drawn,3)" ], [ "<b>Absent</b>", "list.not_in_view()", "", "list.add_post(<b>Absent</b>,blog)" ],
                   [ "Old", "list.not_in_view()", "", "list.add_retired_post(Old,<i>gone</i>)" ] ], result["rows"],
      "the type's label in lower case, and for a retired type its stored name in lower case in its own sentence: never a bare 'post'"
    assert_equal [ [ "select", "post-1" ], [ "add", "post-2" ], [ "add", "post-3" ], [ "unlisted", true ] ], result["calls"]
    assert_equal [ [ "/posts?type=blog", "Open in Posts" ], 0, true, "list.unlisted()" ], result.values_at("link", "markup", "checked", "label")
  end

  # Design answer G5: the error line is in the list, with a small button.
  test "list: a failed read says so in the list with Try again, and pressing it asks again" do
    result = js_module("mind_graph/node_list", <<~JS)
      (() => {
        const { container, list } = #{LIST_SCRIPT}
        document.body.append(container)
        let asked = 0
        list.fail("The list couldn't be loaded.", { label: "Try again", onRetry: () => { asked += 1 }, focus: true })
        const button = container.querySelector("[role=alert] button[data-mind-graph-retry]")
        const said = [ container.querySelector("[role=alert] p").textContent, button.textContent, button.type, button.className, document.activeElement === button, container.querySelectorAll("button[data-node-id]").length ]
        button.click()
        button.click()
        const checkbox = Boolean(container.querySelector("input[type=checkbox]"))
        list.render([ { id: "tag-1", kind: "tag", title: "tag", degree: 2 } ])
        list.focus()
        const focused = document.activeElement?.dataset.nodeId
        container.remove()
        return { said, asked, checkbox, focused }
      })()
    JS

    assert_equal [ "The list couldn't be loaded.", "Try again", "button", "retry", true, 0 ], result["said"]
    assert_equal [ 2, true, "tag-1" ], result.values_at("asked", "checkbox", "focused"), "the checkbox above the rows is still there, and the focus goes to the first row once there is one"
  end
```

  Run: `bin/rails tailwindcss:build && PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/mind_graph_modules_test.rb && PGGSSENCMODE=disable bin/rails test test/lib test/integration/admin/mind_graph_test.rb`
  Expected: PASS.

- [ ] **Step 9: the browser tests.** In `test/system/admin/mind_graph_test.rb`, the existing search tests change where a row ended with its kind's word: a row's text is its label (and a page's path), and the kind is the heading of its group (`[data-mind-graph-results] [data-search-group=tag] a`, text the tag's name). `"search lists tags too, says when nothing matches, and Escape closes the list"` reads `"No page, post or tag matches."`. New:

```ruby
  test "search finds a page, groups its rows under Pages, Posts and Tags, shows a page's path, and opens the page's neighbourhood" do
    docs = create_page(title: "Ruby docs")
    create_post(title: "Ruby notes", tags: [ "ruby" ])
    create_post(title: "Other", tags: [ "ruby" ])
    visit admin_mind_graph_path
    await_graph

    fill_in "Find a page, post or tag", with: "ruby"

    within("#{GRAPH} [data-mind-graph-results]") do
      assert_equal %w[PAGES POSTS TAGS], all("[data-search-group] > p").map { |heading| heading.text.upcase }
      assert_selector "[data-search-group=page] a", text: "Ruby docs"
      assert_selector "[data-search-group=page] a span.font-cs-mono", text: PublicPath.current.where(record: docs).pick(:path)
      assert_selector "[data-search-group=post] a", text: "Ruby notes"
      assert_selector "[data-search-group=tag] a", text: "ruby"
      assert_selector "a > span[aria-hidden='true']", count: 3
    end
    click_frame_link { find("#{GRAPH} [data-search-group=page] a").click }

    assert_current_path admin_mind_graph_path(page: docs.id)
    assert_selector "[data-mind-graph-focus]", text: "Around the page “Ruby docs”"
    await_graph
    assert_equal nid(docs), graph["data-labelled"].split(",").first, "the focus is labelled first"
  end

  test "Not listed on any page shows the posts no page lists in place of the groups, and a row that is not in view adds its post once" do
    blog = create_page(title: "Blog")
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    listed = create_post(title: "Listed")
    PostRelation.create!(post: listed, related_post: create_post(title: "Also listed"))
    drawn = create_post(title: "Entry drawn", content_type: "resume_entry")
    PostRelation.create!(post: drawn, related_post: listed)
    alone = create_post(title: "Entry alone", content_type: "resume_entry")
    visit admin_mind_graph_path
    await_graph
    assert_nil screen_position(alone.id), "a post with no connection is not drawn"
    before = [ graph["data-nodes"], graph["data-edges"] ]

    find("#{LIST} label", text: "Not listed on any page").click

    within(LIST) do
      assert_equal [ "POSTS · 2" ], all("h2").map { |heading| heading.text.upcase }
      assert_selector "button[data-node-id='#{nid(drawn)}']:not([data-not-in-view])", text: "Entry drawn"
      assert_selector "button[data-node-id='#{nid(alone)}'][data-not-in-view]", text: /Entry alone\s*not in view/
      assert_row "Entry alone, #{ContentTypes.fetch("resume_entry").label.downcase} post, not in view. Activate to add it to the graph."
      assert_no_selector "button", text: "Listed"
    end
    assert_equal before, [ graph["data-nodes"], graph["data-edges"] ], "the canvas is left as it is"

    find("#{LIST} button[data-node-id='#{nid(alone)}']").click
    assert_selector "#{GRAPH}[data-selected='#{nid(alone)}'][data-nodes='#{before.first.to_i + 1}']"
    assert_selector "[data-mind-graph-card] h2", text: "Entry alone"
    assert_selector "#{LIST} button[data-node-id='#{nid(alone)}']:not([data-not-in-view])"
    await_graph
    assert screen_position(alone.id)

    find("#{LIST} button[data-node-id='#{nid(alone)}']").click
    assert_selector "#{GRAPH}[data-nodes='#{before.first.to_i + 1}']", wait: 2
    assert_equal "Posts #{before.first.to_i - 3 + 1}", legend_counts[1], "the count of posts follows what the graph holds"

    find("#{LIST} label", text: "Not listed on any page").click
    within(LIST) do
      assert_equal [ "PAGES · 2", "POSTS · 4", "POST TYPES · 1" ], all("h2").map { |heading| heading.text.upcase }
      assert_row "#{ContentTypes.fetch("blog").label}: post type, 2 posts. Shows it in the graph."
      assert_selector "button[data-node-id='type-blog'] span.mg-hub[aria-hidden='true']"
      assert_equal "2", find("button[data-node-id='type-blog']").all("span").last.text, "the number of posts of the type, where a tag's row has its connections"
    end
    # The fourth group is the keyboard's way to a post type's node: its row
    # selects it, as any row does.
    find("#{LIST} button[data-node-id='type-blog']").click
    assert_selector "#{GRAPH}[data-selected='type-blog']"
    assert_selector "[data-mind-graph-card] h2", text: ContentTypes.fetch("blog").label
  end

  # Design answer G5: a read that fails says so in the list, not in a toast,
  # with a small "Try again" button. The stub answers the first request for
  # the unlisted posts itself and hands every other request to the real fetch.
  test "a failed read of the unlisted posts says so in the list, and Try again loads them" do
    create_page(title: "Blog")
    alone = create_post(title: "Alone")
    visit admin_mind_graph_path
    await_graph
    page.execute_script(<<~JS)
      const original = window.fetch
      window.unlistedFailures = 1
      window.fetch = (url, options) => {
        if (!String(url).includes("/mind_graph/unlisted") || window.unlistedFailures <= 0) return original(url, options)
        window.unlistedFailures -= 1
        return Promise.resolve(new Response("", { status: 500 }))
      }
    JS

    find("#{LIST} label", text: "Not listed on any page").click

    within(LIST) do
      assert_selector "[role=alert] p", text: "The list couldn't be loaded."
      assert_no_selector "button[data-node-id]"
      assert_selector "input[data-mind-graph-unlisted]:checked", visible: :all
      press "Try again"
      assert_selector "button[data-node-id='#{nid(alone)}'][data-not-in-view]", text: "Alone"
      assert_no_selector "[role=alert]"
    end
    await_js("document.activeElement?.dataset.nodeId === #{nid(alone).to_json}")
    assert_equal "ready", graph["data-state"], "the graph itself is untouched by the list's failed read"
  end

  test "the list's Pages group is the tree, a page's title and path with markup in them are text in the list, the search and the card" do
    docs = create_page(title: "<b>Docs</b>")
    create_page(title: "Guide", parent: docs)
    visit admin_mind_graph_path
    await_graph

    within(LIST) do
      assert_equal [ "PAGES · 3" ], all("h2").map { |heading| heading.text.upcase }
      assert_equal [ "Home", "<b>Docs</b>", "Guide" ], all("li button span.truncate").map(&:text)
      assert_no_selector "b"
    end
    click_node(nid(docs))
    assert_selector "[data-mind-graph-card] h2", text: "<b>Docs</b>"
    assert_no_selector "[data-mind-graph-card] b"
    fill_in "Find a page, post or tag", with: "docs"
    assert_selector "#{GRAPH} [data-search-group=page] a", text: "<b>Docs</b>"
    assert_no_selector "#{GRAPH} [data-mind-graph-results] b"
  end
```

  (In the second test the graph holds two pages, three drawn posts, the type node and no tag: `before.first` is 6, and the fourth post makes "Posts 4". Write the two figures as literals once the first run has shown them; the arithmetic above is how they are checked. A row of "Not listed on any page" has no hub, so the added post gets no line.) In `"the list beside the canvas holds every drawn node …"` and the tests that count `#{LIST} li`, nothing changes where the test's graph holds no page: the checkbox is a `label`, not a row, and without a page there is no post type's node and so no fourth group; in `"the Tab key meets the search first and the list last"` the checkbox is inside the list and is classified with it.

  Run: `bin/rails tailwindcss:build && sysctl -n vm.loadavg`, then `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/mind_graph_test.rb`
  Expected: PASS.

- [ ] **Step 10: look at it, report, commit.** Screenshots of the open search with all three groups, of the list with its four groups, of the list with rows that are not in view, and of the error line with "Try again" (stop the server while "Not listed on any page" is switched on), both themes; with a screen reader or the inspector's accessibility tree, the name of a row that is not in view. The readings, the two strings nobody gave and the one point of H7 that is still open, all named at the head of this task, go to the controller. Then:

```bash
git add app/queries/post_graph/search.rb app/views/admin/mind_graph/show.html.erb config/locales/admin/mind_graph.en.yml app/javascript/mind_graph test/queries/post_graph/search_test.rb test/integration test/system/admin
git commit -m "feat: the mind graph's search finds pages, and its list has four groups, the posts no page lists and rows that are not in view"
```

---

### Task 8: a page's card, a post type's card, "+N more", and the graph that opens around Home

**The status chip on a card is the design answer's** (G4, H6): it keeps its three dots and adds the second state after the label, and its words are the status key's, one set: "Live, unpublished changes" and "Live, change scheduled 14 Oct" (the date only here). To the eye it is G4's row, "● Live · unpublished changes" with no second dot and "● Live · ● change scheduled 14 Oct" with a warn dot before the second part; a screen reader is given H6's sentence whole. The date is the data's `change_on` (Task 3: the controller's, in CS Studio's short date format). **To report**: G4 writes the chip with "·" and dots, H6 with a comma; this builds both, the one for the eye and the other for the ear, and the second part in lower case as H6 writes it.

**A pill per target** (design answer H1): a page with two list blocks has two "+N more" pills, each on its own hub or tag, and a press on one opens the list with ITS posts (`listed?page=…&target=…`).

**"Show everything" is not remembered after a reload** (the third answers, "Large site notice"): once the whole graph is drawn the script takes `everything=1` out of the address, so a reload asks again and opens around Home.

**Design readings to report** (screenshots, both themes): a page's card in the order path and status, title, counts, notes, actions; the chip's separator, a "·" hidden from a screen reader as the card's counts have theirs, and its `data-status`, the state's name; a post type's card (the type's dot and name, the title, "N posts", Pin; no link) and a retired type's (its title ends "(retired)"); what a press on "+N more" does (no card: it opens the list); a row added from that list joined to its hub and not to the page; the place of "Show everything" in the focus bar (where "Whole graph" stands) and of the notice; that Back to a graph that showed everything shows everything again, while a reload does not.

**Files:**
- Modify: `app/controllers/admin/mind_graph_controller.rb`, `app/views/admin/mind_graph/show.html.erb`, `config/locales/admin/mind_graph.en.yml`, `app/javascript/mind_graph/card.js`, `card_notes.js`, `app.js`, `app/javascript/controllers/admin/mind_graph/graph_controller.js` (its comment)
- Test: `test/integration/admin/mind_graph_test.rb`, `test/integration/admin/mind_graph_data_test.rb`, `test/system/admin/mind_graph_test.rb`

**Interfaces:**
- Consumes: `GET mind_graph/listed` and `PostGraph::Global`'s `open` answer (Tasks 3, 4); `showRowsFrom`, `showGroups`, `reveal` (Task 7); `recordId`, `fill`, `PAGE_MARK`.
- Produces: on the controller's element `data-page-focus-url`, `data-page-notes-url`, `data-listed-url` (with `__ID__` and `__TARGET__`), `data-open-url` (with `__ID__`, and `__LINES__`), `data-opened-lines` (a number, only when the address's `lines=` is one); in the address `lines=<n>`, and `everything=1` only until the whole graph is drawn.

```js
cardNotes(node, { text, type, url, recordUrl, onChange })   // type: "post" | "page"; `recordUrl` was `postUrl`
createCard(container, { …, urls })                           // urls gains pageFocus, pageNotes
```

- [ ] **Step 1: the failing integration tests.** In `test/integration/admin/mind_graph_test.rb`:

```ruby
  test "the page's templates ride on the element, built by the route helpers" do
    sign_in_as(users(:one))
    create_page(title: "About")

    get "/cs-studio/mind_graph"
    element = css_select("[data-controller='admin--mind-graph--graph']").first

    assert_equal "/cs-studio/mind_graph?page=__ID__", element["data-page-focus-url"]
    assert_equal "/cs-studio/notes/page/__ID__/threads", element["data-page-notes-url"]
    assert_equal "/cs-studio/mind_graph/listed?page=__ID__&target=__TARGET__", element["data-listed-url"]
    assert_equal "/cs-studio/mind_graph?lines=__LINES__&page=__ID__", element["data-open-url"]
    assert_equal "/cs-studio/mind_graph", element["data-path"], "the screen's own path: the script takes everything=1 out of the address only while the address is this screen's"
    assert_nil element["data-opened-lines"]
  end

  test "lines= is read as a decimal number and nothing else, and is never written into the page as it came" do
    sign_in_as(users(:one))
    page = create_page(title: "About")

    get "/cs-studio/mind_graph", params: { page: page.id, lines: "3412" }
    assert_equal "3412", css_select("[data-controller='admin--mind-graph--graph']").first["data-opened-lines"]
    assert_select "[data-mind-graph-focus] a[href='/cs-studio/mind_graph?everything=1']", text: "Show everything"
    assert_select "[data-mind-graph-focus] a", text: "Whole graph", count: 0

    [ "<script>x</script>", "0x10", "-5", "0", "12abc", "9" * 40 ].each do |junk|
      get "/cs-studio/mind_graph", params: { page: page.id, lines: junk }
      assert_response :success
      assert_nil css_select("[data-controller='admin--mind-graph--graph']").first["data-opened-lines"], junk
      assert_not_includes response.body, "x</script>"
      assert_select "[data-mind-graph-focus] a", text: "Whole graph"
    end
    get "/cs-studio/mind_graph", params: { page: page.id, lines: [ "1" ] }
    assert_response :success

    get "/cs-studio/mind_graph", params: { lines: "3412" }
    assert_nil css_select("[data-controller='admin--mind-graph--graph']").first["data-opened-lines"], "without a focus there is nothing that was opened"
  end

  test "everything=1 rides in the data url, and only as 1" do
    sign_in_as(users(:one))
    create_page(title: "About")

    get "/cs-studio/mind_graph", params: { everything: "1" }
    assert_includes css_select("[data-controller='admin--mind-graph--graph']").first["data-url"], "everything=1"
    get "/cs-studio/mind_graph", params: { everything: "yes" }
    assert_not_includes css_select("[data-controller='admin--mind-graph--graph']").first["data-url"], "everything"
  end
```

  and in `test/integration/admin/mind_graph_data_test.rb`:

```ruby
  test "a site above the threshold is answered with where to open, and with everything=1 with the whole graph" do
    sign_in_as(users(:one))
    home = root_page
    3.times { |index| create_page(title: "Page #{index}") }

    with_singleton_override(PostGraph::Global, :call, ->(**options) { PostGraph::Global.new(**options, open_above: 2).call }) do
      get "/cs-studio/mind_graph/data"
      assert_equal({ "open" => "page-#{home.id}", "edges" => 3 }, data)

      get "/cs-studio/mind_graph/data", params: { everything: "1" }
      assert_equal 4, data["pages"].size
      assert_nil data["open"]

      get "/cs-studio/mind_graph/data", params: { page: home.id }
      assert_equal "page", data.dig("focus", "kind"), "a local view is never redirected"
    end
  end
```

  Run both files; expected FAIL: no such attributes, and `data` answers the whole graph.

- [ ] **Step 2: the controller and the frame.** In `Admin::MindGraphController`:

```ruby
    def show
      @focus = focus
      @depth = params[:depth].to_s == "2" ? 2 : 1
      @content_types = AccessControl.scope(Current.actor, "posts.read", Post.all).distinct.pluck(:content_type)
      @type_labels = @content_types.filter_map { |name| (definition = ContentTypes.find(name)) && [ name, definition.label ] }.to_h
      @pages = AccessControl.scope(Current.actor, "pages.read", Page.all).exists?
      @everything = everything?
      @opened_lines = opened_lines if @focus
    end
```

  in `data`, the global call (the comment of Task 3 goes):

```ruby
          PostGraph::Global.call(actor: Current.actor, locale: admin_locale, url_for: editor_url, everything: everything?)
```

  and privately:

```ruby
    def everything? = params[:everything].to_s == "1"

    # How many lines the site had when the screen opened around Home instead
    # (pages spec, decision 6): the script puts the figure of the `open`
    # answer into the address, so the notice survives a reload and Back. It
    # is a number or it is nothing: what came in the address is never
    # written into the page, and a figure nobody could have been sent is
    # none either.
    def opened_lines
      lines = Integer(params[:lines].to_s, 10, exception: false)
      lines if lines&.between?(PostGraph::OPEN_AROUND_HOME_ABOVE + 1, 10_000_000)
    end
```

  (The integration test's `lines: "3412"` is above 3,000 and inside the bound.) In `show.html.erb`, on the controller's element: the data URL gains `everything: ("1" if @everything)`, and beside the other templates

```erb
       data-page-focus-url="<%= admin_mind_graph_path(**admin_url_options, page: "__ID__") %>"
       data-page-notes-url="<%= admin_record_note_threads_data_path("page", 0, **admin_url_options).sub("/0/", "/__ID__/") %>"
       data-listed-url="<%= listed_admin_mind_graph_path(**admin_url_options, page: "__ID__", target: "__TARGET__") %>"
       data-open-url="<%= admin_mind_graph_path(**admin_url_options, page: "__ID__", lines: "__LINES__") %>"
       data-path="<%= admin_mind_graph_path %>"
       <% if @opened_lines %>data-opened-lines="<%= @opened_lines %>"<% end %>
```

  and in the focus bar the way back is "Show everything" when the view was opened by the rule (the whole graph would only open around Home again):

```erb
          <% if @opened_lines %>
            <%= link_to t(".focus.everything"), admin_mind_graph_path(**admin_url_options, everything: 1), class: "text-accent underline" %>
          <% else %>
            <%= link_to t(".focus.whole"), admin_mind_graph_path(**admin_url_options), class: "text-accent underline" %>
          <% end %>
```

  Extend the comment above the element (the four new templates; `data-opened-lines`; `data-path`, the screen's own path with no parameter, by which the script knows the address is this screen's before it takes `everything=1` out of it).

- [ ] **Step 3: the strings.** In `config/locales/admin/mind_graph.en.yml`: under `show.focus`, `everything: "Show everything"`; under `script`:

```yaml
        opened: "This site has %{figure} connections, so the graph opens around Home."
```

  and under `script.card`:

```yaml
          open_page: "Open page"
          child_pages:
            one: "%{count} child page"
            other: "%{count} child pages"
          lists_posts:
            one: "lists %{count} post"
            other: "lists %{count} posts"
          status:
            draft: "Draft"
            scheduled: "Scheduled"
            live: "Live"
            unpublished_changes: "unpublished changes"
            change_scheduled: "change scheduled %{date}"
            live_with_changes: "Live, unpublished changes"
            live_change_scheduled: "Live, change scheduled %{date}"
```

  (`status.draft`, `scheduled` and `live` are there today: the chip's first part, with its dot. `unpublished_changes` and `change_scheduled` are its SECOND part as the eye reads it after the "·", G4; `live_with_changes` and `live_change_scheduled` are the whole chip as a screen reader is given it, H6's words, the status key's with the day added. "All posts"'s card line, "N posts", is `card.tag_posts`, which has both forms already.) Add to `messages_data(...)`: `"mind_graph.script.opened"`, `"mind_graph.script.card.open_page"`, `"mind_graph.script.card.child_pages"`, `"mind_graph.script.card.lists_posts"`, `"mind_graph.script.card.status.unpublished_changes"`, `"mind_graph.script.card.status.change_scheduled"`, `"mind_graph.script.card.status.live_with_changes"`, `"mind_graph.script.card.status.live_change_scheduled"`; and to the key list of `"the script's messages ride on the element"`. Bring the locale file's header comment up to date (`script.opened`: `%{figure}` is the grouped count; `script.card.status.change_scheduled`: `%{date}` is the node's `change_on`, a day the server has already written in the short date format, so the script formats no date).

  Run the two integration files; expected PASS.

- [ ] **Step 4: the cards.** In `app/javascript/mind_graph/card_notes.js`: the signature is `cardNotes(node, { text, type, url, recordUrl, onChange })`; `section.dataset.notesType = type`; the draft's key is ``graph-${type === "page" ? "Page" : "Post"}-${recordId(node.id)}`` (a post's key is the one it had); every `postUrl` is `recordUrl`; the header's first line says "A post's or a page's open notes". In `card.js`, the header gains the page's and the type's card, and:

```js
const STATUS_DOTS = { draft: "bg-meta", scheduled: "bg-warn", live: "bg-ok" }
// Which of the five states a node is in (pages spec §4): the chip's
// `data-status`, and what its second part says.
const stateOf = (node) => (node.status === "live" && node.changes ? (node.changes === "scheduled" ? "live_change_scheduled" : "live_with_changes") : node.status)
```

```js
  // The status chip (design answers G4 and H6): `Admin::Ui::StatusChipComponent`'s,
  // class for class, with its three dots, and for a live record that has
  // more to say the second state after the label:
  //   "● Live · unpublished changes"          no second dot
  //   "● Live · ● change scheduled 14 Oct"    a warn dot: warn means "scheduled"
  // Those two rows are for the eye and hidden from a screen reader, which is
  // given the status key's own words in one sentence (H6: one set of
  // words): "Live, unpublished changes", "Live, change scheduled 14 Oct".
  // The day is the server's (`change_on`, CS Studio's short date).
  function statusChip(node) {
    const chip = element("span", "admin-status-chip inline-flex shrink-0 items-center gap-1.5 rounded-cs border border-line-strong px-2 py-0.5 text-xs text-ink")
    const state = stateOf(node)
    chip.dataset.status = state
    chip.append(mark(`h-1.5 w-1.5 rounded-full ${STATUS_DOTS[node.status]}`))
    if (state === node.status) {
      chip.append(text.t(`mind_graph.script.card.status.${node.status}`))
      return chip
    }

    const date = node.change_on ?? ""
    const seen = element("span", "inline-flex items-center gap-1.5")
    seen.setAttribute("aria-hidden", "true")
    seen.append(text.t("mind_graph.script.card.status.live"), element("span", "text-meta", "·"))
    if (node.changes === "scheduled") seen.append(mark(`h-1.5 w-1.5 rounded-full ${STATUS_DOTS.scheduled}`), text.t("mind_graph.script.card.status.change_scheduled", { date }))
    else seen.append(text.t("mind_graph.script.card.status.unpublished_changes"))
    chip.append(seen, element("span", "sr-only", text.t(`mind_graph.script.card.status.${state}`, { date })))
    return chip
  }
```

  (`post` calls `statusChip(node)` where it called `statusChip(node.status)`, and passes `type: "post"` and `recordUrl: node.url` to `cardNotes`.) `openLink` takes the label's key: `const openLink = (node, key = "mind_graph.script.card.open_post") => { … text.t(key) … }`. The two new cards, and `plain` of Task 5 goes:

```js
  // A page (pages spec §7): its address and its state, its title, "4 child
  // pages · lists 112 posts", its open notes as on a post's card, then "Open
  // page", "Focus" and Pin. Enter on a selected page opens it, as a post's.
  function page(node) {
    const counts = element("p", "m-0 flex flex-wrap gap-x-1.5")
    const separator = label("·")
    separator.setAttribute("aria-hidden", "true")
    counts.append(
      label(text.t("mind_graph.script.card.child_pages", { count: node.child_count ?? 0 })), separator,
      label(text.t("mind_graph.script.card.lists_posts", { count: node.listed_count ?? 0 }))
    )
    return [
      heading(mark(PAGE_MARK), element("span", "min-w-0 truncate font-cs-mono text-label text-meta", node.path || ""), ...(Object.hasOwn(STATUS_DOTS, node.status) ? [ statusChip(node) ] : [])),
      title(node),
      counts,
      cardNotes(node, { text, type: "page", url: fill(urls.pageNotes, "__ID__", recordId(node.id)), recordUrl: node.url, onChange }),
      actions(
        openLink(node, "mind_graph.script.card.open_page"),
        link(buttonClasses.secondary, text.t("mind_graph.script.card.focus"), fill(urls.pageFocus, "__ID__", recordId(node.id)))
      )
    ]
  }

  // A post type a page lists, and "All posts": what it is, how many posts
  // the viewer can read of it, and Pin. It leads nowhere: the pages that
  // list it are its neighbours on the canvas.
  function type(node) {
    const counts = element("p", "m-0 flex")
    counts.append(label(text.t("mind_graph.script.card.tag_posts", { count: node.count ?? 0 })))
    return [ heading(hubMark(node)), title(node), counts, actions() ]
  }
```

  and `show` chooses by kind: `container.replaceChildren(...({ tag, post, page, type }[node.kind])(node), closeButton())` (a `more` node never reaches `show`: Step 5). `createCard`'s `urls` gains `pageFocus` and `pageNotes`, which the app reads from `element.dataset.pageFocusUrl` and `element.dataset.pageNotesUrl`. (`PAGE_MARK` and `hubMark` are `card.js`'s own from Task 7; `recordId` is already imported. A retired type's title already ends "(retired)": `nodesOf` wrote it in Task 5.)

- [ ] **Step 5: "+N more", and the graph that opens around Home.** In `app/javascript/mind_graph/app.js`:
  - `import { fill } from "mind_graph/card"` and `import { recordId } from "mind_graph/ids"`.
  - A press on "+N more" opens the list and selects nothing. In `select`, first:

```js
    // "+N more" is not something to select (design answer F4): it opens the
    // list beside the canvas with the posts it stands for, each a row "not
    // in view", and "Open in Posts →" under them. A PILL PER TARGET (H1):
    // the read is asked for this pill's target, and answers its posts only.
    if (index >= 0 && state.nodes[index].kind === "more") {
      list.setUnlisted(false)
      showRowsFrom(fill(fill(element.dataset.listedUrl, "__ID__", recordId(state.nodes[index].page)), "__TARGET__", state.nodes[index].target), { postsLink: true })
      return
    }
```

  - `show` begins with the `open` answer:

```js
  function show(data) {
    // Too many lines for one picture (pages spec, decision 6): the server
    // says where to open instead, and the screen goes there, replacing this
    // visit, so Back does not come back here to be sent on again. The one
    // place this script navigates by itself. The figure rides in the address
    // for the notice of the view it opens.
    if (data.open) {
      const url = fill(fill(element.dataset.openUrl, "__ID__", recordId(data.open)), "__LINES__", data.edges)
      return window.Turbo.visit(url, { action: "replace" })
    }
```

  - and where `say(...)` lists the notice's lines, first among them:

```js
      element.dataset.openedLines ? text.t("mind_graph.script.opened", { figure: number(Number(element.dataset.openedLines)) }) : null,
```

  - "Show everything" is not remembered after a reload. Below `show`:

```js
  // "Show everything" is not remembered after a reload (the third design
  // answers, "Large site notice"): the address that asked for everything
  // loses the parameter once the whole graph is on screen, so a reload asks
  // again and a large site opens around Home. REPLACED, never pushed (Back
  // still leaves the screen), by Turbo's own history with the identifier it
  // has, as the notes drawer does its parameters: a bare `replaceState`
  // would leave Turbo believing in the old address. Written only while the
  // address IS this screen's (`data-path`): "Show everything" is a link
  // into the content frame, whose answer is drawn a moment before Turbo
  // makes the address its own, so this is asked again on `turbo:load`.
  // Nothing is stored; a page Turbo restores still fetches `data-url`, which
  // is the server's and still says everything: Back shows what was shown.
  function forgetEverything() {
    if (destroyed || !state.data || state.data.open || state.data.focus) return
    const url = new URL(window.location.href)
    if (url.pathname !== element.dataset.path || url.searchParams.get("everything") !== "1") return

    url.searchParams.delete("everything")
    const history = window.Turbo?.session?.history
    if (history?.restorationIdentifier) history.replace(url, history.restorationIdentifier)
    else window.history.replaceState(window.history.state, "", url.href)
  }
```

    `show` calls it after `setState("ready")`; `document.addEventListener("turbo:load", forgetEverything)` stands where `mount` adds its other listeners, and `destroy()` removes it with them.

  In `graph_controller.js` nothing is added to `reset()` (the notice is emptied there already, `data-opened-lines` and `data-path` are the server's, and the address is no part of the page); say so in its comment.

- [ ] **Step 6: the browser tests.** In `test/system/admin/mind_graph_test.rb`:

```ruby
  # Pages spec §7: a page's card, in its order, and where its links lead.
  test "a click on a page opens its card: its path and state, its counts, its notes, Open page, Focus and Pin" do
    blog = create_page(title: "Blog")
    create_page(title: "Archive", parent: blog)
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    2.times { |index| create_post(title: "Post #{index}") }
    as(users(:two)) { Notes::Start.call(blog, body: "Check the intro") }
    visit admin_mind_graph_path
    await_graph

    click_node(nid(blog))

    within("[data-mind-graph-card]") do
      assert_selector "span.font-cs-mono", text: PublicPath.current.where(record: blog).pick(:path)
      assert_equal "Live · unpublished changes", find(".admin-status-chip[data-status='live_with_changes'] span[aria-hidden='true'].inline-flex").text.squish
      assert_selector "h2", text: "Blog"
      assert_text(/1 child page\s*·\s*lists 2 posts/i)
      assert_selector "[data-mind-graph-card-notes][data-notes-type=page][data-notes-id='#{blog.id}'] li[data-note-row]", text: "Check the intro"
      assert_equal [ "Open page", "Focus", "Pin" ], all("a, button[data-mind-graph-card-pin]").map(&:text) & [ "Open page", "Focus", "Pin" ]
      assert_link "Focus", href: /mind_graph\?page=#{blog.id}\z/
    end
    assert_selector "#{LIST} button[aria-current='true'][data-node-id='#{nid(blog)}']"

    click_frame_link "Open page"
    assert_current_path admin_page_path(blog)
  end
```

  (The chip reads "Live · unpublished changes" because the block was added to a live page; if the page is plain live in this setup, publish nothing and assert the state the graph's data gives: read `Publishing::State.of(blog.reload).state` in the test and derive the expected words from it, "Live" alone for `:live`.)

```ruby
  # Design answers G4 and H6: the chip keeps its three dots and says the
  # second state after the label; warn means "scheduled", so the second dot
  # is a scheduled change's and unpublished changes have none. A screen
  # reader is given the status key's own words, with the day.
  test "the card's chip says unpublished changes for a live record that has them, and change scheduled with its day behind a warn dot, in the key's words" do
    changed = create_page(title: "Changed")
    pending = create_page(title: "Pending")
    plain = create_page(title: "Plain")
    at = 3.days.from_now
    day = I18n.l(at, format: :"admin.short")
    Publishing::Version.take!(pending, live_at: at)
    [ changed, pending ].each { |record| record.update_columns(unpublished_changes_at: Time.current) } # version: none (a test sets the facts a state is derived from) # changes: none (a test sets the facts a state is derived from)
    visit admin_mind_graph_path
    await_graph
    dots = -> { all("[data-mind-graph-card] .admin-status-chip span.rounded-full").map { |dot| dot[:class][/bg-\w+/] } }
    heard = ->(chip) { chip.find(".sr-only", visible: :all).text(:all).squish }

    click_node(nid(plain))
    assert_equal "Live", find("[data-mind-graph-card] .admin-status-chip[data-status='live']").text.squish
    assert_equal %w[bg-ok], dots.call

    click_node(nid(changed))
    chip = find("[data-mind-graph-card] .admin-status-chip[data-status='live_with_changes']")
    assert_equal "Live · unpublished changes", chip.find("span[aria-hidden='true'].inline-flex").text.squish
    assert_equal "Live, unpublished changes", heard.call(chip)
    assert_equal %w[bg-ok], dots.call, "no second dot"

    click_node(nid(pending))
    chip = find("[data-mind-graph-card] .admin-status-chip[data-status='live_change_scheduled']")
    assert_equal "Live · change scheduled #{day}", chip.find("span[aria-hidden='true'].inline-flex").text.squish
    assert_equal "Live, change scheduled #{day}", heard.call(chip)
    assert_equal %w[bg-ok bg-warn], dots.call, "a warn dot before the second part"
  end
```

```ruby
  test "Enter on a selected page opens it, a post type's card says how many posts it has, and All posts is named" do
    home = root_page
    ContentBlock.create!(owner: home, block_type: :post_list, position: 0, settings: {})
    ContentBlock.create!(owner: create_page(title: "Blog"), block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    create_post(title: "Alpha")
    visit admin_mind_graph_path
    await_graph

    click_node("type-blog")
    within("[data-mind-graph-card]") do
      assert_selector "h2", text: ContentTypes.fetch("blog").label
      assert_text(/1 post/i)
      assert_no_selector "a"
      assert_selector "button[data-mind-graph-card-pin]", text: "Pin"
    end
    click_node("all-posts")
    assert_selector "[data-mind-graph-card] h2", text: "All posts"

    click_node(nid(home))
    assert_selector "[data-mind-graph-card] a", text: "Open page"
    find(CANVAS).execute_script("this.focus()")
    click_frame_link { page.driver.browser.keyboard.type(:Enter) }
    assert_current_path admin_page_path(home)
  end

  # Pages spec §7, design answers F4, F5 and the third answers: around a page
  # at depth 2 the twenty newest posts it lists are drawn, each hanging off
  # the hub that brings it in; the rest stand behind "+N more", which hangs
  # off the same hub and opens the list; a row there adds its post, joined
  # to its hub and not to the page.
  test "around a page, more opens the list with the posts that are not drawn, a row adds its post to its hub, and Open in Posts leads there" do
    blog = create_page(title: "Blog")
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 0, settings: { "content_type" => "resume_entry" })
    posts = 22.times.map { |index| create_post(title: "Entry #{index}", content_type: "resume_entry") }
    posts.each_with_index { |post, index| post.update_columns(published_at: (index + 1).hours.ago) } # version: none (a test sets a time) # changes: none (a test sets a time)
    visit admin_mind_graph_path(page: blog.id, depth: 2)
    await_graph
    assert_selector "[data-mind-graph-focus]", text: "Around the page “Blog”"
    lines = graph["data-edges"].to_i
    assert_equal 23, lines, "the tree line to Home, the lists line to the type, and the hub's faint lines to twenty posts and to more"
    assert_nil screen_position(posts.last.id)
    assert screen_position("more-type-resume_entry"), "the pill is not drawn"
    assert_selector "#{CANVAS}[aria-label='Mind graph around Blog, depth 2: 2 pages, 1 post type and 20 of 22 posts. 2 more are in the list.']"
    assert_not_includes graph["data-labelled"].split(","), "more-type-resume_entry", "the pill carries its words: it has no label beside it"

    click_node("more-type-resume_entry")

    assert_equal "", graph["data-selected"], "more is not selected"
    assert_no_selector "[data-mind-graph-card]", visible: :visible
    within(LIST) do
      assert_equal [ "POSTS · 2" ], all("h2").map { |heading| heading.text.upcase }
      assert_equal [ "Entry 20", "Entry 21" ], all("li button span.truncate").map(&:text)
      assert_selector "button[data-not-in-view]", count: 2
      assert_row "Entry 21, #{ContentTypes.fetch("resume_entry").label.downcase} post, not in view. Activate to add it to the graph."
      assert_selector "a[data-mind-graph-posts-link]", text: "Open in Posts →"
    end

    find("#{LIST} button[data-node-id='#{nid(posts.last)}']").click
    assert_selector "#{GRAPH}[data-selected='#{nid(posts.last)}'][data-edges='#{lines + 1}']"
    assert_equal [ "type-resume_entry" ], graph["data-neighbours"].split(","), "the added post is joined to the hub that brings it in, and not to the page"
    await_graph
    assert screen_position(posts.last.id)

    toggle "Lists"
    assert_selector "#{GRAPH}[data-edges='1']"
    toggle "Lists"

    click_frame_link "Open in Posts →"
    assert_equal({ "type" => "resume_entry" }, Rack::Utils.parse_query(URI(current_url).query).slice("type", "tag"))
  end

  # Design answer H1: ONE PILL PER TARGET. A page with two list blocks has
  # two pills, each on its own hub or tag, each with its own posts.
  test "a page with two list blocks has two pills, and each opens the list with its own posts and its own way to Posts" do
    blog = create_page(title: "Blog")
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 0, settings: { "tag" => "pill" })
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 1, settings: { "content_type" => "resume_entry" })
    pills = 15.times.map { |index| create_post(title: "Pill #{index}", tags: [ "pill" ]) }
    entries = 15.times.map { |index| create_post(title: "Entry #{index}", content_type: "resume_entry") }
    pills.each_with_index { |post, index| post.update_columns(published_at: (2 * index + 1).hours.ago) }   # version: none (a test sets a time) # changes: none (a test sets a time)
    entries.each_with_index { |post, index| post.update_columns(published_at: (2 * index + 2).hours.ago) } # version: none (a test sets a time) # changes: none (a test sets a time)
    tag = "tag-#{Tag.find_by!(name: "pill").id}"
    visit admin_mind_graph_path(page: blog.id, depth: 2)
    await_graph

    # The twenty newest are ten of each; five of each are left out.
    [ "more-#{tag}", "more-type-resume_entry" ].each { |id| assert screen_position(id), "#{id} is not drawn" }
    assert_selector "#{CANVAS}[aria-label='Mind graph around Blog, depth 2: 2 pages, 1 post type, 20 of 30 posts and 1 tag. 10 more are in the list.']"

    click_node("more-type-resume_entry")
    within(LIST) do
      assert_equal [ "POSTS · 5" ], all("h2").map { |heading| heading.text.upcase }
      assert_equal entries.last(5).map(&:title), all("li button span.truncate").map(&:text)
      assert_equal({ "type" => "resume_entry" }, Rack::Utils.parse_query(URI(find("a[data-mind-graph-posts-link]")[:href]).query).slice("type", "tag"))
    end

    click_node("more-#{tag}")
    within(LIST) do
      assert_equal pills.last(5).map(&:title), all("li button span.truncate").map(&:text), "the other pill's posts, and none of the first's"
      assert_equal({ "tag" => "pill" }, Rack::Utils.parse_query(URI(find("a[data-mind-graph-posts-link]")[:href]).query).slice("type", "tag"))
    end
    lines = graph["data-edges"].to_i
    find("#{LIST} button[data-node-id='#{nid(pills.last)}']").click
    assert_selector "#{GRAPH}[data-selected='#{nid(pills.last)}'][data-edges='#{lines + 1}']"
    assert_equal [ tag ], graph["data-neighbours"].split(","), "a post a tag brings in gets its own line to that tag"
    await_graph
  end

  # Design answer H4: the pill grows to fit and its figure has a thousands
  # separator. The data is played by the test (nobody makes two thousand
  # posts for it); every other request goes to the real fetch.
  test "a pill with a figure of four digits is wider than sixty pixels, is pressed anywhere on it, and its figure is grouped" do
    home = root_page
    visit admin_tags_path
    await_admin_controllers
    played = {
      nodes: [], tags: [], edges: [ { source: "page-#{home.id}", target: "type-blog", kind: "lists" }, { source: "type-blog", target: "more-type-blog", kind: "brings" } ],
      pages: [ { id: "page-#{home.id}", title: "Home", path: "/", depth: 0, home: true, parent: nil, order: 0, status: "live", changes: nil, url: "/page", degree: 1, child_count: 0, listed_count: 2000, open_notes: 0 } ],
      types: [ { id: "type-blog", name: "blog", label: "Blog", colour_index: 1, count: 2000, degree: 2 } ],
      more: [ { id: "more-type-blog", count: 1980, page: "page-#{home.id}", target: "type-blog" } ],
      total: 0, shown: 0, site: { pages: 1, posts: 2000, tags: 0 }, focus: { kind: "page", id: home.id, node_id: "page-#{home.id}", title: "Home", depth: 2 }
    }
    page.execute_script(<<~JS, played.to_json)
      const original = window.fetch
      const played = arguments[0]
      window.fetch = (url, options) => {
        if (!String(url).includes("/mind_graph/data")) return original(url, options)
        return Promise.resolve(new Response(played, { headers: { "Content-Type": "application/json" } }))
      }
    JS
    page.execute_script("window.Turbo.visit(#{admin_mind_graph_path(page: home.id, depth: 2).to_json})")
    assert_selector "[data-mind-graph-focus]", text: "Around the page “Home”"
    await_graph

    assert_selector "#{CANVAS}[aria-label='Mind graph around Home, depth 2: 1 page and 1 post type. 1,980 more are in the list.']"
    at = screen_position("more-type-blog")
    hub = screen_position("type-blog")
    # 37 pixels from its centre, on the side away from its hub: on a pill
    # that grew to fit "+1,980 more", and off one of sixty (30 and the
    # slack of 4).
    page.driver.browser.mouse.click(x: at["x"] + (hub["x"] > at["x"] ? -37 : 37), y: at["y"])

    within(LIST) { assert_selector "h2", text: /posts · 0/i }
    assert_equal "", graph["data-selected"], "the press was the pill's: it opened the list and selected nothing"
  end

  # Pages spec, decision 6: a site with more than 3,000 lines opens around
  # Home. The data's answer is played by the test: what the server answers
  # is the query's and the integration test's.
  test "a site with too many lines opens around Home, says why, and Show everything draws the whole graph and is not kept in the address" do
    home = root_page
    create_page(title: "Blog")
    visit admin_tags_path
    await_admin_controllers
    page.execute_script(<<~JS)
      const original = window.fetch
      window.fetch = (url, options) => {
        const address = String(url)
        if (!address.includes("/mind_graph/data") || address.includes("page=") || address.includes("everything=1")) return original(url, options)
        return Promise.resolve(new Response(JSON.stringify({ open: "page-#{home.id}", edges: 3412 }), { headers: { "Content-Type": "application/json" } }))
      }
    JS
    within("nav[aria-label='Modules']") { click_link "Mind graph" }

    assert_selector "[data-mind-graph-focus]", text: "Around the page “Home”"
    assert_current_path admin_mind_graph_path(lines: 3412, page: home.id)
    await_graph
    assert_text "This site has 3,412 connections, so the graph opens around Home."
    assert_selector "[data-mind-graph-focus] a", text: "Show everything"
    assert_no_selector "[data-mind-graph-focus] a", text: "Whole graph"

    page.go_back
    assert_selector "h1", text: "Tags", wait: 5

    page.go_forward
    await_graph
    click_frame_link "Show everything"
    await_graph
    assert_no_selector "[data-mind-graph-focus]"
    assert_equal "2", graph["data-nodes"]
    # Not remembered after a reload (the third design answers): once the whole
    # graph is drawn the address is the screen's own, so a reload asks the
    # server again, which answers a large site with where to open. The page
    # itself still knows what it shows: `data-url` is the server's.
    assert_current_path admin_mind_graph_path
    assert_includes graph["data-url"], "everything=1"

    page.go_back
    assert_selector "[data-mind-graph-focus]", text: "Around the page “Home”", wait: 5
    assert_current_path admin_mind_graph_path(lines: 3412, page: home.id), "the address was replaced, not pushed: Back leaves the whole graph in one step"
  end
```

  (The stub hands every other request to the real `fetch`, as CLAUDE.md asks; it is installed on a screen visited before the graph because the window outlives a Turbo visit, like `stub_graph_data`.)

  Update `"the card reads top to bottom: kind and status, the title, the two counts, its notes, then its actions as buttons"` and `"a draft's card says Draft"` only where they read `data-status` (it holds the state's name now: `live`, `draft`, …, unchanged for those two; a post's chip follows the same rule as a page's, which the test above reads on pages), and add to `"a post with open notes shows them in its card, …"` nothing: a post's notes key and type are what they were.

  Run: `bin/rails tailwindcss:build && sysctl -n vm.loadavg`, then `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/mind_graph_test.rb test/system/admin/mind_graph_modules_test.rb`, then `PGGSSENCMODE=disable bin/rails test test/integration test/lib test/components test/queries`
  Expected: PASS.

- [ ] **Step 7: look at it, report, commit.** The two cards, the chip in each of its three live forms, and the local view around a page at both depths (the pill, the faint lines), both themes; "Show everything" pressed on a site made to open around Home (`PostGraph::OPEN_AROUND_HOME_ABOVE` lowered in a console for the look only), then a reload; the readings at the head of this task go to the controller. Then:

```bash
git add app/controllers/admin/mind_graph_controller.rb app/views/admin/mind_graph/show.html.erb config/locales/admin/mind_graph.en.yml app/javascript test/integration/admin test/system/admin/mind_graph_test.rb
git commit -m "feat: a page's card and local view in the mind graph, a chip that says the second state, more that opens the list, and a large site that opens around Home"
```

---

### Task 9: the measurement, the whole suite, and the documents

**Files:**
- Create: `script/dev/mind_graph_pages.rb`
- Modify: `docs/reference/cs-studio-shell-and-dashboard.md`, `CLAUDE.md`, `docs/roadmap.md`, `docs/superpowers/specs/2026-10-12-pages-in-the-mind-graph-design.md` ("As built"), `app/queries/post_graph.rb` (the header, if a figure of it changed), and, only if the measurement says so, `app/javascript/mind_graph/layout_worker.js` (`LINKS.tree`)

**Interfaces:**
- Consumes: everything.
- Produces: the measured table in the spec's "As built"; the rules in `CLAUDE.md`; the pull request's "Documentation" list.

- [ ] **Step 1: the measurement's pages.** Create `script/dev/mind_graph_pages.rb`, beside `mind_graph_posts.rb` and run the same way against a throwaway database:

```ruby
# Builds a page tree in DEVELOPMENT for measuring the mind graph with pages
# (pages in the mind graph, spec "Testing": 200 pages and 2,000 posts).
# Through `Pages::Save` and `ContentBlocks::Save`, like the seeds, so the
# closure rows, the addresses and the copies are what a real site holds.
#
#   export DATABASE_URL=postgres://contentspiel:contentspiel@localhost:5433/content_spiel_measure
#   bin/rails db:prepare db:seed
#   bin/rails runner script/dev/mind_graph_posts.rb 2000
#   bin/rails runner script/dev/mind_graph_pages.rb 200
#
# Shape: Home, eight sections under it, every later page under one of the
# first sixty.
# Every third page has a post-list block: by one of the measurement's tags
# ("graph-tag-N", the posts script's), by the "blog" type, or by nothing, in
# turn. Deterministic and safe to run again: a page is found by its title.
abort "development only" unless Rails.env.development?

count = Integer(ARGV.fetch(0, "200"))
locale = Locales.default.to_s
home = Page.find_by(parent_id: nil) || Pages::Save.call(attributes: { published: true }, translations: { locale => { title: "Home", slug: "" } }).record
pages = [ home ]

(1...count).each do |number|
  title = "Graph page #{number}"
  parent = number <= 8 ? home : pages[1 + ((number * 7) % [ pages.size - 1, 60 ].min)]
  page = Page.title_matching(title, locale: locale).find { |found| found.title == title }
  unless page
    result = Pages::Save.call(attributes: { parent: parent, published: number % 9 != 0 }, translations: { locale => { title: title } })
    abort "#{title}: #{result.errors.to_sentence}" unless result.ok?
    page = result.record
    if (number % 3).zero?
      settings = [ { "tag" => "graph-tag-#{number % 60}" }, { "content_type" => "blog" }, {} ][(number / 3) % 3]
      saved = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: settings })
      abort "#{title}: #{saved.errors.to_sentence}" unless saved.ok?
    end
  end
  pages << page
  puts "#{number + 1} / #{count}" if ((number + 1) % 50).zero?
end
```

- [ ] **Step 2: measure**, as the canvas spec's §7 did and with its tools (the server in development against the throwaway database, Chrome headless over the DevTools protocol at 1440 × 900, eleven `curl` requests for the endpoint; that section's "How each was taken" is the method). At 200 pages and 2,000 posts, take:

  | What | How |
  |---|---|
  | The number of lines of the whole graph | `data?everything=1`: `edges.size`, and by kind |
  | Whether the site opens around Home | `data` without it: an `open` answer or a graph |
  | The data endpoint: time, size, statements | `data?everything=1`, and `data?page=<home>&depth=2` |
  | Navigation to settled | `?everything=1`, four loads; and the view around Home |
  | Frames while panning, whole graph in view and at the largest zoom | as §7 |
  | A toggle, until its handler returns | "Posts" off and on |
  | The node under the pointer | the hit test's time at 2,200 nodes |

  Then decide from the numbers, and write each decision down:
  - **More than three seconds to settled** with `everything=1`: saved positions go on the roadmap as "Should" with the figure (they are "Could" there now). Nothing is built.
  - **The site opens around Home at this size** (more than 3,000 lines): that is the spec's named risk. Report it to the controller with the count by kind before the pull request is opened; do not move the threshold.
  - **A late frame at 2,200 nodes** in the hit test or the label rule: report it; a quadtree is spec decision 12's trigger and its own piece of work.
  - **The tree against the tag clusters**: look at the graph. A subtree torn apart or a page dragged into a tag's cluster is a reason to tune `LINKS.tree` (distance between 30 and 60, strength between 0.6 and 1), in steps, with the worker's module test still green; write the values tried and the one kept into "As built".

- [ ] **Step 3: the whole suite.**

  Run: `bin/rubocop && bin/brakeman -q && bin/rails zeitwerk:check && PGGSSENCMODE=disable bin/rails test`
  Expected: no offences, no warnings, "All is good!", PASS.
  Run: `bin/rails tailwindcss:build && sysctl -n vm.loadavg`, then `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test:system`
  Expected: PASS. A run that takes twice its usual time is not a result: run it again on a quiet machine.

- [ ] **Step 4: the reference.** In `docs/reference/cs-studio-shell-and-dashboard.md`, rewrite the Mind graph's part where it is no longer true, paragraph by paragraph, keeping every incident it records. What changes, each a paragraph that exists today:
  - the opening: pages, the two new lines, who may open it (`pages.read` or `posts.read`), and that it shows THE ROWS (decision 3, with the reason);
  - "Two modes, one screen": `?page=`, the order of the three parameters, `everything=1`, `lines=`, the four JSON reads;
  - "The data": the whole shape (copy it from Task 3's "Interfaces"), `PostGraph::Site`, `Tree`, `Listings`, `Builder#plan` and `#build`; a typed id and `PostGraph.node_id`; `status` and `changes` from `Publishing::State` handed its pending time;
  - "The cap": thirteen statements, named; where the count depends on the shape (no page: `Notes::Counts` asks nothing; no named tag: `Tag.named_any` asks nothing); the 3,000-line rule and why the count is taken before any node is built;
  - "The tag rule": a listed tag is a node whatever its count;
  - a new paragraph, "What a page lists": a line is made from the block; the criteria are `BlockTypes::PostList.matches?` and the parity test; "listed" and "unlisted" are true for the viewer;
  - "Search": pages, in tree order, with their path;
  - "The page holds no data": the legend is the filter, the counts are the script's, the new templates, `data-opened-lines`;
  - "The modules and what each owns": `ids.js`, `graph_data.js`, `marks.js`; the worker's `kind`, `anchor`, `held`, `add`;
  - the looks: the five states and that warn means "scheduled" in all of them, a ring type as its mark inside a ring, the hubs (a type's, "All posts", a retired type's), the pill, the corners, the lines' five styles (the Lists line's round dots; a hub's faint `brings` lines, which only a page's local view has), the label order and `free`, and the hit test's boxes;
  - "Selecting, and the card": a page's and a type's card; the chip's second part and where its date comes from (`change_at` from the query, `change_on` from the controller); "+N more";
  - the legend: the toggles, and the status key as a dialog of its own (`StatusKeyComponent`, outside the graph's element, in the chip's words), which the graph's script neither opens nor resets; the canvas's summary and every form of it;
  - the list: four groups, the tree order, the "Post types" group (a row's mark `hubMark`, its number the type's posts, the order the data's), "Not listed on any page", rows not in view and their name, the error line with "Try again";
  - the address: `everything=1` taken out once the whole graph is drawn, by Turbo's history, and why it is asked again on `turbo:load`;
  - "Testing it": `graphPosition`, `marks_drawn`, `lines_drawn`, `toggle`, and that a toggle's effect is read without `await_graph`.
  The file's first line ("Describes: …") gains nothing: the directories are the same.

- [ ] **Step 5: `CLAUDE.md`.** In "Rules a change can break silently", after the Mind graph's rule, add (each with the test that guards it, in the file's own form):

  - The mind graph shows THE ROWS, not the published copies, by decision (CS Studio is the editors' view; a line a live page's unpublished block adds is drawn, and the page's own mark says so), and a node's state is `Publishing::State`'s, handed the pending copies read once for all nodes: nothing under `app/queries/post_graph/` or `app/javascript/mind_graph/` compares `published_at` or reads a copy (`test/lib/mind_graph_guards_test.rb`: "no query and no script of the mind graph compares published_at: a node's state is Publishing::State's", "the mind graph reads the rows: no query of it reads a published copy").
  - Which page lists which post is `BlockTypes::PostList.matches?`, the one criteria function `lists?` and the graph share (`test/queries/post_graph/listings_test.rb`: "the posts a page lists are the listing's own, for every shape of settings"). A lists line is made from the block's settings, never from the posts.
  - The graph's data costs a fixed number of statements, thirteen for the global view, whatever the number of pages and posts (`test/queries/post_graph/global_test.rb`: "the global graph costs thirteen statements", "the statement count is the same for 3 pages and for 30, and for 3 posts and for 30"); a new read of pages or posts for the graph goes into `PostGraph::Site`, not into a loop.
  - "Not listed on any page" and a page's `listed_count` are true for the viewer, not for the site: they are computed from the pages and posts the viewer may read, because saying more would disclose a page (`test/queries/post_graph/rows_test.rb`: "unlisted is true for the viewer: a post only a page they cannot read lists is a row, and a trashed post is none").
  - A node's id is its kind and its database id everywhere (`post-12`), written by `PostGraph.node_id` and taken apart only in `mind_graph/ids.js`.
  - The legend's counts and the toggles' names are the script's and are taken back in `reset()`; the checkboxes' state is the person's and is kept (`test/system/admin/mind_graph_test.rb`: "Back to the graph draws it once, with the filter the control shows"). The status key is a dialog outside the graph's element and not the graph's: `reset()` does not touch it, and its five names are the chip's words (`status_key.states` and `script.card.status` must be changed together).
  - A hub's line to a post (`brings`) exists only in a page's local view; in the whole graph a type node joins only pages, and no lists line joins a page to a post anywhere (`test/queries/post_graph/global_test.rb`: "a type node joins only the pages that list it, never a post of its type"; `test/queries/post_graph/local_test.rb`: "depth 2 around a page draws the twenty newest posts it lists, each joined to the hub that brings it in, and counts the rest behind more"). "+N more" is one pill per target, each counting what its own target brings in ("a page with two list blocks has a pill per target, each on its own hub or tag with its own count, and a target that brings in nothing more has none").
  - A scheduled change's day reaches the card as `change_on`, written by the controller with `I18n.l` and the `admin.short` format from the query's `change_at`; no query and no script formats a date (`test/integration/admin/mind_graph_data_test.rb`: "a scheduled change's day is in the data as CS Studio's short date, and a node without one has no such key").
  - `everything=1` does not stay in the Mind graph's address: the script replaces the address through Turbo's history once the whole graph is drawn, so a reload opens a large site around Home again (`test/system/admin/mind_graph_test.rb`: "a site with too many lines opens around Home, says why, and Show everything draws the whole graph and is not kept in the address"). **No guard** for a link elsewhere that is built with `everything=1` and expected to last.

  And in the existing Mind graph rule, "search, graph, list" stays; add that the legend's toggles are part of the graph's column and come before the zoom buttons. In "Setup & Commands" nothing changes. Run `PGGSSENCMODE=disable bin/rails test test/lib` (the guards read `CLAUDE.md` and `docs/reference`: every identifier and test name written there must exist).

- [ ] **Step 6: the roadmap.** In `docs/roadmap.md`: version 1's item 5 says step one is built (the date, the pull request once it has a number); a row under "Shipped" in the table's own form, naming this spec; the row "Mind graph, pages, step two: links in the text as lines …" stays under "Dashboard and CS Studio"; the row "Mind graph: saved positions …" is "Should" with the measured figure if Step 2 found more than three seconds, and otherwise says "measured on <date> at 200 pages and 2,000 posts: <figure> to rest, not needed".

- [ ] **Step 7: the spec's "As built".** At the end of `docs/superpowers/specs/2026-10-12-pages-in-the-mind-graph-design.md`, a section "As built" (and the status line at the top says "built", with the branch): the measured table of Step 2 and how each figure was taken; every place the build left the text, each with its reason. Those this plan already knows:
  - `changes` in the data is `nil`, `"unpublished"` or `"scheduled"`, not a boolean: with `status` it names the fifth state, which a boolean could not; `Publishing::State.of` takes `pending_at:`.
  - A search row and a post's row carry `record_id` beside the typed `id`; a post's search row carries `colour_index` for its marker.
  - The notice's figure travels in the address as `lines=`, and the focus bar offers "Show everything" in place of "Whole graph" only in the view the rule opened.
  - Over the threshold with no readable Home the whole graph is answered.
  - The five status looks are tested against a recording context, and one of them from the canvas's pixels; the spec's "Testing" asked for all of them from pixels.
  - A local view around a page costs no walk statement; `Local` reads the tag links from the site, so its fixed part is the global view's thirteen.
  - The statement count is thirteen on a site with a page and a list block that names a tag; one or two fewer where there is nothing to ask.
  - A "+N more" pill is one per target; the payload's `more` is a list, a pill's id is `more-<target>`, and `listed` takes `target=`.
  - The status key is CS Studio's modal dialog, where the third answers said "popover" and the fourth "a dialog".
  - The chip is G4's row for the eye and H6's sentence for a screen reader.
  - In a page's local view a post a block lists by TAG has no faint line: its "Shares a tag" line to that tag is the line. A row added from "+N more" gets its hub's line through `via`.
  - The readings this plan made of the design answer (Task 5's second table; Task 6's and Task 7's lists), with what the design system's owner answered to each after looking at the drawing.
  - The wording nobody gave (Task 6: the singular of "more", the three other "… hidden." sentences and the three other "… lines hidden."; Task 7: "Post types · N" and a post type row's name), with what was answered; and the two points still open: a type name "capitalised by design", and what the summary says where a whole graph is cut at the 2,000 posts.
  - The canvas is named "Mind graph" before its data has come, the summary's first words, where the first text of the spec said "Graph of pages, posts and tags".
  - `LINKS.tree` as tuned.

- [ ] **Step 8: commit, and the pull request's "Documentation".**

```bash
git add script/dev/mind_graph_pages.rb docs/reference/cs-studio-shell-and-dashboard.md CLAUDE.md docs/roadmap.md docs/superpowers/specs/2026-10-12-pages-in-the-mind-graph-design.md app
git commit -m "docs: pages in the mind graph — the reference, the rules, the roadmap and the spec as built, with the measurement"
```

  Do not push; the controller opens the pull request. Its body names, under "Documentation", the guide pages this changes, in `contentspiel-docs` (no guide text is kept here):
  - **The Mind graph** (editors): rewritten. Pages and Home at the centre; the two new lines; the five status looks, that the amber dot always means "scheduled", what a draft's dashes mean, and that the key is behind "Status" in the legend; the legend as the filter, and that a line switched off hides only the line; search for pages; the list's four groups (Pages, Posts, Tags, Post types); "Not listed on any page" **and what it means for someone who can read only part of the tree**; a page's card, its chip ("Unpublished changes", "Change scheduled" with its day) and local view; "+N more" and the faint lines from a hub to its posts; a large site opening around Home and "Show everything", which a reload does not keep; the graph shows what is being edited, so a line can be one visitors do not see yet.
  - **Pages** (editors): a pointer to the graph.
  - **The post-list block** (editors): where a post appears, and that the graph shows it.
  - **Groups and permissions** (administrators): the Mind graph opens with read access to pages or to posts.

---

## Self-Review

**1. Spec coverage.**

| Spec | Task |
|---|---|
| "What changes" 1 (post looks), §4 status (warn means "scheduled"), ring types, type hubs, a retired type's hub, the "+N more" pill, the exact readings | 5 |
| "What changes" 2, 3 (legend as controls, a line hides only lines), §6, decision 8; status not a filter and the "Status" key, a dialog; "What changes" 8 and the summary in all its forms | 6 |
| "What changes" 4 (grouped search; the list's four groups), §3 search, §7 search | 7 |
| "What changes" 5 (label colours, mono tags), §4 labels and priority | 5 |
| "What changes" 6 (typed ids; `pages.read` or `posts.read`), decision 4, §2 | 1, 3 |
| "What changes" 7, decision 6 (3,000 lines, "Show everything", not remembered after a reload) | 3 (the answer), 8 (the screen, the address) |
| Decision 3 (rows, not copies) | 2 (the guard), 3 |
| Decision 5 (every readable page, cap 2,000 posts) | 3 |
| Decision 7 (no saved positions; measure) | 9 |
| Decisions 9, 10 (a line from the block; "not listed" its own read), §1 listings, parity | 2, 4 |
| Decision 11 (the module keeps its name) | all: nothing is renamed |
| Decision 12 (no quadtree unless measured) | 9 |
| §1 data: pages, types, edges, `changes`, `change_at`, `listed`, the cost, the cut | 3 |
| §1 a hub's faint lines in a page's local view (`brings`), which hub brings a post in | 2 (`target_of`), 3 (the plan's lines), 4 (the view, `via`), 5 (the look), 6 (the toggle), 7 and 8 (a row added) |
| §2 rights and the trash, `trash_visibility_test` | 3, 4, 7 |
| §3 reads: `page=`, `everything=1`, `unlisted`, `listed` | 4, 8 |
| §4 lines, batches, culling, the 40% rule; tokens | 5 |
| §5 layout: kinds, Home's anchor, no rings by level, the filter | 5 |
| §7 the list and its four groups, rows not in view and their name, the error line, a page's card and its chip, the local view, "+N more", "Open in Posts →" | 4 (data), 7, 8 |
| §8 strings | 4, 5, 6, 7, 8 (each key written out) |
| "Testing": the measurement | 9 |
| "Documentation" | 9 |
| The fourth answers, H1 to H7 (a pill per target; a Post types row; a ring type's hub and the retired hub's dashes; the pill's width and figure; the summary's other forms; the key as a dialog in the chip's words; a retired type's row name) | H1: 2, 3, 4, 5, 6, 8; H2: 3, 7; H3: 5; H4: 5; H5: 6; H6: 6, 8; H7: 7 |
| What is still open (a type name capitalised by design; the summary at the 2,000-post cap) | 7 and 6: built the plain way, reported |

No gap. Three things the spec leaves open and this plan settles, each reported in the task that builds it and written into "As built" (Task 9, Step 7): the form of `changes`; how the notice's figure reaches the view around Home; how `everything=1` leaves the address (Turbo's history, and again on `turbo:load`). The third and fourth design answers closed what was open before: a retired type's hub, the look and the number of the "+N more" pills, a "Post types" row and the status key are the designer's now, and no provisional constant stands for any.

**2. Placeholder scan.** No "TBD", no "similar to Task N", no step that says to write tests without saying which. Where a step changes many lines by one rule (Task 1, Steps 1, 5 and 8; Task 6, Step 8's table) the rule, the command that finds the lines and the lines that are different are all given. Two expected values are derived in the test from the record instead of written as a literal, each with the reason (a page's path; a page's state after a block is added to it).

**3. Type consistency.** `PostGraph.node_id(kind, id)` (Task 1) is the only writer of an id in Ruby, `recordId` the only reader in JavaScript. `Builder#plan` / `#build` / `#post_nodes` (Task 3) are called with the same keywords in `Global` (3), `Local` (3, 4) and `Rows` (4): `brought:` is `[[target, post_id]]` and `more:` is a list of `{ page_id:, target:, count: }` in the builder (3) and in `Local` (4), and nothing passes `listed:` or `from:` any more. A pill's id is `PostGraph.node_id(MORE, target)`, "more-type-blog", in the builder (3), `nodesOf` (5) and every test; the payload's `more` is a list in the builder (3), `nodesOf` (5), `summarise` (6, which adds the pills' counts) and the played payloads (8). `Listings#left_out` and `#left_out_of` (2) are what `Local` and `Rows#listed(page_id, target)` (4) ask, and `data-listed-url` carries `__TARGET__` (8). `Listings#edges` is `[[page_id, target]]` in Tasks 2, 3 and 4, and `Listings#target_of(page_id, post_id)` (2) is what `Local#brought` and `Rows#listed`'s `via` (4) ask. The edge kind is `"brings"` in the builder (3), `LINE_STYLES` (5), `visible`'s `lineToggleOf` (6), `addPost` (7) and the worker's test (7). The payload's keys in Task 3's "Interfaces" are the ones `nodesOf` (5), `visible` and `counts` (6), the list (7) and the cards (8) read: `home`, `depth`, `order`, `parent`, `status`, `changes`, `change_on` (the controller's, from `change_at`), `child_count`, `listed_count`, `count`, `label`, `colour_index`, `page`, `via`. The theme's keys are `dim`, `warn`, `faint`, `line` in `theme.js`, `marks.js`, `renderer.js` and both recording themes of the module tests. `boxOf` (5) is what `radiusFor`, `collisionRadius`, the renderer's ring, the hit test's `boxes` and `addPost` (7) use. The checkboxes are `mind_graph_nodes` and `mind_graph_lines` in the component, the app, `reset()` and the tests; the status key is `#mind-graph-status-key` everywhere. The summary's keys are `mind_graph.script.summary.*` in the locale file, `messages_data` and `summarise` (6). `list.fail(line, { label, onRetry, focus })` and `list.focus()` are the list's (7) and `showRowsFrom`'s (7, 8). `hubMark` is `card.js`'s (7), used by the list (7) and the type's card (8), on the stylesheet's `.mg-hub` (7). `moreWidth` and `boxOf` are `marks.js`'s (5), and the app writes a pill's `width` (5). The key is `Admin::MindGraphScreen::StatusKeyComponent` with `ID` "mind-graph-status-key" in the component, the legend's trigger, the view and the three kinds of test (6); its two long names are the chip's sentences without the day (6, 8). `cardNotes` takes `type` and `recordUrl` from Task 8 on; Tasks 1 to 7 leave its `postUrl`.

**4. Review Focus.** Each of the thirteen lines names its tests, and each test is written in the task that owns the code: 1 in Tasks 2, 3 and 7; 2 in Task 2 (and Task 3 for the retired type's node); 3 in Tasks 3 and 8; 4 in Task 6; 5 in Tasks 7 and 8; 6 in Task 4; 7 in Task 7; 8 in Task 7; 9 in Task 6; 10 in Tasks 3, 4, 6 and 8; 11 in Task 8; 12 in Tasks 2, 4 and 8; 13 in Tasks 5 and 8.
