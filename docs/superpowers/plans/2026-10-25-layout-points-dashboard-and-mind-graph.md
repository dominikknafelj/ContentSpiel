# The layout points, part 2: the dashboard and the Mind graph — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The second of the spec's three pull requests, "the dashboard and the Mind graph" (its sections C and D): the dashboard's cards in at most three columns, one quiet empty line per card in Claude Design's O6 words, Recent activity collapsing a run of the same person's block edits or uploads into one counted row, the activity row's two-letter circle (O9), the Mind graph's legend in two visible groups "Show" and "Key" with "Status key…" last (O5), a first view and "Fit all" that fill about 80% of the canvas, and a page's notes badge drawn outside its card (O11's Mind graph half).

**Architecture:** The grid is one container query on a wrapper of the dashboard's view. The empty line is `Admin::DashboardScreen::CardComponent`'s own markup with an `empty_action` slot; `Admin::Ui::EmptyStateComponent` is not touched. The collapse is `Dashboard::Activity`'s, in Ruby over the events its one event query already read (that query reads four times the row limit), so the statement count does not move; the counted wording is `Audit::Sentence`'s (`count:`, `mixed:`, a new `:collection` part), drawn by `Admin::AuditScreen::SentenceComponent`. The Mind graph's changes are a component's markup, one pure function's numbers (`camera.fit`) and the notes badge's drawing (outside a page's card, drawn last on a ring of the ground, an obstacle the label rule already knows how to avoid); no query, no script-written state, nothing new for `reset()` to take back.

**Tech Stack:** Rails 8.1, ViewComponent, Tailwind 4 (`tailwindcss-rails`, container queries), Stimulus over import maps, a 2D canvas, Minitest + fixtures, Capybara on Cuprite.

**Spec:** `docs/superpowers/specs/2026-10-23-layout-points-design.md` (approved 2026-10-24). Read "What a person gets" C and D, Decisions 11–15, Rulings 5 and 7, Claude Design's answers O5 and O6 and the owner's O9, O10 and O11, and "As built (part 1)". Part 1's plan, `docs/superpowers/plans/2026-10-24-layout-points-forms-and-lists.md`, is the style this one follows. Section E (the public site), Decisions 16–17 and Ruling 8 are plan 3's and not this one's.

## Global Constraints

- Read `CLAUDE.md` first; its rules bind. Before a task read the reference its area names: `docs/reference/cs-studio-shell-and-dashboard.md` (every task; its "Mind graph" part for Tasks 6–8: the legend is a filter that moves nothing, swatches are the renderer's drawings, the Tab order is search, graph, list, `reset()` takes back what a script writes, no clock read, the viewer's scope), `docs/reference/access-control-and-audit.md` (Tasks 3, 4), `docs/reference/design-system.md` (Tasks 1, 2, 6), `docs/reference/i18n.md` (any task adding a key; `Audit::Sentence` stays English, "Out of scope, named").
- Dashboard grid (Decision 13): one column below **40rem** (640px) of the dashboard's width, two from 40rem, **three from 60rem** (960px), never more; no `auto-fit`.
- The empty lines (O6 as answered): Your drafts **"No drafts."** + **"Start a draft"**; Going live next **"Nothing scheduled."** + **"Drafts →"** (Claude Design, 2026-10-25, in place of O6's "Your drafts →"); Unpublished changes **"No unpublished changes."**; Needs translation **"Nothing to translate."** (unchanged); Notes for you **"No notes for you."** (unchanged); Open threads **"No open threads."** (unchanged); Recent activity **"No recent activity."** (unchanged). One line in `text-dim`, left-aligned under the card's title where the first row would be. The hint "Schedule a draft to see it here." goes (spec Ruling 5).
- The collapse (Decision 11, O10): a run is adjacent in the feed, the same person (and token), the same counted action, the same page or post (a block's owner; any image for an upload), within `Audit::COALESCE_WINDOW` (10 minutes); `Dashboard::Activity` returns at most **15** rows and reads at most **60** events. The statement count of `Dashboard::Activity#rows` and of the dashboard's page does not change.
- The words (English; `Audit::Sentence` is not converted): "added 4 Code blocks to “X”", "edited 3 blocks on “X”" (mixed types), "uploaded 12 images" (linked to the library, not quoted).
- The legend (O5, Decision 14): a visible mono label "Show" before the toggles and "Key" before the marks; "Status key…" (with U+2026) is the last thing in Key; the Tab order (toggles, then "Status key…", then the zoom buttons) does not change.
- Fit (Decision 15): a margin of **0.1** of the canvas on each side, `MAX_FIT_ZOOM` **3**; a box with no extent is centred at the cap. No measured layout figure in a test (the Mind graph's testing rule; spec Ruling 7: the first view is fitted at `[data-settled]` as today).
- The page's notes badge (Claude Design's K3, `.superpowers/design-answers/2026-10-12-pages-in-mind-graph.md` in the main checkout): outside the card, its right edge **2px** clear of the card's left edge, its centre on the card's top edge. A post's badge is unchanged (4px over the corner).
- New or changed admin strings are keys in `config/locales/admin/*.en.yml` read with `t(".key")`; a converted file joins `CONVERTED` in `test/lib/admin_i18n_test.rb`.
- Tokens, not colours; no text under 11px; a mono label is `font-cs-mono text-label uppercase tracking-mono`.
- Never define an `Admin::` constant named after a top-level domain (`test/lib/admin_namespace_shadow_test.rb`).
- Tests: every command prefixed `PGGSSENCMODE=disable`. One file: `PGGSSENCMODE=disable bin/rails test <path>`; one test: `… -n "/<fragment of its name>/"`. Before any system test: `bin/rails tailwindcss:build && bin/rails theme_css:build`, and **never a build while tests run**; never two test runs at once. The browser suite: `PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system`, on a quiet machine (`sysctl -n vm.loadavg` first).
- System tests: `press` (a native click on a link or button), no fixed `sleep`; a test that resizes the window puts it back to 1400×1400 in an `ensure`; any JavaScript error fails the test.
- Commits: one per task, conventional subject, never `--no-verify`, ending with exactly:

```
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
```

- Nothing is pushed. No guide text in this repository: the guide pages are named in the PR's "Documentation" section (Task 9).

### Rulings of this plan

Where the spec and the design answers left a choice, this plan decides. Each says what it costs if it is wrong.

1. **The window is measured from the run's newest event.** An event joins a run when the run's newest event's `last_occurred_at` minus its own `last_occurred_at` is at most `Audit::COALESCE_WINDOW`. `last_occurred_at` is the feed's sort key, so the measure follows the order a person reads. *If wrong:* a steady session of more than ten minutes splits into a row per ten minutes, never a wrong count.
2. **Only the counted actions collapse**: `Audit::Sentence::COUNTED = %w[block.created block.updated media.uploaded]`, which `Dashboard::Activity::COLLAPSING` is (one list). Every other action stays one row per event, because a counted sentence for it ("published “X” twice") is not designed, and the same record's same edit already coalesces in the audit log. *If wrong:* two quick publishes of one page show as two rows, as today.
3. **"The same person" is `[user_id, actor_type, actor_id]`**: a user is one actor, each token another, so a person's own edits and their token's never join. *If wrong:* a person working in CS Studio and through MCP at once gets two rows.
4. **The count is the number of distinct subjects** in the run (blocks, images), and the type is named only when every event's snapshot names the same `block_type`; otherwise "blocks". The plurals are written by hand ("blocks", "images"): a counted sentence only exists for a count of 2 or more, and `Audit::Sentence` is English by i18n.md's "Out of scope". *If wrong:* nothing in English; the German conversion turns each into one key with `count:`.
5. **The uploads' subject is a new part kind, `:collection`**: linked like a subject, never quoted ("You uploaded 12 images", not "“12 images”"). Its route is `Audit::Sentence.library_route` (`admin_media_path` with no params), a name already on `SentenceComponent::ROUTES`. *If wrong:* one `when` branch.
6. **The read is four times the row limit, collapsed in Ruby.** Sixty newest events that collapse into fewer than fifteen rows show fewer rows, not older ones (Decision 11's cost). `test/queries/dashboard/activity_test.rb`'s "an older readable event is listed after 60 uploads for a viewer without media.upload" changes on purpose: its owner's 60 uploads are now ONE row of 60, not 15 rows.
7. **The activity row's letters are `PersonName.initials` of the name the row shows** (`Admin::Ui::UserNameComponent#label`: the display name, "a deleted user", "System"), drawn upper-case by the style, as `Admin::Ui::AvatarComponent` draws them. "one@example.com" is "ON", "Ada Lovelace" "AL", a deleted user "AD", System "SY". The row keeps its own 28px circle (the shared avatar has no such size). *If wrong:* odd letters for nobody in particular, nothing else.
8. **The empty action is a slot, `empty_action`**, not Decision 12's label and URL: "Start a draft" carries a controller and a fragment. The card draws the slot only when it has no rows.
9. **"Start a draft" is a link to `#dashboard_draft_title`** whose controller, `admin--dashboard--start-draft`, moves the focus to the quick-create title (a fragment alone scrolls and focuses nothing). It is drawn whenever the quick-create row is; without the row, "No drafts." stands alone. "Drafts →" goes to the posts list's drafts (`scope=drafts`) for whoever holds `posts.read`. The words are Claude Design's answer of 2026-10-25 to this plan's first open question: that list holds every draft the viewer can read, and "Your drafts" would claim a filter it does not have (the link can say "Your drafts →" again once a "mine" filter exists).
10. **The empty line's link is ink and underlined** (`text-ink underline`): ink on dim text is not 3:1, so the underline is what tells it apart.
11. **The dashboard's view is converted to keys** (`admin.dashboard.show.*`) and joins `CONVERTED` with the card component, since every card's words change here; `QuickCreateComponent`, `RowComponent` and `TranslationCardComponent` are not converted (their words do not change). The translation card's empty line never shows: the card is hidden when it has nothing (unchanged).
12. **"About 80%" is 10% of the canvas on each side, on the axis that binds.** The fit takes the smaller of the two zooms, so a wide graph fills 80% of the width and less of the height. The box is the nodes' centres, so a mark at the edge reaches a few pixels beyond it, into the margin. *If wrong:* a wide graph on a tall canvas leaves more room above and below; one constant.
13. **The legend's "Show" is a visible label hidden from a screen reader** (`aria-hidden`), because the fieldsets keep their legends "Show" and "Lines" for it (Decision 14); **"Key" labels the list** (`aria-labelledby`), which keeps its marks and no control; **"Status key…" follows the list** inside the Key group, so the list stays a list of marks and the button is still the first stop after the toggles (the marks hold no stop).
14. **K3 moves a page's badge**: Home's card too; a post's badge, the pin and the hit test stay where they are. The renderer's culling margin grows with it (`NODE_MARGIN` 23 → 30: "99+" and its ring now end 30px left of a card's edge).
15. **A badge outside its card covers what it lands on, cleanly** (Claude Design's answer of 2026-10-25 to this plan's second open question, (a)): every notes badge is drawn after every mark and label, on a 2px ring filled with the theme's `surface` (the canvas's ground, a theme key, never a colour), at its node's strength. The layout makes no room for badges. *If wrong:* a badge hides a sliver of a neighbour's mark; one draw-order change.
16. **Labels keep clear of badges** (the same answer, (b)): the badges' boxes, ring included, are obstacles `chooseLabels` refuses a label over, by the rule that already keeps labels apart (`obstacles`, `badgeBoxes`, the geometry one function, `notesBadgeBox`, shared with the renderer). A label still only ever sits right of its node, so one blocked by a badge is not shown. *If wrong:* a label that would have fitted beside a badge is hidden; the rule is one list.

## Review Focus

1. **A run broken by someone else**: Ada adds a block, Ben adds one, Ada adds another, all on one page within ten minutes: three rows, not "Ada added 2" (Task 4: `"a run is broken by another person's event between, by another page and by another action"`).
2. **A block deleted out of a run**: three blocks added, the middle one deleted: the row says 2, and the deleted block's event neither shows nor splits the run (Task 4: `"a block deleted from a run is not counted and does not split it"`).
3. **A reader who may not create anything**: "No drafts." with no "Start a draft", and no dead link; "Drafts →" only with `posts.read` (Task 2: `"someone who may create nothing reads No drafts. alone, and Drafts → only with posts.read"`).
4. **A one-word name in another script**: "Δήμητρα" is "ΔΉ" in the circle, two letters, never one (Task 5: `"a one-word name in another script gives its first two letters"`; part 1's deferred minor).
5. **A keyboard user after the legend moved**: Tab from the last toggle reaches "Status key…" and then the zoom buttons, as before (Task 6: the two tab-order tests in `test/integration/admin/mind_graph_test.rb`, updated only for the button's words).

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `app/assets/tailwind/content-spiel.tailwind.css` | `.admin-dashboard` container, `.admin-dashboard-cards` at 1/2/3 columns | 1 |
| `app/views/admin/dashboard/show.html.erb` | the wrapper and the grid; the empty lines and actions; keys | 1, 2 |
| `config/locales/admin/dashboard.en.yml` | the view's keys | 2 |
| `app/components/admin/dashboard_screen/card_component.{rb,html.erb}` | the one-line empty state, `empty_action`; no `hint:` | 2 |
| `app/javascript/controllers/admin/dashboard/start_draft_controller.js` (new) | "Start a draft" focuses the quick-create title | 2 |
| `app/models/audit/sentence.rb` | `COUNTED`, `count:`/`mixed:`, `:collection`, `library_route` | 3 |
| `app/components/admin/audit_screen/sentence_component.rb` | draws `:collection` | 3 |
| `app/queries/dashboard/activity.rb` | the runs, `Row#count`, `READ_FACTOR` | 4 |
| `app/components/admin/dashboard_screen/activity_row_component.{rb,html.erb}` | `initials` | 5 |
| `app/components/admin/mind_graph_screen/legend_component.html.erb`, `config/locales/admin/mind_graph_screen.en.yml` | Show and Key; "Status key…" last | 6 |
| `app/javascript/mind_graph/camera.js` | `FIT_MARGIN`, `MAX_FIT_ZOOM` | 7 |
| `app/javascript/mind_graph/marks.js`, `renderer.js`, `labels.js`, `app.js` | `notesBadgeBox`; a page's badge outside its card, badges drawn last on a ring; `NODE_MARGIN`; labels' `obstacles` and `badgeBoxes` | 8 |
| `CLAUDE.md`, `docs/reference/*.md`, `docs/roadmap.md`, the spec | documents | 9 |

---

### Task 1: The dashboard's cards in at most three columns

**Files:**
- Modify: `app/assets/tailwind/content-spiel.tailwind.css` (after the section lanes block, about line 545)
- Modify: `app/views/admin/dashboard/show.html.erb` (a wrapper around the whole view; the grid `div`'s classes)
- Test: `test/system/admin/dashboard_test.rb`, `test/lib/admin_design_rules_test.rb`

**Interfaces:**
- Produces: classes `.admin-dashboard` (the container, named `admin-dashboard`) and `.admin-dashboard-cards` (the grid). Task 2's view edits keep both.

- [ ] **Step 1: Write the failing tests**

In `test/system/admin/dashboard_test.rb`, a helper and two tests:

```ruby
  # The cards' grid (layout points spec, C and decision 13): three columns at
  # most, by the dashboard's own width. Six cards (two languages, so "Needs
  # translation" is drawn) make the 3×2 the design asked for.
  def card_grid
    page.evaluate_script(<<~JS)
      (() => {
        const grid = document.querySelector(".admin-dashboard-cards")
        const cards = Array.from(grid.querySelectorAll(":scope > section, :scope > turbo-frame > section"))
        return { columns: getComputedStyle(grid).gridTemplateColumns.split(" ").length, cards: cards.length,
                 rows: new Set(cards.map((card) => Math.round(card.getBoundingClientRect().top))).size }
      })()
    JS
  end

  test "the cards stand three in a row at 1600px and at 1400px, two rows of three, and one in a row at 600px" do
    with_locales(%w[en de], default: "en")
    create_post(title: "Untranslated")
    sign_in_via_form(users(:one))
    begin
      [ [ 1600, 3, 2 ], [ 1400, 3, 2 ], [ 600, 1, 6 ] ].each do |width, columns, rows|
        page.driver.resize(width, 1000)
        visit admin_root_path
        await_admin_controllers
        assert_equal({ "columns" => columns, "cards" => 6, "rows" => rows }, card_grid, "at #{width}px")
      end
    ensure
      page.driver.resize(1400, 1400)
    end
  end
```

In `test/lib/admin_design_rules_test.rb`:

```ruby
  # Layout points spec, decision 13: at most three cards in a row, by the
  # dashboard's own width, never `auto-fit`.
  test "the dashboard's grid is one, two or three columns by its container, and never auto-fit" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/\.admin-dashboard\s*\{\s*container:\s*admin-dashboard\s*\/\s*inline-size;\s*\}/, css)
    assert_match(/@container admin-dashboard \(min-width: 40rem\)\s*\{\s*\.admin-dashboard-cards\s*\{\s*grid-template-columns:\s*repeat\(2, minmax\(0, 1fr\)\);/m, css)
    assert_match(/@container admin-dashboard \(min-width: 60rem\)\s*\{\s*\.admin-dashboard-cards\s*\{\s*grid-template-columns:\s*repeat\(3, minmax\(0, 1fr\)\);/m, css)
    assert_no_match(/auto-fit/, Rails.root.join("app/views/admin/dashboard/show.html.erb").read)
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/lib/admin_design_rules_test.rb -n "/dashboard's grid/"`, then `bin/rails tailwindcss:build && bin/rails theme_css:build` and `PGGSSENCMODE=disable bin/rails test test/system/admin/dashboard_test.rb -n "/three in a row/"`
Expected: FAIL — the rules are not in the stylesheet; `.admin-dashboard-cards` is not found (`grid` is null).

- [ ] **Step 3: The stylesheet and the view**

In `content-spiel.tailwind.css`, after the section lanes' `@container (min-width: 40rem)` block, with a comment saying the breakpoints are the dashboard's own width (the tree is absent here but the sidebar and the notes column are not), that a wider window widens the cards and never adds a fourth, and that `turbo-frame.contents` keeps the notes cards grid items:

```css
.admin-dashboard { container: admin-dashboard / inline-size; }
.admin-dashboard-cards { display: grid; gap: 1rem; grid-template-columns: minmax(0, 1fr); }
@container admin-dashboard (min-width: 40rem) {
  .admin-dashboard-cards { grid-template-columns: repeat(2, minmax(0, 1fr)); }
}
@container admin-dashboard (min-width: 60rem) {
  .admin-dashboard-cards { grid-template-columns: repeat(3, minmax(0, 1fr)); }
}
```

In `show.html.erb`: wrap everything after the leading comment in `<div class="admin-dashboard">…</div>`; the grid's `class="grid grid-cols-[repeat(auto-fit,minmax(min(300px,100%),1fr))] gap-4"` becomes `class="admin-dashboard-cards"`; the header comment's "an auto-fit grid" becomes "a grid of at most three columns (`.admin-dashboard-cards`)".

- [ ] **Step 4: Run them to see them pass**

Run: `bin/rails tailwindcss:build && bin/rails theme_css:build`, then `PGGSSENCMODE=disable bin/rails test test/lib/admin_design_rules_test.rb test/system/admin/dashboard_test.rb test/integration/admin/dashboard_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/assets/tailwind/content-spiel.tailwind.css app/views/admin/dashboard/show.html.erb test/system/admin/dashboard_test.rb test/lib/admin_design_rules_test.rb
git commit -m "feat(dashboard): at most three cards in a row, by the dashboard's own width

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 2: One quiet empty line per card, with its action (O6)

**Files:**
- Modify: `app/components/admin/dashboard_screen/card_component.rb` (the `hint:` keyword and its comment go; `renders_one :empty_action`), `card_component.html.erb` (the empty line replaces `EmptyStateComponent`; the hint paragraph goes)
- Modify: `app/views/admin/dashboard/show.html.erb` (every literal becomes a key; the empty lines and actions)
- Modify: `config/locales/admin/dashboard.en.yml`
- Create: `app/javascript/controllers/admin/dashboard/start_draft_controller.js`
- Modify: `test/components/previews/admin/dashboard_screen/card_component_preview.rb` (no `hint:`; the preview "short_list_with_hint" becomes "empty_with_action")
- Modify: `test/lib/admin_i18n_test.rb` (`CONVERTED` gains the view and the card component's two files)
- Test: `test/components/admin/dashboard_screen/card_component_test.rb`, `test/integration/admin/dashboard_test.rb`, `test/system/admin/dashboard_test.rb`

**Interfaces:**
- Produces: `Admin::DashboardScreen::CardComponent.new(title:, id:, empty:, link: nil, limit: LIMIT)` with slots `rows`, `badge`, `action`, `footer`, `empty_action`; the empty line is `p[data-card-empty]`. Stimulus `admin--dashboard--start-draft` (value `field`, action `start`).
- Keys (`admin.dashboard.show`): `title`, `drafts.{title,empty,start,all}`, `going_live.{title,empty,drafts_html,all}`, `unpublished_changes.{title,empty}`, `activity.{title,empty,audit_log_html}`.

- [ ] **Step 1: Write the failing component tests**

In `card_component_test.rb`, replace the test "empty shows its sentence in the card, no arrow without a link, and the hint when given" with:

```ruby
  # Layout points spec, decision 12 and Claude Design's O6: an empty card says
  # one line in dim, left-aligned where its first row would be, with its
  # action (if any) after it. No centred bold title, no 48px of padding.
  test "an empty card says one line where its first row would be, in dim, with its action after it" do
    render_inline Admin::DashboardScreen::CardComponent.new(title: "Your drafts", id: "d", empty: "No drafts.") do |card|
      card.with_empty_action { '<a href="#x">Start a draft</a>'.html_safe }
    end

    assert_selector "section > header + p[data-card-empty].px-4.text-sm.text-dim", text: /\ANo drafts\.\s+Start a draft\z/
    assert_selector "p[data-card-empty] a[href='#x']", text: "Start a draft"
    assert_no_selector ".admin-empty-state, h3, ul"
  end

  test "an empty card without an action says its line alone, and a card with rows draws neither" do
    render_inline Admin::DashboardScreen::CardComponent.new(title: "Going live next", id: "g", empty: "Nothing scheduled.")
    assert_selector "p[data-card-empty]", exact_text: "Nothing scheduled."
    assert_no_selector "a"

    render_inline Admin::DashboardScreen::CardComponent.new(title: "Your drafts", id: "d", empty: "No drafts.") do |card|
      card.with_row { "A row" }
      card.with_empty_action { '<a href="#x">Start a draft</a>'.html_safe }
    end
    assert_no_selector "p[data-card-empty]"
    assert_no_text "Start a draft"
  end

  # Spec, Ruling 5: the hint under a short list is gone, also with rows.
  test "there is no hint line any more" do
    assert_raises(ArgumentError) { Admin::DashboardScreen::CardComponent.new(title: "Going live next", id: "g", empty: "None", hint: "Schedule a draft to see it here.") }
  end
```

- [ ] **Step 2: Write the failing integration tests**

In `test/integration/admin/dashboard_test.rb`: in "going live next shows the date tile, a relative phrase and by you" replace the hint assertion with `assert_no_match "Schedule a draft", response.body`; in "empty-state copy doesn't point at a quick-create row the viewer doesn't have" replace the two `assert_no_match` lines with `assert_no_match "Start a draft", response.body`; in "empty lists say so" replace "Nothing scheduled on the site." with "Nothing scheduled.". Add:

```ruby
  # Claude Design's O6: each card's empty line, and the two actions.
  test "every empty card says its one line, with Start a draft and Drafts → for someone who may create and read posts" do
    with_locales(%w[en], default: "en")
    sign_in_as users(:one)
    get admin_root_path

    lines = css_select("p[data-card-empty]").to_h { |line| [ line.ancestors("section").first["aria-labelledby"], line.text.squish ] }
    assert_equal({ "dashboard-notes-for-you" => "No notes for you.", "dashboard-open-threads" => "No open threads.",
                   "dashboard-drafts" => "No drafts. Start a draft", "dashboard-going-live-next" => "Nothing scheduled. Drafts →",
                   "dashboard-unpublished-changes" => "No unpublished changes.", "dashboard-activity" => "No recent activity." }, lines)
    assert_select "section[aria-labelledby=dashboard-drafts] p[data-card-empty] a[href='#dashboard_draft_title'][data-controller='admin--dashboard--start-draft'][data-action='admin--dashboard--start-draft#start'][data-admin--dashboard--start-draft-field-value='dashboard_draft_title']", text: "Start a draft"
    assert_select "section[aria-labelledby=dashboard-going-live-next] p[data-card-empty] a[href='#{admin_posts_path(scope: "drafts")}'][data-turbo-frame=_top] span[aria-hidden=true]", text: "→"
    assert_select ".admin-empty-state", count: 0
  end

  test "someone who may create nothing reads No drafts. alone, and Drafts → only with posts.read" do
    sign_in_as users(:reader)
    get admin_root_path
    assert_select "section[aria-labelledby=dashboard-drafts] p[data-card-empty]", text: "No drafts."
    assert_select "a", text: "Start a draft", count: 0
    # The read-only group holds posts.read (test/fixtures/access_control/grants.yml).
    assert_select "section[aria-labelledby=dashboard-going-live-next] p[data-card-empty] a[href='#{admin_posts_path(scope: "drafts")}']", count: 1

    sign_in_as users(:editor_branch)
    get admin_root_path
    assert_select "section[aria-labelledby=dashboard-going-live-next] p[data-card-empty]", text: "Nothing scheduled."
    assert_select "section[aria-labelledby=dashboard-going-live-next] p[data-card-empty] a", count: 0
  end
```

(`users(:editor_branch)` holds no grants in fixtures, so neither link is drawn for them.)

- [ ] **Step 3: Write the failing system test**

In `test/system/admin/dashboard_test.rb`:

```ruby
  # O6: "Start a draft" takes the person to the quick-create row: the focus
  # moves to its title, ready to type (a fragment alone would only scroll).
  test "Start a draft in an empty Your drafts moves the focus to the quick-create title" do
    sign_in_via_form(users(:one))
    visit admin_root_path
    await_admin_controllers

    within("section[aria-labelledby=dashboard-drafts]") { press "Start a draft" }
    await_js("document.activeElement?.id === 'dashboard_draft_title'")
    assert_equal admin_root_path, URI(page.current_url).path
  end
```

- [ ] **Step 4: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/components/admin/dashboard_screen/card_component_test.rb test/integration/admin/dashboard_test.rb`, then `PGGSSENCMODE=disable bin/rails test test/system/admin/dashboard_test.rb -n "/Start a draft/"`
Expected: FAIL — no `p[data-card-empty]`, `empty_action` is not a slot, `hint:` is accepted, no "Start a draft" link.

- [ ] **Step 5: The card**

`card_component.rb`: drop `hint:` (keyword, reader and the comment's sentence about it); add `renders_one :empty_action` with one comment line ("drawn after the empty line, only while the card has no rows: a link, which the caller builds"). `card_component.html.erb`: the `EmptyStateComponent` render and the `<% if hint %>` paragraph go; in their place, with rows empty:

```erb
<p class="px-4 py-2.5 text-sm text-dim" data-card-empty><%= empty %><% if empty_action? %> <%= empty_action %><% end %></p>
```

The class comment says why the card no longer uses `Admin::Ui::EmptyStateComponent` (spec decision 12: that component's 16 other uses stay as they are).

- [ ] **Step 6: The controller**

`app/javascript/controllers/admin/dashboard/start_draft_controller.js`: `static values = { field: String }`; `start(event)` finds `document.getElementById(this.fieldValue)`, and only when it is there prevents the default and calls `focus()` on it (without it the fragment's scroll is all there is). A header comment says what it is for and that the link works without it.

- [ ] **Step 7: The view and its keys**

`config/locales/admin/dashboard.en.yml` (under `admin.dashboard.show`, beside the existing `unpublished_changes`), with a comment line per group:

```yaml
        title: "Dashboard"
        drafts:
          title: "Your drafts"
          empty: "No drafts."
          start: "Start a draft"
          all: "All drafts"
        going_live:
          title: "Going live next"
          empty: "Nothing scheduled."
          drafts_html: "Drafts %{arrow}"
          all: "All scheduled posts"
        unpublished_changes:
          title: "Unpublished changes"
          empty: "No unpublished changes."
        activity:
          title: "Recent activity"
          empty: "No recent activity."
          audit_log_html: "Full audit log %{arrow}"
```

The file's header comment ("Only what a later change added is here; the rest of the view is not converted yet") becomes "the whole view is converted".

`show.html.erb`: every literal is `t(".…")` (the arrows `tag.span("→", aria: { hidden: true })` passed as `arrow:`); the comment about "start one above" goes with the words it explained; `going_live` and the `hint:` go. The drafts card gets, when `quick_create.render?`:

```erb
<% card.with_empty_action do %>
  <%= link_to t(".drafts.start"), "#dashboard_draft_title", class: "text-ink underline",
        data: { controller: "admin--dashboard--start-draft", action: "admin--dashboard--start-draft#start", "admin--dashboard--start-draft-field-value": "dashboard_draft_title" } %>
<% end %>
```

and the going-live card, when `can?("posts.read")`, an `empty_action` linking `t(".going_live.drafts_html", arrow: …)` to `admin_posts_path(scope: "drafts", **admin_url_options)` with the same class and `data: { turbo_frame: "_top" }`. Add `app/views/admin/dashboard/show.html.erb`, `app/components/admin/dashboard_screen/card_component.rb` and `card_component.html.erb` to `CONVERTED`; update the preview.

- [ ] **Step 8: Run them to see them pass**

Run: `PGGSSENCMODE=disable bin/rails test test/components/admin/dashboard_screen test/integration/admin/dashboard_test.rb test/lib/admin_i18n_test.rb test/lib/source_layout_test.rb test/lib/inline_handlers_test.rb test/integration/admin/note_inbox_test.rb`, then `PGGSSENCMODE=disable bin/rails test test/system/admin/dashboard_test.rb`
Expected: PASS (the notes cards' empty words are theirs and unchanged; `note_inbox_test.rb` is whatever file holds the notes cards' integration tests: `grep -rl "notes-for-you" test/integration`).

- [ ] **Step 9: Commit**

```bash
git add app/components/admin/dashboard_screen/card_component.rb app/components/admin/dashboard_screen/card_component.html.erb app/views/admin/dashboard/show.html.erb config/locales/admin/dashboard.en.yml app/javascript/controllers/admin/dashboard/start_draft_controller.js test/components test/integration/admin/dashboard_test.rb test/system/admin/dashboard_test.rb test/lib/admin_i18n_test.rb
git commit -m "feat(dashboard): one quiet empty line per card, with Start a draft and Drafts (O6)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 3: `Audit::Sentence` counts a run of blocks or uploads

**Files:**
- Modify: `app/models/audit/sentence.rb` (`COUNTED`, `library_route`, `build`'s two keywords, `Wording#block_parts` and the upload)
- Modify: `app/components/admin/audit_screen/sentence_component.rb` (`:collection`)
- Test: `test/models/audit/sentence_test.rb`, `test/components/admin/audit_screen/sentence_component_test.rb`

**Interfaces:**
- Produces: `Audit::Sentence::COUNTED` (`%w[block.created block.updated media.uploaded]`); `Audit::Sentence.build(event, viewer:, target:, fallback_scheduled_at: nil, count: 1, mixed: false)`; `Audit::Sentence.library_route -> Route` (`:admin_media_path, [], {}`); part kind `:collection`. Task 4 calls `build` with `count:` and `mixed:`.

- [ ] **Step 1: Write the failing sentence tests**

In `test/models/audit/sentence_test.rb` (its `read` helper quotes only `:subject` parts, so a collection reads unquoted):

```ruby
  # Layout points spec, decision 11: the dashboard joins a run of one
  # person's block edits on one page into one row, and the sentence counts.
  test "a counted block sentence names the count and the type, or blocks for mixed types" do
    page = as(@me) { create_page(title: "Code block demo") }
    target = Audit::Sentence::Target.new("Code block demo", Audit::Sentence.route_for(page))
    created = event("block.created", subject_type: "ContentBlock", subject_id: 1, snapshot: { "block_type" => "code" })
    edited = event("block.updated", subject_type: "ContentBlock", subject_id: 2, snapshot: { "block_type" => "rich_text" })

    assert_equal "You added 4 Code blocks to “Code block demo”", read(Audit::Sentence.build(created, viewer: @me, target:, count: 4))
    assert_equal "You added 2 blocks to “Code block demo”", read(Audit::Sentence.build(created, viewer: @me, target:, count: 2, mixed: true))
    assert_equal "You edited 3 Rich text blocks on “Code block demo”", read(Audit::Sentence.build(edited, viewer: @me, target:, count: 3))
    assert_equal "You edited 3 blocks on “Code block demo”", read(Audit::Sentence.build(edited, viewer: @me, target:, count: 3, mixed: true))
    assert_equal "You added a Code block to “Code block demo”", read(Audit::Sentence.build(created, viewer: @me, target:, count: 1))
  end

  # The owner's O10: uploads collapse too, and the row links to the library.
  test "a counted upload reads uploaded 12 images, linked to the library and not quoted" do
    upload = event("media.uploaded", subject_type: "Media::Asset", subject_id: 5, subject_label: "photo.jpg")
    sentence = Audit::Sentence.build(upload, viewer: @me, target: Audit::Sentence::Target.new(nil, Audit::Sentence.library_route), count: 12)

    assert_equal "You uploaded 12 images", read(sentence)
    assert_equal [ Audit::Sentence::Part.new(:text, "uploaded "), Audit::Sentence::Part.new(:collection, "12 images") ], sentence.parts
    assert_equal Audit::Sentence::Route.new(:admin_media_path, [], {}), sentence.subject_route
  end

  test "a count is for the counted actions only, and needs a target" do
    published = event("post.published", subject_type: "Post", subject_id: 1, subject_label: "Hello")
    block = event("block.created", subject_type: "ContentBlock", subject_id: 1)

    assert_raises(ArgumentError) { Audit::Sentence.build(published, viewer: @me, target: nil, count: 2) }
    assert_raises(ArgumentError) { Audit::Sentence.build(block, viewer: @me, target: nil, count: 2) }
    assert_equal %w[block.created block.updated media.uploaded], Audit::Sentence::COUNTED
  end
```

In `test/components/admin/audit_screen/sentence_component_test.rb`:

```ruby
  test "a collection is linked where the sentence has a route, and never quoted" do
    upload = Audit::Event.new(action: "media.uploaded", channel: "admin", user_id: users(:one).id, occurred_at: Time.current, last_occurred_at: Time.current)
    sentence = Audit::Sentence.build(upload, viewer: users(:one), target: Audit::Sentence::Target.new(nil, Audit::Sentence.library_route), count: 12)
    render_inline Admin::AuditScreen::SentenceComponent.new(sentence:)

    assert_text "You uploaded 12 images"
    assert_no_text "“"
    assert_selector "a[href='/cs-studio/media']", exact_text: "12 images"
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/models/audit/sentence_test.rb test/components/admin/audit_screen/sentence_component_test.rb`
Expected: FAIL — `unknown keyword: :count`, `uninitialized constant Audit::Sentence::COUNTED`.

- [ ] **Step 3: Implement**

In `sentence.rb`: `COUNTED` with a comment (the actions whose sentence has a counted form; `Dashboard::Activity` collapses exactly these, layout points spec decision 11); `library_route`; `build` raises `ArgumentError` when `count > 1` and the action is not in `COUNTED` or `target` is nil, and hands `count:` and `mixed:` to `Wording.new`. In `Wording`:

- `block_parts`: with `count > 1` the noun is `"#{count} #{type} blocks"`, or `"#{count} blocks"` when `mixed` or no type; "created" reads `"added #{noun} to "`, "updated" `"edited #{noun} on "` (only these two can be counted).
- the upload: `content_parts("uploaded")` with `count > 1` answers `[ text("uploaded "), Part.new(:collection, "#{count} images") ]`.

The class comment's `parts` line names `:collection` ("a counted set of records, linked like a subject and never quoted"). In `SentenceComponent#part_html`, `when :collection then collection_html(part.text)`: the same link as `subject_html` when the route is on `ROUTES`, else a `font-semibold` span, with no quotes.

- [ ] **Step 4: Run them to see them pass**

Run: `PGGSSENCMODE=disable bin/rails test test/models/audit test/components/admin/audit_screen test/integration/admin/audit_events_test.rb`
Expected: PASS (the audit log never passes a count, so its sentences are unchanged).

- [ ] **Step 5: Commit**

```bash
git add app/models/audit/sentence.rb app/components/admin/audit_screen/sentence_component.rb test/models/audit/sentence_test.rb test/components/admin/audit_screen/sentence_component_test.rb
git commit -m "feat(audit): a counted sentence for a run of blocks or uploads

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 4: Recent activity collapses a run into one row

**Files:**
- Modify: `app/queries/dashboard/activity.rb`
- Test: `test/queries/dashboard/activity_test.rb`

**Interfaces:**
- Consumes: `Audit::Sentence::COUNTED`, `Audit::Sentence.build(…, count:, mixed:)`, `Audit::Sentence.library_route` (Task 3).
- Produces: `Dashboard::Activity::Row` gains `count` (default 1; `Row.new(event:, record:, sentence:, at:, span_end:)` still works); `Dashboard::Activity::READ_FACTOR = 4`; `Dashboard::Activity::COLLAPSING = Audit::Sentence::COUNTED`.

- [ ] **Step 1: Write the failing tests**

In `test/queries/dashboard/activity_test.rb`, a helper and the tests:

```ruby
  # --- layout points spec, decision 11: runs ---------------------------------

  def add_blocks(page, types, actor: @me, every: 2.minutes, from: Time.current.change(usec: 0))
    types.each_with_index.map do |type, index|
      travel_to(from + every * index) { as(actor) { ContentBlocks::Save.call(ContentBlock.new(owner: page, block_type: type)).record } }
    end
  end

  def runs(actor = @me) = activity(actor).rows.select { |row| row.event.action.start_with?("block.", "media.") }.map { |row| [ row.event.action, row.count ] }

  test "four blocks added to one page in a row are one row with their count, its time the last one's and its span the run's" do
    page = as(@me) { create_page(title: "Code block demo") }
    start = Time.current.change(usec: 0)
    add_blocks(page, %w[rich_text] * 4, from: start)

    row = activity.rows.find { |r| r.event.action == "block.created" }
    assert_equal [ [ "block.created", 4 ] ], runs
    assert_equal [ "added 4 Rich text blocks to", "Code block demo", "" ], words(row)
    assert_equal page, row.record
    assert_equal start, row.at
    assert_equal start + 6.minutes, row.span_end
  end

  test "blocks of mixed types are counted as blocks" do
    page = as(@me) { create_page(title: "Mixed") }
    add_blocks(page, %w[rich_text post_list rich_text])

    assert_equal [ "added 3 blocks to", "Mixed", "" ], words(activity.rows.find { |r| r.event.action == "block.created" })
  end

  test "a run ends ten minutes after its newest event" do
    page = as(@me) { create_page(title: "Slow") }
    add_blocks(page, %w[rich_text] * 3, every: 5.minutes + 30.seconds)

    assert_equal [ [ "block.created", 2 ], [ "block.created", 1 ] ], runs
  end

  test "a run is broken by another person's event between, by another page and by another action" do
    one = as(@me) { create_page(title: "One") }
    other = as(@me) { create_page(title: "Other") }
    start = Time.current.change(usec: 0)
    add_blocks(one, %w[rich_text], from: start)
    add_blocks(one, %w[rich_text], actor: users(:two), from: start + 1.minute)
    add_blocks(one, %w[rich_text], from: start + 2.minutes)
    add_blocks(other, %w[rich_text], from: start + 3.minutes)
    travel_to(start + 4.minutes) { as(@me) { Pages::Save.call(other, attributes: { published: true }) } }
    add_blocks(other, %w[rich_text], from: start + 5.minutes)

    assert_equal [ [ "block.created", 1 ] ] * 5, runs
  end

  test "a block deleted from a run is not counted and does not split it" do
    page = as(@me) { create_page(title: "Three") }
    blocks = add_blocks(page, %w[rich_text] * 3)
    as(@me) { ContentBlocks::Destroy.call(blocks.second) }

    assert_equal [ "added 2 Rich text blocks to", "Three", "" ], words(activity.rows.find { |r| r.event.action == "block.created" })
  end

  # The owner's O10: twelve uploads in a row are one row, linked to the library.
  test "uploads in a row are one row, whatever the images, and read uploaded 12 images" do
    12.times { as(@me) { Audit.record("media.uploaded", subject: create_media_asset) } }

    row = activity.rows.first
    assert_equal [ [ "media.uploaded", 12 ] ], runs
    assert_equal [ [ :text, "uploaded " ], [ :collection, "12 images" ] ], row.sentence.parts.map { |part| [ part.kind, part.text ] }
    assert_equal Audit::Sentence.library_route, row.sentence.subject_route
    assert_empty activity(users(:reader)).rows, "a viewer without media.upload sees no upload, counted or not"
  end

  test "after collapsing there are at most fifteen rows" do
    20.times { |i| add_blocks(as(@me) { create_page(title: "P#{i}") }, %w[rich_text rich_text], every: 1.second) }

    rows = activity.rows
    assert_equal 15, rows.size
    assert_equal 2, rows.first.count
  end

  test "the same number of statements for a run of 5 blocks and one of 60, and for 60 runs of one" do
    counts = [ 5, 60 ].map do |n|
      page = as(@me) { create_page(title: "N#{n}") }
      n.times { as(@me) { Audit.record("block.created", subject: page.content_blocks.create!(block_type: "rich_text", position: 0)) } }
      Current.set(actor: @me, channel: :admin) do
        Dashboard::Activity.new(actor: @me).rows # warm up
        capture_sql { Dashboard::Activity.new(actor: @me).rows.each { |row| row.record.title } }.size
      end
    end
    assert_equal counts.first, counts.last
  end
```

And change, on purpose, the second assertion of "an older readable event is listed after 60 uploads for a viewer without media.upload":

```ruby
    # The owner's sixty uploads are now one run (the owner's O10), read in
    # one LIMIT of sixty events, so the older post is past the read (Decision
    # 11's cost: a feed whose newest events collapse shows fewer rows).
    assert_equal [ [ "media.uploaded", 60 ] ], activity(@me).rows.map { |row| [ row.event.action, row.count ] }
```

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/queries/dashboard/activity_test.rb`
Expected: FAIL — `undefined method 'count'` on the row; four rows where one is expected.

- [ ] **Step 3: Implement the runs**

In `activity.rb`: `READ_FACTOR = 4` and `COLLAPSING = Audit::Sentence::COUNTED`, each with a comment line; `Row = Data.define(:event, :record, :sentence, :at, :span_end, :count)` with an `initialize(count: 1, **rest)` that passes on; the event query's `.limit(@limit)` becomes `.limit(@limit * READ_FACTOR)`; `build_rows` ends `runs(events, records).first(@limit).map { |run| row_for(run) }`. The class comment gains a paragraph: the collapse, in Ruby over the events already read, statements unchanged, the four rules of a run and Rulings 1–6's reasons. The run rule, which the tests do not determine alone:

```ruby
    # `[[event, record], ...]` per run, newest first. An event whose record
    # the viewer can't read (or is gone) is left out BEFORE the runs are
    # made, so it neither shows nor splits one. An event joins the run before
    # it when (Ruling 1-3): its action is a counted one and the run's; its
    # actor is the run's (`actor_key`); its record is the run's (any image,
    # for an upload); and it is at most COALESCE_WINDOW older than the run's
    # newest event, by `last_occurred_at`, the feed's own order.
    def runs(events, records)
      events.filter_map { |event| (record = records[subject_key(event)]) && [ event, record ] }
        .each_with_object([]) do |(event, record), runs|
          if runs.last && joins?(runs.last, event, record) then runs.last << [ event, record ]
          else runs << [ [ event, record ] ]
          end
        end
    end

    def joins?(run, event, record)
      newest, newest_record = run.first
      COLLAPSING.include?(event.action) && event.action == newest.action && actor_key(event) == actor_key(newest) &&
        (event.action == "media.uploaded" || record == newest_record) &&
        newest.last_occurred_at - event.last_occurred_at <= Audit::COALESCE_WINDOW
    end

    def actor_key(event) = [ event.user_id, event.actor_type, event.actor_id ]
```

`subject_key(event)` takes the event alone (it reads `@blocks`, which `readable_records` sets). `row_for(run)`: `event` and `record` are the newest pair; `count` the run's distinct `subject_id`s; `mixed` whether the events' `snapshot["block_type"]` differ; the target is `Target.new(nil, Audit::Sentence.library_route)` for an upload run of more than one, the record's title and route otherwise; `at` the oldest event's `occurred_at`; `span_end` the newest's `last_occurred_at` when it is later than `at`.

- [ ] **Step 4: Run them to see them pass**

Run: `PGGSSENCMODE=disable bin/rails test test/queries/dashboard test/components/admin/dashboard_screen test/integration/admin/dashboard_test.rb`
Expected: PASS, the existing "the same number of queries for 5 and 60 events" and "the dashboard renders in the same number of queries with 1 or 20 records per list" unchanged.

- [ ] **Step 5: Commit**

```bash
git add app/queries/dashboard/activity.rb test/queries/dashboard/activity_test.rb
git commit -m "feat(dashboard): recent activity joins a run of block edits or uploads into one counted row

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 5: The activity row's two letters (O9)

**Files:**
- Modify: `app/components/admin/dashboard_screen/activity_row_component.rb` (`initial` becomes `initials`; the class comment's "the person's initial"), `activity_row_component.html.erb` (`initials`, `uppercase`)
- Test: `test/components/admin/dashboard_screen/activity_row_component_test.rb`, `test/values/person_name_test.rb`

**Interfaces:**
- Consumes: `PersonName.initials(text) -> String` (part 1), `Admin::Ui::UserNameComponent#label`.
- Produces: `Admin::DashboardScreen::ActivityRowComponent#initials -> String`.

- [ ] **Step 1: Write the failing tests**

In `activity_row_component_test.rb`, the two `assert_selector "span.rounded-full", text: …display_name[0].upcase` lines become `assert_selector "span.rounded-full.uppercase[aria-hidden=true]", exact_text: "on"` and `exact_text: "tw"`; add:

```ruby
  # The owner's O9: the dashboard's circle is the two-letter rule
  # (`PersonName.initials`) of the name the row shows, drawn upper-case.
  test "the circle is two letters of the name the row shows: two words, one word, a deleted user, System" do
    users(:two).update!(name: "Ada Lovelace")
    render_inline Admin::DashboardScreen::ActivityRowComponent.new(row: row_for(actor: users(:two)))
    assert_selector "span.rounded-full.uppercase", exact_text: "AL"

    users(:two).update!(name: "Δήμητρα")
    render_inline Admin::DashboardScreen::ActivityRowComponent.new(row: row_for(actor: users(:two)))
    assert_selector "span.rounded-full.uppercase", exact_text: "Δή"

    assert_equal "ad", Admin::DashboardScreen::ActivityRowComponent.new(row: row_with(user: nil, user_id: 999_999)).initials
    assert_equal "Sy", Admin::DashboardScreen::ActivityRowComponent.new(row: row_with(user: nil, user_id: nil)).initials
  end
```

with a helper `row_with(user:, user_id:)` that builds a `Dashboard::Activity::Row` around an `Audit::Sentence` whose `actor` is `Audit::Sentence::Actor.new(you: false, user:, user_id:, via_label: nil, none: false)` (the test "a coalesced burst shows its span as the time's tooltip" shows how a row is built by hand). In `test/values/person_name_test.rb`, part 1's deferred minor:

```ruby
  test "a one-word name in another script gives its first two letters" do
    assert_equal "Δή", PersonName.initials("Δήμητρα")
    assert_equal "Юл", PersonName.initials("Юлия")
    assert_equal "美咲", PersonName.initials("美咲")
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/components/admin/dashboard_screen/activity_row_component_test.rb test/values/person_name_test.rb`
Expected: FAIL — one letter, no `uppercase`, no `initials` method. (The person-name test may already pass: it pins what part 1 built.)

- [ ] **Step 3: Implement**

`initials` is `PersonName.initials(Admin::Ui::UserNameComponent.new(user: actor.user, user_id: actor.user_id).label.to_s)`; the template draws it in the existing span with `uppercase` added and `aria-hidden="true"` kept. The class comment says the letters are the two-letter rule of the name the row shows (Ruling 7) and that the circle stays this row's own 28px one.

- [ ] **Step 4: Run them to see them pass**

Run: `PGGSSENCMODE=disable bin/rails test test/components/admin/dashboard_screen test/values/person_name_test.rb test/lib/initials_rule_test.rb test/integration/admin/dashboard_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/components/admin/dashboard_screen/activity_row_component.rb app/components/admin/dashboard_screen/activity_row_component.html.erb test/components/admin/dashboard_screen/activity_row_component_test.rb test/values/person_name_test.rb
git commit -m "feat(dashboard): two letters in the activity row's circle, by the one rule (O9)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 6: The Mind graph's legend in two groups, Show and Key, with "Status key…" last (O5)

**Files:**
- Modify: `app/components/admin/mind_graph_screen/legend_component.html.erb` (and the class comment in `legend_component.rb`)
- Modify: `config/locales/admin/mind_graph_screen.en.yml` (`legend.key: "Key"`; `legend.status: "Status key…"`; `legend.label` goes; the comment above names the two groups)
- Modify (the comments that describe the order): `app/views/admin/mind_graph/show.html.erb` (lines about "the legend's toggles and its "Status" link")
- Test: `test/components/admin/mind_graph_screen/legend_component_test.rb`, `test/integration/admin/mind_graph_test.rb` (selectors `ul[aria-label='Legend']` → `ul[data-legend-keys]`, lines 331–360; "Status" → "Status key…", lines 444, 466, 594), `test/system/admin/mind_graph_test.rb` (lines 476 and 3634: "Status" → "Status key…")

**Interfaces:**
- Produces: `[data-legend-section=show]` (a hidden-from-screen-readers mono "Show", then the two fieldsets), `[data-legend-section=key]` (`span#mind-graph-legend-key` "Key", `ul[data-legend-keys][aria-labelledby=mind-graph-legend-key]`, then `button[data-legend-status]`). Everything the script reads (`data-mind-graph-legend`, `data-legend-toggle`, `data-legend-count`, the swatches' controller on the legend's root) is unchanged.

- [ ] **Step 1: Write the failing component tests**

In `legend_component_test.rb`, replace "the keys that are no controls are a list named Legend, after the toggles and the Status button" with:

```ruby
  # Layout points spec, D and decision 14; Claude Design's O5: two groups a
  # person can see, "Show" over the toggles of both kinds and "Key" over the
  # marks, "Status key…" last in Key. The marks hold no stop, so the Tab
  # order is still the toggles, then the button.
  test "the legend is two labelled groups: Show over both kinds of toggle, then Key over the marks, with Status key… last" do
    legend(content_types: %w[blog])

    assert_selector "[data-mind-graph-legend] > [data-legend-section=show] + [data-legend-section=key]"
    assert_selector "[data-legend-section=show] > span[aria-hidden=true]:first-child", exact_text: "Show"
    assert_selector "[data-legend-section=show] > fieldset[data-legend-group=nodes] + fieldset[data-legend-group=lines]"
    assert_selector "[data-legend-section=key] > span#mind-graph-legend-key:first-child", exact_text: "Key"
    assert_selector "span#mind-graph-legend-key + ul[data-legend-keys][aria-labelledby=mind-graph-legend-key] + button[data-legend-status]:last-child", exact_text: "Status key…"
    assert_selector "[data-legend-section] > span.font-cs-mono.text-label.uppercase.tracking-mono", count: 2
    assert_no_selector "ul[data-legend-keys] button, ul[data-legend-keys] input"
    assert_no_selector "[aria-label='Legend']"
  end
```

In the same file: "the legend's Status button opens the key and is no filter" asserts `text: "Status key…"`; "names the pin mark" and "names the notes badge, last, after the pin" select `ul[data-legend-keys]` instead of `ul[aria-label='Legend']`; "a viewer gets the toggles…" adds, after `legend(content_types: [], pages: false)`, `assert_no_selector "[data-legend-section=show]"`.

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/components/admin/mind_graph_screen/legend_component_test.rb test/integration/admin/mind_graph_test.rb`
Expected: FAIL — no `[data-legend-section]`, the button says "Status".

- [ ] **Step 3: Implement**

In `legend_component.html.erb` the root keeps its attributes and classes. Its children become two groups, each `class="flex min-w-0 flex-wrap items-center gap-x-4 gap-y-1.5"`:

- `[data-legend-section=show]`, drawn only when a fieldset is: `<span aria-hidden="true" class="font-cs-mono text-label uppercase tracking-mono text-meta">`t(".show")`</span>`, then the two fieldsets as they are (their `sr-only` legends "Show" and "Lines" stay: Ruling 13).
- `[data-legend-section=key]`: `<span id="mind-graph-legend-key" class="…the same label classes…">`t(".key")`</span>`, the `ul` with `data-legend-keys` and `aria-labelledby="mind-graph-legend-key"` in place of `aria-label`, its items unchanged, then the status button unchanged but for its words.

The template's and the class's comments say the new order (toggles, the marks, "Status key…"), that the Tab order is unchanged because the marks hold no stop, and O5.

- [ ] **Step 4: Update the tests that name the button or the list**

`test/integration/admin/mind_graph_test.rb`: `ul[aria-label='Legend']` → `ul[data-legend-keys]` (lines 331–360); `text: "Status"` → `text: "Status key…"` (line 444); in both tab orders (lines 466, 594) `"Status"` → `"Status key…"`; the comment at line 447–448 says "its "Status key…" button, which is named by its text". `test/system/admin/mind_graph_test.rb`: line 476's `'Status'` → `'Status key…'`, line 3634's `[ "Status", 0 ]` → `[ "Status key…", 0 ]`, and the comment above it.

- [ ] **Step 5: Run them to see them pass**

Run: `PGGSSENCMODE=disable bin/rails test test/components/admin/mind_graph_screen test/integration/admin/mind_graph_test.rb test/lib/admin_i18n_test.rb`, then `bin/rails tailwindcss:build && bin/rails theme_css:build` and `PGGSSENCMODE=disable bin/rails test test/system/admin/mind_graph_test.rb`
Expected: PASS, the toggle tests ("a toggle moves nothing…", "each toggle of the legend hides its kind…", "Back to the graph draws it once…") unchanged.

- [ ] **Step 6: Commit**

```bash
git add app/components/admin/mind_graph_screen/legend_component.rb app/components/admin/mind_graph_screen/legend_component.html.erb config/locales/admin/mind_graph_screen.en.yml app/views/admin/mind_graph/show.html.erb test/components/admin/mind_graph_screen/legend_component_test.rb test/integration/admin/mind_graph_test.rb test/system/admin/mind_graph_test.rb
git commit -m "feat(mind-graph): the legend in two labelled groups, Show and Key, with Status key… last (O5)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 7: Fit fills about 80% of the canvas

**Files:**
- Modify: `app/javascript/mind_graph/camera.js` (`MAX_FIT_ZOOM`, a new `FIT_MARGIN`, `fit`'s fourth parameter and its comment)
- Test: `test/system/admin/mind_graph_modules_test.rb` (the four camera tests at lines 412, 429, 621, 636, and one new)

**Interfaces:**
- Produces: `fit(box, width, height, margin = FIT_MARGIN) -> { k, tx, ty }`, `margin` a fraction of each side (0.1); `app.js`'s two calls are unchanged.

- [ ] **Step 1: Change the module tests to the new numbers, and add one**

In `mind_graph_modules_test.rb`:

- "camera: fit puts every corner inside the padded box and the middle in the middle" → named "camera: fit leaves a tenth of the canvas on each side of a wide box, its middle in the middle": `k` 0.64, `topLeft[0]` 80, `bottomRight[0]` 720, `topLeft[1]` ≥ 60.
- "camera: fitting a single point does not divide by zero or zoom past 1.5" → "… or zoom past 3": `[ 3, 400, 300 ]`.
- "camera: fit of a tall box is limited by the height": `k` 0.48, `top[1]` 60, `bottom[1]` 540.
- "camera: bounds skip positions that are not laid out yet, and fit never returns NaN": unchanged (`fit(null)` is still `k: 1` at the middle).

New:

```ruby
  # Layout points spec, decision 15: a small graph is zoomed in to fill the
  # box, up to 3 and never further.
  test "camera: a small graph is zoomed in to fill the box, up to 3 and never further" do
    small = js_module("mind_graph/camera", "m.fit({ minX: -100, minY: -50, maxX: 100, maxY: 50 }, 800, 600).k")
    tiny = js_module("mind_graph/camera", "m.fit({ minX: -10, minY: -5, maxX: 10, maxY: 5 }, 800, 600).k")

    assert_in_delta 3.2, js_module("mind_graph/camera", "Math.min(800 * 0.8 / 200, 600 * 0.8 / 100)"), 0.001
    assert_equal 3, small, "200 by 100 would fill 80% at 3.2: it stops at the cap"
    assert_equal 3, tiny
    assert_in_delta 2.4, js_module("mind_graph/camera", "m.fit({ minX: -100, minY: -50, maxX: 100, maxY: 50 }, 600, 300).k"), 0.001
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bin/rails tailwindcss:build && bin/rails theme_css:build`, then `PGGSSENCMODE=disable bin/rails test test/system/admin/mind_graph_modules_test.rb -n "/camera/"`
Expected: FAIL — `k` 0.72 where 0.64 is expected; 1.5 where 3 is.

- [ ] **Step 3: Implement**

`MAX_FIT_ZOOM = 3`; `FIT_MARGIN = 0.1` with a comment ("a tenth of the canvas on each side: the graph fills about 80% of it on the axis that binds", Ruling 12); `fit(box, width, height, margin = FIT_MARGIN)` with `roomX = Math.max(width * (1 - margin * 2), 1)` and the same for Y; the function's and the `MAX_FIT_ZOOM` comments say the new numbers and why the cap stays (three nodes stretched over the whole box).

- [ ] **Step 4: Run them to see them pass, and the screen's tests**

Run: `PGGSSENCMODE=disable bin/rails test test/system/admin/mind_graph_modules_test.rb`, then `PGGSSENCMODE=disable bin/rails test test/system/admin/mind_graph_test.rb`
Expected: PASS. The screen's tests compare zooms with the fitted one and pin none; one that fails because a small graph now opens at 3 (nearer `MAX_ZOOM` 4, so a second "Zoom in" changes nothing) is rewritten to compare, never to pin a number.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/mind_graph/camera.js test/system/admin/mind_graph_modules_test.rb
git commit -m "feat(mind-graph): the first view and Fit all fill about 80% of the canvas, up to a zoom of 3

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 8: A page's notes badge stands outside its card, over everything, and labels keep clear of it (O11, K3)

**Files:**
- Modify: `app/javascript/mind_graph/marks.js` (a new `notesBadgeBox`: where a node's badge and its ring stand, the one geometry the renderer and the labels share)
- Modify: `app/javascript/mind_graph/renderer.js` (`drawNotes` draws from `notesBadgeBox`; a page's badge is outside its card; the badges are drawn after every mark and label, each on a ring; `NOTES_CLEAR = 2`, `NOTES_RING = 2`; `NODE_MARGIN` 30; the header's "WITH OPEN NOTES" item and the draw order in the first lines)
- Modify: `app/javascript/mind_graph/labels.js` (`chooseLabels` takes `obstacles`; a new `badgeBoxes`), `app/javascript/mind_graph/app.js` (passes `obstacles: badgeBoxes(…)` where it calls `chooseLabels`, line 439)
- Test: `test/system/admin/mind_graph_modules_test.rb` (lines 920 and 1325–1355, and four new)

**Interfaces:**
- Produces: `notesBadgeBox(node, x, y, radius) -> { left, top, right, bottom } | null` in `marks.js`: the badge's box WITH its ring, in screen pixels, for a post or a page whose `open_notes` is above zero, null for anything else. `badgeBoxes({ nodes, indexes, positions, radii, camera }) -> Array<box>` in `labels.js`. `chooseLabels({ …, obstacles = [] })`: a label is not placed where it would overlap an obstacle. The swatch "notes" (a post), the pin and the hit test are unchanged in place; the swatch gains the ring because it is the renderer's own drawing.

- [ ] **Step 1: Change the module tests that pin the badge, and write the new ones**

In "renderer: a card's and a pill's pin, notes badge and ring are on the box, and a type's ring is a circle", the badge's assertion becomes the badge and its ring:

```ruby
    assert_includes page, [ "box", -16, -5, 14, 14, 7 ], "the badge outside the card: its right edge 2px clear of the card's left edge, its centre on the top edge"
    assert_includes page, [ "box", -16, -5, 18, 18, 9 ], "its ring, 2px of the canvas's ground all round"
```

In "renderer: a post with open notes carries its count in a neutral badge that grows leftwards from the top-left corner", each badge is now preceded by its ring, a pill 2px larger all round, filled with the ground and stroked with nothing:

```ruby
    assert_equal [
      [ "pill", 32.96, 35.96, 18, 18, 9, "surface" ], [ "pill", 34.96, 37.96, 14, 14, 7, "surface" ], [ "line", "line", 1 ], [ "text", "3", 41.96, 45.46, "ink", "count" ],
      [ "pill", 126.96, 35.96, 24, 18, 9, "surface" ], [ "pill", 128.96, 37.96, 20, 14, 7, "surface" ], [ "line", "line", 1 ], [ "text", "12", 138.96, 45.46, "ink", "count" ],
      [ "pill", 220.96, 35.96, 30, 18, 9, "surface" ], [ "pill", 222.96, 37.96, 26, 14, 7, "surface" ], [ "line", "line", 1 ], [ "text", "99+", 235.96, 45.46, "ink", "count" ]
    ], drawn.reject { |entry| entry.first == "pin" }
```

In "renderer: a pinned node's notes badge never reaches its pin, whatever the count", the pills come in pairs (ring, badge): `rings, pills = drawn.select { |entry| entry.first == "pill" }.each_slice(2).to_a.transpose`, the loop reads each RING's right edge (`left + width`, no line: the ring is a fill) against the pin's left, and the widths are `[ 14, 20, 26 ]` for `pills` and `[ 18, 24, 30 ]` for `rings`: the ring, drawn after the pin now, must not cover it either.

New, after the card test:

```ruby
  # Claude Design's K3 (2026-10-12), the "count badges overlap the page
  # cards" of the 2026-10-15 review: on a page's card, Home's too, the badge
  # stands OUTSIDE the card, 2px clear of its left edge, centred on its top
  # edge, and grows leftwards; a post's still reaches 4px over its corner.
  test "renderer: a page's notes badge stands outside its card, on a page and on Home, and a post's is as it was" do
    page_badge, home_badge, post_badge = shapes_drawn([ { kind: "page", open_notes: 120 }, { kind: "page", home: true, open_notes: 12 }, { open_notes: 3 } ])
      .map { |shapes| shapes.find { |shape| shape.first == "box" && shape.last == 7 } }

    assert_equal [ "box", -22, -5, 26, 14, 7 ], page_badge, "99+ on a 14 by 10 card: right edge at -9, 2px left of -7"
    assert_equal [ "box", -21, -6.5, 20, 14, 7 ], home_badge, "12 on Home's 18 by 13 card: right edge at -11"
    assert_operator post_badge[1] + post_badge[3] / 2, :>, -7 * 0.71, "a post's badge still reaches over its corner"
  end

  # Claude Design's answer of 2026-10-25 (a): a badge that lands on a
  # neighbour covers it cleanly. Every badge is drawn after every mark and
  # every label, on a 2px ring of the canvas's ground (the theme's `surface`,
  # never a colour), at its node's strength.
  test "renderer: the notes badges are drawn after every mark and label, each on a ring of the canvas's ground" do
    calls = draw_calls([ { kind: "page", open_notes: 3, label: "About" }, { label: "Neighbour" } ], positions: [ 100, 100, 70, 96 ], labels: [ 0, 1 ])
    texts = calls.each_index.select { |i| calls[i][0] == "fillText" && calls[i][1] != "3" }
    marks = calls.each_index.select { |i| calls[i][0] == "fill" && calls[i][1] != "surface" }
    rings = calls.each_index.select { |i| calls[i][0] == "roundRect" }.first

    assert_equal 2, texts.size
    assert_operator [ texts.max, marks.max ].max, :<, rings, "a badge is drawn before a label or a mark"
    assert_equal [ "fill", "surface", 1 ], calls[rings + 1], "the ring is the ground, at the node's strength"
  end

  # Claude Design's answer of 2026-10-25 (b): the badge's box is one more box
  # the labels keep clear of, by the rule that keeps labels apart; the layout
  # makes no room for it.
  test "labels: a label that would cover a notes badge is not placed, and one clear of it is" do
    labelled = js_module("mind_graph/labels", <<~JS)
      m.chooseLabels({ free: new Set(), order: [0, 1], positions: new Float32Array([0, 0, 0, 200]), widths: [80, 80], radii: [8, 8],
        camera: { k: 1, tx: 100, ty: 50 }, width: 800, height: 600, always: new Set(),
        obstacles: [ { left: 150, top: 40, right: 180, bottom: 58 } ] }).map((label) => label.index)
    JS

    assert_equal [ 1 ], labelled
  end

  test "labels: the badge boxes are a post's and a page's, ring included, and none for a tag, a type or a node without notes" do
    boxes = js_module("mind_graph/labels", <<~JS)
      m.badgeBoxes({ nodes: [ { kind: "page", open_notes: 120 }, { kind: "post", degree: 1, open_notes: 3 }, { kind: "tag", open_notes: 4 }, { kind: "type", id: "type-a", open_notes: 2 }, { kind: "post", degree: 1, open_notes: 0 } ],
        indexes: [ 0, 1, 2, 3, 4 ], positions: new Float32Array([ 100, 100, 200, 100, 300, 100, 400, 100, 500, 100 ]), radii: [ 7, 7, 4.5, 6, 7 ], camera: { k: 1, tx: 0, ty: 0 } })
    JS

    assert_equal 2, boxes.size
    assert_equal({ "left" => 63, "top" => 86, "right" => 93, "bottom" => 104 }, boxes.first)
    { "left" => 182.96, "top" => 85.96, "right" => 200.96, "bottom" => 103.96 }.each { |side, value| assert_in_delta value, boxes.second[side], 0.01, side }
  end
```

with a helper beside `notes_badges`, `draw_calls(nodes, positions:, labels:)`: draws `nodes` (each `{ kind: "post", degree: 1 }` unless it says otherwise) at `positions` through `renderer.js`'s `draw` with a context `Proxy` that records, in order, every `fillText` as `["fillText", text]`, every `roundRect` as `["roundRect"]` and every `fill` as `["fill", fillStyle, globalAlpha]`, with a theme whose values are their own names and `labels` as `{ index, alpha: 1, x, y }` beside each node (`labelAt`'s place).

- [ ] **Step 2: Run them to see them fail**

Run: `bin/rails tailwindcss:build && bin/rails theme_css:build`, then `PGGSSENCMODE=disable bin/rails test test/system/admin/mind_graph_modules_test.rb -n "/notes badge|pin, notes badge|badge box|cover a notes badge|after every mark/"`
Expected: FAIL — the page's badge is at -10, overlapping its card by 4px; no ring; a badge is drawn with its node, before the labels; `badgeBoxes` is not a function; the label over the badge is placed.

- [ ] **Step 3: Implement**

- `marks.js`, `notesBadgeBox(node, x, y, radius)`: null unless `(node.open_notes ?? 0) > 0` and the node is a post or a page. The badge's right edge is `x - corner.x - NOTES_CLEAR` on a page's card and `x - corner.x + NOTES_OVERLAP` on a post (`corner = topCorner(node, radius)`); its half width `Math.max(NOTES_BADGE, NOTES_CHARACTER * label.length + NOTES_BADGE_PAD)` with the label "99+" above ninety-nine; it is centred on `y - corner.y`; the box answered is that pill grown by `NOTES_RING` (2) on every side. The badge's constants move here from `renderer.js` (they are its geometry), with their comments and the K3 sentence on `NOTES_CLEAR`.
- `renderer.js`: the node loop draws the mark and the pin only and keeps the indexes of the nodes it drew that have a badge; after the labels' loop and before the rings, each of those is drawn at its node's strength (`globalAlpha` as the node had it): first its ring, the box from `notesBadgeBox` as a pill filled with `theme.surface` and no stroke, then the badge as today inside it. `NODE_MARGIN = 30` with its comment's figure corrected ("99+" and its ring now end 30px left of a card's edge). The header's first lines say the order (edges, marks and pins, labels, notes badges, rings) and the "WITH OPEN NOTES" item says a card's badge stands outside it, over whatever it lands on, on a ring of the ground.
- `labels.js`: `chooseLabels` takes `obstacles = []` (a default: a caller with no badges has none to give) and `place` refuses a box that overlaps one, by the same test it uses for a label already placed; `badgeBoxes({ nodes, indexes, positions, radii, camera })` answers `notesBadgeBox` of every node of `indexes` at its screen position, the nulls left out. The header's rule 2 says "no label, and no notes badge (Claude Design, 2026-10-25)".
- `app.js`: the `chooseLabels` call passes `obstacles: badgeBoxes({ nodes: state.nodes, indexes: state.visibleNodes, positions: state.positions, radii: state.radii, camera: state.camera })`. Nothing new is written into the page, so `reset()` is unchanged.

- [ ] **Step 4: Run them to see them pass**

Run: `PGGSSENCMODE=disable bin/rails test test/system/admin/mind_graph_modules_test.rb`, then `PGGSSENCMODE=disable bin/rails test test/system/admin/mind_graph_test.rb`
Expected: PASS, "renderer: a node outside the canvas is not drawn, one whose mark reaches in is", the swatch tests (the notes swatch is the renderer's drawing on both sides of its comparison) and the label tests that pass no `obstacles` unchanged.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/mind_graph/marks.js app/javascript/mind_graph/renderer.js app/javascript/mind_graph/labels.js app/javascript/mind_graph/app.js test/system/admin/mind_graph_modules_test.rb
git commit -m "fix(mind-graph): a page's notes badge stands outside its card, over everything on a ring of the ground, and labels keep clear of it

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 9: The rules, the references, the roadmap, the spec, the full check and the pull request's text

**Files:**
- Modify: `CLAUDE.md`, `docs/reference/cs-studio-shell-and-dashboard.md`, `docs/reference/access-control-and-audit.md`, `docs/reference/design-system.md`, `docs/roadmap.md`, `docs/superpowers/specs/2026-10-23-layout-points-design.md`

- [ ] **Step 1: The rules in `CLAUDE.md`**

In the Mind graph bullet whose test list ends "the tab order is the search, the filter, the zoom buttons, then the canvas", the words "the legend's toggles and its "Status" link come before the zoom buttons and the canvas" become "the legend's toggles and its "Status key…" button come before the zoom buttons and the canvas (the button is last in the legend's Key group, after the marks, which hold no stop)".

Under "Rules a change can break silently", after the bullet on `Audit.record`, add:

```markdown
- Recent activity's collapse is `Dashboard::Activity`'s, in Ruby over the events its one event query read (four times the row limit, `READ_FACTOR`): a run joins only the actions with a counted sentence (`Audit::Sentence::COUNTED`, which is `Dashboard::Activity::COLLAPSING`), of one actor (user, token), on one page or post (any image, for uploads), within `Audit::COALESCE_WINDOW` of the run's newest event, and a run never costs a statement (`test/queries/dashboard/activity_test.rb`: "the same number of statements for a run of 5 blocks and one of 60, and for 60 runs of one", "a run is broken by another person's event between, by another page and by another action", "a block deleted from a run is not counted and does not split it"). The audit log does not collapse.
```

- [ ] **Step 2: The references**

- `cs-studio-shell-and-dashboard.md`: the dashboard paragraph ("three cards in an auto-fit grid") says the grid of at most three columns (`.admin-dashboard-cards`, 40rem and 60rem of the dashboard's width) and the empty line (`CardComponent`'s `p[data-card-empty]`, `empty_action`, O6's words, "Start a draft" and `admin--dashboard--start-draft`, "Drafts →"; no hint); "Recent activity" gains the collapse (Rulings 1–6, `Row#count`, the read of sixty) and the row's two letters (Ruling 7); "The camera" says the fit's margin of a tenth and the cap of 3; "The legend is the FILTER" and "Status is not a filter" say the two groups, "Status key…" last in Key and the unchanged Tab order; the badge sentences ("WITH OPEN NOTES" in "The states", "Hit testing", the marks) say a card's badge stands outside it (K3), that every badge is drawn after the marks and labels on a ring of `surface`, and "The label rule" that a label is not placed over a badge (`obstacles`, `badgeBoxes`; Claude Design, 2026-10-25).
- `access-control-and-audit.md`, where `Audit::Sentence` is described (and the audit log paragraph in the shell reference): `COUNTED`, `count:`/`mixed:`, the `:collection` part, and that only the dashboard passes a count.
- `design-system.md`: the dashboard card's empty line beside `EmptyStateComponent` (which stays for every other list).
- Then `grep -n "auto-fit\|Schedule a draft\|start one above\|MAX_FIT_ZOOM\|1\.5\b\|40px\|\"Status\" link\|aria-label='Legend'\|Nothing is waiting" docs/reference/*.md` and correct each sentence this PR made untrue.

- [ ] **Step 3: The roadmap and the spec**

`docs/roadmap.md`: a "Shipped" row "Layout points, part 2: the dashboard and the Mind graph (three cards at most in a row, one quiet empty line per card, recent activity collapsing runs of block edits and uploads, two letters in the activity row, the legend's Show and Key with "Status key…", a fit that fills about 80%, a page's notes badge outside its card, over its neighbours and clear of labels)" pointing at the spec; in "Contrast and buttons, part 2" strike the Mind graph's legend split, fit and count badges, the dashboard grid, collapsed activity and the empty states' wording, leaving the site's three for plan 3; remove "Layout points (part 1)"'s known gap "The dashboard's activity row still draws one letter by its own rule"; remove "a quieter empty-state line" from the Dashboard polish line; add under a "Layout points (part 2)" heading of known gaps the plan's limits: a feed whose sixty newest events collapse shows fewer than fifteen rows (Ruling 6), the audit log does not collapse, and a badge outside its card covers a neighbour's mark in a dense tree by design (Rulings 15, 16: the layout makes no room for it).

The spec: add `## As built (part 2, the dashboard and the Mind graph)` after "As built (part 1…)", listing this plan's sixteen rulings one line each and the departures from the spec's text: Decision 12's "a label and a URL" is a slot (Ruling 8); the counted actions are three, not every action (Ruling 2); the activity row keeps its own 28px circle (Ruling 7); Decision 14's "Status" link moved into Key as "Status key…", last (O5), outside the key list (Ruling 13); the dashboard view was converted to keys (Ruling 11); O6's "Your drafts →" is "Drafts →", and a page's badge is drawn last on a ring of the ground and kept clear of labels, both Claude Design's answers of 2026-10-25 to this plan's two questions (Rulings 9, 15, 16).

- [ ] **Step 4: The full check**

Run, in order, each after the previous has finished:

```bash
bin/rubocop
bin/brakeman
bin/rails zeitwerk:check
bin/rails tailwindcss:build && bin/rails theme_css:build
PGGSSENCMODE=disable bin/rails test
sysctl -n vm.loadavg
PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system
git status --short
```

Expected: rubocop and brakeman clean, zeitwerk fine, every test green, the browser suite in about its usual time (a run twice as long is not a result), and `git status` shows nothing but this task's documents.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs
git commit -m "docs: the activity collapse in CLAUDE.md, the references, the roadmap and the spec's as built (part 2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

- [ ] **Step 6: The pull request's text** (whoever opens the PR uses it; this plan pushes nothing)

```markdown
## Layout points, part 2 of 3: the dashboard and the Mind graph

Claude Design's review, part 2 (`docs/superpowers/specs/2026-10-23-layout-points-design.md`, sections C and D), with Claude Design's answers O5 and O6 and the owner's O9, O10 and O11.

- **Dashboard: at most three cards in a row**, by the dashboard's own width (two from about 640px, three from about 960px); a wider window makes them wider. With six cards that is a 3×2 grid at 1,400px.
- **Dashboard: one quiet empty line per card**, left-aligned under the title: "No drafts." with "Start a draft" (which puts the cursor in the quick-create title), "Nothing scheduled." with "Drafts →", "No unpublished changes.", "No recent activity."; "Schedule a draft to see it here." is gone.
- **Recent activity collapses a run**: "You added 4 Code blocks to “Code block demo”", "You edited 3 blocks on “About”", "You uploaded 12 images" (to the library), when one person does the same within ten minutes; the time is the last one's and its tooltip the span. Same number of database statements as before.
- **Two letters** in the activity row's circle, by the rule notes and presence use.
- **Mind graph: the legend in two groups**, "Show" (the toggles) and "Key" (the marks, then "Status key…"); the Tab order is unchanged.
- **Mind graph: Fit fills about 80%** of the canvas, and a small graph may be zoomed in up to 3.
- **Mind graph: a page's notes badge stands outside its card**, so it no longer covers it; badges are drawn over everything else on a thin ring of the background, and labels keep clear of them.

Not in this PR: the site's captions, its subpages list and its tags are part 3.

## Documentation

Editors: `editors/getting-started/signing-in-and-finding-your-way.md` (the dashboard: three columns, the empty lines and their actions, collapsed activity, two letters), `editors/posts/tags-related-posts-and-the-mind-graph.md` (the legend's Show and Key, "Status key…", Fit), `editors/working-together/notes-on-content.md` (where a page's notes badge stands in the Mind graph), `editors/media/the-media-library.md` (uploads in Recent activity are one line linking here). Administrators: none. Integrators: none.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
```

---

## Self-review

- **Claude Design's answers of 2026-10-25** are in: "Drafts →" (Task 2, Ruling 9), the badge drawn last on a ring and the labels' obstacles (Task 8, Rulings 15, 16); the plan has no open question left.
- **Spec coverage.** C: three columns (Task 1), the collapse (Tasks 3, 4; O10's uploads in both), the empty look and O6's words (Task 2), Notes for you unchanged (11c; its empty line follows the card, Task 2), the activity row's letters (O9, Task 5). D: the legend's two groups and O5 (Task 6), Fit (Task 7). O11's Mind graph half (Task 8; the reference card's triangle shipped in part 1). Part 1's deferred minors that touch these screens: the one-word non-Latin name (Task 5); the rest belong to editors, Settings, Translations and Media. E is plan 3's.
- **Steps.** Every test step carries its assertions and the spec's values (40rem/60rem, the words, 15/60, 10 minutes, 0.1/3, 2px); code appears for the decisions a signature leaves open (the run rule, the stylesheet, the empty line, the start-draft link); the rest is a signature, a file and the values.
- **Names.** `COUNTED` / `COLLAPSING`, `build(…, count:, mixed:)`, `library_route`, `:collection` (Tasks 3, 4); `Row#count`, `READ_FACTOR` (Task 4, docs); `empty_action`, `p[data-card-empty]`, `admin--dashboard--start-draft` with `field` and `start` (Task 2, docs); `.admin-dashboard`, `.admin-dashboard-cards` (Tasks 1, 2); `initials` (Task 5); `data-legend-section`, `data-legend-keys`, `#mind-graph-legend-key` (Task 6); `FIT_MARGIN`, `MAX_FIT_ZOOM` (Task 7); `notesBadgeBox`, `badgeBoxes`, `obstacles`, `NOTES_CLEAR`, `NOTES_RING`, `NODE_MARGIN` (Task 8, its Interfaces).
- **Review Focus.** Each of the five has its test in its task (4, 4, 2, 5, 6).
- **The Mind graph's rules.** No query changes, so no statement test moves; the legend's toggles, counts and swatches are untouched (a filter that moves nothing); the script writes nothing new into the page, so `reset()` has nothing new to take back; no clock is read; the Tab order is held by the existing tests with the button's new words.
- **Proportion.** Shorter than part 1's plan for fewer tasks; code bodies only for the run rule, a few stylesheet lines and two template lines.
