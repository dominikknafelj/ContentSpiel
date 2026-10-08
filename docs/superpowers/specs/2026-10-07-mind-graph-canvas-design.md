# Mind graph on a canvas

The first sub-project after the technical cleanup (`docs/roadmap.md`, "Mind graph on a canvas", agreed 2026-10-04). The design was agreed with the user on 2026-10-07 in four sections. This is the binding spec for one implementation plan and one PR.

**Status: implemented** (branch `mind-graph-canvas`, plan `docs/superpowers/plans/2026-10-07-mind-graph-canvas.md`). The measured numbers are in §7; where the build departs from this text, §11 says how and why.

## 1. Purpose

CS Studio's Mind graph shows how posts relate through related-post links and shared tags. Before this sub-project it drew every readable post as SVG elements inside a fixed box, computed the layout in the page, and embedded the whole data set in the HTML. That worked for a few dozen posts and broke down well before a serious site's size:

- There was no cap: the screen loaded and simulated every readable post.
- Labels overlapped, because every node was labelled at all times.
- Every node was one size, so a hub looked like a leaf.
- Nodes were clamped to the box, so a large graph was pressed against its edges.
- You couldn't zoom, pan, or look at one post's neighbourhood.
- A post whose type was no longer registered differed from a ring of slots 7–12 by colour alone.
- d3-force was preloaded on every CS Studio page.

**Design target:** a site with low thousands of posts (2,000–5,000). The screen should feel the same at 200 posts and at the cap.

**Success:**
- The graph is drawn on one 2D canvas, zooms and pans, and the first view fits everything.
- Zoom, pan and selection stay responsive while the layout is still settling, at the cap.
- Labels never overlap; hubs are labelled first and the rest arrive with zoom.
- A hub is recognisable by size before any label appears.
- Any post or tag the viewer may read can be reached as a local graph, including one the capped global view doesn't draw.
- Over the cap the screen says what it shows and what it leaves out.
- Everything a pointer can do has a keyboard and screen-reader path.
- No page other than the Mind graph loads d3-force.
- No colour literal appears in the script, and no cue is colour-only.

## 2. Decisions

Agreed on 2026-10-07:

1. **Scale:** built and measured for low thousands of posts. Plain 2D canvas; WebGL is not part of this sub-project.
2. **Local graph:** lives on the Mind graph screen as a focus. An embedded neighbourhood panel in the post editor is a later roadmap item.
3. **Click:** selects a node and opens a card with the actions. A click never navigates by itself.
4. **Over the cap:** the global view draws the best-connected posts and says so. A search field reaches everything else.
5. **Layout:** the force simulation runs in a Web Worker; the page draws and handles input.
6. **Isolated posts** (no related post and no shared tag) are left out of the global view and counted in a message. This changes today's behaviour, where "All" shows them.
7. The graph stays read-only. Relations are edited in the post editor.

## 3. Data and server

### 3.1 Routes

- `GET <admin>/mind_graph` — the screen (the existing path). With no parameters, the global view.
- `GET <admin>/mind_graph?post=<id>&depth=<1|2>` and `?tag=<id>&depth=<1|2>` — a local view. A depth other than 1 or 2 is read as 1. `post` wins if both are given.
- `GET <admin>/mind_graph/data` with the same parameters — the graph's data, as JSON.
- `GET <admin>/mind_graph/search?q=<text>` — posts and tags by name, for the search field.

The screen and both JSON reads need `posts.read` somewhere, as the screen does today. A focus the viewer may not read, a trashed post and an unknown id answer 404, from the page and from the data endpoint alike. An id is read as a decimal number and nothing else: `post=010` is post 10, and `post=0x1A`, a word or a list (`post[]=1`) names nothing and is a 404 (§11).

### 3.2 The data moves out of the page

The page renders only the frame: heading, focus bar, search field, legend, filter, the empty canvas, the card's container and the list's container. The script fetches the data endpoint. The `<script type="application/json">` island is removed.

Reason: at the cap the JSON is several hundred kilobytes, which would otherwise sit in every page load and in Turbo's page cache.

### 3.3 `PostGraph::Global` and `PostGraph::Local`

`PostGraph` becomes a namespace in `app/queries/post_graph/` with two queries and a shared builder for the common parts (node rows, tag derivation, edge rows): `PostGraph::Global`, `PostGraph::Local` and `PostGraph::Builder`. Both queries take `actor:`, `locale:` and `url_for:` as today, with `actor:` and `url_for:` required, and `cap:` (the constant by default). `PostGraph::Local` also takes `focus:` and `depth:`. The focus is a `PostGraph::Focus`, which resolves the request's `post=` / `tag=` for this viewer or raises not found; the search field's query is `PostGraph::Search` (§3.5).

**Shape**, the same for both:

```
{
  nodes: [{ id, title, type, colour_index, status, url, degree }],
  tags:  [{ id: "tag-<id>", name, count, degree }],
  edges: [{ source, target, kind: "related" | "tag" }],
  total: <readable posts with at least one connection>,
  shown: <posts in nodes>,
  isolated: <readable posts with no connection>,   # global only
  focus: { kind: "post" | "tag", id, node_id, title, depth } # local only; node_id is the focus's id among the nodes ("tag-<id>" for a tag)
}
```

- `degree` is the number of edges the node has *in this response*, so size and label priority match what is drawn.
- `url` is the post's editor URL, built by the caller's `url_for:`. A query knows no routes (`test/lib/dependency_direction_test.rb`).
- Posts are loaded with only the columns the node needs: id, the title column, the content type, and the columns `Publishable#status` reads.

**`PostGraph::Global`**
- Ranks the readable posts by connection count: related-post links (either direction) plus tag links to tags that qualify as nodes.
- Keeps the top `PostGraph::CAP` posts with a count above zero. Ties break by newest `updated_at`, then id, so the result is stable between requests.
- Derives tags and edges only from the kept posts.
- A tag's weight in the ranking is decided before the cut, among all readable posts.

**`PostGraph::Local`**
- Starts from the focus and walks outward one level per depth, following both edge kinds, one set of queries per level and never one per node.
- From a post: its related posts and its qualifying tags are depth 1; their posts and tags are depth 2.
- From a tag: its readable posts are depth 1; their related posts and other tags are depth 2.
- Capped at `PostGraph::CAP` posts too. Over the cap it keeps the focus, then nearer posts before farther ones, and among equals the better connected; `total` / `shown` say so.

**The cap** is one constant, `PostGraph::CAP`, starting at 2,000 and set from the measurements in §7.

### 3.4 Rules that do not change

- Tags are derived only from readable posts, and a tag's `count` is the number of *readable* posts carrying it — never the tag's true total, and not the smaller number drawn, which would understate it.
- No edge points at a post that isn't in `nodes`.
- A tag is a node only when at least two readable posts carry it (`MIN_TAGGED_POSTS`) and it has enough edges in this response to say something: two in the global view, one in a local view (where a post's own tags are its depth-1 neighbours). One exception: the focused tag of a local view is always a node.
- A focused tag that no readable post carries is not found.
- Trashed posts are hidden explicitly, and the data and search endpoints are added to `test/integration/trash_visibility_test.rb`.
- The cost does not grow with the number of posts: a fixed number of queries for the global view (five), and a fixed number per depth level for the local one (three per level, plus five).

### 3.5 Search

The search endpoint returns up to ten posts and ten tags whose name matches, through the existing scopes (`title_matching_any_locale`, `Tag.name_containing`), posts through `AccessControl.scope`. A tag is listed only if at least one readable post carries it. Each row carries a label, a kind, an id and the URL of its local view (the query answers the first three; the controller adds the URL, since a query knows no routes). Posts come in id order, loaded with their id and title only; tags whose name starts with the text come before those that only contain it.

## 4. The script

### 4.1 Modules

The 385-line `admin/mind_graph_controller.js` becomes a thin Stimulus controller over modules in `app/javascript/mind_graph/`. The controller only imports `mind_graph/app` when the screen is on the page, mounts it, destroys it on `disconnect()`, and takes back the state a Turbo page snapshot carries; `app.js` wires the others together.

| Module | Does | Knows about |
|---|---|---|
| `layout_worker.js` | Runs d3-force and posts positions back | d3-force |
| `layout_client.js` | Starts the worker, sends commands, hands positions to the page | the worker's messages |
| `camera.js` | Zoom, pan, fit-to-view, screen ↔ graph coordinates | numbers |
| `renderer.js` | Draws edges, nodes, labels and the selection onto the canvas | camera, theme, positions |
| `hit_test.js` | Finds the node under a point | positions |
| `labels.js` | Decides which labels are shown at this zoom | degree, camera, positions |
| `theme.js` | Reads the colour tokens from CSS custom properties | the document |
| `input.js` | Turns the canvas's pointer, wheel and key events into callbacks: press, drag, drop, pan, click, zoom, hover, Escape | the canvas element |
| `card.js` | The selection card | the server's URL templates, the messages |
| `node_list.js` | The list of links below the box | the same |
| `search_box.js` | The search field's results | `search/suggestions.js`, the messages |
| `app.js` | Wires the above: the data request, the worker, the state, the redraw loop, the filter, the notice, the tooltip, and the state said on the element | all of them |

`app.js` owns the HTML around the canvas through those modules: the filter, the search field, the card and the list.

### 4.2 The worker

- A module worker, served through the asset pipeline with a digest URL. It imports the vendored `d3-force.js` by its asset URL, because an import map does not apply inside a worker. The file is one self-contained bundle, so that import needs nothing else.
- Page to worker: `start` (the d3-force URL, nodes as `{ id, radius }`, edges as `{ source, target }`), `filter` (the visible node ids and the indexes of the visible edges), `pin` (id, x, y) / `unpin` (id) for dragging a node. There is no `stop` message: the page terminates the worker.
- Worker to page: `tick` with one `Float32Array` of x/y pairs for every node given to `start`, transferred and not copied; `settled` with `after`, the number of messages the worker had taken up when the layout cooled down (§11); `error`.
- The worker runs as many simulation ticks as fit into 12 ms, sends one message, and yields before the next slice, so a `pin` or `filter` that arrived meanwhile is handled first.
- The worker handles its messages strictly in order (§11).
- An error inside the worker is forwarded to the page and reported with `console.error`, so the system tests' JavaScript-error rule sees it.
- The worker is terminated on `disconnect()`.

There is no second code path that runs the simulation in the page. If the worker can't start, the box shows a message and the list of links (§5.7) still works.

`hit_test.js` is a linear scan over the visible nodes: at the cap that is 2,000 distance checks per pointer event, which needs no index.

### 4.3 Drawing

- One redraw per animation frame, and only when something changed: positions, the camera, the selection, the filter, the theme.
- Order: edges, nodes, labels, selection and focus rings.
- Edges are batched into one path per kind (related solid, tag dashed) and strength: with a selection, the edges that do not touch it are a second, faded path.
- What is outside the canvas is not drawn: a node whose mark lies wholly outside, and an edge that can't cross the canvas because both its ends are beyond the same side (§7, §11).
- Nothing is drawn before the worker's first positions have arrived: until then every node is at one point.
- The canvas is sized for the device pixel ratio and follows the box through a `ResizeObserver`.
- `theme.js` reads the `--cs-*` tokens once and again when the theme changes (the `data-theme` or `class` attribute of `<html>`, or the system scheme). The script holds no colour value.

### 4.4 The camera

- Wheel and pinch zoom towards the pointer. Dragging empty space pans. Dragging a node moves that node (`pin` / `unpin`).
- Three buttons in a corner of the box: zoom in, zoom out, "Fit all".
- With the canvas focused, arrow keys pan and `+` / `-` zoom.
- The first view fits everything: the camera follows the layout from its first positions until it has settled, and that fit is final (§11). After that — or from the user's first zoom, pan or drag of a node, if that comes sooner — the camera moves only on the user's input or on "Fit all". A change of focus is a new visit, and so a new first view.
- Nodes are no longer clamped to the box. The box is a window onto the graph.
- Zoom has a lower and an upper limit: 0.05 and 4. A fit never zooms in past 1.5, so three nodes are not stretched over the whole box.

### 4.5 Loading

- The `d3-force` pin loses `preload: "admin"`; only the worker loads the file.
- The `mind_graph/` modules are not preloaded on other screens.
- `test/integration/public_javascript_test.rb` keeps the public pages free of both.

### 4.6 Kept from today

- Dragging a node.
- The All / Related / Tags filter, client-side, handing the simulation only what is visible.
- Back restores a clean screen, and the graph shows what the filter control says.
- A drag below a few pixels of movement is a click.

## 5. What the user sees

The legend is rendered by the server from the content types of the viewer's readable posts (one distinct query), since the page no longer holds the graph's data.

### 5.1 Nodes

- A post is a circle and a tag is a square.
- Size follows `degree` in four steps, from 6 to 14 pixels radius for a post (6 up to two connections, 8 up to five, 11 up to twelve, 14 beyond), and three quarters of that as a tag's half side. A node is the same size on screen at every zoom.
- Type and status cues are unchanged: slots 1–6 filled, slots 7–12 a ring of the same hues; a draft or scheduled post has a dashed outline, with a small filled core for slots 1–6.
- A post whose type is no longer registered is a grey ring with a diagonal stroke through it. The legend shows a "Retired type" entry when one is present.

### 5.2 Labels

- Hubs first: the zoom decides how many labels are shown — 40 at zoom 1, growing with the square of the zoom — and they go to the best-connected nodes *on the canvas* (§11; as designed, each node had a zoom level of its own over the whole graph).
- A label is skipped when it would overlap one already placed. Higher degree places first.
- The selected node, the focus and the selection's direct neighbours are labelled at any zoom, in that order, unless one would overlap an earlier one of them (§11).
- The last quarter of the labels the zoom allows is drawn fainter, the last one faintest, so a label arrives gradually as you zoom in. With `prefers-reduced-motion` it switches without fading.
- A long title is cut with an ellipsis, by code point as today; a tag's label keeps its count.

### 5.3 Selecting

- A click on a node selects it. It and its direct neighbours stay at full strength, the rest dims, and the card opens.
- The card is HTML over the top-right corner of the canvas, with a Close button.
  - Post: title, type, status chip, number of connections, "Open post", "Focus graph here".
  - Tag: name, number of posts, "Focus graph here", "Show posts with this tag" (the posts list with its `tag` filter).
- A click on empty space, or Escape, clears the selection and closes the card.
- Hovering a node shows its full title in a tooltip.

### 5.4 Local view

- The focus is drawn with a marker ring and is always labelled. It is not held in the middle (§11).
- A bar above the box names it — "Around ‘Title’" — with a two-way depth switch (1 · 2) and a "Whole graph" link.
- "Focus graph here" and the depth switch are ordinary visits, so Back works.

### 5.5 Search

One field above the box. Typing lists matching posts and tags; choosing one opens its local view. This is how a post outside the capped global view is reached.

### 5.6 Messages

- Over the cap, global view: "Showing the 2,000 best-connected of 6,000 posts." The second figure is `total`, the posts with a connection; the isolated ones are the next sentence's.
- Over the cap, local view: "Showing the 2,000 nearest of 2,695 posts around this one." A local view keeps the nearest posts first (§3.3), so "best-connected" would be untrue of it (§11).
- Isolated posts, global view: "214 posts have no connections yet." Every figure in these sentences is grouped for the language of the messages ("1,214").
- No connections at all: today's hint about related posts and shared tags.
- The viewer can read no post: "No posts yet.", as today.
- The data could not be loaded: a message in the box with Retry.
- The worker could not start: a message in the box, without Retry.

### 5.7 Keyboard and screen reader

- The canvas is one labelled image: its name says how many posts and connections are shown.
- Below the box, a collapsed "List of posts and tags in this graph" holds every drawn node, grouped as posts and tags, each with its connection count. A row links to the node's local view; a post's row also links to its editor.
- The list is rendered by the script from the same data as the canvas, and follows the filter.
- Tab order: search, the focus bar's links in a local view (§11), filter, zoom buttons, the canvas, the card when open, the list.

### 5.8 Strings

Every string of the screen, the card, the legend and the script is a key in `config/locales/admin/`, read with `t(".key")` or, in the script, `messages(element).t(key)`. The screen and its components join `CONVERTED` in `test/lib/admin_i18n_test.rb`.

## 6. Errors

- The data request fails or times out (after 15 seconds): the box message with Retry. Search keeps working.
- The worker fails: the box message; the list still gives every node as a link, and still follows the filter.
- A stale focus: 404.
- Leaving the screen stops the worker, the animation frame and the observers.

## 7. Tests and measurement

**Queries**
- `PostGraph::Global`: ranking, the cap, tie-breaking, `total` / `shown` / `isolated`, column selection.
- `PostGraph::Local`: both depths from a post and from a tag, the focused-tag exception, the cap.
- Both: no node, edge, tag or count that discloses an unreadable or trashed post.
- Both: the number of statements does not depend on the number of posts (`capture_sql`).

**Integration**
- The page, the data endpoint and the search endpoint: permission, scoping, 404 on an unreadable, trashed or unknown focus.
- The trash-visibility test covers the new endpoints.
- No page other than the Mind graph references d3-force.

**System** — the project has no JavaScript test runner and gains none. The screen is tested through the browser (`test/system/admin/mind_graph_test.rb`), and the modules that are plain functions — the camera, the hit test, the label rule, the renderer's culling, the input's gestures, the worker and its client — are imported in the test browser from a CS Studio page and called directly (`test/system/admin/mind_graph_modules_test.rb`; §11). The app says its state on the element as data attributes: `data-state`, `data-settled`, `data-nodes`, `data-edges`, `data-zoom`, `data-labelled`, `data-selected`, `data-neighbours`. `element.mindGraph.screenPosition(id)` returns a node's place on screen, where the test clicks with a real click, and `element.mindGraph.draws()` the number of frames drawn.
- The graph settles and the first view fits everything.
- A click selects, opens the card, and both actions go where they say.
- Zoom buttons and keys change the zoom, and more labels appear.
- The filter, search to focus, the depth switch, Back.
- The list of links matches what is drawn.
- The worker-failure and load-failure messages.
- Any JavaScript error, in the page or the worker, fails the test.

**Measurement**
- A development script, `script/dev/mind_graph_posts.rb`, builds 2,000 and 6,000 posts with relations and tags through `Posts::Save`: a few hubs, many posts with one to three links, a tail with none, 60 tags of which some are very common. It is run against a throwaway database (`DATABASE_URL`), never the one a developer works in.
- The cap is set from the numbers below. **It stays at 2,000**: at the cap no frame of a pan was late and the data endpoint answers in about a tenth of a second, a long way inside the two limits the decision was to be made by (33 ms a frame, one second for the endpoint). It was not raised: that was never measured, and it is not this sub-project's question.

Measured on 2026-10-08, with both renderer changes of §11 in place:

| | 2,000 posts | 6,000 posts |
|---|---|---|
| The site | 2,005 posts: 1,933 connected, 72 isolated; 3,162 related-post links, 2,770 tag links | 6,005 posts: 5,791 connected, 214 isolated; 9,427 related-post links, 8,358 tag links |
| Drawn | 1,933 posts, 61 tags, 5,931 edges | 2,000 posts, 60 tags, 7,904 edges; "Showing the 2,000 best-connected of 5,791 posts." |
| Data endpoint, time | 96 ms (92–107) | 136 ms (133–143) |
| Data endpoint, size | 515 kB; 45 kB gzipped | 617 kB; 55 kB gzipped |
| Data endpoint, statements | 8, together 8–9 ms; the slowest 2.7 ms | 8, together 13 ms; the slowest 4.1 ms |
| Navigation to the first frame with nodes | 0.24 s | 0.29 s (0.28–0.31) |
| Navigation to settled | 2.5 s (2.49–2.58) | 2.8 s (2.69–2.86) |
| The same on the first visit of a fresh browser | 0.86–0.90 s and 3.1–3.2 s | 0.91–0.97 s and 3.4–3.5 s |
| Frame while panning, layout still running | median 16.7 ms, worst 16.8 ms | median 16.7 ms, worst 16.8 ms |
| Frame while panning, settled, whole graph in view | median 16.7 ms, worst 16.8 ms | median 16.7 ms, worst 16.8 ms |
| Frame while panning, settled, at the largest zoom | median 16.7 ms, worst 16.8 ms | median 16.7 ms, worst 16.8 ms |
| Script time of one frame (labels and canvas calls) | median 0.3–1.1 ms, worst 1.4 ms | median 0.3–1.1 ms, worst 2.0 ms |
| A filter change, until the handler returns | 6–10 ms; the first one 21 ms | 8–11 ms; the first one 24 ms |
| Of that, building the list of links | 6.3–6.9 ms for 1,994 rows (7,921 elements) | 6.7 ms for 2,060 rows (8,186 elements) |
| Finding the node under the pointer | 0.2 ms, worst 0.4 ms | 0.2 ms, worst 0.4 ms |
| The page's JavaScript heap after settling | 19–21 MB | 18–23 MB |

How each was taken:
- **The machine:** an Apple M4 Pro (12 cores, 48 GB), macOS 27.0.1. The server was `bin/rails server` in the development environment (code reloading, verbose query logs, the console span exporter) against Postgres 17 in Docker, so the endpoint's times are a development server's; production was not measured.
- **The browser:** Google Chrome 154, **headless**, driven by a script over the DevTools protocol (Ferrum), window 1440 × 900, the canvas 1150 × 532 CSS pixels. Headless numbers are indicative: there is no display, so they say whether a frame was late, not what a person sees on a screen. One run of each size was repeated at a device pixel ratio of 2 (a 2300 × 1238 bitmap) with the same frame times.
- **The endpoint:** `curl` with the session's cookie, eleven requests, median and range of the total time; the size is the body's, which the development server sends uncompressed, and the gzipped figure is the same body through `gzip` (production serves through Thruster, which compresses). Statements and their times are the development log's: five are the query's (§3.4), three the request's own (session, user, settings). No statement stands out, and about nine tenths of the time is spent outside the database, building 2,000 nodes and their JSON.
- **Navigation to first frame and to settled:** `performance.now()`, read in a frame loop installed before the page's scripts: the first frame drawn after the worker's first positions arrived, and the frame on which `data-settled` appeared. Four loads of each size in a browser that had visited the screen before (median and range), and separately the first visit of a fresh browser, where the modules and the worker are fetched and compiled for the first time.
- **Frame times:** the differences between successive `requestAnimationFrame` timestamps over 240 frames of a scripted drag on empty space, one pointer event per frame, and 60 frames of wheel events for the zoom. At 60 Hz these are multiples of 16.7 ms, so "worst 16.8 ms" means no frame was late; it does not say how much room was left. The script time is the duration of the app's own frame callback.
- **The filter:** `performance.now()` around the radio's `click()`, whose `change` handler runs `applyFilter` — the visible sets, the list of links, the message to the worker — before it returns. The list alone is `renderList` called on a detached container, seven times. With the list open the browser needs one more frame to lay the rows out (about 50 ms from the click to the second frame after it, 33 ms with it closed). Nothing here is near 100 ms, so the list is still rebuilt on every filter change, open or not.
- **A local view** at 6,000 posts, for comparison: a hub's depth 1 (725 posts) answers in 49 ms; its depth 2 reaches 2,695 posts, is cut to 2,000 and answers in 117 ms with 14 statements (22–29 ms). The frame page itself is 46 ms and 78 kB whatever the site's size, and a search 20 ms.

What the measurement changed:
- **Off-canvas culling.** Before it, at the largest zoom, five or six of 240 frames of a pan took 33 ms instead of 17 at 2,000 posts (three runs, the same each time), while the script time stayed under a millisecond: the cost was the rasteriser's, walking every dash of long dashed edges that are almost wholly outside the view. With the culling of §4.3 no frame is late.
- **No frame before the first positions.** The first frame after the data arrived drew every node at one point, the canvas's top-left corner — for one frame on a normal load (the 12–25 ms until the worker's first message), and for good when the worker failed. It is now an empty frame.

## 8. Risk

Serving a module worker through the asset pipeline with a digest URL, and running it in the system-test browser, was not proven in this project when this was written. The plan's first task proved it (`test/system/admin/mind_graph_modules_test.rb`, "the layout worker starts from its asset URL…"), so the fallback below was never built: to run the simulation on the main thread in time slices (a few milliseconds of ticks per frame), with `layout_client.js` keeping its interface and nothing else in this design changing.

## 9. Documentation

- The Mind graph section of `docs/reference/cs-studio-shell-and-dashboard.md` is rewritten.
- `docs/roadmap.md`: the entry is closed, and two items are added — the neighbourhood panel in the post editor, and WebGL for sites beyond the cap.
- `CLAUDE.md`: the reference index entry gains `app/queries/post_graph/` and `app/javascript/mind_graph/`.

## 10. Out of scope

- Editing relations in the graph.
- Pages and media as nodes.
- Saving a layout or node positions between visits.
- Clustering or colouring by community.
- The embedded panel in the post editor.
- WebGL.

## 11. Where the build departs from this spec

The sections above are corrected where they stated something that is no longer true (the module table, the worker's messages, the data's `focus`, the label rule's wording, the tests). What follows are the decisions made while building, each with its reason.

**Labels**
- *A label's rank is among the nodes on the canvas, not over the whole graph.* §5.2 gave each node a zoom level of its own, derived from its degree. Zoomed into a corner, that budget would be spent on hubs nobody can see while the nodes in view stay unnamed. So the zoom decides how many labels there are, and they go to the best-connected nodes inside the canvas. The cost: a label can appear or disappear while panning, as a better-connected node enters or leaves the view.
- *"Labels never overlap" wins over "always labelled".* The selected node is placed first, then the focus, then the selection's neighbours, and one of them that would overlap an earlier label is left out. A hub's forty neighbours can't all be named in a few hundred pixels without overlap, and overlapping labels are what this sub-project set out to end.
- *The fade is by rank, not over time.* The last quarter of the labels a zoom level allows is drawn fainter. Nothing animates; zooming is what moves a label through the fade.

**The worker**
- *`settled` says which request it answers.* The worker counts the messages it has taken up and sends that number as `after`; the page counts what it sent and believes only a `settled` whose `after` equals it. A small graph cools down inside the first slice, before a `filter` sent right behind `start` is handled, and that first `settled` describes a layout the page has already asked to change — the page would fit the view and call the screen settled on the wrong layout.
- *Messages are handled strictly in order.* `start` waits for the import of d3-force, and a `filter`, `pin` or `unpin` behind it would otherwise run before the simulation exists. Each message is handled after the one before it has finished.
- *A message that changes nothing is still answered.* A `pin` for a node that isn't there gets a `settled` when the layout is at rest, because the page waits for one that counts it.
- *There is no `stop` message.* The page terminates the worker, and nothing in flight is delivered afterwards.

**The camera and input**
- *The camera follows the layout until it has settled.* §4.4 had the first view fit "once the layout has settled enough to have a shape". There is no good moment for that: the graph keeps growing for a second or two, and a fit made early leaves it running out of the box. The camera is refitted on every tick until the layout has cooled down or the user moves it, whichever comes first.
- *A two-finger touch pinch is implemented*, beside the wheel and the trackpad's pinch (which arrives as a wheel event). It is tested with synthetic pointer events only; no touch device was used. A touch or a pen also ends on `lostpointercapture`, as on a cancel and without a click: a touch whose `pointerup` and `pointercancel` are both lost would otherwise stay in the table of pointers and turn every later touch into a pinch. A mouse does not: its `pointerup` always comes, and a capture dropped mid-press must not end its drag. A new finger arriving while one of a pinch remains restarts the pinch.
- *The focus is not held in the middle.* §5.4 said it "starts in the middle". The layout places it like any other node and the first view fits everything, so a focus with neighbours on one side sits off-centre. It has its ring and is always labelled.

**The page**
- *The data request times out after 15 seconds* (§6 said "fails or times out" without a number), into the same message with Retry.
- *The search field is first in the document*, before the focus bar's links, so Tab reaches it first; on screen the bar is on the left (`order-first`). §5.7 lists search first and did not place the bar.
- *The card has a Close button*, and Escape closes it from inside the card as well as from the canvas; the focus then goes back to the canvas.
- *Turbo's page snapshot is undone on connect.* Turbo caches the page as it stood when it was left, script-written state included: `data-state="ready"`, `data-settled`, the counts, the notice, an open card, the search's text and results, the list's rows. The controller's `reset()` clears all of it before anything is fetched, and puts the canvas's name back to the server's (kept in its `data-label`), since the script writes the counts into it. The filter's radios and whether the list is open are the person's own state and are kept.
- *The scripts' class names need a line in the Tailwind build.* `app/assets/tailwind/application.css` reads only the paths its `@source` lines name, and `app/javascript/mind_graph` was not one: `w-fit`, used only there, was never built, and nothing failed. The line is there now, and `test/lib/tailwind_sources_test.rb` fails for any directory of scripts that writes class names without one.
- *The current depth is text, not a disabled link.* It is marked `aria-current` and carries a visually hidden "Depth" before its number; the other depth is a link named "Depth 2".
- *The edit link of a list row is named by a key of its own* ("Edit %{title}"), not by joining "Edit" and the title in the script.

**The data**
- *Under the cap, a kept post can be drawn with no edge.* A post is ranked by its connections among all readable posts. If its only link is a tag whose other posts were cut, the tag has one edge left in the response, is no node (§3.4), and the post stands alone. It is still counted in `shown`, and its `degree` is 0. In the measured 6,000-post set this happened to no post.
- *The local view's cap ranks by the connections inside the neighbourhood*, nearer depth first; the global view's by those among all readable posts.
- *A capped local view has a sentence of its own* (§5.6), chosen when the response carries a `focus`.
- *The isolated count is grouped like the other figures.* The script hands the message the formatted figure as `%{figure}`; `count` stays, to choose the plural form.
- *An id is parsed as a strict decimal* (`Integer(value.to_s, 10, exception: false)` in `PostGraph::Focus`). Ruby's `Integer("010")` is 8 and `Integer("0x1A")` 26, so a URL could open a post other than the one it names.

**Drawing**
- *Hit testing is a linear scan* (already in §4.1): measured at 0.2 ms per pointer event at the cap.
- *What is outside the canvas is not drawn*, and *nothing is drawn before the first positions* — both added after the measurement, which is where §7 describes them.
- *The list of links is rebuilt on every filter change, open or closed.* Building it lazily was considered and measured unnecessary (§7).

**Tests**
- *The pure modules are tested by importing them in the browser*, not "through the screen" as §7 first said: a camera's arithmetic or the label rule can't be asserted through a canvas's pixels, and the import map already resolves the modules on any CS Studio page.
- *What the worker is told is recorded in the test*, by wrapping `Worker.prototype.postMessage`: no pixel shows that a plain click sent the layout nothing.

