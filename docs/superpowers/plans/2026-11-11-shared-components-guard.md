# Shared components: a guard, and three moves to `ui/` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A test fails when one screen's component is drawn by another screen, by a shared component or by a registry. The three components that already are shared move to `app/components/admin/ui/` with the full `Admin::Ui::Contract`.

**Architecture:** `test/lib/component_screens_test.rb` maps every CS Studio view folder, controller and controller concern to the screen it draws, or to "shared". Each screen component's users are read from code that creates or renders its constant, with comments stripped. A component drawn from anywhere other than its own screen fails, and the message says to move it to `ui/`. `Admin::TranslationScreen::TranslateButtonComponent`, `Admin::TranslationScreen::TranslateAllComponent` and `Admin::EditorScreen::ReferenceCardComponent` become `Admin::Ui::TranslateButtonComponent`, `Admin::Ui::TranslateAllComponent` and `Admin::Ui::ReferenceCardComponent`, and their English literals become keys.

**Tech Stack:** Rails 8.1, ViewComponent, Minitest, Lookbook previews, Stimulus.

**Spec:** this plan is the agreed description (owner, 2026-11-11: "yes" to the guard and the moves). The rule it enforces is `docs/reference/design-system.md`, "A component that more than one screen uses moves to `ui/`…". The decisions are the design agent's:
- `DashboardScreen::PanelComponent` stays. `note_inbox/_card` is the dashboard's own "Notes for you" panel, which `Admin::NoteInboxController` redraws, so the map counts both as the dashboard's.
- The three moved components map to the Design System card `StudioTranslationPair` through `COVERED_BY`, and no card is added.
- None is merged with another component.

## Global Constraints

- New names: `Admin::Ui::TranslateButtonComponent`, `Admin::Ui::TranslateAllComponent`, `Admin::Ui::ReferenceCardComponent`. The old constants are gone with no alias, and are listed under `### Removed` in `CHANGELOG.md` `## Unreleased`.
- No look changes. Markup, classes, Stimulus identifiers (`admin--translation--translate` and the rest) and DOM ids stay as they are.
- Each moved component includes `Admin::Ui::Contract` and declares it fully, as `test/components/admin/ui/contract_test.rb` and `test/lib/component_parts_test.rb` require:
  - interface, slots, keys, controller, states with a preview example per static state;
  - `keyboard:` naming an existing browser test that reaches it, or the no-focus sentence where allowed (these three draw buttons, so each names a test);
  - its Design System entry, through `COVERED_BY` → `"StudioTranslationPair"` in `test/support/design_system_entries.rb`.
- Words become keys under `admin.components.ui.<component>` in `config/locales/admin/ui.en.yml`. That covers the literals the design agent listed:
  - TranslateAll: the label "Suggest translations for N empty fields" (pluralised by I18n, `one`/`other`), "Cancel", "Use all", "Discard all", "Suggesting…";
  - TranslateButton: "Translate", "Suggest update";
  - ReferenceCard: "Still correct — mark up to date", the formatting note, the too-long note, "↻ Changed".

  Words a script reads come through the server's `data-messages` (`docs/reference/i18n.md`). The components join `CONVERTED` in `test/lib/admin_i18n_test.rb`. Keys the components already read move with their words unchanged.
- The previews move to `test/components/previews/admin/ui/`, and the component tests to `test/components/admin/ui/`.
- Comments state invariants, never the plan step. Test commands are prefixed `PGGSSENCMODE=disable`. Browser tests run one file at a time, at load under 6, with nothing else testing.

## Review Focus

1. **A constant that is still named somewhere.** A script, a stylesheet comment, a doc, the MCP tools or a test may refer to an old name (`git grep -n "TranslationScreen::Translate\|EditorScreen::ReferenceCard"` must find nothing outside `CHANGELOG.md`'s Removed lines).
2. **A string a script shows** (the "Suggesting i of n" progress, Cancel, Use all, Discard all) must still read the same, now served as a key through `data-messages`. A browser test of Translate all must still pass.
3. **A guard that passes for the wrong reason.** A component referenced only in a comment must not count as a user. A view folder, controller or concern that is in no screen must fail the guard by name. And the guard must be able to fail (its own sample).
4. **Shared callers count.** `Admin::Ui::*`, `Admin::Columns::*`, `Admin::Fields::*`, `Admin::Shell::*`, `app/views/layouts/`, `app/views/admin/shared/`, `app/helpers/` and the answers' shared streams all count as users from "shared". A screen component drawn by any of them fails.
5. **The map stays honest.** The map is checked against the folders on disk, so a stale entry also fails.

---

### Task 1: TranslateButton moves to `ui/`, with keys and a contract

**Files:**
- Move: `app/components/admin/translation_screen/translate_button_component.{rb,html.erb}` → `app/components/admin/ui/`
- Move: `test/components/admin/translation_screen/translate_button_component_test.rb` → `test/components/admin/ui/`
- Create: its preview in `test/components/previews/admin/ui/` (one example per declared static state)
- Modify: every caller (`app/components/admin/ui/field_component.rb`, `app/components/admin/columns/base.rb`, `TranslateAllComponent`'s reads of its `BUTTON_CLASS`/`SPINNER_CLASS`, and anything `git grep` finds); `config/locales/admin/ui.en.yml` (`admin.components.ui.translate_button.label` "Translate", `.update_label` "Suggest update"); `test/lib/admin_i18n_test.rb` (`CONVERTED`); `test/support/design_system_entries.rb` (`COVERED_BY`); `CHANGELOG.md` (Removed)

**Interfaces:**
- Produces: `Admin::Ui::TranslateButtonComponent` with the same keywords as today, and the same `BUTTON_CLASS` and `SPINNER_CLASS` constants.
- [ ] **Step 1:** Move the files and rename the constant everywhere. Turn the `LABEL` and `UPDATE_LABEL` literals into `t(".label")`/`t(".update_label")` (the constants go). Declare the contract; the keyboard test is the existing browser test that presses Translate (find it with `git grep -ln "Translate" test/system`).
- [ ] **Step 2:** Run `PGGSSENCMODE=disable bin/rails test test/components test/lib` and `bin/rails zeitwerk:check`. Expected: pass.
- [ ] **Step 3:** Commit: `ref: the translate button is a shared component (Admin::Ui::TranslateButtonComponent)`.

### Task 2: TranslateAll moves to `ui/`, with keys and a contract

Same shape as Task 1. Callers: `app/components/admin/settings_screen/site_card_component.html.erb`, `app/components/admin/editor_screen/post_form_component.html.erb`, `app/views/admin/pages/show.html.erb`. Keys `admin.components.ui.translate_all.*`:
- `label` (`one`/`other`, "Suggest translations for 1 empty field" / "Suggest translations for %{count} empty fields"; if the Ruby today words the `one` case differently, keep today's words);
- `cancel`, `use_all`, `discard_all`, `suggesting`.

The script reads them from `data-messages`. Its preview moves.
- [ ] Steps as Task 1, plus run the Translate all browser test alone. Commit: `ref: Translate all is a shared component (Admin::Ui::TranslateAllComponent), its words keys`.

### Task 3: ReferenceCard moves to `ui/`, with keys and a contract

Same shape as Task 1. Callers: `app/components/admin/ui/field_component.rb`, `app/components/admin/columns/base.rb`. Keys `admin.components.ui.reference_card.*`:
- `confirm` "Still correct — mark up to date";
- `formatting_note` and `too_long_note`, with today's exact words;
- `changed` "↻ Changed".

Its existing keys move with it. Its preview moves.
- [ ] Steps as Task 1, plus run the reference card's browser test alone (the translation pair's). Commit: `ref: the reference card is a shared component (Admin::Ui::ReferenceCardComponent), its words keys`.

### Task 3b: Suggestion and Pending move to `ui/`

Found while building Task 1: `Admin::Ui::TranslateButtonComponent#box_id` reads `Admin::TranslationScreen::SuggestionComponent.dom_id`, and `Admin::TranslationsController` (the AI suggestion endpoint every editor field and Settings uses) renders it. That makes it a shared part: the box an AI suggestion streams into, under any translatable field. Same shape as Task 1: it becomes `Admin::Ui::SuggestionComponent`, its literals become keys `admin.components.ui.suggestion.*`, it gets a contract (keyboard: the existing browser test that accepts or discards a suggestion), its preview and test move, `COVERED_BY` → `"StudioTranslationPair"`, and the old constant goes under Removed. The comments in `field_component.html.erb`, `plain_column_component.html.erb`, `rich_text_column_component.html.erb` and `app/views/admin/shared/_translation_box.html.erb` name the new constant.
`Admin::TranslationScreen::PendingComponent` (the waiting state a suggestion box shows, rendered once by `app/views/layouts/admin.html.erb` into `#translation-pending-template` for the script to clone) is drawn by the layout, so it is shared too: it moves the same way to `Admin::Ui::PendingComponent`, renamed `Admin::Ui::TranslationPendingComponent` if a bare `Pending` would be ambiguous among `ui/`'s names (check `ls app/components/admin/ui`), its literals keys, its contract (it takes no focus → the sentence, if its markup draws nothing focusable).
- [ ] Steps as Task 1, plus run the suggestion's browser test alone. Commit (one per component): `ref: the AI suggestion box is a shared component (Admin::Ui::SuggestionComponent), its words keys` and `ref: the suggestion's waiting state is a shared component`.

### Task 4: The guard

**Files:**
- Create: `test/lib/component_screens_test.rb`
- Modify: `docs/reference/design-system.md`: the "No guard" line ("A component that a second screen uses moves to `app/components/admin/ui/`…") becomes the guard's rule, naming the test. Also the sentence "Whether a component has a second user is a judgement at review, and nothing finds a one-screen component that a second screen has begun to draw." Update CLAUDE.md's "Where a component goes" bullet, where it says "Which folder a component belongs in is a convention with no test", so it names the guard.

**Interfaces:**
- `SCREENS`: a hash from each screen folder under `app/components/admin/` (every folder but `ui`, `columns`, `fields`, `shell`) to the view folders under `app/views/admin/`, the controllers under `app/controllers/admin/` (with `answers/`) and the concerns under `app/controllers/concerns/admin/` that draw it. For example:
  - `editor_screen` ← views `pages`, `posts`; controllers `pages`, `posts`, `content_blocks`, `editing`, `publishing`, the answers; concerns `publishing_state`, `editing_claims`, …;
  - `dashboard_screen` ← views `dashboard` and `note_inbox`; controllers `dashboard` and `note_inbox`.

  Build it by reading which controller renders which view and component.
- `SHARED`: path prefixes whose files are users from "shared": `app/components/admin/ui/`, `columns/`, `fields/`, `shell/`, `slots.rb`, `admin_component.rb`, `app/views/layouts/`, `app/views/admin/shared/`, `app/helpers/`, `app/controllers/admin/base_controller.rb`, `app/controllers/application_controller.rb`.
- **A user** is a file under `app/` whose code, with comments stripped (reuse `SourceLayoutTest.code_of` or the same per-language rule), names the component's constant: `Const.new`, `render Const`, `Const::SOMETHING`, or a subclass.
- **Tests:**
  - "every screen component is drawn by its own screen only": for each class under a screen folder, every user is in that screen's folder or mapped to that screen. The failure names the component, each outside user and its screen (or "shared"), and says: "Move it to app/components/admin/ui/ and give it Admin::Ui::Contract (docs/reference/design-system.md, 'Component contract')."
  - "every admin view folder, controller and concern is mapped to one screen or shared": an unmapped one fails by name, and so does one mapped twice.
  - "the map names only folders and files that exist".
  - "the guard can fail": a planted sample, a screen component's constant written into a `ui/` file's code in memory, is refused; the same name written only in a comment is not.
- [ ] **Step 1:** Write the tests. Run them; the map tests fail until the map is complete.
- [ ] **Step 2:** Complete the map. After Tasks 1–3, the main test passes. If it names another component drawn from outside its screen, judge it:
  - it is the same screen drawn through another controller: fix the map;
  - it is truly shared: stop and report it with its users, and do not move it in this task.
- [ ] **Step 3:** Run `PGGSSENCMODE=disable bin/rails test test/lib`. Expected: pass. Then the docs edits.
- [ ] **Step 4:** Commit: `test: a component one screen owns is drawn by that screen only`.

### Task 5: Changelog and the Design System

- `CHANGELOG.md` `## Unreleased`:
  - `### Removed`: the three old constants, each with its new name, with no alias.
  - `### For a gem or an outside caller`: the three are shared components with a contract; their words are keys under `admin.components.ui.*`.
- `test/support/design_system_entries.rb`: `COVERED_BY` holds the three. Bump `VERSION` only if the design agent has published since; it is told when the build is done, and updates StudioTranslationPair's Code section.
- [ ] Run `bin/changelog-guard origin/main` and `PGGSSENCMODE=disable bin/rails test`. Commit: `docs: the three shared translation parts in the changelog`.
