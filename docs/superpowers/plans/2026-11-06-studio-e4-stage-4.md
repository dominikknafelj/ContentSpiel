# CS Studio in E4, Stage 4 (the dashboard) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The dashboard's panels are headed by their job, with their heads tinted by kind. "Waiting for you" merges Open threads and Unpublished changes behind a segmented filter, and its unpublished rows offer "Review and publish…". Your drafts become tiles. The information panels stand in a rail when it fits. "New post…" is the screen's one primary and "New page…" its secondary, and the quick-create row goes. Riding with the stage, three shell changes: CS Studio's z-index values become one token scale with a guard, the theme switch cross-fades, and every sidebar module has a colour family.

**Architecture:** The dashboard keeps its container (`.admin-dashboard`, named `admin-dashboard`) and gains its own two-track grid at the rail's threshold, built from the rail's tokens (`--cs-editor-column`, `--cs-rail-width`, `--cs-rail-gap`, `--cs-rail`, `--cs-shadow-2`, `--cs-radius-rail`). It does not reuse `.admin-rail-grid`: that grid is a tab switcher (`admin--ui--rail`, tabs, panels, docked-only panels, the post form's `display: contents`) keyed to the editor's container. The dashboard's rail has no tabs and shows every panel. The merged panel is one query, `Dashboard::WaitingForYou`, over `Dashboard::OpenThreads` and `Dashboard::Feed#unpublished_changes`. It is drawn in a frame of its own, `turbo-frame#dashboard-waiting`, which its filter navigates and the notes inbox reloads. The z-index scale is fourteen `--cs-z-*` tokens written once in `content-spiel.css`, used as `z-index: var(--cs-z-…)` and `z-(--cs-z-…)`. The tie between the canvas's popovers and the notes slide-over goes because the canvas (`.admin-rail__main`) becomes a stacking context of its own.

**Tech Stack:** Rails 8.1, ViewComponent with Lookbook previews, Tailwind v4 (`tailwindcss-rails`), Stimulus over import maps, Turbo 8 frames and streams (no morphing), the View Transitions API, Minitest with Capybara on Cuprite.

**Spec:** `docs/superpowers/specs/2026-11-06-studio-e4-design.md` (approved 2026-11-06). The sections this plan uses: "Decided on 2026-11-06" (1), "The design, as decided" (tokens, the icon hue map, buttons, status), the screen table (Dashboard, Shell), "The rule for a screen the artifact does not draw", "Stage 4" in full (with its two shell changes added 2026-11-06), "Architecture-review findings", "The guard after E4" and "Constraints". Stage 3 as built (the base branch): `docs/reference/design-system.md` ("E4: the right rail") and the `.admin-rail-grid` comment in `content-spiel.tailwind.css`. The drawings are the Design System artifact's `StudioCalmDashboard` and `StudioCalmColourE4E5`.

**Two pull requests, stacked.**
- **PR 4a, the dashboard,** is Tasks 1–7 on branch `studio-e4-4`. It is stacked on `studio-e4-3b` (PR #191, in CI now) and targets that branch; once #191 merges it is rebased onto `main` and targets `main`.
- **PR 4b, the shell,** is Tasks 8–11 on `studio-e4-4b`, branched from `studio-e4-4`. It targets `studio-e4-4` until 4a merges, then `main`.

The reason for two: 4a is one screen, its queries, its read scope and its access checks, and is reviewed against the dashboard's drawing. 4b changes every screen's layering, the theme script that the public site shares, and the sidebar registry that a gem would use. A regression in either is then bisected to one PR. The two touch the same guard files (`admin_design_rules_test.rb`, `admin_contrast_test.rb`) and the same reference files. Stacking them, rather than opening them side by side, keeps those edits from conflicting. Each PR leaves the full suite green on its own.

## Global Constraints

- **The public site keeps its look.** No file under `app/assets/tailwind/themes/`, `app/components/blocks/`, `app/components/public/` or `app/views/layouts/public/` changes, and no `th-*` token. The theme fade's rule lives in the product stylesheet only. The public footer's toggle calls the same transition and gets the browser's own cross-fade (spec: "the public toggle takes the browser's default cross-fade"), so the theme contract is untouched.
- **Read scope, trash and notes visibility.** Every dashboard list reads through `AccessControl.scope` (which hides the trash), and every list or count of notes through `Notes.readable_threads`. A record outside the viewer's scope leaves no row. The merged panel adds no read of its own beyond its two sources and one scoped `pluck` of the publishable ids per model. `test/integration/trash_visibility_test.rb` stays green, and Task 1 joins it.
- **Queries are Active Record, then Arel, then SQL, as named reads.** `Dashboard::WaitingForYou` composes its two sources and adds no SQL string. The dashboard's statement count stays constant (`test/integration/admin/dashboard_test.rb`: "the dashboard renders in the same number of queries with 1 or 20 records per list"), and that includes the publishable ids.
- **Dependency direction.** The query returns data: a reason, a time, the source row or record, a route as `Audit::Sentence::Route`, and whether the viewer may publish. It holds no wording and no component. The component resolves the route and picks the words.
- **No admin string is a literal.**
  - The dashboard view's keys stay in `config/locales/admin/dashboard.en.yml` (`admin.dashboard.show.*`).
  - Every component under `app/components/admin/dashboard_screen/` reads `admin.components.dashboard_screen.*` from a new `config/locales/admin/dashboard_screen.en.yml`. That converts `RowComponent`, `ActivityRowComponent` and the translation panel, which hold English today ("edited", "by you", "tomorrow", "Needs translation", "(untitled)").
  - Notes' rows read `notes.en.yml`, and the shell's keys go in `shell.en.yml`.
  - Every new or converted component joins `admin_i18n_test`'s `CONVERTED`.
  - A script's words come from `data-messages`.
- **One primary per area.** "New post…" is the dashboard's one primary (`ButtonComponent.classes(:primary)` on the dialog trigger link) and "New page…" its secondary. "Review and publish…" is a small secondary. A row's closing verb is accent words, not a button. Nothing else on the screen is solid accent.
- **Colour by role, with words.** Panel heads: action is `bg-head-action`/`text-head-action-ink`, shortcuts are `head-cool`, information is `head-warm`. Docked in the rail, an information panel has no card and no band: its heading is `text-head-warm-ink` on `--cs-rail`. Scheduled dates are drawn only by a status component (`Admin::Ui::ScheduledDateComponent`, Task 2) in `bg-scheduled text-on-scheduled`. Translation states are never red.
- **Type voice.** A label is `text-label`, and a count is `text-count`. No `uppercase` with tracking, and no `font-mono` beyond `MONO_ALLOWED`. The scheduled date's month becomes sans `text-label`, no longer mono.
- **Depth.** A shadow is an elevation token, and a radius is a radius token. A tile is `rounded-tile bg-surface shadow-1`, raised to `shadow-2` on hover. The dashboard's rail is `--cs-rail` with `--cs-shadow-2` and `--cs-radius-rail`.
- **Left-aligned.** `mx-auto` stays refused. The dashboard's main column and rail are one left-aligned group, as the editors' are. Spare width falls right of the rail.
- **No Turbo morphing**, no `turbo_refreshes_with`, no `broadcast_refresh`. The merged panel and Notes for you are frames that are fetched again part by part.
- **No compatibility code.** The quick-create row, `POST dashboard/draft`, `Admin::DashboardController#create_draft`, `GET notes/open_threads`, `NoteInboxController#open_threads`, `_open_threads.html.erb` and the two `admin--dashboard--*` controllers are deleted, not kept beside the new ones. Their identifiers join `test/lib/source_layout_test.rb`'s list of old names.
- **Stimulus conventions.** An identifier follows its path. No inline handlers (`inline_handlers_test`). After removing a controller, search the tests by hand for its fragments (`quick-create`, `start-draft`, `dashboard_draft`).
- **Comment rule (#117).** A comment states a current invariant, a hazard or a reason. It never states a plan step, a review round, "Task N", "design pass round 2" or "spec §". Every task rewrites the comments of the files it changes by this rule. The dashboard's components, `feed.rb`, `open_threads.rb` and `theme_controller.js` are full of them.
- **Tests and the machine.** On macOS every test command is prefixed with `PGGSSENCMODE=disable`. Browser tests run only after `bin/rails tailwindcss:build`, never during a build or beside a running `bin/dev`. They run one file at a time, and only while the one-minute load (`sysctl -n vm.loadavg`, first figure) is under 6. **No test run is left in the background** when a task ends: a task's last step checks that `pgrep -f "rails test"` prints nothing.
- Commits follow conventional commits and end with:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT`
  A task that carries a finding says so in its body ("Advances #117", "Advances #140", "Advances #127").
- A look the spec does not settle and that a person sees is marked **(owner)**. Each has a default the build goes ahead on, and the PR lists them under "For the owner to check".

## Review Focus

1. **A filter chosen, then a live note arrives.** Today `admin--notes--inbox#reload` sets a frame's `src` back to its fixed URL, which would throw the person's "Unpublished changes" choice away under them. Task 3 changes `reload` so that a frame that already has a `src` reloads that `src`, and adds "a filter chosen in Waiting for you survives a live reload of the panel".
2. **Someone who may read a record but not publish it.** "Review and publish…" leads to a dialog that the editor draws only for `<type>s.publish`. Such a row says "Open" and leads to the editor, and is never a press that opens nothing. Task 1 answers `publishable` per row. Task 3 holds both verbs, and Task 4 holds "a viewer without publish opens the editor with no dialog".
3. **`?review=publish` on the wrong record or at the wrong time.** It may arrive on a draft, on a record with nothing to publish, or after a save's answer redraws the post header. Each of these opens nothing and raises nothing. The dialog opens at most once per page view, and never again from a re-render. Task 4.
4. **The theme pressed twice inside the fade, or a transition refused.** `startViewTransition` throws in a hidden document and skips a transition already running. The last choice must win, `aria-checked` must match it at once, and the theme must still change when the API throws. Task 9: "two presses inside the fade end on the second choice" and "a transition that throws still changes the theme".
5. **A canvas popover under the notes slide-over.** The rich-text popover and an open table strip sit at 20 today, and the slide-over sits at 20 too, so the slide-over wins only by coming later in the document. After Task 8 the canvas is its own stacking context, and the slide-over covers everything the canvas raises, at every width below the threshold. Task 8 measures it with `elementFromPoint`, not by reading the stylesheet.

---

## Decisions the spec left open

| Question | Decision | Why |
|---|---|---|
| Does the dashboard reuse `.admin-rail-grid` and the `admin-editor` container? | No. It has its own grid under its existing container `admin-dashboard`, reads the rail's tokens, and uses the same 1200px threshold. A test holds that the two thresholds are one number. | The editor's grid is a tab switcher whose rules (tabs, docked-only panels, the post form, notes) mean nothing here. Renaming its container for a second user would rewrite stage 3's guard for no gain. A container query cannot read a custom property, so the threshold is written twice and tied by a test. |
| The order in the document | Heading row, the mail notice, then the main column (Waiting for you, Notes for you, Pick up where you left off), then the rail (Publishing on its own, Languages behind …, What changed recently). | What needs the person comes first at every width, and the rail is information, read second. This is the opposite of the editor, where the settings come first because they configure what follows. |
| Below the threshold | The rail's panels follow the main column as cards (elevation 1, a tinted warm head), one column, two from 40rem. | Spec rule 5: the rail folds back into the page. |
| How the filter works | Three links of `Admin::Ui::TabLinksComponent` (the posts list's segmented control) that navigate `turbo-frame#dashboard-waiting` to `GET <admin>/dashboard/waiting?filter=threads\|unpublished`. Everything is the default. The filter is not written into the page's address **(owner)**. | It needs no script and no new control, and the frame is the same one a live signal reloads. Pushing the frame's address would put the partial's address in the location bar. |
| The same record both has an open thread and is unpublished | Two rows, one per reason, each with its own verb. | They are two jobs. A merged row would need two verbs on one link. |
| "Review and publish…" | A link to the record's editor with `review=publish`. There the header's Publish changes dialog opens on load through the dialog's existing `open_on_load:`. For a viewer who may not publish the record, the row's verb is "Open". | The dialog lives with the editor (drawn once, outside what a save replaces). A second copy on the dashboard would duplicate its queue-hold wiring and its shown-schedule check. |
| A row's closing verb | Accent words at the row's end, inside the row's one link: "Open thread" on a thread row and on a Notes for you row, "Review and publish…" (a small secondary link) or "Open" on an unpublished row **(owner)**. | "Action rows end in a verb", and a whole-row link cannot hold a second link. |
| The line under each heading | The copy in Task 2's key list **(owner)**. | The spec asks for one line and gives no words. |
| "Languages behind English" | `Languages behind %{language}`, the primary language's name in the CS Studio language (`Translations.primary_locale`). | A site whose primary language is not English must not read "English". |
| "The sidebar chips on the sidebar's ground at 3:1" | Every registered module's family icon is measured at 3:1 on its chip, on `--cs-chrome` and on `--cs-accent-tint` (the current row's ground, since the selected row keeps its chip's colour), in both themes. The test iterates `StudioModules.entries`, so a new module is measured by being registered. | A chip's pale fill on white is not 3:1, and the spec does not ask for that. The icon is what must read. Figures: lowest form on accent tint 4.86 (light), media on accent tint 4.95. |
| The z-index scale's values | The order of today is kept for every pair of layers that can meet. The changes are: the save bar 20 → 15, the media drop overlay 30 → 32, the shell's scrim 30 → 35 (it covers an open popover, which it tied with), and the rich-text popover 20 → the popover layer (30) inside the isolated canvas. | That keeps a refactor that shows nothing new apart from the fixed tie. The full table is in Task 8. |

---

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `app/queries/dashboard/waiting_for_you.rb` (new) | the merged panel's rows | 1 |
| `app/components/admin/dashboard_screen/panel_component.*` (replaces `card_component.*`), `translation_panel_component.*` (replaces `translation_card_component.*`), `row_component.*`, `activity_row_component.*`, `app/components/admin/ui/scheduled_date_component.rb` (new), `config/locales/admin/dashboard_screen.en.yml` (new) | panels by kind, the scheduled date, every string a key | 2 |
| `app/components/admin/dashboard_screen/waiting_panel_component.*`, `unpublished_row_component.*` (new), `app/views/admin/dashboard/_waiting.html.erb` (new), `DashboardController#waiting`, `config/routes.rb`, `NoteInboxController`, `app/views/admin/note_inbox/_card.html.erb`, `notes_screen/open_thread_row_component.*`, `inbox_row_component.*`, `controllers/admin/notes/inbox_controller.js`, `app/views/layouts/admin.html.erb` | Waiting for you and Notes for you | 3 |
| `editor_screen/header_component.*`, `publish_changes_dialog_component.*` | `review=publish` opens Publish changes | 4 |
| `app/components/admin/dashboard_screen/draft_tile_component.*` (new), `app/views/admin/dashboard/show.html.erb`, `DashboardController`, deleted: `quick_create_component.*`, `controllers/admin/dashboard/*` | the heading row, drafts as tiles, quick create gone | 5 |
| `content-spiel.tailwind.css`, `show.html.erb`, `test/lib/admin_design_rules_test.rb` | the main column and the rail | 6 |
| `docs/reference/*.md`, `CLAUDE.md` | 4a's reference | 7 |
| `content-spiel.css`, `content-spiel.tailwind.css`, `admin-rich-text.css`, eleven components and views, `rich_text/popover.js` | the z-index scale and its guard | 8 |
| `app/javascript/controllers/theme_controller.js`, `content-spiel.css` | the theme switch fades | 9 |
| `app/models/studio_modules.rb`, `config/initializers/studio_modules.rb`, `shell/sidebar_component.rb` | every module has a family | 10 |
| `docs/reference/*.md`, `CLAUDE.md` | 4b's reference | 11 |

---

# PR 4a: the dashboard

### Task 1: One query answers Waiting for you

**Files:**
- Create: `app/queries/dashboard/waiting_for_you.rb`
- Modify: `app/queries/dashboard/feed.rb` and `open_threads.rb` (comments only: the "Task 16", "design pass", "spec §" and "final fix wave" references become the invariants they stand for)
- Test: `test/queries/dashboard/waiting_for_you_test.rb` (new), `test/integration/trash_visibility_test.rb` (one case added)

**Interfaces:**
- Consumes: `Dashboard::OpenThreads.new(actor:, channel:, limit:)#rows` (`OpenThreads::Row`) and `Dashboard::Feed.new(actor:, channel:)#unpublished_changes` (records carrying `unpublished_changes_at`), both unchanged.
- Produces:
  - `Dashboard::WaitingForYou::FILTERS = %w[everything threads unpublished].freeze`.
  - `Dashboard::WaitingForYou::Row = Data.define(:reason, :at, :thread, :record, :route, :publishable)`.
    - `reason` is `:thread` or `:unpublished`.
    - For a thread row, `thread` is the `OpenThreads::Row`, `record` is its record, `route` is its route and `publishable` is false.
    - For an unpublished row, `thread` is nil and `at` is `unpublished_changes_at`. `route` is `Audit::Sentence.route_for(record).with(params: { review: "publish" })` when `publishable`, and the bare route otherwise.
  - `Dashboard::WaitingForYou.new(actor:, filter: "everything", channel: Current.channel, limit: 5)`. An unknown or blank filter is `"everything"`, and `#filter` answers the one in use.
  - `#rows` merges both sources newest `at` first (ties by reason, then id) and cuts to `limit`. `"threads"` and `"unpublished"` read only their own source.
  - `publishable` is decided for all unpublished rows at once: one `AccessControl.scope(actor, "pages.publish", Page.where(id: …)).pluck(:id)`, and the same for posts. It is skipped when there are no rows of that model.

- [ ] **Step 1: Write the failing tests** in `waiting_for_you_test.rb`:
  - `test "threads and unpublished changes in one list, the newest first, cut to five"`. Make 4 records with open threads and 4 published records with marks, at interleaved times. Assert the 5 newest across both sources, in order, with their reasons.
  - `test "each filter reads its own source alone, and an unknown filter is everything"`. With `filter: "threads"` every reason is `:thread`, and with `"unpublished"` every reason is `:unpublished`. `filter: "junk"` gives `#filter == "everything"`.
  - `test "a record both discussed and unpublished is two rows, one per reason"`.
  - `test "an unpublished row leads to Publish changes only for a viewer who may publish it"`. As an editor with `pages.edit` and no `pages.publish`, assert `publishable == false` and `route.params` without `review`. As a publisher, assert `{ review: "publish" }`.
  - `test "what the viewer may not read and what is in the trash leave no row"`. Use a scoped group, trash one unpublished page, and give one thread a record outside the scope.
  - `test "the same statements for one row of each as for five"`, counted with `count_statements` (`test/test_helper.rb`).
  - In `trash_visibility_test.rb`: `test "Waiting for you hides a trashed record's open threads and its unpublished changes"`.
- [ ] **Step 2: Run them, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/queries/dashboard/waiting_for_you_test.rb test/integration/trash_visibility_test.rb`. Expected: `NameError: uninitialized constant Dashboard::WaitingForYou`.
- [ ] **Step 3: Implement** `Dashboard::WaitingForYou`. Each source is read at `limit`, so the merged cut can never drop a row that belongs in the top `limit`. The class comment states that, and the scope rule: "each source hides what the viewer may not read; this class adds only the publish ids". Rewrite the comments of `feed.rb` and `open_threads.rb` by the comment rule.
- [ ] **Step 4: Run them, and verify they pass.** Also run `test/queries/dashboard`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: Dashboard::WaitingForYou, open threads and unpublished changes in one read-scoped list` (body: `Advances #117`)

---

### Task 2: Panels headed by their job, a scheduled date block, and every string a key

**Files:**
- Create: `app/components/admin/dashboard_screen/panel_component.{rb,html.erb}` (from `card_component.*`, which is deleted), `translation_panel_component.{rb,html.erb}` (from `translation_card_component.*`, deleted), `app/components/admin/ui/scheduled_date_component.rb`, `config/locales/admin/dashboard_screen.en.yml`
- Modify: `row_component.*` (the going-live variant draws `ScheduledDateComponent`; every word a key), `activity_row_component.*` (its words keys, its comments by the rule; its 28px circle stays its own)
- Modify: `test/components/previews/admin/dashboard_screen/*` (renamed), `test/components/previews/admin/ui/scheduled_date_component_preview.rb` (new)
- Test: `test/components/admin/dashboard_screen/panel_component_test.rb` (from `card_component_test.rb`), `translation_panel_component_test.rb`, `row_component_test.rb`, `test/components/admin/ui/scheduled_date_component_test.rb` (new), `test/lib/admin_i18n_test.rb`, `test/lib/admin_design_rules_test.rb`, `test/lib/admin_contrast_test.rb`, `test/lib/notes_boundary_test.rb`

**Interfaces:**
- Produces:
  - `Admin::DashboardScreen::PanelComponent.new(kind:, title:, line:, id:, empty:, link: nil, limit: LIMIT)`.
    - `KINDS = { action: "bg-head-action text-head-action-ink", shortcuts: "bg-head-cool text-head-cool-ink", information: "bg-head-warm text-head-warm-ink" }`. An unknown kind raises `ArgumentError`.
    - It keeps `CardComponent`'s slots (`rows`, `badge`, `action`, `footer`, `empty_action`) and its `LIMIT = 5`.
    - It draws `section.admin-dashboard-panel.admin-dashboard-panel--<kind>[aria-labelledby=<id>]`, which holds `header.admin-dashboard-panel__head`. The head holds `h2#<id>` (`text-h3`, the kind's ink), then `p.admin-dashboard-panel__line` (`text-sm`, the kind's ink), then the badge and the action.
  - `Admin::Ui::ScheduledDateComponent.new(at:)` draws `span.admin-scheduled-date` (`bg-scheduled text-on-scheduled rounded-chip size-10`): the month as `text-label` and the day at 18px semibold. It is `aria-hidden`, because the row's `<time>` says the date in words. It joins `LIVE_SCHEDULED_FILES`.
  - `Admin::DashboardScreen::TranslationPanelComponent.new(entries:)` is the translation card as an information panel. `STATUS_FILL_FILES` names the new path in place of the old.
  - `PanelComponent` takes its words from its caller, so each heading and line is a key where the caller is. The headings and lines are **(owner)**:

    | Key | Words |
    |---|---|
    | `admin.components.dashboard_screen.waiting_panel.title` / `.line` | "Waiting for you" / "Open threads and changes that are not on the site yet." |
    | `admin.note_inbox.card.title` / `.line` (`notes.en.yml`) | "Notes for you" / "Mentions and replies addressed to you." |
    | `admin.dashboard.show.drafts.title` / `.line` | "Pick up where you left off" / "Your drafts, the latest first." |
    | `admin.dashboard.show.going_live.title` / `.line` | "Publishing on its own" / "Scheduled pages and posts, the soonest first." |
    | `admin.components.dashboard_screen.translation_panel.title` / `.line` | "Languages behind %{language}" / "What is missing or outdated, per language." |
    | `admin.dashboard.show.activity.title` / `.line` | "What changed recently" / "The latest changes to pages, posts and images." |
    | `admin.components.dashboard_screen.row.*`: `edited_html`, `by_you`, `page`, `untitled`, `tomorrow`, `in_days` (one/other), `in_hours`, `soon` | today's words |
    | `admin.components.dashboard_screen.translation_panel.*` | today's words: "12 missing · 1 outdated", "All translated", "Outdated:", "Open the translations overview" |

    `dashboard.en.yml` loses `unpublished_changes.*` (Task 3 removes that card) and every key that only quick create used (Task 5). The i18n test's unused-key check holds it.

- [ ] **Step 1: Write the failing tests.**
  - `panel_component_test.rb`:
    - `test "each kind tints its head: action violet, shortcuts cool, information warm"`. Assert the head's classes per kind, and `ArgumentError` for `:other`.
    - `test "the heading and its one line stand in the head, and the section is named by the heading"`.
    - Keep `CardComponent`'s tests renamed: the cap, the empty line with its action, the badge, the action and the footer.
  - `scheduled_date_component_test.rb`: `test "a scheduled date is an amber block with its month and day, hidden from a screen reader"`.
  - `row_component_test.rb`: `test "a going-live row draws the scheduled date block and says when in words"`, which asserts `.admin-scheduled-date` and the `<time>`. Its existing tests read the keys.
  - `admin_i18n_test.rb`: add to `CONVERTED` `panel_component.{rb,html.erb}`, `translation_panel_component.{rb,html.erb}`, `row_component.{rb,html.erb}`, `activity_row_component.{rb,html.erb}` and `app/components/admin/ui/scheduled_date_component.rb`, and remove `card_component.*`. The test fails while English remains.
  - `admin_design_rules_test.rb`:
    - add `dashboard_screen/card_component.rb`, `dashboard_screen/translation_card_component.rb` and `dashboard_screen/quick_create_component.rb` to "the replaced components are gone";
    - `LIVE_SCHEDULED_FILES` gains `scheduled_date_component.rb`;
    - the danger test at line 106 names the translation panel's path.
  - `admin_contrast_test.rb`: `test "an information panel's heading and line read on the rail's ground"`. Assert `--cs-head-warm-ink` on `--cs-rail` at ≥ 4.5 (6.56 light / 8.92 dark) and `--cs-head-action-ink` on `--cs-rail` (9.21 / 8.57), both schemes.
  - `notes_boundary_test.rb`: the named exception `dashboard_screen/card_component.rb` becomes `dashboard_screen/panel_component.rb`, with the same reason.
- [ ] **Step 2: Run them, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/components/admin/dashboard_screen test/components/admin/ui/scheduled_date_component_test.rb test/lib/admin_i18n_test.rb test/lib/admin_design_rules_test.rb test/lib/admin_contrast_test.rb`.
- [ ] **Step 3: Implement.** The dashboard view renders `PanelComponent` and `TranslationPanelComponent` wherever it rendered the card. Notes' `_card` partial too (`kind: :action`), so the screen draws as before with the new heads. Task 6 places the panels. `TranslationCardComponent::WIDTHS` moves with the component. Rewrite every comment in these files by the comment rule.
- [ ] **Step 4: Run them, and verify they pass.** Also run `test/integration/admin/dashboard_test.rb test/integration/admin/note_inbox_test.rb` (headings read by the tests change to the new words). Expected: PASS.
- [ ] **Step 5: Commit** `feat: the dashboard's panels are headed by their job, tinted by kind, and every word is a key` (body: `Advances #117`)

---

### Task 3: Waiting for you, and rows that end in a verb

**Files:**
- Create: `app/components/admin/dashboard_screen/waiting_panel_component.{rb,html.erb}`, `unpublished_row_component.{rb,html.erb}`, `app/views/admin/dashboard/_waiting.html.erb`
- Modify: `app/controllers/admin/dashboard_controller.rb` (`waiting`), `config/routes.rb` (`get "dashboard/waiting", to: "dashboard#waiting", as: :dashboard_waiting`; `notes/open_threads` deleted, and the comment above the inbox routes rewritten)
- Modify: `app/controllers/admin/note_inbox_controller.rb` (`open_threads` deleted; the class comment says five answers), `app/views/admin/note_inbox/_open_threads.html.erb` (deleted), `app/views/admin/note_inbox/_card.html.erb` (`PanelComponent`, `kind: :action`)
- Modify: `app/components/admin/notes_screen/open_thread_row_component.*` and `inbox_row_component.*` (a closing verb; `inbox_row_component.rb` calls `PersonName.of` in place of `::Notes.name_of`, and so does `note_inbox_controller.rb#delivery_sentence`), `config/locales/admin/notes.en.yml` (`open_thread_row.verb`, `inbox_row.verb`: "Open thread"; `note_inbox.open_threads.*` deleted)
- Modify: `app/javascript/controllers/admin/notes/inbox_controller.js` (`openThreadsUrl` → `waitingUrl`; `reload` keeps a navigated `src`), `app/views/layouts/admin.html.erb` (`data-admin--notes--inbox-waiting-url-value`)
- Test: `test/components/admin/dashboard_screen/waiting_panel_component_test.rb`, `unpublished_row_component_test.rb` (new), `test/integration/admin/dashboard_waiting_test.rb` (new), `test/integration/admin/note_inbox_test.rb`, `test/components/admin/notes_screen/{open_thread_row,inbox_row}_component_test.rb`, `test/system/admin/note_inbox_test.rb`, `test/system/admin/unpublished_changes_test.rb`, `test/lib/notes_boundary_test.rb`, `test/lib/source_layout_test.rb`

**Interfaces:**
- Consumes: Task 1's `Dashboard::WaitingForYou` and `Row`; Task 2's `PanelComponent`.
- Produces:
  - `Admin::DashboardScreen::WaitingPanelComponent.new(waiting:)` draws `turbo-frame#dashboard-waiting.contents` around a `PanelComponent` (`kind: :action`, `id: "dashboard-waiting-title"`).
    - Its action slot holds `Admin::Ui::TabLinksComponent` with the label key `waiting_panel.filter_label` ("Show"). There are three tabs: `waiting_panel.filters.everything` "Everything", `.threads` "Open threads" and `.unpublished` "Unpublished changes". Each `href` is `admin_dashboard_waiting_path(filter:)`, with `link_data: { turbo_frame: "dashboard-waiting" }`.
    - Its empty line is per filter: "Nothing is waiting for you.", "No open threads." or "No unpublished changes.".
    - A `:thread` row is `NotesScreen::OpenThreadRowComponent` and an `:unpublished` row is `UnpublishedRowComponent`.
  - `Admin::DashboardScreen::UnpublishedRowComponent.new(row:)` draws:
    - the title as a link to the record's editor (bare route);
    - "Page" or the content-type dot, and "changed <time ago>";
    - `UnpublishedChipComponent`;
    - then the verb. For a `publishable` row the verb is `link_to t(".review"), <route with review>` with `ButtonComponent.classes(:secondary, size: :small)` ("Review and publish…"). Otherwise it is accent words, `t(".open")` ("Open"), on the same link as the title.
  - `Admin::DashboardController#waiting` renders `admin/dashboard/_waiting` with `layout: false` for a frame request (`turbo_frame_request_id == "dashboard-waiting"`). Any other request is answered 303 to `admin_root_path(**admin_url_options)`.
  - `admin--notes--inbox`:
    - `static values` gains `waitingUrl` and loses `openThreadsUrl`.
    - `refreshInbox` reloads `#dashboard-waiting` and `#notes-for-you`.
    - `reload(frame, url)`: a frame with a `src` calls `frame.reload()`, and one without gets `src = url`. The comment says why: the person's filter is the frame's `src`.
  - The closing verb: `span.admin-row-verb` (`text-sm font-medium text-accent shrink-0`) inside the row's one link, after the count pill (thread row) or the time (inbox row). The rows' grids gain an `auto` track.

- [ ] **Step 1: Write the failing tests.**
  - `dashboard_waiting_test.rb` (integration, signed in, `with_locales(%w[en de])`):
    - `test "the dashboard draws Waiting for you in its own frame, with Everything chosen"`. Assert `turbo-frame#dashboard-waiting`, `nav[aria-label=Show] a[aria-current=page]` with the text "Everything", and no `#notes-open-threads` and no `#dashboard-unpublished-changes`.
    - `test "each filter is answered by the frame alone"`. GET with `Turbo-Frame: dashboard-waiting` and `filter=unpublished`. Assert no `<html>`, the frame, only unpublished rows, and "Unpublished changes" current.
    - `test "the panel's address outside a frame goes to the dashboard"` asserts a 303 to the admin root.
    - `test "notes/open_threads is gone"` asserts `admin_open_note_threads_path` is undefined (a `NameError` from the route helper).
  - `unpublished_row_component_test.rb`:
    - `test "a publisher's row ends in Review and publish…, leading to the editor with review=publish"`;
    - `test "a row the viewer may not publish ends in Open, on the title's own link"`.
  - `open_thread_row_component_test.rb` and `inbox_row_component_test.rb`: `test "the row ends in Open thread, inside its one link"`.
  - `note_inbox_test.rb` (integration): "each part is fetched on its own" loses the open-threads GET and keeps the card and the count. "the dashboard has Notes for you and Open threads…" becomes "the dashboard has Notes for you and Waiting for you, each in a frame of its own".
  - `notes_boundary_test.rb`: `waiting_panel_component.rb` (it names open threads through `OpenThreadRowComponent`) joins the dashboard's named exception, with the same trigger.
  - `source_layout_test.rb`: the old-name list gains `admin--dashboard--quick-create` and `admin--dashboard--start-draft` (Task 5 deletes them; listing them here makes the first run of Task 5's tests catch a leftover).
  - System, `note_inbox_test.rb`: `test "a filter chosen in Waiting for you survives a live reload of the panel"`. Choose "Unpublished changes", have a second session mention the viewer, wait for the Notes for you row, and assert that "Unpublished changes" is still current and the rows are still unpublished ones.
  - System, `unpublished_changes_test.rb`: `test "an unpublished change waits for its publisher on the dashboard, and Review and publish… opens Publish changes"` (the dialog part is held by Task 4's implementation; it runs green after Task 4).
- [ ] **Step 2: Run them, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/integration/admin/dashboard_waiting_test.rb test/components/admin/dashboard_screen test/components/admin/notes_screen test/lib/notes_boundary_test.rb`.
- [ ] **Step 3: Implement.** `show.html.erb` renders `WaitingPanelComponent.new(waiting: Dashboard::WaitingForYou.new(actor: Current.actor))` where the Open threads card and the Unpublished changes card stood. Delete both cards. The `_waiting` partial renders the same component with `filter: params[:filter]`. The class comment of `NoteInboxController` and the routes comment state the five answers. #140's part: in the two files this task changes, `Notes.name_of` becomes `PersonName.of`. The alias itself stays for stage 6, which deletes it.
- [ ] **Step 4: Run them, and verify they pass.** Run `test/integration/admin test/components/admin test/lib`, and locally `note_inbox_test`. Expected: PASS (except the dialog assertion of `unpublished_changes_test`, which passes after Task 4).
- [ ] **Step 5: Commit** `feat: Waiting for you merges open threads and unpublished changes, filtered, and action rows end in a verb` (body: `Advances #140`, `Advances #117`)

---

### Task 4: `review=publish` opens Publish changes in the editor

**Files:**
- Modify: `app/components/admin/editor_screen/header_component.{rb,html.erb}`, `publish_changes_dialog_component.{rb,html.erb}`
- Test: `test/integration/admin/review_publish_test.rb` (new), `test/components/admin/editor_screen/publish_changes_dialog_component_test.rb`, `test/system/admin/unpublished_changes_test.rb`

**Interfaces:**
- Produces:
  - `PublishChangesDialogComponent.new(…, open_on_load: false)` opens on load when `error.present? || open_on_load`.
  - `HeaderComponent#review_on_load?` is `helpers.params[:review] == "publish" && !draft? && state.changes? && may_publish?`. It is passed as `open_on_load:`. Every condition false opens nothing and raises nothing.

- [ ] **Step 1: Write the failing tests** in `review_publish_test.rb`:
  - `test "a live page with changes opens Publish changes on load from review=publish"`, which asserts `dialog#publish-changes-page-<id>[data-admin--ui--dialog-open-on-load]`;
  - `test "review=publish on a draft, on a clean live page, or for a viewer without publish opens nothing"`;
  - `test "a save's answer draws the post header without the dialog opening again"`: PATCH the post and assert that the streamed header has no `open-on-load`.
  - The component test: `test "open_on_load opens the dialog without an error"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** The header's comment for the dialogs gains one sentence: the dialog opens on load only from a GET that asks for it, so a save's answer, which is no GET, never reopens it. `admin--ui--dialog` already strips the attribute, so a Turbo restore does not reopen it.
- [ ] **Step 4: Run them, and verify they pass.** Locally run `unpublished_changes_test` and `publish_dialog_steady_test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: an editor opened with review=publish opens Publish changes` (body: `Advances #117`)

---

### Task 5: The heading row, drafts as tiles, and quick create gone

**Files:**
- Create: `app/components/admin/dashboard_screen/draft_tile_component.{rb,html.erb}`
- Modify: `app/views/admin/dashboard/show.html.erb`, `config/locales/admin/dashboard.en.yml`
- Modify: `app/controllers/admin/dashboard_controller.rb` (`create_draft` deleted; the class comment), `config/routes.rb` (`post "dashboard/draft"` deleted)
- Delete: `app/components/admin/dashboard_screen/quick_create_component.*`, `app/javascript/controllers/admin/dashboard/quick_create_controller.js`, `start_draft_controller.js`, `test/components/admin/dashboard_screen/quick_create_component_test.rb`, `test/components/previews/admin/dashboard_screen/quick_create_component_preview.rb`
- Test: `test/components/admin/dashboard_screen/draft_tile_component_test.rb` (new), `test/integration/admin/dashboard_test.rb`, `test/system/admin/dashboard_test.rb`, `test/system/admin/new_record_test.rb`, `test/lib/admin_i18n_test.rb`

**Interfaces:**
- Consumes: `Dashboard::Feed#drafts` (unchanged), and the layout's `new-post-dialog` and `new-page-dialog` (`dialog_trigger(...)`).
- Produces:
  - The heading row is `div.admin-dashboard__head`: `h1` "Dashboard", then:
    - "New page…" (`t(".new_page")`, a link to `new_admin_page_path` with `ButtonComponent.classes(:secondary)` and `dialog_trigger("new-page-dialog")`), drawn with `can?("pages.create")`;
    - "New post…" (`t(".new_post")`, a link to `new_admin_post_path` with `ButtonComponent.classes(:primary)` and `dialog_trigger("new-post-dialog")`), drawn with `can?("posts.create")`.

    The primary comes last, by the convention of a header. Both are `turbo_frame: "_top"`, and each falls through to its standalone page without the dialog.
  - `Admin::DashboardScreen::DraftTileComponent.new(record:)` draws an `article.admin-draft-tile` (`rounded-tile bg-surface shadow-1 p-4`, hover `shadow-2`). It holds:
    - the type ("Page", or the content-type dot with its label);
    - the title as a link (`text-h3`), whose `::after` stretches over the tile, so the whole tile is the one target;
    - the excerpt for a post, clamped to two lines (`line-clamp-2`, escaped text), or nothing;
    - "edited <time ago>";
    - the verb "Continue" in accent words.

    It reads only what `Feed#drafts` loaded, so a tile costs no statement.
  - "Pick up where you left off" is a `PanelComponent` with `kind: :shortcuts`, whose rows are a `ul.admin-draft-tiles` grid (Task 6 lays it out). Its link is "→ All drafts" for `posts.read`. Its empty action, with `posts.create`, is "Start a draft": a link with `dialog_trigger("new-post-dialog")`.

- [ ] **Step 1: Write the failing tests.**
  - `draft_tile_component_test.rb`:
    - `test "a draft tile shows its type, title, two lines of excerpt and when it was edited, and ends in Continue"`;
    - `test "a tile's excerpt is escaped text"`, with `<script>` in the excerpt.
  - `dashboard_test.rb` (integration):
    - delete the six quick-draft tests;
    - `test "New post… is the screen's one primary and New page… its secondary, each with its right"` checks a user with both rights, one with each, and one with neither;
    - `test "Start a draft opens the New post dialog, for someone who may create posts"`;
    - `test "POST dashboard/draft is gone"`;
    - keep "the same number of queries with 1 or 20 records per list", now with 20 drafts as tiles.
  - System `dashboard_test.rb`:
    - the quick-create tests go;
    - `test "New post… opens the New post dialog, and its draft opens in the editor"`;
    - `test "Start a draft in an empty Pick up where you left off opens the New post dialog"`;
    - `test "a draft tile is one target: a press anywhere on it opens the draft"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Delete the files, the route and the action. Delete the `drafts.start` comment in `dashboard.en.yml` and the keys only quick create used. `create_draft`'s "Draft created" notice goes with it. The New post dialog's own create path makes the draft.
- [ ] **Step 4: Run them, and verify they pass.** Run `test/integration/admin test/components/admin/dashboard_screen test/lib`, and locally `dashboard_test`, `new_record_test` and `drafts_test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: New post… and New page… replace the quick-create row, and drafts are tiles` (body: `Advances #117`)

---

### Task 6: The main column and the rail

**Files:**
- Modify: `app/assets/tailwind/content-spiel.tailwind.css` (the dashboard's block: the comment and rules below replace `.admin-dashboard-cards`)
- Modify: `app/views/admin/dashboard/show.html.erb` (the two areas, in document order)
- Test: `test/lib/admin_design_rules_test.rb` ("the dashboard's grid…" is rewritten), `test/system/admin/dashboard_test.rb`

**Interfaces:**
- Produces, in `content-spiel.tailwind.css`:

  | Rule | What it does |
  |---|---|
  | `.admin-dashboard { container: admin-dashboard / inline-size; }` | unchanged: the dashboard's width, not the window's |
  | `.admin-dashboard__grid { display: grid; grid-template-columns: minmax(0, 1fr); row-gap: 1.5rem; }` | one column below the threshold |
  | `.admin-dashboard__main { container: admin-dashboard-main / inline-size; display: flex; flex-direction: column; gap: 1rem; }` | the main column's panels |
  | `.admin-dashboard__actions { display: grid; gap: 1rem; grid-template-columns: minmax(0, 1fr); }` and `@container admin-dashboard-main (min-width: 44rem) { … repeat(2, minmax(0, 1fr)) }` | Waiting for you and Notes for you side by side when the main column is wide enough **(owner)** |
  | `.admin-draft-tiles { display: grid; gap: 0.75rem; grid-template-columns: minmax(0, 1fr); }`, two from `admin-dashboard-main` 32rem, three from 48rem | the tiles, never `auto-fit` |
  | `.admin-dashboard__rail { display: grid; gap: 1rem; grid-template-columns: minmax(0, 1fr); }`, two from `admin-dashboard` 40rem | below the threshold: the information panels as cards after the main column |
  | `@container admin-dashboard (min-width: 1200px) { … }` | docked: `.admin-dashboard__grid { grid-template-columns: minmax(0, var(--cs-editor-column)) var(--cs-rail-width); column-gap: var(--cs-rail-gap); justify-content: start; align-items: start; }`; `.admin-dashboard__rail { grid-template-columns: minmax(0, 1fr); background: var(--cs-rail); box-shadow: var(--cs-shadow-2); border-radius: var(--cs-radius-rail); padding: var(--cs-sp-3) var(--cs-sp-4); }`; inside it `.admin-dashboard-panel { background: transparent; box-shadow: none; }` and `.admin-dashboard-panel__head { background: transparent; padding-inline: 0; }`: on the rail an information panel has no card and no band, and its heading is its warm ink on the rail's ground |

- [ ] **Step 1: Write the failing tests.**
  - `admin_design_rules_test.rb`:
    - `test "the dashboard's main column and rail are laid out by the dashboard's container, from the rail's tokens"`. Parse the `@container admin-dashboard (min-width: 1200px)` block, as `css_blocks` does for the editor. Assert the grid's columns use `--cs-editor-column` and `--cs-rail-width`, the gap is `--cs-rail-gap`, and the rail's ground is `--cs-rail` / `--cs-shadow-2` / `--cs-radius-rail`. Assert that no `@media` rule names `admin-dashboard`, and that `show.html.erb` holds no `auto-fit`.
    - `test "the editors' rail and the dashboard's dock at one threshold"`. The `min-width` of `@container admin-editor (…)` and of the dashboard's docking block are equal.
  - System `dashboard_test.rb`, which replaces "the cards stand three in a row…". Each case uses `at_window`:
    - `test "at 1600px the information stands in a rail right of the main column, on the rail's ground without cards"`. Assert that the rail's box starts at main's right + 28 (± 1) and is 360 wide (± 1); that a panel in it has a computed `box-shadow` of `none`; and that the rail's `background-color` equals `--cs-rail` read through `getComputedStyle`. This is the cascade test of the docked rule over the panel's card.
    - `test "at 1100px the information follows the main column as cards"`. Assert the rail panels' tops are below the main column's bottom, and their `box-shadow` equals `--cs-shadow-1`.
    - `test "the rail follows the dashboard's own width, not the window's"`. Below 1280px the sidebar is a drawer, so the dashboard is wider at 1279px than at 1280px. At both windows, assert that the rail is docked exactly when `.admin-dashboard`'s measured width is 1200px or more.
    - `test "the focus goes heading, New page…, New post…, Waiting for you, Notes for you, drafts, then the rail"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** `show.html.erb`: `div.admin-dashboard > div.admin-dashboard__head`, then the mail notice, then `div.admin-dashboard__grid > (div.admin-dashboard__main > div.admin-dashboard__actions, the drafts panel) + aside.admin-dashboard__rail[aria-label=t(".rail_label")]`. The aside's label is "At a glance" **(owner)**. Rewrite the block's comment from the old one: the container, the threshold shared with the editors' (and why it is written twice), the order in the document, and no `auto-fit`. Delete the view's long header comment and its "round 2" history.
- [ ] **Step 4: Run them, and verify they pass.** Run `bin/rails tailwindcss:build`, then locally `dashboard_test`, `note_inbox_test` and `presence_lists_test`. Also run `test/lib`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: the dashboard's information stands in a rail when it fits` (body: `Advances #117`)

---

### Task 7: 4a's reference, CLAUDE.md and the pull request

**Files:**
- Modify: `docs/reference/cs-studio-shell-and-dashboard.md`:
  - the dashboard paragraph is rewritten: the panels and their kinds, Waiting for you and its frame and filter, the tiles, the two buttons, the rail and its threshold;
  - "Notes on the dashboard and in the sidebar": `#dashboard-waiting` replaces `#notes-open-threads`, and `reload` keeps a navigated `src`;
  - its "Rules a change can break silently": the merged panel's two sources at `limit` each.
- Modify: `docs/reference/notes.md` ("The inbox": five answers, the frame the inbox reloads), `docs/reference/publishing.md` (`review=publish` beside the dialogs' rule), `docs/reference/design-system.md` (a part "E4: the dashboard": panel kinds, the scheduled date as a status component, the rail without cards)
- Modify: `CLAUDE.md`: the shell index line (`app/queries/dashboard/` gains `waiting_for_you.rb`; `Admin::DashboardScreen` named), and the publishing line (`review=publish`)
- Test: `PGGSSENCMODE=disable bin/rails test test/lib`, `bin/rubocop`, `bin/rails zeitwerk:check`, `bin/brakeman`, `bin/changelog-guard`

- [ ] **Step 1: Write the reference and CLAUDE.md changes.** Add a `CHANGELOG.md` `## Unreleased` entry under "Changed" (the dashboard), and under "Removed" (the quick-create row; `POST dashboard/draft`; `GET notes/open_threads`).
- [ ] **Step 2: Run** the five checks. Expected: all pass.
- [ ] **Step 3: Write the PR body.**
  - Base: `studio-e4-3b`, or `main` once #191 has merged.
  - Findings: Advances #140 (the two call sites in the files it changed), Advances #117.
  - "For the owner to check" lists every **(owner)** of Tasks 2, 3, 5 and 6.
  - It names the Documentation below.
- [ ] **Step 4: Check no test run is left**: `pgrep -f "rails test"` prints nothing.
- [ ] **Step 5: Commit** `docs: E4 stage 4a in the reference and CLAUDE.md` (body: `Advances #117`)

**Documentation (4a), in `/Users/dknafelj/src/contentspiel-docs`:**
- pages:
  - `docs/editors/getting-started/signing-in-and-finding-your-way.md` (the dashboard: its panels, the rail);
  - `docs/editors/index.md`;
  - `docs/editors/posts/the-life-of-a-page-or-post.md` and `publish-schedule-and-preview.md` (Waiting for you, Review and publish…, Publishing on its own);
  - `docs/editors/working-together/notes-on-content.md` (Notes for you, open threads in Waiting for you);
  - `docs/editors/translating/keep-translations-up-to-date.md` (Languages behind …);
  - `docs/editors/pages/create-and-organise-pages.md` (New page… on the dashboard).
- screenshots: `dashboard.png` (retaken, wide with the rail); `dashboard-quick-create.png` (deleted, and its recipe in `screenshots/recipes.rb`); `dashboard-narrow.png` (new).

---

# PR 4b: the shell

### Task 8: CS Studio's z-index values are one token scale, with a guard

**Files:**
- Modify: `app/assets/tailwind/content-spiel.css`: the scale, written once in the `:root` block beside the layout tokens, with "THE LAYERS" as its comment (moved from `content-spiel.tailwind.css`).
- Modify: `app/assets/tailwind/content-spiel.tailwind.css`:
  - the tree divider, scrim, sidebar and tree drawers, the notes slide-over and sheet use `var(--cs-z-…)`;
  - `.admin-rail__main { isolation: isolate; }` with its reason;
  - the old "THE LAYERS" paragraph becomes one line pointing at the scale.
- Modify: `app/assets/tailwind/admin-rich-text.css` (the table strip's entries and its button)
- Modify the utilities, from `z-<n>` to `z-(--cs-z-<name>)`:
  - `app/components/admin/ui/{chip_input_component.html.erb,save_bar_component.rb,toast_region_component.html.erb,menu_component.rb,tooltip_component.rb}`;
  - `editor_screen/header_component.html.erb`, `shell/top_bar_component.html.erb`, `notes_screen/composer_component.{rb,html.erb}`, `users_screen/list_component.html.erb`, `audit_screen/sentence_component.rb`;
  - `translation_screen/matrix_component.{rb,html.erb}`, `app/views/admin/mind_graph/show.html.erb`, `app/views/admin/media/index.html.erb` and `app/javascript/rich_text/popover.js`.
- Test: `test/lib/admin_design_rules_test.rb`, `test/system/admin/notes_rail_test.rb` 

**Interfaces:**
- Produces: the scale. The first three rows are the local layers, which mean something only inside a stacking context their component makes. The rest are the page layers, lowest first and strictly increasing.

  | Token | Value | Was | Who |
  |---|---|---|---|
  | `--cs-z-lift` | 1 | 1 | a focused control over its neighbours (the table strip's button) |
  | `--cs-z-raised` | 10 | 10 | over its own row or cell: a row's links over its stretched link (audit sentence, users list), a matrix cell's link, a table strip entry and its "+", the mind graph's card and tooltip |
  | `--cs-z-raised-top` | 20 | 20 | over `raised` in the same context: the matrix's sticky title cell, an open or focused strip entry |
  | `--cs-z-sticky` | 15 | 20 | the save bar (configuration screens, where no slide-over is) |
  | `--cs-z-slide-over` | 20 | 20 | the notes slide-over |
  | `--cs-z-header` | 21 | 21 | the editor's sticky header, whose menus stay inside it |
  | `--cs-z-sheet` | 22 | 22 | the notes sheet under 640px |
  | `--cs-z-divider` | 23 | 23 | the tree's divider |
  | `--cs-z-top-bar` | 25 | 25 | the top bar below 1280px |
  | `--cs-z-popover` | 30 | 30 (the rich-text popover 20, the mind graph's results 20) | a menu, tooltip, listbox, emoji panel, the rich-text popover, the mind graph's search results |
  | `--cs-z-drop` | 32 | 30 | the media library's whole-window drop overlay |
  | `--cs-z-scrim` | 35 | 30 | the shell's scrim, over any open popover |
  | `--cs-z-drawer` | 40 | 40 | the sidebar and tree drawers |
  | `--cs-z-toast` | 50 | 50 | the toast region |

  Dialogs open with `showModal()` in the top layer and take no z-index. The public preview bar (`components/public`, z-50) is the public site's and is outside the scan, as it is for every E4 guard.

  `z-index: auto` (the docked notes) is no layer, and stays allowed. `--cs-z-sticky` is lower than its old value: nothing at 15 to 20 meets it, since the matrix's cells are inside their own `isolate` and the slide-over is never on a screen with a save bar.

- [ ] **Step 1: Write the failing tests** in `admin_design_rules_test.rb`:
  - `RAW_Z_UTILITY = /(?<![\w-])-?z-(?:\d+|\[[^\]]*\]|auto)(?![\w-])/` and `Z_TOKEN_UTILITY = /(?<![\w-])z-\(--cs-z-([a-z-]+)\)/`.
  - `test "no z-index is a raw value outside the scale, in a stylesheet or a class"`:
    - `elevation_offences(RAW_Z_UTILITY)` is empty;
    - in `content-spiel.tailwind.css` and `admin-rich-text.css` (comments stripped) every `z-index:` is `var(--cs-z-<name>)` or `auto`;
    - in `content-spiel.css` a numeric `z-index` appears nowhere, and each `--cs-z-*` is defined once.
  - `test "every z token used is one the scale defines"`. Collect every name from `Z_TOKEN_UTILITY` and `var(--cs-z-…)`, and assert each is defined.
  - `test "the page layers stand in THE LAYERS' order"`. Read the values of `sticky slide-over header sheet divider top-bar popover drop scrim drawer toast` and assert they are strictly increasing.
  - `test "the z patterns match a raw value and not a token or a word"`. Matches: `z-30`, `-z-10`, `z-[60]`, `md:z-20`, `z-auto`. Non-matches: `z-(--cs-z-popover)`, `size-10`, `fuzz-1`, `"Zoom"`.
  - `test "the canvas is its own stacking context"`. `.admin-rail__main` declares `isolation: isolate`.
  - Browser test, in the slide-over's file: `test "the slide-over covers a rich-text popover and an open table strip in the canvas"`. At 1100px, open a rich-text link popover in a block at the right edge and a table's column menu, then open the notes. Assert that `document.elementFromPoint` at a point inside both the popover's box and the slide-over's box answers an element inside `#notes-drawer`.
- [ ] **Step 2: Run them, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/lib/admin_design_rules_test.rb`. Expected: the raw-value test lists the files above.
- [ ] **Step 3: Implement.** In Ruby and ERB, a class string writes `z-(--cs-z-popover)` (Tailwind v4's custom-property shorthand, the form `top-(--admin-top-offset)` already uses). Check that `bin/rails tailwindcss:build` emits each one (`grep -c "z-index: var(--cs-z-" app/assets/builds/tailwind.css`). The scale's comment in `content-spiel.css` says three things: the local layers' meaning, why the page layers have their order, and that the canvas's isolation is what keeps its popovers under the slide-over and the header.
- [ ] **Step 4: Run them, and verify they pass.** Run `bin/rails tailwindcss:build`, then `test/lib`. Locally, one at a time: `notes_rail_test`, `shell_test`, `tree_column_test`, `editor_header_test`, `rich_text_test`, `table_block_test`, `chip_input_test`, `toast_test`, `dialog_test`, `media_library_test` and `translations_test`. Expected: PASS.
- [ ] **Step 5: Commit** `ref: CS Studio's z-index values are one token scale, and the canvas is its own stacking context` (body: `Advances #117`)

---

### Task 9: The theme switch fades

**Files:**
- Modify: `app/javascript/controllers/theme_controller.js`
- Modify: `app/assets/tailwind/content-spiel.css` (the tokens and the two `::view-transition-*` rules)
- Test: `test/system/theme_toggle_test.rb`, `test/lib/admin_design_rules_test.rb`

**Interfaces:**
- Produces:
  - In `content-spiel.css`, `--cs-theme-fade-duration: 250ms;` and `--cs-theme-fade-easing: ease-out;`, written once. The rule `html[data-surface="studio"]::view-transition-old(root), html[data-surface="studio"]::view-transition-new(root) { animation-duration: var(--cs-theme-fade-duration); animation-timing-function: var(--cs-theme-fade-easing); }` sets only the duration and the easing, so the browser's own fade-out and fade-in keyframes are kept.
  - `theme_controller.js`:
    - `apply(choice)` sets `data-theme-choice` and runs `sync()` first, so `aria-checked` changes at once and the pressed button keeps the focus. Only then does it change `data-theme`: through `document.startViewTransition(() => …)` when the API exists and `matchMedia("(prefers-reduced-motion: reduce)")` does not match, and directly otherwise.
    - A `startViewTransition` that throws falls back to the direct change.
    - `choose`, `toggle` and the OS change while Auto all go through `apply`. `connect` does not, and neither does `shared/_theme_head`, so the first paint never fades.
    - The header comment says this, and that the public toggle gets the browser's default cross-fade, since the theme build carries no such rule.

- [ ] **Step 1: Write the failing tests** in `theme_toggle_test.rb`. A spy is put in place before the press: `window.__vt = []; document.startViewTransition = (cb) => { window.__vt.push(document.documentElement.dataset.theme); cb(); return { finished: Promise.resolve(), ready: Promise.resolve(), updateCallbackDone: Promise.resolve() } }`.
  - `test "pressing Dark changes the theme through one view transition, with aria-checked set before it"`. Assert `__vt.length == 1`, that the theme seen inside was still the old one, `html[data-theme=dark]`, and that `aria-checked` is true on Dark.
  - `test "under reduced motion the theme changes with no transition"`. Use `Emulation.setEmulatedMedia` with `prefers-reduced-motion: reduce` (as `editing_live_test` does), and reset it in `ensure`.
  - `test "two presses inside the fade end on the second choice"`. The spy defers `cb` with `setTimeout(cb, 100)`; press Dark then Light, and assert light and Light checked.
  - `test "a transition that throws still changes the theme"`. The spy throws `new DOMException("hidden", "InvalidStateError")`.
  - `test "the first paint never fades"`. Put the spy in with `page.driver.browser.evaluate_on_new_document`, then visit, and assert `__vt` is empty.
  - `test "the public toggle fades too"`. Assert the spy is called on the footer's toggle.
  - Token test: `--cs-theme-fade-duration` and `-easing` are defined once, and the `::view-transition-old(root)` and `-new(root)` rules read them and set no `animation` shorthand.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** No test waits on the animation: the spy calls back at once, and nothing reads a frame in the middle of the fade.
- [ ] **Step 4: Run them, and verify they pass.** Locally run `theme_toggle_test` and `theme_script_test`. Run `test/lib` too. Expected: PASS.
- [ ] **Step 5: Commit** `feat: switching between light and dark cross-fades, except under reduced motion` (body: `Advances #117`)

---

### Task 10: Every sidebar module has a colour family

**Files:**
- Modify: `app/models/studio_modules.rb` (`FAMILIES` without `:neutral`; `register(..., family:)` required)
- Modify: `config/initializers/studio_modules.rb` (every module names its family)
- Modify: `app/components/admin/shell/sidebar_component.rb` (`chip_family(entry) = entry[:family]`; the current row keeps the accent-tint ground and accent words, and its chip keeps its family)
- Test: `test/models/studio_modules_test.rb`, `test/components/admin/shell/sidebar_component_test.rb`, `test/lib/admin_contrast_test.rb`

**Interfaces:**
- Produces:
  - `StudioModules::FAMILIES = %i[text media code form lists structure people].freeze`.
  - `StudioModules.register(name, icon:, family:, path:, permission:, group:, visible: nil)`. A missing family raises Ruby's own `ArgumentError` (missing keyword). `:neutral`, `:accent` or an unknown family raises with the message "#{name}: no sidebar family is named …; a module's chip takes one of text, media, code, form, lists, structure, people (accent is the current module's)".
  - The families:

    | Family | Modules |
    |---|---|
    | structure | Dashboard, Pages, Mind graph |
    | lists | Posts, Tags |
    | media | Media |
    | form | Forms |
    | text | Translations |
    | people | Users, Groups |
    | code | Trash, Settings, AI assistant, System status, Audit log |

- [ ] **Step 1: Write the failing tests.**
  - `studio_modules_test.rb`:
    - `test "a module must declare its family, and neutral and accent are refused"`;
    - `test "every built-in module has the spec's family"`, with the table above as a Hash.
    - The registry's other tests pass a family.
  - `sidebar_component_test.rb`:
    - "each module's icon is on its family's chip…" becomes `test "no module's chip is neutral, and each is its family's"`;
    - "the current module's chip is the accent tint…" becomes `test "the current module keeps its chip's family on the accent-tint row with accent words"`.
  - `admin_contrast_test.rb`: `test "every sidebar module's icon is 3:1 on its chip, on the sidebar and on the current row, in both schemes"`. It iterates `StudioModules.entries.map(&:family).uniq` and measures `--cs-ic-<family>` on `--cs-ic-<family>-bg`, `--cs-chrome` and `--cs-accent-tint`. It also asserts that no entry's family is `:neutral`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** The model's comment says why a family is required: a gem's module would otherwise be the one grey chip in a coloured sidebar. `docs/reference/content-blocks-and-types.md` keeps "a block type naming none is neutral": that rule is the block types', not the sidebar's.
- [ ] **Step 4: Run them, and verify they pass.** Run `test/models/studio_modules_test.rb test/components/admin/shell test/lib`, and locally `shell_test` and `command_palette_test` (⌘K reads `family`). Expected: PASS.
- [ ] **Step 5: Commit** `feat: every sidebar module has a colour family, and a module must name one` (body: `Advances #127`, `Advances #117`)

---

### Task 11: 4b's reference, CLAUDE.md and the pull request

**Files:**
- Modify: `docs/reference/design-system.md`:
  - "E4: the dashboard" gains the shell's three changes: the scale, the fade, the families;
  - "Rules a change can break silently": the local layers mean something only inside their component's stacking context, with **no guard** that a `--cs-z-raised*` user makes one.
- Modify: `docs/reference/cs-studio-shell-and-dashboard.md` (the sidebar's families and the required `family:`), `docs/reference/theming.md` (one line: the footer toggle cross-fades by the browser's default; a theme may style `::view-transition-*(root)` in its own stylesheet)
- Modify: `CLAUDE.md`, the design-system index line (`--cs-z-*`, written once in `content-spiel.css`, guarded in `admin_design_rules_test.rb`) and the "Rules a change can break silently" bullet for the local layers
- Test: `PGGSSENCMODE=disable bin/rails test test/lib`, `bin/rubocop`, `bin/rails zeitwerk:check`, `bin/changelog-guard`

- [ ] **Step 1: Write the reference and CLAUDE.md changes.** Add a `CHANGELOG.md` entry under "Changed" for the theme fade and the families. Add one under "Changed" for gem authors too: "`StudioModules.register` requires `family:`".
- [ ] **Step 2: Run** the four checks. Expected: all pass.
- [ ] **Step 3: Write the PR body.**
  - Base: `studio-e4-4`, or `main` once 4a has merged.
  - Findings: Advances #127 (the module entry requires its family), Advances #117.
  - For the owner to check: the fade's 250ms ease-out, the families of System's modules (code), and the scrim now above an open menu.
- [ ] **Step 4: Check no test run is left**: `pgrep -f "rails test"` prints nothing.
- [ ] **Step 5: Commit** `docs: E4 stage 4b in the reference and CLAUDE.md` (body: `Advances #117`)

**Documentation (4b), in `contentspiel-docs`:**
- pages:
  - `docs/editors/getting-started/signing-in-and-finding-your-way.md` (the sidebar's colours; the theme switch);
  - `docs/integrators/theming/the-theme-contract.md` (the footer toggle's cross-fade, if the contract page names the toggle).
- screenshots: every one that shows the sidebar is retaken (the chips' colours), in the same pass as 4a's.

---

## Architecture-review findings

Checked on 2026-11-06 against every open issue labelled `architecture-review`.

| Issue | Taken | Why |
|---|---|---|
| #117 comments about invariants | advances, every task | each task rewrites the comments of the files it changes, and the dashboard's are among the densest in "Task 16", "design pass round 2" and "spec §" |
| #140 one name for a person's short name | advances (Task 3): `inbox_row_component.rb` and `note_inbox_controller.rb` call `PersonName.of` | Task 3 changes both files, and the rule takes a finding's part in changed code. The alias, its other call sites and the `display_name` rename stay with stage 6, which closes it |
| #127 slots fit one shape | advances (Task 10): the module entry requires its family | Task 10 changes the module entry that #127 asked for. The list column and the save-answer contributions remain |
| #133 entry helpers, large system files | not taken | the helpers exist (`visit_screen`, `visit_editor`), the new tests use them, and the dashboard's system files are 125 to 605 lines |
| #124 admin scripts on demand | not taken | deleting two dashboard controllers changes neither `controllers/index.js` nor the pins |
| #142 a new site's one language | not taken | it would change what "Languages behind …" shows, which is a product decision the spec leaves out of E4 |
| #132, #112, #114 to #116, #119 to #122, #128 to #131, #135 to #138, #141, #143, #185 | not taken | no task changes their code |

## Browser tests

Run locally after `bin/rails tailwindcss:build`, one file at a time, only while the one-minute load is under 6, each prefixed with `PGGSSENCMODE=disable`.

**The implementer must run:**
- 4a:
  - `dashboard_test`, `note_inbox_test`, `unpublished_changes_test` and `drafts_test`;
  - `presence_lists_test`, `new_record_test` and `publish_dialog_steady_test`.
- 4b:
  - `theme_toggle_test`, `theme_script_test`, `shell_test` and `command_palette_test`;
  - `notes_rail_test` (the slide-over over the canvas), `tree_column_test` and `editor_header_test`;
  - `rich_text_test`, `table_block_test`, `chip_input_test`, `toast_test` and `dialog_test`;
  - `media_library_test` and `translations_test`.

**Likely to change, left to CI** (the whole browser suite runs per PR):
- `notes_live_test` and `notes_flow_test` (the inbox's reload);
- `view_only_test` (the dashboard for a reader);
- `system_status_and_preview_test`;
- `mind_graph_test` (the search results' layer);
- `audit_log_test` and `users_test` (a row's raised links).

A CI failure is fixed in the task that owns the file.
