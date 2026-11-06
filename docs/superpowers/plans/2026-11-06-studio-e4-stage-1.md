# CS Studio in E4, Stage 1 (foundations) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recolour and reshape every CS Studio screen at once by giving today's tokens E4's values, adding E4's new tokens, and restyling the shared components, the fields, the labels and the sidebar. The form-send pages stay neutral. Guards keep the old look from creeping back.

**Architecture:** E4's values go under today's token names in `app/assets/tailwind/content-spiel.css`, so every utility (`bg-paper`, `text-accent`, …) changes at once. New tokens are added beside them, and each is mapped to a utility in `content-spiel.tailwind.css`. The shared components in `app/components/admin/ui/` take E4's buttons, fields, radii, elevations and chips. A new `Admin::Ui::IconChipComponent` draws a block type's icon and a sidebar entry's icon. The sidebar's modules become a registry (`StudioModules`, advancing #127). `test/lib/admin_design_rules_test.rb` and `test/lib/admin_contrast_test.rb` hold the result.

**Tech Stack:** Rails 8.1, ViewComponent with Lookbook previews, Tailwind v4 (`tailwindcss-rails`), Stimulus over import maps, Minitest with Capybara on Cuprite.

**Spec:** `docs/superpowers/specs/2026-11-06-studio-e4-design.md` (approved 2026-11-06; architecture-review findings folded in by f52c9082). The sections this plan uses: "The design, as decided", "Stage 1", "The guard after E4", "Constraints", "Left to the builder" and "Architecture-review findings".

## Global Constraints

- Every text pair is 4.5:1, and every control edge, state mark, icon and focus ring is 3:1, in both themes. `test/lib/admin_contrast_test.rb` measures these; nobody judges them by eye.
- Colour is never the only cue. Every status, role and type keeps its word or name beside it.
- No admin string is a literal. A new word is a key in `config/locales/admin/<folder>.en.yml`, read with `t(".key")`. A script's words come from `data-messages`. A new shared component joins `CONVERTED` in `test/lib/admin_i18n_test.rb`.
- Nothing changes the save rule, the write queue (`app/javascript/saving/queue.js`), live editing or the leave guard. Every form keeps its ids, its `base_updated_at` and its `data-editing-*` marks.
- A component used by more than one screen goes in `app/components/admin/ui/`. Nothing is loose in `app/components/admin/` (`source_layout_test`). No `Admin::<Domain>` is defined.
- No colour literal and no `dark:` variant in CS Studio's sources. A colour is a token.
- The public theme (`th-*`, `app/assets/tailwind/themes/`) is untouched. No product token reaches `theme.css` (`design_tokens_test`).
- No Turbo morphing. Nothing writes `--admin-tree-width` or `data-tree-fits` but the two writers named in `CLAUDE.md`.
- Comment rule (#117): a comment states a current invariant, a hazard or a reason. It never states a plan step, a review round or what used to be there. Every task applies the rule to the comments of the files it changes, and no task adds a "Task N" or "spec §" reference.
- On macOS every test command is prefixed with `PGGSSENCMODE=disable`. Run browser tests only on a quiet machine: check `sysctl -n vm.loadavg` and compare the load with the number of cores. Run `bin/rails tailwindcss:build` first, never while tests run.
- Commits follow conventional commits and end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. A task that carries a finding says so in its message: "Advances #127", "Advances #133", "Advances #117".
- Parts of "The guard after E4" are not in this stage, because the code they hold is built later:
  - the 900px column and the 360px rail written once (Stage 3a);
  - avatar initials under the 11px rule (Stage 6);
  - the people tokens in the marker, the row pill, the hold strip and the people frame (Stage 6; Task 7's guard already admits those files).

  Each of those stages adds its part to `admin_design_rules_test.rb`.
- A choice that changes what a person sees and that the spec does not settle goes to the owner before it ships. Each such choice is marked **(owner)** below. Each has a default the build goes ahead on.

## Review Focus

1. **A component or view still hard-codes a palette colour, a `white`/`black` utility, a non-token shadow or a non-token radius.** The palette and white parts are covered by Task 5. The shadow and radius parts are covered by Task 9. Each pattern guard has a sample test that proves it can fail.
2. **Focus rings under 3:1 in dark mode on the new grounds.** The rail (`#1f2a3d`) and the popover (`#283244`) are the darkest. Task 1 measures the accent ring on every ground, the popover included, in both schemes.
3. **The form-send pages turn violet.** They share the product stylesheet. Task 2 measures the re-valued accent family. An integration test asserts the mark on `<html>`, and a CSS test asserts that the plain block sets every accent token.
4. **Mono or capitals left where the guard can't see them.** Places the guard misses: CSS rules in the stylesheets, classes built in scripts, and words that are literal capitals in a key. Task 3 extends the guard to `app/javascript/**`. It adds a stylesheet check for `text-transform: uppercase` and a sample test. Task 4 does the same for `font-family: var(--cs-mono)`.
5. **A status colour used without its word, or the new live/scheduled fills spreading.** Task 10 confines `--cs-live` and `--cs-scheduled` to their components. It ratchets the ok/warn/danger fills to today's files. The status chip's test asserts the word beside each fill.

---

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `app/assets/tailwind/content-spiel.css` | every token value, both schemes; the plain-surface block | 1, 2, 3, 7 |
| `app/assets/tailwind/content-spiel.tailwind.css` | `--color-*`, `--shadow-*`, `--radius-*`, `--text-*` mappings; fields, select, checkbox, toggle, drag, dialog rules | 1, 3, 6, 9 |
| `app/assets/tailwind/admin-rich-text.css` | the rich-text box as a field | 6 |
| `app/views/layouts/form_send.html.erb` | the plain-surface mark | 2 |
| `app/helpers/setup_helper.rb` | label, input, button class strings of the wizard and auth pages | 3, 5, 6 |
| `app/components/admin/ui/*` | the shared components | 3, 4, 5, 6, 7, 9, 10 |
| `app/components/admin/ui/icon_chip_component.rb` (new) | an icon on its family's chip | 7 |
| `app/models/content_model/block_type_definition.rb`, `app/models/block_types/*.rb` | a block type's icon family | 7 |
| `app/models/studio_modules.rb` (new), `config/initializers/studio_modules.rb` (new) | the sidebar's modules as a registry (#127) | 8 |
| `app/controllers/admin/base_controller.rb`, `app/components/admin/shell/sidebar_component.*`, `app/views/layouts/admin.html.erb`, `app/helpers/admin/jump_helper.rb` | read the registry | 8 |
| `test/lib/admin_design_rules_test.rb` | the guard after E4, the parts Stage 1 can hold | 3, 4, 5, 6, 7, 9, 10 |
| `test/lib/admin_contrast_test.rb` | every pair measured | 1, 2, 7 |
| `test/application_system_test_case.rb`, `test/system/README.md` (new) | entry helpers and the browser-test rules (#133) | 11 |
| `docs/reference/design-system.md`, `docs/reference/writing-tests.md`, `docs/reference/content-blocks-and-types.md`, `CLAUDE.md` | the reference | 12 |

---

### Task 1: E4's token values and their measurements

**Files:**
- Modify: `app/assets/tailwind/content-spiel.css` (both colour blocks; the `:root` block of radii)
- Modify: `app/assets/tailwind/content-spiel.tailwind.css` (the `@theme inline` block)
- Test: `test/lib/admin_contrast_test.rb`, `test/integration/design_tokens_test.rb`

**Interfaces:**
- Produces these utilities for every later task: `bg-field-fill`, `bg-rail`, `bg-popover`, `bg-structure`/`border-structure`, `bg-structure-tint`, `text-structure-ink`, `bg-live`, `text-on-live`, `bg-scheduled`, `text-on-scheduled`, `bg-head-{action,cool,warm}` with `text-head-{action,cool,warm}-ink`, `bg-type-chip`, `text-type-chip-ink`, `text-on-danger`. Also `shadow-1` … `shadow-4`, and `rounded-field`, `rounded-button`, `rounded-button-sm`, `rounded-chip`, `rounded-tile`, `rounded-card`, `rounded-frame`, `rounded-rail` (with Tailwind's side forms, such as `rounded-t-field`).
- `--cs-shadow-menu` is renamed `--cs-shadow-3`. The stylesheet's own `var(--cs-shadow-menu)` uses (`.admin-drag-chosen`, `.admin-drag-fallback`) switch to `var(--cs-shadow-3)` here. The utility `shadow-menu` stays as an alias, `--shadow-menu: var(--cs-shadow-3)`, until Task 9 removes it. That keeps this commit green.

Today's names that take E4 values (**retune**). Values are light / dark:

| Token | Light | Dark |
|---|---|---|
| `--cs-paper` | `#f3f4f7` | `#14161c` |
| `--cs-surface` | `#ffffff` | `#1d2029` |
| `--cs-chrome` | `#ffffff` | `#181a21` |
| `--cs-sunken` | `#e7e9ef` | `#252935` |
| `--cs-ink` | `#17191f` | `#e3e5ec` |
| `--cs-dim` | `#4a4f5a` | `#b0b6c4` |
| `--cs-meta` | `#5a6070` | `#9ca2b2` |
| `--cs-field-line` | `#808797` | `#7a8191` |
| `--cs-line` | `rgba(23,25,31,0.10)` | `rgba(255,255,255,0.08)` |
| `--cs-line-strong` | `rgba(23,25,31,0.22)` | `rgba(255,255,255,0.16)` |
| `--cs-accent` | `#6236d9` | `#b49cff` |
| `--cs-accent-hover` | `#5831c3` | `#bca6ff` |
| `--cs-on-accent` | `#ffffff` | `#140c2e` |
| `--cs-accent-tint` | `#ece6fd` | `#2c2350` |
| `--cs-shadow-stuck` | `0 -6px 16px rgba(23,25,31,0.06)` | `0 -6px 16px rgba(0,0,0,0.35)` |

`--cs-accent-hover` follows the spec's rule: about 10% darker in light and 10% lighter in dark. The hex values are this plan's arithmetic. White on the light hover measures 7.95:1, and `--cs-on-accent` on the dark hover 8.95:1. `--cs-ok*`, `--cs-warn*`, `--cs-danger*`, `--cs-cat-1…6`, `--cs-graph-*` and `--cs-ph-*` keep their values. They were measured on the E4 grounds for this plan (state marks 4.1:1 or better, inks 6.3:1 or better), so none is retuned.

New tokens (**add**). Values are light / dark:

| Token | Light | Dark | Role |
|---|---|---|---|
| `--cs-field-fill` | `#f1f3f7` | `#272b36` | a text field's ground |
| `--cs-rail` | `#eaf1fb` | `#1f2a3d` | elevation 2: a rail or panel |
| `--cs-popover` | `#ffffff` | `#283244` | elevation 3: popover, menu, dialog, a dragged card |
| `--cs-structure` | `#c98a4b` | `#b9824a` | a section's 1.5px frame |
| `--cs-structure-tint` / `--cs-structure-ink` | `#fbeedd` / `#7a4a12` | `#3a2a17` / `#f0c48f` | a section's head and its words |
| `--cs-live` / `--cs-on-live` | `#1c7a46` / `#ffffff` | `#5cc48f` / `#0f1a14` | the solid "● Live" chip |
| `--cs-scheduled` / `--cs-on-scheduled` | `#e8a93a` / `#3a2600` | `#e3a650` / `#2a1c00` | a scheduled date's block |
| `--cs-head-action` / `--cs-head-action-ink` | `#ece6fd` / `#45249f` | `#2c2350` / `#cdbfff` | a panel that asks for action |
| `--cs-head-cool` / `--cs-head-cool-ink` | `#e6ecfb` / `#24418f` | `#22304d` / `#a9c0ff` | a panel of shortcuts |
| `--cs-head-warm` / `--cs-head-warm-ink` | `#fbeedd` / `#7a4a12` | `#3a2a17` / `#f0c48f` | a panel that informs |
| `--cs-type-chip` / `--cs-type-chip-ink` | `#e6ecfb` / `#2b50c8` | `#24304f` / `#9db4ff` | the type chip |
| `--cs-on-danger` | `#ffffff` | `#1a0b0b` | words on the danger fill **(owner)** |
| `--cs-shadow-1` | `0 1px 2px rgba(23,25,31,0.06), 0 4px 12px rgba(23,25,31,0.05)` | `inset 0 1px 0 rgba(255,255,255,0.04)` | elevation 1 |
| `--cs-shadow-2` | `0 2px 4px rgba(23,25,31,0.07), 0 12px 28px rgba(23,25,31,0.09)` | `inset 0 1px 0 rgba(255,255,255,0.06), 0 8px 24px rgba(0,0,0,0.35)` | elevation 2 |
| `--cs-shadow-3` (renames `--cs-shadow-menu`) | `0 3px 8px rgba(23,25,31,0.09), 0 18px 40px rgba(23,25,31,0.12)` | `inset 0 1px 0 rgba(255,255,255,0.07), 0 12px 32px rgba(0,0,0,0.45)` | elevation 3 |
| `--cs-shadow-4` | `0 6px 12px rgba(23,25,31,0.12), 0 28px 56px rgba(23,25,31,0.20)` | `inset 0 1px 0 rgba(255,255,255,0.08), 0 24px 56px rgba(0,0,0,0.6)` | elevation 4 |

`--cs-on-danger` is new because today's `text-white` on the dark danger fill measures 3.11:1, which fails 4.5:1. `#1a0b0b` measures 6.15:1. With it, a dark-mode destructive confirm has dark words **(owner)**.

Radii (**add**, in the scheme-independent `:root` block): `--cs-radius-field: 6px`, `--cs-radius-button: 8px`, `--cs-radius-button-sm: 7px`, `--cs-radius-chip: 7px`, `--cs-radius-tile: 12px`, `--cs-radius-card: 14px`, `--cs-radius-frame: 16px`, `--cs-radius-rail: 18px`. `--cs-radius` (2px) and `--cs-radius-pill` are kept. `--cs-radius` stays the radius of small marks: a status, translation or channel chip, a badge, the tooltip and a menu row's hover.

- [ ] **Step 1: Rewrite the contrast tests for E4's grounds (failing)**

In `admin_contrast_test.rb`:
- `GROUNDS` becomes `%w[--cs-paper --cs-surface --cs-sunken --cs-chrome --cs-rail --cs-popover --cs-field-fill]`.
- `FIELD_GROUNDS` becomes `%w[--cs-paper --cs-surface --cs-field-fill --cs-rail --cs-popover]`. `--cs-sunken` leaves it: the field line on light sunken measures 2.97:1, and in E4 no control edge stands on sunken (sunken is hover, badges and disabled). The comment says so.
- The state-mark test's grounds become `%w[--cs-surface --cs-chrome --cs-rail]`.

Rewrite "a line that only groups is stronger than it was and still no outline" as `test "a line that only groups stays a hairline: the strong one above the plain one, both under 3:1"`. On surface it asserts `line >= 1.2`, `strong >= 1.55`, `strong > line` and `strong < 3.0`. The measured values are 1.23 / 1.27 for the line and 1.60 / 1.66 for the strong line.

Rewrite "the grounds step apart" as `test "the grounds step apart: sunken from surface, and in dark each elevation over the one below"`. It asserts sunken against surface at 1.10 or more in both schemes (measured 1.21 / 1.12). In dark it asserts surface over paper, rail over surface and popover over rail, each at 1.10 or more (measured 1.11, 1.13 and 1.12).

New tests, each asserting through `assert_ratio`:

```ruby
test "the primary's, the secondary's and the danger confirm's words are 4.5:1 or better on their fills, at rest and hovered" do
  # --cs-on-accent on --cs-accent and on --cs-accent-hover; --cs-accent on --cs-accent-tint;
  # --cs-on-danger on --cs-danger, both schemes
end
test "the accent focus ring is 3:1 or better on every ground, the rail and the popover included" do
  # --cs-accent against each of GROUNDS, both schemes
end
test "Live, a scheduled date, a panel head's words, a section head's words and the type chip's words are 4.5:1 or better" do
  # on-live/live, on-scheduled/scheduled, head-*-ink/head-*, structure-ink/structure-tint,
  # type-chip-ink/type-chip; and --cs-live 3:1 against --cs-surface (the chip's shape)
end
```

In `design_tokens_test.rb`, extend "the chrome and content-type tokens exist in both themes and map to utilities". Every new colour token, and `--cs-shadow-1…4`, must be in both blocks. Every one must have its `--color-*` (or `--shadow-*`) mapping. Every radius must have its `--radius-*` mapping.

- [ ] **Step 2: Run the two files, verify they fail**

Run: `PGGSSENCMODE=disable bin/rails test test/lib/admin_contrast_test.rb test/integration/design_tokens_test.rb`
Expected: FAIL. The cause is the missing tokens (`--cs-rail` and the rest) and the floors.

- [ ] **Step 3: Write the values and mappings from the tables above**

The `@theme inline` block gains one line per new token, written like the existing ones: `--color-field-fill: var(--cs-field-fill);`, …, `--shadow-1: var(--cs-shadow-1);` … `--shadow-4`, `--shadow-menu: var(--cs-shadow-3);` and `--radius-field: var(--cs-radius-field);` and the rest. The file's comments say what each level is used for, from the spec's "Where each level is used".

- [ ] **Step 4: Run them again, and the unit suite**

Run: `PGGSSENCMODE=disable bin/rails test test/lib test/integration/design_tokens_test.rb`, then `PGGSSENCMODE=disable bin/rails test`.
Expected: PASS. A screen test that asserts a measured colour is not expected, and none is known.

- [ ] **Step 5: Commit** `feat: E4's token values, the new tokens and their measured pairs`

---

### Task 2: The form-send pages stay neutral

**Files:**
- Modify: `app/views/layouts/form_send.html.erb` (`<html>`)
- Modify: `app/assets/tailwind/content-spiel.css` (a block after the dark one)
- Test: `test/lib/admin_contrast_test.rb` ("a form's plain pages are readable…"), `test/integration/form_sends_test.rb`

**Interfaces:**
- Produces the mark `data-surface="plain"` on `<html>`. Only `layouts/form_send.html.erb` writes it.

The mark re-values the accent family under it, in both schemes, with `var()` only: `--cs-accent: var(--cs-ink)`, `--cs-accent-hover: var(--cs-ink)`, `--cs-accent-tint: var(--cs-sunken)`, `--cs-on-accent: var(--cs-paper)`. The selector is `[data-surface="plain"]`, after both theme blocks, so it wins in both. Measured: paper on ink 15.97 / 14.37:1, and ink on sunken 14.47 / 11.53:1.

- [ ] **Step 1: Write the failing tests**

`admin_contrast_test.rb` reads the plain block (`css[/\[data-surface="plain"\]\s*\{(.*?)\}/m, 1]`) and merges it over each scheme. Then "a form's plain pages are readable…" also asserts the following, in both schemes:
- `--cs-accent` resolves to the scheme's `--cs-ink`, and `--cs-accent-tint` to its `--cs-sunken`;
- `--cs-accent` is 4.5:1 or better on paper and surface;
- `--cs-on-accent` is 4.5:1 or better on the re-valued `--cs-accent`.

A new test, `test "the plain surface re-values every accent token and nothing else"`, asserts that the block's keys are exactly `%w[--cs-accent --cs-accent-hover --cs-accent-tint --cs-on-accent]`.

`form_sends_test.rb`'s "invalid answers redraw the form…" gains `assert_select "html[data-surface=plain]"`. Another test asserts that the admin layout's `<html>` carries no `data-surface`.

- [ ] **Step 2: Run, verify it fails** — `PGGSSENCMODE=disable bin/rails test test/lib/admin_contrast_test.rb test/integration/form_sends_test.rb`. Expected: FAIL, because the block and the mark are missing.

- [ ] **Step 3: Add the block and the mark.** Above the block, a comment says why: a visitor's page carries no CMS colour, and there is no second stylesheet.

- [ ] **Step 4: Run, verify it passes.**

- [ ] **Step 5: Commit** `feat: the form-send pages keep a neutral accent under E4`

---

### Task 3: One type voice, the labels

**Files:**
- Modify: `app/assets/tailwind/content-spiel.css` (`--cs-t-label: 12px`)
- Modify: `app/helpers/setup_helper.rb` (`setup_label_class`)
- Modify: every line that writes the mono label: `font-cs-mono text-label uppercase tracking-mono` and its variants (`tracking-wide`, `uppercase` without tracking on a label). That is 83 lines in 67 files under `app/views`, `app/components` and `app/javascript` today (the spec counted 78 in 64 before the forms PR). The list comes from `grep -rn -E "uppercase[^\"'\`]*tracking-|tracking-[a-z]+[^\"'\`]*uppercase" app`, plus the `uppercase` labels without tracking: `translation_chip_component.rb`, `notes_screen/drawer_component.html.erb:28`, `translation_screen/summary_card_component.html.erb:8`, and `forms_screen/field_row_component.html.erb:4`'s `class: "uppercase"`.
- Modify: `app/components/admin/ui/badge_component.rb` (`CLASS`)
- Modify: `app/assets/tailwind/content-spiel.tailwind.css`: `.form-send-page .form-field__required` loses its mono, tracking and `text-transform`.
- Modify: the locale keys whose words were written in capitals for a label (`config/locales/admin/*.en.yml`, `config/locales/*.en.yml`)
- Test: `test/lib/admin_design_rules_test.rb`, `test/components/admin/ui/badge_component_test.rb`, `test/components/admin/ui/translation_chip_component_test.rb`, and the component tests that assert the old classes (listed in Step 6)

**Interfaces:**
- Produces the label as `text-label` (12px, weight 500 from `--text-label--font-weight`) with its colour beside it, `text-meta` unless it sits on a tint. `setup_label_class` returns `"block text-label text-meta"`. No `cs-label` class exists or is created: the spec names one, but the code never had it (see the report). `text-label` is the one label utility.
- The save status line (`SaveStatusComponent`) is not a label. It keeps `font-cs-mono text-label tracking-mono` and its literal capitals.

A language code in a translation chip or a language tab is the code's own spelling, so it stays in capitals (`uppercase`, no tracking). Task 4 moves it from mono to sans.

- [ ] **Step 1: Write the failing guard**

```ruby
UPPER_TRACKED = /(?<![\w-])uppercase(?![\w-])[^"'`]*(?<![\w-])tracking-[\w-]+|(?<![\w-])tracking-[\w-]+[^"'`]*(?<![\w-])uppercase(?![\w-])/
UPPER_TRACKED_ALLOWED = {
  "admin-wordmark" => "the brand's wordmark, drawn as the Brand page draws it",
  "CONTENT·SPIEL" => "the product layout's wordmark",
  "Content·Spiel</span>" => "the setup layout's wordmark"
}.freeze

test "one type voice: no capitals with tracking in CS Studio's sources but the wordmark" do
  # over CONTROL_SOURCES (ADMIN_SOURCES + setup_helper.rb), skipping lines with an allowed marker
end
test "the type-voice pattern matches tracked capitals in either order, and nothing else" do
  # match: "uppercase tracking-mono", "tracking-wide font-bold uppercase", "font-cs-mono text-label uppercase tracking-mono"
  # no match: "uppercase", "tracking-tight", "text-transform: uppercase; /* note */", "uppercase\" class=\"tracking-mono" (two strings)
end
test "every allowed tracked-capitals marker is still there" do ... end
test "the stylesheets set no label in capitals but the save status line" do
  # content-spiel.tailwind.css and admin-rich-text.css, comments stripped: no `text-transform: uppercase`
end
```

Add to `ADMIN_SOURCES`: `javascript/**`, which already covers `controllers`, `media`, `saving`, `search`, `rich_text`, `mind_graph` and `notes`. Add `javascript/live` and `javascript/editing` to `SOURCE_DIRECTORIES`, so that markup built in a script is read too. "every directory the rules cover is there and has sources" holds them.

- [ ] **Step 2: Run, verify it fails.** The offence list should be the 83 lines.

- [ ] **Step 3: Set `--cs-t-label: 12px`, rewrite `setup_label_class` and `BadgeComponent::CLASS` (`"inline-flex shrink-0 items-center rounded-cs px-1.5 py-0.5 text-label"`), then rewrite each offending line to `text-label` with the colour it had.** Read each line. A column head, a summary, a badge and a count are all labels. A wordmark is not.

- [ ] **Step 4: Rewrite each label's key in sentence case.** Look at the key behind every rewritten label. A key whose English holds capitals only because the CSS drew them that way is rewritten: "DEFAULT" becomes "Default", "NO ALT" becomes "No alt". A key already in sentence case stays. Proper nouns and codes keep their capitals.

- [ ] **Step 5: Run the guard and the unit suite.** Run `PGGSSENCMODE=disable bin/rails test test/lib`, then `PGGSSENCMODE=disable bin/rails test`. Expected: PASS once Step 6 is done.

- [ ] **Step 6: Update the tests that read the old classes or capitals.** The component tests that assert `uppercase`, `tracking-mono` or `font-cs-mono` on a label:
  - `ui/badge_component_test`, `ui/translation_chip_component_test`, `ui/language_tabs_component_test`, `ui/channel_chip_component_test`;
  - `shell/sidebar_component_test`, `audit_screen/row_component_test`, `trash_screen/retention_tag_component_test`, `tokens_screen/table_component_test`, `posts_screen/table_component_test`, `translation_screen/state_cell_component_test`, `editor_screen/header_component_test`, `editor_screen/shared_fields_component_test`, `columns/rich_text_column_component_test`, `fields/select_field_test`, `fields/date_field_test`;
  - `test/integration/admin/{posts_list,audit_log_screen,settings_mail,notes_drawer}_test.rb`, `test/integration/setup_mail_step_test.rb`.

  The browser tests whose capital words change, which CI runs:
  - `users_test` ("OWNER");
  - `media_library_test` ("NO ALT", "DEUTSCH");
  - `media_picker_test` ("UNUSED");
  - `notes_markers_test` and `notes_view_only_test` ("NEW NOTE ON RICH TEXT", "RICH TEXT");
  - `sections_test:2011` ("SECTION");
  - `ai_settings_test` ("CONNECTED · n MS", if its key turns out to be a label and not a status).

  Each now reads the rendered words. Save-status capitals ("CHANGED ELSEWHERE", "SAVED · NOT PUBLISHED") do not change.

- [ ] **Step 7: Commit** `feat: one type voice: labels are the 12px sans in sentence case` (body: `Advances #117` for the comments rewritten)

---

### Task 4: One type voice, mono only where it is code or a value

**Files:**
- Modify: the 169 `font-cs-mono` uses in 122 files under `app/views`, `app/components`, `app/javascript` and `app/helpers`, minus those the allow-list keeps
- Modify: `app/assets/tailwind/content-spiel.tailwind.css` (`--text-small: var(--cs-t-small);`)
- Test: `test/lib/admin_design_rules_test.rb`, and the component tests that assert `font-cs-mono` (from Task 3's list: `editor_screen/changes_overview_component_test`, `editor_screen/tile_summary_component_test`, `audit_screen/row_component_test`, `notes_screen/header_button_component_test`, `presence_screen/{people,row_marker}_component_test`, `ui/avatar_component_test`, `dashboard_screen/activity_row_component_test`, `settings_screen/ai_test_result_component_test`)

**Interfaces:**
- Produces `text-small` (13px) for an address (`/de/about`): sans, 13px, in the colour it had.
- `MONO_ALLOWED` (path => reason). The implementer writes it while reading each use. It holds what the spec keeps: code; the Code block's fields (`fields/code_field.*`, `tile_summary_component.rb`'s `mono` look); a token's or key's value (the setup token and MCP token views, `tokens_screen/create_step_component`, `audit_screen/row_component` (`event.action`), `audit_screen/changes_component` (a field's key), `groups_screen/permission_row_component` and `toggle_list_component` (`permission.key`), `audit_screen/event_header_component`'s values); and `save_status_component.rb`.
- A line that holds `<code`, `<pre`, `tag.code` or `tag.pre` passes without an entry.
- Counts, times, addresses, ⌘K, the "!" of a field error, language codes, avatars' initials, badges and the sidebar's numbers all become sans.

- [ ] **Step 1: Write the failing guard**

```ruby
MONO_CODE = /<code|<pre|tag\.code|tag\.pre/
test "mono is for code, a token's or key's value and the save status line only" do
  # every line with font-cs-mono in CONTROL_SOURCES is MONO_CODE or in a MONO_ALLOWED path
end
test "every mono allowance names a file that still writes mono" do ... end
test "the stylesheets draw mono only for code, an embed and the save line" do
  # content-spiel.tailwind.css and admin-rich-text.css, comments stripped: each `var(--cs-mono)` is in a rule whose
  # selector is .admin-rich-text-content pre, .admin-rich-text-content code or .admin-rich-text-embed
  # (the form-send error's "!" loses its mono in this task)
end
```

- [ ] **Step 2: Run, verify it fails.** The offence list is every non-code `font-cs-mono`.

- [ ] **Step 3: Rewrite each use to sans (addresses `text-small`), keeping its size and colour otherwise, and write `MONO_ALLOWED`.** Then run the guard until it passes.

- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test`, and update the component tests named above.

- [ ] **Step 5: Commit** `feat: one type voice: mono only for code and values`

---

### Task 5: Buttons, and no palette colour

**Files:**
- Modify: `app/components/admin/ui/button_component.rb`
- Modify: `app/helpers/setup_helper.rb` (`setup_primary_button_class`, `setup_secondary_link_class`, `setup_ghost_link_class` becomes `setup_tertiary_link_class`)
- Modify: every `variant: :ghost` (22 files, 33 uses with the tests) and every `setup_ghost_link_class` caller
- Modify: `app/javascript/rich_text/popover.js` (`primary:` and its siblings, the popover's own button classes)
- Modify: `app/views/admin/posts/index.html.erb:26` (New post's split button half)
- Test: `test/components/admin/ui/button_component_test.rb`, `test/components/previews/admin/ui/button_component_preview.rb`, `test/lib/admin_design_rules_test.rb`

**Interfaces:**
- `Admin::Ui::ButtonComponent.new(label:, variant: :primary, type: "button", size: :regular, **html)`. Its variants are `:primary`, `:secondary`, `:tertiary`, `:danger` and `:danger_text`.
- `:ghost` is **renamed** `:tertiary` and now raises `ArgumentError`. This is the spec's "ghost becomes tertiary", builder's call. A dialog's Cancel and "Discard changes…" become accent words **(owner)**.
- `VARIANT_CLASSES` values:
  - **primary**: `bg-accent text-on-accent shadow-2 not-disabled:hover:bg-accent-hover not-disabled:hover:shadow-3 not-disabled:active:translate-y-px not-disabled:active:shadow-none`.
  - **secondary**: `bg-accent-tint text-accent not-disabled:hover:shadow-1`. The hover is not drawn, so a lift is this plan's choice **(owner)**.
  - **tertiary**: `bg-transparent text-accent not-disabled:hover:underline`.
  - **danger**: `bg-danger text-on-danger not-disabled:hover:opacity-90`.
  - **danger_text**: `bg-sunken text-danger-ink not-disabled:hover:shadow-1`. Red words on the violet tint would fight. Measured on sunken: 7.53 / 7.33:1.
- `COMMON_CLASS`: `rounded-button` (small: `rounded-button-sm`), `border border-transparent` at rest on every variant (so that no state changes the size), `focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent`, `font-semibold`. The one disabled look is `disabled:not-aria-busy:bg-sunken disabled:not-aria-busy:text-meta disabled:not-aria-busy:shadow-none`, with no hairline and no opacity. The busy exception is kept.
- `setup_*` class strings are the same strings: `setup_primary_button_class` returns the primary's common and variant classes plus `inline-flex`. One constant is shared: `ButtonComponent.classes(variant, size: :regular)`, a class method returning the joined string that `setup_helper.rb` and `html_attrs` both call.

- [ ] **Step 1: Write the failing tests**

`button_component_test.rb`:

```ruby
test "the primary is a solid accent fill raised to shadow 2, and hovered it darkens and rises to shadow 3" do
  # assert classes include bg-accent text-on-accent shadow-2 not-disabled:hover:bg-accent-hover not-disabled:hover:shadow-3
end
test "the secondary is a tinted fill with accent words and no outline" do
  # bg-accent-tint text-accent; refute border-field-line
end
test "the tertiary is accent words with no fill, and ghost is no longer a variant" do
  # text-accent; assert_raises(ArgumentError) { ButtonComponent.new(label: "x", variant: :ghost) }
end
test "the danger confirm's words are --cs-on-danger, never a white literal" do ... end
test "every variant has the accent focus ring 2px out and the button radius" do ... end
test "classes(variant) is what the component draws, so the wizard's buttons are the same" do ... end
```

`admin_design_rules_test.rb`:

```ruby
PALETTE = /(?<![\w-])(?:bg|text|border|ring|outline|fill|stroke|from|via|to|divide|decoration|accent|caret|shadow|placeholder)-(?:slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-(?:50|[1-9]00|950)(?![\w-])|(?<![\w-])(?:bg|text|border|ring|outline|fill|stroke)-(?:white|black)(?![\w-])/
test "no Tailwind palette colour or white/black utility in CS Studio" do ... end
test "the palette pattern matches a palette step and white, and no token" do
  # match: "bg-violet-600", "text-gray-500", "border-rose-950", "text-white", "hover:bg-black"
  # no match: "bg-accent", "text-ink", "bg-white-ish", "text-on-accent", "bg-cat-1"
end

ACCENT_FILL = /(?<![\w-])bg-accent(?![\w-])/
ACCENT_FILL_ALLOWED = {
  "app/components/admin/ui/button_component.rb" => "the buttons",
  "app/helpers/setup_helper.rb" => "the wizard's buttons, built from ButtonComponent.classes",
  "app/components/admin/shell/sidebar_component.rb" => "the Dashboard's count pill",
  "app/components/admin/notes_screen/header_button_component.html.erb" => "the unread count pill",
  "app/components/admin/notes_screen/thread_row_component.html.erb" => "the unread bubble",
  "app/components/admin/notes_screen/inbox_row_component.html.erb" => "the unread bubble",
  "app/javascript/controllers/admin/notes/inbox_controller.js" => "the unread bubble",
  "app/javascript/mind_graph/card_notes.js" => "the unread bubble",
  "app/javascript/notes/merge.js" => "the NEW divider",
  "app/components/admin/translation_screen/translate_all_component.html.erb" => "a progress bar",
  "app/javascript/media/upload_tiles.js" => "a progress bar",
  "app/javascript/rich_text/popover.js" => "a script-built button that cannot render the component",
  "app/views/admin/posts/index.html.erb" => "the primary's own split half, New post's type chooser"
}.freeze
test "only a button, the checkbox, a count pill, the unread bubble and a progress bar carry the accent fill" do ... end
test "every accent-fill allowance is still used" do ... end
```

The tint-and-accent pair (`bg-accent-tint` with `text-accent` on one line) gets the same rule, with its own allow-list. Today's users are `ui/channel_chip_component.rb` (the MCP chip, not pressable) and `notes_screen/body_component.rb` (your own mention).

- [ ] **Step 2: Run, verify it fails.** The expected failures are the variant classes, `text-white`, the `:ghost` callers and the hand-made accent fills not listed.

- [ ] **Step 3: Implement `ButtonComponent.classes(variant, size:)` and the variants, rename `:ghost` to `:tertiary` at each caller, and rebuild the three setup helpers on `classes`.** The posts index split half keeps its `bg-accent` and takes `rounded-r-none`/`rounded-l-none` with `rounded-button`.

- [ ] **Step 4: Run the unit suite.** Update the component tests that assert `variant: :ghost` or `border-field-line` on a button. Run `PGGSSENCMODE=disable bin/rails test`.

- [ ] **Step 5: Commit** `feat: E4's buttons: a raised primary, a tinted secondary, accent-word tertiary; no palette colour`

---

### Task 6: Fields as wells

**Files:**
- Modify: `app/assets/tailwind/content-spiel.tailwind.css`: the `:is(.admin-column, .admin-field, …) :is(input…, textarea, select, .admin-rich-text-editor, [role="toolbar"])` rule; `.cs-select`; `.admin-prefix-input`; `.admin-held …` and `.admin-view-only …` (which keep their own grounds); `.cs-toggle`; `.cs-checkbox`
- Modify: `app/assets/tailwind/admin-rich-text.css` (the box)
- Modify: `app/helpers/setup_helper.rb` (`setup_input_class`, 73 callers, unchanged)
- Modify: `app/components/admin/ui/prefix_input_component.*`, `chip_input_component.html.erb`, `password_field_component.html.erb`, `app/components/admin/columns/rich_text_column_component.html.erb`
- Test: `test/lib/admin_design_rules_test.rb`, `test/system/admin/field_error_border_test.rb`

**Interfaces:**
- A text field (input, textarea, select, the rich-text box, the prefix input's wrapper, the chip input's field) has `background: var(--cs-field-fill)`, `border-width: 0 0 1px` in `var(--cs-field-invalid-border, var(--cs-field-line))`, and `border-radius: var(--cs-radius-field) var(--cs-radius-field) 0 0`.
- Focused, it has `outline: 2px solid var(--cs-accent); outline-offset: 0`, a transparent bottom edge and `--cs-surface` behind it, as drawn. It is invalid when the bottom edge is danger.
- A checkbox, a toggle and a segmented control keep a full 1px `--cs-field-line` outline.
- `setup_input_class` returns `"mt-1 block w-full rounded-t-field border-0 border-b border-field-line bg-field-fill px-3 py-2 text-ink focus:outline-2 focus:outline-accent"`. Auth and wizard pages are outside `.admin-column`, so they read the same look from the helper.
- The rule is unlayered, so it beats the utilities written beside a control, as `.cs-select` does today. That is how one rule reshapes every schema field with no change to `Admin::Fields::*`.

- [ ] **Step 1: Reword the field guard (failing)**

Rename "a pressable or typed-into element is outlined in border-field-line, never border-line-strong" to "a control is identified by a field-line edge or a fill of its own, never border-line-strong". Its logic is unchanged. Rewrite "the stylesheet's controls draw their outline in --cs-field-line…" as `test "a text field is a well: the field fill and a field-line bottom edge, the accent outline on focus; a checkbox and a toggle keep a full outline"`. It asserts:
- the shared rule sets `background: var(--cs-field-fill)`, `border-width: 0 0 1px` and `var(--cs-field-invalid-border, var(--cs-field-line))`;
- `.cs-select` has `border-width: 0 0 1px` with `--cs-field-line`, and `background-color: var(--cs-field-fill)`;
- `.cs-toggle` keeps `border: 1px solid var(--cs-field-line);`;
- the focus rule has `outline: 2px solid var(--cs-accent)`;
- there is no `font-size: 10px`.

A second test asserts that `setup_input_class` holds `bg-field-fill` and `border-b`.

- [ ] **Step 2: Run, verify it fails.**

- [ ] **Step 3: Write the rules.** `.admin-held` and `.admin-view-only` keep the read-only grounds they have, re-checked, with a full `--cs-line` border and no fill change: a held form stays read-only at full contrast.

- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test`. **Then locally, on a quiet machine**, run `bin/rails tailwindcss:build`, then `PGGSSENCMODE=disable bin/rails test test/system/admin/field_error_border_test.rb test/system/admin/filter_bar_test.rb`. `field_error_border_test` reads the border colour: it now reads the bottom edge, so assert `border-bottom-color`. In `filter_bar_test` the 38px heights must hold on the wells and the segment frame.

- [ ] **Step 5: Commit** `feat: E4's fields: a filled well with a bottom edge and the accent outline on focus`

---

### Task 7: Icon chips and block-type families

**Files:**
- Modify: `app/assets/tailwind/content-spiel.css` (the 14 icon tokens), `content-spiel.tailwind.css` (their mappings)
- Create: `app/components/admin/ui/icon_chip_component.rb`
- Create: `test/components/admin/ui/icon_chip_component_test.rb`, `test/components/previews/admin/ui/icon_chip_component_preview.rb`
- Modify: `app/models/content_model/block_type_definition.rb` (`icon`, `family`, `ICON_FAMILIES`)
- Modify: `app/models/block_types/{rich_text,note,image,card,code,table,form,post_list,section}.rb`
- Modify: `app/components/admin/editor_screen/block_icon_component.rb`
- Modify: `lib/generators/block_type/templates/definition.rb.tt` (the commented `t.icon` line names `family:`)
- Test: `test/models/content_model/block_type_definition_test.rb`, `test/components/admin/editor_screen/block_icon_component_test.rb`, `test/lib/admin_contrast_test.rb`, `test/lib/admin_design_rules_test.rb`, `test/lib/admin_i18n_test.rb` (`CONVERTED` gains the new file)

**Interfaces:**
- The icon tokens (**add**). Each pair is the icon and its chip, light then dark:
  - `--cs-ic-text` `#2a4fc6` / `--cs-ic-text-bg` `#e7ecfb`; dark `#9db4ff` / `#24304f`
  - `--cs-ic-media` `#a14a06` / `--cs-ic-media-bg` `#fbeedd`; dark `#f0b06a` / `#3a2a17`
  - `--cs-ic-code` `#0b6a73` / `--cs-ic-code-bg` `#dcf0f1`; dark `#6fd0d6` / `#14353a`
  - `--cs-ic-form` `#1b7339` / `--cs-ic-form-bg` `#e0f2e5`; dark `#7fd39a` / `#183622`
  - `--cs-ic-lists` `#6a35c9` / `--cs-ic-lists-bg` `#efe8fb`; dark `#c4a8ff` / `#30264a`
  - `--cs-ic-structure` `#7a4a12` / `--cs-ic-structure-bg` `#f4e6d4`; dark `#e8b77e` / `#40301c`
  - `--cs-ic-people` `#8c1d5c` / `--cs-ic-people-bg` `#fbe6ef`; dark `#ffb8d6` / `#3d2030`

  Their utilities are `text-ic-<family>` and `bg-ic-<family>-bg`, mapped as `--color-ic-text: var(--cs-ic-text);` and the rest. Measured on the E4 grounds: every icon is 5.06:1 or better on its chip, the surface, the rail, the chrome and the popover, in both schemes.
- `ContentModel::BlockTypeDefinition::ICON_FAMILIES = %i[text media code form lists structure].freeze`. People has no block type and is not a block family.
- `icon(name = nil, for_block: nil, family: nil)`. `family:` must be one of `ICON_FAMILIES`, refused otherwise through `refuse` like the icon's name. `#family` returns the declared family or `:neutral`. A type from outside may declare one. A type that declares none, a gem's included, is `:neutral`.
- The built-ins' families, from the spec: rich_text and note `:text`; image and card `:media`; code and table `:code`; form `:form`; post_list `:lists`; section `:structure`.
- `Admin::Ui::IconChipComponent.new(icon:, family:, size: :md)`:
  - `family` is one of `ICON_FAMILIES + %i[people accent neutral]`;
  - `size` is `:md` (24px chip, 14px icon) or `:lg` (22px chip, as in a tile's and a section's head, 14px icon);
  - the chip has a 7px radius (`rounded-chip`) and draws `admin/shared/icon`;
  - `:accent` is `bg-accent-tint text-accent`; `:neutral` is `bg-sunken text-dim`;
  - it is decoration (`aria-hidden`), because a chip always stands beside its type's or module's name;
  - it has no words of its own.
- `BlockIconComponent` keeps its `PLACES`, `dom_id`, `render?` and `data-block-icon`. Its `call` renders through `IconChipComponent` with the definition's family: `:picker` and `:card` are `:md`, `:tile` is `:lg`. The id still sits on the outer span the block-icon stream replaces.

- [ ] **Step 1: Write the failing tests**

- `block_type_definition_test`: "a block type declares its icon's family, one of seven, and one that names none is neutral". It covers the refusal of `family: :people` and `family: :purple`, and `#family` on a bare definition.
- A built-ins test: "every built-in block type declares the family the design gives it". It holds a hash of type to family, the nine above.
- `icon_chip_component_test`:
  - "each family draws its icon on its chip, 24px with a 7px radius";
  - "accent and neutral are the tint pair and the sunken pair";
  - "an unknown family or size raises";
  - "the chip is hidden from a screen reader".
- `block_icon_component_test`: "a block type's icon is drawn on its family's chip, and a type with no family on the neutral chip". Its existing tests keep passing: the id, `data-block-icon`, and the note's icon that follows its block.
- `admin_contrast_test`: `test "each family's icon is 3:1 or better on its chip and on surface, rail, chrome and popover, in both schemes"`.
- `admin_design_rules_test`:

```ruby
test "an icon's hue is drawn only by the icon chip" do
  # /(?<![\w-])(?:text|bg|fill|stroke)-ic-|--cs-ic-/ appears in ADMIN_SOURCES only in ui/icon_chip_component.rb
end
test "a block type's icon is drawn only through BlockIconComponent" do
  # `definition.icon` / `.icon_for(` read in app/components and app/views only by block_icon_component.rb
end
test "the people hue is drawn only by the icon chip and the people's own components, never by a button" do
  # ic-people in: ui/icon_chip_component.rb (and, as the spec allows, ui/avatar_component.rb,
  # notes_screen/marker_component*, notes_screen/row_pill_component*, presence_screen/row_marker_component*,
  # editor_screen/hold_strip_component*: none uses it yet); never in ui/button_component.rb
end
test "the icon guards' patterns match a hue utility and the token, and not a word" do ... end
```

- [ ] **Step 2: Run, verify they fail.**

- [ ] **Step 3: Implement the tokens, `family:`, the component and `BlockIconComponent`'s drawing through it. Declare the nine families. Add the new file to `CONVERTED`.**

- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test`. `test/components/previews_test.rb` renders the new preview, which shows every family in both sizes.

- [ ] **Step 5: Commit** `feat: icon chips: a hue per block-type family, declared beside the icon`

---

### Task 8: The sidebar's modules as a registry, drawn with chips (#127)

**Files:**
- Create: `app/models/studio_modules.rb`, `config/initializers/studio_modules.rb`
- Create: `test/models/studio_modules_test.rb`
- Modify: `app/controllers/admin/base_controller.rb` (remove `MODULES` and `MODULE_GROUPS`; `admin_modules` reads the registry)
- Modify: `app/components/admin/shell/sidebar_component.{rb,html.erb}`, `top_bar_component.html.erb` and `account_identity_component.rb` (the same row and label look), `app/views/layouts/admin.html.erb:98-109`, `app/helpers/admin/jump_helper.rb`
- Modify: `config/locales/admin/shell.en.yml` (`admin.modules.<name>`, `admin.module_groups.<group>`, and the sidebar's words: "Jump to…", "Sign out", the groups' headings)
- Modify: `test/components/admin/shell/sidebar_component_test.rb`, `test/components/previews/admin/shell_preview.rb`, `test/queries/jump/search_test.rb`, `test/integration/admin/access_control_test.rb`, `test/lib/admin_i18n_test.rb` (sidebar files into `CONVERTED`)

**Interfaces:**
- `StudioModules` is a top-level registry in `app/models` beside the other registries. It is not under `Admin`, and it holds no component.
  - `StudioModules::Entry = Data.define(:name, :icon, :family, :path, :permission, :group, :visible, :badge)`.
  - `name` is a Symbol (`:dashboard`, `:pages`, …); `family` is one of `IconChipComponent`'s families; `path` is a route helper name; `visible` is a callable or nil (today's `if:`); `badge` is `->(viewer:) { Integer }` or nil.
- `StudioModules.register(name, icon:, family: :neutral, path:, permission:, group:, visible: nil)` raises on a second name. `StudioModules.badge(name, &counter)` sets the badge of a registered module and raises for an unknown one. Notes and trash register their badges this way.
- `StudioModules.entries` returns the registration order. `StudioModules.groups` returns `%i[content people system]`. `StudioModules.reset!` exists for `to_prepare`, and `StudioModules.with(entries) { }` exists for tests, as `Admin::Slots` has both.
- `config/initializers/studio_modules.rb` (`to_prepare`) registers today's 15 modules in today's order, with today's icons, paths, permissions, groups and the Translations `visible:`. Families: posts `:lists`, media `:media`, forms `:form`, the rest `:neutral`. Badges: `:dashboard` is the viewer's unread notes (`Dashboard::NotesForYou.new(actor:).unread_count`, today's `notes_badge_count`), and `:trash` is today's trash count.
- `Admin::BaseController#admin_modules` returns the visible entries as hashes of today's shape plus `family:`. The shape is `{ label:, icon:, family:, path:, permission:, group: }`, with `label` being `t("admin.modules.#{name}")`. So `Jump::Search` and its helper stay unchanged in shape.
- `SidebarComponent.new(modules:, user:, current_path:, url_options:, badges:)` keeps its signature. The layout builds `badges` from `StudioModules`' badge callables, not by hand.
- The sidebar draws each entry's icon with `IconChipComponent.new(icon:, family:)`. The current module's chip is `family: :accent`, on `bg-accent-tint` words in `text-accent` **(owner: the drawing shows the accent tint; the current row's ground today is sunken)**.
- No Notes module exists in the sidebar today, so the people hue gets no sidebar entry in this stage. Stage 6's Notes item registers with `family: :people`.

- [ ] **Step 1: Write the failing tests**

`studio_modules_test.rb`:
- "the registry holds today's modules in order, each with a label key that exists in English";
- "a second module of one name is refused, and a badge for an unknown module is refused";
- "a module's badge is counted for the viewer it is asked for";
- "with puts the registry back".

`sidebar_component_test`:
- "each module's icon is on its family's chip: Posts lists, Media media, Forms form, the rest neutral";
- "the current module's chip is the accent tint";
- "the labels and headings are read from keys". This asserts the rendered words, with no literal left in the file.

`access_control_test` and `jump/search_test` change only where they read `Admin::BaseController::MODULES`: they read `StudioModules.entries`.

- [ ] **Step 2: Run, verify it fails** (`StudioModules` is undefined).

- [ ] **Step 3: Implement the registry, the initializer, `admin_modules`, the layout's badges and the sidebar's chips. Move the sidebar's literals to keys.** Restyle the sidebar's rows: `rounded-button` and the hover `bg-sunken`, the label as Task 3's, and counts in sans.

- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test`, including `bin/rails zeitwerk:check`.

- [ ] **Step 5: Commit** `feat: the sidebar's modules are a registry, each icon on its family's chip` (body: `Advances #127`)

---

### Task 9: Elevation and radii: cards, dialogs, menus, toasts, tooltips, ⌘K, drag

**Files:**
- Modify: `app/components/admin/ui/{dialog_component.html.erb,menu_component.rb,toast_component.html.erb,tooltip_component.rb,chip_input_component.html.erb}`, `app/components/admin/shell/command_palette_component.html.erb`, `app/views/admin/jump/show.html.erb`, `app/components/admin/fields/link_field.html.erb:22` (`shadow-sm`)
- Modify: `app/assets/tailwind/content-spiel.tailwind.css`: `.admin-dialog`, `.admin-drag-chosen`, `.admin-drag-fallback`, `.admin-drag-ghost`, `.admin-shell__tree`, `.admin-save-bar[data-stuck]`. Remove `--shadow-menu`.
- Modify: the 26 `shadow-menu` uses; and the card pattern (`border border-line … bg-surface` on a card's element: 62 lines in 58 files) to `rounded-card bg-surface shadow-1` with no border
- Test: `test/lib/admin_design_rules_test.rb`, `test/components/admin/ui/{dialog,menu,toast,tooltip}_component_test.rb`, `test/integration/design_tokens_test.rb` ("the product build carries the drag pattern classes")

**Interfaces:**
- Where each level is used:
  - elevation 1 (`bg-surface shadow-1`, `rounded-card`): a card, the tree column (`.admin-shell__tree` gets `box-shadow: var(--cs-shadow-1)` and loses its right border);
  - elevation 3 (`bg-popover shadow-3`, `rounded-card`): a dialog, a menu's list, the chip input's suggestions, the link field's list, ⌘K;
  - elevation 4 (`--cs-shadow-4`): `.admin-drag-chosen` and `.admin-drag-fallback`. The ghost keeps its dashed drop place, in `rounded-tile`.
- A toast and the tooltip keep their inverted look (`bg-ink text-paper`). The toast takes `shadow-3` and `rounded-button`. The tooltip keeps no shadow and `rounded-cs`, as the design system has it.
- A menu row's hover stays `bg-sunken` with `rounded-cs`. The menu's current row is `bg-accent-tint`, the spec's "menu's current row".
- A table is one card with grouping lines inside it (`.admin-card-table` keeps its padding).
- The notes drawer keeps no shadow until 3b. The selected tree row's `shadow-[inset_2px_0_0_var(--cs-ink)]` stays until Stage 2, through an allow-list entry.

- [ ] **Step 1: Write the failing guards**

```ruby
SHADOW = /(?<![\w-])shadow-(?:2xs|xs|sm|md|lg|xl|2xl|inner|menu|\[[^\]]*\])(?![\w-])/
SHADOW_ALLOWED = { "app/components/admin/pages_screen/tree_node_component.rb" => "the selected row's bar; stage 2 draws it in the accent" }.freeze
RADIUS = /(?<![\w-])rounded-(?:(?:[trblse]|tl|tr|bl|br|ss|se|es|ee)-)?(?:xs|sm|md|lg|xl|2xl|3xl|4xl|\[[^\]]*\])(?![\w-])/
test "a shadow is an elevation token" do ... end
test "a radius is a radius token" do ... end
test "the elevation and radius patterns match Tailwind's own and arbitrary values, and not a token or a word" do
  # SHADOW match: "shadow-sm", "hover:shadow-lg", "shadow-[0_1px_0_red]", "shadow-menu"; no match: "shadow-1", "shadow-4", "no shadow, no arrow"
  # RADIUS match: "rounded-md", "rounded-t-lg", "rounded-[3px]"; no match: "rounded-cs", "rounded-full", "rounded-t-field", "rounded-r-none", "rounded down"
end
test "every shadow allowance is still there" do ... end
```

Dialog, menu and toast tests assert `shadow-3` and the elevation-3 ground (`bg-popover`) on the panel, and no `border-line` on a dialog.

- [ ] **Step 2: Run, verify it fails.**

- [ ] **Step 3: Rewrite the 26 `shadow-menu` uses and `link_field`'s `shadow-sm`, the shared panels, the CSS rules and the cards.** Read each card line, because some bordered boxes are a control (the drop zone) or an alert, and those keep their edge.

- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test`. **Then locally, on a quiet machine:** `bin/rails tailwindcss:build`, then `PGGSSENCMODE=disable bin/rails test test/system/admin/dialogs_hang_test.rb test/system/admin/publish_dialog_steady_test.rb test/system/admin/form_width_test.rb`. A dialog's frame must not move or resize, and the form column must keep its 760px.

- [ ] **Step 5: Commit** `feat: depth from elevation: cards, dialogs, menus and the dragged tile`

---

### Task 10: The remaining shared components, status and the people hue

**Files:**
- Modify: `app/components/admin/ui/`:
  - `status_chip_component.{rb,html.erb}`, `unpublished_chip_component.html.erb`;
  - `checkbox_component.*` (`.cs-checkbox` in the stylesheet), `file_drop_component.html.erb`, `save_bar_component.*`, `empty_state_component.*`, `pagination_component.*`, `tab_links_component.*`, `language_tabs_component.*`, `theme_switch_component.html.erb`, `system_check_row_component.*`, `error_summary_component.html.erb`, `insecure_notice_component.rb`, `mail_failed_notice_component.rb`;
  - `app/components/admin/editor_screen/new_page_*` (the New page dialog: a field and a button)
- Test: each component's test in `test/components/admin/ui/`, and `test/lib/admin_design_rules_test.rb`

**Interfaces:**
- `StatusChipComponent.new(status:, at: nil, hide_live: false)`. Its signature and `data-status` are unchanged.
  - Live: `bg-live text-on-live font-semibold`, with a dot in `bg-on-live` and the word "Live".
  - Draft: `border border-field-line bg-transparent text-dim`, with a ring glyph "○" and the word "Draft".
  - Scheduled: `bg-scheduled text-on-scheduled`, with its word and its `title`.
  - All take `rounded-cs`, and Live still draws no chip in the page tree.
  - The glyphs are `aria-hidden`, and the label key is the word.
- Grounds and radii for the rest:
  - tabs and segmented groups: `rounded-button` on their frame; the selected segment stays inverted with its paper ring;
  - the save bar: `bg-paper`, with the stuck shadow;
  - empty states: in-card, `text-dim`;
  - pagination: `rounded-button`;
  - file drop: `rounded-card`, keeping its dashed field-line edge, with the accent tint while dragging;
  - checkbox: `rounded-cs` (2px) with the accent fill;
  - alerts (error summary, insecure and mail-failed notices): `rounded-card`, keeping their tint and words.

- [ ] **Step 1: Write the failing tests**

`status_chip_component_test`:
- "Live is a solid live chip with its dot and the word";
- "Draft is an outlined chip with its ring and the word";
- "Scheduled is the scheduled block with the word and the exact time as its title";
- "every state says its word; the glyph is hidden from a screen reader".

`admin_design_rules_test`:

```ruby
test "the live and scheduled fills are drawn only by the status chip and the scheduled date" do
  # /(?<![\w-])(?:bg|text|border)-(?:live|on-live|scheduled|on-scheduled)(?![\w-])/ only in ui/status_chip_component.*
  # (stage 4 adds the dashboard's scheduled date)
end
STATUS_FILL_FILES = [ ... ] # the 48 files that draw bg-ok/warn/danger(-tint) today, written out
test "the ok, warn and danger fills are in no file beyond today's: a new one goes in a status component" do
  # files matching /(?<![\w-])bg-(?:ok|warn|danger)(?:-tint)?(?![\w-])/ ⊆ STATUS_FILL_FILES
end
test "the status-fill list holds only files that still draw a status fill" do ... end
```

The second rule is a ratchet. It holds the spec's "status colours only in the status components" as far as Stage 1 can. The spec's alerts are not a shared component yet, so today's files are written out. The list may only shrink: a new file joins only by review, and each later stage that restyles a screen moves its fills into a status component and removes the entry.

- [ ] **Step 2: Run, verify it fails.** Run `PGGSSENCMODE=disable bin/rails test test/components/admin/ui test/lib/admin_design_rules_test.rb`. Expected: FAIL on the chip's classes and on the live/scheduled rule once the chip draws them.

- [ ] **Step 3: Restyle each component to the values above, and write `STATUS_FILL_FILES` from today's grep.**

- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test`. Expected: PASS.

- [ ] **Step 5: Commit** `feat: the shared chips, tabs, alerts and the New page dialog in E4; status keeps its word`

---

### Task 11: Entry helpers for a browser test, and the rules beside the tests (#133)

**Files:**
- Modify: `test/application_system_test_case.rb`
- Create: `test/system/README.md`, `test/system/admin/entry_helpers_test.rb`
- Modify: `docs/reference/writing-tests.md` (the browser-test paragraphs move out; one line and a link stay), `CLAUDE.md` (the index line)
- Modify: the browser tests this stage already edits (Tasks 3, 6, 9, 10). Where they `visit` an editor and then call `await_admin_controllers`, they use the helpers.

**Interfaces:**
- `visit_editor(record, locale: nil)` visits the page's or post's editor (`admin_page_path` / `admin_post_path` with the admin URL options), then `await_admin_controllers`, which already waits for the live part. It raises `ArgumentError` for any record that is neither a `Page` nor a `Post`.
- `visit_screen(path)` is `visit(path)` and then `await_admin_controllers`.
- Both return nothing, and neither signs in.

The finding asks for the rules to leave `CLAUDE.md`. They already left it, for `docs/reference/writing-tests.md`, so they move from there to `test/system/README.md`: what a system test must and must not do, the helpers, the waits, the sleeps, the JS errors and the two-people rule. `writing-tests.md` keeps how the suites run, the test databases, coverage and CI, plus one line: "What a browser test must and must not do: `test/system/README.md`". `CLAUDE.md`'s line "read `docs/reference/writing-tests.md`" gains "and `test/system/README.md` before a browser test".

- [ ] **Step 1: Write the failing browser test**

`entry_helpers_test.rb`:
- "visit_editor opens a page's editor with its controllers connected and its live part answered". Assert `#editing[data-live-part=answered]` right after the call, with no wait.
- "visit_editor refuses a record that has no editor".
- "visit_screen waits for the screen's controllers".

- [ ] **Step 2: Run it locally (quiet machine), verify it fails**, then implement, then run it again: `PGGSSENCMODE=disable bin/rails test test/system/admin/entry_helpers_test.rb`. The file joins a shard by itself (`system_test_shards_test`).

- [ ] **Step 3: Move the rules. Run** `PGGSSENCMODE=disable bin/rails test test/lib`: the guards that read `CLAUDE.md` and `docs/reference` must still pass.

- [ ] **Step 4: Commit** `test: entry helpers for a browser test, and its rules beside the tests` (body: `Advances #133`)

---

### Task 12: The reference, the guide pages and CLAUDE.md

**Files:**
- Modify: `docs/reference/design-system.md`. Rewrite "The design pass" paragraph's rules, "Shared components" (the button variants, badge, status chip, the icon chip, the registry) and "Rules a change can break silently". It gains:
  - E4's tokens by role, the elevations and their uses, the radii and the type voice;
  - accent on a marker versus the tree row's bar ("a selection, not a marker");
  - the plain surface;
  - every new guard by its test name;
  - the no-guard cases: one primary per area; the stylesheet's own mono and capitals beyond what Tasks 3 and 4 read; the status-fill ratchet's list.
- Modify: `docs/reference/content-blocks-and-types.md`, "Adding a block type": the icon's `family:`, and that a type naming none is neutral.
- Modify: `docs/reference/cs-studio-shell-and-dashboard.md`: the sidebar's registry (`StudioModules`).
- Modify: `CLAUDE.md`:
  - the design-system index line names `app/models/studio_modules.rb`, `config/initializers/studio_modules.rb` and `Admin::Ui::IconChipComponent`;
  - the Key Conventions bullet "Long, load-bearing code comments are the norm" gains the comment rule (#117): "A comment states a current invariant, a hazard or a reason; never the plan step, the review round or what used to be there: history lives in git and the pull request."
- Test: `PGGSSENCMODE=disable bin/rails test test/lib` (`theming_reference_test`, `source_layout_test` and the other guards that read `CLAUDE.md` and `docs/reference`)

The guide lives in `/Users/dknafelj/src/contentspiel-docs`, a separate repository. Its pages are updated there before release, and its screenshots (27 in `screenshots/`, recipes in `screenshots/recipes.rb`) are retaken after merge. The pull request's "Documentation" section names these pages:
- First, the getting-started tour: `docs/editors/getting-started/signing-in-and-finding-your-way.md` and `docs/editors/index.md`.
- Labels quoted in capitals become sentence case ("**YOUR DRAFTS**", "**TITLE**", "**RELATED POSTS**", "**DATE AND TIME**"; save-status words stay capitals) in:
  - `docs/editors/`: `pages/{build-a-page-with-blocks,create-and-organise-pages,page-settings-and-search-appearance,the-page-tree}.md`, `posts/{posts-and-content-types,publish-schedule-and-preview,tags-related-posts-and-the-mind-graph,the-life-of-a-page-or-post}.md`, `forms/collect-answers-with-a-form.md`, `media/the-media-library.md`, `trash/the-trash.md`, `translating/{keep-translations-up-to-date,write-in-more-than-one-language}.md`, `working-together/live-refresh-and-edit-reservations.md`, `when-things-go-wrong/when-an-edit-is-not-saved.md`;
  - `docs/administrators/`: `install/{the-setup-wizard,before-you-go-live}.md`, `operations/system-status.md`, `people/{api-tokens-and-the-ai-assistant,the-audit-log,users-and-owners}.md`, `site/{languages,mail,site-settings}.md`;
  - and `docs/STYLE.md`, which sets how a label is quoted.
- Every page with a "Screenshot:" line is retaken after merge: the pages above, plus `pages/{arrange-blocks-in-sections,the-rich-text-editor}.md`, `posts/work-with-many-posts.md` and `working-together/{notes-on-content,who-else-has-this-open}.md`.

- [ ] **Step 1: Rewrite the reference sections and CLAUDE.md lines named above. Run** `PGGSSENCMODE=disable bin/rails test test/lib`. Expected: PASS.
- [ ] **Step 2: Write the pull request's "Documentation" section from the list above.** It goes in the PR description, not in this repository.
- [ ] **Step 3: Commit** `docs: E4 stage 1 in the design-system reference and CLAUDE.md` (body: `Advances #117`)

---

### Task 13: The Design System artifact in E4 (last; a subagent)

**Files:** none in this repository. The artifact is https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT.

**Interfaces:**
- Consumes: the merged `content-spiel.css` and `content-spiel.tailwind.css`, and Tasks 5, 7 and 10's components. The artifact's rule is that the code is the source.

This is a design-system write through the artifact type's revise steps. It runs after the PR merges.

- [ ] **Step 1: Dispatch a subagent.** It first reads the type's `SKILL.md` (`read_file`, path `SKILL.md`), then follows its revise steps. Its brief:
  - bring `project/tokens.json` in line with the merged token blocks, every name and both schemes;
  - update the component pages that Stage 1 changed: Button, Badge, TextFields, FormControls, ChoiceFields, Dialog, Menu, Toast, Tooltip, StudioShell, FoundationContrast, FoundationIcons, FoundationFocus;
  - add the icon chip to FoundationIcons;
  - add a `project/Changelog.md` entry;
  - leave the StudioCalm* proposal pages as the record.
- [ ] **Step 2: Report the new artifact version to the owner.**

---

## Browser tests

Run locally, few at a time, on a quiet machine, after `bin/rails tailwindcss:build`, prefixed with `PGGSSENCMODE=disable`:
- `field_error_border_test` and `filter_bar_test` (Task 6);
- `dialogs_hang_test`, `publish_dialog_steady_test` and `form_width_test` (Task 9);
- `entry_helpers_test` (Task 11).

Left to CI, which runs the whole browser suite for the pull request:
- the label-word changes of Task 3: `users_test`, `media_library_test`, `media_picker_test`, `notes_markers_test`, `notes_view_only_test`, `sections_test`, `ai_settings_test`;
- the tests that read classes or computed styles: `presence_lists_test`, `presence_test`, `editor_header_test`, `dashboard_test`, `translations_test`, `audit_log_test`, `notes_alert_test`, `notes_live_test`, `mind_graph_test`, `mind_graph_modules_test`;
- any test that finds a button by a class, or by `variant: :ghost`'s look.

A CI failure is fixed in the task that owns the file.
