# Mind graph on a canvas

The first sub-project after the technical cleanup (`docs/roadmap.md`, "Mind graph on a canvas", agreed 2026-10-04). The design was agreed with the user on 2026-10-07 in four sections. This is the binding spec for one implementation plan and one PR.

**Status: design agreed, not built.**

## 1. Purpose

CS Studio's Mind graph shows how posts relate through related-post links and shared tags. Today it draws every readable post as SVG elements inside a fixed box, computes the layout in the page, and embeds the whole data set in the HTML. That works for a few dozen posts and breaks down well before a serious site's size:

- There is no cap: the screen loads and simulates every readable post.
- Labels overlap, because every node is labelled at all times.
- Every node is one size, so a hub looks like a leaf.
- Nodes are clamped to the box, so a large graph is pressed against its edges.
- You can't zoom, pan, or look at one post's neighbourhood.
- A post whose type is no longer registered differs from a ring of slots 7–12 by colour alone.
- d3-force is preloaded on every CS Studio page.

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

All three need `posts.read` somewhere, as the screen does today. A focus the viewer may not read, a trashed post and an unknown id answer 404, from the page and from the data endpoint alike.

### 3.2 The data moves out of the page

The page renders only the frame: heading, focus bar, search field, legend, filter, the empty canvas, the card's container and the list's container. The script fetches the data endpoint. The `<script type="application/json">` island is removed.

Reason: at the cap the JSON is several hundred kilobytes, which would otherwise sit in every page load and in Turbo's page cache.

### 3.3 `PostGraph::Global` and `PostGraph::Local`

`PostGraph` becomes a namespace in `app/queries/post_graph/` with two queries and a shared builder for the common parts (node rows, tag derivation, edge rows). Both take `actor:`, `locale:` and `url_for:` as today, with `actor:` required.

**Shape**, the same for both:

```
{
  nodes: [{ id, title, type, colour_index, status, url, degree }],
  tags:  [{ id: "tag-<id>", name, count, degree }],
  edges: [{ source, target, kind: "related" | "tag" }],
  total: <readable posts with at least one connection>,
  shown: <posts in nodes>,
  isolated: <readable posts with no connection>,   # global only
  focus: { kind: "post" | "tag", id, title, depth } # local only
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
- Capped at `PostGraph::CAP` posts too. Over the cap it keeps the focus, then the best-connected neighbours, nearer depth first, and `total` / `shown` say so.

**The cap** is one constant, `PostGraph::CAP`, starting at 2,000 and set from the measurements in §7.

### 3.4 Rules that do not change

- Tags are derived only from readable posts, and a tag's `count` is the number of *readable* posts carrying it — never the tag's true total, and not the smaller number drawn, which would understate it.
- No edge points at a post that isn't in `nodes`.
- A tag is a node only when at least two readable posts carry it (`MIN_TAGGED_POSTS`) and it has enough edges in this response to say something: two in the global view, one in a local view (where a post's own tags are its depth-1 neighbours). One exception: the focused tag of a local view is always a node.
- A focused tag that no readable post carries is not found.
- Trashed posts are hidden explicitly, and the data and search endpoints are added to `test/integration/trash_visibility_test.rb`.
- The cost does not grow with the number of posts: a fixed number of queries for the global view, and a fixed number per depth level for the local one.

### 3.5 Search

The search endpoint returns up to ten posts and ten tags whose name matches, through the existing scopes (`title_matching_any_locale`, `Tag.name_containing`), posts through `AccessControl.scope`. A tag is listed only if at least one readable post carries it. Each row carries a label, a kind and the URL of its local view.

## 4. The script

### 4.1 Modules

The 385-line `admin/mind_graph_controller.js` becomes a thin Stimulus controller over modules in `app/javascript/mind_graph/`:

| Module | Does | Knows about |
|---|---|---|
| `layout_worker.js` | Runs d3-force and posts positions back | d3-force |
| `layout_client.js` | Starts the worker, sends commands, hands positions to the page | the worker's messages |
| `camera.js` | Zoom, pan, fit-to-view, screen ↔ graph coordinates | numbers |
| `renderer.js` | Draws edges, nodes, labels and the selection onto the canvas | camera, theme, positions |
| `hit_test.js` | Finds the node under a point | positions |
| `labels.js` | Decides which labels are shown at this zoom | degree, camera, positions |
| `theme.js` | Reads the colour tokens from CSS custom properties | the document |

The controller wires them together and owns the HTML around the canvas: the filter, the search field, the card and the list.

### 4.2 The worker

- A module worker, served through the asset pipeline with a digest URL. It imports the vendored `d3-force.js` by its asset URL, because an import map does not apply inside a worker. The file is one self-contained bundle, so that import needs nothing else.
- Page to worker: `start` (nodes, edges, size), `filter` (visible ids), `pin` / `unpin` (dragging a node), `stop`.
- Worker to page: `tick` with one `Float32Array` of x/y pairs, transferred and not copied; `settled`; `error`.
- The worker runs several simulation ticks per message and sends at most one message per frame's worth of work.
- An error inside the worker is forwarded to the page and reported with `console.error`, so the system tests' JavaScript-error rule sees it.
- The worker is terminated on `disconnect()`.

There is no second code path that runs the simulation in the page. If the worker can't start, the box shows a message and the list of links (§5.7) still works.

`hit_test.js` is a linear scan over the visible nodes: at the cap that is 2,000 distance checks per pointer event, which needs no index.

### 4.3 Drawing

- One redraw per animation frame, and only when something changed: positions, the camera, the selection, the filter, the theme.
- Order: edges, nodes, labels, selection and focus rings.
- Edges are batched into one path per kind (related solid, tag dashed).
- The canvas is sized for the device pixel ratio and follows the box through a `ResizeObserver`.
- `theme.js` reads the `--cs-*` tokens once and again when the theme changes (the `data-theme` attribute or the system scheme). The script holds no colour value.

### 4.4 The camera

- Wheel and pinch zoom towards the pointer. Dragging empty space pans. Dragging a node moves that node (`pin` / `unpin`).
- Three buttons in a corner of the box: zoom in, zoom out, "Fit all".
- With the canvas focused, arrow keys pan and `+` / `-` zoom.
- The first view fits everything, once the layout has settled enough to have a shape. After that the camera moves only on the user's input, on "Fit all", or on a change of focus.
- Nodes are no longer clamped to the box. The box is a window onto the graph.
- Zoom has a lower and an upper limit.

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
- Size follows `degree` in four steps, from 6 to 14 pixels radius for a post, and proportionally for a tag.
- Type and status cues are unchanged: slots 1–6 filled, slots 7–12 a ring of the same hues; a draft or scheduled post has a dashed outline, with a small filled core for slots 1–6.
- A post whose type is no longer registered is a grey ring with a diagonal stroke through it. The legend shows a "Retired type" entry when one is present.

### 5.2 Labels

- Each node has a zoom level from which its label is shown, derived from its degree: hubs first.
- A label is skipped when it would overlap one already placed. Higher degree places first.
- The selected node, its direct neighbours and the focus are always labelled.
- A label fades in over a short zoom range. With `prefers-reduced-motion` it switches without fading.
- A long title is cut with an ellipsis, by code point as today; a tag's label keeps its count.

### 5.3 Selecting

- A click on a node selects it. It and its direct neighbours stay at full strength, the rest dims, and the card opens.
- The card is HTML at the side of the box.
  - Post: title, type, status chip, number of connections, "Open post", "Focus graph here".
  - Tag: name, number of posts, "Focus graph here", "Show posts with this tag" (the posts list with its `tag` filter).
- A click on empty space, or Escape, clears the selection and closes the card.
- Hovering a node shows its full title in a tooltip.

### 5.4 Local view

- The focus is drawn with a marker ring and starts in the middle.
- A bar above the box names it — "Around ‘Title’" — with a two-way depth switch (1 · 2) and a "Whole graph" link.
- "Focus graph here" and the depth switch are ordinary visits, so Back works.

### 5.5 Search

One field above the box. Typing lists matching posts and tags; choosing one opens its local view. This is how a post outside the capped global view is reached.

### 5.6 Messages

- Over the cap: "Showing the 2,000 best-connected of 6,000 posts."
- Isolated posts, global view: "214 posts have no connections yet."
- No connections at all: today's hint about related posts and shared tags.
- The viewer can read no post: "No posts yet.", as today.
- The data could not be loaded: a message in the box with Retry.
- The worker could not start: a message in the box, without Retry.

### 5.7 Keyboard and screen reader

- The canvas is one labelled image: its name says how many posts and connections are shown.
- Below the box, a collapsed "List of posts and tags in this graph" holds every drawn node, grouped as posts and tags, each with its connection count. A row links to the node's local view; a post's row also links to its editor.
- The list is rendered by the script from the same data as the canvas, and follows the filter.
- Tab order: search, filter, zoom buttons, the canvas, the card when open, the list.

### 5.8 Strings

Every string of the screen, the card, the legend and the script is a key in `config/locales/admin/`, read with `t(".key")` or, in the script, `messages(element).t(key)`. The screen and its components join `CONVERTED` in `test/lib/admin_i18n_test.rb`.

## 6. Errors

- The data request fails or times out: the box message with Retry. Search keeps working.
- The worker fails: the box message; the list still gives every node as a link.
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

**System** — the pure modules have no unit runner (the project has none and gains none); they are exercised through the screen. The controller exposes its state on the element as data attributes: node count, settled flag, zoom level, selected id, labelled ids. A test-only lookup returns a node's screen position, and the test clicks there with a real click.
- The graph settles and the first view fits everything.
- A click selects, opens the card, and both actions go where they say.
- Zoom buttons and keys change the zoom, and more labels appear.
- The filter, search to focus, the depth switch, Back.
- The list of links matches what is drawn.
- The worker-failure and load-failure messages.
- Any JavaScript error, in the page or the worker, fails the test.

**Measurement**
- A development script builds 2,000 and 6,000 posts with realistic relations and tags through the save services.
- Recorded in this spec once measured: time to first draw, time to settle, frame time while panning, the response size and time of the data endpoint.
- The cap is set from those numbers. If 2,000 is too many, the cap comes down and the design stands.

## 8. Risk

Serving a module worker through the asset pipeline with a digest URL, and running it in the system-test browser, is not yet proven in this project. The plan's first task is a spike that proves it. If it fails, the fallback is to run the simulation on the main thread in time slices (a few milliseconds of ticks per frame); `layout_client.js` keeps its interface and nothing else in this design changes.

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
