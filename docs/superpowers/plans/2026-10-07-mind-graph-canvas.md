# Mind Graph on a Canvas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CS Studio's Mind graph is drawn on one zoomable canvas, laid out in a Web Worker, capped at the best-connected posts, with a local graph around any post or tag.

**Architecture:** Two queries (`PostGraph::Global`, `PostGraph::Local`) share one builder and answer through a JSON endpoint. The page renders only a frame; a thin Stimulus controller lazy-loads `mind_graph/app`, which fetches the data, hands the simulation to a module worker (d3-force) and draws positions onto a 2D canvas through small pure modules (camera, labels, hit test, renderer, theme).

**Tech Stack:** Rails 8.1, Postgres, Minitest + fixtures, Capybara on Cuprite, Stimulus, importmap-rails, Propshaft, d3-force 3.0.0 (already vendored), Tailwind v4.

**Spec:** `docs/superpowers/specs/2026-10-07-mind-graph-canvas-design.md` — read it before any task.

## Global Constraints

- Before touching the screen, read the Mind graph section of `docs/reference/cs-studio-shell-and-dashboard.md`, and `docs/reference/i18n.md` before adding a string.
- Every test command is prefixed `PGGSSENCMODE=disable`. System tests: `bin/rails tailwindcss:build` first, then `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test:system`. Never run two test runners at once.
- No new dependency: no npm, no new gem, no new import-map pin of a library. d3-force stays at the vendored 3.0.0.
- No colour literal in JavaScript, a view or a component: no hex, `rgb()`, `hsl()` or `oklch()` value. Colours are read from the `--cs-*` custom properties (`test/lib/admin_design_rules_test.rb`).
- No cue is colour-only: every type and status difference is also a shape or line-style difference.
- Every string a person reads is a key in `config/locales/admin/`, read with `t(".key")` or, in a script, `messages(element).t(key)`. No English in a view, component or script of this screen.
- No inline event handlers: behaviour is wired through `data-action` (`test/lib/inline_handlers_test.rb`).
- A query knows no routes: `url_for:` is passed in, never defaulted (`test/lib/dependency_direction_test.rb`).
- Queries are Active Record, then Arel, then SQL; an unmarked SQL string under `app/` fails `test/lib/sql_strings_test.rb`.
- A record outside the viewer's scope is not found: look posts up through `AccessControl.scope(actor, "posts.read", …)` and answer 404.
- No count, node, edge or tag may disclose a post the viewer can't read, or a trashed post.
- No fixed `sleep` in a system test without `# sleep: <reason>`; wait with `assert_selector`, `await_js`, `assert_eventually`.
- A system test fails on any JavaScript error. A worker's error is forwarded to the page and logged with `console.error`.
- A click in a system test is a real click (`press`, or the browser mouse at a coordinate), never a scripted one.
- A test that resizes the window restores the size in an `ensure`.
- The cap is one constant, `PostGraph::CAP = 2_000`, until Task 10 confirms or lowers it.
- Never define `Admin::PostGraph` (it would shadow the query namespace).
- The existing path stays `<admin>/mind_graph` (underscore).
- Commits follow conventional commits and end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never skip hooks.

## Review Focus

1. **A title or tag name with markup or quotes in it** (`</script>`, `"><img>`, an emoji). Expected: it shows as text in the card, the list, the tooltip, the search results and on the canvas. Pinned in Task 7 (card) and Task 9 (list).
2. **Leaving the screen while the data is loading or the layout is running.** Expected: no error, no worker left running, no draw after disconnect. Pinned in Task 6.
3. **Back to the graph after opening a post.** Expected: the graph draws once, in the mode the URL and the filter control say. Pinned in Task 6.
4. **A box with no size at connect time** (a Turbo cache preview, a hidden tab), then a resize. Expected: nothing is drawn at 0×0 and the first real size fits the view. Pinned in Task 6.
5. **A graph of one node, or of nodes all at one point.** Expected: "Fit all" neither divides by zero nor zooms beyond the limit. Pinned in Task 5.

## File Structure

| File | Responsibility |
|---|---|
| `app/queries/post_graph.rb` | The namespace: `CAP`, `MIN_TAGGED_POSTS`. (A class with `.call` until Task 6 removes the old query.) |
| `app/queries/post_graph/builder.rb` | Turns chosen post ids, relation pairs and tag links into `{ nodes, tags, edges }` with degrees. |
| `app/queries/post_graph/global.rb` | The best-connected readable posts up to the cap. |
| `app/queries/post_graph/focus.rb` | Resolves `post=` / `tag=` into a focus the viewer may see, or raises not found. |
| `app/queries/post_graph/local.rb` | The neighbourhood of a focus to depth 1 or 2. |
| `app/queries/post_graph/search.rb` | Readable posts and tags by name, for the search field. |
| `app/controllers/admin/mind_graph_controller.rb` | `show` (the frame), `data`, `search`. |
| `app/views/admin/mind_graph/show.html.erb` | The frame: heading, focus bar, search, legend, filter, canvas, card, list. |
| `app/components/admin/mind_graph_legend_component.*` | The legend, with keys and a "Retired type" entry. |
| `config/locales/admin/mind_graph.en.yml` | The screen's and the script's strings. |
| `app/javascript/controllers/admin/mind_graph_controller.js` | Thin: lazy-imports `mind_graph/app`, mounts and destroys it. |
| `app/javascript/mind_graph/layout_worker.js` | d3-force in a module worker. |
| `app/javascript/mind_graph/layout_client.js` | The page's side of the worker. |
| `app/javascript/mind_graph/camera.js` | Zoom, pan, fit, coordinate conversion. Pure. |
| `app/javascript/mind_graph/hit_test.js` | The node under a point. Pure. |
| `app/javascript/mind_graph/labels.js` | Which labels show at this zoom, without overlap. Pure. |
| `app/javascript/mind_graph/theme.js` | Colours from CSS custom properties. |
| `app/javascript/mind_graph/renderer.js` | Draws one frame. |
| `app/javascript/mind_graph/input.js` | Pointer, wheel and key events into callbacks. |
| `app/javascript/mind_graph/card.js` | The selection card. |
| `app/javascript/mind_graph/node_list.js` | The accessible list of links. |
| `app/javascript/mind_graph/search_box.js` | The search field's results. |
| `app/javascript/mind_graph/app.js` | Wires the above: fetch, layout, state, redraw loop. |
| `test/system/admin/mind_graph_modules_test.rb` | The pure modules, imported in the browser. |
| `test/system/admin/mind_graph_test.rb` | The screen. |
| `script/dev/mind_graph_posts.rb` | Builds the large data set for measuring. |

---

### Task 1: The layout worker, proven in the test browser

The risk named in the spec's §8. This task builds the real worker and its client and proves, in the system-test browser, that a module worker served by Propshaft with a digest URL can import the vendored d3-force and return positions. The SVG graph stays untouched; the worker runs beside it.

**Files:**
- Create: `app/javascript/mind_graph/layout_worker.js`, `app/javascript/mind_graph/layout_client.js`
- Modify: `config/importmap.rb` (add the `mind_graph` directory, not preloaded)
- Test: `test/system/admin/mind_graph_modules_test.rb`

**Interfaces:**
- Produces: `createLayout({ workerUrl, d3Url, onTick, onSettled, onError })` returning `{ start(nodes, edges), filter(nodeIds, edgeIndexes), pin(id, x, y), unpin(id), stop() }`.
  - `nodes`: `[{ id, radius }]`; `edges`: `[{ source, target }]` (ids).
  - `onTick(positions)`: a `Float32Array` of length `2 * nodes.length`, x then y, in the order of `nodes` as given to `start`.
  - `onSettled()`: the simulation cooled down. `onError(message)`: the worker failed.
- Asset URLs: `asset_path("mind_graph/layout_worker.js")` and `asset_path("d3-force.js")`.

- [ ] **Step 1: Pin the directory**

In `config/importmap.rb`, after the `media` line:

```ruby
# The mind graph's modules: imported only by `controllers/admin/mind_graph_controller.js`
# through a dynamic `import()`, so no other CS Studio screen fetches them --
# `preload: false`. `layout_worker.js` is in this directory too but is never
# imported: it is started as a module Worker from its asset URL.
pin_all_from "app/javascript/mind_graph", under: "mind_graph", preload: false
```

- [ ] **Step 2: Write the failing test**

`test/system/admin/mind_graph_modules_test.rb`:

```ruby
require "application_system_test_case"

# The mind graph's own modules (`app/javascript/mind_graph/`), imported in the
# browser from any CS Studio page: the project has no JavaScript test runner,
# and these are plain modules the import map resolves, so a system test can
# call them directly and compare what they return.
class Admin::MindGraphModulesSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    visit admin_tags_path
    await_admin_controllers
  end

  test "the layout worker starts from its asset URL, lays three nodes out and settles" do
    result = page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"), ActionController::Base.helpers.asset_path("d3-force.js"))
      const [workerUrl, d3Url, done] = arguments
      import("mind_graph/layout_client").then(({ createLayout }) => {
        let ticks = 0
        let last = null
        const layout = createLayout({
          workerUrl, d3Url,
          onTick: (positions) => { ticks += 1; last = Array.from(positions) },
          onSettled: () => { layout.stop(); done({ ticks, last }) },
          onError: (message) => done({ error: message })
        })
        layout.start([{ id: 1, radius: 8 }, { id: 2, radius: 8 }, { id: "tag-3", radius: 6 }], [{ source: 1, target: 2 }, { source: 2, target: "tag-3" }])
      })
    JS

    assert_nil result["error"]
    assert_operator result["ticks"], :>, 0
    assert_equal 6, result["last"].size
    assert result["last"].all? { |value| value.is_a?(Numeric) && value.finite? }
    xs = result["last"].each_slice(2).map(&:first)
    assert_equal 3, xs.uniq.size, "three nodes at one x: the simulation never ran"
  end

  test "a worker that can't load d3-force reports an error instead of hanging" do
    result = page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"))
      const [workerUrl, done] = arguments
      import("mind_graph/layout_client").then(({ createLayout }) => {
        const layout = createLayout({
          workerUrl, d3Url: "/assets/no-such-file.js",
          onTick: () => {}, onSettled: () => done({ settled: true }),
          onError: (message) => { layout.stop(); done({ error: message }) }
        })
        layout.start([{ id: 1, radius: 8 }], [])
      })
    JS

    assert result["error"].present?
  end
end
```

- [ ] **Step 3: Run it to see it fail**

Run: `bin/rails tailwindcss:build && PGGSSENCMODE=disable bin/rails test test/system/admin/mind_graph_modules_test.rb`
Expected: FAIL — the module `mind_graph/layout_client` cannot be resolved.

- [ ] **Step 4: Write the worker**

`app/javascript/mind_graph/layout_worker.js`:

```js
// The mind graph's layout, off the main thread (mind graph canvas spec §4.2):
// d3-force runs here and the page only draws, so zoom, pan and clicks stay
// smooth while a graph of a few thousand nodes is still settling.
//
// A MODULE worker started from its own asset URL. An import map does not
// apply inside a worker, so d3-force can't be imported by name: the page
// hands over the vendored file's URL (`d3Url`) with `start`, and it is
// imported once, dynamically. That file is one self-contained bundle.
//
// Messages in:  { type: "start", d3Url, nodes: [{ id, radius }], edges: [{ source, target }] }
//               { type: "filter", nodeIds: [...], edgeIndexes: [...] }
//               { type: "pin", id, x, y } / { type: "unpin", id }
// Messages out: { type: "tick", positions: Float32Array }   (transferred, not copied)
//               { type: "settled" }
//               { type: "error", message }
//
// `positions` always covers EVERY node given to `start`, in that order, two
// numbers each: a node the filter hides keeps its last place, so it comes
// back where it was.
//
// The simulation's own timer is stopped at once and it is stepped by hand:
// as many ticks as fit into SLICE_MS, one message, then a zero timeout so a
// `pin` or `filter` that arrived meanwhile is handled before the next slice.
const SLICE_MS = 12

let d3 = null
let simulation = null
let nodes = []
let edges = []
let running = false

self.onmessage = (event) => {
  handle(event.data).catch((error) => self.postMessage({ type: "error", message: String(error?.message || error) }))
}

async function handle(message) {
  if (message.type === "start") {
    d3 ||= await import(message.d3Url)
    start(message.nodes, message.edges)
  } else if (message.type === "filter") {
    filter(new Set(message.nodeIds), new Set(message.edgeIndexes))
  } else if (message.type === "pin") {
    const node = nodes.find((candidate) => candidate.id === message.id)
    if (!node) return
    node.fx = message.x
    node.fy = message.y
    simulation.alphaTarget(0.3)
    run()
  } else if (message.type === "unpin") {
    const node = nodes.find((candidate) => candidate.id === message.id)
    if (!node) return
    node.fx = null
    node.fy = null
    simulation.alphaTarget(0)
    run()
  }
}

function start(givenNodes, givenEdges) {
  nodes = givenNodes.map((node) => ({ id: node.id, radius: node.radius }))
  edges = givenEdges.map((edge, index) => ({ source: edge.source, target: edge.target, index }))
  simulation = d3.forceSimulation(nodes)
    // `distanceMax` bounds each node's repulsion to its surroundings: without
    // it every node pushes every other, which is what makes a large graph slow
    // and flings its outer nodes away.
    .force("charge", d3.forceManyBody().strength(-250).distanceMax(600))
    .force("link", d3.forceLink(edges.slice()).id((node) => node.id).distance(90))
    .force("x", d3.forceX(0).strength(0.04))
    .force("y", d3.forceY(0).strength(0.04))
    .force("collide", d3.forceCollide((node) => node.radius + 10))
    .stop()
  run()
}

function filter(nodeIds, edgeIndexes) {
  simulation.nodes(nodes.filter((node) => nodeIds.has(node.id)))
  simulation.force("link").links(edges.filter((edge) => edgeIndexes.has(edge.index)))
  simulation.alpha(0.8)
  run()
}

function run() {
  if (running) return
  running = true
  step()
}

function step() {
  const started = performance.now()
  const cooling = () => simulation.alpha() >= simulation.alphaMin()
  while (cooling() && performance.now() - started < SLICE_MS) simulation.tick()

  const positions = new Float32Array(nodes.length * 2)
  nodes.forEach((node, index) => {
    positions[index * 2] = node.x
    positions[index * 2 + 1] = node.y
  })
  self.postMessage({ type: "tick", positions }, [ positions.buffer ])

  if (cooling()) {
    setTimeout(step, 0)
  } else {
    running = false
    self.postMessage({ type: "settled" })
  }
}
```

- [ ] **Step 5: Write the client**

`app/javascript/mind_graph/layout_client.js`:

```js
// The page's side of the layout worker (`layout_worker.js`, which documents
// the messages). One worker per graph; `stop()` terminates it, and nothing it
// had in flight is delivered afterwards.
export function createLayout({ workerUrl, d3Url, onTick, onSettled, onError }) {
  const worker = new Worker(workerUrl, { type: "module" })
  let stopped = false

  worker.onmessage = ({ data }) => {
    if (stopped) return
    if (data.type === "tick") onTick(data.positions)
    else if (data.type === "settled") onSettled()
    else if (data.type === "error") onError(data.message)
  }
  // A worker that can't be fetched or parsed at all never runs `onmessage`.
  worker.onerror = (event) => {
    event.preventDefault()
    if (!stopped) onError(event.message || "the layout worker could not start")
  }

  return {
    start(nodes, edges) { worker.postMessage({ type: "start", d3Url, nodes, edges }) },
    filter(nodeIds, edgeIndexes) { worker.postMessage({ type: "filter", nodeIds, edgeIndexes }) },
    pin(id, x, y) { worker.postMessage({ type: "pin", id, x, y }) },
    unpin(id) { worker.postMessage({ type: "unpin", id }) },
    stop() {
      stopped = true
      worker.terminate()
    }
  }
}
```

- [ ] **Step 6: Run the test**

Run: `PGGSSENCMODE=disable bin/rails test test/system/admin/mind_graph_modules_test.rb`
Expected: PASS, 2 runs.

**If the first test cannot be made to pass** (the worker is refused, or the dynamic import fails in the test browser): stop and report BLOCKED with the browser's exact error. The fallback in the spec's §8 is a decision for the plan's owner, not for this task.

- [ ] **Step 7: The guards**

Run: `PGGSSENCMODE=disable bin/rails test test/integration/public_javascript_test.rb test/lib`
Expected: PASS. If `public_javascript_test.rb` lists admin-only prefixes (`ADMIN_ONLY`), add `mind_graph/` to it and run again.

- [ ] **Step 8: Commit**

```bash
git add config/importmap.rb app/javascript/mind_graph test/system/admin/mind_graph_modules_test.rb test/integration/public_javascript_test.rb
git commit -m "feat: the mind graph's layout runs in a module worker — the worker, its client, and the proof in the test browser"
```

---

### Task 2: `PostGraph::Global` and the shared builder

**Files:**
- Create: `app/queries/post_graph/builder.rb`, `app/queries/post_graph/global.rb`
- Modify: `app/queries/post_graph.rb` (add `CAP`)
- Test: `test/queries/post_graph/global_test.rb`

**Interfaces:**
- Produces: `PostGraph::CAP` (Integer), `PostGraph::MIN_TAGGED_POSTS` (existing).
- Produces: `PostGraph::Builder.new(locale:, url_for:).call(post_ids:, relations:, tag_links:, tag_counts:, min_tag_edges:, keep_tag: nil)` → `{ nodes:, tags:, edges: }`.
  - `post_ids`: Array of Integer, the posts to draw. `relations`: `[[post_id, related_post_id], …]`. `tag_links`: `[[tag_id, post_id], …]`. `tag_counts`: `{ tag_id => readable post count }`.
  - Node: `{ id:, title:, type:, colour_index:, status:, url:, degree: }`. Tag: `{ id: "tag-<id>", name:, count:, degree: }`. Edge: `{ source:, target:, kind: }`.
- Produces: `PostGraph::Global.call(actor:, url_for:, locale: Locales.default, cap: PostGraph::CAP)` → the builder's hash plus `total:`, `shown:`, `isolated:`.

`PostGraph` is still a class with its own `.call` in this task; the new classes nest under it. Do not change `PostGraph#call`.

- [ ] **Step 1: Write the failing tests**

`test/queries/post_graph/global_test.rb`:

```ruby
require "test_helper"

# `PostGraph::Global` (mind graph canvas spec §3.3): the best-connected
# readable posts up to a cap, their tags and edges, and what was left out.
class PostGraph::GlobalTest < ActiveSupport::TestCase
  def graph(actor: nil, cap: PostGraph::CAP) = PostGraph::Global.call(actor: actor, cap: cap, url_for: ->(post) { "/cs-studio/posts/#{post.id}" })

  def relate(a, b) = PostRelation.create!(post: a, related_post: b)

  test "a connected post is a node with its title, type, colour index, status, url and degree" do
    a = create_post(title: "Alpha", content_type: "resume_entry")
    b = create_post(title: "Beta")
    relate(a, b)

    node = graph[:nodes].find { |n| n[:id] == a.id }

    assert_equal({ id: a.id, title: "Alpha", type: "resume_entry", colour_index: ContentTypes.fetch("resume_entry").colour_index,
                   status: "live", url: "/cs-studio/posts/#{a.id}", degree: 1 }, node)
  end

  test "a post with no connection is left out and counted as isolated" do
    a = create_post(title: "A")
    b = create_post(title: "B")
    create_post(title: "Alone")
    relate(a, b)

    result = graph

    assert_equal [ a.id, b.id ], result[:nodes].map { |n| n[:id] }
    assert_equal 2, result[:total]
    assert_equal 2, result[:shown]
    assert_equal 1, result[:isolated]
  end

  test "a tag on two readable posts is a node, carries the readable count and its degree" do
    a = create_post(title: "A", tags: [ "shared" ])
    b = create_post(title: "B", tags: [ "shared" ])
    create_post(title: "C", tags: [ "lonely" ])
    tag = Tag.find_by!(name: "shared")

    result = graph

    assert_equal [ { id: "tag-#{tag.id}", name: "shared", count: 2, degree: 2 } ], result[:tags]
    assert_equal [ { source: a.id, target: "tag-#{tag.id}", kind: "tag" }, { source: b.id, target: "tag-#{tag.id}", kind: "tag" } ], result[:edges]
    assert_equal 1, result[:isolated], "a tag on one post connects nothing"
  end

  test "over the cap the best-connected posts are kept, and total says how many there were" do
    hub = create_post(title: "Hub")
    spokes = 4.times.map { |i| create_post(title: "Spoke #{i}") }
    spokes.each { |spoke| relate(hub, spoke) }
    relate(spokes[0], spokes[1])

    result = graph(cap: 3)

    assert_equal [ hub.id, spokes[0].id, spokes[1].id ].sort, result[:nodes].map { |n| n[:id] }.sort
    assert_equal 5, result[:total]
    assert_equal 3, result[:shown]
    assert result[:edges].all? { |edge| [ edge[:source], edge[:target] ].all? { |id| result[:nodes].any? { |n| n[:id] == id } } }, "an edge points at a post that was cut"
  end

  test "equal connection counts break by newest, then id, so the cut is stable" do
    posts = 4.times.map { |i| create_post(title: "P#{i}") }
    relate(posts[0], posts[1])
    relate(posts[2], posts[3])
    posts.each_with_index { |post, i| post.update_columns(updated_at: Time.zone.local(2026, 1, 1) + i.days) } # version: none (a test's own timestamps)

    assert_equal [ posts[2].id, posts[3].id ], graph(cap: 2)[:nodes].map { |n| n[:id] }
    assert_equal graph(cap: 2), graph(cap: 2)
  end

  test "a tag's count stays the readable number when the cap cuts some of its posts" do
    hub = create_post(title: "Hub", tags: [ "wide" ])
    others = 3.times.map { |i| create_post(title: "T#{i}", tags: [ "wide" ]) }
    relate(hub, others[0])

    tag = graph(cap: 2)[:tags].first

    assert_equal 4, tag[:count]
    assert_equal 2, tag[:degree]
  end

  test "an actor sees only readable posts, no edge to an unreadable one, and no count that includes one" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    own = 2.times.map { |i| create_post(title: "Own #{i}", tags: [ "t" ]).tap { |post| post.update_column(:author_id, users(:author).id) } } # version: none (a test's fixture set-up)
    other = create_post(title: "Other", tags: [ "t" ])
    relate(own[0], other)

    result = as(users(:author)) { graph(actor: users(:author)) }

    assert_equal own.map(&:id), result[:nodes].map { |n| n[:id] }
    assert_equal 2, result[:tags].first[:count]
    assert result[:edges].none? { |edge| edge[:source] == other.id || edge[:target] == other.id }
    assert_equal 2, result[:total]
  end

  test "a trashed post is no node and makes no tag shared" do
    a = create_post(title: "A", tags: [ "t" ])
    gone = create_post(title: "Gone", tags: [ "t" ])
    relate(a, gone)
    gone.update_column(:trashed_at, Time.current) # version: none (a test's fixture set-up)

    result = graph

    assert_empty result[:nodes]
    assert_empty result[:tags]
    assert_equal 1, result[:isolated]
  end

  test "no posts: empty lists and zero counts" do
    assert_equal({ nodes: [], tags: [], edges: [], total: 0, shown: 0, isolated: 0 }, graph)
  end

  test "the number of statements does not grow with the posts" do
    build = ->(count) do
      posts = count.times.map { |i| create_post(title: "N#{count}-#{i}", tags: [ "bulk" ]) }
      posts.each_cons(2) { |a, b| relate(a, b) }
    end
    build.call(3)
    few = capture_sql { graph }.size
    build.call(12)
    many = capture_sql { graph }.size

    assert_equal few, many
  end

  test "posts are loaded with only the columns a node needs" do
    a = create_post(title: "A")
    relate(a, create_post(title: "B"))

    statements = capture_sql { graph }

    assert statements.none? { |sql| sql.include?('"posts".*') }, "a whole post row was loaded:\n#{statements.grep(/"posts"/).join("\n")}"
  end
end
```

Check before running: `users(:author)` and `access_control_grants(:author_posts_read)` are the fixtures `test/integration/admin/access_control_test.rb` uses in `narrow_author_reads_to_own`; if a name differs, use that file's.

- [ ] **Step 2: Run to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/queries/post_graph/global_test.rb`
Expected: FAIL — `uninitialized constant PostGraph::Global`.

- [ ] **Step 3: Add the cap**

In `app/queries/post_graph.rb`, directly under `MIN_TAGGED_POSTS = 2`:

```ruby
  # The most posts one graph draws (mind graph canvas spec §3.3): beyond it the
  # global view keeps the best-connected, and a local view the nearest. Set
  # from the measurements in that spec's §7.
  CAP = 2_000
```

- [ ] **Step 4: Write the builder**

`app/queries/post_graph/builder.rb`:

```ruby
# The part `PostGraph::Global` and `PostGraph::Local` share (mind graph canvas
# spec §3.3): given the posts to draw and what connects them, the
# `{ nodes, tags, edges }` the page draws, each node with its `degree` -- the
# number of edges it has IN THIS RESPONSE, so size and label priority match
# what is on screen.
#
# The callers decide WHICH posts; this decides nothing about access. Every id
# handed in is already readable, and the rules that keep the graph from
# disclosing anything hold here because of what it is given:
# - an edge is made only between two posts in `post_ids`, or from a tag to one;
# - a tag's `count` is `tag_counts[tag_id]`, the number of READABLE posts
#   carrying it -- not the tag's true total, and not the smaller number drawn;
# - a tag is a node only when at least `MIN_TAGGED_POSTS` readable posts carry
#   it AND it has `min_tag_edges` edges here (two in the global view, where a
#   tag with one drawn post connects nothing; one in a local view, where a
#   post's own tags are its neighbours). `keep_tag` is the one exception: a
#   local view's focused tag is always a node.
#
# Two queries: the posts (only the columns a node is made from) and the tags'
# names.
class PostGraph
  class Builder
    COLUMNS = %i[id title content_type published_at].freeze

    def initialize(locale:, url_for:)
      @locale = locale
      @url_for = url_for
    end

    def call(post_ids:, relations:, tag_links:, tag_counts:, min_tag_edges:, keep_tag: nil)
      drawn = post_ids.to_set
      related = relations.select { |post_id, related_id| drawn.include?(post_id) && drawn.include?(related_id) }
      by_tag = tag_links.select { |_tag_id, post_id| drawn.include?(post_id) }.group_by(&:first)
      by_tag.select! do |tag_id, rows|
        tag_id == keep_tag || (tag_counts.fetch(tag_id, 0) >= MIN_TAGGED_POSTS && rows.size >= min_tag_edges)
      end
      names = Tag.where(id: by_tag.keys).pluck(:id, :name).to_h
      by_tag.select! { |tag_id, _rows| names.key?(tag_id) }

      degree = Hash.new(0)
      related.each { |post_id, related_id| degree[post_id] += 1; degree[related_id] += 1 }
      by_tag.each_value { |rows| rows.each { |_tag_id, post_id| degree[post_id] += 1 } }

      {
        nodes: nodes(post_ids, degree),
        tags: by_tag.map { |tag_id, rows| { id: "tag-#{tag_id}", name: names[tag_id], count: tag_counts.fetch(tag_id, rows.size), degree: rows.size } }
                    .sort_by { |tag| [ tag[:name].to_s.downcase, tag[:id] ] },
        edges: related.map { |post_id, related_id| { source: post_id, target: related_id, kind: "related" } } +
               by_tag.flat_map { |tag_id, rows| rows.map { |_tag_id, post_id| { source: post_id, target: "tag-#{tag_id}", kind: "tag" } } }
      }
    end

    private

    def nodes(post_ids, degree)
      Post.where(id: post_ids).select(*COLUMNS).order(:id).map do |post|
        {
          id: post.id,
          title: Locales.read(post, :title, locale: @locale),
          type: post.content_type,
          colour_index: post.definition&.colour_index,
          status: post.status,
          url: @url_for.call(post),
          degree: degree[post.id]
        }
      end
    end
  end
end
```

- [ ] **Step 5: Write the global query**

`app/queries/post_graph/global.rb`:

```ruby
# The whole site's graph, as far as one screen can draw it (mind graph canvas
# spec §3.3): the readable posts that have at least one connection, ranked by
# how many, and the best-connected `cap` of them.
#
# - A connection is a `PostRelation` (either direction) or a tag carried by at
#   least `MIN_TAGGED_POSTS` readable posts. That is decided BEFORE the cut,
#   among all readable posts: a tag's weight in the ranking doesn't depend on
#   which posts happen to survive it.
# - Ties break by newest `updated_at`, then id, so two requests cut the same.
# - A post with no connection is left out (spec §2, decision 6) and counted in
#   `isolated`. `total` is the connected posts, `shown` the ones in `nodes`.
#
# `actor:` is required, as everywhere: nothing draws the whole graph by
# forgetting to pass one. Everything is derived from the readable posts'
# ids, so nothing here can count or name a post outside the scope -- or a
# trashed one, which `AccessControl.scope` already leaves out.
#
# Cost: five queries whatever the size -- the readable ids with their
# timestamps, the relations, the tag links, and the builder's two.
class PostGraph
  class Global
    def self.call(...) = new(...).call

    def initialize(actor:, url_for:, locale: Locales.default, cap: CAP)
      @actor = actor
      @locale = locale
      @url_for = url_for
      @cap = cap
    end

    def call
      readable = AccessControl.scope(@actor, "posts.read", Post.all)
      stamps = readable.pluck(:id, :updated_at).to_h
      relations = PostRelation.where(post_id: readable.select(:id), related_post_id: readable.select(:id)).order(:id).pluck(:post_id, :related_post_id)
      tag_links = PostTag.where(post_id: readable.select(:id)).order(:tag_id, :post_id).pluck(:tag_id, :post_id)
      tag_counts = tag_links.group_by(&:first).transform_values(&:size)

      weight = Hash.new(0)
      relations.each { |post_id, related_id| weight[post_id] += 1; weight[related_id] += 1 }
      tag_links.each { |tag_id, post_id| weight[post_id] += 1 if tag_counts[tag_id] >= MIN_TAGGED_POSTS }

      kept = weight.keys.sort_by { |id| [ -weight[id], -stamps[id].to_f, id ] }.first(@cap)
      graph = Builder.new(locale: @locale, url_for: @url_for)
                     .call(post_ids: kept, relations: relations, tag_links: tag_links, tag_counts: tag_counts, min_tag_edges: MIN_TAGGED_POSTS)
      graph.merge(total: weight.size, shown: kept.size, isolated: stamps.size - weight.size)
    end
  end
end
```

- [ ] **Step 6: Run the tests**

Run: `PGGSSENCMODE=disable bin/rails test test/queries/post_graph/global_test.rb test/queries/post_graph_test.rb`
Expected: PASS. The old `post_graph_test.rb` must still pass unchanged.

If the tie-break test fails because `create_post` relations change `updated_at`, set the timestamps after creating the relations (the test already does).

- [ ] **Step 7: The guards**

Run: `PGGSSENCMODE=disable bin/rails test test/lib && bin/rubocop app/queries test/queries`
Expected: PASS, no offenses.

- [ ] **Step 8: Commit**

```bash
git add app/queries test/queries
git commit -m "feat: the global mind graph is the best-connected posts up to a cap — PostGraph::Global and the shared builder"
```

---

### Task 3: `PostGraph::Focus` and `PostGraph::Local`

**Files:**
- Create: `app/queries/post_graph/focus.rb`, `app/queries/post_graph/local.rb`
- Test: `test/queries/post_graph/focus_test.rb`, `test/queries/post_graph/local_test.rb`

**Interfaces:**
- Consumes: `PostGraph::Builder` (Task 2), `PostGraph::CAP`, `PostGraph::MIN_TAGGED_POSTS`.
- Produces: `PostGraph::Focus.find(actor:, post: nil, tag: nil, locale: Locales.default)` → `nil` when neither id is given, else a `PostGraph::Focus` with `kind` (`"post"` / `"tag"`), `id` (Integer), `title` (String) and `node_id` (`12` or `"tag-7"`). Raises `ActiveRecord::RecordNotFound` for an unreadable, trashed or unknown post, an unknown tag, and a tag no readable post carries. `post` wins when both are given.
- Produces: `PostGraph::Local.call(actor:, focus:, url_for:, depth: 1, locale: Locales.default, cap: PostGraph::CAP)` → the builder's hash plus `total:`, `shown:`, `focus: { kind:, id:, node_id:, title:, depth: }`. `depth` other than 2 is 1.

- [ ] **Step 1: Write the failing focus tests**

`test/queries/post_graph/focus_test.rb`:

```ruby
require "test_helper"

class PostGraph::FocusTest < ActiveSupport::TestCase
  test "neither id: no focus" do
    assert_nil PostGraph::Focus.find(actor: nil)
    assert_nil PostGraph::Focus.find(actor: nil, post: "", tag: " ")
  end

  test "a readable post is a focus with its title" do
    post = create_post(title: "Alpha")

    focus = PostGraph::Focus.find(actor: nil, post: post.id.to_s)

    assert_equal [ "post", post.id, "Alpha", post.id ], [ focus.kind, focus.id, focus.title, focus.node_id ]
  end

  test "a tag a readable post carries is a focus with its name" do
    create_post(title: "A", tags: [ "ruby" ])
    tag = Tag.find_by!(name: "ruby")

    focus = PostGraph::Focus.find(actor: nil, tag: tag.id)

    assert_equal [ "tag", tag.id, "ruby", "tag-#{tag.id}" ], [ focus.kind, focus.id, focus.title, focus.node_id ]
  end

  test "post wins when both are given" do
    post = create_post(title: "A", tags: [ "ruby" ])

    assert_equal "post", PostGraph::Focus.find(actor: nil, post: post.id, tag: Tag.find_by!(name: "ruby").id).kind
  end

  test "an unknown, trashed or unreadable post is not found" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    other = create_post(title: "Other")
    gone = create_post(title: "Gone")
    gone.update_column(:trashed_at, Time.current) # version: none (a test's fixture set-up)

    assert_raises(ActiveRecord::RecordNotFound) { PostGraph::Focus.find(actor: nil, post: 0) }
    assert_raises(ActiveRecord::RecordNotFound) { PostGraph::Focus.find(actor: nil, post: "abc") }
    assert_raises(ActiveRecord::RecordNotFound) { PostGraph::Focus.find(actor: nil, post: gone.id) }
    assert_raises(ActiveRecord::RecordNotFound) { as(users(:author)) { PostGraph::Focus.find(actor: users(:author), post: other.id) } }
  end

  test "an unknown tag, and a tag only unreadable or trashed posts carry, is not found" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    create_post(title: "Other", tags: [ "theirs" ])
    gone = create_post(title: "Gone", tags: [ "binned" ])
    gone.update_column(:trashed_at, Time.current) # version: none (a test's fixture set-up)
    unused = Tag.create!(name: "unused")

    assert_raises(ActiveRecord::RecordNotFound) { PostGraph::Focus.find(actor: nil, tag: 0) }
    assert_raises(ActiveRecord::RecordNotFound) { PostGraph::Focus.find(actor: nil, tag: unused.id) }
    assert_raises(ActiveRecord::RecordNotFound) { PostGraph::Focus.find(actor: nil, tag: Tag.find_by!(name: "binned").id) }
    assert_raises(ActiveRecord::RecordNotFound) { as(users(:author)) { PostGraph::Focus.find(actor: users(:author), tag: Tag.find_by!(name: "theirs").id) } }
  end
end
```

- [ ] **Step 2: Run to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/queries/post_graph/focus_test.rb`
Expected: FAIL — `uninitialized constant PostGraph::Focus`.

- [ ] **Step 3: Write the focus**

`app/queries/post_graph/focus.rb`:

```ruby
# What a local graph is drawn around (mind graph canvas spec §3.1): one post
# or one tag, resolved from the request's `post=` / `tag=` for THIS viewer.
#
# Not found, never forbidden: a post outside the viewer's scope, a trashed
# post and an id that names nothing all raise `ActiveRecord::RecordNotFound`,
# and so does a tag no readable post carries -- a focus on it would say the
# tag exists and is in use somewhere the viewer can't look.
class PostGraph
  class Focus
    attr_reader :kind, :id, :title

    def self.find(actor:, post: nil, tag: nil, locale: Locales.default)
      readable = AccessControl.scope(actor, "posts.read", Post.all)
      if post.present?
        record = readable.find_by(id: Integer(post, exception: false)) or raise ActiveRecord::RecordNotFound
        new("post", record.id, Locales.read(record, :title, locale: locale))
      elsif tag.present?
        record = Tag.find_by(id: Integer(tag, exception: false)) or raise ActiveRecord::RecordNotFound
        raise ActiveRecord::RecordNotFound unless PostTag.where(tag_id: record.id, post_id: readable.select(:id)).exists?

        new("tag", record.id, record.name)
      end
    end

    def initialize(kind, id, title)
      @kind = kind
      @id = id
      @title = title.to_s
    end

    # The id the node carries in the graph's data.
    def node_id = kind == "tag" ? "tag-#{id}" : id
  end
end
```

`Integer(value, exception: false)` accepts an Integer or a String and answers `nil` for `"abc"`; check it against a String that carries spaces (`" 12 "` parses) and keep the behaviour.

- [ ] **Step 4: Run the focus tests**

Run: `PGGSSENCMODE=disable bin/rails test test/queries/post_graph/focus_test.rb`
Expected: PASS.

- [ ] **Step 5: Write the failing local tests**

`test/queries/post_graph/local_test.rb`:

```ruby
require "test_helper"

# `PostGraph::Local` (mind graph canvas spec §3.3): a post's or a tag's
# neighbourhood, one level per depth, over both kinds of connection.
class PostGraph::LocalTest < ActiveSupport::TestCase
  def local(focus, depth: 1, actor: nil, cap: PostGraph::CAP)
    PostGraph::Local.call(actor: actor, focus: focus, depth: depth, cap: cap, url_for: ->(post) { "/cs-studio/posts/#{post.id}" })
  end

  def post_focus(post, actor: nil) = PostGraph::Focus.find(actor: actor, post: post.id)
  def tag_focus(name, actor: nil) = PostGraph::Focus.find(actor: actor, tag: Tag.find_by!(name: name).id)
  def relate(a, b) = PostRelation.create!(post: a, related_post: b)
  def ids(result) = result[:nodes].map { |n| n[:id] }.sort
  def tag_names(result) = result[:tags].map { |t| t[:name] }.sort

  setup do
    #   centre -- near -- far -- beyond
    #   centre, cousin share "shared"; far, cousin share "outer"; centre alone has "solo"
    @centre = create_post(title: "Centre", tags: %w[shared solo])
    @near = create_post(title: "Near")
    @far = create_post(title: "Far", tags: %w[outer])
    @beyond = create_post(title: "Beyond")
    @cousin = create_post(title: "Cousin", tags: %w[shared outer])
    relate(@centre, @near)
    relate(@far, @near) # stored the other way round on purpose: relations read as undirected
    relate(@far, @beyond)
  end

  test "depth 1 from a post: its related posts and its shared tags, not the tags' other posts" do
    result = local(post_focus(@centre))

    assert_equal [ @centre.id, @near.id ].sort, ids(result)
    assert_equal %w[shared], tag_names(result), "a tag on one readable post is no node"
    assert_equal({ kind: "post", id: @centre.id, node_id: @centre.id, title: "Centre", depth: 1 }, result[:focus])
    assert_equal 2, result[:tags].first[:count], "the readable count, not the one drawn post"
    assert_equal 1, result[:tags].first[:degree]
  end

  test "depth 2 from a post adds the neighbours' neighbours and the tags' other posts" do
    result = local(post_focus(@centre), depth: 2)

    assert_equal [ @centre.id, @near.id, @far.id, @cousin.id ].sort, ids(result)
    assert_not_includes ids(result), @beyond.id
    assert_includes tag_names(result), "shared"
    assert_equal 2, result[:focus][:depth]
  end

  test "depth 1 from a tag: the posts that carry it; depth 2: their related posts and other tags" do
    one = local(tag_focus("shared"))
    two = local(tag_focus("shared"), depth: 2)

    assert_equal [ @centre.id, @cousin.id ].sort, ids(one)
    assert_equal %w[shared], tag_names(one)
    assert_equal [ @centre.id, @cousin.id, @near.id ].sort, ids(two)
    assert_equal %w[outer shared], tag_names(two)
    assert_equal "tag-#{Tag.find_by!(name: "shared").id}", two[:focus][:node_id]
  end

  test "a focused tag is a node even with one readable post" do
    result = local(tag_focus("solo"))

    assert_equal [ @centre.id ], ids(result)
    assert_equal %w[solo], tag_names(result)
    assert_equal 1, result[:tags].first[:count]
  end

  test "a depth other than 2 is 1" do
    assert_equal 1, local(post_focus(@centre), depth: 7)[:focus][:depth]
    assert_equal 1, local(post_focus(@centre), depth: "x")[:focus][:depth]
    assert_equal 2, local(post_focus(@centre), depth: "2")[:focus][:depth]
  end

  test "every edge is between two drawn nodes, and degrees count them" do
    result = local(post_focus(@centre), depth: 2)
    node_ids = ids(result) + result[:tags].map { |t| t[:id] }

    assert result[:edges].all? { |edge| node_ids.include?(edge[:source]) && node_ids.include?(edge[:target]) }
    centre = result[:nodes].find { |n| n[:id] == @centre.id }
    assert_equal result[:edges].count { |edge| edge[:source] == @centre.id || edge[:target] == @centre.id }, centre[:degree]
  end

  test "over the cap the focus stays, nearer posts come first, and total says how many there were" do
    result = local(post_focus(@centre), depth: 2, cap: 2)

    assert_equal [ @centre.id, @near.id ].sort, ids(result)
    assert_equal 4, result[:total]
    assert_equal 2, result[:shown]
  end

  test "an unreadable or trashed neighbour is no node, no edge, and not in a tag's count" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    [ @centre, @near ].each { |post| post.update_column(:author_id, users(:author).id) } # version: none (a test's fixture set-up)

    result = as(users(:author)) { local(post_focus(@centre, actor: users(:author)), depth: 2, actor: users(:author)) }

    assert_equal [ @centre.id, @near.id ].sort, ids(result)
    assert_empty result[:tags], "'shared' has one readable post for this viewer"

    @near.update_column(:trashed_at, Time.current) # version: none (a test's fixture set-up)
    assert_equal [ @centre.id ], ids(local(post_focus(@centre)))
  end

  test "the number of statements depends on the depth, not on the neighbourhood's size" do
    few = capture_sql { local(post_focus(@centre), depth: 2) }.size
    6.times { |i| relate(@centre, create_post(title: "More #{i}", tags: %w[shared])) }
    many = capture_sql { local(post_focus(@centre), depth: 2) }.size

    assert_equal few, many
  end
end
```

- [ ] **Step 6: Run to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/queries/post_graph/local_test.rb`
Expected: FAIL — `uninitialized constant PostGraph::Local`.

- [ ] **Step 7: Write the local query**

`app/queries/post_graph/local.rb`:

```ruby
# One post's or one tag's neighbourhood (mind graph canvas spec §3.3). The
# graph is walked as it is drawn: posts and tags are nodes, a `PostRelation`
# joins two posts and a tag joins the posts carrying it. Each depth level
# takes one step outward:
#
#   from a post: its related posts and its tags are depth 1;
#                their related posts, their tags' posts and so on are depth 2.
#   from a tag:  the posts carrying it are depth 1;
#                their related posts and their other tags are depth 2.
#
# Only readable posts are ever stepped onto (`readable`), so an unreadable or
# trashed post is neither a node nor a bridge to what lies behind it. A tag
# reached by the walk becomes a node by `Builder`'s rule: at least two
# READABLE posts carry it (its `count`), and one of them is drawn. The focused
# tag is always a node.
#
# Capped like the global view: a tag on thousands of posts is its own
# explosion. Over the cap the focus is kept first, then nearer posts before
# farther ones, and among equals the better connected.
#
# Cost: three queries per depth level (the relations touching the frontier,
# the frontier posts' tags, the frontier tags' posts) plus five whatever the
# size -- never one per node.
class PostGraph
  class Local
    def self.call(...) = new(...).call

    def initialize(actor:, focus:, url_for:, depth: 1, locale: Locales.default, cap: CAP)
      @actor = actor
      @focus = focus
      @url_for = url_for
      @depth = depth.to_s == "2" ? 2 : 1
      @locale = locale
      @cap = cap
    end

    def call
      @readable = AccessControl.scope(@actor, "posts.read", Post.all).select(:id)
      walk

      post_ids = @posts.keys
      relations = PostRelation.where(post_id: post_ids, related_post_id: post_ids).order(:id).pluck(:post_id, :related_post_id)
      tag_links = PostTag.where(tag_id: @tags.keys, post_id: post_ids).order(:tag_id, :post_id).pluck(:tag_id, :post_id)
      tag_counts = PostTag.where(tag_id: @tags.keys, post_id: @readable).group(:tag_id).count

      kept = cut(post_ids, relations, tag_links)
      graph = Builder.new(locale: @locale, url_for: @url_for)
                     .call(post_ids: kept, relations: relations, tag_links: tag_links, tag_counts: tag_counts,
                           min_tag_edges: 1, keep_tag: (@focus.id if @focus.kind == "tag"))
      graph.merge(total: post_ids.size, shown: kept.size,
                  focus: { kind: @focus.kind, id: @focus.id, node_id: @focus.node_id, title: @focus.title, depth: @depth })
    end

    private

    # `@posts` and `@tags`: id => the depth it was first reached at.
    def walk
      @posts = {}
      @tags = {}
      post_frontier = []
      tag_frontier = []
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
        if post_frontier.any?
          touching = PostRelation.where(post_id: post_frontier).or(PostRelation.where(related_post_id: post_frontier))
          reached_posts.concat(touching.where(post_id: @readable, related_post_id: @readable).pluck(:post_id, :related_post_id).flatten)
          reached_tags.concat(PostTag.where(post_id: post_frontier).distinct.pluck(:tag_id))
        end
        reached_posts.concat(PostTag.where(tag_id: tag_frontier, post_id: @readable).distinct.pluck(:post_id)) if tag_frontier.any?

        post_frontier = reached_posts.uniq - @posts.keys
        tag_frontier = reached_tags.uniq - @tags.keys
        post_frontier.each { |id| @posts[id] = level }
        tag_frontier.each { |id| @tags[id] = level }
      end
    end

    def cut(post_ids, relations, tag_links)
      return post_ids if post_ids.size <= @cap

      weight = Hash.new(0)
      relations.each { |post_id, related_id| weight[post_id] += 1; weight[related_id] += 1 }
      tag_links.each { |_tag_id, post_id| weight[post_id] += 1 }
      post_ids.sort_by { |id| [ @posts[id], -weight[id], id ] }.first(@cap)
    end
  end
end
```

The three per-level queries must run whether or not a frontier is empty for the statement-count test to hold at every shape; if that test fails because a level skipped a query, drop the `if … any?` guards (an empty `IN ()` is a cheap statement) and keep the count constant per depth.

- [ ] **Step 8: Run the tests**

Run: `PGGSSENCMODE=disable bin/rails test test/queries/post_graph`
Expected: PASS.

- [ ] **Step 9: The guards**

Run: `PGGSSENCMODE=disable bin/rails test test/lib && bin/rubocop app/queries test/queries && bin/brakeman -q`
Expected: PASS, no offenses, zero warnings.

- [ ] **Step 10: Commit**

```bash
git add app/queries test/queries
git commit -m "feat: a local mind graph around a post or a tag — PostGraph::Focus and PostGraph::Local"
```

---

### Task 4: The data and search endpoints

The page still draws its SVG from the embedded data in this task; the endpoints are added beside it.

**Files:**
- Create: `app/queries/post_graph/search.rb`
- Modify: `config/routes.rb` (the `mind_graph` resource), `app/controllers/admin/mind_graph_controller.rb`
- Test: `test/queries/post_graph/search_test.rb`, `test/integration/admin/mind_graph_data_test.rb`, `test/integration/trash_visibility_test.rb`

**Interfaces:**
- Consumes: `PostGraph::Global.call`, `PostGraph::Focus.find`, `PostGraph::Local.call`.
- Produces: `PostGraph::Search.call(actor:, text:, locale: Locales.default, limit: 10)` → `[{ kind: "post" | "tag", id: Integer, label: String }]`, posts first.
- Produces routes `data_admin_mind_graph_path` → `GET <admin>/mind_graph/data` and `search_admin_mind_graph_path` → `GET <admin>/mind_graph/search`, both JSON.
- `data` answers the query's hash as JSON. `search` answers `[{ kind, id, label, url }]` where `url` is the row's local view (`admin_mind_graph_path(post: id)` or `(tag: id)`, with `admin_url_options`).

- [ ] **Step 1: Write the failing search test**

`test/queries/post_graph/search_test.rb`:

```ruby
require "test_helper"

class PostGraph::SearchTest < ActiveSupport::TestCase
  def search(text, actor: nil, limit: 10) = PostGraph::Search.call(actor: actor, text: text, limit: limit)

  test "posts by title and tags by name, posts first" do
    post = create_post(title: "Ruby notes", tags: [ "ruby" ])
    create_post(title: "Unrelated")
    tag = Tag.find_by!(name: "ruby")

    assert_equal [ { kind: "post", id: post.id, label: "Ruby notes" }, { kind: "tag", id: tag.id, label: "ruby" } ], search("rub")
  end

  test "a typed % or _ is a character, not a wildcard" do
    create_post(title: "Plain")

    assert_empty search("%")
    assert_empty search("_")
  end

  test "an unreadable or trashed post is not listed, nor a tag only such posts carry" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    create_post(title: "Secret plan", tags: [ "secret" ])
    gone = create_post(title: "Secret bin", tags: [ "secretbin" ])
    gone.update_column(:trashed_at, Time.current) # version: none (a test's fixture set-up)

    assert_empty as(users(:author)) { search("secret", actor: users(:author)) }
    assert_equal [ "Secret plan", "secret" ], search("secret").map { |row| row[:label] }
  end

  test "at most `limit` of each" do
    3.times { |i| create_post(title: "Many #{i}", tags: [ "many#{i}" ]) }

    rows = search("many", limit: 2)

    assert_equal 2, rows.count { |row| row[:kind] == "post" }
    assert_equal 2, rows.count { |row| row[:kind] == "tag" }
  end

  test "blank text finds nothing" do
    create_post(title: "A")

    assert_empty search("  ")
  end
end
```

- [ ] **Step 2: Run to see it fail**

Run: `PGGSSENCMODE=disable bin/rails test test/queries/post_graph/search_test.rb`
Expected: FAIL — `uninitialized constant PostGraph::Search`.

- [ ] **Step 3: Write the search**

`app/queries/post_graph/search.rb`:

```ruby
# The mind graph's search field (mind graph canvas spec §3.5): readable posts
# by title (in any language) and tags by name, up to `limit` of each. It is
# how a post the capped global view doesn't draw is reached. A tag is listed
# only when a readable post carries it, the same rule `Focus` applies -- so a
# result never leads to a 404, and never names a tag the viewer can't see used.
class PostGraph
  class Search
    def self.call(...) = new(...).call

    def initialize(actor:, text:, locale: Locales.default, limit: 10)
      @actor = actor
      @text = text.to_s.strip
      @locale = locale
      @limit = limit
    end

    def call
      return [] if @text.empty?

      readable = AccessControl.scope(@actor, "posts.read", Post.all)
      posts = readable.title_matching_any_locale(@text).order(:id).limit(@limit).select(:id, :title)
      tags = Tag.name_containing(@text).where(id: PostTag.where(post_id: readable.select(:id)).select(:tag_id))
                .name_starting_first(@text).by_name.limit(@limit).pluck(:id, :name)

      posts.map { |post| { kind: "post", id: post.id, label: Locales.read(post, :title, locale: @locale) } } +
        tags.map { |id, name| { kind: "tag", id: id, label: name } }
    end
  end
end
```

Read `app/models/tag.rb` first and use its scopes by their real names and arities (`name_containing`, `name_starting_first`, `by_name`).

- [ ] **Step 4: Run it**

Run: `PGGSSENCMODE=disable bin/rails test test/queries/post_graph/search_test.rb`
Expected: PASS.

- [ ] **Step 5: Write the failing endpoint tests**

`test/integration/admin/mind_graph_data_test.rb`:

```ruby
require "test_helper"

# The mind graph's two JSON endpoints (mind graph canvas spec §3.1): the
# graph's data, global or around a focus, and the search field's rows. Same
# permission and scope as the screen.
class Admin::MindGraphDataTest < ActionDispatch::IntegrationTest
  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  def data = response.parsed_body

  test "an unauthenticated request is redirected to sign-in" do
    get "/cs-studio/mind_graph/data"
    assert_redirected_to "/cs-studio/sign-in"
    get "/cs-studio/mind_graph/search", params: { q: "a" }
    assert_redirected_to "/cs-studio/sign-in"
  end

  test "with no focus: the global graph, with totals" do
    sign_in_as(users(:one))
    a = create_post(title: "A")
    b = create_post(title: "B")
    create_post(title: "Alone")
    PostRelation.create!(post: a, related_post: b)

    get "/cs-studio/mind_graph/data"

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal [ a.id, b.id ], data["nodes"].map { |n| n["id"] }
    assert_equal [ 2, 2, 1 ], data.values_at("total", "shown", "isolated")
    assert_equal "/cs-studio/posts/#{a.id}", data["nodes"].first["url"]
    assert_nil data["focus"]
  end

  test "post= and depth= answer that post's neighbourhood" do
    sign_in_as(users(:one))
    a = create_post(title: "A")
    b = create_post(title: "B")
    c = create_post(title: "C")
    PostRelation.create!(post: a, related_post: b)
    PostRelation.create!(post: b, related_post: c)

    get "/cs-studio/mind_graph/data", params: { post: a.id }
    assert_equal [ a.id, b.id ], data["nodes"].map { |n| n["id"] }
    assert_equal({ "kind" => "post", "id" => a.id, "node_id" => a.id, "title" => "A", "depth" => 1 }, data["focus"])

    get "/cs-studio/mind_graph/data", params: { post: a.id, depth: 2 }
    assert_equal [ a.id, b.id, c.id ], data["nodes"].map { |n| n["id"] }
  end

  test "tag= answers that tag's neighbourhood" do
    sign_in_as(users(:one))
    a = create_post(title: "A", tags: [ "t" ])
    tag = Tag.find_by!(name: "t")

    get "/cs-studio/mind_graph/data", params: { tag: tag.id }

    assert_equal [ a.id ], data["nodes"].map { |n| n["id"] }
    assert_equal "tag-#{tag.id}", data["focus"]["node_id"]
  end

  test "an unknown, trashed or unreadable focus is 404" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    other = create_post(title: "Other")
    gone = create_post(title: "Gone")
    gone.update_column(:trashed_at, Time.current) # version: none (a test's fixture set-up)
    sign_in_as(users(:author))

    [ { post: 0 }, { post: other.id }, { post: gone.id }, { tag: 0 } ].each do |params|
      get "/cs-studio/mind_graph/data", params: params
      assert_response :not_found, "expected 404 for #{params}"
    end
  end

  test "editor urls keep the editing language" do
    sign_in_as(users(:one))
    with_locales(%w[en de], default: "en")
    a = create_post(title: "A")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))

    get "/cs-studio/mind_graph/data", params: { locale: "de" }

    assert_equal "/cs-studio/posts/#{a.id}?locale=de", data["nodes"].first["url"]
  end

  test "a viewer without posts.read is refused, as on the screen itself" do
    sign_in_as(users(:editor_branch))

    get "/cs-studio/mind_graph/data"
    assert_response :forbidden
    get "/cs-studio/mind_graph/search", params: { q: "a" }
    assert_response :forbidden
  end

  test "search answers rows with the url of each row's local view" do
    sign_in_as(users(:one))
    post = create_post(title: "Ruby notes", tags: [ "ruby" ])
    tag = Tag.find_by!(name: "ruby")

    get "/cs-studio/mind_graph/search", params: { q: "rub" }

    assert_equal [
      { "kind" => "post", "id" => post.id, "label" => "Ruby notes", "url" => "/cs-studio/mind_graph?post=#{post.id}" },
      { "kind" => "tag", "id" => tag.id, "label" => "ruby", "url" => "/cs-studio/mind_graph?tag=#{tag.id}" }
    ], data

    get "/cs-studio/mind_graph/search"
    assert_equal [], data
  end
end
```

`users(:editor_branch)` is the account `test/integration/admin/access_control_test.rb` uses for "may not read posts" (it is refused `/cs-studio/posts`); confirm there that it is refused `/cs-studio/mind_graph` too, and assert the same status that file asserts.

- [ ] **Step 6: Run to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/integration/admin/mind_graph_data_test.rb`
Expected: FAIL — no route matches `/cs-studio/mind_graph/data`.

- [ ] **Step 7: Routes**

In `config/routes.rb` replace `resource :mind_graph, only: :show, controller: :mind_graph` with:

```ruby
    # `data` and `search` are the screen's own JSON reads (mind graph canvas
    # spec §3.1): the graph, global or around `post=` / `tag=`, and the search
    # field's rows.
    resource :mind_graph, only: :show, controller: :mind_graph do
      get :data, defaults: { format: :json }
      get :search, defaults: { format: :json }
    end
```

Read the comments in `routes.rb` about `format: false` first; these are admin routes and are not under the public constraint, but confirm with `bin/rails routes -g mind_graph` that the three routes exist as `admin_mind_graph`, `data_admin_mind_graph` and `search_admin_mind_graph`.

- [ ] **Step 8: Controller**

Replace the body of `app/controllers/admin/mind_graph_controller.rb`'s class with (keep and extend the class comment: say that `data` and `search` are JSON reads with the screen's own permission and scope, and that a focus the viewer may not see is not found):

```ruby
  class MindGraphController < BaseController
    before_action -> { require_permission("posts.read") }

    def show
      @graph = PostGraph.call(actor: Current.actor, locale: admin_locale, url_for: editor_url)
    end

    def data
      focus = PostGraph::Focus.find(actor: Current.actor, post: params[:post], tag: params[:tag], locale: admin_locale)
      graph =
        if focus
          PostGraph::Local.call(actor: Current.actor, focus: focus, depth: params[:depth], locale: admin_locale, url_for: editor_url)
        else
          PostGraph::Global.call(actor: Current.actor, locale: admin_locale, url_for: editor_url)
        end
      render json: graph
    end

    def search
      rows = PostGraph::Search.call(actor: Current.actor, text: params[:q], locale: admin_locale)
      render json: rows.map { |row| row.merge(url: admin_mind_graph_path(row[:kind] => row[:id], **admin_url_options)) }
    end

    private

    def editor_url = ->(post) { admin_post_path(post, **admin_url_options) }
  end
```

`ActiveRecord::RecordNotFound` must come out as a 404: check how `Admin::BaseController` already answers it for another screen and rely on that; do not add a rescue here unless nothing does.

- [ ] **Step 9: Run the endpoint tests**

Run: `PGGSSENCMODE=disable bin/rails test test/integration/admin/mind_graph_data_test.rb test/integration/admin/mind_graph_test.rb`
Expected: PASS (the old page test included).

- [ ] **Step 10: Trash visibility**

In `test/integration/trash_visibility_test.rb`, in the test that already requests `/cs-studio/mind_graph` after `PostRelation.create!(post: @kept_post, related_post: @gone_post)`, add after its last assertion:

```ruby
    get "/cs-studio/mind_graph/data"
    assert_not_includes response.parsed_body["nodes"].map { |n| n["id"] }, @gone_post.id
    get "/cs-studio/mind_graph/data", params: { post: @gone_post.id }
    assert_response :not_found
    get "/cs-studio/mind_graph/data", params: { post: @kept_post.id }
    assert_equal [ @kept_post.id ], response.parsed_body["nodes"].map { |n| n["id"] }
    get "/cs-studio/mind_graph/search", params: { q: "gone" }
    assert_empty response.parsed_body
```

Run: `PGGSSENCMODE=disable bin/rails test test/integration/trash_visibility_test.rb`
Expected: PASS.

- [ ] **Step 11: The guards and commit**

Run: `PGGSSENCMODE=disable bin/rails test test/lib test/integration/admin && bin/rubocop && bin/brakeman -q`
Expected: PASS, no offenses, zero warnings.

```bash
git add config/routes.rb app/controllers/admin/mind_graph_controller.rb app/queries/post_graph/search.rb test
git commit -m "feat: the mind graph's data and search endpoints — global or around a focus, 404 outside the viewer's scope"
```

---

### Task 5: The pure modules — camera, hit test, labels

**Files:**
- Create: `app/javascript/mind_graph/camera.js`, `app/javascript/mind_graph/hit_test.js`, `app/javascript/mind_graph/labels.js`
- Test: `test/system/admin/mind_graph_modules_test.rb` (extend)

**Interfaces** (all pure; a camera is a plain object `{ k, tx, ty }`, screen = graph × k + t):
- `camera.js`: `MIN_ZOOM = 0.05`, `MAX_ZOOM = 4`, `identity()`, `toScreen(camera, x, y) → [sx, sy]`, `toGraph(camera, sx, sy) → [x, y]`, `zoomAt(camera, sx, sy, factor) → camera`, `panBy(camera, dx, dy) → camera`, `bounds(positions, indexes) → { minX, minY, maxX, maxY } | null`, `fit(bounds, width, height, padding = 40) → camera`.
- `hit_test.js`: `nodeAt({ positions, indexes, radii, camera, sx, sy, slack = 4 }) → index | -1` (the nearest hit; `radii[index]` is the node's radius in screen pixels, which does not scale with zoom).
- `labels.js`: `LABEL_BUDGET = 40`, `chooseLabels({ order, positions, widths, radii, camera, width, height, always }) → [{ index, alpha, x, y }]`.
  - `order`: visible node indexes, highest degree first. `widths[index]`: the label's width in screen pixels. `always`: a `Set` of indexes labelled whatever the zoom.
  - `x`, `y`: the label's screen position (left edge, text middle). `alpha` in (0, 1].

- [ ] **Step 1: Add a helper and the failing tests**

In `test/system/admin/mind_graph_modules_test.rb`, add as a private method:

```ruby
  private

  # Imports a module of the page's import map and answers `expression`, in
  # which the module is `m`.
  def js_module(path, expression)
    page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import(#{path.to_json}).then((m) => done(#{expression}))
    JS
  end
```

and these tests above `private`:

```ruby
  test "camera: graph and screen coordinates convert both ways" do
    assert_equal [ 30, 50 ], js_module("mind_graph/camera", "m.toScreen({ k: 2, tx: 10, ty: 20 }, 10, 15)")
    assert_equal [ 10, 15 ], js_module("mind_graph/camera", "m.toGraph({ k: 2, tx: 10, ty: 20 }, 30, 50)")
  end

  test "camera: zooming keeps the point under the pointer where it is, and stops at the limits" do
    kept = js_module("mind_graph/camera", "(() => { const c = m.zoomAt(m.identity(), 100, 80, 2); return [c.k, ...m.toScreen(c, 100, 80)] })()")
    assert_equal [ 2, 100, 80 ], kept

    assert_equal 4, js_module("mind_graph/camera", "m.zoomAt(m.identity(), 0, 0, 1000).k")
    assert_in_delta 0.05, js_module("mind_graph/camera", "m.zoomAt(m.identity(), 0, 0, 0.000001).k")
  end

  test "camera: panning moves by screen pixels" do
    assert_equal({ "k" => 2, "tx" => 15, "ty" => 17 }, js_module("mind_graph/camera", "m.panBy({ k: 2, tx: 10, ty: 20 }, 5, -3)"))
  end

  test "camera: bounds cover the given nodes only, and are null for none" do
    assert_equal({ "minX" => -10, "minY" => 0, "maxX" => 30, "maxY" => 40 },
      js_module("mind_graph/camera", "m.bounds(new Float32Array([-10, 0, 30, 40, 999, 999]), [0, 1])"))
    assert_nil js_module("mind_graph/camera", "m.bounds(new Float32Array([1, 2]), [])")
  end

  test "camera: fit puts every corner inside the padded box and the middle in the middle" do
    result = js_module("mind_graph/camera", <<~JS)
      (() => {
        const box = { minX: -500, minY: -100, maxX: 500, maxY: 100 }
        const c = m.fit(box, 800, 600)
        return { k: c.k, topLeft: m.toScreen(c, box.minX, box.minY), bottomRight: m.toScreen(c, box.maxX, box.maxY), middle: m.toScreen(c, 0, 0) }
      })()
    JS

    assert_in_delta 0.72, result["k"], 0.001
    assert_in_delta 40, result["topLeft"][0], 0.01
    assert_in_delta 760, result["bottomRight"][0], 0.01
    assert_equal [ 400, 300 ], result["middle"].map(&:round)
    assert_operator result["topLeft"][1], :>=, 40
  end

  # Review focus 5: one node, or all nodes at one point.
  test "camera: fitting a single point does not divide by zero or zoom past 1.5" do
    result = js_module("mind_graph/camera", "(() => { const c = m.fit({ minX: 7, minY: 7, maxX: 7, maxY: 7 }, 800, 600); return [c.k, ...m.toScreen(c, 7, 7)] })()")

    assert_equal [ 1.5, 400, 300 ], result
    assert_equal({ "k" => 1, "tx" => 400, "ty" => 300 }, js_module("mind_graph/camera", "m.fit(null, 800, 600)"))
  end

  test "hit test: the nearest node within its radius plus slack, or none" do
    hit = ->(sx, sy) do
      js_module("mind_graph/hit_test", "m.nodeAt({ positions: new Float32Array([0, 0, 100, 0, 104, 0]), indexes: [0, 1, 2], radii: [8, 8, 8], camera: { k: 1, tx: 0, ty: 0 }, sx: #{sx}, sy: #{sy} })")
    end

    assert_equal 0, hit.call(3, 3)
    assert_equal 0, hit.call(11, 0), "inside the 4px slack"
    assert_equal(-1, hit.call(13, 0))
    assert_equal 2, hit.call(103, 0), "two overlap: the nearer centre wins"
    assert_equal 1, hit.call(101, 0)
  end

  test "hit test: a hidden node is not hit, and the radius does not grow with zoom" do
    assert_equal(-1, js_module("mind_graph/hit_test", "m.nodeAt({ positions: new Float32Array([0, 0]), indexes: [], radii: [8], camera: { k: 1, tx: 0, ty: 0 }, sx: 0, sy: 0 })"))
    assert_equal(-1, js_module("mind_graph/hit_test", "m.nodeAt({ positions: new Float32Array([0, 0]), indexes: [0], radii: [8], camera: { k: 4, tx: 0, ty: 0 }, sx: 20, sy: 0 })"))
  end

  test "labels: zoomed out only the first of the order are labelled, zoomed in more are" do
    count = ->(k) do
      js_module("mind_graph/labels", <<~JS)
        (() => {
          const n = 400
          const positions = new Float32Array(n * 2)
          for (let i = 0; i < n; i++) { positions[i * 2] = (i % 20) * 400; positions[i * 2 + 1] = Math.floor(i / 20) * 400 }
          const order = Array.from({ length: n }, (_, i) => i)
          return m.chooseLabels({ order, positions, widths: new Array(n).fill(60), radii: new Array(n).fill(8),
            camera: { k: #{k}, tx: 0, ty: 0 }, width: 100000, height: 100000, always: new Set() }).map((label) => label.index)
        })()
      JS
    end

    few = count.call(0.5)
    more = count.call(2)

    assert_equal (0...few.size).to_a, few, "the best-connected come first"
    assert_operator few.size, :<, 20
    assert_operator more.size, :>, few.size * 4
  end

  test "labels: a label that would overlap a better-connected node's is left out" do
    labelled = js_module("mind_graph/labels", <<~JS)
      m.chooseLabels({ order: [0, 1, 2], positions: new Float32Array([0, 0, 10, 2, 0, 200]), widths: [80, 80, 80], radii: [8, 8, 8],
        camera: { k: 1, tx: 100, ty: 100 }, width: 1000, height: 1000, always: new Set() }).map((label) => label.index)
    JS

    assert_equal [ 0, 2 ], labelled
  end

  test "labels: the always set is labelled at any zoom, at full strength, and first" do
    labels = js_module("mind_graph/labels", <<~JS)
      m.chooseLabels({ order: [0, 1, 2], positions: new Float32Array([0, 0, 10, 2, 0, 200]), widths: [80, 80, 80], radii: [8, 8, 8],
        camera: { k: 0.05, tx: 100, ty: 100 }, width: 1000, height: 1000, always: new Set([1]) })
    JS

    assert_equal 1, labels.first["index"]
    assert_equal 1, labels.first["alpha"]
  end

  test "labels: a node outside the canvas gets no label, and a label sits right of its node" do
    labels = js_module("mind_graph/labels", <<~JS)
      m.chooseLabels({ order: [0, 1], positions: new Float32Array([50, 50, 5000, 50]), widths: [80, 80], radii: [8, 8],
        camera: { k: 1, tx: 0, ty: 0 }, width: 300, height: 300, always: new Set([1]) })
    JS

    assert_equal [ 0 ], labels.map { |label| label["index"] }
    assert_equal [ 62, 50 ], labels.first.values_at("x", "y")
  end
```

- [ ] **Step 2: Run to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/system/admin/mind_graph_modules_test.rb`
Expected: the new tests FAIL (the modules cannot be resolved); Task 1's two pass.

- [ ] **Step 3: Write the camera**

`app/javascript/mind_graph/camera.js`:

```js
// The mind graph's camera (mind graph canvas spec §4.4): where the graph sits
// on the canvas. A plain object `{ k, tx, ty }` -- screen = graph * k + t --
// and pure functions that answer a new one, so a zoom or a pan is a value the
// redraw compares, and all of it can be checked without a canvas.
export const MIN_ZOOM = 0.05
export const MAX_ZOOM = 4
// "Fit all" never zooms a small graph in further than this: three nodes
// stretched over the whole box would be drawn as three huge gaps.
const MAX_FIT_ZOOM = 1.5

const clamp = (value, low, high) => Math.max(low, Math.min(high, value))

export function identity() {
  return { k: 1, tx: 0, ty: 0 }
}

export function toScreen(camera, x, y) {
  return [ x * camera.k + camera.tx, y * camera.k + camera.ty ]
}

export function toGraph(camera, sx, sy) {
  return [ (sx - camera.tx) / camera.k, (sy - camera.ty) / camera.k ]
}

// Zooms by `factor` around the screen point (sx, sy): what is under the
// pointer stays under it.
export function zoomAt(camera, sx, sy, factor) {
  const k = clamp(camera.k * factor, MIN_ZOOM, MAX_ZOOM)
  const ratio = k / camera.k
  return { k, tx: sx - (sx - camera.tx) * ratio, ty: sy - (sy - camera.ty) * ratio }
}

export function panBy(camera, dx, dy) {
  return { k: camera.k, tx: camera.tx + dx, ty: camera.ty + dy }
}

// The box around the nodes at `indexes`; null when there are none.
export function bounds(positions, indexes) {
  if (indexes.length === 0) return null

  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
  for (const index of indexes) {
    const x = positions[index * 2], y = positions[index * 2 + 1]
    if (x < minX) minX = x
    if (x > maxX) maxX = x
    if (y < minY) minY = y
    if (y > maxY) maxY = y
  }
  return { minX, minY, maxX, maxY }
}

// The camera that shows the whole box with `padding` pixels around it, its
// middle in the middle of the canvas. A box with no extent (one node, or
// every node at one point) has nothing to scale by: it is centred at the
// largest fit zoom.
export function fit(box, width, height, padding = 40) {
  if (!box) return { k: 1, tx: width / 2, ty: height / 2 }

  const spanX = box.maxX - box.minX
  const spanY = box.maxY - box.minY
  const roomX = Math.max(width - padding * 2, 1)
  const roomY = Math.max(height - padding * 2, 1)
  const k = clamp(Math.min(spanX > 0 ? roomX / spanX : Infinity, spanY > 0 ? roomY / spanY : Infinity), MIN_ZOOM, MAX_FIT_ZOOM)
  return { k, tx: width / 2 - ((box.minX + box.maxX) / 2) * k, ty: height / 2 - ((box.minY + box.maxY) / 2) * k }
}
```

- [ ] **Step 4: Write the hit test**

`app/javascript/mind_graph/hit_test.js`:

```js
// The node under a screen point (mind graph canvas spec §4.1). A linear scan
// over the visible nodes: at the cap that is 2,000 distance checks per pointer
// event, which needs no index. A node's radius is in SCREEN pixels -- nodes
// are drawn the same size at every zoom -- so the camera moves the centres
// only. `slack` makes a small dot easier to hit. Where two overlap, the
// nearer centre wins.
export function nodeAt({ positions, indexes, radii, camera, sx, sy, slack = 4 }) {
  let best = -1
  let bestDistance = Infinity
  for (const index of indexes) {
    const dx = positions[index * 2] * camera.k + camera.tx - sx
    const dy = positions[index * 2 + 1] * camera.k + camera.ty - sy
    const distance = Math.hypot(dx, dy)
    if (distance <= radii[index] + slack && distance < bestDistance) {
      best = index
      bestDistance = distance
    }
  }
  return best
}
```

- [ ] **Step 5: Write the labels**

`app/javascript/mind_graph/labels.js`:

```js
// Which labels the mind graph shows (mind graph canvas spec §5.2). Three rules:
//
// 1. HUBS FIRST. `order` is the visible nodes, best-connected first, and the
//    zoom decides how far down that list labels reach: LABEL_BUDGET of them at
//    zoom 1, growing with the square of the zoom (four times the area on
//    screen per node, four times the labels). The last quarter of that reach
//    fades, so a label arrives gradually as you zoom in.
// 2. NO OVERLAP. A label is placed only where no label placed before it is;
//    better-connected nodes place first, so the hub wins.
// 3. `always` -- the selection, its neighbours, the focus -- is labelled at
//    any zoom, at full strength, and places before everything else.
//
// A node outside the canvas gets no label. Answers `{ index, alpha, x, y }`,
// `x`/`y` the label's left edge and vertical middle in screen pixels: right
// of the node, as the SVG graph drew it.
export const LABEL_BUDGET = 40

const GAP = 4
const HEIGHT = 14

export function chooseLabels({ order, positions, widths, radii, camera, width, height, always }) {
  const reach = Math.max(1, Math.ceil(LABEL_BUDGET * camera.k * camera.k))
  const fadeFrom = reach * 0.75
  const placed = []
  const labels = []

  const place = (index, alpha) => {
    const sx = positions[index * 2] * camera.k + camera.tx
    const sy = positions[index * 2 + 1] * camera.k + camera.ty
    if (sx < 0 || sy < 0 || sx > width || sy > height) return

    const box = { left: sx + radii[index] + GAP, top: sy - HEIGHT / 2, right: sx + radii[index] + GAP + widths[index], bottom: sy + HEIGHT / 2 }
    if (placed.some((other) => box.left < other.right && box.right > other.left && box.top < other.bottom && box.bottom > other.top)) return

    placed.push(box)
    labels.push({ index, alpha, x: box.left, y: sy })
  }

  for (const index of order) if (always.has(index)) place(index, 1)

  let rank = 0
  for (const index of order) {
    if (rank >= reach) break
    const alpha = rank < fadeFrom ? 1 : 1 - (rank - fadeFrom) / (reach - fadeFrom)
    rank += 1
    if (!always.has(index) && alpha > 0) place(index, alpha)
  }
  return labels
}
```

- [ ] **Step 6: Run the tests**

Run: `PGGSSENCMODE=disable bin/rails test test/system/admin/mind_graph_modules_test.rb`
Expected: PASS. If a numeric expectation is off by the module's own documented constants (for example the label count at a zoom), check the test's arithmetic against the comment first; the comment is the contract.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/mind_graph test/system/admin/mind_graph_modules_test.rb
git commit -m "feat: the mind graph's camera, hit test and label rule — pure modules, tested in the browser"
```

---

### Task 6: The screen draws on a canvas

The switch. After this task the page holds no graph data, the SVG is gone, and the global view is drawn on a canvas with zoom, pan, fit, the filter and the messages. Selecting, the card, dragging a node, the local view's bar, search and the list come in Tasks 7–9; this task leaves their containers out.

**Files:**
- Create: `app/javascript/mind_graph/theme.js`, `app/javascript/mind_graph/renderer.js`, `app/javascript/mind_graph/input.js`, `app/javascript/mind_graph/app.js`, `config/locales/admin/mind_graph.en.yml`, `test/system/admin/mind_graph_test.rb`
- Rewrite: `app/javascript/controllers/admin/mind_graph_controller.js`, `app/views/admin/mind_graph/show.html.erb`, `app/queries/post_graph.rb` (class → module), `test/integration/admin/mind_graph_test.rb`
- Modify: `app/controllers/admin/mind_graph_controller.rb` (`show`), `config/importmap.rb` (d3-force no longer preloaded), `app/assets/tailwind/content-spiel.tailwind.css` (drop the SVG-only `.mg-*` rules the legend doesn't use), `test/integration/trash_visibility_test.rb`, `test/integration/admin/access_control_test.rb`, `test/integration/public_javascript_test.rb`, `test/system/admin/ai_assistant_and_graph_test.rb` (remove its mind graph tests), `test/lib/admin_i18n_test.rb` (`CONVERTED`)
- Delete: `test/queries/post_graph_test.rb`

**Interfaces:**
- Consumes: `createLayout` (Task 1), `camera.js`, `hit_test.js`, `labels.js` (Task 5), the data endpoint (Task 4).
- Produces: `mount(element) → { destroy() }` from `mind_graph/app`.
- Produces, on the controller's element, for tests and later tasks:
  - `data-state`: `loading` → `ready`, or `failed` (the data), or `worker-failed`.
  - `data-settled` (present once the layout cooled down), `data-nodes`, `data-edges` (visible counts), `data-zoom` (the camera's `k`, three decimals), `data-labelled` (the labelled nodes' ids, comma-separated).
  - `element.mindGraph.screenPosition(id) → { x, y } | null`, client coordinates of a visible node's centre.
- Produces `radiusFor(node) → number` from `mind_graph/renderer` (screen pixels; a post's radius or a tag's half side).
- Produces, inside `app.js`, a `state` object later tasks extend: `{ nodes, edges, positions, visibleNodes (indexes), visibleEdges (indexes), camera, selected (index or -1), neighbours (Set), focusIndex, theme }`, and `requestDraw()`.
- Element data attributes the view provides: `data-url` (the data endpoint with the request's own `post` / `tag` / `depth` / `locale`), `data-worker-url`, `data-d3-url`, `data-messages`.

- [ ] **Step 1: The locale file**

`config/locales/admin/mind_graph.en.yml`:

```yaml
# The Mind graph (docs/reference/i18n.md): `admin.mind_graph.show` is the
# view's own lazy-lookup scope, `script` what `mind_graph/app.js` and its
# modules show (handed over through the element's `data-messages`).
en:
  admin:
    mind_graph:
      show:
        title: "Mind graph"
        intro: "How your posts relate to each other. Scroll or pinch to zoom, drag to move."
        no_posts: "No posts yet."
        filter:
          legend: "Show connections"
          all: "All"
          related: "Related"
          tag: "Tags"
        canvas_label: "Post relationship graph"
        zoom_in: "Zoom in"
        zoom_out: "Zoom out"
        fit: "Fit all"
      script:
        loading: "Loading the graph…"
        load_failed: "The graph could not be loaded."
        retry: "Retry"
        worker_failed: "The graph can't be drawn in this browser."
        no_connections: "Link posts with Related posts, or give them shared tags, to see connections."
        capped: "Showing the %{shown} best-connected of %{total} posts."
        isolated:
          one: "%{count} post has no connections yet."
          other: "%{count} posts have no connections yet."
        summary: "%{posts} posts and tags, %{edges} connections."
```

- [ ] **Step 2: Write the failing system test**

`test/system/admin/mind_graph_test.rb`:

```ruby
require "application_system_test_case"

# The Mind graph (mind graph canvas spec): drawn on a canvas, so nothing on it
# is an element a test can find. The controller says what it shows through
# data attributes on its element (`data-state`, `data-settled`, `data-nodes`,
# `data-edges`, `data-zoom`, `data-labelled`) and answers a node's place on
# screen through `element.mindGraph.screenPosition(id)`, where a test then
# clicks for real.
class Admin::MindGraphSystemTest < ApplicationSystemTestCase
  GRAPH = "[data-controller~='admin--mind-graph']".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
  end

  test "the graph loads, settles, and the first view fits every node inside the canvas" do
    posts = 6.times.map { |i| create_post(title: "Post #{i}", tags: [ "shared" ]) }
    PostRelation.create!(post: posts[0], related_post: posts[1])

    visit admin_mind_graph_path
    await_graph

    assert_equal "7", graph["data-nodes"], "six posts and the tag they share"
    assert_equal "7", graph["data-edges"], "one related and six tag edges"
    canvas = find("#{GRAPH} canvas").native.node
    box = page.evaluate_script("(() => { const r = document.querySelector(#{"#{GRAPH} canvas".to_json}).getBoundingClientRect(); return [r.left, r.top, r.right, r.bottom] })()")
    (posts.map(&:id) + [ "tag-#{Tag.find_by!(name: "shared").id}" ]).each do |id|
      point = screen_position(id)
      assert point, "no position for #{id}"
      assert point["x"].between?(box[0], box[2]) && point["y"].between?(box[1], box[3]), "#{id} is outside the canvas: #{point} in #{box}"
    end
    assert canvas
  end

  test "the canvas is sharp: its bitmap is the box times the device pixel ratio" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_mind_graph_path
    await_graph

    sizes = page.evaluate_script("(() => { const c = document.querySelector(#{"#{GRAPH} canvas".to_json}); const r = c.getBoundingClientRect(); return [c.width, Math.round(r.width * window.devicePixelRatio)] })()")

    assert_equal sizes[1], sizes[0]
    assert_operator sizes[0], :>, 0
  end

  test "the zoom buttons zoom, more labels arrive, and Fit all brings everything back" do
    posts = 60.times.map { |i| create_post(title: "Post #{i}", tags: [ "t#{i % 6}" ]) }
    posts.each_cons(2) { |a, b| PostRelation.create!(post: a, related_post: b) }
    visit admin_mind_graph_path
    await_graph

    fitted = graph["data-zoom"].to_f
    labelled = graph["data-labelled"].split(",").size
    3.times { press "Zoom in" }
    await_js("Number(document.querySelector(#{GRAPH.to_json}).dataset.zoom) > #{fitted}")
    assert_operator graph["data-labelled"].split(",").size, :>=, labelled

    press "Zoom out"
    press "Fit all"
    await_js("Math.abs(Number(document.querySelector(#{GRAPH.to_json}).dataset.zoom) - #{fitted}) < 0.002")
  end

  test "the wheel zooms and a drag on empty space pans" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_mind_graph_path
    await_graph
    before = graph["data-zoom"].to_f
    first_id = Post.order(:id).first.id
    start = screen_position(first_id)
    corner = page.evaluate_script("(() => { const r = document.querySelector(#{"#{GRAPH} canvas".to_json}).getBoundingClientRect(); return [r.left + 12, r.top + 12] })()")

    mouse = page.driver.browser.mouse
    mouse.move(x: corner[0], y: corner[1])
    mouse.scroll_to(0, -240) rescue page.driver.browser.mouse.wheel(delta_y: -240)
    await_js("Number(document.querySelector(#{GRAPH.to_json}).dataset.zoom) !== #{before}")

    moved_from = screen_position(first_id)
    mouse.move(x: corner[0], y: corner[1])
    mouse.down
    mouse.move(x: corner[0] + 60, y: corner[1] + 40)
    mouse.up
    await_js("(() => { const p = document.querySelector(#{GRAPH.to_json}).mindGraph.screenPosition(#{first_id}); return Math.abs(p.x - #{moved_from["x"] + 60}) < 2 && Math.abs(p.y - #{moved_from["y"] + 40}) < 2 })()")
    assert start
  end

  test "the filter hands the layout only what is shown" do
    a, b, c = 3.times.map { |i| create_post(title: "P#{i}") }
    PostRelation.create!(post: a, related_post: b)
    [ b, c ].each { |post| PostTag.create!(post: post, tag: Tag.find_or_create_by!(name: "t")) }
    visit admin_mind_graph_path
    await_graph
    assert_equal [ "4", "3" ], [ graph["data-nodes"], graph["data-edges"] ]

    find("label", text: "Related").click
    await_graph
    assert_equal [ "2", "1" ], [ graph["data-nodes"], graph["data-edges"] ]
    assert_nil screen_position(c.id), "a hidden node has no place on screen"

    find("label", text: "Tags").click
    await_graph
    assert_equal [ "3", "2" ], [ graph["data-nodes"], graph["data-edges"] ]

    find("label", text: "All").click
    await_graph
    assert_equal [ "4", "3" ], [ graph["data-nodes"], graph["data-edges"] ]
  end

  test "posts with no connection are counted, not drawn" do
    a = create_post(title: "A")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    create_post(title: "Alone")
    visit admin_mind_graph_path
    await_graph

    assert_equal "2", graph["data-nodes"]
    assert_text "1 post has no connections yet."
  end

  test "posts but no connection at all: the hint, and nothing to draw" do
    create_post(title: "Alone")
    visit admin_mind_graph_path

    assert_selector "#{GRAPH}[data-state='ready']"
    assert_text "Link posts with Related posts, or give them shared tags, to see connections."
    assert_equal "0", graph["data-nodes"]
  end

  test "no readable post: 'No posts yet.' and no canvas" do
    visit admin_mind_graph_path

    assert_text "No posts yet."
    assert_no_selector "canvas"
  end

  test "the data can't be loaded: a message with Retry, which loads it" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_tags_path
    await_admin_controllers
    page.execute_script(<<~JS)
      const original = window.fetch
      window.failGraph = true
      window.fetch = (url, options) => (window.failGraph && String(url).includes("/mind_graph/data") ? Promise.reject(new TypeError("Failed to fetch")) : original(url, options))
    JS

    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    assert_selector "#{GRAPH}[data-state='failed']"
    assert_text "The graph could not be loaded."

    page.execute_script("window.failGraph = false")
    press "Retry"
    await_graph
    assert_no_text "The graph could not be loaded."
  end

  test "the worker can't start: a message, and an error in the console" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_tags_path
    await_admin_controllers
    page.execute_script("window.Worker = class { constructor() { throw new Error('no workers here') } }")

    expect_js_error(/layout worker|no workers here/) do
      within("nav[aria-label='Modules']") { click_link "Mind graph" }
      assert_selector "#{GRAPH}[data-state='worker-failed']"
      assert_text "The graph can't be drawn in this browser."
    end
  end

  # Review focus 2.
  test "leaving while the graph is loading or settling raises nothing and stops the worker" do
    posts = 40.times.map { |i| create_post(title: "P#{i}", tags: [ "t#{i % 4}" ]) }
    posts.each_cons(2) { |a, b| PostRelation.create!(post: a, related_post: b) }
    visit admin_tags_path
    await_admin_controllers
    page.execute_script(<<~JS)
      window.liveWorkers = 0
      const Real = window.Worker
      window.Worker = class extends Real {
        constructor(...args) { super(...args); window.liveWorkers += 1 }
        terminate() { window.liveWorkers -= 1; super.terminate() }
      }
    JS

    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    assert_selector GRAPH
    within("nav[aria-label='Modules']") { click_link "Tags" }
    assert_selector "h1", text: "Tags"
    await_js("window.liveWorkers === 0")

    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    await_graph
    within("nav[aria-label='Modules']") { click_link "Tags" }
    assert_selector "h1", text: "Tags"
    await_js("window.liveWorkers === 0")
  end

  # Review focus 3.
  test "Back to the graph draws it once, with the filter the control shows" do
    a, b = 2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    PostRelation.create!(post: a, related_post: b)
    visit admin_mind_graph_path
    await_graph
    find("label", text: "Related").click
    await_graph
    assert_equal "2", graph["data-nodes"]

    within("nav[aria-label='Modules']") { click_link "Tags" }
    assert_selector "h1", text: "Tags"
    page.go_back
    await_graph

    assert_equal "2", graph["data-nodes"], "the Related filter is still chosen, so the tag is not drawn"
    assert_selector "#{GRAPH} canvas", count: 1
  end

  # Review focus 4.
  test "a box that changes size is redrawn at the new size and still holds every node" do
    posts = 5.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_mind_graph_path
    await_graph
    original = page.current_window.size

    begin
      page.current_window.resize_to(900, 620)
      await_js("(() => { const c = document.querySelector(#{"#{GRAPH} canvas".to_json}); return c.width === Math.round(c.getBoundingClientRect().width * window.devicePixelRatio) })()")
      press "Fit all"
      box = page.evaluate_script("(() => { const r = document.querySelector(#{"#{GRAPH} canvas".to_json}).getBoundingClientRect(); return [r.left, r.top, r.right, r.bottom] })()")
      posts.each do |post|
        point = screen_position(post.id)
        assert point["x"].between?(box[0], box[2]) && point["y"].between?(box[1], box[3])
      end
    ensure
      page.current_window.resize_to(*original)
    end
  end

  test "the theme's colours are read from the page, and the graph is redrawn when the theme changes" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_mind_graph_path
    await_graph

    draws = page.evaluate_script("document.querySelector(#{GRAPH.to_json}).mindGraph.draws()")
    page.execute_script("document.documentElement.setAttribute('data-theme', document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark')")

    await_js("document.querySelector(#{GRAPH.to_json}).mindGraph.draws() > #{draws}")
  end

  private

  def graph = find(GRAPH)

  def await_graph
    assert_selector "#{GRAPH}[data-state='ready'][data-settled]", wait: 15
  end

  def screen_position(id)
    page.evaluate_script("document.querySelector(#{GRAPH.to_json}).mindGraph.screenPosition(#{id.to_json})")
  end
end
```

Two notes for the implementer of this test file:
- The wheel line guesses at Cuprite's API. Read `Ferrum::Mouse` in the installed gem (`bundle exec gem contents ferrum | grep mouse`) and use its real wheel/scroll method; remove the `rescue`.
- `page.go_back` on a Turbo screen restores a cached snapshot first; if the count assertion races the snapshot, wait with `await_graph` (already there) and nothing else. No `sleep`.

- [ ] **Step 3: Run to see it fail**

Run: `bin/rails tailwindcss:build && PGGSSENCMODE=disable bin/rails test test/system/admin/mind_graph_test.rb`
Expected: FAIL — the page still draws an SVG and has no `data-state`.

- [ ] **Step 4: `PostGraph` becomes a namespace**

Replace `app/queries/post_graph.rb` with:

```ruby
# The mind graph's data (mind graph canvas spec §3): the queries behind CS
# Studio's Mind graph screen and its two JSON reads.
#
# - `PostGraph::Global`: the best-connected readable posts, up to `CAP`.
# - `PostGraph::Local`: one post's or tag's neighbourhood (`PostGraph::Focus`).
# - `PostGraph::Search`: readable posts and tags by name.
# - `PostGraph::Builder`: the `{ nodes, tags, edges }` the first two share.
#
# Shape: `{ nodes: [{ id, title, type, colour_index, status, url, degree }],
# tags: [{ id: "tag-<id>", name, count, degree }], edges: [{ source, target,
# kind }], total, shown }`, plus `isolated` (global) or `focus` (local). There
# is deliberately NO colour here: a node carries its content type's
# `colour_index` (nil for a type that isn't registered any more) and the page
# draws it from the `--cs-cat-<n>` tokens, so a type looks the same in the
# graph as in `Admin::ContentTypeDotComponent`. `status` is
# `Publishable#status`.
#
# Every query takes `actor:` with no default, so nothing draws the whole graph
# by forgetting to pass one, and `url_for:` with no default, because a query
# knows no routes (`test/lib/dependency_direction_test.rb`).
module PostGraph
  # A tag on fewer readable posts than this is no connection and has no node.
  MIN_TAGGED_POSTS = 2

  # The most posts one graph draws: beyond it the global view keeps the
  # best-connected, and a local view the nearest. Set from the measurements in
  # the spec's §7.
  CAP = 2_000
end
```

Change `class PostGraph` to `module PostGraph` in `builder.rb`, `global.rb`, `focus.rb`, `local.rb` and `search.rb`. Delete `test/queries/post_graph_test.rb`: every case in it is covered by `test/queries/post_graph/global_test.rb` (node fields, one edge per relation, the unregistered type, the three statuses, tag nodes, trashed posts, readable counts, the statement count, no posts, an actor's scope). Before deleting, check each of its eleven tests against that list and add to `global_test.rb` any case that has no counterpart — "a type that isn't registered any more has no colour index" and "status is the post's own" need adding:

```ruby
  test "a type that isn't registered any more has no colour index" do
    a = create_post(title: "A")
    relate(a, create_post(title: "B"))
    a.update_column(:content_type, "gone/thing") # version: none (a test's fixture set-up)

    node = graph[:nodes].find { |n| n[:id] == a.id }

    assert_equal [ "gone/thing", nil ], node.values_at(:type, :colour_index)
  end

  test "status is the post's own: draft, scheduled or live" do
    draft, scheduled, live = %w[Draft Scheduled Live].map { |title| create_post(title: title, tags: [ "t" ]) }
    draft.update_column(:published_at, nil) # version: none (a test's fixture set-up)
    scheduled.update_column(:published_at, 2.days.from_now) # version: none (a test's fixture set-up)
    live.update_column(:published_at, 1.day.ago) # version: none (a test's fixture set-up)

    assert_equal({ draft.id => "draft", scheduled.id => "scheduled", live.id => "live" }, graph[:nodes].to_h { |n| [ n[:id], n[:status] ] })
  end
```

- [ ] **Step 5: The controller's `show`**

In `app/controllers/admin/mind_graph_controller.rb` replace `show`:

```ruby
    # The frame only: the graph itself is fetched by the script from `data`.
    # What the page needs from the database is whether this viewer can read a
    # post at all ("No posts yet."), which content types their posts have (the
    # legend names only those, so it discloses no type they can't see) and the
    # focus, which is not found when it is outside their scope.
    def show
      @focus = PostGraph::Focus.find(actor: Current.actor, post: params[:post], tag: params[:tag], locale: admin_locale)
      @depth = params[:depth].to_s == "2" ? 2 : 1
      @content_types = AccessControl.scope(Current.actor, "posts.read", Post.all).distinct.pluck(:content_type)
    end
```

Update the class comment: the data island is gone; the page is a frame and `data` answers the graph.

- [ ] **Step 6: The view**

Replace `app/views/admin/mind_graph/show.html.erb`:

```erb
<%# The Mind graph (mind graph canvas spec §3.2, §5): a frame. The graph's data
    is NOT in the page -- at the cap it is several hundred kilobytes, which
    would sit in every load and in Turbo's page cache -- so `admin--mind-graph`
    fetches it from `data-url`, lays it out in a worker (`data-worker-url`,
    which imports d3-force from `data-d3-url`: an import map does not apply
    inside a worker, so both are plain asset URLs) and draws it on the canvas.
    The canvas is one image to assistive technology; what a pointer can do on
    it has an HTML path beside it. Read-only: relations are edited in the post
    editor's related-posts picker. %>
<% content_for :title, t(".title") %>
<div class="mb-4">
  <h1 class="text-h1 text-ink"><%= t(".title") %></h1>
  <p class="mt-1 text-meta"><%= t(".intro") %></p>
</div>

<% if @content_types.empty? %>
  <%# For THIS viewer: a viewer who can read no post sees this, whatever the site holds. %>
  <div class="rounded-cs border border-line bg-surface p-6 text-meta" data-mind-graph-empty="no-posts"><%= t(".no_posts") %></div>
<% else %>
  <%# The box takes the width of the content column and the height left under
      the heading (never less than 480px); the canvas takes what the legend row
      leaves (`flex-1`) and follows the box's resizes. The filter is three
      radios (arrow keys move between them), applied client-side. %>
  <div data-controller="admin--mind-graph"
       data-url="<%= data_admin_mind_graph_path(**admin_url_options, post: params[:post].presence, tag: params[:tag].presence, depth: (@depth if @focus)) %>"
       data-worker-url="<%= asset_path("mind_graph/layout_worker.js") %>"
       data-d3-url="<%= asset_path("d3-force.js") %>"
       data-messages="<%= messages_data(*%w[loading load_failed retry worker_failed no_connections capped isolated summary].map { |key| "mind_graph.script.#{key}" }) %>"
       data-state="loading"
       class="flex h-[calc(100vh-11rem)] min-h-[480px] flex-col overflow-hidden rounded-cs border border-line bg-surface">
    <div class="flex flex-wrap items-center justify-between gap-x-6 gap-y-2 border-b border-line px-3.5 py-2.5">
      <%= render Admin::MindGraphLegendComponent.new(content_types: @content_types) %>
      <fieldset class="m-0 min-w-0 border-0 p-0">
        <legend class="sr-only"><%= t(".filter.legend") %></legend>
        <div class="inline-flex overflow-hidden rounded-cs border border-line-strong bg-surface">
          <% %w[all related tag].each do |value| %>
            <label for="mind-graph-filter-<%= value %>" class="flex cursor-pointer items-center border-r border-line px-3 py-1.5 text-sm text-dim last:border-r-0 hover:bg-sunken has-[:checked]:bg-accent-tint has-[:checked]:font-semibold has-[:checked]:text-ink has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:-outline-offset-2 has-[:focus-visible]:outline-accent">
              <%= radio_button_tag "mind_graph_filter", value, value == "all", id: "mind-graph-filter-#{value}", class: "sr-only", data: { action: "change->admin--mind-graph#filter" } %>
              <span><%= t(".filter.#{value}") %></span>
            </label>
          <% end %>
        </div>
      </fieldset>
    </div>
    <div class="relative min-h-0 flex-1">
      <canvas data-admin--mind-graph-target="canvas" class="block h-full w-full touch-none text-ink" role="img" tabindex="0" aria-label="<%= t(".canvas_label") %>"></canvas>
      <div data-admin--mind-graph-target="notice" class="pointer-events-none absolute left-3.5 top-3 m-0 flex max-w-md flex-col gap-1 text-meta"></div>
      <div class="absolute bottom-3 right-3 flex gap-1.5">
        <%= render Admin::ButtonComponent.new(label: t(".zoom_out"), variant: :secondary, size: :small, data: { action: "admin--mind-graph#zoomOut" }) %>
        <%= render Admin::ButtonComponent.new(label: t(".zoom_in"), variant: :secondary, size: :small, data: { action: "admin--mind-graph#zoomIn" }) %>
        <%= render Admin::ButtonComponent.new(label: t(".fit"), variant: :secondary, size: :small, data: { action: "admin--mind-graph#fit" }) %>
      </div>
    </div>
  </div>
<% end %>
```

Before using `Admin::ButtonComponent`, read its initializer (`app/components/admin/button_component.rb`) and pass the arguments it really takes (label, variant, size, data); if it has no small size, use the variant the dashboard's secondary buttons use. `admin_url_options` may already carry `locale`; `nil` values are dropped by the path helper.

- [ ] **Step 7: The legend takes keys and a retired-type entry**

Add to `config/locales/admin/components.en.yml`, under `admin.components` (read the file's header comment first and keep its ordering):

```yaml
      mind_graph_legend:
        label: "Legend"
        tag: "Tag"
        hollow: "Draft or scheduled"
        retired: "Retired type"
        related: "Related post"
        tag_edge: "Shares a tag"
```

In `app/components/admin/mind_graph_legend_component.rb` add:

```ruby
    # Whether a shown post's type is no longer registered: such a post is drawn
    # as a grey ring with a stroke through it, and the legend says what that is.
    def retired? = (@content_types - ::ContentTypes.names.map(&:to_s)).any?

    # Only registered types get a dot of their own.
    def type_names
      registered = ::ContentTypes.names.map(&:to_s)
      (@content_types & registered).sort_by { |name| registered.index(name) }
    end
```

(replacing the existing `type_names`), and in the template replace each English word with `t(".tag")`, `t(".hollow")`, `t(".related")`, `t(".tag_edge")`, the `aria-label` with `t(".label")`, and add after the "hollow" entry:

```erb
  <% if retired? %>
    <li class="inline-flex items-center gap-1.5" data-legend="retired">
      <svg class="mg-key" width="12" height="12" viewBox="0 0 12 12" aria-hidden="true"><circle class="mg-key-retired" cx="6" cy="6" r="4"/><line class="mg-key-retired" x1="2.5" y1="9.5" x2="9.5" y2="2.5"/></svg>
      <%= t(".retired") %>
    </li>
  <% end %>
```

In `app/assets/tailwind/content-spiel.tailwind.css`, beside `.mg-key-hollow`, add `.mg-key-retired { fill: none; stroke: var(--cs-meta); stroke-width: 1.5; }`. Remove the rules only the SVG graph used (`.mg-node …`, `.mg-cat-*`, `.mg-tag text`, `.mg-hidden`, `.mg-node:focus*`), keeping every rule the legend's swatches use (`.mg-key*`, `.mg-tag rect`, `.mg-edge*`), and rewrite the comment block above them to say the canvas reads the same tokens through `mind_graph/theme.js`.

Update `test/components/admin/mind_graph_legend_component_test.rb`: add a case that a retired type shows the `data-legend="retired"` entry and no dot of its own, and that without one the entry is absent. Add the component's two files to `CONVERTED` in `test/lib/admin_i18n_test.rb`, with `app/views/admin/mind_graph/show.html.erb`.

- [ ] **Step 8: The theme module**

`app/javascript/mind_graph/theme.js`:

```js
// The mind graph's colours (mind graph canvas spec §4.3): read from the CSS
// custom properties, never written here. A canvas takes a colour as a string,
// and the browser accepts whatever CSS does (`oklch(...)` included), so the
// tokens are handed over exactly as the stylesheet resolves them.
//
// `watchTheme` answers a function that stops watching. The theme changes when
// `<html data-theme>` does (`theme_controller.js`) or, with no explicit
// choice, when the system's scheme does.
const TOKENS = { ink: "--cs-ink", meta: "--cs-meta", surface: "--cs-surface", accent: "--cs-accent", line: "--cs-line" }
const CATEGORIES = 6

export function readTheme(element) {
  const style = getComputedStyle(element)
  const read = (name) => style.getPropertyValue(name).trim()
  const theme = Object.fromEntries(Object.entries(TOKENS).map(([ key, name ]) => [ key, read(name) ]))
  theme.categories = Array.from({ length: CATEGORIES }, (_, index) => read(`--cs-cat-${index + 1}`))
  theme.font = `12px ${style.fontFamily}`
  return theme
}

export function watchTheme(callback) {
  const observer = new MutationObserver(callback)
  observer.observe(document.documentElement, { attributes: true, attributeFilter: [ "data-theme", "class" ] })
  const scheme = window.matchMedia("(prefers-color-scheme: dark)")
  scheme.addEventListener("change", callback)
  return () => {
    observer.disconnect()
    scheme.removeEventListener("change", callback)
  }
}
```

- [ ] **Step 9: The renderer**

`app/javascript/mind_graph/renderer.js`:

```js
// Draws one frame of the mind graph (mind graph canvas spec §4.3, §5.1).
// Order: edges, nodes, labels, rings. Everything is in SCREEN pixels: the
// camera moves a node's centre, and a node is the same size at every zoom.
//
// A node's mark carries two cues that never share a shape, exactly as
// `Admin::ContentTypeDotComponent` and the legend draw them:
// - the TYPE is the fill: colour slots 1-6 are filled with the hue, 7-12 are a
//   ring of the same six hues (13+ cycle);
// - the STATUS is the outline: a live post's is solid, a draft's or a
//   scheduled post's dashed -- with a small filled core for slots 1-6, so the
//   hue is still there;
// - a post whose type is no longer registered (no `colour_index`) is a ring in
//   the `meta` grey WITH A STROKE THROUGH IT, so it differs from a 7-12 ring
//   by shape, not by colour alone.
// A tag is a square. A related edge is solid, a shared tag's dashed.
const STEPS = [ [ 2, 6 ], [ 5, 8 ], [ 12, 11 ], [ Infinity, 14 ] ]
const DIM = 0.18

// Four sizes by degree: small differences in size can't be read, so a hub is
// one of four steps, not a point on a scale. A tag's is its half side.
export function radiusFor(node) {
  const radius = STEPS.find(([ upTo ]) => node.degree <= upTo)[1]
  return node.kind === "tag" ? radius * 0.75 : radius
}

export function draw(context, { width, height, ratio, camera, theme, nodes, edges, positions, radii, visibleNodes, visibleEdges, labels, selected, neighbours, focusIndex }) {
  context.setTransform(ratio, 0, 0, ratio, 0, 0)
  context.clearRect(0, 0, width, height)

  const x = (index) => positions[index * 2] * camera.k + camera.tx
  const y = (index) => positions[index * 2 + 1] * camera.k + camera.ty
  const dimmed = (index) => selected >= 0 && index !== selected && !neighbours.has(index)

  for (const kind of [ "tag", "related" ]) {
    for (const faded of [ true, false ]) {
      context.beginPath()
      for (const edgeIndex of visibleEdges) {
        const edge = edges[edgeIndex]
        if (edge.kind !== kind) continue
        const touchesSelection = selected < 0 || edge.source === selected || edge.target === selected
        if (touchesSelection === faded) continue
        context.moveTo(x(edge.source), y(edge.source))
        context.lineTo(x(edge.target), y(edge.target))
      }
      context.globalAlpha = (kind === "tag" ? 0.8 : 0.35) * (faded ? DIM : 1)
      context.strokeStyle = kind === "tag" ? theme.meta : theme.ink
      context.lineWidth = kind === "tag" ? 1 : 1.5
      context.setLineDash(kind === "tag" ? [ 4, 3 ] : [])
      context.stroke()
    }
  }
  context.setLineDash([])

  for (const index of visibleNodes) {
    context.globalAlpha = dimmed(index) ? DIM : 1
    if (nodes[index].kind === "tag") drawTag(context, theme, x(index), y(index), radii[index])
    else drawPost(context, theme, nodes[index], x(index), y(index), radii[index])
  }

  context.font = theme.font
  context.textBaseline = "middle"
  for (const label of labels) {
    context.globalAlpha = label.alpha * (dimmed(label.index) ? DIM : 1)
    context.fillStyle = nodes[label.index].kind === "tag" ? theme.meta : theme.ink
    context.fillText(nodes[label.index].label, label.x, label.y)
  }

  context.globalAlpha = 1
  for (const index of [ focusIndex, selected ]) {
    if (index == null || index < 0 || !visibleNodes.includes(index)) continue
    context.beginPath()
    context.arc(x(index), y(index), radii[index] + 5, 0, Math.PI * 2)
    context.strokeStyle = theme.accent
    context.lineWidth = index === selected ? 2 : 1.5
    context.setLineDash(index === selected ? [] : [ 2, 3 ])
    context.stroke()
  }
  context.setLineDash([])
}

function drawTag(context, theme, x, y, half) {
  context.fillStyle = theme.surface
  context.strokeStyle = theme.meta
  context.lineWidth = 1.5
  context.setLineDash([])
  context.fillRect(x - half, y - half, half * 2, half * 2)
  context.strokeRect(x - half, y - half, half * 2, half * 2)
}

function drawPost(context, theme, node, x, y, radius) {
  const retired = node.colour_index == null
  const slot = retired ? null : (node.colour_index - 1) % 12
  const hue = retired ? theme.meta : theme.categories[slot % 6]
  const ring = retired || slot >= 6
  const hollow = node.status !== "live"

  context.beginPath()
  context.arc(x, y, radius, 0, Math.PI * 2)
  context.fillStyle = ring || hollow ? theme.surface : hue
  context.fill()
  context.strokeStyle = hue
  context.lineWidth = ring ? 2.5 : hollow ? 2 : 1.5
  context.setLineDash(hollow ? [ 3, 2.5 ] : [])
  context.stroke()
  context.setLineDash([])

  if (hollow && !ring) {
    context.beginPath()
    context.arc(x, y, radius * 0.4, 0, Math.PI * 2)
    context.fillStyle = hue
    context.fill()
  }
  if (retired) {
    const reach = radius * 0.72
    context.beginPath()
    context.moveTo(x - reach, y + reach)
    context.lineTo(x + reach, y - reach)
    context.lineWidth = 1.5
    context.stroke()
  }
}
```

`edges[i].source` / `.target` here are node INDEXES (app.js converts the ids once). `visibleNodes.includes` is called twice per frame, which is fine.

- [ ] **Step 10: The input module**

`app/javascript/mind_graph/input.js`:

```js
// The canvas's pointer, wheel and key events as callbacks (mind graph canvas
// spec §4.4). It knows nothing of the graph: it says where something happened,
// in canvas pixels, and `app.js` decides what that means.
//
// - `onPress(x, y)` answers what the press is on: anything truthy starts a
//   drag of that thing (`onDrag(x, y)`, `onDrop()`), null pans (`onPan(dx, dy)`).
// - A press released within CLICK_SLOP pixels of where it began is a click
//   (`onClick(x, y)`), whatever it was on: "select" and "drag" start alike and
//   can only be told apart afterwards.
// - `onZoom(x, y, factor)`: the wheel (and a pinch, which a trackpad sends as
//   a wheel with ctrlKey), and + / - with the canvas focused, around its middle.
// - Arrow keys pan; Escape is `onEscape()`.
// Answers a function that removes every listener.
const CLICK_SLOP = 5
const KEY_PAN = 60
const KEY_ZOOM = 1.25

export function attachInput(canvas, { onPress, onDrag, onDrop, onPan, onClick, onZoom, onHover, onEscape }) {
  const at = (event) => {
    const box = canvas.getBoundingClientRect()
    return [ event.clientX - box.left, event.clientY - box.top ]
  }
  let press = null

  const pointerdown = (event) => {
    if (event.button !== 0) return
    const [ x, y ] = at(event)
    canvas.setPointerCapture(event.pointerId)
    press = { startX: x, startY: y, lastX: x, lastY: y, moved: 0, target: onPress(x, y) }
  }
  const pointermove = (event) => {
    const [ x, y ] = at(event)
    if (!press) return onHover(x, y)

    press.moved = Math.max(press.moved, Math.hypot(x - press.startX, y - press.startY))
    if (press.moved >= CLICK_SLOP) {
      if (press.target) onDrag(x, y)
      else onPan(x - press.lastX, y - press.lastY)
    }
    press.lastX = x
    press.lastY = y
  }
  const pointerup = (event) => {
    if (!press) return
    const [ x, y ] = at(event)
    const wasClick = press.moved < CLICK_SLOP
    const hadTarget = Boolean(press.target)
    press = null
    if (hadTarget) onDrop()
    if (wasClick) onClick(x, y)
  }
  const wheel = (event) => {
    event.preventDefault()
    const [ x, y ] = at(event)
    onZoom(x, y, Math.exp(-event.deltaY * (event.ctrlKey ? 0.01 : 0.0015)))
  }
  const keydown = (event) => {
    const box = canvas.getBoundingClientRect()
    const pans = { ArrowLeft: [ KEY_PAN, 0 ], ArrowRight: [ -KEY_PAN, 0 ], ArrowUp: [ 0, KEY_PAN ], ArrowDown: [ 0, -KEY_PAN ] }
    if (pans[event.key]) onPan(...pans[event.key])
    else if (event.key === "+" || event.key === "=") onZoom(box.width / 2, box.height / 2, KEY_ZOOM)
    else if (event.key === "-") onZoom(box.width / 2, box.height / 2, 1 / KEY_ZOOM)
    else if (event.key === "Escape") onEscape()
    else return
    event.preventDefault()
  }
  const pointerleave = () => onHover(-1, -1)

  const listeners = { pointerdown, pointermove, pointerup, pointercancel: pointerup, pointerleave, keydown }
  Object.entries(listeners).forEach(([ name, handler ]) => canvas.addEventListener(name, handler))
  canvas.addEventListener("wheel", wheel, { passive: false })

  return () => {
    Object.entries(listeners).forEach(([ name, handler ]) => canvas.removeEventListener(name, handler))
    canvas.removeEventListener("wheel", wheel)
  }
}
```

- [ ] **Step 11: The app**

`app/javascript/mind_graph/app.js`:

```js
// The mind graph, wired together (mind graph canvas spec §4): fetch the data,
// hand the layout to the worker, and redraw the canvas when something changed.
// `mount(element)` is everything `admin--mind-graph` asks for; `destroy()`
// stops all of it -- the request, the worker, the frame, the observers -- so
// nothing runs or draws after the screen is left.
//
// What the screen shows is said on the element, for tests and for anything
// that wants to know without reading a canvas: `data-state` (loading, ready,
// failed, worker-failed), `data-settled`, `data-nodes`, `data-edges`,
// `data-zoom`, `data-labelled`. `element.mindGraph.screenPosition(id)` answers
// where a visible node is, in client coordinates.
import { messages } from "i18n/messages"
import { createLayout } from "mind_graph/layout_client"
import { identity, toGraph, zoomAt, panBy, bounds, fit } from "mind_graph/camera"
import { nodeAt } from "mind_graph/hit_test"
import { chooseLabels } from "mind_graph/labels"
import { readTheme, watchTheme } from "mind_graph/theme"
import { draw, radiusFor } from "mind_graph/renderer"
import { attachInput } from "mind_graph/input"

// A label longer than this is cut with an ellipsis; a tag's count is appended
// whole. Counted by code point, so an emoji is never cut in half.
const MAX_LABEL_CHARACTERS = 32
const BUTTON_ZOOM = 1.4

function labelFor(node) {
  const suffix = node.kind === "tag" ? ` (${node.count})` : ""
  const room = MAX_LABEL_CHARACTERS - Array.from(suffix).length
  const characters = Array.from(String(node.title))
  return (characters.length > room ? `${characters.slice(0, room - 1).join("")}…` : characters.join("")) + suffix
}

export function mount(element) {
  const canvas = element.querySelector("canvas")
  const notice = element.querySelector("[data-admin--mind-graph-target='notice']")
  const context = canvas.getContext("2d")
  const text = messages(element)
  const aborter = new AbortController()
  const state = {
    nodes: [], edges: [], positions: new Float32Array(0), radii: [], widths: [], order: [],
    visibleNodes: [], visibleEdges: [], camera: identity(), selected: -1, neighbours: new Set(), focusIndex: -1,
    theme: readTheme(canvas), width: 0, height: 0, ratio: 1, fitted: false, data: null
  }
  let destroyed = false
  let layout = null
  let frame = null
  let draws = 0
  let labelled = ""

  const mode = () => element.querySelector("input[name=mind_graph_filter]:checked")?.value || "all"
  const setState = (value) => { element.dataset.state = value }

  function say(...lines) {
    notice.replaceChildren(...lines.filter(Boolean).map((line) => {
      const paragraph = document.createElement("p")
      paragraph.className = "m-0 w-fit rounded-cs bg-surface px-1"
      if (line instanceof Node) paragraph.append(line)
      else paragraph.textContent = line
      return paragraph
    }))
  }

  function requestDraw() {
    if (destroyed || frame != null) return
    frame = requestAnimationFrame(() => {
      frame = null
      if (destroyed || state.width === 0) return

      const always = new Set(state.neighbours)
      if (state.selected >= 0) always.add(state.selected)
      if (state.focusIndex >= 0) always.add(state.focusIndex)
      const labels = chooseLabels({ order: state.order, positions: state.positions, widths: state.widths, radii: state.radii,
        camera: state.camera, width: state.width, height: state.height, always })
      draw(context, { ...state, labels })
      draws += 1

      element.dataset.zoom = state.camera.k.toFixed(3)
      const ids = labels.map((label) => state.nodes[label.index].id).join(",")
      if (ids !== labelled) element.dataset.labelled = labelled = ids
    })
  }

  // The canvas's bitmap is the box times the device pixel ratio. A box with no
  // size (a Turbo cache preview, a hidden tab) draws nothing; the observer
  // calls again when it gets one, and that first real size fits the view.
  function resize() {
    const box = canvas.getBoundingClientRect()
    const ratio = window.devicePixelRatio || 1
    if (box.width === state.width && box.height === state.height && ratio === state.ratio) return

    state.width = box.width
    state.height = box.height
    state.ratio = ratio
    canvas.width = Math.round(box.width * ratio)
    canvas.height = Math.round(box.height * ratio)
    if (!state.fitted && element.hasAttribute("data-settled")) fitAll()
    requestDraw()
  }

  function fitAll() {
    if (state.width === 0) return
    state.camera = fit(bounds(state.positions, state.visibleNodes), state.width, state.height)
    state.fitted = true
    requestDraw()
  }

  // What the filter shows: every edge of the chosen kind, and under "All"
  // every node, otherwise only the nodes such an edge touches.
  function applyFilter() {
    const chosen = mode()
    state.visibleEdges = state.edges.flatMap((edge, index) => (chosen === "all" || edge.kind === chosen ? [ index ] : []))
    const touched = new Set(state.visibleEdges.flatMap((index) => [ state.edges[index].source, state.edges[index].target ]))
    state.visibleNodes = state.nodes.flatMap((_, index) => (chosen === "all" || touched.has(index) ? [ index ] : []))
    state.order = state.visibleNodes.slice().sort((a, b) => state.nodes[b].degree - state.nodes[a].degree || a - b)
    if (state.selected >= 0 && !state.visibleNodes.includes(state.selected)) select(-1)
    element.dataset.nodes = state.visibleNodes.length
    element.dataset.edges = state.visibleEdges.length
  }

  function select(index) {
    state.selected = index
    state.neighbours = new Set()
    if (index >= 0) {
      for (const edgeIndex of state.visibleEdges) {
        const edge = state.edges[edgeIndex]
        if (edge.source === index) state.neighbours.add(edge.target)
        if (edge.target === index) state.neighbours.add(edge.source)
      }
    }
    element.dataset.selected = index >= 0 ? state.nodes[index].id : ""
    requestDraw()
  }

  function show(data) {
    state.data = data
    state.nodes = [ ...data.nodes.map((node) => ({ ...node, kind: "post" })), ...data.tags.map((tag) => ({ ...tag, title: tag.name, kind: "tag" })) ]
    const indexOf = new Map(state.nodes.map((node, index) => [ node.id, index ]))
    state.edges = data.edges.map((edge) => ({ kind: edge.kind, source: indexOf.get(edge.source), target: indexOf.get(edge.target) }))
    state.positions = new Float32Array(state.nodes.length * 2)
    state.radii = state.nodes.map(radiusFor)
    context.font = state.theme.font
    state.nodes.forEach((node) => { node.label = labelFor(node) })
    state.widths = state.nodes.map((node) => context.measureText(node.label).width)
    state.focusIndex = data.focus ? indexOf.get(data.focus.node_id) ?? -1 : -1
    applyFilter()
    canvas.setAttribute("aria-label", `${canvas.getAttribute("aria-label").split(":")[0]}: ${text.t("mind_graph.script.summary", { posts: state.nodes.length, edges: state.edges.length })}`)

    say(
      state.edges.length === 0 ? text.t("mind_graph.script.no_connections") : null,
      data.shown < data.total ? text.t("mind_graph.script.capped", { shown: data.shown.toLocaleString(), total: data.total.toLocaleString() }) : null,
      data.isolated > 0 ? text.t("mind_graph.script.isolated", { count: data.isolated }) : null
    )
    setState("ready")

    if (state.nodes.length === 0) return element.setAttribute("data-settled", "")
    startLayout()
  }

  function startLayout() {
    try {
      layout = createLayout({
        workerUrl: element.dataset.workerUrl,
        d3Url: element.dataset.d3Url,
        onTick: (positions) => {
          state.positions = positions
          // The first view fits everything as soon as there is a shape to fit;
          // after that the camera moves only when the user moves it.
          if (!state.fitted) state.camera = fit(bounds(positions, state.visibleNodes), state.width, state.height)
          requestDraw()
        },
        onSettled: () => {
          if (!state.fitted) fitAll()
          element.setAttribute("data-settled", "")
        },
        onError: workerFailed
      })
    } catch (error) {
      return workerFailed(error.message)
    }
    layout.start(state.nodes.map((node, index) => ({ id: node.id, radius: state.radii[index] })),
      state.edges.map((edge) => ({ source: state.nodes[edge.source].id, target: state.nodes[edge.target].id })))
    if (mode() !== "all") sendFilter()
  }

  function sendFilter() {
    layout?.filter(state.visibleNodes.map((index) => state.nodes[index].id), state.visibleEdges)
  }

  // Loud on purpose: the system tests fail on any console error, so a worker
  // that breaks is never a graph that silently stays empty.
  function workerFailed(message) {
    if (destroyed) return
    console.error(`mind graph: the layout worker failed: ${message}`)
    layout?.stop()
    layout = null
    setState("worker-failed")
    say(text.t("mind_graph.script.worker_failed"))
  }

  async function load() {
    setState("loading")
    element.removeAttribute("data-settled")
    say(text.t("mind_graph.script.loading"))
    try {
      const response = await fetch(element.dataset.url, { headers: { Accept: "application/json" }, signal: aborter.signal })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json()
      if (!destroyed) show(data)
    } catch (error) {
      if (destroyed || error.name === "AbortError") return
      setState("failed")
      const retry = document.createElement("button")
      retry.type = "button"
      retry.className = "pointer-events-auto underline"
      retry.textContent = text.t("mind_graph.script.retry")
      retry.addEventListener("click", load, { once: true })
      say(text.t("mind_graph.script.load_failed"), retry)
    }
  }

  const stopInput = attachInput(canvas, {
    onPress: () => null,
    onDrag: () => {},
    onDrop: () => {},
    onClick: () => {},
    onHover: () => {},
    onEscape: () => {},
    onPan: (dx, dy) => { state.camera = panBy(state.camera, dx, dy); state.fitted = true; requestDraw() },
    onZoom: (x, y, factor) => { state.camera = zoomAt(state.camera, x, y, factor); state.fitted = true; requestDraw() }
  })
  const stopTheme = watchTheme(() => { state.theme = readTheme(canvas); requestDraw() })
  const observer = new ResizeObserver(resize)
  observer.observe(canvas)
  resize()
  load()

  const zoomBy = (factor) => { state.camera = zoomAt(state.camera, state.width / 2, state.height / 2, factor); state.fitted = true; requestDraw() }

  element.mindGraph = {
    screenPosition(id) {
      const index = state.nodes.findIndex((node) => node.id === id)
      if (index < 0 || !state.visibleNodes.includes(index)) return null
      const box = canvas.getBoundingClientRect()
      return { x: box.left + state.positions[index * 2] * state.camera.k + state.camera.tx, y: box.top + state.positions[index * 2 + 1] * state.camera.k + state.camera.ty }
    },
    draws: () => draws
  }

  return {
    state, requestDraw, select, toGraph,
    hit: (x, y) => nodeAt({ positions: state.positions, indexes: state.visibleNodes, radii: state.radii, camera: state.camera, sx: x, sy: y }),
    layout: () => layout,
    zoomIn: () => zoomBy(BUTTON_ZOOM),
    zoomOut: () => zoomBy(1 / BUTTON_ZOOM),
    fit: fitAll,
    filter() {
      applyFilter()
      element.removeAttribute("data-settled")
      sendFilter()
      requestDraw()
    },
    destroy() {
      destroyed = true
      aborter.abort()
      layout?.stop()
      if (frame != null) cancelAnimationFrame(frame)
      observer.disconnect()
      stopInput()
      stopTheme()
      delete element.mindGraph
    }
  }
}
```

Two things to check while writing it, against the test and not against this listing:
- After `filter()`, `data-settled` must come back: the worker answers `settled` again after a `filter` message (Task 1's `run()`). With nothing visible to lay out it still must; if the worker's `filter` with an empty set never posts `settled`, make `run()` post it (the loop exits at once).
- The `aria-label` line keeps the server's label and appends the summary; do not build English here.

- [ ] **Step 12: The thin controller**

Replace `app/javascript/controllers/admin/mind_graph_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

// CS Studio's mind graph (`admin/mind_graph/show`; mind graph canvas spec §4).
// Deliberately thin: every `controllers/admin/*` file is loaded on every CS
// Studio page, so the graph's own modules -- and, through its worker,
// d3-force -- are imported only here, only when this screen is on the page
// (`import()` of `mind_graph/app`, which the import map resolves but nothing
// preloads). What the graph does is in `app/javascript/mind_graph/`.
//
// `connect()` may be followed by `disconnect()` before the import has arrived
// (a quick visit away, a Turbo cache preview): `this.live` says whether this
// connection is still the current one, so a late import mounts nothing.
export default class extends Controller {
  static targets = ["canvas", "notice"]

  connect() {
    const live = (this.live = Symbol("connection"))
    import("mind_graph/app").then(({ mount }) => {
      if (this.live === live) this.app = mount(this.element)
    })
  }

  disconnect() {
    this.live = null
    this.app?.destroy()
    this.app = null
  }

  filter() { this.app?.filter() }
  zoomIn() { this.app?.zoomIn() }
  zoomOut() { this.app?.zoomOut() }
  fit() { this.app?.fit() }
}
```

A failed `import()` must not be silent: it rejects, the unhandled rejection is a JavaScript error, and the system tests fail on it — leave it unhandled.

- [ ] **Step 13: d3-force is no longer preloaded**

In `config/importmap.rb` replace `pin "d3-force", preload: "admin" # @3.0.0` with:

```ruby
# Vendored for the mind graph's layout WORKER, which imports the file by its
# asset URL (an import map does not apply inside a worker). Nothing in a page
# imports it, so it is not preloaded; the pin stays so `bin/importmap audit`
# and `outdated` still see the package.
pin "d3-force", preload: false # @3.0.0
```

and update the header comment's list ("…SortableJS and D3") to drop D3. In `test/integration/public_javascript_test.rb`, add a test:

```ruby
  test "only the Mind graph loads its own modules, and no page preloads d3-force" do
    sign_in_as(users(:one))

    get "/cs-studio/tags"
    assert_no_match %r{modulepreload[^>]*(mind_graph/|d3-force)}, response.body

    get "/cs-studio/mind_graph"
    assert_no_match %r{modulepreload[^>]*d3-force}, response.body
  end
```

Match the file's existing way of signing in and of reading the preload links; the assertion is that no `<link rel="modulepreload">` names `mind_graph/` or `d3-force` on any page.

- [ ] **Step 14: Rewrite the page's integration test**

Replace the tests in `test/integration/admin/mind_graph_test.rb` (keep the class, its `setup` and "an unauthenticated request is redirected to sign-in"; delete `graph_data` and every test that reads the data island) with:

```ruby
  test "the page is a frame: no graph data in it, and the script is told where to get it" do
    sign_in_as(users(:one))
    a = create_post(title: "A very particular title")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))

    get "/cs-studio/mind_graph"

    assert_response :success
    assert_select "script#mind-graph-data", count: 0
    assert_no_match "A very particular title", response.body
    assert_select "[data-controller='admin--mind-graph'][data-url='/cs-studio/mind_graph/data'][data-state='loading']"
    assert_select "[data-controller='admin--mind-graph'][data-worker-url*='mind_graph/layout_worker'][data-d3-url*='d3-force']"
    assert_select "canvas[role='img'][tabindex='0'][aria-label]"
    assert_select "nav[aria-label='Modules'] a[href='/cs-studio/mind_graph']", text: "Mind graph"
  end

  test "the data url carries the focus, the depth and the editing language" do
    sign_in_as(users(:one))
    with_locales(%w[en de], default: "en")
    post = create_post(title: "A")

    get "/cs-studio/mind_graph", params: { post: post.id, depth: 2, locale: "de" }

    url = css_select("[data-controller='admin--mind-graph']").first["data-url"]
    assert_equal({ "post" => post.id.to_s, "depth" => "2", "locale" => "de" }, Rack::Utils.parse_query(URI(url).query))
  end

  test "a focus outside the viewer's scope, in the trash or unknown is 404" do
    sign_in_as(users(:one))
    gone = create_post(title: "Gone")
    gone.update_column(:trashed_at, Time.current) # version: none (a test's fixture set-up)

    [ { post: 0 }, { post: gone.id }, { tag: 0 } ].each do |params|
      get "/cs-studio/mind_graph", params: params
      assert_response :not_found, "expected 404 for #{params}"
    end
  end

  test "a viewer who can read no post sees 'No posts yet.' and no canvas, however many exist" do
    create_post(title: "Hidden from them")
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    sign_in_as(users(:author))

    get "/cs-studio/mind_graph"

    assert_select "[data-mind-graph-empty=no-posts]", text: "No posts yet."
    assert_select "canvas", count: 0
    assert_select "[data-controller='admin--mind-graph']", count: 0
    assert_not_includes response.body, "Hidden from them"
  end

  test "the legend names only the content types of the viewer's posts, plus the shapes" do
    sign_in_as(users(:one))
    create_post(title: "A", content_type: "resume_entry")

    get "/cs-studio/mind_graph"

    assert_select "[data-legend-type]", count: 1
    assert_select "[data-legend-type='resume_entry']"
    assert_select "[data-legend='tag']", text: /Tag/
    assert_select "[data-legend='hollow']", text: /Draft or scheduled/
    assert_select "[data-legend='retired']", count: 0
  end

  test "a post of a type that is no longer registered adds the Retired type entry" do
    sign_in_as(users(:one))
    create_post(title: "A").update_column(:content_type, "gone/thing") # version: none (a test's fixture set-up)

    get "/cs-studio/mind_graph"

    assert_select "[data-legend='retired']", text: /Retired type/
    assert_select "[data-legend-type]", count: 0
  end

  test "the filter is All, Related and Tags, with All chosen" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    assert_select "fieldset input[type=radio][name=mind_graph_filter]", count: 3
    assert_select "input#mind-graph-filter-all[checked]"
    assert_select "label[for=mind-graph-filter-related]", text: "Related"
    assert_select "label[for=mind-graph-filter-tag]", text: "Tags"
  end
```

In `test/integration/trash_visibility_test.rb` and `test/integration/admin/access_control_test.rb`, every assertion that parses `script#mind-graph-data` from `/cs-studio/mind_graph` now requests `/cs-studio/mind_graph/data` and reads `response.parsed_body` (string keys). In the trash test "the mind graph's tag nodes count kept posts only", the tag hashes gain `"degree" => 2`. In the access-control test the node ids and edges stay as asserted. Remove the three now-duplicated lines Task 4 added to the trash test if they repeat these.

In `test/system/admin/ai_assistant_and_graph_test.rb`, delete the five mind graph tests (from "the mind graph draws every post and a click opens its editor" to "a draft is drawn as a dashed ring, a live post filled, and nodes are keyboard links") and fix the file's header comment; what they covered is in `test/system/admin/mind_graph_test.rb` and, for the click and the keyboard path, arrives in Tasks 7 and 9.

- [ ] **Step 15: Run everything this task touches**

Run:
```
bin/rails tailwindcss:build
PGGSSENCMODE=disable bin/rails test test/queries test/integration test/components test/lib
PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/mind_graph_test.rb test/system/admin/mind_graph_modules_test.rb test/system/admin/ai_assistant_and_graph_test.rb
bin/rubocop && bin/brakeman -q && bin/rails zeitwerk:check
```
Expected: all PASS, no offenses, zero warnings.

- [ ] **Step 16: Look at it**

Start the server (`bin/dev`), sign in, open `/cs-studio/mind_graph` with a few related and tagged posts in development, and check by eye in light and dark theme: nodes and edges are drawn, zoom and pan work, labels appear with zoom, a draft is a dashed ring. Report what you saw; a canvas can pass every test and still draw nothing useful.

- [ ] **Step 17: Commit**

```bash
git add -A
git commit -m "feat: the mind graph is drawn on a canvas — the page is a frame, the data is fetched, the layout runs in the worker, with zoom, pan, fit and the cap's messages"
```

---

### Task 7: Selecting a node, the card, hover and dragging

**Files:**
- Create: `app/javascript/mind_graph/card.js`
- Modify: `app/javascript/mind_graph/app.js`, `app/views/admin/mind_graph/show.html.erb`, `config/locales/admin/mind_graph.en.yml`
- Test: `test/system/admin/mind_graph_test.rb`

**Interfaces:**
- Consumes: from Task 6's `app.js` — `state`, `select(index)`, `hit(x, y)`, `requestDraw()`, `layout()`, and `attachInput`'s callbacks.
- Produces: `createCard(container, { text, urls, typeLabels }) → { show(node), hide() }`.
  - `urls`: `{ postFocus, tagFocus, tagPosts }`, templates with `__ID__` / `__NAME__`.
  - The card element is `[data-mind-graph-card]`, hidden with the `hidden` attribute when nothing is selected.
- View data attributes added: `data-post-focus-url`, `data-tag-focus-url`, `data-tag-posts-url`, `data-type-labels` (JSON `{ type name: label }`).
- `data-selected` on the element: the selected node's id, or empty.

- [ ] **Step 1: Strings**

Add under `admin.mind_graph.script` in `config/locales/admin/mind_graph.en.yml`:

```yaml
        card:
          connections:
            one: "%{count} connection"
            other: "%{count} connections"
          tag_posts:
            one: "%{count} post"
            other: "%{count} posts"
          open_post: "Open post"
          focus: "Focus graph here"
          show_tagged: "Show posts with this tag"
          close: "Close"
          tag: "Tag"
          status:
            draft: "Draft"
            scheduled: "Scheduled"
            live: "Live"
```

and add `card.connections card.tag_posts card.open_post card.focus card.show_tagged card.close card.tag card.status.draft card.status.scheduled card.status.live` to the view's `messages_data` list (each prefixed `mind_graph.script.`).

- [ ] **Step 2: Write the failing tests**

Add to `test/system/admin/mind_graph_test.rb`, above `private`:

```ruby
  test "a click on a post selects it and opens its card; Open post opens the editor" do
    a = create_post(title: "Alpha", content_type: "resume_entry")
    b = create_post(title: "Beta")
    PostRelation.create!(post: a, related_post: b)
    visit admin_mind_graph_path
    await_graph
    assert_no_selector "[data-mind-graph-card]", visible: :visible

    click_node(a.id)

    assert_equal a.id.to_s, graph["data-selected"]
    within("[data-mind-graph-card]") do
      assert_text "Alpha"
      assert_text ContentTypes.fetch("resume_entry").label
      assert_text "Live"
      assert_text "1 connection"
      assert_link "Focus graph here", href: /mind_graph\?post=#{a.id}\z/
      click_link "Open post"
    end
    assert_current_path admin_post_path(a)
  end

  test "a click on a tag opens its card, with the posts list filtered by it" do
    2.times { |i| create_post(title: "P#{i}", tags: [ "c++ & more" ]) }
    tag = Tag.find_by!(name: "c++ & more")
    visit admin_mind_graph_path
    await_graph

    click_node("tag-#{tag.id}")

    within("[data-mind-graph-card]") do
      assert_text "c++ & more"
      assert_text "2 posts"
      assert_link "Focus graph here", href: /mind_graph\?tag=#{tag.id}\z/
      click_link "Show posts with this tag"
    end
    assert_current_path admin_posts_path(tag: "c++ & more")
  end

  test "a click on empty space, Escape and the card's Close all clear the selection" do
    a = create_post(title: "A")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph
    corner = page.evaluate_script("(() => { const r = document.querySelector(#{"#{GRAPH} canvas".to_json}).getBoundingClientRect(); return [r.left + 6, r.top + 6] })()")

    click_node(a.id)
    assert_selector "[data-mind-graph-card]"
    page.driver.browser.mouse.click(x: corner[0], y: corner[1])
    assert_no_selector "[data-mind-graph-card]", visible: :visible
    assert_equal "", graph["data-selected"]

    click_node(a.id)
    find("#{GRAPH} canvas").send_keys(:escape)
    assert_no_selector "[data-mind-graph-card]", visible: :visible

    click_node(a.id)
    within("[data-mind-graph-card]") { press "Close" }
    assert_no_selector "[data-mind-graph-card]", visible: :visible
  end

  test "the selected node and its neighbours are labelled at any zoom" do
    hub = create_post(title: "Hub")
    spokes = 30.times.map { |i| create_post(title: "Spoke #{i}") }
    spokes.each { |spoke| PostRelation.create!(post: hub, related_post: spoke) }
    spokes.each_cons(2) { |a, b| PostRelation.create!(post: a, related_post: b) }
    visit admin_mind_graph_path
    await_graph
    6.times { press "Zoom out" }
    last = spokes.last

    click_node(last.id)

    await_js("document.querySelector(#{GRAPH.to_json}).dataset.labelled.split(',').includes('#{last.id}')")
    labelled = graph["data-labelled"].split(",")
    assert_includes labelled, hub.id.to_s
  end

  # Review focus 1.
  test "a title with markup in it is text in the card" do
    a = create_post(title: %(</script><img src=x onerror="window.pwned=1"> "quoted" 🎉))
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph

    click_node(a.id)

    within("[data-mind-graph-card]") { assert_text %(</script><img src=x onerror="window.pwned=1"> "quoted" 🎉) }
    assert_no_selector "[data-mind-graph-card] img", visible: :all
    assert_nil page.evaluate_script("window.pwned")
  end

  test "dragging a node moves it and the selection is not changed by the drag" do
    a = create_post(title: "A")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph
    from = screen_position(a.id)

    mouse = page.driver.browser.mouse
    mouse.move(x: from["x"], y: from["y"])
    mouse.down
    mouse.move(x: from["x"] + 40, y: from["y"] + 30)
    mouse.move(x: from["x"] + 80, y: from["y"] + 60)
    await_js("(() => { const p = document.querySelector(#{GRAPH.to_json}).mindGraph.screenPosition(#{a.id}); return Math.abs(p.x - #{from["x"] + 80}) < 6 && Math.abs(p.y - #{from["y"] + 60}) < 6 })()")
    mouse.up

    assert_equal "", graph["data-selected"].to_s
    assert_no_selector "[data-mind-graph-card]", visible: :visible
    await_graph
  end

  test "hovering a node shows its full title" do
    long = "A title that is certainly longer than thirty-two characters"
    a = create_post(title: long)
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph
    point = screen_position(a.id)

    page.driver.browser.mouse.move(x: point["x"], y: point["y"])

    assert_selector "[data-mind-graph-tooltip]", text: long
    page.driver.browser.mouse.move(x: point["x"] + 200, y: point["y"] + 200)
    assert_no_selector "[data-mind-graph-tooltip]", visible: :visible
  end
```

and, under `private`:

```ruby
  # A real click where the node is drawn.
  def click_node(id)
    point = screen_position(id)
    assert point, "node #{id} is not on screen"
    page.driver.browser.mouse.click(x: point["x"], y: point["y"])
  end
```

`ContentTypes.fetch(name).label` is the type's human name, as the legend's own test reads it.

- [ ] **Step 3: Run to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/system/admin/mind_graph_test.rb`
Expected: the seven new tests FAIL (no card), the earlier ones pass.

- [ ] **Step 4: The view**

In `show.html.erb`, add to the controller element's attributes:

```erb
       data-post-focus-url="<%= admin_mind_graph_path(**admin_url_options, post: "__ID__") %>"
       data-tag-focus-url="<%= admin_mind_graph_path(**admin_url_options, tag: "__ID__") %>"
       data-tag-posts-url="<%= admin_posts_path(**admin_url_options, tag: "__NAME__") %>"
       data-type-labels="<%= @type_labels.to_json %>"
```

and inside the `relative min-h-0 flex-1` box, after the notice:

```erb
      <%# The selection card and the hover tooltip: HTML over the canvas, filled
          by `mind_graph/card.js` with `textContent` only. %>
      <aside data-mind-graph-card hidden class="absolute right-3 top-3 flex w-64 flex-col gap-2 rounded-cs border border-line-strong bg-surface p-3 shadow-cs"></aside>
      <div data-mind-graph-tooltip hidden role="presentation" class="pointer-events-none absolute z-10 max-w-xs rounded-cs border border-line bg-surface px-2 py-1 text-sm text-ink shadow-cs"></div>
```

In the controller's `show`, add `@type_labels`: a hash of each of `@content_types` that is registered to its human label — built the way `Admin::ContentTypeDotComponent` reads the label, in the controller (a controller may know the registry). Use the shadow utility the other floating panels of CS Studio use if `shadow-cs` is not it (look at the menu or dialog component).

- [ ] **Step 5: The card module**

`app/javascript/mind_graph/card.js`:

```js
// The selection card (mind graph canvas spec §5.3): what a click on a node
// opens, and the only place a selection leads anywhere. HTML beside the
// canvas, so its links are links -- reachable by keyboard, opened in a new tab
// like any other -- and a click on the canvas never navigates by itself.
//
// Built with `textContent` and `href` only: a title or a tag's name is the
// editor's text, whatever it contains. A URL comes from a template the server
// built with its route helpers (`__ID__`, `__NAME__`), never from a path
// written here.
export function createCard(container, { text, urls, typeLabels, onClose }) {
  const element = (tag, className, content) => {
    const node = document.createElement(tag)
    if (className) node.className = className
    if (content != null) node.textContent = content
    return node
  }
  const link = (label, href) => {
    const anchor = element("a", "text-sm text-accent underline", label)
    anchor.href = href
    return anchor
  }
  const fill = (template, values) => Object.entries(values).reduce((url, [ key, value ]) => url.replace(key, encodeURIComponent(value)), template)

  return {
    show(node) {
      const close = element("button", "self-end text-sm text-meta underline", text.t("mind_graph.script.card.close"))
      close.type = "button"
      close.addEventListener("click", onClose)

      const lines = node.kind === "tag"
        ? [
            element("p", "m-0 text-label text-meta", text.t("mind_graph.script.card.tag")),
            element("h2", "m-0 break-words text-base font-semibold text-ink", node.title),
            element("p", "m-0 text-sm text-dim", text.t("mind_graph.script.card.tag_posts", { count: node.count })),
            link(text.t("mind_graph.script.card.focus"), fill(urls.tagFocus, { __ID__: String(node.id).replace("tag-", "") })),
            link(text.t("mind_graph.script.card.show_tagged"), fill(urls.tagPosts, { __NAME__: node.title }))
          ]
        : [
            element("p", "m-0 text-label text-meta", [ typeLabels[node.type], text.t(`mind_graph.script.card.status.${node.status}`) ].filter(Boolean).join(" · ")),
            element("h2", "m-0 break-words text-base font-semibold text-ink", node.title),
            element("p", "m-0 text-sm text-dim", text.t("mind_graph.script.card.connections", { count: node.degree })),
            link(text.t("mind_graph.script.card.open_post"), node.url),
            link(text.t("mind_graph.script.card.focus"), fill(urls.postFocus, { __ID__: node.id }))
          ]
      container.replaceChildren(close, ...lines)
      container.hidden = false
    },
    hide() {
      container.hidden = true
      container.replaceChildren()
    }
  }
}
```

`admin_posts_path(tag: "__NAME__")` puts the placeholder in the query string, where the path helper may escape nothing in `__NAME__`; confirm the rendered template contains `__NAME__` literally and that `encodeURIComponent("c++ & more")` gives the URL the posts list reads back as that name (the system test checks it).

- [ ] **Step 6: Wire it in `app.js`**

In `mount`, after `state` is defined:

```js
  const tooltip = element.querySelector("[data-mind-graph-tooltip]")
  const card = createCard(element.querySelector("[data-mind-graph-card]"), {
    text,
    urls: { postFocus: element.dataset.postFocusUrl, tagFocus: element.dataset.tagFocusUrl, tagPosts: element.dataset.tagPostsUrl },
    typeLabels: JSON.parse(element.dataset.typeLabels),
    onClose: () => select(-1)
  })
  let dragging = -1
```

with `import { createCard } from "mind_graph/card"` at the top. At the end of `select(index)`, before `requestDraw()`:

```js
    if (index >= 0) card.show(state.nodes[index])
    else card.hide()
```

Replace the four no-op input callbacks:

```js
    // A press on a node pins it under the pointer in the worker (`pin`), which
    // reheats the layout so the rest resettles around it; a press on empty
    // space pans. Whether the press was a click is known only at release.
    onPress: (x, y) => {
      dragging = hit(x, y)
      return dragging >= 0 ? dragging + 1 : null
    },
    onDrag: (x, y) => {
      if (dragging < 0 || !layout) return
      const [ gx, gy ] = toGraph(state.camera, x, y)
      element.removeAttribute("data-settled")
      layout.pin(state.nodes[dragging].id, gx, gy)
    },
    onDrop: () => {
      if (dragging >= 0) layout?.unpin(state.nodes[dragging].id)
      dragging = -1
    },
    onClick: (x, y) => select(hit(x, y)),
    onEscape: () => select(-1),
    onHover: (x, y) => {
      const index = dragging < 0 ? hit(x, y) : -1
      canvas.style.cursor = index >= 0 ? "pointer" : ""
      tooltip.hidden = index < 0
      if (index < 0) return
      tooltip.textContent = state.nodes[index].title
      tooltip.style.left = `${x + 14}px`
      tooltip.style.top = `${y + 14}px`
    },
```

`hit` must be the function `mount` defines (move its definition above `attachInput`), and `onPress` answers `dragging + 1` because index 0 is falsy. `unpin` without a preceding `pin` (a plain click) must do no harm: in the worker it clears `fx`/`fy` and calls `run()`, which resettles from the current alpha — check that a plain click does not visibly shake the graph, and if it does, send `unpin` only when `pin` was sent (track it in a flag).

`destroy()` gains `card.hide()`.

- [ ] **Step 7: Run the tests**

Run: `PGGSSENCMODE=disable bin/rails test test/system/admin/mind_graph_test.rb test/lib`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: a click selects a node and opens its card — open the post, focus the graph, list the tag's posts; hover names it, a drag moves it"
```

---

### Task 8: The local view's bar and the search field

**Files:**
- Create: `app/javascript/mind_graph/search_box.js`
- Modify: `app/views/admin/mind_graph/show.html.erb`, `app/javascript/mind_graph/app.js`, `config/locales/admin/mind_graph.en.yml`
- Test: `test/system/admin/mind_graph_test.rb`, `test/integration/admin/mind_graph_test.rb`

**Interfaces:**
- Consumes: `search_admin_mind_graph_path` (Task 4), `createSuggestions` from `search/suggestions` (`{ url, getQuery, onRows(query, rows), onError }` → an object with `schedule()` and `cancel()`; read the module's header for its guarantees), `@focus` / `@depth` (Task 6).
- Produces: `attachSearch(field, list, { url, text }) → stop()`.
- The local view's focus is already drawn with a dashed accent ring (`focusIndex`, Task 6) and always labelled.

- [ ] **Step 1: Strings**

Under `admin.mind_graph.show`:

```yaml
        focus:
          around_post: "Around “%{title}”"
          around_tag: "Around the tag “%{title}”"
          depth: "Depth"
          whole: "Whole graph"
        search:
          label: "Find a post or tag"
          placeholder: "Find a post or tag…"
```

Under `admin.mind_graph.script`:

```yaml
        search:
          none: "No post or tag matches."
          failed: "Search failed — check your connection."
          post: "Post"
          tag: "Tag"
```

Add `search.none search.failed search.post search.tag` (prefixed) to `messages_data`.

- [ ] **Step 2: Write the failing tests**

Integration, in `test/integration/admin/mind_graph_test.rb`:

```ruby
  test "a focused view names its focus, offers both depths and the way back" do
    sign_in_as(users(:one))
    post = create_post(title: "Alpha")

    get "/cs-studio/mind_graph", params: { post: post.id }

    assert_select "[data-mind-graph-focus]", text: /Around “Alpha”/
    assert_select "[data-mind-graph-focus] a[href='/cs-studio/mind_graph?depth=2&post=#{post.id}']", text: "2"
    assert_select "[data-mind-graph-focus] [aria-current='true']", text: "1"
    assert_select "[data-mind-graph-focus] a[href='/cs-studio/mind_graph']", text: "Whole graph"

    get "/cs-studio/mind_graph", params: { post: post.id, depth: 2 }
    assert_select "[data-mind-graph-focus] [aria-current='true']", text: "2"
    assert_select "[data-mind-graph-focus] a", text: "1"
  end

  test "the global view has no focus bar, and every view has the search field" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    assert_select "[data-mind-graph-focus]", count: 0
    assert_select "input[type=search][aria-label='Find a post or tag']"
  end
```

The exact `href` strings depend on the order the path helper writes parameters in; assert on the parsed query if the order differs.

System, in `test/system/admin/mind_graph_test.rb`:

```ruby
  test "Focus graph here opens that node's neighbourhood, the depth switch widens it, and Back returns" do
    a, b, c = %w[Alpha Beta Gamma].map { |title| create_post(title: title) }
    PostRelation.create!(post: a, related_post: b)
    PostRelation.create!(post: b, related_post: c)
    visit admin_mind_graph_path
    await_graph

    click_node(a.id)
    within("[data-mind-graph-card]") { click_link "Focus graph here" }

    assert_selector "[data-mind-graph-focus]", text: "Around “Alpha”"
    await_graph
    assert_equal "2", graph["data-nodes"]
    assert_includes graph["data-labelled"].split(","), a.id.to_s, "the focus is always labelled"

    within("[data-mind-graph-focus]") { click_link "2" }
    await_graph
    assert_equal "3", graph["data-nodes"]

    page.go_back
    await_graph
    assert_equal "2", graph["data-nodes"]

    within("[data-mind-graph-focus]") { click_link "Whole graph" }
    assert_no_selector "[data-mind-graph-focus]"
    await_graph
    assert_equal "3", graph["data-nodes"]
  end

  test "search finds a post the global view does not draw and opens its neighbourhood" do
    a = create_post(title: "Connected")
    PostRelation.create!(post: a, related_post: create_post(title: "Also connected"))
    alone = create_post(title: "Hidden gem")
    visit admin_mind_graph_path
    await_graph
    assert_nil screen_position(alone.id)

    fill_in "Find a post or tag", with: "hidden"
    within("[data-mind-graph-results]") { click_link "Hidden gem" }

    assert_selector "[data-mind-graph-focus]", text: "Around “Hidden gem”"
    await_graph
    assert_equal "1", graph["data-nodes"]
  end

  test "search lists tags too, says when nothing matches, and Escape closes the list" do
    2.times { |i| create_post(title: "P#{i}", tags: [ "ruby" ]) }
    visit admin_mind_graph_path
    await_graph

    fill_in "Find a post or tag", with: "rub"
    within("[data-mind-graph-results]") { assert_link "ruby" }

    fill_in "Find a post or tag", with: "zzzz"
    assert_selector "[data-mind-graph-results]", text: "No post or tag matches."

    find_field("Find a post or tag").send_keys(:escape)
    assert_no_selector "[data-mind-graph-results]", visible: :visible
  end
```

- [ ] **Step 3: Run to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/integration/admin/mind_graph_test.rb test/system/admin/mind_graph_test.rb`
Expected: the new tests FAIL.

- [ ] **Step 4: The view**

In `show.html.erb`, between the heading block and the `if @content_types.empty?`, and only when there are posts (move it inside the `else` branch, above the box):

```erb
  <div class="mb-3 flex flex-wrap items-center justify-between gap-x-6 gap-y-2">
    <% if @focus %>
      <%# The local view's bar: what the graph is drawn around, both depths (the
          current one is text, the other a link -- ordinary visits, so Back
          works) and the way back to the whole graph. %>
      <p data-mind-graph-focus class="m-0 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-dim">
        <span class="font-semibold text-ink"><%= t(".focus.around_#{@focus.kind}", title: @focus.title) %></span>
        <span class="inline-flex items-center gap-1.5"><%= t(".focus.depth") %>
          <% [ 1, 2 ].each do |depth| %>
            <% if depth == @depth %>
              <span aria-current="true" class="font-semibold text-ink"><%= depth %></span>
            <% else %>
              <%= link_to depth, admin_mind_graph_path(**admin_url_options, @focus.kind => @focus.id, depth: (depth if depth == 2)), class: "text-accent underline" %>
            <% end %>
          <% end %>
        </span>
        <%= link_to t(".focus.whole"), admin_mind_graph_path(**admin_url_options), class: "text-accent underline" %>
      </p>
    <% else %>
      <span></span>
    <% end %>
    <%# The search field: how a post or tag the graph doesn't draw is reached.
        Its rows are links to that row's local view. %>
    <div class="relative w-72 max-w-full" data-mind-graph-search data-url="<%= search_admin_mind_graph_path(**admin_url_options) %>">
      <input type="search" autocomplete="off" aria-label="<%= t(".search.label") %>" placeholder="<%= t(".search.placeholder") %>"
             class="w-full rounded-cs border border-line-strong bg-surface px-2.5 py-1.5 text-sm text-ink">
      <ul data-mind-graph-results hidden class="absolute left-0 right-0 top-full z-20 m-0 mt-1 list-none rounded-cs border border-line-strong bg-surface p-1 shadow-cs"></ul>
    </div>
  </div>
```

The search block must be INSIDE the controller's element for `messages(element)` and for `mount` to find it: wrap the bar and the box in one `div data-controller="admin--mind-graph"` and move the box's layout classes to an inner div, keeping every data attribute on the outer element. Use the input classes the other CS Studio search fields use (the posts list's) instead of the ones above if they differ.

- [ ] **Step 5: The search box module**

`app/javascript/mind_graph/search_box.js`:

```js
// The mind graph's search field (mind graph canvas spec §5.5): readable posts
// and tags by name, each row a LINK to that row's local view -- so a result is
// opened like any other link, by click, Enter or a new tab, and Back returns.
// Debounce, one request at a time and the stale-answer guard are
// `search/suggestions.js`'s, shared with the chip input and the link search.
import { createSuggestions } from "search/suggestions"

export function attachSearch(field, list, { url, text }) {
  const close = () => {
    list.hidden = true
    list.replaceChildren()
  }
  const say = (line) => {
    const item = document.createElement("li")
    item.className = "px-2 py-1.5 text-sm text-meta"
    item.textContent = line
    list.replaceChildren(item)
    list.hidden = false
  }

  const suggestions = createSuggestions({
    url,
    getQuery: () => field.value.trim(),
    onRows: (_query, rows) => {
      if (rows.length === 0) return say(text.t("mind_graph.script.search.none"))

      list.replaceChildren(...rows.map((row) => {
        const item = document.createElement("li")
        const link = document.createElement("a")
        link.href = row.url
        link.className = "flex items-baseline justify-between gap-3 rounded-cs px-2 py-1.5 text-sm text-ink hover:bg-sunken"
        const label = document.createElement("span")
        label.textContent = row.label
        const kind = document.createElement("span")
        kind.className = "text-label text-meta"
        kind.textContent = text.t(`mind_graph.script.search.${row.kind}`)
        link.append(label, kind)
        item.append(link)
        return item
      }))
      list.hidden = false
    },
    onError: () => say(text.t("mind_graph.script.search.failed"))
  })

  const input = () => {
    if (field.value.trim() === "") {
      suggestions.cancel()
      close()
    } else {
      suggestions.schedule()
    }
  }
  const keydown = (event) => {
    if (event.key !== "Escape") return
    suggestions.cancel()
    close()
  }
  field.addEventListener("input", input)
  field.addEventListener("keydown", keydown)

  return () => {
    suggestions.cancel()
    field.removeEventListener("input", input)
    field.removeEventListener("keydown", keydown)
  }
}
```

Read `app/javascript/search/suggestions.js` in full first: use its real option names, the query parameter name it sends (the endpoint reads `q` — if the module sends another name, pass it through `params`), and its real method names for "ask after the delay" and "cancel".

- [ ] **Step 6: Wire it**

In `app.js`'s `mount`:

```js
  const search = element.querySelector("[data-mind-graph-search]")
  const stopSearch = attachSearch(search.querySelector("input"), search.querySelector("[data-mind-graph-results]"), { url: search.dataset.url, text })
```

with the import, and `stopSearch()` in `destroy()`.

- [ ] **Step 7: Run the tests**

Run: `PGGSSENCMODE=disable bin/rails test test/integration/admin/mind_graph_test.rb test/system/admin/mind_graph_test.rb test/lib`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: the mind graph's local view names its focus and both depths, and a search field reaches any post or tag"
```

---

### Task 9: The list of links, and the screen joins the i18n guard

**Files:**
- Create: `app/javascript/mind_graph/node_list.js`
- Modify: `app/views/admin/mind_graph/show.html.erb`, `app/javascript/mind_graph/app.js`, `config/locales/admin/mind_graph.en.yml`, `test/lib/admin_i18n_test.rb`
- Test: `test/system/admin/mind_graph_test.rb`

**Interfaces:**
- Consumes: `state.nodes`, `state.visibleNodes`, the focus URL templates (Task 7).
- Produces: `renderList(container, { nodes, text, urls })`, called after the data arrives and after every filter change.
- The list is `<details data-mind-graph-list>` below the box.

- [ ] **Step 1: Strings**

`admin.mind_graph.show`: `list_summary: "List of posts and tags in this graph"`.
`admin.mind_graph.script`:

```yaml
        list:
          posts: "Posts"
          tags: "Tags"
          edit: "Edit"
          connections:
            one: "%{count} connection"
            other: "%{count} connections"
```

Add them to `messages_data`.

- [ ] **Step 2: Write the failing tests**

```ruby
  test "the list below the graph holds every drawn node as a link, and follows the filter" do
    a = create_post(title: "Alpha", tags: [ "shared" ])
    b = create_post(title: "Beta", tags: [ "shared" ])
    c = create_post(title: "Gamma")
    PostRelation.create!(post: a, related_post: c)
    tag = Tag.find_by!(name: "shared")
    visit admin_mind_graph_path
    await_graph

    find("[data-mind-graph-list] summary", text: "List of posts and tags in this graph").click
    within("[data-mind-graph-list]") do
      assert_link "Alpha", href: /mind_graph\?post=#{a.id}\z/
      assert_link "shared", href: /mind_graph\?tag=#{tag.id}\z/
      assert_selector "li", text: /Alpha.*2 connections/
      assert_selector "li", text: /Gamma.*1 connection\b/
      assert_selector "a[href='#{admin_post_path(a)}']", text: "Edit"
      assert_selector "li", count: 4
    end

    find("label", text: "Related").click
    await_graph
    within("[data-mind-graph-list]") do
      assert_selector "li", count: 2
      assert_no_link "Beta"
      assert_no_link "shared"
    end
  end

  test "the whole screen works from the keyboard: the list's link opens a node's neighbourhood" do
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))
    visit admin_mind_graph_path
    await_graph

    summary = find("[data-mind-graph-list] summary")
    summary.send_keys(:enter)
    link = find("[data-mind-graph-list] a", text: "Alpha")
    link.send_keys(:enter)

    assert_selector "[data-mind-graph-focus]", text: "Around “Alpha”"
  end

  test "the canvas pans and zooms from the keyboard" do
    a = create_post(title: "A")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph
    canvas = find("#{GRAPH} canvas")
    zoom = graph["data-zoom"].to_f
    before = screen_position(a.id)

    canvas.send_keys("+")
    await_js("Number(document.querySelector(#{GRAPH.to_json}).dataset.zoom) > #{zoom}")
    canvas.send_keys("-")
    await_js("Math.abs(Number(document.querySelector(#{GRAPH.to_json}).dataset.zoom) - #{zoom}) < 0.002")
    canvas.send_keys(:right)
    await_js("document.querySelector(#{GRAPH.to_json}).mindGraph.screenPosition(#{a.id}).x < #{before["x"]} - 30")
  end

  # Review focus 1.
  test "a title with markup in it is text in the list and in the search results" do
    nasty = %(<img src=x onerror="window.pwned=1"> & co)
    a = create_post(title: nasty)
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph

    find("[data-mind-graph-list] summary").click
    within("[data-mind-graph-list]") { assert_link nasty }
    fill_in "Find a post or tag", with: "onerror"
    within("[data-mind-graph-results]") { assert_link nasty }

    assert_no_selector "[data-mind-graph-list] img, [data-mind-graph-results] img", visible: :all
    assert_nil page.evaluate_script("window.pwned")
  end
```

- [ ] **Step 3: Run to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/system/admin/mind_graph_test.rb`
Expected: the list tests FAIL; the keyboard pan/zoom test may already pass (Task 6's `input.js`) — that is fine, it pins it.

- [ ] **Step 4: The view**

Below the box, inside the controller's element:

```erb
  <%# The keyboard and screen-reader path (mind graph canvas spec §5.7): a
      canvas's nodes can't take focus, so every node the graph draws is also a
      link here, filled by `mind_graph/node_list.js` from the same data and
      following the filter. %>
  <details data-mind-graph-list class="mt-3 rounded-cs border border-line bg-surface px-3.5 py-2.5 text-sm">
    <summary class="cursor-pointer text-dim"><%= t(".list_summary") %></summary>
    <div data-mind-graph-list-body class="mt-2 grid gap-x-8 gap-y-3 sm:grid-cols-2"></div>
  </details>
```

- [ ] **Step 5: The module**

`app/javascript/mind_graph/node_list.js`:

```js
// Every node the graph draws, as a link (mind graph canvas spec §5.7): the
// path for a keyboard and a screen reader, since nothing on a canvas can take
// focus. Two lists, posts and tags, best-connected first as on the canvas; a
// row links to the node's local view and says how many connections it has,
// and a post's row links to its editor too. Text goes in with `textContent`.
export function renderList(container, { nodes, text, urls }) {
  const section = (title, rows) => {
    const wrapper = document.createElement("section")
    const heading = document.createElement("h2")
    heading.className = "m-0 mb-1 text-label text-meta"
    heading.textContent = title
    const list = document.createElement("ul")
    list.className = "m-0 flex list-none flex-col gap-1 p-0"
    list.append(...rows)
    wrapper.append(heading, list)
    return wrapper
  }
  const row = (node) => {
    const item = document.createElement("li")
    item.className = "flex flex-wrap items-baseline gap-x-2"
    const focus = document.createElement("a")
    focus.className = "text-ink underline"
    focus.textContent = node.title
    focus.href = node.kind === "tag"
      ? urls.tagFocus.replace("__ID__", String(node.id).replace("tag-", ""))
      : urls.postFocus.replace("__ID__", node.id)
    const count = document.createElement("span")
    count.className = "text-meta"
    count.textContent = text.t("mind_graph.script.list.connections", { count: node.degree })
    item.append(focus, count)
    if (node.kind === "post") {
      const edit = document.createElement("a")
      edit.className = "text-accent underline"
      edit.textContent = text.t("mind_graph.script.list.edit")
      edit.href = node.url
      edit.setAttribute("aria-label", `${text.t("mind_graph.script.list.edit")}: ${node.title}`)
      item.append(edit)
    }
    return item
  }
  const byDegree = (a, b) => b.degree - a.degree || String(a.title).localeCompare(String(b.title))
  const posts = nodes.filter((node) => node.kind === "post").sort(byDegree)
  const tags = nodes.filter((node) => node.kind === "tag").sort(byDegree)

  container.replaceChildren(
    ...(posts.length ? [ section(text.t("mind_graph.script.list.posts"), posts.map(row)) ] : []),
    ...(tags.length ? [ section(text.t("mind_graph.script.list.tags"), tags.map(row)) ] : [])
  )
}
```

- [ ] **Step 6: Wire it**

In `app.js`, at the end of `applyFilter()`:

```js
    renderList(listBody, { nodes: state.visibleNodes.map((index) => state.nodes[index]), text,
      urls: { postFocus: element.dataset.postFocusUrl, tagFocus: element.dataset.tagFocusUrl } })
```

with `const listBody = element.querySelector("[data-mind-graph-list-body]")` near the top of `mount` and the import. `applyFilter()` runs once per load and once per filter change, never per frame.

- [ ] **Step 7: The i18n guard**

Add to `CONVERTED` in `test/lib/admin_i18n_test.rb` (the view and the legend went in with Task 6; confirm they are there):

```
    app/javascript/controllers/admin/mind_graph_controller.js
    app/javascript/mind_graph/app.js
    app/javascript/mind_graph/card.js
    app/javascript/mind_graph/node_list.js
    app/javascript/mind_graph/search_box.js
```

Read the guard's header first: if it holds script files to its rules only under certain paths, list them the way it expects. Run it and fix what it finds — a class name or a message key it mistakes for copy is handled the way the file's header says (never by loosening a rule).

Run: `PGGSSENCMODE=disable bin/rails test test/lib/admin_i18n_test.rb`
Expected: PASS.

- [ ] **Step 8: Run everything**

Run:
```
PGGSSENCMODE=disable bin/rails test
bin/rails tailwindcss:build && PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test:system
bin/rubocop && bin/brakeman -q && bin/importmap audit
```
Expected: all PASS.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: every node of the mind graph is also a link in a list below it, and the screen joins the i18n guard"
```

---

### Task 10: Measure, set the cap, and write it down

**Files:**
- Create: `script/dev/mind_graph_posts.rb`
- Modify: `app/queries/post_graph.rb` (`CAP`, only if the numbers say so), `docs/superpowers/specs/2026-10-07-mind-graph-canvas-design.md` (§7 numbers, status), `docs/reference/cs-studio-shell-and-dashboard.md` (the Mind graph section), `docs/roadmap.md`, `CLAUDE.md` (reference index), `test/integration/admin/invariants_test.rb` (its header comment, if it names the old query)

**Interfaces:**
- Consumes: `Posts::Save` (`attributes:` with `tag_names`, `related_post_ids`; `translations:`), the trusted channel the seeds use.

- [ ] **Step 1: The data set script**

`script/dev/mind_graph_posts.rb`:

```ruby
# Builds a large, connected set of posts in DEVELOPMENT for measuring the mind
# graph (mind graph canvas spec §7). Through `Posts::Save`, like the seeds, so
# every derived row is what a real site would hold.
#
#   bin/rails runner script/dev/mind_graph_posts.rb 2000
#
# Shape: a few hubs, many posts with two or three links, a tail with none; a
# few dozen tags, some very common. Deterministic (a fixed seed), and safe to
# run again: titles are numbered, and a run adds only what is missing.
abort "development only" unless Rails.env.development?

count = Integer(ARGV.fetch(0, "2000"))
random = Random.new(20261007)
tags = 60.times.map { |i| "graph-tag-#{i}" }

Current.set(actor: nil, channel: :console) do
  existing = Post.i18n.where("title LIKE ?", "Graph post %").count # sql: a one-off development script's own prefix match
  ids = Post.where(id: Post.order(:id).last(existing).map(&:id)).pluck(:id)

  (existing...count).each do |number|
    # Preferential attachment: an earlier post is the likelier target the lower
    # its number, which is what makes hubs.
    related = number < 3 || random.rand < 0.2 ? [] : Array.new(random.rand(1..3)) { ids[(random.rand**3 * ids.size).floor] }.compact.uniq
    names = random.rand < 0.3 ? [] : Array.new(random.rand(1..3)) { tags[(random.rand**2 * tags.size).floor] }.uniq
    result = Posts::Save.call(
      attributes: { content_type: "blog", published: random.rand < 0.8, tag_names: names, related_post_ids: related },
      translations: { Locales.default => { title: "Graph post #{number}" } }
    )
    abort result.errors.to_sentence unless result.ok?
    ids << result.record.id
    puts "#{number + 1} / #{count}" if ((number + 1) % 250).zero?
  end
end
```

Before running it, read `db/seeds.rb` and `test/support/content_helper.rb` for how a trusted write is made (the channel's real name, and what `Posts::Save.call` returns — `result.record` may be named otherwise), and `app/models/post.rb` for how a title is matched; fix the three guesses above against them. The `LIKE` line must satisfy `test/lib/sql_strings_test.rb` if that guard looks at `script/`; if it does, use `Post.title_matching("Graph post", locale: Locales.default)` instead.

- [ ] **Step 2: Measure at 2,000 and at 6,000**

With `bin/dev` running and Chrome's DevTools open on `/cs-studio/mind_graph`, record for each size:

- the data endpoint's response time and transferred size (Network tab; and `capture_sql`-style statement count from the development log);
- time from navigation to the first drawn frame and to `data-settled`;
- frame time while panning during and after settling (Performance tab; the bar is 16 ms, and 33 ms is the limit of acceptable);
- memory after settling.

Run 6,000 to see the cap at work: the message must read "Showing the 2,000 best-connected of … posts."

- [ ] **Step 3: Decide the cap**

If panning stays under 33 ms a frame at 2,000 and the endpoint answers in under a second, `CAP` stays 2,000. If not, lower it to the largest round number that does and say so. Do not raise it above 2,000 without asking.

- [ ] **Step 4: Write the numbers into the spec**

In the spec's §7 "Measurement", replace the bullet "Recorded in this spec once measured: …" with a table of the measured values for both sizes, the machine they were taken on, and the cap they led to. Set the spec's status line to `**Status: implemented** (branch \`mind-graph-canvas\`, plan \`docs/superpowers/plans/2026-10-07-mind-graph-canvas.md\`).` and add a "§11 Where the build departs from this spec" section listing every departure made while building (an empty list is stated as "None.").

- [ ] **Step 5: The reference**

Rewrite the "## Mind graph" section of `docs/reference/cs-studio-shell-and-dashboard.md` and the file's "Describes:" line (`app/queries/post_graph/`, `app/javascript/mind_graph/`). It must say, in the file's own style:

- the two modes and their URLs, the two JSON reads, and that a focus outside scope is not found;
- the data's shape, `degree`, `total` / `shown` / `isolated`, the cap and how each query cuts;
- the tag rule (readable count; two edges globally, one locally; the focused tag always);
- that the page holds no data and why;
- the worker, why d3-force is imported by URL, and that nothing else loads it;
- the modules and what each owns;
- the node shapes, including the retired type's stroke, and the label rule;
- the selection card, the list of links and the state the element exposes for tests.

- [ ] **Step 6: The roadmap and CLAUDE.md**

Re-read `docs/roadmap.md` immediately before editing it (another session may have changed it). Move "Mind graph on a canvas" from the ordered list to the table of finished work with this spec's file name, renumber the list, and add two items where the roadmap keeps later ideas: "A post's neighbourhood in the post editor (an embedded mind graph panel)" and "WebGL rendering for sites beyond the mind graph's cap". Mark the lazy-loading item (S13) as done for d3-force only; Tiptap's is still open. Commit the roadmap alone.

In `CLAUDE.md`'s reference index, extend the CS Studio shell line's file list with `app/queries/post_graph/` and `app/javascript/mind_graph/`.

- [ ] **Step 7: Full verification**

Run:
```
PGGSSENCMODE=disable bin/rails test
bin/rails tailwindcss:build && PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test:system
bin/rubocop && bin/brakeman -q && bin/bundler-audit && bin/importmap audit && bin/rails zeitwerk:check
```
Expected: all PASS. Name every failure in the report, with its output.

- [ ] **Step 8: Commit**

```bash
git add script/dev/mind_graph_posts.rb app/queries/post_graph.rb docs/superpowers docs/reference CLAUDE.md test
git commit -m "docs: the mind graph on a canvas — the measured numbers, the cap, the reference and the index"
git add docs/roadmap.md
git commit -m "docs: the roadmap — the mind graph on a canvas is done; the editor panel and WebGL are later items"
```
