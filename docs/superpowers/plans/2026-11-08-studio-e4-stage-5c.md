# CS Studio in E4, Stage 5c (Settings and the setup wizard) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Settings and the setup wizard take E4, as drawn on `StudioCalmE4Setup`. On Settings, each card is raised with its section's icon chip in a cool head, and the nav repeats the chips. The save bar is the screen's one primary area: it floats at the foot of the column and names what changed ("2 unsaved changes · Provider, Server"), and a changed field carries a violet edge. An "At a glance" rail shows the state of languages, AI, mail and images. In the wizard each step has one primary (Continue); Back and Skip for now are text buttons, and "Optional" is a word. The current step is violet on its tint and a done step has a green check. A progress bar, static per step, stands above the steps, and the first step opens with a welcome line. There is no "time left". Before any of it, the eight open Dependabot updates land (Task 0).

**Architecture:**
- One list of Settings' sections, `SettingsSections` (`app/values/settings_sections.rb`), gives the id, the right and the icon family of each. It is read by the nav, by one card frame (`Admin::SettingsScreen::CardComponent`, which all seven cards draw through), by the rail (`Admin::SettingsScreen::GlanceComponent`) and by ⌘K's Settings rows.
- One shared state chip, `Admin::Ui::StateChipComponent` (a dot and a word on its tone), draws every "how is this system part doing" mark: the rail's rows, the Mail card's state, the AI key, Test connection's result and the system check rows that Settings, the wizard and System status show.
- The save bar keeps its controller. What it counts moves into a plain module (`app/javascript/saving/form_snapshot.js`), which also answers which controls changed and their names, so the bar can name them and mark them (`data-save-bar-changed`).
- The wizard's layout draws the progress and the step list from `SetupController::STEPS`, and its words become keys (`config/locales/setup.en.yml`).
- The Mail fields of the Settings card and of the wizard's Mail step become one component (`Admin::SettingsScreen::MailFieldsComponent`) with one port rule (`mail-port`), in two groups, Server and Sender.

**Tech Stack:** Rails 8.1, ViewComponent 4 with Lookbook previews, Tailwind v4 (`tailwindcss-rails`), Turbo frames and streams, Stimulus over import maps, Minitest with Capybara on Cuprite.

**Spec:** `docs/superpowers/specs/2026-11-06-studio-e4-design.md` (approved 2026-11-06). Sections used:
- "Decided on 2026-11-06", items 4, 14 and 15;
- "The design, as decided": tokens, the icon hue map, buttons, the four roles and status;
- "Every screen, and its stage": the rows "Settings" and "Setup wizard";
- "The rule for a screen the artifact does not draw" (the wizard's steps other than the first and Mail);
- "Stage 5", item **5c** in full;
- "Architecture-review findings", "The guard after E4" and "Constraints".

The drawing is `StudioCalmE4Setup` in the Design System artifact (https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT, read at version 1794108449-0fdc). It draws Settings at 1900px, the wizard's first step and its Mail step at 1440px, each in light and dark. Its sibling cards `SaveBar` ("Decided, not built (E4 stage 5c)": the floating bar and the changed-field edge) and `StudioRail` were read too.

**One pull request** on branch `studio-e4-5c`, made from `main` at 6cb49c02, targeting `main`. Task 0 comes first, and its body says "Supersedes #204–#211". Dependabot closes those eight itself once `main` has the versions. Task 0 needs no design answer and may be dispatched while the design questions are out.

---

## Design questions

The spec and the drawing leave these open, or settle them against a rule another stage made. Each is sent to the design agent before Task 1, and the answers are written to `.superpowers/sdd/design-answers-5c.md` in this worktree. The tasks below are written on the recommendation. An answer that differs is written into its task by the controller before that task is dispatched.

1. **Each section's icon chip and family** (the nav, the card heads, the rail's rows). Drawn: Site structure, Languages code, Publishing lists, Forms form, AI translation **accent**, Mail media, Images media. The icon chip has no accent family, and stage 4 kept accent out of the sidebar's chips: it means the current module and "unread and addressed to you".
   - (a) As drawn, with a ninth `:accent` family for the chip.
   - (b) As drawn, but AI translation takes `code` (the sidebar's "AI assistant" is code) and Languages takes `text` (the sidebar's Translations is text).
   - (c) Every section neutral.

   The icons, from the existing set: Site `pages`, Languages `translations`, Publishing `file_text`, Forms `clipboard_list`, AI `assistant`, Mail `at_sign`, Images `image`. The other way is the drawing's own glyphs added to `admin/shared/_icon.html.erb`.
   **Recommend (b), with the existing icons.**
2. **The wizard's welcome line.** It is drawn in accent words (14px, 600) with an accent chip ("Welcome to Content·Spiel"), above the heading "Let's set up your site". Accent words on something that cannot be pressed read as a link.
   - (a) As drawn.
   - (b) Ink words at 600 with a `structure` chip.
   - (c) No chip, the line in `text-meta`.

   **Recommend (b).**
3. **"Where do I find the log?"** It is drawn as a tertiary button beside Continue on the token step, with no target.
   - (a) A disclosure under the field with the commands that show the log: `bin/dev`'s terminal in development, `docker compose logs web`, and `kamal app logs` or `contentspiel logs` where `docs/reference/hosting.md` names one. The words go to the design agent.
   - (b) A link to the guide's hosting page in `contentspiel-docs`, opening in a new tab.
   - (c) Leave it out.

   **Recommend (a)**: the wizard works with no network and before the guide's address is known.
4. **The Languages card's "Default".** It is drawn as the solid green Live chip, "● Default". Live means published, and the guard keeps the Live fill to the status chip.
   - (a) As drawn.
   - (b) The neutral `BadgeComponent` "Default", as today.
   - (c) An accent-tint badge.

   **Recommend (b).**
5. **The look of a system state** (the rail's rows, and the same states in the cards). Drawn: the Live fill for "● On", "● Connected" and "● Ready", and the Scheduled fill for "◷ Not tested".
   - (a) As drawn: publishing's colours for system states.
   - (b) One shared state chip, a dot and a word on the `ok`, `warn` and `danger` tints (and an outlined "off"). It is used by the rail, the Mail card's state, the AI key's state, Test connection's result and the system check rows, so System status's rows change too.
   - (c) As (b), but System status keeps its look until 7b.

   **Recommend (b)**: one job, one component, and the ok/warn/danger roles are these states' roles in the spec.
6. **What each rail row says.** The drawn "3 languages ● On" says nothing that can change. "Connected" cannot be known on load: Test connection's result is not stored.
   - Languages: "3 languages", then "English is the default", with no chip.
   - AI translation: "Off" (no provider), "No key" (a provider, no key), "Key saved" (a key that was not tested on this visit), then "Connected" or "Not connected" after Test connection is pressed on the page.
   - Mail: the four words `MailSettings#state` already has: Not set up, Saved, not tested, Working, Last send failed.
   - Images: "Ready", "12 waiting" (made with other settings), "2 failed" (both when both), or "No images yet".

   **Recommend these.** Not recommended: storing the last test result, which would be a new column and a write path.
7. **The rail's rows and its hint.**
   - (a) Each row is a same-page link to its card (`#languages`, `#ai`, `#mail`, `#images`), exempt from the leave guard as the nav's are.
   - (b) Plain text.

   The drawn hint under the rows ("Settings save together, with the bar at the foot: they are configuration, not content.") is kept or left out. **Recommend (a), and keep the hint.**
8. **Where the rail docks, and where it stands below that.**
   - The threshold: (a) the shared 1200px, measured on the Settings area's own width (nav, column and rail), so the column narrows from 760px to about 614px between 1200px and 1346px, as the editors' blocks column takes what the rail leaves; (b) only once the column keeps its full 760px, which is a second threshold of 1346px.
   - Below the threshold: (i) a compact card above the first card, first in the document after the nav; (ii) not shown, since the cards say it; (iii) under the nav, in its column.
   - Docked, sticky under the top bar as the lists' rail is, or not.

   **Recommend (a), (i), sticky.**
9. **The floating save bar.**
   - (a) Where: on Settings only, or on every explicit-save screen whose bar is not `contained:` (Groups, Users, Your account's profile form, the form builder).
   - (b) Its words: "Save changes" and "Discard" everywhere, or a screen's own label kept where it passes one ("Save group", "Create group").
   - (c) With nothing to save: Save changes disabled, "No unsaved changes", the accent dot hidden.
   - (d) At the end of the form the bar keeps floating at elevation 3, so the "stuck" state (a strong top edge and `--cs-shadow-stuck`) goes.
   - (e) After a refused (422) or stale (409) save, the bar names the typed fields that differ from the saved settings. That works on Settings only, which has the stored values; elsewhere the bar says "Unsaved changes".
   - (f) At most three names, then "and N more". A control that has no plain label gets its own name: "Deutsch: Falls back to", "Language order", "Social links", "Logo".

   **Recommend:** (a) every non-contained bar, (b) "Discard" everywhere with a screen's own Save label kept, and (c)–(f) as written.
10. **The changed-field mark.**
    - Drawn: a 2px accent inset bottom edge on a well.
    - Not drawn: a segmented control, a checkbox, the language list's order, the social link rows and the logo's drop zone. (a) The same edge under the control's frame; (b) the bar's 8px accent dot after the field's label or legend; (c) no mark, since the bar names them.
    - When a field is both changed and invalid: (i) the invalid edge wins; (ii) both are shown.
    - Where: Settings only, or every screen that has the floating bar (Q9 a).

    **Recommend (b), (i), and every screen with the floating bar.**
11. **The instant actions' buttons.**
    - Drawn: Make default… and Add language secondary; Turn off… and Remove… danger text; Replace, Test connection and Send test mail secondary.
    - Not drawn: "Save key" (the AI key's entry) and "Save login" (the mail login), primary today. (a) They stay primary (their own forms, but a second primary on the screen). (b) They become secondary.

    **Recommend as drawn, and (b).**
12. **The card's head.**
    - Its ground, drawn as `--cs-rail` (the cool ground) with the 22px chip.
    - Its heading, drawn at 18px, a size with no token: (a) `text-h2` (20px, today); (b) `text-h3` (15px); (c) a new 18px token.
    - Its intro: drawn in `--cs-dim`, while the drawing's measured figure (6.3 / 6.4:1) is `--cs-meta`'s.
    - The Site card's language tabs stay in its head.

    **Recommend `--cs-rail`, (a), dim.**
13. **"Optional".** It is drawn as a meta word in the step list and as an outlined chip (Draft's look) beside the Mail step's heading.
    - (a) As drawn.
    - (b) One look in both places, the meta word.
    - (c) The neutral badge in both.

    **Recommend (b).**
14. **The wizard's action row on every step.** The Mail step draws: Send test mail (secondary), "Sends to you", then at the row's end Back, Skip for now (tertiary) and Continue (primary). The first step draws Continue first, then "Where do I find the log?".
    - (a) On every step a step's own secondary (Re-run checks, Send test mail) starts the row, and Back, Skip and the primary end it, the primary last.
    - (b) The primary first everywhere, as today.

    Where the step's action advances, it is the primary in Continue's place: "Generate token", "Add starter content", "Finish setup". And "Sends to you" (drawn), or today's "Sends to <address> (your address)"? **Recommend (a), the step's own action as the primary, and keep the address.**
15. **One Mail form, two screens.** The wizard's Mail step is drawn in two groups, Server (a `media` chip: server, port, security, login) and Sender (a `text` chip: name, address), each on the paper ground at the tile radius. The Settings card is drawn without groups.
    - (a) Both screens draw the same two groups through one component.
    - (b) Only the wizard groups them.

    **Recommend (a).**
16. **⌘K's Settings rows.** ⌘K offers four sections (Site, Publishing, Languages, AI translation) in its own order. With one list of sections, it offers all seven in the nav's order, each under its right: Site, Languages, Publishing, Forms, AI translation, Mail, Images. **Recommend yes.**

## Design answers

Before Task 1 the design agent's answers are written to `.superpowers/sdd/design-answers-5c.md`. An implementer reads that file beside their task. A look that neither the answers nor the drawing settle is reported as **NEEDS_CONTEXT**, never decided at review.

## Global Constraints

- **Design first.** An implementer who meets a look, a word or a state that neither this plan, the answers nor the drawing settle stops and reports **NEEDS_CONTEXT**, naming the gap. The design agent answers in the artifact, marked "Designed, not built", and the answer goes back to the same implementer.
- **The public site keeps its look.** No file under `app/assets/tailwind/themes/`, `app/components/blocks/`, `app/components/posts/`, `app/components/public/`, `app/views/layouts/public/` or `app/views/pages/` changes, and no `th-*` token.
- **CLAUDE.md binds every task.** In particular:
  - Settings saves explicitly through `Admin::Ui::SaveBarComponent`. Nothing on Settings or in the wizard autosaves.
  - `Settings::Save` and `Locales::*` keep locking the settings row first. No task changes a service.
  - The instant actions keep their own forms outside `#settings-form`, reached with `form=`. A named control of the explicit-save form is never locked.
  - A token, an API key, a password and the mail login are never rendered. The host's login stays the card's mask (`MailLoginComponent::MASK`) in both screens. The wizard's own box once printed it, and `test/integration/setup_mail_step_test.rb` holds that it never does again.
  - `MailSettings` is the one reader of the `MAIL_*` variables and of the delivery columns. A new screen file that names a `mail_` column joins `COLUMN_NAMERS` (`test/lib/mail_guards_test.rb`), with its reason.
  - Dependency direction: `SettingsSections` (a value) knows no component. `Jump::Search` reads it, never a component.
  - Never define `Admin::<Domain>`. The Settings components stay in `Admin::SettingsScreen::`.
- **No admin string is a literal.**
  - A component under `app/components/admin/<folder>/` reads `admin.components.<folder>.*` from `config/locales/admin/<folder>.en.yml`.
  - The Settings view reads `admin.settings.show.*` from `config/locales/admin/settings.en.yml` (new). The controllers' `admin.settings.*` answers move there from `settings_screen.en.yml` in Task 2, so each file holds one tree.
  - The wizard reads `setup.*` from `config/locales/setup.en.yml` (new): a view by lazy lookup (`setup.token.*`), the layout by full key (`setup.layout.*`), and the step names as `setup.steps.<step>`.
  - A script's words come from `data-messages`.
  - A key is added in the task whose code reads it. A file converted to keys is converted whole, in one task, and joins `admin_i18n_test.rb`'s `CONVERTED` in that task.
  - Out of scope, as `docs/reference/i18n.md` names them: `Setup::SystemCheck`'s sentences, which stay English.
- **The component contract.** A new or changed shared component (`app/components/admin/ui/`) declares `Admin::Ui::Contract` (`app/components/component_contract.rb`, `app/components/admin/ui/contract.rb`). It has a component test, a preview example per previewable state, and a Design System entry, or a `DesignSystemEntries::NOT_YET` reason. A new one names its keyboard browser test, or stands in `UiContract::KEYBOARD_NOT_YET` until the task that writes it. `StateChipComponent` is new; `SaveBarComponent`, `SystemCheckRowComponent` and `BadgeComponent` change.
- **Buttons are the shared button.**
  - One primary per area: Settings' is the bar's Save changes, and a dialog's is its confirm. In the wizard it is the step's Continue or the step's own advancing action.
  - Back, Skip for now, Discard and "Where do I find the log?" are `:tertiary`. Turn off… and Remove… are `:danger_text`.
  - A new accent fill or tint pair that is no button goes into `ACCENT_FILL_ALLOWED` or `TINT_PAIR_ALLOWED` with its reason, in the task that draws it.
- **The rail** (spec rule 5) docks by the Settings area's own container, never a window `@media`. It comes first in the document after the nav at every width, so the focus order is the document's and nothing is moved by script.
- **Layers.** No raw z-index. The floating bar keeps `--cs-z-sticky`.
- **Contrast is measured** (`test/lib/admin_contrast_test.rb`) in both schemes. The spec's figures are floors: the changed-field edge is 6.9 / 7.1:1, the progress fill 6.9 / 7.1:1 against its track, and the current step's violet on its tint 5.7 / 6.3:1.
- **Comment rule (#117).** A comment states a current invariant, a hazard or a reason. It never states a plan step, a review round, "spec §", "handoff §", "decision D9", "ruling P2", "final review 1", "Final fix wave (Important 3)" or what used to be there. The Settings and setup files are full of these. Every task rewrites the comments of the files it changes. Its last step before its commit runs the grep below over the files the task changed, and it prints nothing:

  ```
  grep -n "spec §\|handoff §\|Task [0-9]\|round [0-9]\|final review\|[Rr]uling [A-Z][0-9]\|decision D[0-9]\|fix wave\|ledger C-\|design answer [A-Z][0-9]\|old name\|used to\|no longer"
  ```

  The plan's wording is never copied into a comment.
- **Tests and the machine.**
  - On macOS every test command is prefixed with `PGGSSENCMODE=disable`. The worktree runs `bin/rails db:test:prepare` once before its first test.
  - Browser tests run only after `bin/rails tailwindcss:build`, never during a build or beside a running `bin/dev`. They run one file at a time, and only while the one-minute load (`sysctl -n vm.loadavg`, first figure) is under 6.
  - A browser test begins on `visit_screen` or `visit_editor`. A test this stage rewrites moves its bare `visit … await_admin_controllers` onto them. The wizard runs signed out, before CS Studio's controllers exist, so its tests keep `visit`.
  - No new browser file. The tests join `settings_test.rb`, `save_bar_test.rb`, `setup_wizard_test.rb`, `settings_mail_test.rb` and `ai_settings_test.rb`. New unit files are weighed by their count (`bin/test-shard`). No task deletes a test file.
  - **No test run is left in the background** when a task ends: its last step checks that `pgrep -f "rails test"` prints nothing.
- Commits follow conventional commits and end with:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT`
  A task that carries a finding says so in its body ("Advances #117").

## Review Focus

1. **After a refused or stale save.** A 422 or 409 re-renders Settings with the typed values, and the browser's baseline is then those values, so its own comparison finds nothing changed. The bar must still say which fields are unsaved, mark them, and keep the leave guard. Task 5: `test "after a refused save the typed fields that differ from the saved settings carry the mark and the bar names them"` (browser) and `test "Values#changed_names lists what was typed and differs from the stored settings, and nothing on a plain load"` (component).
2. **A control with no plain label.** These are the language rows' fallback selects (whose label is "Falls back to" plus a hidden " for Deutsch"), the social link rows (`aria-label` "Network" or "URL" on every row), the hidden language order, the logo's drop zone and the segmented controls (a legend). Each must give the bar a name a person can read. Task 5: `test "every control the Settings form submits has a name the bar can say"` (integration: every named, non-ignored control of `#settings-form` has `label[for]`, a legend or `data-save-bar-name`).
3. **A viewer with only `languages.manage`.** They see the Languages card alone. The rail must not tell them whether mail works, whether an AI key is saved or how many images failed. Task 4: `test "a viewer with languages.manage alone sees the languages row and no other state"`.
4. **The rail after an instant action.** Test connection, Send test mail, a saved or removed AI key and a saved mail login each answer with streams that replace their own card's part. The rail's row must follow in the same answer, and a mail field saved through the bar makes mail "Saved, not tested" again (a new fingerprint). Task 4: `test "Test connection, Send test mail and a saved key update their rail row in the same answer"` (integration) and `test "saving a mail field puts the rail's Mail row back to Saved, not tested"` (browser).
5. **Enter on the Mail step.** Continue moves to the end of the one row, after Send test mail. Enter in a field must still mean Continue, never "send a mail". Task 7: `test "Enter in a Mail field continues and sends no mail, whatever the row's order"` (browser).

---

## Decisions the spec left open (not looks)

| Question | Decision | Why |
|---|---|---|
| Where the section list lives | `SettingsSections` in `app/values/settings_sections.rb`. `Section = Data.define(:id, :permission, :family, :icon)`; `ALL` in the nav's order; `.for(&holds) -> Array<Section>`; `.ids -> Array<String>`. Each section's words are `admin.components.settings_screen.sections.<id>`, read by full key by the nav, the card frame and the rail. | The nav and ⌘K hold two lists of the same sections today. A value is below both the components and `Jump::Search`. |
| ⌘K's titles | `Jump::Search` builds its Settings rows from `SettingsSections.for` and keeps its English titles in `SETTINGS_TITLES` (a Hash keyed by the section ids), because it matches what a person types against them and is not converted. A test asserts `SETTINGS_TITLES.keys == SettingsSections.ids`. | A query may not read a component, and its words are not part of this conversion. |
| The card frame | `Admin::SettingsScreen::CardComponent.new(section:, intro: nil, **html)`, with `renders_one :head_end` (the Site card's language tabs) and `renders_one :head_note` (the Mail state, the Languages pending hint). Content is the body. It draws `section#settings-<id>-card.admin-settings-card[aria-labelledby=<id>]` and `h2#<id>`, which keeps every anchor the nav, ⌘K and the tests use. `**html` (an `id`, `data`) is merged onto the section. | Seven cards write the same section, head and heading by hand. |
| The rail's data | `GlanceComponent.new(sections:, site_setting:, mail_settings:, images_progress:, ai_result: nil)`. It reads only what the view already has: `MailSettings.current(@site_setting)`, `Media::RenditionProgress#counts` (already computed for the Images card), the `ai_*` columns, `Locales.enabled` and `Locales.default`. It runs no query of its own. Each row is its own element, `#settings-glance-<id>`, so an answer replaces one row. | The spec: "a component and not a query". |
| Which answers redraw a row | `SettingsController#mail_test_streams` adds `replace("settings-glance-mail")`. `ai_test_result_stream` adds `replace("settings-glance-ai")` with `ai_result:` (`:connected` or `:failed`). `AiKeysController` and `MailLoginsController` add the AI and Mail row through `Admin::CarriedBase`'s ending, beside the part they replace. | Review Focus 4. |
| Where the snapshot logic goes | `app/javascript/saving/form_snapshot.js`: `snapshot(form) -> { values: Object, controls: Object<key, Element[]> }`, `changedKeys(initial, now) -> String[]`, `nameOf(control) -> String`. The controller imports it, and its `snapshot()` and `changes` become calls to it. | Marking and naming need the key's controls. The controller (560 lines) does not grow, and the keys stay in one place. |
| The changed mark's one writer | `admin--saving--save-bar#refresh` writes `data-save-bar-changed` on the nearest `[data-field-name]` of each changed control (the cards already carry it for errors), and removes it from the rest. The server writes `data-save-bar-changed="saved"` on a wrapper only in a refused or stale re-render (`Values#changed_names`). The script keeps such a mark until a save or Discard, since the browser does not know the saved value. | One writer in the browser. The server's mark covers Review Focus 1. |
| The bar's words | Keys in `ui.en.yml` under `save_bar`: `save_changes` "Save changes", `discard` "Discard", `names` "%{changes} · %{names}", `more` (`one` "%{names} and 1 more", `other` "%{names} and %{count} more"), `separator` ", ". `cancel` goes once its last reader goes. `NAMES_SHOWN = 3`, in `form_snapshot.js`. | Q9. The list is joined by a key, so a language may change the separator. |
| The wizard's progress | `SetupHelper#setup_progress(step) -> { number:, total:, fraction: }` from `SetupController::STEPS`. `fraction` is `number / total` rounded to 2 places: 0.11 on the first step, 0.56 on the fifth, as drawn. The bar is `aria-hidden`. "Step %{number} of %{total}" is its visible text (`setup.layout.progress`). | Static per step (the spec), and no time is measured. |
| Which step carries the welcome | `token` alone, the first step of a fresh install. A signed-in owner who resumes at `site` sees no welcome. | "The first step" is the first a new owner meets. |
| The step names | `SetupController::LABELS` goes. `step_label(step)` reads `I18n.t("setup.steps.#{step}")`, and a test asserts that `setup.steps` holds exactly `STEPS`. | Its words become keys. |
| One port rule | `app/javascript/controllers/mail_port_controller.js` (`mail-port`, top level, since the wizard loads only `application`) replaces `setup_mail_controller.js` and `admin--settings--mail#security` with its `port` target. `admin--settings--mail` keeps the login entry's hold. | The two hold the same rule twice, and their headers say so. |

---

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `Gemfile`, `Gemfile.lock`, `.github/workflows/release.yml`, `test/components/previews/preview_fixtures.rb`, `test/components/previews_test.rb`, `test/queries/dashboard/waiting_for_you_test.rb`, `test/application_system_test_case.rb`, 14 system files (`page.driver.resize`) | the dependency updates and what they break | 0 |
| `app/components/admin/ui/state_chip_component.rb` (new), `settings_screen/mail_state_component.rb`, `ai_key_component.{rb,html.erb}`, `ai_test_result_component.rb`, `ui/system_check_row_component.{rb,html.erb}`, `ui.en.yml`, `settings_screen.en.yml` | one state chip | 1 |
| `app/values/settings_sections.rb` (new), `settings_screen/card_component.{rb,html.erb}` (new), `nav_component.*`, the seven cards' heads, `app/views/admin/settings/show.html.erb`, `app/queries/jump/search.rb`, `config/locales/admin/settings.en.yml` (new), `content-spiel.tailwind.css` (`.admin-settings-*`) | the sections, the nav, the card frame | 2 |
| `settings_screen/{site,languages,publishing,ai}_card_component.*`, `ai_key_component.*`, `mail_login_component.*`, `images_card_component.html.erb`, `language_dialogs_component.*`, `values.rb` | the cards' bodies in keys, their buttons | 3 |
| `settings_screen/glance_component.{rb,html.erb}` (new), `show.html.erb`, `settings_controller.rb`, `ai_keys_controller.rb`, `mail_logins_controller.rb`, `concerns/admin/carried_base.rb`, `content-spiel.tailwind.css` (`.admin-settings-layout`) | the rail and the layout | 4 |
| `ui/save_bar_component.{rb,html.erb}`, `app/javascript/saving/form_snapshot.js` (new), `controllers/admin/saving/save_bar_controller.js`, `values.rb`, the cards (`data-save-bar-name`, the server mark), `content-spiel.tailwind.css` (`.admin-save-bar`, `[data-save-bar-changed]`) | the floating bar, the names, the mark | 5 |
| `app/views/layouts/setup.html.erb`, `app/views/setup/_steps.html.erb` (new), the setup views but `mail`, `app/helpers/setup_helper.rb`, `app/controllers/setup_controller.rb` (`LABELS`), `config/locales/setup.en.yml` (new) | the wizard | 6 |
| `settings_screen/mail_fields_component.{rb,html.erb}` (new), `settings_screen/host_value_component.rb` (new), `mail_card_component.*`, `app/views/setup/mail.html.erb`, `controllers/mail_port_controller.js` (new), `controllers/setup_mail_controller.js` (deleted), `controllers/admin/settings/mail_controller.js` | one Mail form, two screens | 7 |
| `docs/reference/{settings-languages-ai,mail,design-system,save-rule-and-write-queue,i18n}.md`, `CLAUDE.md`, `CHANGELOG.md`, `test/support/design_system_entries.rb` | the reference, the PR and the cards | 8 |

---

### Task 0: The dependency updates (supersedes #204–#211)

The eight Dependabot pull requests, read on 2026-11-08 with `gh pr view` and `gh pr diff`. Every check had finished; none was pending.

| PR | Bump | CI | What failed, and why |
|---|---|---|---|
| #204 | `actions/download-artifact` 4 → 8 (`release.yml:176`) | green | — |
| #205 | `actions/upload-artifact` 4 → 7 (`release.yml:97`) | `test-shard (0)`, so `test` | **Not the bump.** `Dashboard::WaitingForYouTest#test_a_page_and_a_post_with_the_same_id_and_the_same_time_are_ranked_by_their_model…` (`test/queries/dashboard/waiting_for_you_test.rb:131`) raised `PG::UniqueViolation … "posts_pkey" Key (id)=(2)` at line 137. The test moves its post's id to its page's id with `update_all`. Sequences are not rolled back between transactional tests, so on a worker whose posts sequence is behind its pages sequence, the next `create_post` draws the id just taken. It depends on what that worker ran before (seed 25300). |
| #206 | `view_component` 4.20.0 → 4.23.0 (`~> 4.23`), and minitest 6.0.6 → 6.1.0 | `test-shard (0)`, so `test` | `ComponentPreviewsTest` (`test/components/previews_test.rb:28`): `Admin::Ui::LibraryImageComponentPreview#width raised ActiveStorage::FileNotFoundError`. In 4.20 `render_preview` called the controller's `previews` method directly. 4.21 to 4.23 call `previews_controller.process(:previews)`, the whole action, so `ComponentPreviewsController`'s `around_action :discard_preview_writes` now runs in tests too. That action is a `transaction(requires_new: true)` that always rolls back. `PreviewFixtures.processed_media_asset` attaches a file and calls `asset.file.analyze`. Active Storage uploads an attachment in `after_commit` (`activestorage-8.1.4.1/lib/active_storage/attached/model.rb:144`), which never fires inside a savepoint that is rolled back. So the file is never written, and `analyze` cannot download it. In development Lookbook takes that path already, so this preview is broken in Lookbook today. The test flunks at the first preview that raises, so others may fail after it. |
| #207 | `solid_queue` 1.7.0 → 1.7.2, with fugit 1.14.0, irb 1.19.0, minitest 6.1.0 | `system-test-shard (0)`, so `system-test` | `Admin::RichTextSystemTest#test_Enter_on_a_plain_word_applies_nothing_and_says_what_to_do…` (`test/system/admin/rich_text_test.rb:366`): "expected not to find visible css .admin-rich-text-popover, found 1". It is a browser test of the editor's link popover, which solid_queue does not reach, and it passed on the six other runs that day. It is taken as a flake to watch (Step 6). |
| #208 | `opentelemetry-instrumentation-all` 0.99.0 → 0.100.0 (`~> 0.100`), net_http 0.29.2 → 0.30.0 | green | — |
| #209 | `anthropic` 2.3.0 → 2.5.0 | green | — |
| #210 | `cuprite` 0.19 → 0.20, ferrum 0.19.1 → 0.20.1 (development and test) | every system shard (1,521 errors) | Every browser test: `ArgumentError: wrong number of arguments (given 0, expected 1+)` at `test/application_system_test_case.rb:80`, in `StaleNodeAtOnce#command(name, *args)`. Cuprite 0.20 made `Node#command` private, as `command(function = nil, *args)` with a block form (`command { before_click(...) }`), and checks `this.isConnected` itself before every command. The second error, "given 0, expected 2", is `teardown { page.current_window.resize_to(*@original) }` after a setup that failed first. `Driver#resize` is deprecated (52 calls in 14 files) and goes in 0.21. |
| #211 | `mcp` 1.8.2 → 1.9.0 (`~> 1.9`) | green | — |

**What CLAUDE.md flags, checked:**
- **The `turbo-rails` pin** (`Gemfile:21`, `2.0.23` exact): no bump moves it, and `--conservative` keeps it. Step 2 checks the lockfile for it.
- **ViewComponent APIs the contract relies on:** `ViewComponent::Preview.all` and `#examples` (`test/lib/component_parts_test.rb:102`) and `render_preview` (`component_parts_test.rb:149`, `previews_test.rb`) are unchanged in name. `render_preview` now runs the action's callbacks and renders through `response.body`. `with_request_url` restores more request state (4.21, 4.23), and eight component tests use it. No component calls a private ViewComponent API.
- **CI's artifacts between the shard jobs and the aggregate checks:** `ci.yml` already uses `upload-artifact@v7` (coverage, screenshots), and its aggregate `test` and `system-test` jobs download nothing. They read `needs.*.result`. The bumped pair is `release.yml`'s release notes: uploaded in `decide`, downloaded in the publish job, and run only on `main` when a release is cut. No pull request's CI runs that pair. Step 4 reads both actions' release notes for `name:`-only downloads.
- **anthropic and mcp:** `AI::Providers::Anthropic` uses `Anthropic::Client.new(api_key:, base_url:, timeout:, max_retries:)` and eight `Anthropic::Errors::*` classes (`app/models/ai/providers/anthropic.rb:80`, `:174–186`). `app/mcp/` uses `MCP::Server`, `MCP::Tool`, `MCP::Tool::Response`, `MCP::Tool::InputSchema` and `MCP::Server::Transports::StreamableHTTPTransport`. Both PRs were green. Step 5 runs those tests and greps the gems' changelogs for those names.
- **cuprite for the browser tests:** above, and `JsErrorCollector`, which is prepended to `Ferrum::Page#subscribe` (still in Ferrum 0.20.1, `lib/ferrum/page.rb:607`).
- **The changelog guard** watches `contract_ledger.rb`, `plugins.rb` and `db/migrate/` only, so none of this needs a line. The exception would be a solid_queue upgrade that ships a migration for `db/queue_schema.rb`. Step 2 reads the gem's notes for 1.7.1 and 1.7.2. If there is one, it becomes a migration with its version under `### Migrations`.

**Files:**
- Modify `Gemfile`: `view_component "~> 4.23"`, `opentelemetry-instrumentation-all "~> 0.100"`, `mcp "~> 1.9"`.
- Modify `Gemfile.lock` through `bundle update --conservative view_component solid_queue opentelemetry-instrumentation-all anthropic cuprite mcp`.
- Modify `.github/workflows/release.yml`: `actions/upload-artifact@v7` (line 97), `actions/download-artifact@v8` (line 176).
- Modify `test/components/previews/preview_fixtures.rb`: `media_asset` and `processed_media_asset` make their blob with `ActiveStorage::Blob.create_and_upload!(io:, filename:)` and attach it (`asset.file.attach(blob)`), so the file is written whether or not a transaction commits. `processed_media_asset` analyzes the blob it made. The module's comment says why: the preview controller's savepoint is always rolled back, and an attachment's own upload waits for a commit. It also says that a blob uploaded this way stays on disk after a Lookbook visit, while the database rows do not.
- Modify `test/components/previews_test.rb`:
  - It collects every preview that raises and fails once, naming them all, instead of stopping at the first.
  - Its comment says that `render_preview` runs the controller's callbacks, as Lookbook does, `discard_preview_writes` included.
- Modify `test/queries/dashboard/waiting_for_you_test.rb:131–145`. After the `update_all(id: page.id)`, `Post.connection.reset_pk_sequence!(Post.table_name)`, so the next post draws an id above every post. A comment says why.
- Modify `test/application_system_test_case.rb`, `StaleNodeAtOnce`. First run `test/system/stale_node_test.rb` ("a node from a replaced page is stale at once") with the prepend removed:
  - If it passes, Cuprite 0.20's own `this.isConnected` check is enough: delete the module and its comment, and say so in the commit.
  - If not, keep it as `def command(...)` with `raise … unless node.exists?` and `super`, and rewrite the comment for 0.20's two checks.
- Modify the 14 files that call `page.driver.resize(w, h)` (`shell_test`, `table_block_test`, `save_bar_test`, `code_block_test`, `admin/sections_translation_and_unavailable_test`, `admin/rich_text_test`, `admin/form_width_test`, `admin/translations_test`, `admin/publish_dialog_steady_test`, `admin/media_picker_test`, `admin/filter_bar_test`, `admin/settings_test`, `admin/system_status_and_preview_test`, `admin/translation_layout_test`) to `page.current_window.resize_to(w, h)`. Also fix any other deprecation warning the run prints.
- Test: `test/components/previews_test.rb`, `test/lib/component_parts_test.rb`, `test/queries/dashboard/waiting_for_you_test.rb`, `test/models/ai/providers/anthropic_test.rb`, `test/mcp/`, `test/integration/mcp*_test.rb`, `test/integration/opentelemetry_test.rb`, `test/lib/telemetry/`, `test/lib/job_queues_test.rb`, `test/system/stale_node_test.rb`.

- [ ] **Step 1: Reproduce the two unit failures.** Run `PGGSSENCMODE=disable bin/rails test test/components/previews_test.rb` on 4.20 (expected PASS). Run `test/queries/dashboard/waiting_for_you_test.rb` and check by reading that a posts sequence behind the pages sequence collides. A `--seed` alone cannot force it, since the sequences carry over from other files. Write the sequence fix and the fixture fix, and run both files again: PASS.
- [ ] **Step 2: Bump the gems.** Run `bundle update --conservative view_component solid_queue opentelemetry-instrumentation-all anthropic cuprite mcp` after the three `Gemfile` edits. Check `git diff Gemfile.lock`: the six gems, with ferrum, fugit and opentelemetry-instrumentation-net_http as needed, and nothing else. `turbo-rails` stays `2.0.23`. Minitest and irb move only if a bumped gem requires them, and the PR body names every gem that moved. Read solid_queue's 1.7.1 and 1.7.2 release notes for a queue schema change.
- [ ] **Step 3: Run the unit suite's affected files.** `PGGSSENCMODE=disable bin/rails test test/components test/lib/component_parts_test.rb test/queries/dashboard test/models/ai test/mcp test/integration/mcp_test.rb test/integration/mcp_access_control_test.rb test/integration/mcp_media_test.rb test/integration/mcp_rate_limit_test.rb test/integration/opentelemetry_test.rb test/integration/mail_telemetry_test.rb test/lib/telemetry test/lib/job_queues_test.rb test/jobs`. Expected: PASS. If `previews_test` names more previews, fix each fixture the same way.
- [ ] **Step 4: The actions.** Edit `release.yml`. Read the release notes of `upload-artifact` v5 to v7 and `download-artifact` v5 to v8. Confirm that a `name:`-only download still lands `release-notes.md` in the workspace root, where `gh release create … --notes-file release-notes.md` reads it, and that the runner needs nothing these hosted runners lack. Write the finding in the PR body, since no PR run exercises it.
- [ ] **Step 5: anthropic and mcp.** Grep each gem's changelog between the versions for the class names above. Expected: none renamed or removed. Any hit is fixed in this task.
- [ ] **Step 6: The browser side.** Run `bin/rails tailwindcss:build`. Then fix `StaleNodeAtOnce` (above) and run one at a time: `stale_node_test.rb`, `shell_test.rb`, `save_bar_test.rb`, `admin/account_password_answer_test.rb`, `theme_toggle_test.rb`, `admin/presence_lists_test.rb`, `dialog_test.rb`. Then run `admin/rich_text_test.rb` three times. A failure of #207's test there is fixed in this task, with its cause. If it passes all three, the PR body says that it flaked once on #207 and was not reproduced. Then replace the `resize` calls, and run the 14 files: no deprecation warning is printed.
- [ ] **Step 7: Lint and the guards.** `bin/rubocop`, `bin/bundler-audit`, `bin/brakeman`, `bin/rails zeitwerk:check`, `bin/changelog-guard main`. Expected: all pass.
- [ ] **Step 8: Comments and commit.** Run the comment grep over the changed test files. Check `pgrep -f "rails test"`. Commit `chore(deps): view_component 4.23, solid_queue 1.7.2, opentelemetry 0.100, anthropic 2.5, cuprite 0.20, mcp 1.9 and the artifact actions`. The body lists each PR it supersedes and each fix with its cause.

---

### Task 1: One state chip for a system's state (Q5)

**Files:**
- Create `app/components/admin/ui/state_chip_component.rb`, with a test and a preview (`test/components/admin/ui/state_chip_component_test.rb`, `test/components/previews/admin/ui/state_chip_component_preview.rb`, examples `ok`, `warn`, `danger`, `off`).
- Modify `app/components/admin/settings_screen/mail_state_component.rb`: its dot-and-word line is a `StateChipComponent`. The tones are `TONES = { not_set_up: :off, untested: :warn, working: :ok, failed: :danger }`, with the words `admin.mail.states.<state>.word`. The sentence and the failure alert stay. `DOTS` goes.
- Modify `app/components/admin/settings_screen/ai_key_component.{rb,html.erb}`: the hand-built chip ("● Key saved · added 2 Oct" / "No key yet") is a `StateChipComponent` (`:ok` or `:off`), with `data-ai-key-state` kept on it.
- Modify `app/components/admin/settings_screen/ai_test_result_component.rb`, converted to keys whole (`admin.components.settings_screen.ai_test_result.connected` "Connected", `.not_connected` "Not connected", `.time` "%{milliseconds} ms"):
  - a success is `:ok` "Connected" with the detail "412 ms";
  - a failure is `:danger` "Not connected", with the provider's message under it in `text-danger-ink`, as today;
  - its `MONO_ALLOWED` entry goes, since the result is no longer mono capitals.
- Modify `app/components/admin/ui/system_check_row_component.{rb,html.erb}`: the chip is a `StateChipComponent` (`:ok` / `:warn`), and its two words become keys (`admin.components.ui.system_check_row.ok` "OK", `.warning` "Warning"). Nothing else of the row changes; it is 7b's.
- Modify `test/lib/admin_design_rules_test.rb`:
  - `STATUS_FILL_FILES` gains `app/components/admin/ui/state_chip_component.rb` and loses `mail_state_component.rb` and `system_check_row_component.rb` once they draw no fill. Each change carries its reason in the list's comment.
  - `MONO_ALLOWED` loses the AI result.
- Modify `test/support/design_system_entries.rb`: `NOT_YET["Admin::Ui::StateChipComponent"] = "no card yet: the design agent draws StateChip after stage 5c"`.
- Modify `test/support/ui_contract.rb`: `KEYBOARD_NOT_YET["Admin::Ui::StateChipComponent"] = "its keyboard test is the rail's, written with the rail"`. Task 4 removes it.
- Modify `test/lib/admin_i18n_test.rb`: `CONVERTED` gains `state_chip_component.rb` and `ai_test_result_component.rb`.
- Test: `test/components/admin/settings_screen/{ai_key,ai_test_result}_component_test.rb`, `test/components/admin/settings_screen/mail_card_component_test.rb`, `test/components/admin/ui/system_check_row_component_test.rb`, `test/integration/admin/system_status_test.rb` ("a status is a dot and a word, never colour alone"), `test/integration/admin/settings_mail_test.rb`, `test/integration/admin/ai_settings_test.rb`, `test/lib/admin_contrast_test.rb`.

**Interfaces:**
- Produces `Admin::Ui::StateChipComponent.new(tone:, label:, detail: nil, **html)`, with `TONES = %i[ok warn danger off]` (another tone raises). It draws `span.admin-state-chip[data-state-tone=<tone>]` holding an `aria-hidden` dot and the label, then " · detail" when `detail` is given. Its contract:
  - `states: %i[ok warn danger off]`, `keys: []`, `controller: nil`, `widths: :fluid`, `content_edges: %i[short long]`;
  - `limits:` "It cannot be pressed and takes no focus.", "It draws four tones; the word, never the colour, says the state.".

- [ ] **Step 1: Write the failing tests.**
  - `state_chip_component_test.rb`:
    - `test "each tone draws its dot and its word, the dot hidden from a screen reader"`;
    - `test "a detail follows the word after a middle dot"`;
    - `test "an unknown tone is refused"`;
    - `test "it takes no focus and has no role"`.
  - `admin_contrast_test.rb`: `test "a state chip's word is 4.5:1 and its dot 3:1 on its tint, and off's outline 3:1 on the surface and the rail, in both schemes"`.
  - `ai_test_result_component_test.rb`: "connected" asserts the chip's `ok` tone, "Connected" and "412 ms", and no `font-cs-mono`. The keys test stores a test string for `.connected` and asserts the chip reads it.
  - `mail_card_component_test.rb`: each of the four states draws the chip's tone and its word (`data-mail-state` kept).
- [ ] **Step 2: Run them, and verify they fail.** `PGGSSENCMODE=disable bin/rails test test/components/admin/ui/state_chip_component_test.rb test/components/admin/settings_screen test/lib/admin_contrast_test.rb`.
- [ ] **Step 3: Implement.** Search the tests by hand for `CONNECTED ·`, `font-cs-mono` near the AI result, `bg-ok` and `bg-warn` dots near `mail_state` and the system check, and `data-ai-key-state`, and fix each hit in this task.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/lib test/components/admin test/integration/admin/settings_mail_test.rb test/integration/admin/ai_settings_test.rb test/integration/admin/system_status_test.rb test/integration/setup_early_steps_test.rb`.
  - After a build, one at a time: `admin/ai_settings_test.rb`, `admin/settings_mail_test.rb`, `admin/system_status_and_preview_test.rb`, `setup_wizard_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep. Check `pgrep`. Commit `feat: one state chip draws a system's state on Settings, the wizard and System status` (body: `Advances #117`).

---

### Task 2: One list of sections, the nav and the card frame (Q1, Q12, Q16)

**Files:**
- Create `app/values/settings_sections.rb`, with `test/values/settings_sections_test.rb`.
- Create `app/components/admin/settings_screen/card_component.{rb,html.erb}`, with a test and a preview.
  - The head is on `--cs-rail` (`.admin-settings-card__head`), with the 22px `IconChipComponent` (`size: :small`), `h2.text-h2`, the intro in `text-small text-dim`, then `head_end` and `head_note`.
  - The card is `bg-surface shadow-1 rounded-card`, and the head's top corners take the card radius.
- Modify the seven cards (`site`, `languages`, `publishing`, `forms`, `ai`, `mail`, `images`): each renders its body inside `CardComponent`, keeping its `id`, `data-controller` and anchors. Only their heads change in this task.
- Modify `app/components/admin/settings_screen/nav_component.{rb,html.erb}`, converted to keys whole (`nav.label` "Settings sections"). It reads `SettingsSections`; each link has its section's chip before its word. The current link (`aria-current="true"`, written by `admin--settings--nav`, unchanged) is drawn on `--cs-accent-tint` with ink words at 600, in place of the 2px ink bar (`content-spiel.tailwind.css:452`).
- Modify `app/views/admin/settings/show.html.erb`, converted to keys whole (`admin.settings.show.*`: the title, the heading and `Save`, which Task 5 then replaces). Its header comment is rewritten without "cs-studio spec §6.1, handoff §4.5" and "decision D9".
- Create `config/locales/admin/settings.en.yml` (`admin.settings.show.*`), and move the `admin.settings.*` answers there from `settings_screen.en.yml`. Add `admin.components.settings_screen.sections.{site,languages,publishing,forms,ai,mail,images}` and `card.*` to `settings_screen.en.yml`.
- Modify `app/queries/jump/search.rb`: `SETTINGS_DESTINATIONS` goes. `settings_rows` maps `SettingsSections.for { |permission| AccessControl.holds?(actor, permission, channel: :admin) }` to rows titled `SETTINGS_TITLES.fetch(section.id)` (the seven, "Settings › Site" …).
- Modify `test/queries/jump/search_test.rb:48–63`: the order and the three new rows. Add `test "the Settings rows are SettingsSections', titled one each"`.
- Modify `test/lib/admin_design_rules_test.rb`: `TINT_PAIR_ALLOWED` is unchanged (ink words, not accent).
- Modify `test/lib/admin_i18n_test.rb`: `CONVERTED` gains `card_component.{rb,html.erb}`, `nav_component.{rb,html.erb}` and `app/views/admin/settings/show.html.erb`.
- Test: `test/components/admin/settings_screen/{card,nav}_component_test.rb`, `test/integration/admin/settings_test.rb`, `test/integration/admin/language_settings_test.rb`, `test/queries/jump/search_test.rb`, `test/system/admin/settings_test.rb`, `test/system/command_palette_test.rb`.

**Interfaces:**
- Produces `SettingsSections::Section` (`id`, `permission`, `family`, `icon`), with `SettingsSections::ALL`, `.for(&holds)`, `.ids` and `.find(id)` (which raises on an unknown id). The families and icons follow Q1 (b): site `structure`/`pages`, languages `text`/`translations`, publishing `lists`/`file_text`, forms `form`/`clipboard_list`, ai `code`/`assistant`, mail `media`/`at_sign`, images `media`/`image`.
- Produces `Admin::SettingsScreen::CardComponent.new(section:, intro: nil, **html)`, with the slots `head_end` and `head_note`. `NavComponent.new(sections:)` keeps its signature and takes `Section`s.

- [ ] **Step 1: Write the failing tests.**
  - `settings_sections_test.rb`:
    - `test "the seven sections in the nav's order, each with its right, family and icon"`;
    - `test "for keeps the sections whose right is held, and find raises on an unknown id"`;
    - `test "each family is an icon chip's and each icon is drawn by the icon partial"`.
  - `card_component_test.rb`:
    - `test "the card is a section named by its heading, whose id is the section's anchor"`;
    - `test "the head carries the section's chip, its title and its intro, then the head slots"`;
    - `test "the card has no border of its own and its head is the rail's ground"`.
  - `nav_component_test.rb`: `test "each link carries its section's chip before its word"`, and the keys test with a stored string.
  - `settings_test.rb` (integration): `test "every card is drawn by the card frame, in the nav's order, for the rights the viewer holds"`.
  - `settings_test.rb` (system), on `visit_screen admin_settings_path`: "the section in view is the nav's current one, in ink with the bar, and follows the scroll" becomes `test "the section in view is the nav's current one, on the accent tint, and follows the scroll"`. It asserts the computed background is `--cs-accent-tint` and the weight 600.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests by hand for "in ink with the bar", `inset 2px 0 0`, `text-h2 text-ink` inside `admin-settings-card`, `Settings › ` and `SETTINGS_DESTINATIONS`, and fix each hit in this task.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/values test/components/admin/settings_screen test/integration/admin/settings_test.rb test/integration/admin/language_settings_test.rb test/integration/admin/settings_forms_test.rb test/integration/admin/settings_images_test.rb test/queries/jump test/lib`, then `bin/rails zeitwerk:check`.
  - After a build, one at a time: `admin/settings_test.rb`, `command_palette_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: Settings' sections are one list; the nav and every card show the section's chip` (body: `Advances #117`).

---

### Task 3: The cards' bodies in keys, and their buttons (Q4, Q11)

**Files:**
- Modify `site_card_component.*`, `languages_card_component.*`, `publishing_card_component.*`, `ai_card_component.*` and `ai_key_component.*`, each converted to keys whole in its `settings_screen.en.yml` scope, with today's words.
- Modify the Languages card:
  - "Turn off…" is `:danger_text`, small. Its unseen spacer on the default's row takes the same variant, so the rows still line up.
  - "Make default…" and "Add language" stay `:secondary`.
  - "Default" stays the neutral `BadgeComponent` (Q4 b).
- Modify `ai_key_component.html.erb`: "Save key" is `:secondary`, and Cancel stays `:tertiary`. Modify `mail_login_component.html.erb`: "Save login" is `:secondary` (Q11 b).
- Modify `language_dialogs_component.*` if it is not converted yet: converted whole.
- Modify `test/lib/admin_i18n_test.rb`: `CONVERTED` gains every file converted here.
- Test: `test/components/admin/settings_screen/{site_card,languages_card,publishing_card,ai_card,ai_key,language_dialogs}_component_test.rb`, `test/integration/admin/{settings,language_settings,ai_settings,languages}_test.rb`, `test/system/admin/{settings,ai_settings,languages,settings_mail}_test.rb`.

- [ ] **Step 1: Write the failing tests.**
  - `languages_card_component_test.rb`:
    - `test "Turn off… is the danger text button, Make default… and Add language the secondary, and Default the neutral badge"`;
    - the keys test (a stored string for `languages_card.add`).
  - `ai_key_component_test.rb`: `test "Save key is secondary: the save bar is the screen's one primary"`.
  - `mail_card_component_test.rb`: the same for Save login.
  - Integration `settings_test.rb`: `test "the Settings screen draws one primary button, the save bar's"`. It counts every element whose `class` holds every class of `ButtonComponent.classes(:primary)` outside `dialog` elements and asserts one. Its first assertion runs the same matcher over a sample fragment with two primaries and asserts two, so a weakened matcher fails.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests for each card's English words in `assert_text` and `click_on` (they keep passing, since the words are unchanged) and for the old variants' classes, and fix each hit.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components/admin/settings_screen test/integration/admin test/lib`.
  - After a build, one at a time: `admin/settings_test.rb`, `admin/ai_settings_test.rb`, `admin/languages_test.rb`, `admin/settings_mail_test.rb`, `admin/settings_images_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: Settings' instant actions are secondary or danger text, and its cards speak in keys` (body: `Advances #117`).

---

### Task 4: "At a glance" and the Settings layout (Q6, Q7, Q8)

**Files:**
- Create `app/components/admin/settings_screen/glance_component.{rb,html.erb}`, with a test and a preview.
  - `aside.admin-settings-glance[aria-labelledby=settings-glance-heading]`, with `h2#settings-glance-heading` "At a glance".
  - One row per section the viewer's cards show among languages, ai, mail and images. Each row is `#settings-glance-<id>`: a link to `#<id>` (Q7 a) holding the section's chip, its word and its state (Q6).
  - Then the hint (`glance.hint`).
  - Its keys are `glance.{heading,hint,languages.count,languages.default,ai.off,ai.no_key,ai.key_saved,ai.connected,ai.failed,images.ready,images.waiting,images.failed,images.none}`, with `count` plurals. Mail's words are `admin.mail.states.*`.
- Modify `app/views/admin/settings/show.html.erb`:
  - The screen is `div.admin-settings-layout` (`container: admin-settings / inline-size`) holding the nav's column, the rail and the cards' column, in that document order.
  - The rail renders `GlanceComponent` with the progress and `MailSettings` the view already computes.
- Modify `app/assets/tailwind/content-spiel.tailwind.css`, after the lists' rail block. Add `.admin-settings-layout` and its one `@container admin-settings (min-width: 1200px)` block (Q8 a):
  - columns `170px minmax(0, var(--cs-form-max)) var(--cs-rail-width)`, with `--cs-rail-gap` between the nav, the column and the rail; spare width falls right of the rail;
  - `.admin-settings-glance` on `--cs-rail` with `--cs-shadow-2` and `--cs-radius-rail`, sticky as the lists' rail is;
  - below the threshold, a compact card (`--cs-surface`, `--cs-shadow-1`, card radius) above the first card;
  - the nav's own placement (beside the cards from `lg`) is unchanged.
- Modify `app/controllers/admin/settings_controller.rb`: `mail_test_streams` and `ai_test_result_stream` add the row's replace (see the decisions table).
- Modify `app/controllers/admin/ai_keys_controller.rb`, `mail_logins_controller.rb` and `app/controllers/concerns/admin/carried_base.rb`: a saved or removed key or login adds its row's replace.
- Modify `test/lib/admin_design_rules_test.rb`:
  - "the editors' rail, the dashboard's and the lists' dock at one threshold" becomes `test "the editors' rail, the dashboard's, the lists' and Settings' dock at one threshold"`;
  - a test `test "Settings' rail is laid out by the Settings area's own container, from the rail's tokens"`, shaped as the lists' rail test.
- Modify `test/support/ui_contract.rb`: the StateChip entry leaves `KEYBOARD_NOT_YET`, and `StateChipComponent`'s contract names `keyboard: ["test/system/admin/settings_test.rb", "the rail's states are words a keyboard passes over: each row is one link, and no chip takes the focus"]`.
- Modify `test/lib/admin_i18n_test.rb`: `CONVERTED` gains `glance_component.{rb,html.erb}`.
- Test: `test/components/admin/settings_screen/glance_component_test.rb` (new), `test/integration/admin/{settings,settings_mail,ai_settings}_test.rb`, `test/lib/admin_design_rules_test.rb`, `test/system/admin/{settings,ai_settings,settings_mail}_test.rb`.

**Interfaces:**
- Consumes `SettingsSections`, `StateChipComponent` and `CardComponent` (Tasks 1, 2).
- Produces `Admin::SettingsScreen::GlanceComponent.new(sections:, site_setting:, mail_settings:, images_progress:, ai_result: nil)` and `GlanceComponent.row_id(id) -> String`. It also produces `GlanceRowComponent.new(section:, …)` (the one row an answer replaces). The view and the streams draw the same row component.

- [ ] **Step 1: Write the failing tests.**
  - `glance_component_test.rb`:
    - `test "languages: the count and the default, with no state chip"`;
    - `test "AI translation: Off, No key, Key saved, then Connected or Not connected after a test"`;
    - `test "mail: the four states' words and tones from MailSettings"`;
    - `test "images: Ready, waiting, failed, both, and No images yet"`;
    - `test "each row is one link to its card's anchor"`;
    - `test "the rows are only the sections handed in"`.
  - Integration `settings_test.rb`:
    - `test "a viewer with languages.manage alone sees the languages row and no other state"` (Review Focus 3);
    - `test "the rail costs no statement of its own"`: `count_statements` with and without the rail are equal.
  - Integration `settings_mail_test.rb` and `ai_settings_test.rb`: `test "Test connection, Send test mail and a saved key update their rail row in the same answer"` (Review Focus 4). Each answer holds `turbo-stream[action=replace][target=settings-glance-<id>]` with the new word.
  - `admin_design_rules_test.rb`: the two tests above.
  - System `settings_test.rb`, on `visit_screen`:
    - `test "at 1600px the rail stands right of the cards, on the rail's ground, and stays in view down the page"`;
    - `test "at 1100px the rail is a card above the first card"`;
    - `test "the rail follows the Settings area's own width: a 1279px window docks it, a 1280px one does not"` (as the lists' tests, widths first);
    - `test "the rail's states are words a keyboard passes over: each row is one link, and no chip takes the focus"` (the Tab order: nav, rail rows, then the first card's first control);
    - `test "saving a mail field puts the rail's Mail row back to Saved, not tested"` (Review Focus 4: `with_mail_state(:working)`, change Server, Save).
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Check every `turbo_stream.replace` that names a Settings part, and that the row's id is drawn once.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components/admin/settings_screen test/integration/admin test/lib`, then `bin/rails zeitwerk:check`.
  - After a build, one at a time: `admin/settings_test.rb`, `admin/ai_settings_test.rb`, `admin/settings_mail_test.rb`, `admin/settings_images_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: Settings gets an At a glance rail with the state of languages, AI, mail and images` (body: `Advances #117`).

---

### Task 5: The save bar floats, names what changed and marks it (Q9, Q10)

**Files:**
- Create `app/javascript/saving/form_snapshot.js`, which holds `snapshot`'s key rules moved whole from the controller with their comment.
- Modify `app/javascript/controllers/admin/saving/save_bar_controller.js`:
  - `snapshot()` and `changes` call the module;
  - `refresh()` writes the count with the names (the `names` and `more` keys);
  - `refresh()` writes the mark (decisions table) and shows or hides the dot target;
  - the stuck observer and `data-stuck` go (Q9 d).
- Modify `app/components/admin/ui/save_bar_component.{rb,html.erb}`:
  - the default bar is `.admin-save-bar--floating`: on `--cs-popover`, `rounded-card`, `shadow-3`, padded `12px 16px`, sticky at `bottom: var(--cs-sp-3)`, in the form's column;
  - an 8px accent dot (target `dot`), the count, then Discard (`:tertiary`, still `data-save-bar-cancel`) and Save (default label `save_changes`, primary) at the right;
  - `contained: true` is unchanged;
  - the contract's `keys` gain `save_changes discard names more separator` and lose `cancel`;
  - `script_states` lose `stuck` and gain `named: ["test/system/save_bar_test.rb", "the bar names up to three changed fields and how many more"]` and `marked: ["test/system/save_bar_test.rb", "a changed field carries the mark, and loses it when typed back"]`.
- Modify `app/assets/tailwind/content-spiel.tailwind.css`:
  - `.admin-save-bar[data-stuck]` goes, and with it `--cs-shadow-stuck` in `content-spiel.css` (both schemes) if nothing else reads it;
  - `[data-save-bar-changed]`: a well inside it takes `box-shadow: inset 0 -2px 0 var(--cs-accent)`, and any other control's label or legend takes the 8px dot after it (Q10 b);
  - the invalid edge wins (Q10 i), so the rule stands before the invalid rule or under `:not(:has([aria-invalid="true"]))`.
- Modify `app/components/admin/settings_screen/values.rb`: `changed_names -> Array<Symbol>` (submitted and different from stored, for the fields the form posts). The cards write `data-save-bar-changed="saved"` on those wrappers in a re-render.
- Modify the Settings cards: `data-save-bar-name` on the controls with no plain label, with keys `settings_screen.<card>.names.*` (the language rows' "%{language}: Falls back to", `order` "Language order", `social` "Social links", `logo` "Logo").
- Modify `app/views/admin/settings/show.html.erb`, `groups/_form.html.erb`, `users/_form.html.erb`, `accounts/edit.html.erb` and `forms_screen/builder_component.html.erb`: they pass `save_label:` only where it is a screen's own word ("Save group", "Create group", "Change password"). Settings' "Save" goes, for the default.
- Modify `test/lib/admin_design_rules_test.rb`: `ACCENT_FILL_ALLOWED` gains `save_bar_component.html.erb` ("the save bar's unsaved dot, beside its words").
- Test: `test/components/admin/ui/save_bar_component_test.rb`, `test/components/admin/settings_screen/*_card_component_test.rb`, `test/integration/admin/settings_test.rb`, `test/lib/admin_contrast_test.rb`, `test/lib/admin_design_rules_test.rb`, `test/lib/script_messages_test.rb`, `test/lib/admin_i18n_test.rb`, `test/system/save_bar_test.rb`, `test/system/admin/{settings,groups_editor,users,account_password_answer,form_builder}_test.rb`.

**Interfaces:**
- Produces `form_snapshot.js`:
  - `snapshot(form) -> { values, controls }`;
  - `changedKeys(initial, now) -> String[]`;
  - `nameOf(control) -> String`, in this order: `data-save-bar-name`, then `label[for=id]` text without `.sr-only`, then the enclosing legend, then `aria-label`;
  - `NAMES_SHOWN = 3`.
- `SaveBarComponent.new(form_id:, cancel_url:, save_label: nil, save_data: {}, contained: false)` keeps its signature. The targets are `bar`, `count`, `save`, `blocked` and `dot`.
- `Values#changed_names`.

- [ ] **Step 1: Write the failing tests.**
  - `save_bar_component_test.rb`:
    - `test "the bar floats: the popover ground, the card radius, elevation 3, and Discard before Save changes"`;
    - `test "Discard keeps the marker that exempts it from the leave guard"` (from "Cancel carries the marker…");
    - `test "a screen's own Save label is kept"`.
    - "Save comes before Cancel" becomes `test "the count comes first, then Discard, then Save at the end"`.
  - `test/components/admin/settings_screen/values_test.rb` (new): `test "Values#changed_names lists what was typed and differs from the stored settings, and nothing on a plain load"` (Review Focus 1).
  - Integration `settings_test.rb`: `test "every control the Settings form submits has a name the bar can say"` (Review Focus 2). Parse the page and walk `#settings-form`'s named, non-hidden or `data-save-bar-track` controls that are not `data-save-bar-ignore`. Each has `label[for]`, a `legend` ancestor or `data-save-bar-name`.
  - `admin_contrast_test.rb`:
    - `test "the changed mark is 3:1 or better on the field's fill and on the card, in both schemes"` (floor 6.9 / 7.1 on `--cs-surface`);
    - `test "the floating bar's words and dot read on the popover ground"`.
  - System `save_bar_test.rb`:
    - `test "the bar names up to three changed fields and how many more"` (change five fields on Settings: "5 unsaved changes · Provider, Server, Port and 2 more");
    - `test "a changed field carries the mark, and loses it when typed back"`;
    - "a footer stuck over the fields draws a stronger top edge and an elevation, and at the end of the form neither" becomes `test "the bar floats over the fields and at the end of the form alike"`.
    - "Cancel" becomes "Discard" in every test of the file, and `click_link "Cancel"` within the bar becomes `click_link "Discard"`.
  - System `settings_test.rb`:
    - `test "after a refused save the typed fields that differ from the saved settings carry the mark and the bar names them"` (Review Focus 1: an invalid port with a changed server; the 422 shows both marked and named, and leaving asks);
    - "Back with a typed change asks first, and Cancel discards without asking" and "the footer's Cancel reloads the screen…" use Discard.
  - `groups_editor_test.rb`, `users_test.rb`, `account_password_answer_test.rb` and `form_builder_test.rb`: their bar's words, if a test reads "Cancel" or the stuck edge.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search `app/` and `test/` by hand for `data-stuck`, `shadow-stuck`, `stuckObserver`, `"Cancel"` near `.admin-save-bar`, `save_bar.cancel` and `save_label: "Save"`, and fix each hit in this task.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components/admin test/integration/admin test/lib`.
  - After a build, one at a time: `save_bar_test.rb`, `admin/settings_test.rb`, `admin/groups_editor_test.rb`, `admin/users_test.rb`, `admin/account_password_answer_test.rb`, `admin/form_builder_test.rb`, `admin/groups_members_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: the save bar floats, names what changed and marks each changed field` (body: `Advances #117`).

---

### Task 6: The wizard: progress, steps, one primary per step, its words in keys (Q2, Q3, Q13, Q14)

**Files:**
- Modify `app/views/layouts/setup.html.erb`, converted to keys whole (`setup.layout.*`: `title`, `first_run`, `steps_label`, `done`, `optional`, `progress`):
  - the header keeps the wordmark (its `UPPER_TRACKED_ALLOWED` entry) and says "First-run setup" in sans 13px meta;
  - the body is `max-w-[980px]`, a 250px column and the card, 28px apart;
  - the column (`setup/_steps.html.erb`) is on the page itself: the progress line and its 6px bar (accent on `--cs-field-fill`, `rounded-full`), then the steps;
  - a step is 22px numbered circles: current is `bg-accent text-on-accent` on an `--cs-accent-tint` row with ink words at 600; done is `bg-live text-on-live` with "✓" and "Done: " for a screen reader; the rest are on `--cs-field-fill` in dim;
  - "Optional" is the meta word (Q13 b);
  - the card is `bg-surface rounded-rail shadow-2 p-11` (as drawn), holding the insecure notice, the flash and the step.
- Create `app/views/setup/_steps.html.erb`.
- Modify `app/helpers/setup_helper.rb`: `setup_progress(step)`. `setup_step_done?` stays.
- Modify `app/controllers/setup_controller.rb`: `LABELS` goes, and `step_label` reads `setup.steps.<step>`. The comments lose "design spec 2026-09-26 §3-§4", "spec §7.1" and "Final fix wave (Important 3)".
- Modify `app/views/setup/{token,system_check,admin,site,languages,mcp_token,mcp_token_created,starter_content,review}.html.erb`, `_back.html.erb` and `_flash.html.erb`, each converted to keys whole (`setup.<step>.*`). The action row follows Q14 (a):
  - on `token`, the welcome line (Q2 b: ink 600 with a `structure` chip, `setup.token.welcome`), the heading "Let's set up your site" and the drawn intro, then Continue and "Where do I find the log?" (Q3 a: a `details` under the field, `setup.token.log.*`);
  - Back is `ButtonComponent.classes(:tertiary)`;
  - Skip is `:tertiary`;
  - "Re-run checks" is the system check's secondary, at the row's start.
- Create `config/locales/setup.en.yml`. A test asserts that `setup.steps` holds exactly `SetupController::STEPS`.
- Modify `test/lib/admin_design_rules_test.rb`:
  - `ACCENT_FILL_ALLOWED` gains `app/views/setup/_steps.html.erb` ("the wizard's progress bar and the current step's number");
  - `LIVE_SCHEDULED_FILES` gains it too ("a done step's check, the spec's green at 5.4 / 8.3:1");
  - the guard's test name and its comment say so.
- Modify `test/lib/admin_i18n_test.rb`: `CONVERTED` gains the layout, `_steps`, the eleven views and partials, and `setup_controller.rb`.
- Test: `test/helpers/setup_helper_test.rb` (new), `test/integration/setup_{access,early_steps,optional_steps,site_steps,finish,redirect}_test.rb`, `test/lib/admin_contrast_test.rb`, `test/lib/admin_design_rules_test.rb`, `test/lib/admin_i18n_test.rb`, `test/system/setup_wizard_test.rb`.

**Interfaces:**
- Produces `SetupHelper#setup_progress(step) -> { number: Integer, total: Integer, fraction: Float }`. It is read by `_steps`, and by Task 7's Mail step through the layout.

- [ ] **Step 1: Write the failing tests.**
  - `setup_helper_test.rb` (new): `test "setup_progress is the step's place in nine, as a fraction rounded to two places"` (`token` → 1, 9, 0.11; `mail` → 5, 9, 0.56; `review` → 9, 9, 1.0).
  - Integration `setup_early_steps_test.rb`:
    - `test "the token step welcomes, says Step 1 of 9 and has one primary"`;
    - `test "a step names itself current, the earlier ones done, and Optional in words"`;
    - `test "setup.steps holds exactly the steps"`.
  - Integration `setup_optional_steps_test.rb`: `test "every step draws one primary, its Back and Skip tertiary"`. It counts `ButtonComponent.classes(:primary)` on each step's page, with the matcher checked on a sample first.
  - `admin_contrast_test.rb`:
    - `test "the wizard's progress fill is 3:1 or better against its track, in both schemes"` (floor 6.9 / 7.1);
    - `test "the current step's words are 4.5:1 on the accent tint and its number on the accent"`.
  - System `setup_wizard_test.rb`: "a fresh install goes from the token to a live homepage" reads the new words, and the step list's "Optional" is no longer "OPTIONAL". Add `test "Where do I find the log? opens the commands under the field and keeps the focus"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests by hand for `OPTIONAL`, "optional" in the step list, `Setup token` as a heading, `"Back"` links, `LABELS` and "Enter your setup token", and fix each hit in this task.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/helpers test/integration/setup_*_test.rb test/lib`.
  - After a build: `setup_wizard_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: the setup wizard in E4: a progress bar, the steps as chips, one primary per step, and a welcome` (body: `Advances #117`).

---

### Task 7: One Mail form on Settings and in the wizard (Q14, Q15)

**Files:**
- Create `app/components/admin/settings_screen/host_value_component.rb`: a field the host sets, as the sunken box with "Set by the host". A login half takes `MailLoginComponent::MASK` and never reads its value. It replaces the card's three copies and the wizard's `host_box` lambda.
- Create `app/components/admin/settings_screen/mail_fields_component.{rb,html.erb}`, with a test and a preview:
  - two groups, Server (a `media` chip: server, port, security, then the `login` slot) and Sender (a `text` chip: sender name, sender address), each `rounded-tile` on `--cs-paper`, padded 14px, with its heading at 600;
  - the security control is the one segmented control, its radios carrying `data-port` and `data-action="change->mail-port#security"`, and Port carries `data-mail-port-target="port"`.
- Modify `mail_card_component.{rb,html.erb}`: its fields are `MailFieldsComponent` (`name_prefix: "site_setting"`, `id_prefix: "settings-"`), with `MailLoginComponent` in the `login` slot, and the root gains `mail-port` in `data-controller`. The ids `settings-mail_*` are kept.
- Modify `app/views/setup/mail.html.erb`, converted to keys whole (`setup.mail.*`):
  - its fields are `MailFieldsComponent` (`id_prefix: "setup-"`), with the two inline login fields in the slot;
  - the row is one row per Q14 (a): Send test mail (secondary) with "Sends to <address> (your address)", then Back, Skip for now and Continue, Continue last;
  - the hidden first "Continue" stays first in the form;
  - the outcome stays under the row.
- Create `app/javascript/controllers/mail_port_controller.js` (`mail-port`), with the rule and comment of the two it replaces.
- Delete `app/javascript/controllers/setup_mail_controller.js`.
- Modify `app/javascript/controllers/admin/settings/mail_controller.js`: `security`, the `port` target and `PORTS` go, and its header says the port is `mail-port`'s.
- Modify `test/lib/mail_guards_test.rb`: `COLUMN_NAMERS` gains `mail_fields_component.*` and `host_value_component.rb`, and loses any file that no longer names a column, each with its reason.
- Modify `test/lib/admin_i18n_test.rb`: `CONVERTED` gains the two new components and `app/views/setup/mail.html.erb`. Modify `test/lib/source_layout_test.rb` only if it lists top-level controllers by name.
- Test: `test/components/admin/settings_screen/{mail_fields,host_value,mail_card}_component_test.rb`, `test/integration/setup_mail_step_test.rb`, `test/integration/admin/settings_mail_test.rb`, `test/lib/mail_guards_test.rb`, `test/system/setup_wizard_test.rb`, `test/system/admin/settings_mail_test.rb`.

**Interfaces:**
- Produces:
  - `Admin::SettingsScreen::MailFieldsComponent.new(mail_settings:, value:, name_prefix:, id_prefix:, errors: nil)`, where `value` is a callable `(field) -> String` and the slot is `login`;
  - `Admin::SettingsScreen::HostValueComponent.new(field:, label:, mail_settings:)`;
  - Stimulus `mail-port`: target `port`, action `security`.

- [ ] **Step 1: Write the failing tests.**
  - `mail_fields_component_test.rb`:
    - `test "two groups: Server holds server, port, security and the login slot; Sender holds the name and the address"`;
    - `test "a field the host sets is the sunken box with Set by the host, and a login half shows the mask and never its value"`;
    - `test "the security radios carry their port and mail-port's action"`.
  - `setup_mail_step_test.rb`: the two host-secret tests keep their assertions, and `test "the step draws the shared Mail fields: the same groups and controls as Settings"`.
  - System `setup_wizard_test.rb`:
    - "the Mail step's security switch sets the port unless another port was typed" keeps its assertions;
    - `test "Enter in a Mail field continues and sends no mail, whatever the row's order"` (Review Focus 5).
  - System `settings_mail_test.rb`: `test "the Mail card's security switch sets the port unless another port was typed"`, moved there from what `admin--settings--mail` held, if no test held it.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search `app/` and `test/` by hand for `setup-mail`, `setup_mail_controller`, `admin--settings--mail-target="port"`, `#security` and `host_box`, and fix each hit in this task. A test that asserts a controller's absence by a fragment of its name is searched for too (CLAUDE.md).
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components/admin/settings_screen test/integration/setup_mail_step_test.rb test/integration/admin/settings_mail_test.rb test/lib`, then `bin/rails zeitwerk:check`.
  - After a build, one at a time: `setup_wizard_test.rb`, `admin/settings_mail_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `ref: Settings' Mail card and the wizard's Mail step draw one Mail form with one port rule` (body: `Advances #117`).

---

### Task 8: The reference, CLAUDE.md, the pull request and the Design System cards

**Files:**
- Modify `docs/reference/settings-languages-ai.md`, "Settings":
  - `SettingsSections`;
  - the card frame;
  - the nav's chips and current look;
  - the layout, its container and threshold;
  - "At a glance": its rows, the streams that redraw them, and that it is a component and no query;
  - the buttons' variants;
  - the "Describes" line gains the new files.
- Modify `docs/reference/mail.md`: "Settings → Mail" and "The setup wizard's Mail step" name `MailFieldsComponent`, `HostValueComponent` and `mail-port`, and the two groups.
- Modify `docs/reference/save-rule-and-write-queue.md`, "The save rule" and "How the footer counts": the floating bar, Discard, the names (`form_snapshot.js`, `nameOf`'s order, `data-save-bar-name`), the mark and its one writer, and the server's mark after a refused save.
- Modify `docs/reference/design-system.md`:
  - a part "E4: Settings and the wizard": the card frame, the rail, the state chip, the floating bar and the mark, the wizard's progress and step list;
  - "Form placement": the bar floats, and the stuck state is gone;
  - the tokens part: `--cs-shadow-stuck` goes, if Task 5 removed it;
  - "Rules a change can break silently" gains:
    - the changed mark has one writer in the browser (`admin--saving--save-bar`), and **no guard** for a second script that writes it;
    - a system's state is `StateChipComponent`, and **no guard** for a screen that draws its own dot and word;
    - a Settings section is `SettingsSections`, and **no guard** for a card drawn outside `CardComponent`.
- Modify `docs/reference/i18n.md`: the Files table gains `config/locales/setup.en.yml` (`setup.*`) and `config/locales/admin/settings.en.yml`.
- Modify `CLAUDE.md`:
  - the Settings index line names `app/values/settings_sections.rb` and the glance component;
  - the mail index line names `mail_fields_component.rb` and `mail_port_controller.js` in place of `setup_mail_controller.js`;
  - "Where a script goes" lists the top level's `mail_port` in place of `setup_mail`;
  - the design-system line names `Admin::Ui::StateChipComponent`.
- Modify `CHANGELOG.md`, `## Unreleased`, Changed:
  - Settings shows each section's icon, a panel "At a glance" with the state of languages, AI translation, mail and images, and a save bar that floats at the foot and names what changed.
  - The setup wizard shows how far along it is, marks the current and finished steps, and opens with a welcome.
  - ⌘K offers every section of Settings (Q16).
- Modify `test/support/design_system_entries.rb`: after the design agent's change, `VERSION`, `ENTRIES` and `NOT_YET` follow it by hand (StateChip's card leaves `NOT_YET`).
- Test: `PGGSSENCMODE=disable bin/rails test test/lib`, `bin/rubocop`, `bin/rails zeitwerk:check`, `bin/brakeman`, `bin/changelog-guard main`.

- [ ] **Step 1: Write the reference, CLAUDE.md and CHANGELOG changes.**
- [ ] **Step 2: Run** the five checks. Expected: all pass.
- [ ] **Step 3: Write the PR body.**
  - "Supersedes #204–#211", with Task 0's table: each PR, what failed and why, and the gems that moved.
  - Findings: Advances #117.
  - "For the owner to check": every design answer that differed from the drawing (Q1, Q2, Q4, Q5, Q6, Q9, Q13, Q14), the threshold (Q8), and ⌘K's three new rows (Q16).
  - Documentation, in `/Users/dknafelj/src/contentspiel-docs`: the Settings pages (Site, Languages, AI translation, Mail, Images), "First-time setup", and the screenshots of Settings and of the wizard's steps, retaken in both themes and Settings at 1600px.
- [ ] **Step 4: The Design System cards to redraw**, for the design agent:
  - `StudioCalmE4Setup`: from "Decided, not built" to built. Its E4 drawings follow the answers: no "time left", the families of Q1, the Default badge, the state chips, the action rows.
  - `SaveBar`: the floating bar and the changed mark built. Its "Decided, not built" lines go; the stuck state goes; its Interface names `form_snapshot.js`, the `dot` target and the keys.
  - `PatternSaving`: the bar's look and the mark.
  - **New `StateChip`**: tones, words, where it is drawn, and its keyboard test.
  - `FieldFrame` and `TextFields`: the changed state beside the invalid one.
  - `StudioRail`: "When to use / not" names Settings' "At a glance" as a rail of its own.
  - `FoundationLayout`: Settings' area and its threshold.
  - `IconChip`: only if Q1 adds a family.
- [ ] **Step 5: Check no test run is left**: `pgrep -f "rails test"` prints nothing.
- [ ] **Step 6: Commit** `docs: E4 stage 5c in the reference and CLAUDE.md` (body: `Advances #117`).

---

## Architecture-review findings

Checked on 2026-11-08 against every open issue labelled `architecture-review` (`gh issue list --label architecture-review`).

| Issue | Taken | Why |
|---|---|---|
| #117 comments about invariants | advances, every task | the Settings and setup files carry "cs-studio spec §6.1", "handoff §4.5", "decision D9", "final review 1", "plan Ruling P2", "Final fix wave (Important 3)", "ledger C-I1"; each task rewrites the comments of the files it touches |
| #132 split the largest scripts and controllers | not taken | its remaining parts (`hold_controller.js`, `table_controller.js`, the rich-text editor controller, the posts and pages controllers) are not 5c's files. `save_bar_controller.js` (560 lines) gives its snapshot to `saving/form_snapshot.js` rather than grow (Task 5) |
| #133 entry cost of a system test | not taken | its remainder (shorter names) is not in these files; the rewritten tests begin on `visit_screen` |
| #127 slots fit one shape | not taken | "At a glance" reads core states only, and no outside contributor exists; #127 adds a shape when its first user appears |
| #142 a new site's one language | not taken | the spec: a decision E4 does not take. 5c restyles the languages step's view, not `site_settings.locales`' default or the step's `Locales::Configure` |
| #138 every environment variable in one place | not taken | the Mail fields read `MailSettings#from_host?` as before; no variable is added or read |
| #119 the reference docs' structure | not taken | paragraphs of four reference files change, not their structure |
| #112, #114, #116, #121, #122, #124, #128–#131, #135–#137, #140, #141, #143, #185 | not taken | no task changes their code |

## Browser tests

Run locally after `bin/rails tailwindcss:build`, one file at a time, only while the one-minute load is under 6, each prefixed with `PGGSSENCMODE=disable`.

**The implementer must run:**
- Task 0: `stale_node_test`, `shell_test`, `save_bar_test`, `admin/account_password_answer_test`, `theme_toggle_test`, `admin/presence_lists_test`, `dialog_test`, `admin/rich_text_test` (three times), and the 14 files whose `resize` changes;
- Task 1: `admin/ai_settings_test`, `admin/settings_mail_test`, `admin/system_status_and_preview_test`, `setup_wizard_test`;
- Task 2: `admin/settings_test`, `command_palette_test`;
- Task 3: `admin/settings_test`, `admin/ai_settings_test`, `admin/languages_test`, `admin/settings_mail_test`, `admin/settings_images_test`;
- Task 4: `admin/settings_test`, `admin/ai_settings_test`, `admin/settings_mail_test`, `admin/settings_images_test`;
- Task 5: `save_bar_test`, `admin/settings_test`, `admin/groups_editor_test`, `admin/groups_members_test`, `admin/users_test`, `admin/account_password_answer_test`, `admin/form_builder_test`;
- Tasks 6 and 7: `setup_wizard_test`, plus `admin/settings_mail_test` in Task 7.

**Likely to change, left to CI** (the whole browser suite runs per PR):
- `theme_toggle_test` (Settings and the wizard in dark);
- `view_only_test` (a viewer without `settings.manage`);
- `invites_test` and `password_reset_test` (mail's state words);
- `admin/translations_test` (languages turned on from Settings);
- every file Task 0 touched for `resize`.

A CI failure is fixed in the task that owns the file.

## Pre-flight

Done while writing this plan.

- **Red mid-stack.**
  - Task 0 fixes, in itself, the three failures its bumps bring (the preview fixture, the stale-node prepend and the resize calls) and the sequence flake that blocked #205.
  - Task 1 changes the AI result's words from "● CONNECTED · 412 MS" to "Connected · 412 ms", and fixes every test that reads them.
  - Task 2 changes ⌘K's order and fixes `search_test.rb:48–63` and `command_palette_test.rb:156`.
  - Task 5 changes "Cancel" to "Discard" in every save bar, and fixes `save_bar_test.rb` and the four screens' tests that read it.
  - Task 6 changes "OPTIONAL" and the token step's heading.
  - Task 7 deletes `setup-mail`, and searches for its name and fragments by hand.
- **A file changed in two tasks.**
  - The seven cards' heads change in Task 2, their bodies in Task 3; the Mail card's fields in Task 7 and its names in Task 5, each a different part.
  - `show.html.erb` is converted in Task 2 and laid out in Task 4. Task 5 only drops its `save_label:`.
  - `settings_controller.rb`'s streams change in Task 4 only.
  - `ai_key_component.*` gets its chip in Task 1, and its keys and Save key's variant in Task 3. Task 1 converts nothing of it but the chip's words, which come in as `label:`.
  - `mail_login_component.html.erb`'s variant changes in Task 3, and its names in Task 5.
- **Keys before their reader.**
  - `sections.*` arrives with the nav and the frame (Task 2), and `glance.*` with the rail (Task 4).
  - `save_bar.save_changes`, `discard`, `names`, `more` and `separator` arrive in Task 5, and `save_bar.cancel` is deleted there once Discard reads `discard`.
  - `setup.*` arrives in Task 6, and `setup.mail.*` in Task 7.
- **Guard lists.**
  - `STATUS_FILL_FILES` gains one file and loses two (Task 1).
  - `ACCENT_FILL_ALLOWED` gains the bar's dot (Task 5) and the steps (Task 6). `LIVE_SCHEDULED_FILES` gains the steps (Task 6).
  - `MONO_ALLOWED` loses the AI result (Task 1).
  - `KEYBOARD_NOT_YET` gains StateChip in Task 1 and loses it in Task 4. `NOT_YET` gains StateChip in Task 1 and loses it in Task 8, with the design agent's card.
  - `CONVERTED` grows in Tasks 1 to 7, each with its own files.
  - `COLUMN_NAMERS` changes in Task 7.
  - Each list's "still used" test catches an allowance left behind.
- **Tests a mutation would not fail.**
  - The "one primary" tests (Tasks 3 and 6) run their matcher over a sample with a known count first.
  - The keys tests store a test string.
  - The rail's statement test compares with and without the rail.
  - The threshold tests check the widths first.
  - The refused-save test needs the server's mark: without it, the 422 shows no mark.
  - The names test walks the real form, so a new unnamed control fails it.
- **Not reproduced while planning.** No test database exists in this worktree, so the #206 diagnosis rests on ViewComponent's diff (`render_preview` now `process(:previews)`) and Active Storage's `after_commit` upload, not on a run. Task 0 Step 1 runs it first.
- **History comments.** Every task ends on the grep in "Comment rule".
