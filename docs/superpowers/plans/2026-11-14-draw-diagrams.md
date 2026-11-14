# Draw diagrams Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A CS Studio screen, "Draw diagrams", that lists every Diagram block whose drawing is not of its current source and draws them all in the admin's browser, saving each as the card does.

**Architecture:** A query (`Diagrams::ToDraw`) lists the rows; a JSON action (`Admin::DiagramDrawingsController#update`) saves one drawing through `ContentBlocks::Save` after the scope, stale, hold and digest checks; one Stimulus controller opens ONE renderer frame (`diagram/frame`) and walks the rows, each save sent through `saving/queue.js`. System status gets a "Content" card with one row, ⌘K an action.

**Tech Stack:** Rails 8.1, ViewComponent, Stimulus (import maps), Minitest, Cuprite.

**Spec:** `docs/superpowers/specs/2026-11-14-draw-diagrams-design.md`. **Design:** Design System v228 (`https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT`, index `1794675793-e7dd`), card **StudioDrawDiagrams**: its README holds every word, the states table and the markup. Read it with the Artifact tool (`action: "read"`, `path` the card's files under `project/components/StudioDrawDiagrams/`). Where the card and this plan differ on a word, the card wins; on behaviour, the spec wins.

## Global Constraints

- Read `CLAUDE.md`; before a test, `docs/reference/writing-tests.md`, and `test/system/README.md` before a browser test. Browser tests run one file at a time, on a quiet machine (load under 6, no other `bin/rails test`).
- Prefix test commands with `PGGSSENCMODE=disable`. A new worktree: `bin/rails db:test:prepare`, `bin/rails tailwindcss:build` and `bin/rails theme_css:build` once, never while tests run.
- Components go under `Admin::DiagramDrawingsScreen::` — never `Admin::Diagrams` (shadows `Diagrams`; `test/lib/admin_namespace_shadow_test.rb`).
- Every admin string is a key: `admin.diagram_drawings.index.*`, `admin.components.diagram_drawings_screen.<component>.*` (one file, `config/locales/admin/diagram_drawings_screen.en.yml`, plus `config/locales/admin/diagram_drawings.en.yml` for the view), `admin.system_status.show.content.*`. Script words via `data-messages`.
- Every write goes through `app/javascript/saving/queue.js` (`enqueue`), with the tab header (`TAB_HEADER` from `editing/requests.js`).
- No new permission: seeing the screen needs `pages.edit`; each row's save is `ContentBlocks::Save`'s own check.
- The task never writes a published copy and never publishes.
- Comments state invariants, never history. No compatibility code.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT`; commit by explicit path.

## Review Focus

1. A language with no source of its own (falls back to the default's): not listed — Task 1 test `test_a_language_that_falls_back_is_not_listed`.
2. A live page the viewer may edit but not publish: not listed, not counted — Task 1 test `test_a_published_page_needs_publish`.
3. The source changes between the list and the save: refused `changed`, nothing written — Task 2 test `test_a_from_that_is_not_the_stored_source_is_refused`.
4. A diagram inside a section's column, and one on a page in a trashed branch: the first listed, the second not — Task 1 tests `test_a_diagram_in_a_section_is_listed`, `test_a_trashed_branch_is_not_listed`.
5. Leaving the page mid-run: the frame is taken back and nothing more is sent — Task 5 browser test `test_leaving_mid_run_sends_nothing_more`.

---

### Task 1: `Diagrams::ToDraw`

**Files:**
- Create: `app/queries/diagrams/to_draw.rb`
- Test: `test/queries/diagrams/to_draw_test.rb`
- Modify: `test/integration/trash_visibility_test.rb` (join it)

**Interfaces:**
- Produces: `Diagrams::ToDraw.new(actor:).rows -> Array<Row>`, `#count -> Integer`, `#pages -> Array<[Page, Array<Row>]>` in tree order. `Row = Data.define(:block, :page, :locale, :state, :source)`, `state` `:not_drawn` or `:kept`, `locale` a String code, `source` the stored (cast) source.

- [ ] **Step 1: Write the failing tests.** Build pages and Diagram blocks through `ContentBlocks::Save` (as `test/models/block_types/diagram_test.rb` does) with sources from `DiagramFixtures`/`BlockTypes::Diagram::SAMPLE_SOURCES` and drawings `{ "svg" => <a fixture>, "from" => Diagrams::Drawing.digest(source) }`. Tests:
  - `test_a_diagram_with_no_drawing_is_not_drawn` → one row, `state == :not_drawn`.
  - `test_a_drawing_of_another_source_is_kept` → `:kept`.
  - `test_a_current_drawing_is_not_listed` → no row.
  - `test_each_language_with_its_own_source_is_a_row` (en and de sources, en drawn) → one row, locale `"de"`.
  - `test_a_language_that_falls_back_is_not_listed` (en source only, de switched on) → only en's row.
  - `test_a_language_switched_off_is_not_listed`.
  - `test_a_diagram_in_a_section_is_listed`.
  - `test_a_trashed_branch_is_not_listed` (`Trash::Move` the parent).
  - `test_a_page_outside_the_scope_is_not_listed` (a group whose grant scope excludes the page).
  - `test_a_published_page_needs_publish` (viewer with `pages.edit` only: draft page listed, published page not; `count` agrees).
  - `test_rows_follow_the_tree_then_the_position_then_the_languages`.
- [ ] **Step 2:** `PGGSSENCMODE=disable bin/rails test test/queries/diagrams/to_draw_test.rb` → fails (uninitialized constant).
- [ ] **Step 3: Implement.** Scope through `AccessControl.scope`, hide trashed pages itself (no default scope), filter blocks by the Diagram type's key. A language counts when `translated_settings[code]["source"]` is present among `Locales` switched on; the row's state from `Diagrams::Drawing.new(drawing).current?(source)` (an unusable drawing, as `BlockTypes::Diagram::Shown` reads it, is `:not_drawn`). "May save" is `ContentBlocks::OwnerPermissions`' rule asked of the actor without writing: `pages.edit`, plus `pages.publish` when `Publishing::State` of the page is not a draft — reuse the module's predicate, extracting one if it has only the refusal form. Order by `TreeOrder`, position, Settings' language order. A line on the class says what it answers.
- [ ] **Step 4:** run the file → PASS; add the query to `test/integration/trash_visibility_test.rb` the way its other lists are, run that file → PASS.
- [ ] **Step 5: Commit** `feat: Diagrams::ToDraw lists the diagrams with no drawing of their source`.

### Task 2: Saving one drawing

**Files:**
- Create: `app/controllers/admin/diagram_drawings_controller.rb` (`update` only here)
- Modify: `config/routes.rb` (admin scope, beside `diagram-renderer`: `resources :diagram_drawings, path: "diagram-drawings", only: %i[index update]`; `index` lands in Task 3)
- Test: `test/controllers/admin/diagram_drawings_controller_test.rb`

**Interfaces:**
- Consumes: `Diagrams::ToDraw::Row` (not needed by the action itself).
- Produces: `PATCH admin_diagram_drawing_path(block)` with `locale`, `svg`, `from`, `base_updated_at`; answers JSON `{ ok: true, live: <Boolean>, page_id:, page_title:, review_url: }` (200) or `{ ok: false, reason: <String>, holder: <String or nil> }` with the status below. Reasons: `gone` (404: not found in scope, or not a Diagram block), `denied` (403: the service refused), `stale` (409: base), `held` (409: `held_elsewhere?`; `holder` the person's name via `PersonName`), `changed` (409: `from` ≠ digest of the stored source for `locale`, or no source there), `too_large` and `invalid_drawing` (422: the save's error on `drawing`, by its error key).

- [ ] **Step 1: Write the failing tests**, one per outcome: `test_a_drawing_is_saved_and_audited` (stored `{svg (cleaned), from}`, one `content_block.updated` audit event, answer `ok`, `live` false on a draft), `test_a_live_page_answers_live_with_its_review_url` (`review_url` ends `?review=publish`), `test_a_block_outside_the_scope_is_gone`, `test_a_block_that_is_not_a_diagram_is_gone`, `test_a_stale_base_is_refused`, `test_a_block_held_in_another_tab_is_refused_with_the_holder` (a `Editing::Reservation` for another user; request with the tab header), `test_a_from_that_is_not_the_stored_source_is_refused`, `test_a_drawing_that_does_not_clean_is_refused` (an `<svg><script/></svg>`-style refusal), `test_a_drawing_over_the_limit_is_refused`, `test_no_publish_right_on_a_live_page_is_denied`, `test_nothing_is_published` (published copy unchanged).
- [ ] **Step 2:** run → fails (no route).
- [ ] **Step 3: Implement** on `Admin::BaseController`, `require_permission("pages.edit")`, including `Admin::EditingClaims` (`held_elsewhere?`: no claim taken, so nothing to give back) and the stale check of `Admin::AutosaveResponses`/`Admin::StaleForm` against the block's `updated_at`. Save: `ContentBlocks::Save.call(block, translations: { locale => { settings: { drawing: { svg:, from: } } } })` — check the exact shape the block form sends for a translated settings field (`split_block_params` in `ContentBlocksController`) and use that one. The `live` flag and `review_url` from `Publishing::State` and the editor's path with `review: "publish"`. The JSON is the screen's own; keep the decisions in the action, as `Admin::Answers` responders draw only.
- [ ] **Step 4:** run → PASS; `bin/brakeman` exits 0.
- [ ] **Step 5: Commit** `feat: save one diagram's drawing from the Draw diagrams task`.

### Task 3: The screen

**Files:**
- Modify: `app/controllers/admin/diagram_drawings_controller.rb` (`index`)
- Create: `app/views/admin/diagram_drawings/index.html.erb`; `app/components/admin/diagram_drawings_screen/{page_group,row,run_head,publish_card}_component.{rb,html.erb}`; `config/locales/admin/diagram_drawings.en.yml`, `config/locales/admin/diagram_drawings_screen.en.yml`
- Modify: `test/lib/component_screens_test.rb` (`SCREENS`), `test/lib/admin_i18n_test.rb` (`CONVERTED`), `test/support/design_system_entries.rb` (add `StudioDrawDiagrams` to `ENTRIES`, `VERSION = "1794675793-e7dd"`)
- Test: `test/components/admin/diagram_drawings_screen/*_test.rb`, the controller test gains `index` tests

**Interfaces:**
- Consumes: `Diagrams::ToDraw#pages`, the `update` route.
- Produces for Task 5: the list's root carries `data-controller="admin--diagram--draw-all"` with values `renderer-url`, `colours` (the same list `MermaidField` passes) and `data-messages`; a colour probe target as `MermaidField` draws it; each row `data-draw-row` with `data-admin--diagram--draw-all-target="row"` and data `url` (the update path), `locale`, `base` (`updated_at` as the block form writes it), `source` (as a `<template>` or `<script type="text/plain">` child, never an attribute the page could run); the `RunHeadComponent` targets `start`, `stop`, `progress`, `status` (polite live region); `PublishCardComponent` a `<template>` target `publishRow` and its list target `publishList`; the HTTPS notice target `insecure` (hidden by default).

- [ ] **Step 1: Write the failing tests:** component tests for each state the card names (Row: not drawn, kept, description present, description absent shows the first source line in mono, language column only with more than one language); `index` tests: `test_the_list_is_grouped_by_page`, `test_the_empty_state_has_no_button`, `test_a_viewer_without_pages_edit_is_refused`.
- [ ] **Step 2:** run → fails.
- [ ] **Step 3: Implement** to the card's markup and words, with existing components (`ListStateComponent`, `StateChipComponent`, `NoticeComponent`, `.admin-row-link` with the row's link to the editor at the block's anchor). No sidebar entry. "Draw all" is the area's one primary.
- [ ] **Step 4:** run the new tests and `test/lib/component_screens_test.rb test/lib/admin_i18n_test.rb test/lib/component_parts_test.rb test/lib/source_layout_test.rb test/lib/admin_namespace_shadow_test.rb` → PASS; `bin/rails zeitwerk:check`.
- [ ] **Step 5: Commit** `feat: the Draw diagrams screen (Design System v228)`.

### Task 4: System status's Content card and ⌘K

**Files:**
- Modify: `app/controllers/admin/system_status_controller.rb`, `app/views/admin/system_status/show.html.erb`, `config/locales/admin/system_status.en.yml` (or the file its keys live in), `app/queries/jump/search.rb`
- Test: `test/controllers/admin/system_status_controller_test.rb`, `test/queries/jump/search_test.rb`

**Interfaces:**
- Consumes: `Diagrams::ToDraw.new(actor:).count`.

- [ ] **Step 1: Write the failing tests:** `test_the_content_card_counts_the_diagrams_to_draw` (warning sentence with the count and "Draw diagrams →" to `admin_diagram_drawings_path`), `test_the_content_card_says_every_diagram_is_drawn`, `test_the_content_card_is_not_shown_without_pages_edit`, `test_the_content_row_is_not_a_check` (the "n of m checks passed" line unchanged, `Setup::SystemCheck.run` untouched); jump: `test_draw_diagrams_is_offered_while_there_is_something_to_draw`, `test_draw_diagrams_is_not_offered_when_nothing_is_to_draw`, `test_draw_diagrams_needs_pages_edit`.
- [ ] **Step 2:** run → fails.
- [ ] **Step 3: Implement.** The row with `Admin::Ui::SystemCheckRowComponent` as the card says; the count asked only when the viewer holds `pages.edit`. ⌘K: an action row "Draw diagrams" whose condition is the permission AND a non-zero count — add a `when:`-style callable to that one entry rather than a second list.
- [ ] **Step 4:** run → PASS.
- [ ] **Step 5: Commit** `feat: System status and ⌘K reach Draw diagrams`.

### Task 5: The run in the browser

**Files:**
- Create: `app/javascript/controllers/admin/diagram/draw_all_controller.js`
- Test: `test/system/admin/draw_diagrams_test.rb`

**Interfaces:**
- Consumes: Task 3's targets and values; `openFrame` (`diagram/frame`), `digest` (`diagram/digest`), `enqueue` (`saving/queue`), `TAB_HEADER`/`headers()` (`editing/requests`), `messages` (`i18n/messages`); Task 2's JSON.

- [ ] **Step 1: Write the failing browser tests** (begin on `visit_screen`): `test_draw_all_draws_and_saves_every_row` (two diagrams, both drawn; stored drawings current; end notice "2 drawn"), `test_a_source_that_does_not_draw_is_reported_and_the_run_goes_on`, `test_a_held_block_is_skipped_with_the_holder`, `test_a_live_page_is_offered_for_review_and_publish` (link to `?review=publish`; the published copy unchanged), `test_stop_ends_after_the_row_in_hand`, `test_leaving_mid_run_sends_nothing_more` (visit away during a run; no further PATCH arrives — count requests on the server side, as other browser tests do), `test_the_frame_is_taken_back_before_cache`.
- [ ] **Step 2:** run the file → fails.
- [ ] **Step 3: Implement.** One frame, built at `connect`, hidden (`aria-hidden`, out of view, not `display:none`, which would stop its fonts/measuring). At connect, without `crypto.subtle` show `insecure` and disable `start`. Run: for each remaining row in order — mark Drawing (`aria-busy`), `frame.draw(source, colours)`, await the answer; `error` → Doesn't draw with the frame's sentence; `svg` → `enqueue(async (isCurrent) => …)` a `fetch` PATCH (form params `locale`, `svg`, `from = await digest(source)`, `base_updated_at`, the CSRF token, `TAB_HEADER`), then the row's state from the JSON (`reasons` read from `data-messages`); the next row only after the save answered. `stop` sets a flag read between rows ("Stopping…"). The live region speaks at the start, at each refused or skipped row, and at the end. At the end: the summary notice, the live pages cloned from the `publishRow` template (one per page), "Draw all" back while rows remain. `disconnect` and `turbo:before-cache`: close the frame, cancel the run, take back every state and clone the script wrote.
- [ ] **Step 4:** run the file → PASS (one file, quiet machine).
- [ ] **Step 5: Commit** `feat: Draw all draws every listed diagram in one frame`.

### Task 6: Reference, CLAUDE.md, CHANGELOG

**Files:**
- Modify: `docs/reference/content-blocks-and-types.md` (the Diagram block's part: a subsection "Draw diagrams" — what is listed, the action's order of checks, one frame, no publish; and under "Rules a change can break silently" the line that the screen's draw is the card's draw: a change to the frame protocol or to `diagram/digest` reaches both), `CLAUDE.md` (the Diagram block's file list in the reference index gains `app/queries/diagrams/to_draw.rb`, `app/controllers/admin/diagram_drawings_controller.rb`, `app/components/admin/diagram_drawings_screen/`, `app/javascript/controllers/admin/diagram/draw_all_controller.js`), `CHANGELOG.md` (`## Unreleased`, `### Added`: the screen, System status's Content card, ⌘K)
- [ ] **Step 1:** write them; `bin/changelog-guard` and `PGGSSENCMODE=disable bin/rails test test/lib` → PASS.
- [ ] **Step 2: Commit** `docs: the Draw diagrams task in the reference`.
