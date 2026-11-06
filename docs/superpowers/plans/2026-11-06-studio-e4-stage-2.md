# CS Studio in E4, Stage 2 (the editor's canvas) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the page editor's blocks E4's four roles. Block cards float at elevation 1 with no border. A section is a structure frame whose head states its settings as words that open them. A tile shows its type, a heading and two or three lines of text. Adding is one "+ Add block" (primary) and a "+ Add" under each column. The tree's markers rest hidden, and the selected row carries an accent bar. On the way, the blocks script and the block answers are split (#132), SortableJS loads on demand (#124) and `sections_test` is split (#133).

**Architecture:** The look lives in the editor's components (`app/components/admin/editor_screen/`) and in rules of `content-spiel.tailwind.css` keyed on state attributes. The card's state edges (held, unavailable, notes open) become a 2px inset outline from the stylesheet instead of a border. A block type gains a `preview` declaration beside `summary`. `TileSummaryComponent` draws the preview, so its existing stream (`tile_summary_stream`) carries it after every save. The content-blocks controller's Turbo Stream answers move into responders under `app/controllers/admin/answers/`. `blocks_controller.js` keeps its targets and actions and hands each concern to a module of the `editor` topic (`app/javascript/editor/`). SortableJS is pinned `preload: false`, and every one of its four importers loads it with `import()`.

**Tech Stack:** Rails 8.1, ViewComponent with Lookbook previews, Tailwind v4 (`tailwindcss-rails`), Stimulus over import maps, SortableJS 1.15.7, Minitest with Capybara on Cuprite.

**Spec:** `docs/superpowers/specs/2026-11-06-studio-e4-design.md` (approved 2026-11-06). The sections this plan uses: "Decided on 2026-11-06" (3, 9), "The design, as decided", the screen table (page tree, page editor), "Stage 2", "Architecture-review findings", "The guard after E4" and "Constraints". Stage 1 as built: `docs/reference/design-system.md`, "E4: the redesign's first stage", PR #187 and `docs/superpowers/plans/2026-11-06-studio-e4-stage-1.md`. The drawings are the Design System artifact's `StudioCalmColourE4E5` (`.p4` and `.dp` rules) and `StudioCalmEditor` (B's editor and tree).

## Global Constraints

- **The public site keeps its look.** No file under `app/assets/tailwind/themes/`, `app/components/blocks/` or `app/views/layouts/public/` changes, and no `th-*` token either. A value that applies to CS Studio alone goes under `html[data-surface="studio"]` in `content-spiel.css`, after every `:root` block that sets the same property.
- **The scans cover CS Studio only.** Every new guard reads `ADMIN_SOURCES` / `ELEVATION_SOURCES` of `test/lib/admin_design_rules_test.rb`, never the visitor's two layouts.
- **Measured, not judged.** Every text pair is 4.5:1, and every control edge, state edge, state mark, icon and focus ring is 3:1, in both themes (`test/lib/admin_contrast_test.rb`). A section's frame groups; it is 2.6:1 against the canvas and needs no 3:1.
- **Type voice.** A label is `text-label`, and a count (a lane's "N blocks", a tree marker's number) is `text-count`. No `uppercase` with tracking, and no `font-mono` beyond `MONO_ALLOWED` (the Code block's preview is already allowed through `tile_summary_component.rb`).
- **Buttons come from `Admin::Ui::ButtonComponent`.** A menu trigger that looks like a button takes `button_class: Admin::Ui::ButtonComponent.classes(variant, size:)`. **Icons come from `Admin::Ui::IconChipComponent`**, and a block type's icon comes only through `EditorScreen::BlockIconComponent`.
- **Depth.** A shadow is `shadow-1`…`shadow-4` or `var(--cs-shadow-n)`. A radius is a radius token. A card has no border of its own.
- **No admin string is a literal.** Every new heading, button, word and aria label is a key in `config/locales/admin/editor_screen.en.yml`, read with `t(".key")`. A script's words come from `data-messages` (`messages_data(...)`). This includes the keyboard-move sentences that `blocks_controller.js` writes in English today.
- **Every write goes through `app/javascript/saving/queue.js`.** That covers a block move (through `admin--editor--blocks#move`), a section's settings save, an add and a duplicate. No hand-built request sits beside it.
- **Live editing keeps its meaning.** These keep their places and their ids:
  - the block form ids, `base_updated_at` and the `data-editing-*` marks (`data-editing-unit`, `-subject`, `-version`, `-part`, `-held`, `-strip-slot`, `-mark-slot`, `-announcer`);
  - `fieldset.admin-held`, the hold strip slot, the holder's avatar on a tile, the "Updated" mark and the `editor.block.markers` slot.

  Every ancestor of a unit, up to `#content-blocks-list`, carries an id (`editing/merge`).
- **Code asks `capability?(:container)` / `container?`**, never `block_type == "section"`.
- **No Turbo morphing**, no `turbo_refreshes_with`, no `broadcast_refresh`.
- **Stimulus conventions.** An identifier follows its path, and no inline handlers (`inline_handlers_test`). After a rename, search the tests by hand for the old name's fragments (`[data-controller*=…]`).
- **Comment rule (#117).** A comment states a current invariant, a hazard or a reason. Never a plan step, a review round, "stage N" or what used to be there. Every task rewrites the comments of the files it changes by this rule. The two "keeps `rounded-cs` … until stage 2" comments in `block_card_component.html.erb` and `section_card_component.html.erb` go.
- On macOS every test command is prefixed with `PGGSSENCMODE=disable`. Browser tests run only after `bin/rails tailwindcss:build`, never during a build, on a quiet machine (`sysctl -n vm.loadavg` well under the core count).
- Commits follow conventional commits and end with:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT`
  A task that carries a finding says so in its body: "Advances #132", "Advances #124", "Advances #133", "Advances #117".
- **#139 is not in this stage.** The spec gives stage 2 the deletion of `params[:after_id]` from `Admin::ContentBlocksController`. That was done in #186: `grep -rn after_id app test` finds nothing on 2a90538c. The PR body says so, and no task carries a #139 item.
- A look that the spec does not settle and that a person sees is marked **(owner)**. Each has a default that the build goes ahead on, and the PR lists them under "For the owner to check". The owner ruled ahead of time that this stage decides the card edges. They are still listed, so the owner can see them.

## Review Focus

1. **The section's settings form, moved from the head into a region under it, loses its unsaved text or its hold in a catch-up.** `editing/merge` keeps a unit by its ancestors' ids. Task 9 gives the region an id and adds an `editing_merge_test` case: "a section's settings holding unsaved text survive a catch-up with their region closed, and open again with the text".
2. **A preview drawn from what a person typed is markup, very long, or empty.** Task 6 adds these tests:
   - "a preview that looks like markup is drawn as text";
   - "a long preview is cut at PREVIEW_LENGTH and clamped to three lines";
   - "an empty rich-text block keeps today's empty line, not an empty heading".
3. **A gem's `preview` raises on a page.** That would be a 500 for the editor. Task 6 makes `TileSummaryComponent` fall back to the summary line, logging once per type as `own_summary` does. Test: "a type whose preview raises draws its summary line and logs once".
4. **SortableJS arrives after the controller connected, or after it left.** A drag pressed in that gap must not throw, and an element that left the page must not get a Sortable. Task 4 covers both:
   - an `editor_modules_test` case: "a controller disconnected before SortableJS arrives creates no Sortable and throws nothing";
   - `await_admin_controllers` waits for `[data-sortable="pending"]` to go, so no test drags too early.
5. **The keyboard and a screen reader lose a way in.** Tasks 9, 10 and 11 cover this:
   - Task 10: "+ Add block" opens by Enter, arrows walk the grid in reading order, and Escape gives the focus back to the trigger;
   - Task 9: a head word says `aria-expanded`, and Escape in the region gives the focus back to the word that opened it;
   - Task 11: a tree marker hidden at rest is still read ("2 missing translated fields" stays in the accessibility tree).

---

## Seams stage 3 (the right rail) takes from this stage

Stage 3a moves settings into the rail. It needs these to exist, named exactly:

| Seam | Made in | What stage 3 does with it |
|---|---|---|
| `#section-<id>-settings`, the one element that holds the section's settings form `#section-<id>-form` (`SectionCardComponent.settings_id(section)`) | Task 9 | At wide widths it moves this element into the Section panel, and puts it back under its head on deselect, on a fold and on `turbo:before-cache`. It is never cloned. |
| The head's words, `Admin::EditorScreen::SectionSettingsWordsComponent`, id `section-<id>-words`, each word a `<button aria-controls="section-<id>-settings" aria-expanded>` with `data-action="admin--editor--section#openSettings"` | Task 9 | The words are the only target that selects a section. Stage 3 points `aria-controls` at the Section panel at wide widths. |
| The event `admin--editor--section:open-settings`, cancelable, dispatched on the section card with `detail: { sectionId, region, field }` before the region opens in place | Task 9 | The rail's controller cancels it at wide widths and shows the region in its panel instead. Below the threshold nothing listens, and the region opens in place. |
| `Admin::Answers::Context`, `Admin::Answers::Answer`, `Stale`, `Held` | Task 2 | A rail panel re-rendered by id after a save (the `editor.rail.tabs` slot, 3b) is a responder's stream, not a controller's. |
| `PageSettingsFormComponent` and the post's `PostFormComponent` | untouched here | Stage 3 places them in the rail's first panel. |
| `.admin-content-blocks` with `FormColumn.classes` | untouched here | Stage 3 gives it the 900px column token. |
| The tree's head (`app/views/admin/shared/_tree_head.html.erb`) and `TreeNodeComponent#row_class` | Task 11 touches the row only | Stage 3 adds the fold button to the head. |

---

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `app/components/admin/editor_screen/publishing_state_component.html.erb`, `app/components/admin/ui/button_component.rb` (comment) | Discard changes… as `danger_text` | 1 |
| `app/controllers/admin/answers/*.rb` (new), `app/controllers/admin/content_blocks_controller.rb`, `app/controllers/concerns/admin/{autosave_responses,editing_claims,publishing_state}.rb` | one responder per outcome (#132) | 2 |
| `app/javascript/editor/*.js` (new), `app/javascript/controllers/admin/editor/blocks_controller.js`, `config/importmap.rb`, `app/views/admin/pages/show.html.erb` (`data-messages`) | the split blocks script (#132) | 3 |
| `config/importmap.rb`, `app/javascript/controllers/admin/{pages/tree,editor/groups,settings/sortable_rows}_controller.js`, `app/javascript/editor/drag.js`, `test/application_system_test_case.rb` | SortableJS on demand (#124) | 4 |
| `test/system/admin/sections_*_test.rb` (new), `test/support/sections_system_test_case.rb` (new), `test/system_test_seconds.yml` | `sections_test` split (#133) | 5 |
| `app/models/content_model/block_type_definition.rb`, `app/models/content_model/preview.rb` (new), `app/models/rich_text/document.rb`, `app/models/block_types/{rich_text,note,card,code,table}.rb`, `test/support/block_samples.rb` | the `preview` declaration | 6 |
| `block_card_component.*`, `app/assets/tailwind/content-spiel.{css,tailwind.css}` | block cards at elevation 1 and their state edges | 7 |
| `block_tile_component.*`, `tile_summary_component.*` | tiles that preview, and their states | 8 |
| `section_card_component.*`, `section_settings_words_component.rb` (new), `section_summary_component.rb`, `section_lanes_component.*`, `app/javascript/controllers/admin/editor/section_controller.js`, `app/controllers/admin/answers/block_drawing.rb` | the structure frame and its words | 9 |
| `block_picker_component.*`, `app/components/admin/ui/menu_component.*` | one add action | 10 |
| `app/components/admin/pages_screen/tree_node_component.*` | markers at rest, the accent bar | 11 |
| `docs/reference/*.md`, `CLAUDE.md`, `CHANGELOG.md` | the reference | 12 |

---

### Task 1: "Discard changes…" is `danger_text`

**Files:**
- Modify: `app/components/admin/editor_screen/publishing_state_component.html.erb:13`
- Modify: `app/components/admin/ui/button_component.rb` (the head comment that names the ruling)
- Test: `test/components/admin/editor_screen/header_component_test.rb`

**Interfaces:** none.

- [ ] **Step 1: Write the failing test.** In `header_component_test.rb` add `test "Discard changes… throws work away, so it is the danger_text button"`. It renders the live page with an edited title as the existing "Discard changes… is offered…" test does, and asserts:

```ruby
button = page.find("header #publishing-actions button", text: "Discard changes…", visible: :all)
assert_equal Admin::Ui::ButtonComponent.classes(:danger_text), button[:class]
```

- [ ] **Step 2: Run it, and verify it fails** on the tertiary classes: `PGGSSENCMODE=disable bin/rails test test/components/admin/editor_screen/header_component_test.rb`.
- [ ] **Step 3: Change the variant to `:danger_text`.** Rewrite the ButtonComponent comment's sentence to state the rule: "a button that throws work away (Discard changes…) is `:danger_text`". The line about the owner's earlier tertiary ruling goes.
- [ ] **Step 4: Run it, and verify it passes.** Then run `test/components/admin/ui/button_component_test.rb` and `test/lib/admin_design_rules_test.rb`.
- [ ] **Step 5: Commit** `fix: Discard changes… is the danger text button`

---

### Task 2: One responder per outcome for the block answers (#132)

**Files:**
- Create in `app/controllers/admin/answers/`:
  - `answer.rb`, `context.rb`, `publishing_streams.rb`, `stale.rb`, `held.rb`;
  - `block_drawing.rb`, `block_saved.rb`, `block_refused.rb`, `block_gone.rb`.
- Modify: `app/controllers/admin/content_blocks_controller.rb` (the actions keep their decisions; every private stream builder moves out)
- Modify: `app/controllers/concerns/admin/autosave_responses.rb` (`refuse_stale_autosave` renders `Stale`), `editing_claims.rb` (`refuse_held` renders `Held`), `publishing_state.rb` (`publishing_state_streams` calls `PublishingStreams.for`)
- Create in `test/controllers/admin/answers/`: `block_saved_test.rb`, `block_refused_test.rb`, `block_gone_test.rb`, `stale_test.rb`, `held_test.rb`
- Test (unchanged, must stay green): `test/integration/admin/content_blocks_test.rb`, `test/integration/admin/pages_test.rb`, `posts_test.rb`, `editing_test.rb` (whatever exercises the 409s; grep `:conflict`)

**Interfaces:**
- Produces:
  - `Admin::Answers::Answer = Data.define(:streams, :status)`: `streams` is an Array of rendered `<turbo-stream>` strings, `status` a Rack status symbol.
  - `Admin::Answers::Context = Data.define(:view, :page, :locale, :url_options, :holds, :viewer)`, with `#turbo_stream` → `Turbo::Streams::TagBuilder.new(view)` (memoized) and `#render(component)` → `view.render(component)`.
  - `Admin::Answers::PublishingStreams.for(record, view:, url_options:) -> Array`: the body of today's `publishing_state_streams`. The concern's method becomes `PublishingStreams.for(record, view: view_context, url_options: admin_url_options)`.
  - `Admin::Answers::Stale.new(view:).answer(record:, status_id:, error_prefix:, reload_url:, since:, live:) -> Answer` (status `:conflict`): today's `stale_streams`.
  - `Admin::Answers::Held.new(view:).answer(subject:, hold:, viewer:, status_id:, error_prefix:, live:) -> Answer` (status `:conflict`): today's list in `refuse_held`.
  - `Admin::Answers::BlockDrawing`, a module included by the three block responders. It holds the builders moved from the controller under their current names: `tile_streams`, `copy_tile_streams`, `insertion_stream`, `removal_streams`, `move_streams`, `blocks_list_stream`, `section_structure_streams`, `section_save_streams`, `section_count_streams`, `block_icon_streams`, `tile_summary_stream`, `panel_removal_streams`, `card_for`, `panel_component`, `tile_component`, `picker_error_stream`, `fresh_outline`, `top_level_blocks`. Each reads `context` where it read `@page`, `admin_locale`, `admin_url_options`, `holds`, `Current.user` and `helpers`, and uses `context.render(...)` for `render_to_string(...)`.
  - `Admin::Answers::BlockSaved.new(context)`:
    - `#created(block, section:)` → `:created`;
    - `#updated(block, autosave:, refused_media: nil, layout_before:, columns_before:)` → `:ok`, where `autosave:` is the Array from `autosave_stream`;
    - `#removed(block, kept_ids:, section:)` → `:ok`, carrying the `notes-counts` stream;
    - `#reordered(origins:, structural:, before:, undo:, undo_url:)` → `:ok`, with the Undo toast, the "Order restored." toast and the list for `undo: true`;
    - `#duplicated(copy, source:)` → `:created`.
  - `Admin::Answers::BlockRefused.new(context)`:
    - `#created(result, section:)`, `#reordered(result, structural:)`, `#refused(result)` (destroy and duplicate): each `:forbidden` when `result.denied?`, else `:unprocessable_entity`;
    - `#updated(block, result:, autosave:, refused_media: nil)`: its status is `autosave_status(result)`'s rule, moved here as `#status_for(result)`.
  - `Admin::Answers::BlockGone.new(context).answer` → `:gone`. `MESSAGE = "This block was deleted"` moves here from `ContentBlocksController::GONE_MESSAGE`.
  - `Admin::ContentBlocksController#answer(answer)` = `render(turbo_stream: answer.streams, status: answer.status)`, and `#answers_context` (memoized `Context`).
- `Admin::Answers` shadows no top-level domain (`test/lib/admin_namespace_shadow_test.rb` stays green). The classes live under `app/controllers` because they draw views and know routes: they are the controller layer, out of `dependency_direction_test`'s scope by design.

- [ ] **Step 1: Write the failing responder tests.** Each is an `ActionView::TestCase` that builds a `Context` from `view`, `pages(:…)`/`create_page`, `locale: :en`, `url_options: {}`, `holds: Editing::Holds.none`, and `viewer: users(:one)`. A helper `streams_of(answer)` parses `answer.streams.join` with `Nokogiri::HTML5.fragment` into `[[action, target], …]`. Tests:
  - `block_saved_test.rb`:
    - "a block added to the page's list is one append to the list, and the publishing chip when the page is live";
    - "a block added to a column is its panel, its tile and the section's count, and no card";
    - "a reorder of the list that changed the order offers Undo, and one that changed nothing offers nothing";
    - "an undone reorder redraws the list with 'Order restored.'";
    - "a structural move answers each moved block in its new shape";
    - "a duplicate in a column is drawn after its source's tile".

    Each asserts the exact `[action, target]` list and `answer.status`.
  - `block_refused_test.rb`:
    - "a refused add into a column says why and redraws the section's lanes, unless it was denied";
    - "a refused structural move redraws the whole list, a refused list order does not";
    - "a denial is 403 and anything else 422".
  - `block_gone_test.rb`: "a gone block is 410 with its message in the alert slot".
  - `stale_test.rb`: "a stale save is 409: the stale status, the changed-elsewhere bar and the form's toast removed".
  - `held_test.rb`: "a held save is 409: the held status naming the holder, the lost strip and the form's toast removed".
- [ ] **Step 2: Run them, and verify they fail** with `NameError` for `Admin::Answers`: `PGGSSENCMODE=disable bin/rails test test/controllers/admin/answers`.
- [ ] **Step 3: Move the builders into the classes named above.** The actions keep their decisions: lookups, `one_value`, `moved_from_param`, claims, the service calls and which responder is asked. Each ends in `answer(...)`. `refuse_stale_autosave` and `refuse_held` keep their signatures and return values, and render the responder's answer. No stream's target, order or content changes. The long comments travel with the methods they explain, rewritten by the comment rule. A comment that described the controller's flow stays on the action.
- [ ] **Step 4: Run the tests, and verify they pass.** Run `test/controllers/admin/answers`, then `test/integration/admin` and `test/lib`. Expected: PASS. `content_blocks_test.rb` is the proof that no answer changed.
- [ ] **Step 5: Commit** `ref: the block answers are one responder per outcome` (body: `Advances #132`, `Advances #117`)

---

### Task 3: The blocks script split by concern (#132)

**Files:**
- Create in `app/javascript/editor/`:

  | Module | What it holds |
  |---|---|
  | `containers.js` | pure reads of the page's containers |
  | `drag.js` | SortableJS options and the inert clone |
  | `move_queue.js` | the queued send of a move, its put-back and its answer |
  | `menu_moves.js` | Move up/down, Move to column…, Move into section…, Move out of section |
  | `keyboard_moves.js` | the handle's Space / arrows / Escape path |
  | `adding.js` | holding add, duplicate, delete and Undo writes in the queue; focusing a duplicate's copy |

- Modify: `app/javascript/controllers/admin/editor/blocks_controller.js` (targets, values, Stimulus callbacks and the actions named in markup, each delegating; no more than 250 lines)
- Modify: `config/importmap.rb` (`pin_all_from "app/javascript/editor", under: "editor", preload: "admin"`, with a comment saying what the folder holds)
- Modify: `app/views/admin/pages/show.html.erb` (the `data-messages` list gains the four new keys)
- Modify: `config/locales/admin/editor_screen.en.yml`, under `block_moves`:
  - `picked_up: "Picked up %{block}. %{position}"`
  - `dropped: "Dropped %{block}. %{position}"`
  - `cancelled: "Cancelled. %{block} is back where it was."`
  - `position: "Position %{position} of %{count}."`
- Create: `test/system/admin/editor_modules_test.rb`
- Test: `test/lib/source_layout_test.rb` (the new module folder has its topic), `test/integration/public_javascript_test.rb`

**Interfaces:**
- `editor/containers.js` exports:
  - `itemsOf(container) -> Element[]`
  - `placeOf(container) -> { section_id, column }`
  - `isClosed(container) -> boolean`
  - `accepts(lane, dragged) -> boolean`
  - `snapshot(containers) -> Map`
  - `besideSection(event, pointer) -> boolean`
  - `refreshMoveState(containers, openLanes)`
- `editor/drag.js` exports:
  - `sortableOptions({ put, onStart, onEnd }) -> Object`: the handle, classes, fallback and group exactly as today;
  - `makeCloneInert(clone)`.
- `editor/move_queue.js` exports `class MoveQueue`:
  - `constructor(host)`, where `host` is the controller. It reads `host.listTarget`, `host.containers()`, `host.reorderUrlValue`, `host.generation`, `host.application`, `host.element` and `host.picked`, and calls `host.sayMoving()`, `host.focusItem(item)` and `host.announce(text)`.
  - Methods: `move(item, from, before, { focus })`, `reorder(before)` and `get holds()` (the count `moveHolds` today).
  - The private parts carry over unchanged: `queueMove`, `sendMove`, `takeTurn`, `settle`, `putBack`, `taken`, `takenFrom`, `followRedraw`, `renderKeepingForms`, `formsHoldText`, `formState`, `sendHeldEdits`.
- `editor/menu_moves.js` exports `class MenuMoves`: `constructor(host, queue)`, with `up(item)`, `down(item)`, `askWhere(item)`, `moveTo()` and `out(item)`.
- `editor/keyboard_moves.js` exports `class KeyboardMoves`: `constructor(host, queue)`, with `key(event, card)`, `blur(handle, card)`, `cancel(card, { refocus })` and `get picked()`. Its sentences come from `messages(host.element).t("components.editor_screen.block_moves.<key>", …)`.
- `editor/adding.js` exports `watchWrites(host) -> () => void`, which attaches the listeners and returns their removal, and `focusCopy(host, mutations)`.
- `blocks_controller.js` keeps these public members:
  - the Stimulus actions `toggle`, `moveUp`, `moveDown`, `askWhere`, `moveTo`, `moveOut`, `key` and `blur`;
  - `move(item, from, before, options)`, the one sender `CLAUDE.md` names;
  - `dragging`, `sayMoving()` and `containers()`;
  - the `moving` and `toggled` events.

  Browser tests and `admin--editing--live` read these. It still imports `saving/queue` and `saving/order_request` only through `editor/move_queue.js`.

- [ ] **Step 1: Write the failing module test.** `editor_modules_test.rb` visits an editor with a two-column section and runs each module through `page.evaluate_async_script` with `import("editor/containers")`, as `mind_graph_modules_test` does. Tests:
  - "itemsOf counts only an element that stands for a block, and placeOf names the section and its column, or neither";
  - "refreshMoveState disables the ends of each container and Move to column… in a one-column section";
  - "a closed lane accepts nothing, and no lane accepts a section";
  - "besideSection lets the list sort past a section only from above or below its lanes" (rects built by hand);
  - "the keyboard path's sentences are the locale's words" (pick up, step, drop, cancel; assert the announcer's text equals the four keys' English).
- [ ] **Step 2: Run it, and verify it fails** (the module is not found): `PGGSSENCMODE=disable bin/rails test test/system/admin/editor_modules_test.rb`.
- [ ] **Step 3: Move the code into the modules.** The moves are mechanical: each method's body moves as it is. The comments move with the code they explain and are rewritten by the comment rule. The controller's header comment shrinks to what the controller still is (its targets, and which module holds which concern).
- [ ] **Step 4: Run the module test, then the guards and the block browser tests.** First `test/system/admin/editor_modules_test.rb`, then `test/lib test/integration/public_javascript_test.rb`. Then, one at a time on a quiet machine, `blocks_test`, `unsaved_order_test`, `editing_live_test`, `test/system/content_blocks_drag_test.rb` and `sections_test`. Expected: PASS with no change to any of them.
- [ ] **Step 5: Commit** `ref: the blocks script is split by concern into the editor's modules` (body: `Advances #132`, `Advances #117`)

---

### Task 4: SortableJS on demand (#124)

**Files:**
- Modify: `config/importmap.rb` (`pin "sortablejs", preload: false # @1.15.7`, and the head comment no longer lists SortableJS among what `admin` preloads)
- Modify: `app/javascript/editor/drag.js` (`loadSortable()`)
- Modify:
  - `app/javascript/controllers/admin/editor/blocks_controller.js`
  - `app/javascript/controllers/admin/editor/groups_controller.js`
  - `app/javascript/controllers/admin/pages/tree_controller.js`
  - `app/javascript/controllers/admin/settings/sortable_rows_controller.js`
- Modify: `test/application_system_test_case.rb` (`await_sortables`, called from `await_admin_controllers`)
- Test: `test/integration/public_javascript_test.rb`, `test/lib/admin_design_rules_test.rb`, `test/system/admin/editor_modules_test.rb`, `test/system/admin/entry_helpers_test.rb`

The spec names the blocks script, but three more controllers import SortableJS statically: the page tree, the translation tab's groups and Settings' language rows. `registerControllers` imports every `controllers/admin/*` module on every CS Studio screen, so a single static import still fetches SortableJS everywhere. "A non-editing screen loads no SortableJS" therefore needs all four on `import()`.

**Interfaces:**
- `editor/drag.js` exports `loadSortable() -> Promise<Sortable>`, the one `import("sortablejs")` that resolves to its default export. The editor's two controllers use it. The tree and settings controllers call `import("sortablejs")` themselves, because a module folder serves one topic.
- A controller that makes Sortables sets `data-sortable="pending"` on its element in `connect`, and `data-sortable="ready"` once they are made. It makes none if `this.element.isConnected` is false when the import resolves.
- `await_sortables(wait: 8)` in `ApplicationSystemTestCase` waits until no `[data-sortable="pending"]` is left, with the message "SortableJS never arrived: [data-sortable=pending] stayed".

- [ ] **Step 1: Write the failing tests.**
  - `public_javascript_test.rb`: `test "a CS Studio screen with nothing to drag preloads no SortableJS, and the editor fetches it on demand"`. GET `/cs-studio` (the dashboard) and `/cs-studio/pages/:id`, and on both assert that `modulepreloads.none? { |href| href.include?("sortablejs") }`. Assert that the import map still maps `sortablejs`.
  - `admin_design_rules_test.rb`: `test "no script imports SortableJS statically: it is loaded on demand"`. No file under `app/javascript` matches `/^\s*import\s+\w+\s+from\s+["']sortablejs["']/`. A sample test proves the pattern matches `import Sortable from "sortablejs"` and not `import("sortablejs")`.
  - `editor_modules_test.rb`: "a controller disconnected before SortableJS arrives creates no Sortable and throws nothing". The test holds `import` by visiting with a delayed module, or detaches the list element before `loadSortable()` resolves, then asserts `Sortable.get(list)` is undefined and no JS error was collected.
  - `entry_helpers_test.rb`: "visit_editor returns only after the editor's Sortables are made". Assert `[data-sortable=ready]` on the blocks section right after the call.
- [ ] **Step 2: Run them, and verify they fail:** `PGGSSENCMODE=disable bin/rails test test/integration/public_javascript_test.rb test/lib/admin_design_rules_test.rb`.
- [ ] **Step 3: Implement.** Each controller's `connect` starts the import and makes its Sortables in the `then`. `disconnect` destroys what exists, and a resolve after disconnect makes nothing. The lane callbacks of `blocks_controller.js` (`laneTargetConnected`) wait on the same promise. A lane that connects before it resolves is made with the rest.
- [ ] **Step 4: Run the unit tests, then the drag browser tests** one at a time: `blocks_test`, `test/system/content_blocks_drag_test.rb`, `tree_test`, `languages_test`, `translation_layout_test`, `editing_live_test` and `entry_helpers_test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: SortableJS is loaded only where something is dragged` (body: `Advances #124`)

---

### Task 5: `sections_test` split by behaviour (#133)

**Files:**
- Create: `test/support/sections_system_test_case.rb`, `Admin::SectionsSystemTestCase < ApplicationSystemTestCase`. It holds today's `setup` and the shared helpers: `open_editor`, `tile`, `face`, `panel`, `caption`, `hold_first_save`, `count_writes`, `lane`, `tiles_in`, `cards_in_list`, `assert_order_eventually`, `blocks_controller`, `drop_into`, `script_writes`, `section_card`, `focus_is_on`. It is required from `test/application_system_test_case.rb`.
- Create these files, each `< Admin::SectionsSystemTestCase` and holding the tests of today's line ranges, unchanged, with the helpers used only there:

  | File | Lines of today's file | Behaviour |
  |---|---|---|
  | `test/system/admin/sections_panels_test.rb` | 55–301 | tiles and their forms |
  | `test/system/admin/sections_adding_test.rb` | 302–386 | adding into lanes |
  | `test/system/admin/sections_settings_test.rb` | 387–577 | layout, background, width |
  | `test/system/admin/sections_removing_test.rb` | 578–788 | remove, delete, duplicate, collapse |
  | `test/system/admin/sections_moves_test.rb` | 789–1434 | moves by script |
  | `test/system/admin/sections_pointer_test.rb` | 1435–1545 | the pointer |
  | `test/system/admin/sections_menu_moves_test.rb` | 1546–1997 | the menus and the keyboard |
  | `test/system/admin/sections_translation_and_unavailable_test.rb` | 1998–end | the translation tab, an unregistered type |

- Delete: `test/system/admin/sections_test.rb`
- Modify: `test/system_test_seconds.yml`. The `sections_test.rb: 385.8` entry is replaced by one entry per new file. Each takes the old seconds in proportion to its count of tests (95 in all), rounded to 0.1, and the eight sum to 385.8.
- Modify: `CLAUDE.md` and `docs/reference/content-blocks-and-types.md`, wherever they name `sections_test.rb`.

**Interfaces:** the helpers keep their names and signatures. Tasks 9 and 10 add tests to `sections_settings_test.rb` and `sections_adding_test.rb`.

- [ ] **Step 1: Check the count.** `grep -c '^  test "' test/system/admin/sections_test.rb` must print 95. Record it.
- [ ] **Step 2: Move the tests and the helpers.** The test names and bodies stay unchanged.
- [ ] **Step 3: Verify.**
  - `grep -h -c '^  test "' test/system/admin/sections_*_test.rb | paste -sd+ | bc` prints 95.
  - `PGGSSENCMODE=disable bin/rails test test/lib/test_shards_test.rb` passes ("every system test file is in exactly one shard", "no system shard is much heavier than a fair share").
  - Run each new file once, locally, one at a time.
- [ ] **Step 4: Commit** `test: sections_test split by behaviour into eight files` (body: `Advances #133`)

---

### Task 6: A block type's tile preview

**Files:**
- Create: `app/models/content_model/preview.rb`
- Modify: `app/models/content_model/block_type_definition.rb` (`preview`, `PREVIEW_LENGTH`)
- Modify: `app/models/rich_text/document.rb` (`#preview`)
- Modify: `app/models/block_types/{rich_text,note,card,code,table}.rb`
- Modify: `test/support/block_samples.rb`
- Test:
  - `test/models/content_model/block_type_definition_test.rb`, `test/models/built_in_types_test.rb`, `test/models/rich_text/document_test.rb`;
  - a new shared check in `test/models/block_types/samples_preview_test.rb`.

**Interfaces:**
- `ContentModel::Preview = Data.define(:heading, :text, :mono)`, with `heading` and `text` Strings or nil and `mono` defaulting to false. `#blank?` is true when both are blank. `.new` cuts `text` at `ContentModel::BlockTypeDefinition::PREVIEW_LENGTH = 240` with `String#truncate`, and `heading` at `SUMMARY_LENGTH` (80).
- `BlockTypeDefinition#preview(callable = nil)` is a reader and writer like `summary`: a callable taking `(block, locale:)` and answering a `ContentModel::Preview` or nil. Anything else is refused at registration with the message "`preview` is a callable taking the block and `locale:`". At draw time, an answer that is not a Preview raises `ArgumentError`, which the tile catches (Task 8).
- `RichText::Document#preview -> ContentModel::Preview`. The heading is the plain text of the first `heading` node. The text is the plain text of the paragraphs and list items after it, joined with spaces. The plain text comes through `plain_text_of`, the same walk `to_markdown` dumps, so no Markdown syntax reaches the tile.
- The built-ins' previews (only these; image, form, post list and section declare none and keep their summary line):

  | Type | Heading | Text |
  |---|---|---|
  | rich text | the first heading of its body | the rest of the body (`body_document(locale:).preview`) |
  | note | its title, else its kind's word | its body's text |
  | card | its title | its text |
  | code | its file name, else its language's label | the first three lines of its code, `mono: true` |
  | table | its caption | its first row's cells joined with " · " |

- `test/support/block_samples.rb` gains `assert_preview_shows_a_sample_value(type)`. It builds `sample_block` and calls `type.preview.call(block, locale: "en")`. It asserts that `[preview.heading, preview.text].join(" ")` includes one of the sample's own values: a settings value, a translation's value, or a run of 8 or more characters of the body's plain text.

- [ ] **Step 1: Write the failing tests.**
  - `block_type_definition_test.rb`:
    - "preview is a callable taking the block and locale:, and anything else is refused, the type's name first";
    - "a type that declares no preview answers nil".
  - `document_test.rb`:
    - "preview takes the first heading and the text after it, without Markdown";
    - "a body with no heading previews its text with no heading";
    - "an empty body previews as blank".
  - `built_in_types_test.rb`: "the five types that preview declare one, and image, form, post list and section declare none".
  - `samples_preview_test.rb`: `test "every type with a preview shows one of its sample's values"`, run over `BlockTypes.all.select(&:preview)`, gallery/album and test types included (`with_every_type`).
  - A case in `block_type_definition_test.rb`: "a preview's text is cut at PREVIEW_LENGTH and its heading at SUMMARY_LENGTH".
- [ ] **Step 2: Run them, and verify they fail:** `PGGSSENCMODE=disable bin/rails test test/models/content_model test/models/rich_text/document_test.rb test/models/built_in_types_test.rb test/models/block_types`.
- [ ] **Step 3: Implement** the declaration, `Preview`, `Document#preview` and the five built-ins' callables. Each callable is a module method of its type (`BlockTypes::Code.preview(block, locale:)`), as `summary` is.
- [ ] **Step 4: Run them, and verify they pass.** Then run `test/models test/values/theme`. The theme contract is unchanged: `preview` is no theme method.
- [ ] **Step 5: Commit** `feat: a block type declares the preview its tile shows`

---

### Task 7: Block cards at elevation 1, and their state edges

**Files:**
- Modify: `app/components/admin/editor_screen/block_card_component.{rb,html.erb}`
- Modify: `app/views/admin/pages/show.html.erb` (`#content-blocks-list` gap)
- Modify: `app/assets/tailwind/content-spiel.css` (a token: `--cs-tile-raised`), `content-spiel.tailwind.css` (the edge rules)
- Test: `test/components/admin/editor_screen/block_card_component_test.rb`, `test/lib/admin_design_rules_test.rb`, `test/lib/admin_contrast_test.rb`, `test/integration/design_tokens_test.rb`

**The look** (drawn, `.dp .card` and `.calm .bhd`):
- The card is `admin-block-card rounded-card bg-surface shadow-1`, with no `border` utility.
- The head is `admin-block-card__head flex items-center gap-2 px-3 pt-3 pb-1`, with no `border-b` and no `hover:bg-sunken`. The type chip is first after the handle, as Stage 1 drew it.
- The list is `flex flex-col gap-5.5` (22px).

**The state edges (owner: this stage decides them, per the ruling).** A card's state was a border colour. It becomes a 2px outline inside the card's edge (`outline: 2px solid var(--edge); outline-offset: -2px`), drawn by the stylesheet from a state attribute. No class utility draws it, so nothing changes size and no shadow is overwritten.

| State | Attribute (who writes it) | Edge |
|---|---|---|
| held by someone else (`read_only_hold?`) | `data-card-edge="held"` (the component) | `var(--cs-field-line)` |
| its type is gone (`unavailable?`) | `data-card-edge="unavailable"` (the component) | `var(--cs-danger)` |
| its thread is open in the notes drawer | `data-notes-active` (`admin--notes--drawer#markActive`, unchanged) | `var(--cs-accent)` |

When states combine, unavailable beats notes-active, and notes-active beats held, by rule order. Stage 6 re-values held and notes-active to the people frame. Each edge stands with its words: the hold strip, "Unavailable …", the open thread.

**New token** (`content-spiel.css`, both scheme blocks; `--color-tile-raised` in `@theme inline`): `--cs-tile-raised` is `#ffffff` in light and `#1f2a3d` in dark. It is the ground of a tile under the pointer or focused (drawn: dark `.dp .tile.st0/.st1 { background: var(--e2) }`).

**Interfaces:**
- `BlockCardComponent#card_edge -> "held" | "unavailable" | nil`, written as `data-card-edge` on the wrapper.

- [ ] **Step 1: Write the failing tests.**
  - `block_card_component_test.rb`:
    - "a card is a raised tile with no border of its own and no rule under its head";
    - "a held card says so in data-card-edge=held, an unavailable one in data-card-edge=unavailable, and neither carries a border utility".
  - `admin_design_rules_test.rb`:

```ruby
EDITOR_CARDS = %w[block_card_component.html.erb block_tile_component.html.erb].map { |f| "app/components/admin/editor_screen/#{f}" }
test "the editor's cards and tiles draw no border utility: their edges are the stylesheet's state outlines" do
  # no /(?<![\w-])border(?:-(?:line|line-strong|danger|accent|field-line))?(?=[\s"'])/ on the wrapper lines of EDITOR_CARDS
  # and the stylesheet has outline rules for [data-card-edge="held"], [data-card-edge="unavailable"], [data-notes-active]
end
```

  - `admin_contrast_test.rb`: `test "a card's state edge is 3:1 or better against the card and the canvas, in both schemes"`. It measures `--cs-field-line`, `--cs-danger` and `--cs-accent` against `--cs-surface` and `--cs-paper`. Also `test "words on a raised tile are readable: ink, dim and meta 4.5:1 on --cs-tile-raised"`.
  - `design_tokens_test.rb`: `--cs-tile-raised` is in both blocks and mapped.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Delete the "keeps `rounded-cs` … until stage 2" comment.
- [ ] **Step 4: Run** `test/components/admin/editor_screen test/lib test/integration/design_tokens_test.rb`, then locally `blocks_test`, `editing_held_test` and `notes_markers_test`. Expected: PASS. A browser test that finds a card by `border-*` changes to `[data-card-edge]`.
- [ ] **Step 5: Commit** `feat: block cards float at elevation 1, their state edges drawn inside them`

---

### Task 8: Tiles that preview, and their states

**Files:**
- Modify: `app/components/admin/editor_screen/tile_summary_component.{rb,html.erb}`, `block_tile_component.html.erb`
- Modify: `app/assets/tailwind/content-spiel.tailwind.css` (`.admin-block-tile` rules, `.admin-drag-ghost`)
- Test: `test/components/admin/editor_screen/tile_summary_component_test.rb`, `block_tile_component_test.rb`, `test/lib/admin_design_rules_test.rb`, `test/lib/admin_contrast_test.rb`

**The face** (drawn `.calm .tile`, `.tk`, `.tile h4`, `.tile p`):
- A first line holds the type chip at 22px (`BlockIconComponent` `place: :tile`) and the type's name in `text-label text-meta`.
- Under it, the preview's heading as `block truncate text-base font-semibold text-ink`. The drawing is 17px; `text-base` is the nearest token, because no arbitrary size is written.
- Under that, its text as `line-clamp-3 text-sm text-dim`, with `font-cs-mono` when `preview.mono`.
- A type with no preview, or with a blank one, keeps today's summary line under the first line.
- The face pads `px-3.5 py-3`. The tile's name stays the face's first span child, which the move announcement reads.
- Every word is ERB-escaped: no `raw`, no `html_safe`.

**The states** (stylesheet; drawn `.dp .tile.st0/.st1/.st2`):

| State | Selector | Look |
|---|---|---|
| at rest | `.admin-block-tile` | `border-radius: var(--cs-radius-tile); background: var(--cs-surface); box-shadow: var(--cs-shadow-1)`, no border |
| under the pointer | `:hover` | `box-shadow: var(--cs-shadow-2); background: var(--cs-tile-raised)`. The drawing lifts it 2px. This plan does not move it, so nothing shifts under a pointer that is dragging or clicking **(owner)**. |
| open or focused | `:has(> .admin-block-tile__face[aria-expanded="true"])`, `:has(> .admin-block-tile__face:focus-visible)` | `box-shadow: var(--cs-shadow-3), 0 0 0 2px var(--cs-accent); background: var(--cs-tile-raised)` |
| its thread open | `[data-notes-active]` | the 2px accent outline of Task 7 |
| dragged | `.admin-drag-chosen`, `.admin-drag-fallback` | unchanged: `var(--cs-shadow-4)`, with `var(--cs-popover)` as the ground |
| the drop place | `.admin-drag-ghost` | `border: 1.5px dashed var(--cs-line-strong); border-radius: var(--cs-radius-tile)` |

The face drops its own `focus-visible:outline-*` classes, because the tile's ring is the focus ring. If a focus guard refuses a pressable without a focus outline, the face keeps its outline and the tile's focus selector goes; the open state keeps the ring.

**Interfaces:**
- `TileSummaryComponent#preview -> ContentModel::Preview | nil` calls `definition.preview`. It answers nil when there is none, when it is blank, or when the type is outside the CMS and its callable raised. That raise is logged once per definition, exactly as `own_summary` logs, and the summary line is drawn instead.
- The element keeps `id: TileSummaryComponent.dom_id(block)`. `Admin::Answers::BlockDrawing#tile_summary_stream` already replaces it after every save of a block in a column, so the preview follows a save with no new stream.

- [ ] **Step 1: Write the failing tests.**
  - `tile_summary_component_test.rb`:
    - "a rich-text tile shows its first heading and two or three lines of its text";
    - "a code tile shows its file name and its first lines in the mono look";
    - "a type with no preview keeps its summary line";
    - "a preview that looks like markup is drawn as text" (`<script>` in a rich text's paragraph; `assert_no_selector "script"` and `assert_text "<script>"`);
    - "a long preview is cut at PREVIEW_LENGTH and clamped to three lines" (`line-clamp-3`);
    - "an empty rich-text block keeps today's empty line, not an empty heading";
    - "a type whose preview raises draws its summary line and logs once" (a `TestTypes` type owned by `test`, two renders, one log line).
  - `block_tile_component_test.rb`: "the face holds the type chip and the name first, then the preview, and the name is the face's first span".
  - `admin_contrast_test.rb`: "the open tile's accent ring is 3:1 or better against the frame's ground and the canvas" (`--cs-accent` on `--cs-paper` and `--cs-structure-tint`).
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `test/components/admin/editor_screen test/lib`, then locally `rich_text_test`, `code_block_test`, `table_block_test`, `note_block_test`, `card_block_test` and `editor_fields_test`. Expected: PASS. A test reading a tile's single line is rewritten to the heading and the text.
- [ ] **Step 5: Commit** `feat: a tile shows its type, a heading and a few lines of its text`

---

### Task 9: A section as a structure frame, its settings as words

**Files:**
- Modify: `app/components/admin/editor_screen/section_card_component.{rb,html.erb}`
- Create: `app/components/admin/editor_screen/section_settings_words_component.rb`
- Modify: `section_summary_component.rb` (the count only), `section_lanes_component.html.erb` (the lane label as `text-label`, the lanes `gap-4`)
- Modify: `app/javascript/controllers/admin/editor/section_controller.js` (`settings` target, `openSettings`, `closeSettings`, Escape)
- Modify: `app/controllers/admin/answers/block_drawing.rb` (`section_save_streams` also replaces the words)
- Modify: `app/assets/tailwind/content-spiel.tailwind.css` (`.admin-section-card`, `__head`, `__settings`, `.admin-section-word`)
- Modify: `config/locales/admin/editor_screen.en.yml`
- Test:
  - `test/components/admin/editor_screen/section_card_component_test.rb` and `section_settings_words_component_test.rb` (new);
  - `test/controllers/admin/answers/block_saved_test.rb`, `test/lib/admin_contrast_test.rb`;
  - `test/system/admin/sections_settings_test.rb`, `test/system/admin/editing_merge_test.rb`.

**The look** (drawn `.p4 .sec`, `.p4 .shd`, `.q`):
- The frame: `.admin-section-card { border: 1.5px solid var(--cs-structure); border-radius: var(--cs-radius-frame); background: transparent }`. An unavailable section's frame is `var(--cs-danger)`. A held section takes the Task 7 outline (`data-card-edge="held"`).
- The head: `.admin-section-card__head`, with `background: var(--cs-structure-tint)`, `color: var(--cs-structure-ink)`, the frame's top radius less 1.5px, and `padding: 10px 12px`. In order it holds:
  1. the handle;
  2. the structure chip at 22px (`BlockIconComponent`);
  3. the name button that collapses the section, unchanged;
  4. the words;
  5. the count ("5 blocks", `SectionSummaryComponent`);
  6. the ⋯ menu.
- A word: `.admin-section-word`, a `<button type="button">` in 13px `--cs-structure-ink` with `padding: 2px 6px`, `border-radius: var(--cs-radius)` and an `aria-hidden` "▾". Under the pointer or focused it takes `background: color-mix(in srgb, var(--cs-structure-ink) 12%, transparent)`, and focused it also takes the accent outline.
- The settings region: `#section-<id>-settings`, `hidden` until opened, `class="admin-section-card__settings mx-3 mb-3 rounded-card bg-rail p-3"`. It is the cool ground of settings, and its wells already stand on the rail (`FIELD_GROUNDS`). It holds today's form unchanged in its parts:
  - the layout menu and its hidden input;
  - background, width, style and anchor;
  - the status line, the style note and the five error slots.

  The form keeps its id, `data-editing-unit`, `data-editing-subject`, `data-editing-version` and its held marks. The fieldset keeps `admin-held` and `admin-view-only`.
- Order inside the card: head, the hold-strip slot and its announcer, the settings region, the body (lanes and panels). The hold strip stays visible while the region is closed.

**The words** **(owner: which settings get words)**: the layout always ("3 columns"); the background always ("No background", "Tinted background", "Strong background"); the width always ("Content width", "Full width"); the style when the theme offers styles and one other than the default is chosen (the style's label); the anchor when set ("#about").

New keys under `admin.components.editor_screen`:
- `section_settings_words`:
  - `columns.one: "%{count} column"` and `columns.other: "%{count} columns"`
  - `backgrounds.none: "No background"`, `backgrounds.tinted: "Tinted background"`, `backgrounds.strong: "Strong background"`
  - `widths.content: "Content width"`, `widths.full: "Full width"`
  - `anchor: "#%{anchor}"`
  - `label: "Section settings: %{word}"` (the aria label)
- `section_card.close_settings: "Close"`

`section_summary.columns` goes, since the summary is the count alone.

**Interfaces:**
- `SectionCardComponent.settings_id(section) = "section-#{section.id}-settings"` and `.words_id(section) = "section-#{section.id}-words"`.
- `SectionCardComponent.words(section:) -> SectionSettingsWordsComponent`, the one door the card and the answer both draw through, as `summary` is.
- `SectionSettingsWordsComponent.new(section:, editable:)`. Each word is a button with:
  - `aria-controls` the settings id and `aria-expanded="false"`;
  - `data-action="admin--editor--section#openSettings"` and `data-admin--editor--section-field-param` set to the setting's name (`layout`, `background`, `width`, `style`, `anchor`).

  Read-only viewers get the same buttons; the region shows the read-only fieldset.
- `section_controller.js`:
  - the target `settings`;
  - `openSettings(event)`, which toggles when the region is open and was opened by this word. Otherwise it dispatches the cancelable `admin--editor--section:open-settings` with `detail: { sectionId, region, field }`. When nobody cancels it, it opens the region, sets every word's `aria-expanded="true"`, and focuses the named field (the layout menu's button for `layout`);
  - `closeSettings()`, which sends what the form holds through `saveNow()`, hides the region, and gives the focus back to the word that opened it;
  - `escape` closes the open region first, under the same exclusions it has for menus, listboxes and dialogs.
- `Admin::Answers::BlockDrawing#section_save_streams` also returns `turbo_stream.replace(SectionCardComponent.words_id(section), SectionCardComponent.words(section:))` after every saved section setting. The region is never replaced; it is a form that may hold text.

- [ ] **Step 1: Write the failing tests.**
  - `section_settings_words_component_test.rb`:
    - "a section's head says its layout, background and width as words, each a button for its settings";
    - "a style word appears only for a style that is not the default, and an anchor word only when one is set";
    - "every word controls the settings region and says it is closed".
  - `section_card_component_test.rb`:
    - "a section is a structure frame with a tinted head holding its chip, name, words and count";
    - "the settings form sits in a hidden region under the head, with its id and every editing mark";
    - "a held section's region holds the read-only fieldset and its strip stays above the region".
  - `block_saved_test.rb`: "a saved section setting replaces the words, never the region".
  - `admin_contrast_test.rb`: "a section head's words and its hovered word are 4.5:1 or better on the structure tint" (`--cs-structure-ink` on `--cs-structure-tint`, and on its 12% mix computed in the test, in both schemes).
  - `sections_settings_test.rb`:
    - "pressing a head word opens the settings under the head, focused on that setting, and pressing it again closes them";
    - "Escape in the settings closes them and gives the focus to the word that opened them";
    - "a background chosen in the settings is saved and the head's word follows";
    - "the open:settings event, cancelled, leaves the region closed" (`page.execute_script` adds a listener that calls `preventDefault`).

    The existing layout-menu tests find the menu inside the region after opening it: each first presses the "3 columns" word.
  - `admin_design_rules_test.rb`: `section_card_component.html.erb` joins `EDITOR_CARDS` (Task 7), so the frame's edge too is the stylesheet's.
  - `editing_merge_test.rb`: "a section's settings holding unsaved text survive a catch-up with their region closed, and open again with the text".
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Delete the "keeps `rounded-cs` … until stage 2" comment. The card's comment says that the region is the one element holding the section's settings form, and that a script that moves it puts it back before Turbo's snapshot.
- [ ] **Step 4: Run** `test/components/admin/editor_screen test/controllers/admin/answers test/lib`, then locally `sections_settings_test`, `sections_removing_test`, `editing_merge_test`, `editing_held_test` and `editing_live_test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: a section is a structure frame whose head says its settings as words`

---

### Task 10: One add action

**Files:**
- Modify: `app/components/admin/editor_screen/block_picker_component.{rb,html.erb}`
- Modify: `app/components/admin/ui/menu_component.{rb,html.erb}` (`columns:` and `heading:`)
- Modify: `config/locales/admin/editor_screen.en.yml` (`block_picker.add_block: "+ Add block"`, `block_picker.menu_heading: "Add a block"`, `block_picker.add: "+ Add"`); `MenuComponent` gains no word
- Modify: `test/application_system_test_case.rb` (`add_block(label, column: nil, section: nil)`)
- Modify: these tests, which press a type inside `#block-picker-end` or `.admin-block-picker`, to call `add_block`: `code_block_test`, `card_block_test`, `note_block_test`, `blocks_test`, `promotion_hold_test`, `sections_adding_test` and `sections_menu_moves_test`. `form_builder_test`'s `.admin-block-picker` is the form builder's own and stays.
- Test: `test/components/admin/editor_screen/block_picker_component_test.rb`, `block_tile_component_test.rb:52`, `test/components/admin/ui/menu_component_test.rb`, `test/lib/admin_design_rules_test.rb`

**The look** (drawn `.addrow`, `.amenu`):
- At the foot of the blocks, `#block-picker-end` (`mt-5`, the id kept) holds one `MenuComponent`:
  - `label: t(".add_block")` and `aria_label: t(".menu_heading")`;
  - `button_class: Admin::Ui::ButtonComponent.classes(:primary)`, `align: :left`, `close_on_select: true`;
  - `columns: 3` and `heading: t(".menu_heading")`.

  Its items are today's `button_to` forms, one per type, each the chip and the label.
- The panel is at elevation 3 (the menu's own `bg-popover shadow-3 rounded-card`), `w-[34rem] max-w-[calc(100vw-2rem)] p-2.5`, with a grid of three columns `gap-0.5`. An item is `rounded-button-sm px-1.5 py-1.5 gap-2`.
- A lane's picker is `MenuComponent` with `label: t(".add")`, `aria_label: t(".add_to_column", number: column)`, `button_class: Admin::Ui::ButtonComponent.classes(:tertiary, size: :small)` and `align: :left`. Its list is unchanged (no section; a single column, so no `columns:`).
- `BlockPickerComponent::BUTTON_CLASS` goes.

**Interfaces:**
- `MenuComponent.new(..., columns: nil, heading: nil)`. With `columns: n`, the panel adds `grid grid-cols-<n>` (n is 2 or 3, whole class strings written out so Tailwind sees them). Any other value raises `ArgumentError`. `heading:` draws a `<p class="px-1.5 pb-2 text-label text-meta" aria-hidden="true">` before the items; the panel's name is still `aria_label`. The arrow keys keep walking the items in document order (`admin--ui--menu` is unchanged).
- `add_block(label, column: nil, section: nil)`:
  - with no section, it presses `#block-picker-end`'s trigger, then the item named `label`;
  - with a section and a column, it presses the trigger in `#block-picker-<section.id>-<column>`;
  - either way it waits for the new block's form to be in the page.

- [ ] **Step 1: Write the failing tests.**
  - `block_picker_component_test.rb`:
    - "the page's picker is one primary + Add block that opens a menu of every type, each its chip and its name";
    - "the menu is three columns at elevation 3, headed Add a block";
    - "a lane's picker is + Add, named for its column, and offers no Section".
  - `menu_component_test.rb`: "columns: lays the items out in a grid, and a count it does not know is refused"; "heading: is drawn before the items and hidden from a screen reader".
  - `admin_design_rules_test.rb`: `test "the block picker builds no button of its own"` (`block_picker_component.rb` does not reference `VARIANT_CLASSES` or `SMALL_CLASS`).
  - Add to `sections_adding_test.rb`: "+ Add block opens by Enter, the arrows walk the types in reading order, and Escape gives the focus back to it".
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement**, and move the listed browser tests onto `add_block`.
- [ ] **Step 4: Run** `test/components test/lib test/integration/admin/access_control_test.rb test/integration/admin/forms_test.rb`, then locally `blocks_test`, `sections_adding_test`, `code_block_test` and `card_block_test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: one + Add block opens the block menu, and + Add under each column`

---

### Task 11: The tree's markers at rest, and the selected row's accent bar

**Files:**
- Modify: `app/components/admin/pages_screen/tree_node_component.{rb,html.erb}`
- Modify: `app/assets/tailwind/content-spiel.tailwind.css` (`.admin-tree-row--selected`)
- Modify: `test/lib/admin_design_rules_test.rb` (`SHADOW_ALLOWED` becomes `{}`)
- Test: `test/components/admin/pages_screen/tree_component_test.rb`, `test/lib/admin_contrast_test.rb`, `test/system/admin/tree_test.rb`

**The look** (drawn `.calm .row`):
- "↻N" and "○N" take the child count's classes: `sr-only group-hover/node:not-sr-only group-focus-within/node:not-sr-only any-pointer-coarse:not-sr-only`. On the selected row they take none of them, so they are always shown. They stay `role="img"` with their labels, so a screen reader reads them at rest. The size of their number is `text-count`.
- The selected row is `row_class = "admin-tree-row--selected bg-sunken"`, with the title `font-semibold`. The stylesheet draws `.admin-tree-row--selected { box-shadow: inset 3px 0 0 var(--cs-accent) }`. It is a selection, not a marker, and its comment says so. The inline `shadow-[inset_2px_0_0_var(--cs-ink)]` goes, and with it the last `SHADOW_ALLOWED` entry.

**Interfaces:** `TreeNodeComponent#marker_class -> String` (the shared visibility classes, empty for the selected row).

- [ ] **Step 1: Write the failing tests.**
  - `tree_component_test.rb`:
    - "a row's translation markers are hidden at rest but read, and shown on the selected row";
    - "the selected row carries the accent bar's class and no inline shadow".
  - `admin_contrast_test.rb`: "the selected row's accent bar is 3:1 or better on its sunken ground and on the chrome" (`--cs-accent` on `--cs-sunken` and `--cs-chrome`, both schemes).
  - `tree_test.rb`: "a row's markers show when the pointer is on it and when it has the focus".
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `test/components/admin/pages_screen test/lib`, then locally `tree_test` and `tree_column_test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: the tree's markers rest hidden and the selected row carries the accent bar`

---

### Task 12: The reference, CLAUDE.md, the changelog and the guide pages

**Files:**
- Modify: `docs/reference/design-system.md`:
  - a section "E4: the editor's canvas" after "E4: the redesign's first stage": the four roles in the editor, the card's state edges (the table of Task 7), the tile's states, the frame and its words, one add action, the tree's bar;
  - "Accent: a marker, a selection and a button" now says the bar *is* drawn in accent;
  - "Rules a change can break silently" gains every guard of Tasks 4, 7, 10 and 11 by its test name. It also gains the no-guard cases: one primary per area (Publish, "+ Add block"); a tile lifted by a transform would move under a drag; and a state edge drawn as a border again is caught only in the three files `EDITOR_CARDS` names.
- Modify: `docs/reference/content-blocks-and-types.md`:
  - "Adding a block type", step 8 gains "The tile's preview": `t.preview`, `ContentModel::Preview`, `PREVIEW_LENGTH`, the fallback to the summary line, escaped text, and the shared check `assert_preview_shows_a_sample_value`;
  - the declarations table gains its row;
  - "Sections in the editor" describes the frame, the words, the region and the event `admin--editor--section:open-settings`;
  - "Moves" names the `editor/` modules and `loadSortable()`.
- Modify: `docs/reference/editors-and-translation-pair.md` (the add action, the tile), `docs/reference/live-editing.md` (the held edge is `data-card-edge="held"`; the section's form now sits in `#section-<id>-settings`), `docs/reference/notes.md` (a discussed card's edge is the outline from `data-notes-active`), `docs/reference/save-rule-and-write-queue.md` (the move sender is `editor/move_queue.js`, still behind `admin--editor--blocks#move`), `docs/reference/writing-tests.md` and `test/system/README.md` (`add_block`, `await_sortables`, the sections test files).
- Modify: `CLAUDE.md`:
  - the content-blocks index line names `app/javascript/editor/`, `app/controllers/admin/answers/` and `section_settings_words_component.rb`;
  - "Where a script goes" names `editor` as a topic with a module folder;
  - "Where a class goes" gains: "a controller's Turbo Stream answers, one responder per outcome, in `app/controllers/admin/answers/` (`Admin::Answers::*`), drawn with the view they are handed";
  - "Rules a change can break silently" says that "every block move goes through `admin--editor--blocks#move`" is now held in `editor/move_queue.js`.
- Modify: `CHANGELOG.md`, `## Unreleased`:
  - "Added": a block type's `preview` declaration, for a gem's type too;
  - "Changed": "Discard changes…" is red text; SortableJS is no longer preloaded on every CS Studio screen.
- Test: `PGGSSENCMODE=disable bin/rails test test/lib` (`source_layout_test`, `theming_reference_test` and the guards that read `CLAUDE.md` and `docs/reference`), and `bin/changelog-guard`.

The guide lives in `/Users/dknafelj/src/contentspiel-docs`. The pull request's "Documentation" section names these pages, updated there before release, with their screenshots retaken after merge:
- `docs/editors/pages/build-a-page-with-blocks.md`: "+ Add block", the tiles' previews, the cards;
- `docs/editors/pages/arrange-blocks-in-sections.md`: the frame, the words, the settings under the head, "+ Add";
- `docs/editors/pages/the-page-tree.md`: the markers at rest, the selected row;
- `docs/editors/posts/publish-schedule-and-preview.md`: "Discard changes…" in red;
- `docs/editors/working-together/live-refresh-and-edit-reservations.md` and `notes-on-content.md`: the held and discussed edges.

- [ ] **Step 1: Rewrite the reference sections, `CLAUDE.md` and `CHANGELOG.md` named above.**
- [ ] **Step 2: Run** `PGGSSENCMODE=disable bin/rails test test/lib`, `bin/changelog-guard`, `bin/rubocop` and `bin/rails zeitwerk:check`. Expected: all pass.
- [ ] **Step 3: Write the PR's "Documentation" and "For the owner to check" sections.** The owner's list:
  - the state edges;
  - the hover that does not lift;
  - which settings get words;
  - the settings region on the rail's cool ground;
  - `text-base` for the 17px heading.
- [ ] **Step 4: Commit** `docs: E4 stage 2 in the reference, CLAUDE.md and the changelog` (body: `Advances #117`)

---

## Browser tests

Run locally, few at a time, on a quiet machine, after `bin/rails tailwindcss:build`, prefixed with `PGGSSENCMODE=disable`:
- the files each task names in its Step 4;
- `editor_modules_test` and `entry_helpers_test` (Tasks 3 and 4).

Left to CI, which runs the whole browser suite for the pull request:
- `blocks_test`, the eight `sections_*_test` files, `code_block_test`, `table_block_test`, `note_block_test`, `card_block_test`, `rich_text_test`, `editor_fields_test` and `unsaved_order_test`;
- `editing_held_test`, `editing_live_test`, `editing_merge_test` and `notes_markers_test`;
- `tree_test`, `tree_column_test`, `languages_test`, `translation_layout_test`, `drafts_test`, `unpublished_changes_test` and `save_bar_test` (the Discard button's class).

A CI failure is fixed in the task that owns the file.
