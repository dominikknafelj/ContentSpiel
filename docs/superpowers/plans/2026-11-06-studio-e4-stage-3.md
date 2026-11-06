# CS Studio in E4, Stage 3 (the right rail) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** At wide widths the page and post editors put their settings in a 360px rail beside a 900px blocks column. The rail's tabs are Page · Section · Notes (Post · Notes for a post). Pressing a section's words chooses the section and shows its settings in the Section tab. A button folds the page tree away to make room, and the notes drawer becomes the rail's Notes tab: a 400px slide-over below the threshold, and a full-screen sheet under 640px. On the way, the tree reads in SQL and redraws one row on a settings save (#123, closes), the rail's tabs become an editor-panel slot (#127) and notes and live editing share one merge core (#132).

**Architecture:** The rail is a grid area, not a box. `.admin-rail-grid` is laid out by a container query on the editor area (`.admin-editor-area`, the live region). Its children are the tablist, the panels and the blocks column. The ground is the grid's own `::before`, so the post form can be `display: contents` and its settings panel inside it stays inside the form. Nothing is cloned. The page settings are rendered in the Page panel by the server. A section's settings region (`#section-<id>-settings`) is moved into the Section panel by `admin--editor--section-choice` and moved back on deselect, a fold of the rail and `turbo:before-cache`. Live editing's list merge learns about elements that a script moved out of the list (`away:`), so it merges them where they stand. The tree's fold is a third state with the same two writers as the tree's width.

**Tech Stack:** Rails 8.1, ViewComponent with Lookbook previews, Tailwind v4 (`tailwindcss-rails`), Stimulus over import maps, Turbo 8 streams (no morphing), Minitest with Capybara on Cuprite.

**Spec:** `docs/superpowers/specs/2026-11-06-studio-e4-design.md` (approved 2026-11-06). The sections this plan uses: "Decided on 2026-11-06" (2, 4, 8, 9, 10, 19), the screen table (page tree, page editor, post editor, notes drawer), "Stage 3" (3a and 3b), "Architecture-review findings", "The guard after E4" and "Constraints". Stage 2 as built (the base branch, `studio-e4-2`, PR #189): `docs/reference/design-system.md` ("E4: the editor's canvas"), `content-blocks-and-types.md` ("Sections in the editor") and `live-editing.md`. The drawings are the Design System artifact's `StudioCalmEditor` (option D: the rail, 1200px, 360/900), `StudioCalmColourE4E5` (the rail's ground, elevation 2) and `StudioCalmE4Together` (notes in the rail).

**Two pull requests, stacked.** The spec makes stage 3 two PRs, and this plan keeps that split:
- **PR 3a** is Tasks 1–8, on branch `studio-e4-3`, which targets `studio-e4-2` until #189 merges.
- **PR 3b** is Tasks 9–13, on `studio-e4-3b`, branched from `studio-e4-3` and targeting it until 3a merges.

Each PR leaves the full suite green on its own.

## Global Constraints

- **The public site keeps its look.** No file under `app/assets/tailwind/themes/`, `app/components/blocks/` or `app/views/layouts/public/` changes, and no `th-*` token either. A value that applies to CS Studio alone goes under `html[data-surface="studio"]` in `content-spiel.css`, written after every `:root` block that sets the same property. The rail's widths are layout tokens that only CS Studio reads, so they sit beside `--cs-form-max`.
- **One form, never two.** The page settings (`details#page-settings` with its form), a section's settings (`#section-<id>-settings` holding `#section-<id>-form`) and the post form (`form#post-form`) keep these when they stand in the rail:
  - their ids, `data-editing-unit`, `-subject`, `-version`, `-held`, `-strip-slot` and `-announcer` marks;
  - their `base_updated_at` field, their autosave controller and their save status.

  They are rendered or moved, never cloned. A test asserts each id exists exactly once at every width.
- **Every write goes through `app/javascript/saving/queue.js`.** No task adds a request. The fold and the tab choice are browser state (`localStorage`, attributes) and write no record.
- **The tree's width state has two writers.** `--admin-tree-width`, `data-tree-fits` (until Task 11 removes it) and the new `data-tree-folded` on `<html>` are written only by `app/views/admin/shared/_tree_head.html.erb` and `admin--shell--tree-width`. Task 2 adds a static guard for this.
- **Settings first in the document.** The order is header, then rail (tabs, settings), then blocks. The grid places them; no script reorders anything. The language tabs stay in the header (`EditorScreen::HeaderComponent`), above the grid.
- **Left-aligned.** The blocks column sits at the content's left edge and the rail 28px right of it. Spare width falls right of the rail. `mx-auto` stays refused (the 403 and 404 alone). The widths 900px, 360px and 28px are tokens written once in `content-spiel.css`. `.admin-form-column` stays on elements that exist. No new wrapper goes between a unit and `#content-blocks-list`.
- **A cascade test proves which rule wins.** Wherever a docked rule overrides a base rule (the 900px column over `.admin-form-column`'s 760px, the forced-open page settings over a folded `<details>`, the slide-over over the docked panel), a browser test measures the computed result at both widths. Reading the stylesheet is not enough.
- **Type voice.** A label is `text-label`, and a count (the Notes tab's number) is `text-count`. No `uppercase` with tracking, and no `font-mono` beyond `MONO_ALLOWED`.
- **Buttons come from `Admin::Ui::ButtonComponent`** ("Hide page tree", "Show page tree", a tab is not a button variant: it is drawn by `RailTabsComponent` and listed where the hand-built-button guard needs it, with its reason). **Icons come from `Admin::Ui::IconChipComponent`** or the shared icon partial.
- **Depth.** The rail is `--cs-rail` with `--cs-shadow-2` and `--cs-radius-rail`. The slide-over is elevation 3 (`--cs-popover`, `--cs-shadow-3`). Nothing gets a border for depth. A chosen section's frame takes a 2px `--cs-accent` outline: a selection, not a marker.
- **No admin string is a literal.** Every new tab, heading, button and aria label is a key. Editor strings go in `config/locales/admin/editor_screen.en.yml`, the fold button's in `shell.en.yml`, the tree head's in a new `config/locales/admin/pages_screen.en.yml` and notes' in `notes.en.yml`. A script's words come from `data-messages`. Every new component joins `admin_i18n_test`'s `CONVERTED`.
- **The slot boundary.** The rail names no feature. Notes reach the rail only through `editor.rail.tabs` (Task 10), and `test/lib/notes_boundary_test.rb` holds that.
- **No Turbo morphing**, no `turbo_refreshes_with`, no `broadcast_refresh`. Whatever a script moves or writes into the page is put back on `turbo:before-cache`.
- **Code asks `capability?(:container)` / `container?`**, never `block_type == "section"`.
- **Stimulus conventions.** An identifier follows its path, and no inline handlers (`inline_handlers_test`). After a rename or a move of a controller, search the tests by hand for the old name's fragments (`[data-controller*=…]`).
- **Comment rule (#117).** A comment states a current invariant, a hazard or a reason. It never states a plan step, a review round, "stage N" or what used to be there. Every task rewrites the comments of the files it changes by this rule, and that includes the long headers of `tree_width_controller.js`, `drawer_controller.js` and the two merge modules wherever their behaviour changes.
- **Tests and the machine.** On macOS every test command is prefixed with `PGGSSENCMODE=disable`. Browser tests run only after `bin/rails tailwindcss:build`, never during a build or beside a running `bin/dev`, and one file at a time on a quiet machine (`sysctl -n vm.loadavg` well under the core count). **No test run is left in the background** when a task ends: a task's last step checks `pgrep -f "rails test"` is empty.
- Commits follow conventional commits and end with:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT`
  A task that carries a finding says so in its body: "Closes #123", "Advances #127", "Advances #132", "Advances #117".
- **#139 is not in this stage.** The spec gives 3a the post form's "legacy comma-separated" tag string. #186 already removed it (`git log -S"legacy comma-separated"` → d96154b6). `split_tag_names` takes only an Array. Its per-element comma split guards what the chip input sends, so it is not compatibility code and stays. The PR says so.
- A look that the spec does not settle and that a person sees is marked **(owner)**. Each has a default that the build goes ahead on, and the PR lists them under "For the owner to check".

## Review Focus

1. **A colleague's save while a section's settings stand in the rail.** The list merge would draw a second `#section-<id>-settings` under the head beside the one in the rail. If the merge put the region back first, it would move a form under someone typing. Task 5 tests both directions. A clean region in the rail is replaced where it stands, and no copy appears under the head. A region holding unsaved text is the same element afterwards, with its focus and caret.
2. **The window crosses the threshold while the person types in the rail.** A narrowed window, a tree unfolded, or a notes column opened (3a only) undocks the rail. The region goes back under its head with its unsaved text, its queued save and its focus. Task 6: "a window narrowed while a section field in the rail has the focus puts the region under its head with the focus and the text, and the save lands on its base".
3. **A redraw brings a panel drawn in its default state.** A record merge replaces `form#post-form`, a slot tab's stream replaces a tab, and a removal stream takes away the chosen section's card. Each could leave two current panels, no current panel, or a form in the rail for a block that is gone. Task 3 makes the current tab the controller's state, re-applied as a panel or tab connects. Task 6 adds "removing the chosen section takes its settings out of the rail and says Choose a section". Task 7 adds "a post form replaced by a live merge keeps the tab that was current".
4. **The fold and the tree drawer.** A fold remembered on a wide window must not leave a strip, or hide the tree's drawer, on a window under 1024px, where the tree is a drawer and the fold means nothing. Task 2: "a folded tree is the ordinary drawer under 1024px, and folded again at 1600px".
5. **Keyboard and screen reader.** The tab order is header, tabs, settings, blocks. The tabs follow ARIA's tabs pattern (arrows, Home, End). Escape in the Section panel gives the focus back to the word that opened it. The slide-over closes on Escape only while the focus is inside it, and gives the focus back to its opener. Tasks 6 (the tabs' keys, the order, Escape in the Section panel) and 11 (the slide-over) carry the keyboard tests.

---

## The merge decision: teach merge about the rail

Stage 2 left the choice open: put `#section-<id>-settings` back under its head before every live merge, or teach `editing/merge.js` about the rail. **This plan teaches merge.** The reasons come from `editing/merge.js` itself:

- **Putting back is moving.** The module's rule is "A KEPT UNIT IS THE SAME ELEMENT AFTERWARDS, AND IS NOT MOVED. Moving an element takes it out of the document and puts it back: its Stimulus controllers disconnect and connect, the rich-text editor is mounted again and the caret is gone, under someone who is typing." To put the region back before a merge and into the rail after it, the unit would move twice for every list fetch.
- **Merges come from other people.** A list fetch follows any colleague's change to the page, so the moves would come at moments the typist does not choose. Choosing and deselecting a section are the person's own presses. The spec accepts a move only for those.
- **The merge already decides by id.** "DECIDE BY IDS, SUBJECTS AND STATE." The region has an id. The answer's copy of that id can be matched to the element where it stands, as the reconcile already matches ancestors level by level.

So `mergeList` takes `away`: the elements a script moved out of the list. Each one is merged where it is, and the answer's copy is taken out of the answer. The rail's own controller hears `admin--editing--live:merged` for an away element whose section is gone. Task 5 holds the rule, and Task 9 carries it into the shared core.

## Seams 3b takes from 3a

| Seam | Made in | Used by |
|---|---|---|
| `admin--ui--rail` with its `admin--ui--rail:reveal` / `:conceal` events (dispatched from inside a panel, bubbling) and its `admin--ui--rail:shown` event on the panel; `data-rail-docked` on the grid | Task 3 | the Notes tab (Task 11) opens and closes through those events, never by naming the rail's markup |
| `Admin::Ui::RailTabsComponent::Tab`, `Admin::Ui::RailPanelComponent` | Task 3 | the slot's tabs (Task 10) |
| `mergeList(list, fresh, { …, away })` | Task 5 | the merge core (Task 9) |

---

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `app/components/admin/pages_screen/tree_component.rb`, `tree_node_component.*`, `tree_row_component.*` (new), `app/controllers/admin/pages_controller.rb`, `test/support/statement_count.rb` (new) | the tree in SQL, one row redrawn (#123) | 1 |
| `app/javascript/controllers/admin/shell/tree_width_controller.js`, `app/components/admin/shell/tree_divider_component.rb`, `tree_fold_component.rb` (new), `app/views/layouts/admin.html.erb`, `app/views/admin/shared/_tree_head.html.erb`, `tree_component.html.erb`, `content-spiel.tailwind.css` | the tree's fold | 2 |
| `content-spiel.css`, `content-spiel.tailwind.css`, `app/components/admin/ui/rail_tabs_component.*`, `rail_panel_component.*` (new), `app/javascript/controllers/admin/ui/rail_controller.js` (new), `live_region_component.*` | the rail: tokens, grid, tabs | 3 |
| `app/javascript/controllers/admin/editor/section_settings_controller.js` (new), `section_controller.js`, `section_card_component.*` | the region carries its own behaviour | 4 |
| `app/javascript/editing/merge.js`, `controllers/admin/editing/live_controller.js` | merge knows away elements | 5 |
| `app/views/admin/pages/show.html.erb`, `page_settings_form_component.*`, `app/javascript/controllers/admin/editor/section_choice_controller.js` (new) | the page editor in the rail; choosing a section | 6 |
| `post_form_component.*`, `app/views/admin/posts/show.html.erb` | the post editor in the rail | 7 |
| `docs/reference/*.md`, `CLAUDE.md`, `test/system/README.md` | 3a's reference | 8 |
| `app/javascript/live/keep_merge.js` (new), `editing/merge.js`, `notes/merge.js`, both live controllers | one merge core (#132) | 9 |
| `app/components/admin/slots.rb`, `config/initializers/admin_slots.rb`, `rail_tabs_component.rb`, `app/controllers/admin/answers/rail_tab_streams.rb` (new) | the `editor.rail.tabs` slot (#127) | 10 |
| `notes_screen/drawer_component.*` → `notes_screen/rail_panel_component.*`, `controllers/admin/notes/drawer_controller.js`, `_notes_head.html.erb` (deleted), `tree_width_controller.js`, `_tree_head.html.erb`, `content-spiel.tailwind.css` | notes as the Notes tab | 11 |
| `notes_screen/thread_component.*`, `composer_component.*`, `list_component.*`, `test/lib/admin_contrast_test.rb` | notes' E4 look | 12 |
| `docs/reference/*.md`, `CLAUDE.md` | 3b's reference | 13 |

---

# PR 3a: the rail, in the page and post editors, and the tree's fold

### Task 1: The tree reads in SQL and a settings save redraws one row (#123)

**Files:**
- Modify: `app/components/admin/pages_screen/tree_component.rb` (`load_visible`)
- Create: `app/components/admin/pages_screen/tree_row_component.{rb,html.erb}` (the row's `<div>`, cut out of `tree_node_component.html.erb`)
- Modify: `app/components/admin/pages_screen/tree_node_component.{rb,html.erb}` (renders `TreeRowComponent`, then its children)
- Modify: `app/controllers/admin/pages_controller.rb` (`update`: `tree_row_stream` replaces `tree_replace_stream`; `tree_replace_stream` stays for the actions that change the tree's shape)
- Create: `test/support/statement_count.rb` (`count_statements { }`, moved from `tree_component_test.rb#count_queries`, which now calls it)
- Test: `test/components/admin/pages_screen/tree_component_test.rb`, `test/components/admin/pages_screen/tree_row_component_test.rb` (new), `test/integration/admin/pages_tree_row_test.rb` (new), `test/integration/trash_visibility_test.rb` (unchanged, must stay green)

**Interfaces:**
- Produces:
  - `TreeComponent::COLUMNS`: the frozen Array of the `pages` columns the tree's rows, `TreeStateMarkComponent`, `AccessControl.preload_branches` and the `tree.row.markers` loaders read. The list is checked by the tests: a column left out raises `ActiveModel::MissingAttributeError`.
  - `load_visible` reads `Page.kept.where(id: visible_ids).select(*COLUMNS)`.
  - `Admin::PagesScreen::TreeRowComponent.new(page:, child_count:, translation_counts:, loaded:, selected:, locale:, url_options:, context_only: false)` draws `div#tree-row-<page.id>`, which is the row's `<div>` as it is today, carrying `TreeNodeComponent#row_class`'s classes.
  - `TreeRowComponent.for_page(page, selected:, locale:, url_options:)` reads the one page's child count, translation counts, branch and slot data in a fixed number of statements.
  - `Admin::PagesController#tree_row_stream` returns `turbo_stream.replace("tree-row-#{@page.id}", TreeRowComponent.for_page(@page, selected: @page, …))`.

- [ ] **Step 1: Write the failing tests.**
  - In `tree_component_test.rb`:
    - `test "the tree reads only kept, visible pages, and only the tree's columns"`. It trashes one page, then collects the SQL with `ActiveSupport::Notifications.subscribed` and asserts that no statement matches `/SELECT "pages"\.\* FROM "pages"/`, that some statement matches `/"pages"\."id" IN/`, and that `li[data-page-id='<trashed id>']` is absent.
  - In `pages_tree_row_test.rb` (an integration test signed in as an editor, with `with_locales(%w[en de es])`):
    - `test "a settings save replaces the saved page's row and not the tree"`. It PATCHes the page's settings with a new title and parses the streams. It asserts that `turbo-stream[action=replace][target='tree-row-<id>']` is present, that it holds the new title, and that `turbo-stream[target=tree]` is absent.
    - `test "a settings save costs the same statements for 3 pages as for 30"`. It counts with `count_statements { patch … }` after a warm-up save, for 3 and for 30 pages, and asserts the two counts are equal.
  - In `tree_row_component_test.rb`: `test "a row alone draws what the row draws in the whole tree"`. It renders `for_page` for a page with two children, a missing translation and a note. It asserts `#tree-row-<id>` with the `○N` marker, the child count and the notes pill, and the same markup as the row inside a full `TreeComponent` render (compare `css("#tree-row-<id>").to_html` after stripping `nonce`).
- [ ] **Step 2: Run them, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/components/admin/pages_screen test/integration/admin/pages_tree_row_test.rb`. Expected: the select test fails on `"pages".*`, and the integration tests fail on `target=tree`.
- [ ] **Step 3: Implement.** `TreeNodeComponent` passes its slice of what the tree loaded to `TreeRowComponent`. `for_page` answers the same slice for one page. The move, create and trash paths keep `tree_replace_stream` (`TreeController#tree_stream`) and are unchanged. The long comment in `pages_controller.rb#update` is rewritten to the new invariant: a settings save changes only that page's row, and the shape of the tree changes only through a move, a create or a trash. A row's place is `TreeOrder`, by position and never by title, so a retitled page does not move.
- [ ] **Step 4: Run them, and verify they pass.** Then run `test/components/admin/pages_screen test/integration/admin test/integration/trash_visibility_test.rb`, and locally `tree_test` and `presence_lists_test`. Expected: PASS.
- [ ] **Step 5: Commit** `perf: the page tree reads kept, visible pages in SQL, and a settings save redraws one row` (body: `Closes #123`, `Advances #117`)

---

### Task 2: The tree folds

**Files:**
- Modify: `app/javascript/controllers/admin/shell/tree_width_controller.js`:
  - the controller moves from the divider to `aside#tree-column`, and the divider becomes the `divider` target;
  - new: `fold`, `unfold`, `folded`.
- Modify: `app/components/admin/shell/tree_divider_component.rb`:
  - `STRIP = 44` and `FOLD_KEY = "cs-tree-folded"`;
  - `self.column_data`, the controller and its values for the aside;
  - the divider's own data become target and actions only.
- Create: `app/components/admin/shell/tree_fold_component.rb` (the strip's "Show page tree" button)
- Modify: `app/views/layouts/admin.html.erb` (the aside: `data: TreeDividerComponent.column_data`, then `TreeFoldComponent`, then `yield :tree`, then the divider)
- Modify: `app/views/admin/shared/_tree_head.html.erb` (reads `FOLD_KEY` and sets `data-tree-folded` before the first paint; when folded, it counts the strip's width in the `data-tree-fits` sum)
- Modify: `app/components/admin/pages_screen/tree_component.html.erb` (the head's "Hide page tree" button), `config/locales/admin/pages_screen.en.yml` (new: `admin.components.pages_screen.tree.hide: "Hide page tree"`), `config/locales/admin/shell.en.yml` (`tree_fold.show: "Show page tree"`)
- Modify: `app/assets/tailwind/content-spiel.tailwind.css` (`--admin-tree-strip: 2.75rem`; from 1024px, `:root[data-tree-folded]` makes `--admin-tree-column` the strip, hides everything in the column but the strip's button, and hides the divider)
- Test: `test/system/admin/tree_fold_test.rb` (new), `test/system/admin/tree_column_test.rb`, `test/components/admin/shell/tree_divider_component_test.rb`, `test/integration/admin/tree_test.rb` (the head script), `test/lib/admin_design_rules_test.rb`, `test/application_system_test_case.rb` (`at_window(width, height: 900) { }`, moved from `tree_column_test.rb#at_width`, which now calls it)

**Interfaces:**
- Produces:
  - `admin--shell--tree-width`:
    - `static targets = ["divider", "fold", "unfold"]`, and the new value `foldKey: String`.
    - `fold()`: sets `data-tree-folded` on `<html>`, stores `"1"` under `foldKey`, runs `sync()` and focuses `unfoldTarget`.
    - `unfold()`: removes the attribute and the stored key, runs `sync()` and focuses `foldTarget`.
    - `get folded()`: whether `<html>` has `data-tree-folded`.
    - `sync()` counts the strip (`STRIP * scale`) in place of the chosen width while folded, and writes `aria-expanded` on both buttons.
  - `--admin-tree-width` keeps its one meaning, the CHOSEN width. The fold does not overwrite it, so unfolding needs no read of the storage. The grid's track (`--admin-tree-column`, the stylesheet's own derived property) is the strip while folded.
  - The fold button: `<button data-admin--shell--tree-width-target="fold" data-action="admin--shell--tree-width#fold" aria-controls="tree-column" aria-expanded="true">`, a tertiary small `ButtonComponent` with an icon, shown from 1024px. The unfold button is its mirror, `aria-expanded="false"`, and is shown only while folded.

- [ ] **Step 1: Write the failing tests.**
  - `tree_fold_test.rb`, each test using `at_window`:
    - `test "Hide page tree folds the column to a strip, the editor widens, and Show page tree brings it back at its chosen width"` at 1600px. It drags the tree to 320px, presses "Hide page tree", and asserts the column's box is 44px wide (± 1), that `#main` grew by the difference, and that the focus is on "Show page tree". It then presses that button and asserts 320px and the focus on "Hide page tree".
    - `test "a fold is remembered: the next screen is laid out folded from the first paint"`. It folds, visits another page from ⌘K, and asserts that `document.documentElement.hasAttribute('data-tree-folded')` was true in a `DOMContentLoaded` probe (the pattern `tree_column_test` uses for the width).
    - `test "a folded tree is the ordinary drawer under 1024px, and folded again at 1600px"`. It folds at 1600, goes to 900, and asserts "Pages" opens the 17rem drawer with the tree in it and no strip. It goes back to 1600 and asserts the strip.
    - `test "the fold buttons say what they control"`. It asserts `aria-controls="tree-column"` on both, and their `aria-expanded`.
  - `admin_design_rules_test.rb`: `test "the tree's width, fits and fold are written by the head script and the tree-width controller alone"`. It scans `app/javascript`, `app/views` and `app/components` for `setProperty("--admin-tree-width"`, `removeProperty("--admin-tree-width"` and any `setAttribute`, `toggleAttribute` or `removeAttribute` of `"data-tree-fits"` / `"data-tree-folded"` (also through a constant: the scan reads the two constants `PROPERTY`, `FITS` and `FOLDED` and their uses). It asserts that the files writing them are exactly `_tree_head.html.erb` and `tree_width_controller.js`. A second test, `test "the writer pattern matches each way of writing the three"`, feeds it samples.
- [ ] **Step 2: Run them, and verify they fail.** Run the rules test, then locally `PGGSSENCMODE=disable bin/rails test test/system/admin/tree_fold_test.rb`.
- [ ] **Step 3: Implement.** Every `this.element` in the controller that meant the separator becomes `this.dividerTarget`. The divider's ARIA, tooltip and pointer actions stay on the divider. `rest()` and `disconnect()` are unchanged. The fold and the remembered key are document state, like the width, and are not taken back. The header comment gains a part "THE FOLD": a third state of the width, two writers, the track is the strip, and the chosen width is untouched.
- [ ] **Step 4: Run them, and verify they pass.** Then locally `tree_column_test`, `tree_test`, `notes_column_test` and `presence_lists_test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: a button folds the page tree to a strip, remembered before the first paint` (body: `Advances #117`)

---

### Task 3: The rail: tokens, grid, tabs

**Files:**
- Modify: `app/assets/tailwind/content-spiel.css` (beside `--cs-form-max`: `--cs-editor-column: 900px;`, `--cs-rail-width: 360px;`, `--cs-rail-gap: 28px;`)
- Modify: `app/assets/tailwind/content-spiel.tailwind.css`:

  | Rule | What it does |
  |---|---|
  | `.admin-editor-area { container: admin-editor / inline-size; }` | makes the editor area the container |
  | `.admin-rail-grid` | one column below the threshold |
  | `@container admin-editor (min-width: 1200px) { .admin-rail-grid:not(.admin-rail-grid--folded) { … } }` | `grid-template-columns: minmax(0, var(--cs-editor-column)) var(--cs-rail-width); column-gap: var(--cs-rail-gap); justify-content: start;`, with the rail's items in column 2, the blocks column in column 1 across every row, and the ground as `::before` (`--cs-rail`, `--cs-shadow-2`, `--cs-radius-rail`) in column 2 across every row |
  | the same container query | the blocks column's `max-width: var(--cs-editor-column)` over `.admin-form-column` |
  | `.admin-rail__tabs` and `.admin-rail__panel` | the tabs hidden below the threshold; docked, only `[data-current]` panels shown |
- Create: `app/components/admin/ui/rail_tabs_component.{rb,html.erb}`, `app/components/admin/ui/rail_panel_component.{rb,html.erb}`
- Create: `app/javascript/controllers/admin/ui/rail_controller.js`
- Modify: `app/components/admin/editor_screen/live_region_component.*` (class `admin-editor-area`)
- Modify: `config/locales/admin/ui.en.yml` (`rail_tabs.label: "Settings"`)
- Test: `test/components/admin/ui/rail_tabs_component_test.rb`, `rail_panel_component_test.rb` (new), Lookbook previews in `test/components/previews/admin/ui/`, `test/lib/admin_design_rules_test.rb`, `test/lib/admin_contrast_test.rb`, `test/lib/admin_i18n_test.rb`

**Interfaces:**
- Produces:
  - `Admin::Ui::RailTabsComponent::Tab = Data.define(:key, :label, :count)`, where `count` is optional (nil), drawn as `text-count`.
  - `Admin::Ui::RailTabsComponent.new(rail_id:, tabs:, current:)` draws `div.admin-rail__tabs[role=tablist][aria-label]`. Each tab is `button#<rail_id>-tab-<key>[role=tab][aria-selected][aria-controls=<rail_id>-panel-<key>][data-admin--ui--rail-target=tab][data-key]`, with `tabindex=0` only on the current one. With one tab it draws an `h2` with the tab's label instead, and no tablist.
  - `Admin::Ui::RailPanelComponent.new(rail_id:, key:, current: false, docked_only: false)` wraps its content in `div#<rail_id>-panel-<key>.admin-rail__panel[role=tabpanel][aria-labelledby][data-admin--ui--rail-target=panel][data-key]`, with `data-current` when current. `docked_only: true` (the Section panel) is not shown below the threshold.
  - `admin--ui--rail`, on the grid:
    - `static targets = ["tab", "panel"]`, `static values = { current: String }`.
    - `select(event)`, `key(event)` (ArrowLeft/Right, Home, End: move the focus and select, ARIA's automatic tabs).
    - `reveal(event)`, heard as `admin--ui--rail:reveal`: selects the panel that holds `event.target`, after remembering the current key as `previous`.
    - `conceal(event)`: selects `previous`, if the panel holding `event.target` is current.
    - `docked`: whether the grid's computed `--admin-rail-docked` is `1`. The container query sets that property, and the controller only reads it. It writes `data-rail-docked` on its element on connect and from a `ResizeObserver`, and dispatches `admin--ui--rail:docked` with `{ docked }` when the state changes.
    - Every selection dispatches `admin--ui--rail:shown` on the panel with `{ key }`.
    - `tabTargetConnected` and `panelTargetConnected` re-apply `currentValue`, so a redrawn tab or panel takes the controller's state, not the server's.
  - The current tab is the controller's. It is never stored or remembered beyond the document.

- [ ] **Step 1: Write the failing tests.**
  - `rail_tabs_component_test.rb`:
    - "three tabs are a tablist with one tab in the tab order, each controlling its panel";
    - "one tab is a heading, not a tablist";
    - "a tab's count is text-count and hidden at zero".
  - `admin_design_rules_test.rb`:
    - extend "the form column's width is a token…" to `900px`, `360px` and `28px` each written once in `content-spiel.css` and nowhere else in the sources;
    - `test "the rail is laid out by the editor area's container, never the window"`, which asserts the `@container admin-editor (min-width: 1200px)` block and no `@media` rule naming `.admin-rail-grid`;
    - add `.admin-rail__tabs` to whatever allow-list the hand-built-button scan needs, with its reason.
  - `admin_contrast_test.rb`: the selected tab's indicator (accent on `--cs-rail`, 3:1) and its words, a tab's words on `--cs-rail` (4.5:1), in both themes. **(owner):** the drawn tab is a 2px accent underline; the test measures whatever the build draws.
- [ ] **Step 2: Run them, and verify they fail:** `PGGSSENCMODE=disable bin/rails test test/components/admin/ui test/lib`.
- [ ] **Step 3: Implement** the two components, the CSS and the controller. The controller's header says:
  - what it reads (the container's property) and what it writes (`data-current`, `aria-selected`, `tabindex`, `data-rail-docked`);
  - that the events are the only way a feature opens a panel.
- [ ] **Step 4: Run them, and verify they pass.** Expected: PASS. The editors use the rail in Tasks 6 and 7, which hold its browser tests.
- [ ] **Step 5: Commit** `feat: the rail's tokens, grid and tabs, laid out by the editor area's container` (body: `Advances #117`)

---

### Task 4: A section's settings region carries its own behaviour

The region must work in the rail, outside its card. Today its layout menu, its Close button and Escape are actions of `admin--editor--section`, which sits on the card. Outside the card those actions bind to nothing. This task moves them onto the region, with no visible change.

**Files:**
- Create: `app/javascript/controllers/admin/editor/section_settings_controller.js`
- Modify: `app/javascript/controllers/admin/editor/section_controller.js`:
  - it keeps the words, panels, tiles and lanes, and finds the region by id wherever it is (`region`);
  - `chooseLayout`, `layoutMenuTargetConnected`, `pickedIn`, `menuReplaced`, `focusSetting` and the region's Escape and Close move out.
- Modify: `app/components/admin/editor_screen/section_card_component.html.erb` (the region carries `data-controller="admin--editor--section-settings"` and `data-section-id`; its controls' actions are renamed), `section_layout_menu_component.*`
- Unchanged, and must stay green: `admin--editing--hold#reveal` still calls `admin--editor--section#showSettings` with no field (`editing_held_test`)
- Test: `test/system/admin/sections_settings_test.rb`, `editing_held_test.rb`, `editing_merge_test.rb` (unchanged, must stay green), `test/system/admin/editor_modules_test.rb`

**Interfaces:**
- Produces:
  - `admin--editor--section-settings` on `#section-<id>-settings`:
    - `static targets = ["layoutMenu"]`;
    - `chooseLayout(event)`, moved, the same as today;
    - `close()`: sends what the form holds (`saveNow`), hides the region and dispatches `admin--editor--section-settings:closed` with `{ sectionId }`, bubbling;
    - `escape(event)`: today's region branch of `section#escape`, with its same exceptions;
    - `focus(field)`: today's `focusSetting`;
    - `get menuReplaced()`.
  - `admin--editor--section`:
    - `get region()` is `document.getElementById(this.settingsIdValue)`; the card carries `data-admin--editor--section-settings-id-value` = `SectionCardComponent.settings_id(section)`;
    - `showSettings(field)`: the region is shown wherever it ended up after the cancelable `open-settings`. When the event was cancelled, the region is visible if a listener showed it; when nobody cancelled, this opens it in place. Either way the words are marked and `region`'s controller is asked to `focus(field)`;
    - `settingsClosed(event)`, heard as `admin--editor--section-settings:closed@window` for its own `sectionId`, marks the words closed and refocuses the word that opened them;
    - `lanesTargetConnected` asks `region`'s controller for `menuReplaced`;
    - `closeSettings` stays the door for the collapse and for `hold#reveal`, and calls the region's `close()`.

- [ ] **Step 1: Write the failing test.** `editor_modules_test.rb`: `test "a section's settings region works outside its card: layout, Close and Escape"`. It moves `#section-<id>-settings` into `document.body` by script. Then it picks "2 columns" from its layout menu and asserts the save lands (`#section-<id>-form` status "Saved"). It presses Escape in the region and asserts the region is hidden and the focus is on the word "2 columns ▾".
- [ ] **Step 2: Run it, and verify it fails:** locally `PGGSSENCMODE=disable bin/rails test test/system/admin/editor_modules_test.rb`.
- [ ] **Step 3: Implement the split.** A Stimulus controller on an element that moves keeps its instance (Stimulus reuses a context per element and identifier), so `pickedIn` survives a move into the rail and back. The header comment of `section_controller.js` keeps its parts about panels and lanes. Its "THE SECTION'S OWN SETTINGS" part is rewritten so that the region's own behaviour is described in the new controller.
- [ ] **Step 4: Run it, and verify it passes.** Then locally the eight `sections_*_test` files, `editing_held_test` and `editing_merge_test`. Expected: PASS, with no other test changed.
- [ ] **Step 5: Commit** `ref: a section's settings region carries its own controller, so it works wherever it stands` (body: `Advances #117`)

---

### Task 5: The list merge merges what a script moved away

**Files:**
- Modify: `app/javascript/editing/merge.js`:
  - `mergeList` gains `away`;
  - `RUNTIME` gains `data-chosen` and `data-editing-away`;
  - the header gains the rule.
- Modify: `app/javascript/controllers/admin/editing/live_controller.js` (passes `away: [...this.element.querySelectorAll("[data-editing-away]")]`; its `merged` event's detail gains `awayGone`)
- Test: `test/system/admin/editing_merge_test.rb`

**Interfaces:**
- Produces: `mergeList(list, fresh, { unsaved, onlyChanged = false, hold = null, away = [] })` → `{ kept, gone, moved, same, awayGone }`.
  - `away`: elements of the list that a script moved out of it (the Section panel's region). Each carries `data-editing-away` and its own id.
  - For each, the answer's element of that id is taken out of `fresh` before anything is drawn, so the list gets no second copy. The away element is then merged where it stands, as an ancestor is today: its attributes are synced except `hidden` and the `RUNTIME` ones, and its children are reconciled with the same `keep`, `same` and `extra` sets.
  - The `keep` set and `withState` (focus, open settings) cover the away elements as well as the list.
  - An away element whose id the answer lacks (its section is gone):
    - with a kept unit inside, it stays and its unit is marked gone, as everywhere;
    - without one, it is left in place and returned in `awayGone` for its owner to remove.
  - `mergeUnits` is unchanged: a section's own answer is a 204, and the list says what is true.

- [ ] **Step 1: Write the failing tests** in `editing_merge_test.rb`, which drives the module in the browser as its other cases do:
  - "an away region with no unsaved text is replaced where it stands, and the list gets no copy". Assert one `#section-<id>-settings` in the document, inside the away host, showing the answer's layout word.
  - "an away region holding unsaved text is the same element afterwards, with its text, its focus and its caret". Assert `===` identity on the region and the form, and `selectionStart`.
  - "an away region whose section the answer lacks is returned in awayGone when clean, and kept with its unit marked gone when unsaved".
  - "a catch-up leaves an away region of the same version alone". Assert identity with `onlyChanged: true`.
  - "a chosen section's card keeps data-chosen through a merge".
- [ ] **Step 2: Run them, and verify they fail:** locally `PGGSSENCMODE=disable bin/rails test test/system/admin/editing_merge_test.rb`.
- [ ] **Step 3: Implement.** The header's new paragraph is "WHAT A SCRIPT MOVED AWAY", giving the rule and its reason: a merge never moves a unit, so it merges an away element where it stands rather than putting it back.
- [ ] **Step 4: Run them, and verify they pass.** Then locally `editing_live_test`, `editing_held_test` and `changed_elsewhere_test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: live editing's list merge merges a section's settings where a script moved them` (body: `Advances #117`)

---

### Task 6: The page editor in the rail, and choosing a section

**Files:**
- Modify: `app/views/admin/pages/show.html.erb`. Inside the live region, `div#editor-grid.admin-rail-grid` (with `admin-rail-grid--folded` on a translation tab, where `Locales.default` is not `admin_locale`) carries `data-controller="admin--ui--rail admin--editor--section-choice"` and holds, in this order:
  - `RailTabsComponent` (Page · Section);
  - `RailPanelComponent(key: "page")` with `PageSettingsFormComponent`;
  - `RailPanelComponent(key: "section", docked_only: true)` with the choice's slot and its empty line;
  - `#content-blocks-alert`;
  - the blocks `section`.
- Modify: `app/components/admin/editor_screen/page_settings_form_component.html.erb`. While the rail is docked, the `<details>` summary is hidden and its content forced open (the translation pair's `::details-content` rule). Below the threshold it is the disclosure it is today.
- Create: `app/javascript/controllers/admin/editor/section_choice_controller.js`
- Modify: `app/assets/tailwind/content-spiel.tailwind.css` (`.admin-section-card[data-chosen] { outline: 2px solid var(--cs-accent); outline-offset: 2px; }`, written after the stage-2 frame rule)
- Modify: `config/locales/admin/editor_screen.en.yml`:
  - `rail.tabs.page: "Page"`, `rail.tabs.section: "Section"`;
  - `section_choice.empty: "Choose a section"`;
  - `section_choice.help: "Press a section's settings, such as “3 columns ▾”, to change them here."` **(owner)**
- Test: `test/system/admin/editor_rail_test.rb` (new), `test/system/admin/section_choice_test.rb` (new), `test/system_test_seconds.yml` (the new files, so `system_test_shards_test` places them), `form_width_test`, `translation_layout_test`, `editor_header_test`, `sections_settings_test`, `editing_claims_test`, `editing_holds_test`, `autosave_test`, `autosave_unload_test`

**Interfaces:**
- Consumes: `admin--ui--rail` events (Task 3); `admin--editor--section:open-settings` (stage 2, now with the region visible after a cancel, Task 4); `admin--editor--section-settings:closed` (Task 4); `admin--editing--live:merged`'s `awayGone` (Task 5).
- Produces: `admin--editor--section-choice`, on the grid:
  - `static targets = ["slot", "empty"]`.
  - `take(event)` (`admin--editor--section:open-settings->…#take`). Docked only (`data-rail-docked`), it:
    - calls `event.preventDefault()`;
    - releases any other chosen region;
    - appends `event.detail.region` to `slotTarget` and sets `data-editing-away` and `hidden = false` on it;
    - sets `data-chosen` on the section card;
    - hides `emptyTarget`;
    - dispatches `admin--ui--rail:reveal` from the region.
  - `release({ refocus })` puts the chosen region back as the card's region slot's child, in the place `SectionCardComponent` draws it (after the head, `[data-section-settings-home]`). It removes `data-editing-away`, hides the region, removes `data-chosen` and shows `emptyTarget`. It is run:
    - on `admin--editor--section-settings:closed` for the chosen section;
    - on `admin--ui--rail:docked` with `docked: false`, with the focus following the control that had it;
    - on `turbo:before-cache@document`;
    - on `disconnect`.
  - `merged(event)`, for `awayGone` holding the chosen region: removes the region, removes `data-chosen` and shows the empty line.
  - `streamed(event)` (`turbo:before-stream-render@document`, wrapping `event.detail.render`): after the stream's render, if the chosen card is no longer connected (Remove section), the region is removed and the empty line shown.
  - `SectionCardComponent` gains `[data-section-settings-home]`, an empty marker after the head, for `release`.
- The head words keep `aria-controls="section-<id>-settings"`, which is the element that is shown at both widths. No script rewrites them on a resize.

- [ ] **Step 1: Write the failing tests.**
  - `editor_rail_test.rb`, at 1900 × 900 (docked) and 1400 × 900 (folded back) through `at_window`:
    - "at a wide window the rail stands right of a 900px blocks column, left-aligned, 28px apart". Measure the boxes: blocks left equals the content's left, width 900 ± 1, the rail's left equals blocks right + 28, width 360.
    - "below the threshold the page settings stand above the blocks at 760px and there are no tabs". This is the cascade test of the 900-over-760 rule.
    - "the document order is header, tabs, settings, blocks". Tab from the language tabs and assert the sequence of focused elements' closest landmarks.
    - "folding the tree at 1600px docks the rail". This is Task 2's fold with the container query.
    - "a translation tab never docks the rail".
    - "the page settings are one form at every width". Assert `#page-settings` and the settings form's `base_updated_at` field exist once; type in Title docked, then resize to 1400, then type again; assert both saves land with their bases and the same form element (`data-probe` set by script survives).
    - "the page settings are forced open while docked, and keep the person's disclosure state below". This is the cascade test of the forced-open rule.
    - "Page and Section are tabs: arrows move between them, Home and End go to the ends".
  - `section_choice_test.rb`, docked unless named:
    - "pressing a section's words shows its settings in the Section tab and outlines the section". Assert `#editor-grid-panel-section #section-<id>-settings`, `[data-chosen]` on the card, the focus on the word's setting, and `aria-expanded=true` on the words.
    - "nothing else of the section selects it: its ground, a tile, a handle, a lane and + Add". Click each and assert no `[data-chosen]`. A tile still opens its block's panel under the lanes.
    - "with no section chosen the Section tab says Choose a section".
    - "a second section's words move the first one's settings home and show the second's".
    - "Escape and Close in the Section panel put the settings home and give the focus back to the word".
    - "typing in the rail and choosing another section at once saves on the right base". Type, then press another section's words inside the debounce. Assert both forms "Saved" and the first section's stored anchor.
    - "a window narrowed while a section field in the rail has the focus puts the region under its head with the focus and the text, and the save lands on its base".
    - "below the threshold the words open the settings in place, as before".
    - "removing the chosen section takes its settings out of the rail and says Choose a section".
    - "a colleague's save of the chosen section redraws its settings in the rail" (two sessions, as `editing_live_test` does).
    - "a held section's settings shown in the rail are read-only with their hold strip" (`editing_held` setup).
    - "leaving the editor with settings in the rail sends their unsaved text first" (the leave guard).
  - `admin_contrast_test.rb`: the chosen outline (accent against `--cs-paper`, 3:1).
- [ ] **Step 2: Run them, and verify they fail:** locally both new files, one at a time.
- [ ] **Step 3: Implement.** The header comment of `section_choice_controller.js` says:
  - it moves one element and never clones;
  - the four moments it puts the element back;
  - why a merge does not move it (merge.js's away rule);
  - that the words are the only target that selects.
- [ ] **Step 4: Run them, and verify they pass.** Then locally, one at a time: `tree_column_test`, `tree_test`, `form_width_test`, `translation_layout_test`, `editor_header_test`, `sections_settings_test`, `editing_claims_test`, `editing_holds_test`, `autosave_test` and `autosave_unload_test`. Fix whatever measured the old 760px column at a wide window. Expected: PASS.
- [ ] **Step 5: Commit** `feat: the page editor's settings stand in a rail at wide widths, and a section's words choose it` (body: `Advances #117`)

---

### Task 7: The post editor in the rail

**Files:**
- Modify: `app/components/admin/editor_screen/post_form_component.html.erb`:
  - after the header, `div#editor-grid.admin-rail-grid` (`--folded` on a translation tab, `data-controller="admin--ui--rail"`) holds the `RailTabsComponent` (one tab, Post, so a heading until Task 11 adds Notes) and `form#post-form`;
  - the form is `display: contents` while docked (`.admin-rail-grid:not(--folded) > #post-form` under the container query) and holds `RailPanelComponent(key: "post")` with the excerpt, the content type's fields group, the tags and the related posts, then `div.admin-post-main` with the title, the address, and the body;
  - the card look (`rounded-card bg-surface shadow-1 p-4`) moves from the form to `.admin-post-main`, and to the form itself below the threshold. **(owner):** which fields count as the post's settings. The default follows the spec: tags, related posts and excerpt, with the type's own fields beside them.
- Modify: `config/locales/admin/editor_screen.en.yml` (`rail.tabs.post: "Post"`)
- Test: `test/system/admin/editor_rail_test.rb` (post cases), `drafts_test`, `chip_input_test`, `new_record_test`, `tokens_related_posts_and_starter_pages_test`, `test/components/admin/editor_screen/post_form_component_test.rb`

**Interfaces:**
- Consumes: Task 3's components and controller. The post form stays one unit (`data-editing-subject="record"`), so the record merge replaces the whole form, its panel with it, and `admin--ui--rail#panelTargetConnected` re-applies the current tab.

- [ ] **Step 1: Write the failing tests** in `editor_rail_test.rb`:
  - "a post's settings stand in the rail at a wide window, and the post form is still one form". Assert one `form#post-form`, that the tags input and the body are both its descendants, and that a tag added in the rail and a body edit each save through the one autosave.
  - "a post's settings stand above its body below the threshold, in document order". Test the order, then focus.
  - "a post form replaced by a live merge keeps the tab that was current".
  - In `post_form_component_test.rb`: "the post's settings panel is inside the form and before the main column".
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** The comment on `display: contents` gives its reason: the panel must stay inside the one form while it stands in the rail's column, and the notes panel (Task 11) must stand outside every form.
- [ ] **Step 4: Run them, and verify they pass.** Then locally `drafts_test`, `chip_input_test`, `new_record_test`, `tokens_related_posts_and_starter_pages_test` and `notes_column_test` (post cases). Expected: PASS.
- [ ] **Step 5: Commit** `feat: the post editor's settings stand in the rail at wide widths` (body: `Advances #117`)

---

### Task 8: 3a's reference, CLAUDE.md and the pull request

**Files:**
- Modify: `docs/reference/design-system.md`:
  - a section "E4: the right rail": the grid, the container query, the three tokens, the ground as `::before`, the tabs, the chosen outline as a selection;
  - "Rules a change can break silently" gains the guards of Tasks 2, 3 and 6 by test name, and the no-guard case: a new docked override that no browser test measures.
- Modify: `docs/reference/cs-studio-shell-and-dashboard.md` (the fold, its writers and their guard), `editors-and-translation-pair.md` (the editors' layout), `content-blocks-and-types.md` ("Sections in the editor": choosing, the region's controller, `[data-section-settings-home]`), `live-editing.md` (`away`, `data-chosen` in `RUNTIME`), `save-rule-and-write-queue.md` (a moved form re-registers, and the region is moved only by the choice)
- Modify: `CLAUDE.md`:
  - the shell index line names `tree_fold_component.rb`;
  - the editors line names `section_choice_controller.js`, `section_settings_controller.js` and `app/components/admin/ui/rail_*`;
  - "Page tree's width" now reads "`--admin-tree-width`, `data-tree-fits` and `data-tree-folded` … by nothing else", and its "No guard" becomes the guard's name;
  - "Rules a change can break silently" gains: "A section's settings in the rail are the same element moved, never a copy; `admin--editor--section-choice` alone moves them and puts them back."
- Modify: `test/system/README.md` (`at_window`, docked and folded widths: 1900 docks, 1400 does not, 1600 docks only folded)
- Test: `PGGSSENCMODE=disable bin/rails test test/lib`, `bin/rubocop`, `bin/rails zeitwerk:check`, `bin/changelog-guard` (no migration, ledger or plugin change, so no CHANGELOG line)

- [ ] **Step 1: Write the reference and CLAUDE.md changes.**
- [ ] **Step 2: Run** the four checks. Expected: all pass.
- [ ] **Step 3: Write the PR body.** Base `studio-e4-2`. The sections are:
  - "What a person sees";
  - "Under the hood": #123 closes; #139 was already done in #186;
  - "Interim until 3b": the notes column still takes the editor's room and undocks the rail while open;
  - "For the owner to check": the tab look, the strip's 44px, the post's settings fields, the help line under "Choose a section", the rail scrolling with the page;
  - "Documentation" (below).
- [ ] **Step 4: Check no test run is left**: `pgrep -f "rails test"` prints nothing.
- [ ] **Step 5: Commit** `docs: E4 stage 3a in the reference and CLAUDE.md` (body: `Advances #117`)

**Documentation (3a), in `contentspiel-docs`:**
- pages:
  - `docs/editors/pages/build-a-page-with-blocks.md` (the rail);
  - `page-settings-and-search-appearance.md` (settings in the Page tab, and above the blocks on a narrow window);
  - `arrange-blocks-in-sections.md` (choosing a section, the Section tab);
  - `the-page-tree.md` (Hide page tree);
  - `docs/editors/posts/posts-and-content-types.md` (the Post tab);
  - `tags-related-posts-and-the-mind-graph.md` (tags and related posts in the rail).
- screenshots: page-tree, page-tree-folded, editor-rail-page, editor-rail-section, section-choose, post-editor-rail, section-two-columns (retaken).

---

# PR 3b: notes as the rail's Notes tab

### Task 9: One merge core for notes and live editing (#132)

**Files:**
- Create: `app/javascript/live/keep_merge.js`
- Modify: `app/javascript/editing/merge.js`:
  - `reconcile` becomes a call of the core, plus its own gone marking;
  - `mergeList` is renamed `mergeBlockList`.
- Modify: `app/javascript/notes/merge.js`:
  - the list part of `mergeList` becomes a call of the core;
  - `mergeList` is renamed `mergeNoteList`;
  - `mergeThread` and `mergeGone` are unchanged.
- Modify: `app/javascript/controllers/admin/editing/live_controller.js`, `app/javascript/controllers/admin/notes/live_controller.js` (the imports)
- Test: `test/system/admin/editing_merge_test.rb`, `test/system/admin/notes_merge_test.rb`, `test/system/admin/editor_modules_test.rb` (core cases), `test/lib/source_layout_test.rb` (`live` stays a module folder with no topic)

**Interfaces:**
- Produces: `keepMerge(container, fresh, { kept, within = () => false, sync = null, place = null }) -> { orphans }`.
  - `container`: the element on screen. `fresh`: an Array of the answer's elements, not in the document.
  - `kept`: a Set of elements on screen that stay the same element and are never moved. The one exception is today's: when two kept elements changed places, the one without the focus moves.
  - An element of `container` with the id of an answer's element is kept and reconciled inside, level by level, when `within(element)` is true (it holds a kept element). Its attributes are synced through `sync(live, twin)`. Otherwise it is replaced by the answer's element.
  - A kept element that the answer has by id takes that place, and the answer's copy is dropped. A kept element that the answer lacks stays, before `place(orphan, fresh)` when given, else after the nearest preceding sibling the answer has. It is returned in `orphans`.
  - Each feature keeps its own predicate:
    - editing: `kept` = units that hold unsaved text, plus `same`, `held` and the notices;
    - notes: `kept` = `#notes-new` while on screen, with `place` = the first answer part that is not `[hidden]` or `[role=status]`.
- `mergeBlockList` and `mergeNoteList` keep today's contracts and results under their new names, so the two `mergeList` exports with two contracts end.

- [ ] **Step 1: Write the failing core tests** in `editor_modules_test.rb`:
  - "keepMerge keeps a kept element the same element in the answer's place";
  - "keepMerge leaves an orphan after its preceding sibling, or before place()";
  - "keepMerge reconciles inside an element that holds a kept one";
  - "keepMerge moves the kept element without the focus when two swap".
- [ ] **Step 2: Run it, and verify it fails** (no module).
- [ ] **Step 3: Implement the core** and move both callers onto it. Each module's header states its own rule ("WHAT IS TYPED IS NEVER TOUCHED", "A FORM THAT HOLDS CHANGES NOT YET SAVED IS NEVER REPLACED") and names the core for the mechanics. The mechanics' prose moves to the core's header once.
- [ ] **Step 4: Run them, and verify they pass.** Then locally `editing_merge_test`, `notes_merge_test`, `notes_live_test`, `editing_live_test` and `section_choice_test`. Expected: PASS, with no case of the two merge tests changed but the imported name.
- [ ] **Step 5: Commit** `ref: one merge core for notes and live editing, live/keep_merge.js` (body: `Advances #132`, `Advances #117`)

---

### Task 10: The rail's tabs are an editor-panel slot (#127)

**Files:**
- Modify: `app/components/admin/slots.rb` (`NAMES` gains `editor.rail.tabs`; the header describes the panel shape)
- Modify: `app/components/admin/ui/rail_tabs_component.rb` (it takes `slot_tabs:`), `app/components/admin/ui/rail_panel_component.rb`
- Create: `app/components/admin/ui/rail_slot_component.rb`, which draws the registered tabs' panels
- Create: `app/controllers/admin/answers/rail_tab_streams.rb`
- Modify: `app/controllers/admin/pages_controller.rb#update`, `app/controllers/admin/posts_controller.rb#update` (append `RailTabStreams.for(...)` on a successful save)
- Test: `test/components/admin/slots_test.rb`, `test/components/admin/ui/rail_slot_component_test.rb` (new), `test/controllers/admin/answers/rail_tab_streams_test.rb` (new), `test/lib/notes_boundary_test.rb`, `docs/reference/slots.md`

**Interfaces:**
- Produces:
  - The panel shape. A component registered at `editor.rail.tabs` is built like every slot component (`record:, viewer:, data: nil, **context`) and answers:
    - `tab_key` (a String, `/\A[a-z]+\z/`);
    - `tab_label` (a String);
    - `tab_count` (Integer or nil);
    - `render?`.
    Rendered, it is the panel's content.
  - `Admin::Ui::RailSlotComponent.new(rail_id:, record:, viewer:, **context)` → `#tabs` (an Array of `RailTabsComponent::Tab` for the entries that render) and `#call`, which draws each entry inside `RailPanelComponent(key: entry.tab_key)`.
  - `Admin::Answers::RailTabStreams.for(record, view:, viewer:, rail_id: "editor-grid", **context) -> Array`: one `turbo_stream.replace("<rail_id>-tab-<key>", …)` per rendering entry. This is the tab only, never its panel, which may hold typed text.
  - The editors hand the slot `query: request.query_parameters`, so a panel can read its own parameters (`?notes=open`) without the host naming them.

- [ ] **Step 1: Write the failing tests.**
  - `slots_test.rb`: "editor.rail.tabs is a name a screen may put a slot at".
  - `rail_slot_component_test.rb` uses `Admin::Slots.with` and a fake component:
    - "a registered panel adds a tab after the rail's own and draws its panel";
    - "an entry whose render? is false adds no tab";
    - "the context reaches the panel, query included".
  - `rail_tab_streams_test.rb`: "a save's answer replaces each registered tab by id and no panel".
  - `notes_boundary_test.rb`: the rail's components and both editor views are in its scanned set. "the editors' header and the media panel do not name notes" extends to "nor does the rail".
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Write `docs/reference/slots.md`'s new shape, step by step as the file does for the others.
- [ ] **Step 4: Run them, and verify they pass:** `test/components/admin test/controllers/admin/answers test/lib`.
- [ ] **Step 5: Commit** `feat: the rail's tabs are an editor-panel slot, editor.rail.tabs` (body: `Advances #127`, `Advances #117`)

---

### Task 11: Notes are the rail's Notes tab

**Files:**
- Rename: `app/components/admin/notes_screen/drawer_component.*` → `rail_panel_component.*` (`Admin::NotesScreen::RailPanelComponent`). It is the slot entry for `editor.rail.tabs`:
  - `tab_key "notes"`, `tab_label t(".title")`, `tab_count` = the open count, and `render?` true for a page or a post;
  - its markup is today's drawer frame as `div#notes-drawer` (the id the header's button controls). It keeps every data attribute of the `record` target, the counts element, the frame and the `keydown.esc` close.
- Modify: `config/initializers/admin_slots.rb` (`Admin::Slots.register "editor.rail.tabs", Admin::NotesScreen::RailPanelComponent`)
- Modify: `app/views/admin/pages/show.html.erb`, `post_form_component.html.erb` (the slot drawn after the rail's own panels; no `DrawerComponent` render; the editors' `note_counts` are handed in the slot context as today)
- Modify: `app/javascript/controllers/admin/notes/drawer_controller.js`:
  - opening dispatches `admin--ui--rail:reveal` from the drawer, and closing dispatches `admin--ui--rail:conceal`;
  - `admin--ui--rail:shown` on its panel loads the frame as a press of the Notes tab;
  - `data-notes-open`, `measure` and the header `ResizeObserver` go;
  - `beside` becomes "the rail is docked" (`closest("[data-rail-docked]")`), so a remembered open opens the tab at wide widths and never the slide-over;
  - the address rule (`notes=open`, `thread=`) is unchanged;
  - every `total` target is filled, the tab's included.
- Delete: `app/views/admin/shared/_notes_head.html.erb` and its render in `layouts/admin.html.erb`
- Modify: `app/assets/tailwind/content-spiel.tailwind.css`. **Removed:** the 400px column, `--admin-notes-width`, every `:root[data-notes-open]` rule (the tree's fold beside the notes and the hidden presence). **Added:**
  - below the threshold, the Notes panel when current is `position: fixed; top: var(--admin-top-offset); right: 0; bottom: 0; width: 400px` at `--cs-popover` with `--cs-shadow-3`, sliding in from the right (no motion under `prefers-reduced-motion`);
  - under 640px (`@media (max-width: 639.98px)`, the window, since the sheet covers the window) it is `inset-inline: 0`, full screen, with the drawer's Back button shown;
  - from 640px the × is shown.
- Modify: `app/javascript/controllers/admin/shell/tree_width_controller.js`, `tree_divider_component.rb`, `_tree_head.html.erb`. `data-tree-fits` and everything about the notes column go: `NOTES`, the `notes` value, the `data-notes-open` observer, `notesBeside`, the head script's sum. Its only reader was the tree's fold beside the notes column, and decision 2 ends that ("the tree never hides on its own"). The writer guard of Task 2 is updated to two names.
- Modify: `config/locales/admin/notes.en.yml` (keys move with the component; `tab` label)
- Test: rewrite `test/system/admin/notes_column_test.rb` as `notes_rail_test.rb` (delete the old file; its cases that still hold move over); `notes_drawer_test`, `notes_flow_test`, `notes_live_test`, `note_composer_test`, `notes_markers_test`, `tree_column_test`, `presence_test`; `test/integration/admin/notes_drawer_test.rb`, `test/integration/admin/tree_test.rb`, `test/components/admin/shell/tree_divider_component_test.rb`, `test/components/admin/notes_screen/*`, `test/lib/notes_boundary_test.rb` (the drawer exception goes from its named list), `test/lib/admin_design_rules_test.rb`, `test/system_test_seconds.yml`

**Interfaces:**
- Consumes: `admin--ui--rail` events (Task 3), the slot (Task 10), `mergeNoteList` (Task 9).

- [ ] **Step 1: Write the failing tests** in `notes_rail_test.rb`, at 1900 (docked), 1100 (slide-over) and 600 (sheet):
  - "the header's Notes button opens the Notes tab and nothing else on the page moves". Measure the blocks column's box before and after.
  - "a block's marker opens the Notes tab at that block's group".
  - "closing the notes returns to the tab that was current".
  - "Notes is a tab among the rail's own: arrows reach it".
  - "below the threshold the notes are a 400px panel over the canvas at elevation 3, not modal". Assert width 400, `box-shadow` equal to `--cs-shadow-3`, no `inert` anywhere, the page scrollable under it, and the blocks column's box unchanged. This is the cascade test of the slide-over over the docked panel.
  - "Escape closes the slide-over only while the focus is inside, and the focus goes back to the opener".
  - "under 640px the notes are a full-screen sheet with a way back".
  - "a remembered open opens the Notes tab on the next editor at a wide window, and opens nothing at a narrow one".
  - "?notes=open&thread= opens the thread in the tab, and the address follows the tab".
  - "a live note arriving while another tab is current fills the Notes tab's count" (two sessions).
  - "the tree never folds for the notes: opening them at 1280px leaves the tree a column".

  `admin_design_rules_test`: `test "nothing reads or writes data-notes-open or data-tree-fits"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** The drawer controller's header is rewritten: THE PANEL replaces THE DRAWER and "FROM 1024PX THE DRAWER IS A COLUMN", and the parts on focus, counts, the active block, the selection and the address stay. `tree_width_controller.js`'s "BESIDE THE NOTES (T3)" part goes.
- [ ] **Step 4: Run them, and verify they pass.** Then locally, one at a time: `notes_drawer_test`, `notes_flow_test`, `notes_live_test`, `note_composer_test`, `notes_markers_test`, `tree_column_test`, `tree_fold_test`, `editor_rail_test` and `presence_test`. Run `test/lib test/integration/admin test/components/admin` too. Expected: PASS.
- [ ] **Step 5: Commit** `feat: notes are the rail's Notes tab, a slide-over below it and a sheet on a phone` (body: `Advances #127`, `Advances #117`)

---

### Task 12: Notes' messages, mentions and Reply in E4

**Files:**
- Modify: `app/components/admin/notes_screen/thread_component.*`, `list_component.*`, `composer_component.*` (class changes only: message text `text-ink`, times `text-meta`, your own mention on `--cs-accent-tint` with accent words, Reply as the secondary `ButtonComponent`, the composer a well with its `--cs-field-line` bottom edge)
- Modify: `app/javascript/notes/merge.js` (the "NEW" divider's and the jump button's script-built classes follow, and still come from the server's `data-note-jump-class`)
- Test: `test/lib/admin_contrast_test.rb`, `test/components/admin/notes_screen/*`, `test/lib/admin_design_rules_test.rb`

- [ ] **Step 1: Write the failing contrast pairs**, in both themes, with the spec's figures as the floor:
  - message text on the panel, 17.6 / 12.9:1;
  - times, 6.3 / 6.4:1;
  - your own mention, 5.7 / 6.3:1;
  - Reply, 6.9 / 8.2:1;
  - the composer's edge, 3.2 / 3.6:1.

  Each is measured on the ground the Notes tab stands on (`--cs-rail` docked, `--cs-popover` in the slide-over) and asserted ≥ 4.5:1 (text) or 3:1 (edge).
- [ ] **Step 2: Run them, and verify the ones that fail** on the classes today.
- [ ] **Step 3: Change the classes.**
- [ ] **Step 4: Run** `test/lib test/components/admin/notes_screen`, and locally `note_composer_test` and `notes_flow_test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: notes' messages, mentions and Reply in E4` (body: `Advances #117`)

---

### Task 13: 3b's reference, CLAUDE.md and the pull request

**Files:**
- Modify: `docs/reference/notes.md` ("The drawer" becomes "The Notes tab": the slot, the reveal and conceal events, the slide-over, the sheet; the merge core named), `presence.md` (the header's people no longer hide for notes), `slots.md` (Task 10's shape, if not already complete), `live-editing.md` (`mergeBlockList`, the core), `cs-studio-shell-and-dashboard.md` (`data-tree-fits` gone; the tree never folds for notes), `design-system.md` ("E4: the right rail" gains the Notes tab and its elevations)
- Modify: `CLAUDE.md`:
  - the notes index line (`rail_panel_component`, `live/keep_merge.js`);
  - the presence line's three seams;
  - "Page tree's width": `--admin-tree-width` and `data-tree-folded` alone;
  - "Pitfalls, the write queue" ("notes, presence and an open editor are refreshed part by part" names the core).
- Test: `PGGSSENCMODE=disable bin/rails test test/lib`, `bin/rubocop`, `bin/rails zeitwerk:check`, `bin/changelog-guard`

- [ ] **Step 1: Write the reference and CLAUDE.md changes.**
- [ ] **Step 2: Run** the four checks. Expected: all pass.
- [ ] **Step 3: Write the PR body.** Base `studio-e4-3`. It says Advances #127 and #132, and lists for the owner to check: the slide-over's motion, the Notes tab's count, and the sheet's Back.
- [ ] **Step 4: Check no test run is left**: `pgrep -f "rails test"` prints nothing.
- [ ] **Step 5: Commit** `docs: E4 stage 3b in the reference and CLAUDE.md` (body: `Advances #117`)

**Documentation (3b), in `contentspiel-docs`:**
- pages:
  - `docs/editors/working-together/notes-on-content.md` (the Notes tab, the slide-over, the phone sheet);
  - `live-refresh-and-edit-reservations.md` (nothing moves when notes open);
  - `who-else-has-this-open.md` (the header's people stay with notes open);
  - `docs/editors/pages/the-page-tree.md` (the tree no longer folds for notes).
- screenshots: notes-rail (replaces notes-drawer), notes-slide-over, notes-sheet-phone, block-held-strip (retaken, in the rail).

---

## Browser tests

Run locally after `bin/rails tailwindcss:build`, one file at a time on a quiet machine, prefixed with `PGGSSENCMODE=disable`. **The implementer must run:**
- 3a:
  - `tree_fold_test`, `editor_rail_test`, `section_choice_test`, `editor_modules_test` and `editing_merge_test`;
  - `tree_column_test`, `tree_test`, `form_width_test`, `translation_layout_test` and `editor_header_test`;
  - `sections_settings_test`, `editing_claims_test`, `editing_holds_test`, `editing_held_test`, `autosave_test` and `autosave_unload_test`;
  - `drafts_test`, `chip_input_test`, `new_record_test` and `tokens_related_posts_and_starter_pages_test`.
- 3b:
  - `notes_rail_test`, `notes_drawer_test`, `notes_flow_test`, `notes_live_test`, `notes_merge_test`, `note_composer_test` and `notes_markers_test`;
  - `tree_column_test`, `tree_fold_test`, `editor_rail_test`, `editing_merge_test`, `editing_live_test` and `presence_test`.

**Likely to change, left to CI** (the whole browser suite runs per PR):
- the other seven `sections_*_test` files, `blocks_test` and `unsaved_order_test`;
- `changed_elsewhere_test`, `editing_take_over_test` and `presence_lists_test`;
- `note_files_test`, `note_inbox_test`, `note_edit_drafts_test`, `notes_alert_test`, `notes_view_only_test`, `note_thread_answers_test` and `note_reactions_test` (each reads `data-notes-open` or the drawer today; grep `notes-open\|notes-drawer\|tree-fits` in `test/system` and fix each hit in Task 11);
- `languages_test`, `unpublished_changes_test` and `view_only_test`.

A CI failure is fixed in the task that owns the file.
