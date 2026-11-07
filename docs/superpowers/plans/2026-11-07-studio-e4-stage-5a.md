# CS Studio in E4, Stage 5a (the mind graph) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The mind graph takes E4. The canvas draws from E4's tokens, with the contrast the spec measures: related lines 3.9 / 4.3:1, tree lines 3.8 / 4.5:1, post hues 5.9–7.1 / 8.1–9.1:1, tags 6.2 / 8.9:1 and the selection ring 6.9 / 7.1:1. The canvas's text is in the sans. The list carries icon and status chips, and so does the card, whose buttons are the shared button. The status key leaves its dialog and joins the legend's row. Before any of that, two refactors land with no visible change: `mind_graph/app.js` (1,433 lines) is split into state, input and render modules (#132), and the two browser-test files of the graph (3,889 and 2,744 lines) are split by behaviour (#133).

**Architecture:** Every colour, the line strengths and the fade of what a selection leaves out move into `--cs-graph-*` tokens in `content-spiel.css`. `theme.js` reads them, and `marks.js` and `renderer.js` name theme keys only, so `admin_contrast_test` can measure every mark the canvas draws. Translucent lines are written as `rgba()` of their base token's colour, which a canvas takes and the contrast test resolves. A test holds each rgba's colour to its base token. The chips and the card's Close are rendered by the server's own components into one `<template data-mind-graph-parts>` inside the graph's element (`Admin::MindGraphScreen::PartsComponent`). The scripts clone them (`mind_graph/parts.js`), so no chip or button is drawn by hand in JavaScript. `app.js` keeps the wiring, the data request and the test API. The state of the graph and its pure operations go to `state.js`, a frame to `frame.js`, the canvas's gestures to `gestures.js`, the selection and pins to `selection.js`, the list's two reads to `list_reads.js` and the notice to `notice.js`.

**Tech Stack:** Rails 8.1, ViewComponent with Lookbook previews, Tailwind v4 (`tailwindcss-rails`), Stimulus over import maps (`mind_graph/` pinned `preload: false`), a 2D canvas, d3-force in a module worker, Minitest with Capybara on Cuprite.

**Spec:** `docs/superpowers/specs/2026-11-06-studio-e4-design.md` (approved 2026-11-06). Sections used: "Decided on 2026-11-06" (11), "The design, as decided" (tokens, buttons, the four roles and status), the screen table's Mind graph row, "Stage 5", item **5a** in full, "Architecture-review findings", "The guard after E4" and "Constraints". Parked items from PR #187: "the mind graph's canvas fonts, its zoom readout and its card's status chip". The drawing is the Design System artifact's `StudioCalmE4More` (https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT). The artifact tools were unavailable while this plan was written, so its values come from the spec's figures, matched by measurement (see "Decisions the spec left open").

**Two pull requests, stacked.**
- **PR 5a-1, the split,** is Tasks 1–3 on branch `studio-e4-5a`. It is stacked on `studio-e4-4b` (PR #194), which is stacked on `studio-e4-4` (PR #193), and targets `studio-e4-4b`. As those merge, it is rebased onto `main` and targets `main`.
- **PR 5a-2, the look,** is Tasks 4–7 on `studio-e4-5a-look`, branched from `studio-e4-5a`. It targets `studio-e4-5a` until 5a-1 merges, then `main`.

Why two: 5a-1 changes nothing a person sees. Its whole proof is that every browser test of the graph passes unchanged, across nine new files and six new modules, and a reviewer reads it as a move. 5a-2 is read against the drawing: tokens, chips, the legend. Mixed, a regression in the look would have to be found inside a 1,400-line move. The split goes first because every task of 5a-2 changes code that the split moves (`app.js`'s card and list wiring, the module tests of `theme`, `renderer`, `card` and `list`). The other order would convert those files twice.

## Global Constraints

- **The public site keeps its look.** No file under `app/assets/tailwind/themes/`, `app/components/blocks/`, `app/components/public/` or `app/views/layouts/public/` changes, and no `th-*` token.
- **The script holds no colour value** (spec 5a), and from Task 4 no strength either. Every colour and every opacity the canvas uses comes from a `--cs-*` token read by `theme.js`. `marks.js` and `renderer.js` name theme keys. The one numeric `globalAlpha` left in them is `1`. A label's fade-in strength from `labels.js` is motion, not colour, and stays.
- **Pages stay neutral; the hues mean post types** (spec 5a). Every status keeps its shape and its word. A draft is dashed on every mark.
- **The no-guard rules of the graph** (CLAUDE.md, "The Mind graph"):
  - `reset()` takes back whatever the script writes into the page. A task that makes the script write something new adds it to `reset()` and to the "Back to the graph" tests in the same task. Cloned chips land only inside the list and the card, which `reset()` already empties.
  - `PostGraph.node_id`, `mind_graph/ids.js` and the `"tag-"` prefix are not touched.
  - The CSS marks outside the canvas change with `marks.js`. Task 4 adds a guard that holds them (the tag's square, a post's dot, a retired type's ring).
  - The status key's words: `legend.states` and `script.card.status` change together. Task 6 adds a guard that holds them.
  - `everything=1` stays a parameter of the data alone.
  - Whatever can be pressed on the canvas has a row in the list.
  - No test pins a measured layout figure or waits out a script call of more than about two seconds. A contrast figure is a token's measurement, not a layout figure. A DOM box of the card is not the layout's.
- **No admin string is a literal.**
  - A component under `app/components/admin/mind_graph_screen/` reads `admin.components.mind_graph_screen.*` (`config/locales/admin/mind_graph_screen.en.yml`).
  - A script's words come from `data-messages` (`admin.mind_graph.script.*`, `mind_graph.en.yml`), each key written out in `show.html.erb` for `script_messages_test`.
  - A key is added in the task whose code reads it, and deleted, with its `data-messages` entry, in the task that deletes its last reader.
  - A new component or script joins `admin_i18n_test`'s `CONVERTED` in the task that creates it.
- **Buttons are the shared button.** A link styled as a button takes `ButtonComponent.classes`, handed over in `data-button-classes`. A button the script needs whole, with its icon (the card's Close), is the component's own markup, cloned from the parts template.
- **Type voice.** Labels are `text-label` (sans, 12px, `cs-meta`), counts `text-count`. No `font-cs-mono` beyond `MONO_ALLOWED`, and from Task 4 no mono on the canvas. No `text-[13px]`: a size is a type token (`text-small` is 13px).
- **Depth and radius.** A shadow is an elevation token, and a radius a radius token. The card and the tooltip keep `rounded-card` / `rounded-cs` on `bg-popover shadow-3`, and the zoom control takes `rounded-button`.
- **Comment rule (#117).** A comment states a current invariant, a hazard or a reason. It never states a plan step, a review round ("Task 7's review", "the ruling on the review of"), "spec §" or what used to be there. Every task rewrites the comments of the files it changes by this rule. The graph's files are among the densest in "spec §" and "design answer": a design answer's letter (G3, H6) names a decision and may stay, while a review round or a task number goes.
- **Tests and the machine.** On macOS every test command is prefixed with `PGGSSENCMODE=disable`. Browser tests run only after `bin/rails tailwindcss:build`, never during a build or beside a running `bin/dev`. They run one file at a time, and only while the one-minute load (`sysctl -n vm.loadavg`, first figure) is under 6. A graph file costs about 8 seconds a test, so each split file is run alone. **No test run is left in the background** when a task ends: a task's last step checks that `pgrep -f "rails test"` prints nothing.
- Commits follow conventional commits and end with:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT`
  A task that carries a finding says so in its body ("Advances #132", "Advances #133", "Advances #117").
- A look that a person sees and that the spec does not settle is marked **(owner)**. Each has a default the build goes ahead on, and PR 5a-2 lists them under "For the owner to check".

## Review Focus

1. **The theme switched while a card is open.** The canvas is redrawn by `watchTheme`, but the card's chips are cloned DOM. They must follow the theme through their tokens, with nothing re-cloned and the note half typed in the card kept. Task 5: "the card's chips follow the theme, and what is typed in the card stays".
2. **A two-state chip in a 240px card.** A live record with a change scheduled shows Live, then "Change scheduled 14 Oct". In German, or on a long date, the row must wrap inside the card and never run under Close. Task 5: "a two-state chip wraps inside the card, clear of Close, in German too" (`with_locales(%w[en de])`, DOM boxes only).
3. **A font the canvas measures before it has loaded.** Labels are measured once per load (`takeData`). After Task 4 the count font is the sans at weight 500. Archivo 500 is a weight the page already uses for labels. If the canvas asked for one that is not loaded, the hit test would use the fallback's widths. Task 4: "the canvas's fonts are faces the page has loaded when the graph is drawn" (`document.fonts.check` on each of the theme's fonts after `await_graph`).
4. **Back to the graph after the status looks moved onto the legend.** The legend's five status swatches are drawn by `admin--mind-graph--swatches` on connect. A restored page must show them drawn, not as blank canvases, and the list must show no cloned chip from the visit that was left. Task 6 adds both to the worker-and-Back file.
5. **Ring and retired types after the hues are retuned.** Slots 7–12 are rings of slots 1–6, and a retired type is a ring in `meta` with a stroke. A retune that moved a hue's angle would bring two types together. Task 4 pins each slot's hue angle and keeps the module test "marks: every mark that has a state is drawn in each of the five looks exactly as the table says, no two alike".

---

## Decisions the spec left open

| Question | Decision | Why |
|---|---|---|
| "`theme.js` reads `--cs-*`" when it already does | The change is in WHICH tokens it reads: the graph's own `--cs-graph-*` (lines, tag, page, the fade), the Draft chip's edge, and the sans for every font. The alphas in `LINE_STYLES` and the `DIM` constant leave the script. | The spec's figures for lines can be measured only when a line's colour is a token, not a token times a constant in JavaScript. |
| The artifact could not be read while planning | The spec's figures were matched by measuring E4's tokens on `--cs-surface` with `ContrastMeasure`. Ink at 55% (light) and 50% (dark) gives 3.92 / 4.27:1, the spec's related line. Dim at 70% gives 3.76 / 4.64:1, the tree line. The structure icon hue gives 7.46 / 8.91:1 on the surface for a tag. **Task 4 Step 0** reads `StudioCalmE4More`'s `preview.html`, and where the drawing writes a value, the drawing's value is used. The tests hold the spec's figures either way. | The figures are the spec's. A value within them is the builder's, and the drawing outranks the builder. |
| The post hues (5.9–7.1 / 8.1–9.1) | `--cs-cat-1…6` are retuned in lightness only, keeping today's oklch hue and chroma, until each is inside the band on `--cs-surface` **(owner)**. This changes the type dot on every screen (`ContentTypeDotComponent`). | The figures coincide with five of the seven icon families on the surface (form 5.90 to lists 7.08; dark 8.05 to 9.05). But the graph has six slots, and a post type in "form green" would borrow a meaning the sidebar gives Forms. Today's hues were chosen to stay apart (design answer D2). |
| Tags (6.2 / 8.9) | A tag's square edge and its label are `--cs-graph-tag: var(--cs-ic-structure)`, 7.46 / 8.91:1 **(owner: the light figure is above the spec's 6.2)**. | 5b's tag usage bar is "structure hue, 6.2 / 8.9:1", the same figures, so tags are the structure hue. The structure icon hue meets them; no token in the set measures exactly 6.2. |
| The tree line, the related line, the shared-tag and lists lines | `--cs-graph-line-tree` (dim at 70%), `-related` (ink at 55% / 50%), `-tag` (meta at 80%: today's look, 3.96 / 4.59:1), `-lists` (`var(--cs-dim)`), `-brings` (`var(--cs-line)`, a grouping line, unmeasured). Each translucent one is written `rgba(<base token's colour>, a)`. `--cs-graph-tree` is renamed to `--cs-graph-line-tree`, with no alias. | One token per line style, named after the style. `rgba()` is a colour every canvas takes; `color-mix()` reaches the canvas as an unresolved string. |
| The dim factor | `--cs-graph-faded: 0.3` in both schemes, theme key `faded` **(owner)**. The selection's bright pass draws in ink at full strength (today 0.9). | The spec says it changes and gives no figure. 0.3 keeps the strongest mark it fades, ink, under 3:1 (1.94 / 2.40), so a faded node never reads as active. It keeps the faintest post hue above 1.5:1, so the faded node is still seen. A test holds both. |
| A page's mark | Light stays `var(--cs-ink)`. Dark becomes `var(--cs-dim)` (8.0:1), in place of the literal `#d9d9dc` (11.6:1) **(owner)**. | The literal was kept "until stage 5a redraws the graph". E4's dark dim is the neutral one step below ink: no glare, and no hue. |
| `LOOKS` | A draft's dashed outline is the Draft chip's edge, `--cs-field-line` (theme key `edge`; 3.60 / 4.17:1), in place of `meta`. A scheduled record keeps its `warn` centre dot. A live record with changes keeps the `dim` corner dot, and a change scheduled the `warn` one. | The card's chip becomes the shared outlined Draft, so the canvas's draft takes its edge. `--cs-scheduled`, E4's amber, is 2.07:1 on the light surface and cannot be a mark. `warn` is the status that measures (4.98 / 7.41). |
| The canvas's fonts (parked) | Labels `12px` sans, the selected one `600 12px`, and the notes count with the pill's words `500 11px`. A tag's label is no longer mono. The notes badge's geometry stays: "99+" in Archivo 500 at 11px fits its 26px pill. | E4's one type voice: mono is for code and a key's value. A tag is mono nowhere else in CS Studio. |
| The zoom readout (parked) | `text-count` (sans, 11px, weight 500) with `tabular-nums`, so "100%" and "95%" take one width. The zoom control is `rounded-button`, and its buttons `text-small`. | The readout is a figure, not a label. `text-[13px]` is a raw size. |
| "The legend, the list and `node_list.js` gain icon and status chips" | Read as: the legend gains the **status** looks (the status key on its row, decision 11), and the list (`node_list.js`) gains **icon** chips on its group headings and **status** chips on its rows. The legend's toggles keep their canvas swatches, which teach the canvas's marks. A second chip there would stand beside a swatch that already names the kind **(owner)**. | "The list" and `node_list.js` are one thing, so the sentence names two places. The legend's status entries are the chips' words with the canvas's own look. |
| The list's chips | Each group heading has its kind's icon chip in its sidebar family: Pages `pages` / structure, Posts `posts` / lists, Tags `tags` / lists, Post types `clipboard_list` / lists **(owner: the icon of Post types)**. A row shows `StatusChipComponent` for a draft or a scheduled record and `UnpublishedChipComponent` for a live record with any changes. A live row shows none (`hide_live`, as the posts list does). The chips are `aria-hidden`: a row's name stays as it is, and the card it opens says the state in words. | Two thousand live rows clone nothing. Changing every row's name would rewrite the list's accessible names and every test that finds a row by name, for a state the card already says. |
| The card's chip (parked) | The record's `StatusChipComponent` (solid Live, outlined Draft, amber Scheduled), then, for a live record with changes, `UnpublishedChipComponent` or the words "Change scheduled 14 Oct", as the editor's header draws them (`PublishingStateComponent`). The visible row stays `aria-hidden` beside the sr-only sentence in the key's words. | One chip for one state, the same everywhere. The canvas's unpublished corner dot is `dim` while the shared chip's dot is `warn`; that difference is today's and is listed for the owner, not changed here. |
| The card's buttons | "Open post", "Open page", "Show tagged posts" and "Focus" stay links with `ButtonComponent.classes`. Close becomes `ButtonComponent` (`icon: :x`, `variant: :tertiary`, `size: :small`), cloned from the parts template, with its tooltip. The load failure's Retry and the opened view's "Show everything" become `:tertiary` small. `data-button-classes` gains `tertiary`. | Each was drawn by hand (`text-meta hover:bg-sunken`, `font-semibold text-ink underline`, `text-accent underline`). |
| The status key's dialog | Deleted. The five looks stand on the legend's row as a third group, "Status", each with its swatch and the chip's words. `StatusKeyComponent`, its dialog, its button and `status_key.*` go, and `STATES` moves to `LegendComponent` **(owner: "the dialog may stay for the long words")**. | The row wraps, so it holds the long words too. One place for the words, and one Tab stop fewer. |
| The split's module names | `state.js`, `frame.js` (render) and `gestures.js` (input) are the spec's three. `selection.js`, `list_reads.js` and `notice.js` take the rest. `input.js` keeps its job: which gesture the pointer made, knowing nothing of the graph. | `app.js` would otherwise keep 700 lines of selection and list reads. `gestures.js` is named apart from `input.js` because both stay. |
| The test split's files | Nine browser files and five module files, by behaviour, with two base classes in `test/support/`, as `sections_test` was split in stage 2. Their seconds in `test/system_test_seconds.yml` are the old file's, in proportion to each file's count of tests. | `bin/test-shard` deals files by measured weight. `test_shards_test` must still pass, with the heaviest file now about 150 s instead of 863. |

---

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `test/support/mind_graph_system_test_case.rb` (new), nine `test/system/admin/mind_graph_*_test.rb` (new), `mind_graph_test.rb` (deleted), `test/system_test_seconds.yml` | the browser file split | 1 |
| `test/support/mind_graph_modules_system_test_case.rb` (new), five `test/system/admin/mind_graph_*_modules_test.rb` (new), `mind_graph_modules_test.rb` (deleted), `test/system_test_seconds.yml` | the module file split | 2 |
| `app/javascript/mind_graph/{state,frame,gestures,selection,list_reads,notice}.js` (new), `app.js` | the script split | 3 |
| `content-spiel.css`, `content-spiel.tailwind.css` (`--color-graph-tag`), `mind_graph/{theme,marks,renderer,swatches,card}.js` | the graph's tokens, contrast and fonts | 4 |
| `app/components/admin/mind_graph_screen/parts_component.*` (new), `mind_graph/parts.js` (new), `card.js`, `node_list.js`, `app.js`, `show.html.erb` | chips and the shared button | 5 |
| `legend_component.*`, `status_key_component.*` (deleted), `show.html.erb`, `graph_controller.js` | the status key on the legend's row, the zoom control | 6 |
| `docs/reference/cs-studio-shell-and-dashboard.md`, `design-system.md`, `CLAUDE.md`, `CHANGELOG.md` | 5a-2's reference | 7 |

---

# PR 5a-1: the split

### Task 1: `mind_graph_test.rb` split by behaviour (#133)

**Files:**
- Create `test/support/mind_graph_system_test_case.rb` with `Admin::MindGraphSystemTestCase < ApplicationSystemTestCase`. It holds:
  - `GRAPH`, `CANVAS`, `LIST`, `setup` and `teardown` (the fetch and timeout restore);
  - the graph scripts `SHARED_ID_GRAPH`, `CAPPED_GRAPH`, `CAPPED_LOCAL_GRAPH` and `BIG_GRAPH`;
  - every private helper of today's file from `stub_graph_data` on (`count_workers`, `escape_on_canvas` … `pixels_of`), still private.

  It is required from `test/application_system_test_case.rb`, beside the sections base.
- Create these files, each `< Admin::MindGraphSystemTestCase`. Each holds the tests that start at these lines of today's file, bodies and names unchanged. A test runs to the line before the next test, or to the next section comment.

  | File | Behaviour | Tests at today's lines | Count |
  |---|---|---|---|
  | `mind_graph_drawing_test.rb` | the screen, its marks, zoom and pan, size, theme and motion | 57, 82, 104, 125, 149, 178, 234, 268, 293, 561, 831, 926, 1254, 1276, 1903, 1936, 2721, 3244 | 18 |
  | `mind_graph_loading_test.rb` | the load, its failures, the cap, the views a site opens in | 42, 583, 605, 626, 660, 682, 739, 790, 808, 956, 2937 | 11 |
  | `mind_graph_worker_and_back_test.rb` | the worker that can't start, leaving, Back | 976, 999, 1025, 1060, 1086, 1104, 1148, 1187, 2011 | 9 |
  | `mind_graph_legend_test.rb` | the legend's filter and the status key | 319, 387, 431, 450, 480, 503, 522, 537, 551, 1476, 1503 | 11 |
  | `mind_graph_selection_test.rb` | selecting, the card, hovering | 1301, 1333, 1376, 1387, 1410, 1435, 1457, 1520, 1723, 1760, 1790, 1821, 1851, 1877, 1955, 1976, 1994, 2851, 3284 | 19 |
  | `mind_graph_dragging_test.rb` | dragging and pins | 1533, 1569, 1598, 1651, 1672, 1699 | 6 |
  | `mind_graph_search_test.rb` | search and the local views | 2027, 2057, 2073, 2095, 2108, 2125, 2141, 2155, 2166, 2181, 2208 | 11 |
  | `mind_graph_list_test.rb` | the list, its reads and pills, the keyboard path | 2239, 2320, 2415, 2467, 2518, 2600, 2760, 3413, 3446, 3462, 3493, 3512, 3535, 3570, 3602, 3632 | 16 |
  | `mind_graph_notes_test.rb` | notes in the card and on the canvas | 3028, 3061, 3101, 3127, 3144, 3166, 3203, 3266, 3308 | 9 |

  A helper used by one file only moves into that file instead of the base.
- Modify the test at line 42, "every stub of fetch in this file remembers the real one…". It reads every `test/system/admin/mind_graph_*_test.rb` that is not `*_modules_test.rb`, instead of `__FILE__`. It is renamed "every stub of fetch in the graph's browser files remembers the real one, so the teardown can put it back", and its floor stays `> 12` over all of them.
- Delete `test/system/admin/mind_graph_test.rb`.
- Modify `test/system_test_seconds.yml`. The `mind_graph_test.rb: 862.8` entry becomes nine entries, each the old seconds in proportion to its count of the 110 tests, rounded to 0.1, summing to 862.8.
- Modify every citation of `test/system/admin/mind_graph_test.rb` to name its new file:
  - `docs/reference/cs-studio-shell-and-dashboard.md` (15 citations; leave `test/integration/admin/mind_graph_test.rb`, a different file, as it is);
  - the comment in `test/system/admin/tokens_related_posts_and_starter_pages_test.rb`.

**Interfaces:** the helpers keep their names and signatures. Tasks 4–6 add tests to `mind_graph_drawing_test.rb`, `mind_graph_selection_test.rb`, `mind_graph_legend_test.rb`, `mind_graph_loading_test.rb` and `mind_graph_worker_and_back_test.rb`.

- [ ] **Step 1: Check the count.** `grep -c '^  test "' test/system/admin/mind_graph_test.rb` prints 110. Check that every start line in the table is a `test "` line of that file: `awk '/^  test "/{print NR}'` lists exactly the 110 numbers of the table.
- [ ] **Step 2: Move the tests and the helpers.**
- [ ] **Step 3: Verify.**
  - `grep -h -c '^  test "' test/system/admin/mind_graph_{drawing,loading,worker_and_back,legend,selection,dragging,search,list,notes}_test.rb | paste -sd+ - | bc` prints 110.
  - `PGGSSENCMODE=disable bin/rails test test/lib/test_shards_test.rb` passes: "every system test file is in exactly one shard", and "no system shard is much heavier than a fair share", now that the heaviest file is not a whole shard.
  - `grep -rn "system/admin/mind_graph_test.rb" docs CLAUDE.md test app` prints nothing.
  - After `bin/rails tailwindcss:build`, run each new file once, one at a time, on a quiet machine. Expected: PASS, the same 110 tests.
- [ ] **Step 4: Commit** `test: mind_graph_test split by behaviour into nine files` (body: `Advances #133`)

---

### Task 2: `mind_graph_modules_test.rb` split by module (#133)

**Files:**
- Create `test/support/mind_graph_modules_system_test_case.rb` with `Admin::MindGraphModulesSystemTestCase < ApplicationSystemTestCase`. It holds:
  - the `setup` (sign in, `visit admin_tags_path`, `await_admin_controllers`);
  - the private helpers used by more than one new file: `js_module`, `renderer_calls`, `draw_calls`, `marks_drawn`, `shapes_drawn`, `lines_drawn`, `swatch_drawn`, `row_mark_drawn`, `notes_badges`, `settled_log`, `settled_log_script`, `input_calls`, `summaries`, `node_set`;
  - the constants those helpers read (`RECORDING_CONTEXT`, `NODE_RADIUS`, `PIN_RADIUS`).

  The constants of one file's tests stay in that file (`SOLID`, `DASHED`, `CORNER`, `STATES`, `STATED_MARKS`, `LINES`, `GRAPH_DATA`, `MATRIX`, `WHOLE`, `ALL_ON`, `SWATCH_STATES`, `CARD_SCRIPT`, `LIST_SCRIPT`). It is required from `test/application_system_test_case.rb`.
- Create these files, each `< Admin::MindGraphModulesSystemTestCase`, holding the tests that start at these lines of today's file, unchanged:

  | File | Modules | Tests at today's lines | Count |
  |---|---|---|---|
  | `mind_graph_layout_modules_test.rb` | `layout_worker`, `layout_client`, `layout_parameters` | 18, 55, 84, 121, 145, 188, 234, 252, 373, 1031, 1069, 1187, 1203, 1256, 2279, 2311 | 16 |
  | `mind_graph_input_modules_test.rb` | `input`, `camera`, `hit_test`, `card_placement`, `ids` | 273, 283, 298, 315, 330, 346, 361, 389, 394, 402, 406, 412, 429, 438, 448, 460, 467, 482, 500, 509, 516, 525, 539, 625, 633, 648, 699, 871, 888, 1148 | 30 |
  | `mind_graph_drawing_modules_test.rb` | `marks`, `renderer`, `labels`, `theme`, `swatches` | 545, 552, 574, 583, 597, 606, 615, 656, 671, 690, 715, 729, 745, 790, 821, 839, 858, 915, 924, 932, 956, 1000, 1112, 1291, 1301, 1310, 1321, 1343, 1357, 1370, 1386, 1396, 1412, 1429, 1439, 1666, 1674, 1690, 1708, 1725 | 40 |
  | `mind_graph_data_modules_test.rb` | `graph_data`, `summary` | 970, 985, 1168, 1470, 1527, 1534, 1541, 1562, 1577, 1595, 1622, 1641, 2182, 2262 | 14 |
  | `mind_graph_card_and_list_modules_test.rb` | `card`, `node_list` | 1771, 1824, 1859, 1883, 1915, 1949, 1980, 2006, 2032, 2062, 2081, 2128 | 12 |

- Delete `test/system/admin/mind_graph_modules_test.rb`.
- Modify `test/system_test_seconds.yml`. The `mind_graph_modules_test.rb: 375.9` entry becomes five entries, in proportion to their tests out of 112, summing to 375.9.
- Modify every citation of `mind_graph_modules_test.rb` to name its new file:
  - `docs/reference/cs-studio-shell-and-dashboard.md` (7);
  - the comments of `app/components/admin/mind_graph_screen/swatch_component.rb` (→ the drawing file), `test/system/admin/live_connection_test.rb`, `notes_merge_test.rb` and `tokens_related_posts_and_starter_pages_test.rb`.

**Interfaces:** the helpers keep their names and signatures.
- Task 3 adds the state tests to `mind_graph_data_modules_test.rb`.
- Task 4 changes the theme, line, label and fade tests in `mind_graph_drawing_modules_test.rb`.
- Task 5 changes the card and list tests in `mind_graph_card_and_list_modules_test.rb`.

- [ ] **Step 1: Check the count.** The old file has 112 `test "` lines, and the start lines in the table are exactly those.
- [ ] **Step 2: Move the tests, the helpers and the constants.**
- [ ] **Step 3: Verify.** The five files hold 112 tests together. `test/lib/test_shards_test.rb` passes, and no citation of the old name is left. Run each new file once, one at a time. Expected: PASS.
- [ ] **Step 4: Commit** `test: mind_graph_modules_test split by module into five files` (body: `Advances #133`)

---

### Task 3: `mind_graph/app.js` split into state, input and render modules (#132)

**Files:**
- Create in `app/javascript/mind_graph/`:

  | Module | What moves into it from `app.js` |
  |---|---|
  | `state.js` | the `state` record and its index maps; `labelFor`; the data's nodes, lines, sizes and label widths (`show`'s middle part); `addPost`'s change to the graph; `sizePill`; the selection's widths and neighbours; `screenOf`; `hit` |
  | `frame.js` | `requestDraw` (one frame per animation frame: the labels, the hover's label, `draw`, `data-zoom`, `data-labelled` and the readout); `resize` |
  | `gestures.js` | `attachInput`'s callbacks: press, drag, drop, click, double click, Escape, Enter, hover, pan and zoom, with `pressed`, `grab`, `dragging`, `pointerHover`, `rowHover` and `pointerAt`; `syncHover`, `rehover`, `hover` and the tooltip; `moveCamera` |
  | `selection.js` | `select`, `reveal`, `closeCard`, the card's key handler, `positionCard`, `measureCard`, `pin`, `unpin`, `pinsChanged` |
  | `list_reads.js` | `drawList`, `letGo`, `showGroups`, `wayBack`, `backToList`, `showRowsFrom`, `openMore`, with `rowsShown`, `failed` and `asked` |
  | `notice.js` | `say` (the notice's lines kept by their words) and the announced summary line |

- Modify `app.js`. It keeps `mount(element)`: it reads the element's data, builds the parts above, the card, the list and the search, and owns:
  - `load`, `show`, `clear`, `showEverything`, `showOpened`, `opened`;
  - `startLayout`, `workerFailed`;
  - `applyFilter`, `refilter`, `addPost`'s orchestration, `notify`, `summarise`, `writeCounts`;
  - the `element.mindGraph` test API, the returned API and `destroy()`.

  It is no more than 450 lines with its comments. The header essay is divided: each module's header takes the paragraphs about what it owns (the camera's to `frame.js` and `gestures.js`; SELECTING, DRAGGING AND PINNING and HOVERING to `selection.js` and `gestures.js`; THE LIST to `list_reads.js`). `app.js` keeps what it wires, the attributes it writes and the API, rewritten by the comment rule.
- Modify `test/lib/admin_i18n_test.rb`: `selection.js`, `list_reads.js` and `notice.js`, which call `text.t`, join `CONVERTED`.
- Modify `docs/reference/cs-studio-shell-and-dashboard.md`, "The modules and what each owns": `app.js`'s entry shrinks, and the six modules get an entry each.
- Test: `test/system/admin/mind_graph_data_modules_test.rb`, and every browser file of Task 1 unchanged.

**Interfaces:**
- `mind_graph/state.js` exports:
  - `createState(theme) -> State`. The record `app.js` has today, plus `indexOf: Map<id, index>`, `plainWidths: number[]` and `strongWidths: number[]`.
  - `labelFor(node) -> string`. It moves here from `app.js` with `MAX_LABEL_CHARACTERS`. `app.js` exports it no longer, and the browser test at today's line 561 imports `mind_graph/state`.
  - `takeData(state, data, { context, words: { allPosts, more(count), retired(name) } })`:
    - nodes from `nodesOf`, each pill's `of`, the lines whose two ends are held, positions, sizes, labels with `cut`, and both width arrays;
    - it resets `selected`, `focusIndex`, `fitted`, `placed`, `pinned`, `labels` and `hovered`.
  - `addNode(state, row, { context }) -> { index, node, lines, at }`. The post, its hub's line (`tag` to a tag, else `brings`) and its place `ADDED_OFFSET` from the hub or the centre. `ADDED_OFFSET` moves here.
  - `resizePill(state, index, { context, words })`
  - `selectIndex(state, index)`: the width swap, then `neighbours` by `visibleEdges`, then `selected`.
  - `showOnly(state, { visibleNodes, visibleEdges, order, free })`
  - `clearData(state)`
  - `screenOf(state, index) -> { x, y }`
  - `hitAt(state, x, y) -> index`, which is -1 until `placed`.
- `mind_graph/frame.js` exports `createFrame({ element, canvas, context, state, reducedMotion, zoomReadout, percent, onDrawn }) -> { request(), resize() -> boolean, draws: () => number, stop() }`:
  - `onDrawn()` runs inside the frame after the draw, which is where the card is placed;
  - `resize()` answers whether the size changed;
  - `stop()` cancels a pending frame.
- `mind_graph/gestures.js` exports `attachGestures({ canvas, element, state, tooltip, cardElement, layout, act }) -> { hoverRow(index), rehover(), moveCamera(camera), clearHover(), hideTooltip(), stop() }`:
  - `layout` is a function answering the current layout client or null;
  - `act` is `{ select, dismiss, unpin, pinsChanged, measureCard, openCard, request }`;
  - `clearHover()` forgets both hover sources (what `show` and `clear` do today).
- `mind_graph/selection.js` exports `createSelection({ element, canvas, state, card, cardElement, list, layout, release, text, request, onMore }) -> { select(index), reveal(index), closeCard(), pin(index), unpin(indexes), pinsChanged(), measureCard(), positionCard(), forgetPlace(), stop() }`:
  - `onMore(node)` is what a press on a pill does;
  - `forgetPlace()` makes the next frame place the card again;
  - `stop()` removes the card's key handler.
- `mind_graph/list_reads.js` exports `createListReads({ element, list, state, text, number, signal, destroyed }) -> { draw(), showRowsFrom(url, { pill, again }), openMore(pill), showGroups(), backToList(), letGo(), dropPillRows(pillId), forgetPillReads(), pillShown() }`:
  - `signal` is the screen's abort signal;
  - `destroyed()` answers whether the screen was left;
  - `dropPillRows(pillId)` lets a spent pill's rows go (what `addPost` does today);
  - `forgetPillReads()` drops a pill's rows or failed read when a new graph arrives (what `show` does today);
  - `pillShown()` answers whether a pill's rows or its failed read are shown (what `dismiss` asks).
- `mind_graph/notice.js` exports `say(notice, ...lines)` and `announce(notice, summary)`.
- `app.js` exports `mount(element)` alone, with today's returned API (`zoomIn`, `zoomOut`, `fit`, `releasePinned`, `filter`, `showEverything`, `destroy`) and today's `element.mindGraph`.

- [ ] **Step 1: Write the failing state tests** in `mind_graph_data_modules_test.rb`. Each imports `mind_graph/state` with `js_module` and a plain `{ measureText }` context:
  - `test "state: takeData leaves out a line whose end the data does not hold, gives a pill no label, and measures each label twice"`. Assert the edges' length, the pill's `label == ""`, and `plainWidths` and `strongWidths` of equal length with the selected font's entries wider.
  - `test "state: selectIndex lights the neighbours by the lines shown, and swaps the selected label to its semibold width and back"`. Hide one of two lines with `showOnly`, and assert that one neighbour is lit and the widths are restored on `selectIndex(state, -1)`.
  - `test "state: addNode joins a post to a tag by a tag line and to a hub by a brings line, beside it, and to nothing at the corner offset"`
  - `test "state: labelFor cuts by code point and keeps a tag's count whole"`. The browser test at today's line 561 keeps its case; this is the module's own.
  - `test "state: hitAt answers nothing until the layout has placed the nodes"`
- [ ] **Step 2: Run them, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/system/admin/mind_graph_data_modules_test.rb`. Expected: the import of `mind_graph/state` fails.
- [ ] **Step 3: Move the code.** The moves are mechanical: each function's body moves as it is, and what it closed over becomes a parameter or a field named in the interfaces.
  - The order of the calls in `show`, `addPost`, `applyFilter` and `clear` does not change.
  - Nothing new is written into the page, so `reset()` is unchanged.
  - The guards on ids and on the layout's messages read every file of the folder and need no change.
  - The comments move with the code they explain and are rewritten by the comment rule.
- [ ] **Step 4: Run the tests.**
  - First the module test, then `PGGSSENCMODE=disable bin/rails test test/lib test/integration/public_javascript_test.rb test/integration/admin/mind_graph_test.rb`.
  - Then, after `bin/rails tailwindcss:build`, one at a time on a quiet machine: the nine browser files of Task 1, then `mind_graph_input_modules_test.rb` and `mind_graph_card_and_list_modules_test.rb`.
  - Expected: PASS with no change to any test but the import in today's line-561 test.
  - `wc -l app/javascript/mind_graph/app.js` prints at most 450.
- [ ] **Step 5: Write the PR body** for 5a-1.
  - Base: `studio-e4-4b`, or `main` once #193 and #194 have merged.
  - Findings: Advances #132 (`mind_graph/app.js`), Advances #133 (the graph's two files), Advances #117.
  - Documentation: "none: nothing a person sees changes".
  - Check that `pgrep -f "rails test"` prints nothing.
- [ ] **Step 6: Commit** `ref: the mind graph's script is split into state, frame, gestures, selection, list reads and notice` (body: `Advances #132`, `Advances #117`)

---

# PR 5a-2: the look

### Task 4: The graph's tokens, its contrast and its fonts

**Files:**
- Modify `app/assets/tailwind/content-spiel.css`, in both scheme blocks:
  - `--cs-graph-page` (dark becomes `var(--cs-dim)`);
  - `--cs-graph-tag: var(--cs-ic-structure)`;
  - `--cs-graph-line-tree` (replaces `--cs-graph-tree`), `-line-related`, `-line-tag`, `-line-lists`, `-line-brings`;
  - `--cs-graph-faded: 0.3`;
  - `--cs-cat-1…6`, lightness only.

  The comment over them says what each is and that a translucent one is its base token's colour as `rgba()`, which a canvas takes. The "until stage 5a" sentence goes.
- Modify `app/assets/tailwind/content-spiel.tailwind.css`: `--color-graph-tag: var(--cs-graph-tag);` in `@theme`.
- Modify `app/javascript/mind_graph/theme.js`:
  - `TOKENS` gains `edge` (`--cs-field-line`), `tag`, `lineTree`, `lineLists`, `lineRelated`, `lineTag` and `lineBrings`, and loses `faint` and `tree`;
  - `faded` is read as a number;
  - the fonts are the sans: `font`, `strongFont` (600) and `countFont` (`500 11px`). `monoFont` and `strongMonoFont` go, and nothing reads `--cs-mono`.
- Modify `marks.js`: `LOOKS.draft.outline` becomes `"edge"`, and `drawTag` strokes `theme.tag`.
- Modify `renderer.js`:
  - `LINE_STYLES` values are `{ colour: <theme key>, width, dash, cap }`, with no `alpha`;
  - the plain pass draws at 1, the faded pass and a dimmed node at `theme.faded`, and the bright pass in ink at 1;
  - `DIM` goes;
  - `LABEL_COLOURS.tag` becomes `"tag"`, and `labelFont` loses its tag case.
- Modify `swatches.js`, if a scene names `faint` or `tree`.
- Modify `card.js`: `TAG_MARK` becomes `"h-2 w-2 shrink-0 border border-graph-tag bg-surface"`.
- Modify `CLAUDE.md` and `docs/reference/cs-studio-shell-and-dashboard.md`, only the no-guard sentences this task retires (Step 3).
- Test: `test/lib/admin_contrast_test.rb`, `test/lib/mind_graph_guards_test.rb`, `test/lib/design_tokens_test.rb` (if it lists the product tokens), `test/system/admin/mind_graph_drawing_modules_test.rb`, `test/system/admin/mind_graph_drawing_test.rb`

**Interfaces:**
- Produces the theme keys `ink meta dim warn surface sunken accent line page edge tag lineTree lineLists lineRelated lineTag lineBrings` (colours), `categories` (six colours), `faded` (a number in 0–1), `font strongFont countFont` and `radius`. Tasks 5 and 6 read no theme key directly. The legend's swatches follow through `swatches.js`.
- The token values, unless Step 0 finds the drawing's:

  | Token | Light | Dark |
  |---|---|---|
  | `--cs-graph-line-related` | `rgba(23,25,31,0.55)` (ink) | `rgba(227,229,236,0.5)` (ink) |
  | `--cs-graph-line-tree` | `rgba(74,79,90,0.7)` (dim) | `rgba(176,182,196,0.7)` (dim) |
  | `--cs-graph-line-tag` | `rgba(90,96,112,0.8)` (meta) | `rgba(156,162,178,0.8)` (meta) |
  | `--cs-graph-line-lists` | `var(--cs-dim)` | `var(--cs-dim)` |
  | `--cs-graph-line-brings` | `var(--cs-line)` | `var(--cs-line)` |
  | `--cs-graph-tag` | `var(--cs-ic-structure)` | `var(--cs-ic-structure)` |
  | `--cs-graph-page` | `var(--cs-ink)` | `var(--cs-dim)` |
  | `--cs-graph-faded` | `0.3` | `0.3` |
  | `--cs-cat-N` | today's hue and chroma, lightness so that each is 5.9–7.1:1 on `--cs-surface` | the same, 8.1–9.1:1 |

- [ ] **Step 0: Read the drawing.** Open `StudioCalmE4More`'s `preview.html` in the Design System artifact. Note the graph's line, tag, page, hue and fade values. Where it writes one, it replaces the default above. Record which values came from where for the PR body.
- [ ] **Step 1: Write the failing tests.**
  - `admin_contrast_test.rb`. A figure the spec gives is a floor to its rounding: 6.9 is met by 6.85.
    - `test "a post's six hues are 5.9 to 7.1:1 on the canvas in light and 8.1 to 9.1:1 in dark, each on its own hue"`. Each slot is in its band, and each slot's oklch hue is today's (light `200 300 120 0 230 95`, dark `200 300 120 0 260 95`). This replaces "each of the six type hues is 3:1…", whose dark `cat-5` literal goes.
    - `test "the graph's related line is 3.9 / 4.3:1 and its tree line 3.8 / 4.5:1 on the canvas, each under its figure plus 0.4, and the shared-tag and lists lines 3:1 or better"`. The upper bound keeps a line from reading as text.
    - `test "a tag is 6.2 / 8.9:1 or better, a page's mark 3:1 or better and in dark below the ink, and the selection ring 6.9 / 7.1:1"`. This replaces "the Mind graph's page mark and tree line…".
    - `test "what a selection leaves out stays seen and never reads as a control"`. In both schemes, ink at `--cs-graph-faded` over the surface is under 3:1, and the faintest of the six hues at it is 1.5:1 or better.
    - `test "a graph line's translucent colour is its base token's colour"`. Each `rgba()` of `--cs-graph-line-*` has the red, green and blue of the hex of `--cs-ink`, `--cs-dim` or `--cs-meta` in its scheme, as the comment beside it names.
  - `mind_graph_guards_test.rb`:
    - `test "the canvas's text is in the sans: no script of the mind graph reads --cs-mono or names a mono font"`, with a sample `read("--cs-mono")` that the pattern matches;
    - `test "no script of the mind graph sets a strength but 1: what fades is the theme's"`. `globalAlpha =` followed by a number other than `1` is refused in `marks.js`, `renderer.js` and `swatches.js`. Samples: `globalAlpha = 0.35` is matched; `globalAlpha = 1` and `globalAlpha = theme.faded` are not.
    - `test "every theme key LOOKS and LINE_STYLES name is one theme.js reads"`. The keys are parsed from the two tables and from `TOKENS`.
    - `test "the marks drawn in CSS outside the canvas are in the canvas's tokens"`, three cases:
      - `TAG_MARK`'s `border-<x>` names the token `theme.js` reads for the key `drawTag` strokes with;
      - `dotClass`'s ring for a retired type names `drawPost`'s retired key's token;
      - `Admin::Ui::ContentTypeDotComponent::FILLED[i]` holds `bg-cat-#{i + 1}`, as `theme.categories[i]` reads `--cs-cat-#{i + 1}`.
  - `mind_graph_drawing_modules_test.rb`:
    - "theme: every key reads the token the design names…" takes the new `TOKENS` and asserts `faded` is a number, `countFont` is `500 11px <the page's sans>` and no mono font key exists;
    - `LINES` and "renderer: each kind of line has its style…" lose the alpha column and assert the plain pass at `globalAlpha` 1;
    - "renderer: a selection brightens its edges and fades the rest to 28 percent…" becomes "…fades the rest to the theme's faded strength…". It draws with a test theme whose `faded` is 0.5 and asserts 0.5, so a constant written back into the renderer fails it;
    - "renderer: a label is ink for a page and a type, dim for a post, mono meta for a tag…" becomes "…the tag hue for a tag, in the sans…";
    - the mark tests that name `meta` for a draft's outline or a tag's edge take `edge` and `tag`;
    - `test "renderer: the notes count is in the sans at 11px and the widest count, 99+, fits its badge"`. After `document.fonts.load(theme.countFont)`, `measureText("99+")` plus two `NOTES_BADGE_PAD` is within the pill's width.
  - `mind_graph_drawing_test.rb`: `test "the canvas's fonts are faces the page has loaded when the graph is drawn"`. After `await_graph`, `document.fonts` holds a `FontFace` with `status === "loaded"` whose family is the first family of each of `font`, `strongFont` and `countFont` as `readTheme` answers them, at that font's weight (400, 600, 500). `document.fonts.check` alone is not enough: it answers true for a family no face matches.
- [ ] **Step 2: Run them, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/lib/admin_contrast_test.rb test/lib/mind_graph_guards_test.rb`. The two module and browser files fail on the old keys.
- [ ] **Step 3: Implement.**
  - Retune each `--cs-cat-N` with `ContrastMeasure` from a console script in the scratchpad, never by eye.
  - Search the tests by hand for `--cs-cat-`, `oklch(0.5`, `oklch(0.7`, `graph-tree`, `faint` and `monoFont`, and fix each hit in this task.
  - The `marks.js` and `renderer.js` header comments state the new keys, and the notes badge's comment says the count is the sans.
  - The no-guard rules this task retires go in this task:
    - in `CLAUDE.md`, the sentence "A post's dot and a tag's square outside the canvas are CSS spans… **no guard** holds them against `mind_graph/marks.js`", and the type-voice bullet's "or for the Mind graph canvas's own fonts…";
    - in `docs/reference/cs-studio-shell-and-dashboard.md`, the matching sentence of "Rules a change can break silently", which now cites the new guard by name.
- [ ] **Step 4: Run them, and verify they pass.**
  - Run `bin/rails tailwindcss:build`, then `test/lib`.
  - Then, one at a time: `mind_graph_drawing_modules_test.rb`, `mind_graph_drawing_test.rb` (the pixel tests of a live and a draft post read the new colours from the page), `mind_graph_selection_test.rb`, `mind_graph_legend_test.rb`, then `posts_list_test` and `drafts_test`, which draw type dots.
  - Expected: PASS.
- [ ] **Step 5: Commit** `feat: the mind graph draws from its own E4 tokens, at the measured contrast, in the sans` (body: `Advances #117`)

---

### Task 5: The list's and the card's chips, and the shared button

**Files:**
- Create `app/components/admin/mind_graph_screen/parts_component.{rb,html.erb}` and its keys in `config/locales/admin/mind_graph_screen.en.yml` (`parts.close: "Close"`), with a preview under `test/components/previews/admin/mind_graph_screen/`.
- Create `app/javascript/mind_graph/parts.js`.
- Modify `card.js`: the chip, Close, and `STATUS_DOTS` and `DOT` deleted.
- Modify `node_list.js`: the group headings' icon chips and the rows' status chips. Its retry button takes `buttonClasses.tertiary`.
- Modify `app.js`: it reads the parts and hands them to the card and the list. Retry is `buttonClasses.tertiary`.
- Modify `app/views/admin/mind_graph/show.html.erb`:
  - render `PartsComponent` inside the graph's element;
  - `data-button-classes` gains `tertiary`;
  - "Show everything" becomes `ButtonComponent` (`:tertiary`, `size: :small`), with its `data` and `aria` as today;
  - `data-messages` loses `card.close`, `card.status.draft`, `.scheduled`, `.live` and `.unpublished_changes`.
- Modify `config/locales/admin/mind_graph.en.yml`: the five keys above are deleted. `card.status.change_scheduled`, `live_with_changes` and `live_change_scheduled` stay.
- Modify `test/lib/admin_design_rules_test.rb`: `STATUS_FILL_FILES` loses `app/javascript/mind_graph/card.js`, whose `STATUS_DOTS` were its last status fill. Without this, "the status-fill list holds only files that still draw a status fill" goes red. The cloned chips carry their fills from the components' own files, which the guard already lists.
- Test: `test/components/admin/mind_graph_screen/parts_component_test.rb` (new), `test/integration/admin/mind_graph_test.rb`, `test/system/admin/mind_graph_card_and_list_modules_test.rb`, `mind_graph_selection_test.rb`, `mind_graph_loading_test.rb`, `test/lib/admin_i18n_test.rb`, `test/lib/admin_design_rules_test.rb`

**Interfaces:**
- `Admin::MindGraphScreen::PartsComponent.new` draws `template[data-mind-graph-parts]`. It holds one `span[data-part=<name>]` per part, each wrapping one component's markup:
  - `status-live`, `status-draft`, `status-scheduled`: `StatusChipComponent.new(status:)`;
  - `unpublished`: `UnpublishedChipComponent`;
  - `icon-page` (`:pages`, `:structure`), `icon-post` (`:posts`, `:lists`), `icon-tag` (`:tags`, `:lists`), `icon-type` (`:clipboard_list`, `:lists`): `IconChipComponent` at `size: :small`;
  - `close`: `ButtonComponent.new(label: t(".close"), icon: :x, variant: :tertiary, size: :small, data: { mind_graph_card_close: "" })`.

  `NAMES` lists them in that order. A `<template>`'s content is no part of the document, so the page's text, its Tab order and `reset()` do not meet it.
- `mind_graph/parts.js` exports `readParts(element) -> { part(name) -> Element }`. Each call answers a deep clone of that part's one child. An unknown name throws `Error("mind graph: no part named <name>")`, loud as a failed import is.
- `createCard(container, { …, parts })`:
  - a node with one state gets the clone of `status-<status>` beside what it is;
  - a live node with changes gets a row under the first, `aria-hidden`, holding `status-live` and then `unpublished`, or the words `card.status.change_scheduled` with its `date`;
  - the sr-only sentence stays;
  - `data-status` (the state's name) moves onto the row's first chip, or the single chip;
  - Close is `parts.part("close")` with its click wired, still the card's last child.
- `createList(container, { …, parts })`:
  - a group heading starts with `icon-<kind>`;
  - a page's or a post's row gets `status-draft` or `status-scheduled`, or `unpublished` for a live record whose `changes` is set, after its title;
  - a live row with no changes gets none;
  - a chip is `aria-hidden`, and a row's `aria-label` is unchanged.

- [ ] **Step 1: Write the failing tests.**
  - `parts_component_test.rb`:
    - `test "the parts are one template holding the three status chips, the unpublished chip, an icon chip per kind and Close as the shared icon button"`. Assert:
      - each `data-part` and `NAMES`;
      - the chips' own classes (`bg-live`, the Draft's `border-field-line`, `bg-scheduled`);
      - each icon chip's family classes (`bg-ic-structure-bg` for a page, `bg-ic-lists-bg` for the other three);
      - the Close button's `aria-label="Close"`.
    - `test "a part is the shared component's own markup"`. Assert `status-draft`'s inner HTML equals `render_inline(StatusChipComponent.new(status: "draft"))`, and the same for one icon chip and Close.
  - `mind_graph_test.rb` (integration): `test "the parts template is inside the graph's element, once"`.
  - `mind_graph_card_and_list_modules_test.rb`:
    - "card: the chip says each of the five states…" becomes `test "card: the chip is the shared status chip in each of the five states, the second state as the editor's header says it, and in the key's words for a screen reader"`. Each chip in the card `isEqualNode` to the clone `parts.part("status-…")` answers, so a chip copied by hand into the script fails it;
    - `test "card: Close is the shared icon button, named Close, last in the card"`;
    - `test "list: each group's heading carries its kind's icon chip, a draft's and a scheduled record's row its status chip, a changed live row the unpublished chip, and a live row none, all hidden from a screen reader"`;
    - `test "parts: a part the page does not hold is an error, not an empty card"`.
    - `CARD_SCRIPT` and `LIST_SCRIPT` render a `PartsComponent` template into the page they build.
  - `mind_graph_selection_test.rb`:
    - "the card reads top to bottom: kind and status…", "a draft's card says Draft" and "a page's card says its address, state, counts and notes…, a scheduled change says its day behind a warn dot…" read the shared chip. The last one's "behind a warn dot" becomes "beside the Live chip", and its name changes with it;
    - `test "the card's chips follow the theme, and what is typed in the card stays"`: Review Focus 1. Open a post's card, type in its note field, and switch to dark. Assert the Live chip's computed `background-color` equals `--cs-live` read from the page in dark, and the field keeps its text;
    - `test "a two-state chip wraps inside the card, clear of Close, in German too"`: Review Focus 2. A live post with a scheduled change. Assert the chip row's right edge is at most the card's right edge less its padding, and above Close's bottom edge nothing of the row overlaps Close's box.
  - `mind_graph_loading_test.rb`: the Retry test and the "Show everything" test find their button by role and name, and assert it carries the tertiary variant's classes from `data-button-classes` (Retry) or is the component's (Show everything).
  - `admin_i18n_test.rb`: `parts_component.{rb,html.erb}` and `app/javascript/mind_graph/parts.js` join `CONVERTED`.
- [ ] **Step 2: Run them, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/components/admin/mind_graph_screen test/integration/admin/mind_graph_test.rb test/lib`.
- [ ] **Step 3: Implement.** `card_notes.js` keeps its buttons through `buttonClasses`. Search the tests by hand for `mindGraphCardClose`, `data-chip-seen` and the deleted keys' words, and fix each hit.
- [ ] **Step 4: Run them, and verify they pass.** Run `test/lib test/components/admin test/integration/admin/mind_graph_test.rb`. Then, one at a time: `mind_graph_card_and_list_modules_test.rb`, `mind_graph_selection_test.rb`, `mind_graph_loading_test.rb`, `mind_graph_list_test.rb`, `mind_graph_notes_test.rb` and `mind_graph_worker_and_back_test.rb` (Back still shows no card and an empty list). Expected: PASS.
- [ ] **Step 5: Commit** `feat: the mind graph's list and card carry the shared chips, and its buttons are the shared button` (body: `Advances #117`)

---

### Task 6: The status key on the legend's row, and the zoom control

**Files:**
- Modify `app/components/admin/mind_graph_screen/legend_component.{rb,html.erb}`:
  - a third section `div[data-legend-section=status]` after Key, labelled `t(".states_label")` ("Status") like Key;
  - it holds `ul[data-legend-states]` with five `li[data-legend-state=<state>]`, each a `SwatchComponent` (`state-<dasherized>`) and `t(".states.<state>")`;
  - `STATES` moves here from `StatusKeyComponent`;
  - the "Status key…" button goes;
  - the class comment's STATUS IS NOT A FILTER paragraph says the looks are a key on the row.
- Delete `app/components/admin/mind_graph_screen/status_key_component.{rb,html.erb}`, `test/components/admin/mind_graph_screen/status_key_component_test.rb`, and the render in `show.html.erb`.
- Modify `config/locales/admin/mind_graph_screen.en.yml`:
  - `legend.status` and `status_key.*` are deleted;
  - `legend.states_label: "Status"` and `legend.states.{live,draft,scheduled,live_with_changes,live_change_scheduled}` are added, with today's words;
  - the file's comment names the words' guard.
- Modify `show.html.erb`:
  - the zoom group becomes `rounded-button`, its buttons `text-small` in place of `text-[13px]`;
  - the readout becomes `text-count tabular-nums text-meta`;
  - the comments about the status key's dialog go.
- Modify `app/javascript/controllers/admin/mind_graph/graph_controller.js`: the header's sentences about the "Status" key's dialog become one: the legend's swatches are `admin--mind-graph--swatches`' own, drawn on its connect. `reset()` is unchanged, since nothing new is written.
- Modify `app/javascript/controllers/admin/mind_graph/swatches_controller.js`, its comment ("on the legend and on the key's list" becomes the legend).
- Modify `docs/reference/cs-studio-shell-and-dashboard.md`. This task owns, whole:
  - the "Status is not a filter" paragraph (the looks on the legend's row);
  - the legend's paragraph where it names the "Status key…" button and the Tab order;
  - the `reset()` rule's "Not the graph's, so not touched: the status key…";
  - the status-words sentence of "Rules a change can break silently", which now cites the new guard.
- Modify `CLAUDE.md`: the status-words sentence of "The Mind graph" ("The status key's five names are the chip's words… **no guard** holds that") goes, and the index line names the legend's states in place of "the status key". Task 7 does not touch these again.
- Test: `test/components/admin/mind_graph_screen/legend_component_test.rb`, `test/components/previews/admin/mind_graph_screen/legend_component_preview.rb`, `test/integration/admin/mind_graph_test.rb`, `test/lib/mind_graph_guards_test.rb`, `test/system/admin/mind_graph_legend_test.rb`, `mind_graph_worker_and_back_test.rb`, `mind_graph_drawing_modules_test.rb`, `mind_graph_drawing_test.rb`, `mind_graph_list_test.rb`

**Interfaces:**
- `Admin::MindGraphScreen::LegendComponent::STATES = %i[live draft scheduled live_with_changes live_change_scheduled]`. The swatch names `state-*` and `SwatchComponent::SIZES` are unchanged.

- [ ] **Step 1: Write the failing tests.**
  - `legend_component_test.rb`:
    - `test "the legend's Status group holds the five looks in the chip's words, each with its canvas swatch, after the keys"`. The order of the sections is `show key status`. The five words and their `data-legend-state` are in `STATES`' order, and each `li` holds one `canvas[data-swatch=state-…][aria-hidden]`.
    - `test "the legend has a row for every state a record can be in, and no other"` (moved from the deleted component's test).
    - `test "the legend opens no dialog and has no button"`.
    - "every toggle and every key has a swatch…" also counts the five state swatches.
  - `mind_graph_guards_test.rb`: `test "the legend's status words are the chip's: the status chip's three labels and the card's two sentences without their day"`.
    - `legend.states.live/draft/scheduled` equal `admin.components.ui.status_chip.labels.*`.
    - `legend.states.live_with_changes` equals `admin.mind_graph.script.card.status.live_with_changes`.
    - `legend.states.live_change_scheduled` equals `card.status.live_change_scheduled` with `" %{date}"` removed.
    - A sample with one word changed in a copied Hash fails the comparison, so the test can fail.
  - `mind_graph_test.rb` (integration):
    - "the status key is in the page once, a closed dialog outside the graph's element" becomes `test "the status looks are in the legend's row, inside the graph's element, and the page holds no status dialog"`;
    - the two Tab-order tests, whose expected lists end the legend with "Status key…" (today's lines 466 and 594), lose that entry;
    - the comments at today's lines 336 and 431–448 are rewritten.
  - The existing browser tests that name the key change in this task:
    - in `mind_graph_worker_and_back_test.rb`, "Back to the graph draws it once…" counts the legend's swatches with the five state swatches in it, and drops `#mind-graph-status-key`;
    - in `mind_graph_drawing_test.rb`, "the theme's colours are read from the page…" waits for 16 legend swatches, where today it is 11 plus the key's;
    - in `mind_graph_list_test.rb`, "the Tab key meets the search first and the list last" loses "Status key…" from its stops.
  - `mind_graph_legend_test.rb`: "the Status key opens from the keyboard as a dialog, and Escape gives the focus back" becomes `test "the legend's status looks are drawn by the canvas's renderer, and Tab goes from the last toggle to the zoom buttons"`. The first part asserts each state swatch has drawn pixels, with the drawing file's pixel helper.
  - `mind_graph_worker_and_back_test.rb`: `test "Back to the graph draws the legend's status looks again and shows no chip from the visit that was left"` (Review Focus 4). Open a draft's card, leave, go Back.
    - First assert the precondition, before leaving: the list holds the draft's row with its `.admin-status-chip`.
    - After Back, assert that the five state swatches have pixels before the data arrives, and that no `[data-mind-graph-list] .admin-status-chip` and no card chip exists until the data is back.
  - `mind_graph_drawing_modules_test.rb`: "swatches: the Status key's five looks are the canvas's own drawing…" becomes "swatches: the legend's five status looks are the canvas's own drawing…".
  - `mind_graph_drawing_test.rb`: `test "the zoom readout is a figure in the sans with even digits, beside the zoom buttons"`. Its computed `font-variant-numeric` includes `tabular-nums`, its `font-family` is the page's sans, and its text is the zoom as a percentage after a zoom.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests and the docs by hand for `status_key`, `mind-graph-status-key`, `legend_status` and "Status key", and fix each hit.
- [ ] **Step 4: Run them, and verify they pass.** Run `test/lib test/components/admin test/integration/admin/mind_graph_test.rb`, then `bin/rails tailwindcss:build`. Then, one at a time: `mind_graph_legend_test.rb`, `mind_graph_worker_and_back_test.rb`, `mind_graph_drawing_test.rb`, `mind_graph_drawing_modules_test.rb` and `mind_graph_list_test.rb`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: the mind graph's status looks stand on the legend's row, and the zoom readout is a figure` (body: `Advances #117`)

---

### Task 7: 5a-2's reference, CLAUDE.md and the pull request

**Files:**
- Modify `docs/reference/cs-studio-shell-and-dashboard.md`, "Mind graph":
  - "The theme's keys and the token behind each": the new table;
  - "The lines": the five tokens, no alphas in the script;
  - "The five looks…": a draft's `edge`;
  - "The marks": a tag in the structure hue;
  - "The states": the faded strength is `--cs-graph-faded`;
  - the parts template and `parts.js`;
  - the fonts.
  ("Status is not a filter", the `reset()` rule and the two retired no-guard sentences are Tasks 4's and 6's, and are not touched again.)
- Modify `docs/reference/design-system.md`: a part "E4: the mind graph", covering the graph tokens and why a line is `rgba()`, the chips cloned from server-rendered parts, and the canvas in the sans.
- Modify `CLAUDE.md`: the shell index line's file list gains `state.js`, `frame.js`, `gestures.js`, `selection.js`, `list_reads.js`, `notice.js`, `parts.js` and `PartsComponent`.
- Modify `CHANGELOG.md`, `## Unreleased`:
  - Changed: the mind graph's colours, chips and legend; the type dots' lightness;
  - Removed: the mind graph's Status key dialog.
- Test: `PGGSSENCMODE=disable bin/rails test test/lib`, `bin/rubocop`, `bin/rails zeitwerk:check`, `bin/brakeman`, `bin/changelog-guard`

- [ ] **Step 1: Write the reference, CLAUDE.md and CHANGELOG changes.**
- [ ] **Step 2: Run** the five checks. Expected: all pass.
- [ ] **Step 3: Write the PR body.**
  - Base: `studio-e4-5a`, or `main` once 5a-1 has merged.
  - Findings: Advances #117.
  - "For the owner to check" lists:
    - every **(owner)** of the decisions table;
    - which values came from the drawing and which from measurement (Task 4 Step 0);
    - the chip's `warn` dot against the canvas's `dim` corner dot for unpublished changes;
    - the bright pass at full ink.
  - It names the Documentation below.
- [ ] **Step 4: Check no test run is left**: `pgrep -f "rails test"` prints nothing.
- [ ] **Step 5: Commit** `docs: E4 stage 5a in the reference and CLAUDE.md` (body: `Advances #117`)

**Documentation (5a-2), in `/Users/dknafelj/src/contentspiel-docs`:**
- pages:
  - `docs/editors/posts/tags-related-posts-and-the-mind-graph.md` (the colours, the status looks on the legend instead of the Status key, the card's chips, the list's chips);
  - `docs/editors/working-together/notes-on-content.md` (the card's Close);
  - `docs/editors/posts/posts-and-content-types.md` (a type's dot's colour).
- screenshots: `mind-graph` (its recipe in `screenshots/recipes.rb`), retaken in both themes.

---

## Architecture-review findings

Checked on 2026-11-07 against every open issue labelled `architecture-review`.

| Issue | Taken | Why |
|---|---|---|
| #132 split the largest scripts and controllers | advances (Task 3): `mind_graph/app.js` into six modules | 5a changes the legend's, the list's and the card's wiring in `app.js`, and the spec names this split. `hold_controller.js`, `table_controller.js`, the rich-text editor controller and the posts and pages controllers remain |
| #133 entry helpers, large system files | advances (Tasks 1, 2): the graph's two files, the last two of the three the issue names (`sections_test` went in stage 2) | 5a rewrites tests in both. Shorter test names remain, because the reference still quotes them |
| #117 comments about invariants | advances, every task | the graph's files are thick with "spec §", "Task 7's review" and "the ruling on the review of"; every file a task touches is rewritten by the rule |
| #119 the reference docs' structure, and a guard for cited test names | not taken | Tasks 1 and 2 rename 22 citations of the two files by hand, which is the hazard #119 names. The guard and the split of `cs-studio-shell-and-dashboard.md` are a change of the docs' structure that E4 does not make |
| #124 admin scripts on demand | not taken | `mind_graph/` is already `preload: false` and reached by `import()`; the six new modules are pinned by the same `pin_all_from` |
| #127 slots fit one shape | not taken | the graph has no slot |
| #112, #114 to #116, #120 to #122, #128 to #131, #135 to #138, #140 to #143, #185 | not taken | no task changes their code |

## Browser tests

Run locally after `bin/rails tailwindcss:build`, one file at a time, only while the one-minute load is under 6, each prefixed with `PGGSSENCMODE=disable`.

**The implementer must run:**
- 5a-1: each of the nine browser files and the five module files once, after Tasks 1 and 2, then all fourteen again after Task 3.
- 5a-2:
  - `mind_graph_drawing_modules_test`, `mind_graph_drawing_test`, `mind_graph_selection_test` and `mind_graph_legend_test` (Task 4);
  - `posts_list_test` and `drafts_test` (the type dots);
  - `mind_graph_card_and_list_modules_test`, `mind_graph_loading_test`, `mind_graph_list_test`, `mind_graph_notes_test` and `mind_graph_worker_and_back_test` (Tasks 5 and 6).

**Likely to change, left to CI** (the whole browser suite runs per PR):
- `tokens_related_posts_and_starter_pages_test`;
- `theme_toggle_test` (the canvas redraws on a theme change);
- any test that reads a type dot's colour.

A CI failure is fixed in the task that owns the file.
