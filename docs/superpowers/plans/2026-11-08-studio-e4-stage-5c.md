# CS Studio in E4, Stage 5c (Settings and the setup wizard) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Settings and the setup wizard take E4, as drawn on `StudioCalmE4Setup`. On Settings, each card is raised with its section's icon chip in a cool head, and the nav repeats the chips. The save bar is the screen's one primary area: it floats at the foot of the column and names what changed ("2 unsaved changes · Provider, Server"), and a changed field carries a violet edge. An "At a glance" rail shows the state of languages, AI, mail and images. In the wizard each step has one primary (Continue); Back and Skip for now are text buttons, and "Optional" is a word. The current step is violet on its tint and a done step has a check in the ok tone. A progress bar, static per step, stands above the steps, and the first step opens with a welcome line. There is no "time left". Before any of it, the eight open Dependabot updates land (Task 0).

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

The drawing is `StudioCalmE4Setup` in the Design System artifact (https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT, read at version 1794108449-0fdc; the answers and the new cards `StudioSettings`, `StudioWizard` and `StateChip` at 1794162664-ed4a, v114). It draws Settings at 1900px, the wizard's first step and its Mail step at 1440px, each in light and dark. Its sibling cards `SaveBar` ("Decided, not built (E4 stage 5c)": the floating bar and the changed-field edge) and `StudioRail` were read too.

**One pull request** on branch `studio-e4-5c`, made from `main` at 6cb49c02, targeting `main`. Task 0 comes first, and its body says "Supersedes #204–#211". Dependabot closes those eight itself once `main` has the versions. The design answers are in (below).

---

## Design answers

Binding. Design System v113/v114, artifact version `1794162664-ed4a`. The source is `.superpowers/sdd/2026-11-08-studio-e4-stage-5c/design-answers-5c.md`, which an implementer reads beside their task. All sixteen follow the recommendations.

The new cards are `StudioSettings`, `StudioWizard` and `StateChip`, all "Designed, not built, stage 5c". `SaveBar` and `Alerts` are updated.

**Scope (Q5, Q9, Q10).** The state chip, the floating save bar and the changed-field mark reach Groups, Users, Your account, the form builder and System status through the shared components only. Those screens' own cards wait for 7a and 7b.

1. **Section chips** (family / icon): Site `structure`/`pages`, Languages `text`/`translations`, Publishing `lists`/`file_text`, Forms `form`/`clipboard_list`, AI translation `code`/`assistant`, Mail `media`/`at_sign`, Images `media`/`image`. There is no accent family.
2. **Welcome**, on the token step only: a 22px `structure` chip, then "Welcome to Content·Spiel" in ink, `text-sm` at 600, above "Let's set up your site".
3. **Where the log is**: a native `<details>` under the field.
   - The summary is "Where do I find the log?", a tertiary-looking line.
   - The body: "The setup token is printed in the server's log when CS Studio starts.", "In development: the terminal running `bin/dev`.", "With Docker Compose: `docker compose logs web`.", "With Kamal: `kamal app logs`.", "With the contentspiel command: `contentspiel logs`.", with each command in mono.
   - Keys: `setup.token.log.{summary,intro,development,compose,kamal,contentspiel}`.
4. **"Default"** is the neutral `BadgeComponent`.
5. **`Admin::Ui::StateChipComponent.new(tone:, label:, detail: nil)`**, with the tones `ok warn danger off`.
   - Every tone: `rounded-cs`, `px-2 py-0.5`, `text-label` 12px at 500, and a 6px dot.
   - ok: `ok-tint` ground, `ok` dot, `ok-ink` word.
   - warn: `warn-tint`, `warn`, `warn-ink`.
   - danger: `danger-tint`, `danger`, `danger-ink`.
   - off: no ground, a 1px `field-line` edge, a hollow ring and the word in `dim`.
6. **Rail rows** (nothing is stored):
   - Languages: "3 languages" with "English is the default" under it, and no chip.
   - AI: off "Off", warn "No key", ok "Key saved". After a Test connection on this visit: ok "Connected" or danger "Not connected".
   - Mail: off "Not set up", warn "Saved, not tested", ok "Working", danger "Last send failed".
   - Images: ok "Ready", warn "12 waiting", danger "2 failed", off "No images yet".
7. **Rail rows are links**: same-page links to `#languages`, `#ai`, `#mail` and `#images`, exempt from the leave guard. The hint stays, in `text-small` meta.
8. **Docking**: at 1200px of the Settings area's own width. Between 1200 and 1346px the column narrows from 760 to about 614px.
   - Docked, the rail is sticky at `top: calc(var(--admin-top-offset) + var(--cs-sp-4))`, on `--cs-rail` with `shadow-2` and `rounded-rail`.
   - Below 1200px it is a compact card, first after the nav.
9. **Floating save bar**, on every bar that is not contained:
   - `--cs-popover`, `rounded-card`, `shadow-3`, padding 12px 16px, an 8px accent dot; the stuck state goes.
   - "Discard" (tertiary), and "Save changes" unless the screen passes its own label ("Save group" and "Create group" stay).
   - `save_bar.names` "%{changes} · %{names}"; at most 3 names, then `save_bar.more` "%{names} and %{count} more"; `save_bar.separator` ", ".
   - With nothing to save: Save is disabled, "No unsaved changes" in meta, and the dot is hidden.
   - After a 422 or 409, Settings names the fields; other screens say "Unsaved changes".
   - Extra names: "Deutsch: Falls back to", "Language order", "Social links", "Logo".
10. **Changed mark**, on every screen with the floating bar:
    - a well: `box-shadow: inset 0 -2px 0 var(--cs-accent)`;
    - a control that is not a well (the segmented control, a checkbox, the language order, the social rows, the logo): an 8px accent dot after its label or legend;
    - **if the field is also invalid, the invalid edge wins alone.**
11. **Buttons**:
    - secondary: Make default…, Add language, Replace, Test connection, Send test mail, Save key, Save login;
    - danger text: Turn off…, Remove…;
    - the only primary is the bar's.
12. **Card head**: on `--cs-rail` with a 22px chip; heading `text-h2` (20px at 600); intro `text-small` dim; the Site card's language tabs stay in the head.
13. **"Optional"**: the meta word (`text-label` meta), in the step list and beside the step's heading alike.
14. **Action row**:
    - the step's own secondary first, then Back and Skip for now (tertiary), then the primary last;
    - an advancing action is the step's primary: "Generate token", "Add starter content", "Finish setup";
    - keep "Sends to <address> (your address)" in `text-small` meta.
15. **One Mail form**: Server (`media` chip: server, port, security, login) and Sender (`text` chip: name, address). Each group is on `--cs-paper`, `rounded-tile`, `p-3`, with a `text-label` meta heading.
16. **⌘K**: all seven sections, in the nav's order, each under its permission.

From the `StudioWizard` card (v114), on the same footing:
- the progress bar is 4px, `rounded-full`, on a `--cs-sunken` track with an accent fill at `fraction`;
- "Step 1 of 9" follows it, in `text-small` meta.

The card draws no current or done step mark. Task 6 draws the current step as the drawing does. It draws the done step in the ok tone (ruling P5), which is open for the design agent to confirm.

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
- **The component contract.** A new or changed shared component (`app/components/admin/ui/`) declares `Admin::Ui::Contract` (`app/components/component_contract.rb`, `app/components/admin/ui/contract.rb`). It has a component test, a preview example per previewable state, and a Design System entry, or a `DesignSystemEntries::NOT_YET` reason. A new one names its keyboard browser test, or stands in `UiContract::KEYBOARD_NOT_YET` until the task that writes it. `StateChipComponent` is new; `SaveBarComponent` and `SystemCheckRowComponent` change.
- **Buttons are the shared button.**
  - One primary per area: Settings' is the bar's Save changes, and a dialog's is its confirm. In the wizard it is the step's Continue or the step's own advancing action.
  - Back, Skip for now and Discard are `:tertiary`; "Where do I find the log?" is a native disclosure whose summary looks tertiary (Q3). Turn off… and Remove… are `:danger_text`.
  - A new accent fill or tint pair that is no button goes into `ACCENT_FILL_ALLOWED` or `TINT_PAIR_ALLOWED` with its reason, in the task that draws it.
- **The rail** (spec rule 5) docks by the Settings area's own container, never a window `@media`. It comes first in the document after the nav at every width, so the focus order is the document's and nothing is moved by script.
- **Layers.** No raw z-index. The floating bar keeps `--cs-z-sticky`.
- **Contrast is measured** (`test/lib/admin_contrast_test.rb`) in both schemes. The spec's figures are floors: the changed-field edge is 6.9 / 7.1:1 on the card, and the current step's violet on its tint 5.7 / 6.3:1. The progress fill's 6.9 / 7.1:1 is the accent on white; against the card's `--cs-sunken` track the test asks 3:1, a graphic's floor.
- **Comment rule (#117).** A comment states a current invariant, a hazard or a reason. It never states a plan step, a review round, "spec §", "handoff §", "decision D9", "ruling P2", "final review 1", "Final fix wave (Important 3)" or what used to be there. The Settings and setup files are full of these. Every task rewrites the comments of the files it changes. Its last step before its commit runs the grep below over the lines the task added (`git diff -U0 main... -- <files> | grep '^+'`, P28), and it prints nothing:

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

1. **After a refused or stale save.** A 422 or 409 re-renders Settings with the typed values, and the browser's baseline is then those values, so its own comparison finds nothing changed. The bar must still say which fields are unsaved, mark them, and keep the leave guard. A field that is both invalid and changed shows its invalid edge alone (Q10). Task 5:
   - `test "after a refused save the typed fields that differ from the saved settings carry the mark and the bar names them"` (browser): Server marked and named; Port, invalid, shows its invalid edge only and is named;
   - `test "Values#changed_fields lists the wrappers whose typed value differs from the stored settings, per language and per row, and nothing on a plain load"` (component).
2. **A control with no plain label.** These are the language rows' fallback selects (whose label is "Falls back to" plus a hidden " for Deutsch"), the social link rows (`aria-label` "Network" or "URL" on every row), the hidden language order, the logo's drop zone and the segmented controls (a legend). Each must give the bar a name a person can read. Task 5: `test "every control the Settings form submits has a name the bar can say"` (integration: every named, non-ignored control of `#settings-form` has a `data-save-bar-name` on itself or its wrapper, a legend or `label[for]`), and `test "a segmented control is named by its legend"` (browser).
3. **A viewer with only `languages.manage`.** They see the Languages card alone. The rail must not tell them whether mail works, whether an AI key is saved or how many images failed. Task 4: `test "a viewer with languages.manage alone sees the languages row and no other state"`.
4. **The rail after an instant action.** Test connection, Send test mail, a saved or removed AI key and a saved mail login each answer with streams that replace their own card's part. The rail's row must follow in the same answer, and a mail field saved through the bar makes mail "Saved, not tested" again (a new fingerprint). Task 4: `test "Test connection, Send test mail and a saved key update their rail row in the same answer"` (integration) and `test "saving a mail field puts the rail's Mail row back to Saved, not tested"` (browser).
5. **Enter on the Mail step.** Continue moves to the end of the one row, after Send test mail. Enter in a field must still mean Continue, never "send a mail". Task 7: `test "Enter in a Mail field continues and sends no mail, whatever the row's order"` (browser).

---

## Decisions the spec left open (not looks)

| Question | Decision | Why |
|---|---|---|
| Where the section list lives | `SettingsSections` in `app/values/settings_sections.rb`. `Section = Data.define(:id, :permission, :family, :icon)`; `ALL` in the nav's order; `.for(&holds) -> Array<Section>`; `.ids -> Array<String>`. Each section's words are `admin.components.settings_screen.sections.<id>`, read by full key by the nav, the card frame and the rail. | The nav and ⌘K hold two lists of the same sections today. A value is below both the components and `Jump::Search`. |
| ⌘K's titles | `Jump::Search` builds its Settings rows from `SettingsSections.for` and keeps its English titles in `SETTINGS_TITLES` (a Hash keyed by the section ids), because it matches what a person types against them and is not converted. A test asserts `SETTINGS_TITLES.keys == SettingsSections.ids`. | A query may not read a component, and its words are not part of this conversion. |
| The card frame | `Admin::SettingsScreen::CardComponent.new(section:, intro: nil, **html)`. Each card hands its own `intro:`, read from its own scope; the frame holds no key of its own, with `renders_one :head_end` (the Site card's language tabs) and `renders_one :head_note` (the Mail state, the Languages pending hint). Content is the body. It draws `section#settings-<id>-card.admin-settings-card[aria-labelledby=<id>]` and `h2#<id>`, which keeps every anchor the nav, ⌘K and the tests use. `**html` (an `id`, `data`) is merged onto the section. | Seven cards write the same section, head and heading by hand. |
| The rail's data | `GlanceComponent.new(sections:, site_setting:, mail_settings:, images_progress:, locales:, default:, ai_result: nil)` draws its rows through `GlanceRowComponent` (the same keywords plus `section:`). It reads only what the view hands it: `MailSettings.current(@site_setting)`, `Media::RenditionProgress#counts` (already computed for the Images card), the `ai_*` columns through `AiState`, and `Locales.enabled` and `Locales.default` passed in. It runs no query of its own. Each row is its own element, `#settings-glance-<id>`, so an answer replaces one row. | The spec: "a component and not a query". |
| Which answers redraw a row | `SettingsController#mail_test_streams` adds `replace("settings-glance-mail")`. `ai_test_result_stream` adds `replace("settings-glance-ai")` with `ai_result:` (`:connected` or `:failed`). `AiKeysController` and `MailLoginsController` add the AI and Mail row through `Admin::CarriedBase`'s ending, beside the part they replace. | Review Focus 4. |
| Where the snapshot logic goes | `app/javascript/saving/form_snapshot.js`: `snapshot(form) -> { values: Object, controls: Object<key, Element[]> }`, `changedKeys(initial, now) -> String[]`, `nameOf(control) -> String`. The controller imports it, and its `snapshot()` and `changes` become calls to it. | Marking and naming need the key's controls. The controller (560 lines) does not grow, and the keys stay in one place. |
| The changed mark's one writer | `admin--saving--save-bar#refresh` writes `data-save-bar-changed` on the nearest `[data-field-name]` of each changed control, and removes it from the rest. Every field a person changes has one such wrapper: per language (`title.<code>`), per row (`languages.<code>.fallback`), `social_links`, `logo`, `language_order`. The server writes `data-save-bar-changed="saved"` on a wrapper only in a refused or stale re-render (`Values#changed_fields`). The script keeps such a mark until a save or Discard, since the browser does not know the saved value, and counts and names it with its own (Task 5's counting rule). A wrapper holding an invalid control draws the invalid edge alone. | One writer in the browser. The server's mark covers Review Focus 1 (P1). |
| The bar's words | Keys in `ui.en.yml` under `save_bar`: `save_changes` "Save changes", `discard` "Discard", `names` "%{changes} · %{names}", `more` (`one` "%{names} and 1 more", `other` "%{names} and %{count} more"), `separator` ", "; `blocked` becomes "Save or discard your changes first."; `cancel` and `save` go. `NAMES_SHOWN = 3`, in `form_snapshot.js`. | Q9. The list is joined by a key, so a language may change the separator. |
| The wizard's progress | `SetupHelper#setup_progress(step) -> { number:, total:, fraction: }` from `SetupController::STEPS`. `fraction` is `number / total` rounded to 2 places: 0.11 on the first step, 0.56 on the fifth, as drawn. The bar (4px, `rounded-full`, accent on `--cs-sunken`) is `aria-hidden`. "Step %{number} of %{total}" (`setup.layout.progress`, `text-small` meta) is its visible text. | Static per step (the spec), and no time is measured. |
| Which step carries the welcome | `token` alone, the first step of a fresh install. A signed-in owner who resumes at `site` sees no welcome. | "The first step" is the first a new owner meets. |
| The step names | `SetupController::LABELS` goes. `step_label(step)` reads `I18n.t("setup.steps.#{step}")`, and a test asserts that `setup.steps` holds exactly `STEPS`. `_steps.html.erb` reads full keys only (P4). | Its words become keys. |
| One AI state | `Admin::SettingsScreen::AiState` (`ai_state.rb`): `.of(site_setting, result: nil)`, `STATES`, `TONES`, words `ai_state.*`. Read by the key's chip, Test connection's result and the rail's AI row. | Three places say the same state (P24). |
| One port rule | `app/javascript/controllers/mail_port_controller.js` (`mail-port`, top level, since the wizard loads only `application`) replaces `setup_mail_controller.js` and `admin--settings--mail#security` with its `port` target. `admin--settings--mail` keeps the login entry's hold. | The two hold the same rule twice, and their headers say so. |

---

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `Gemfile`, `Gemfile.lock`, `.github/workflows/release.yml`, `test/components/previews/preview_fixtures.rb`, `test/components/previews_test.rb`, `test/queries/dashboard/waiting_for_you_test.rb`, `test/application_system_test_case.rb`, 14 system files (`page.driver.resize`) | the dependency updates and what they break | 0 |
| `app/components/admin/ui/state_chip_component.rb` (new), `settings_screen/ai_state.rb` (new), `settings_screen/mail_state_component.rb`, `ai_key_component.{rb,html.erb}`, `ai_test_result_component.rb`, `ui/system_check_row_component.{rb,html.erb}`, `ui.en.yml`, `settings_screen.en.yml`, `test/support/design_system_entries.rb` | one state chip, one AI state | 1 |
| `app/values/settings_sections.rb` (new), `settings_screen/card_component.{rb,html.erb}` (new), `nav_component.*` and its preview, the seven cards' heads, `app/views/admin/settings/show.html.erb`, `app/queries/jump/search.rb`, `config/locales/admin/settings.en.yml` (new), `content-spiel.tailwind.css` (`.admin-settings-*`) | the sections, the nav, the card frame | 2 |
| `settings_screen/{site,languages,publishing,ai}_card_component.*`, `ai_key_component.*`, `mail_login_component.*`, `language_dialogs_component.*` | the cards' bodies in keys, their buttons | 3 |
| `settings_screen/glance_component.{rb,html.erb}` and `glance_row_component.{rb,html.erb}` (new), `ui/state_chip_component.rb` (`keyboard:`), `show.html.erb`, `settings_controller.rb`, `ai_keys_controller.rb`, `mail_logins_controller.rb`, `concerns/admin/carried_base.rb`, `content-spiel.tailwind.css` (`.admin-settings-layout`) | the rail and the layout | 4 |
| `ui/save_bar_component.{rb,html.erb}`, `app/javascript/saving/form_snapshot.js` (new), `controllers/admin/saving/save_bar_controller.js`, `values.rb`, the cards (`data-save-bar-name`, the server mark), `content-spiel.tailwind.css` (`.admin-save-bar`, `[data-save-bar-changed]`), `content-spiel.css` (`--cs-shadow-stuck`), `ui.en.yml` (`save_bar`), the four other screens' `save_label:` | the floating bar, the names, the mark | 5 |
| `app/views/layouts/setup.html.erb`, `app/views/setup/_steps.html.erb` (new), the setup views and partials but `mail` (with `_system_check_results`), `app/helpers/setup_helper.rb`, `app/controllers/setup_controller.rb` (whole), `config/locales/setup.en.yml` (new) | the wizard | 6 |
| `settings_screen/mail_fields_component.{rb,html.erb}` (new), `settings_screen/host_value_component.rb` (new), `mail_card_component.*`, `app/views/setup/mail.html.erb`, `controllers/mail_port_controller.js` (new), `controllers/setup_mail_controller.js` (deleted), `controllers/admin/settings/mail_controller.js` | one Mail form, two screens | 7 |
| `docs/reference/{settings-languages-ai,mail,design-system,save-rule-and-write-queue,i18n,cs-studio-shell-and-dashboard}.md`, `CLAUDE.md`, `CHANGELOG.md` | the reference, the PR and the cards | 8 |

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

### Task 1: One state chip for a system's state, and one AI state (Q5, Q6)

**Files:**
- Create `app/components/admin/ui/state_chip_component.rb`, with:
  - a test, `test/components/admin/ui/state_chip_component_test.rb`;
  - a preview, `test/components/previews/admin/ui/state_chip_component_preview.rb`, with the examples `ok`, `warn`, `danger` and `off`.

  It draws its tones with utilities (P23): `bg-ok-tint`/`bg-ok`/`text-ok-ink` and the warn and danger pairs, and off as `border border-field-line` with a hollow `border` ring and `text-dim`. So no stylesheet rule is added.
- Create `app/components/admin/settings_screen/ai_state.rb` (module `Admin::SettingsScreen::AiState`), the one place that names an AI state (P24):
  - `AiState.of(site_setting, result: nil) -> Symbol`, one of `STATES = %i[off no_key key_saved connected not_connected]`;
  - `off` without a provider, `no_key` with a provider and no key, `key_saved` with a key; `result:` (`:connected` / `:failed`) gives the last two;
  - `TONES = { off: :off, no_key: :warn, key_saved: :ok, connected: :ok, not_connected: :danger }`;
  - its words are `admin.components.settings_screen.ai_state.<state>`: "Off", "No key", "Key saved", "Connected", "Not connected".
- Modify `app/components/admin/settings_screen/mail_state_component.rb`:
  - its dot-and-word line is a `StateChipComponent`;
  - `TONES = { not_set_up: :off, untested: :warn, working: :ok, failed: :danger }` (public: the rail reads it), with the words `admin.mail.states.<state>.word`;
  - the sentence and the failure alert stay, and `DOTS` goes.
- Modify `app/components/admin/settings_screen/ai_key_component.{rb,html.erb}`: the hand-built chip is a `StateChipComponent` with `AiState`'s tone and word, and the detail "added 2 Oct" when a key is saved. `data-ai-key-state` is kept on the chip. Nothing else in the file changes (Task 3 converts it).
- Modify `app/components/admin/settings_screen/ai_test_result_component.rb`, converted to keys whole. A success is `AiState` `connected` with the detail `ai_test_result.time` "%{milliseconds} ms". A failure is `not_connected`, with the provider's message under it in `text-danger-ink`.
- Modify `app/components/admin/ui/system_check_row_component.{rb,html.erb}`. Its chip is a `StateChipComponent` (`:ok` / `:warn`), and its two words become keys (`admin.components.ui.system_check_row.ok` "OK", `.warning` "Warning"). Its contract changes (P8):
  - `keys` gains `ok warning`;
  - `limits` drops OK and Warning from its "are English, not keys" sentence.

  The chip loses its warn border, the row's second cue (the word stays), and the commit says so.
- Modify `test/lib/admin_design_rules_test.rb`:
  - `STATUS_FILL_FILES` gains `state_chip_component.rb` and loses `mail_state_component.rb` and `system_check_row_component.rb`;
  - the list's comment says a status component may join it in place of the screens' fills it takes over (P23);
  - `MONO_ALLOWED` loses the AI result.
- Modify `test/support/design_system_entries.rb` (P12): `VERSION = "1794162664-ed4a"`, and `ENTRIES` gains `StateChip`, `StudioSettings` and `StudioWizard`, the three cards that version adds. Nothing joins `NOT_YET`.
- Modify `test/support/ui_contract.rb`: `KEYBOARD_NOT_YET["Admin::Ui::StateChipComponent"] = "its keyboard test is the rail's, written with the rail"`. Task 4 removes it.
- Modify `test/lib/admin_i18n_test.rb`: `CONVERTED` gains `state_chip_component.rb`, `ai_state.rb` and `ai_test_result_component.rb`.
- Test:
  - `test/components/admin/settings_screen/{ai_key,ai_test_result,mail_card}_component_test.rb`, `test/components/admin/settings_screen/ai_state_test.rb` (new);
  - `test/components/admin/ui/system_check_row_component_test.rb`;
  - `test/integration/admin/system_status_test.rb` ("a status is a dot and a word, never colour alone"), `test/integration/admin/{settings_mail,ai_settings}_test.rb`;
  - `test/lib/admin_contrast_test.rb`, `test/lib/component_parts_test.rb`, `test/components/admin/ui/contract_test.rb`.

**Interfaces:**
- Produces `Admin::Ui::StateChipComponent.new(tone:, label:, detail: nil)`. `TONES = %i[ok warn danger off]`, and another tone raises. It draws `span.admin-state-chip[data-state-tone=<tone>]`: an `aria-hidden` 6px dot, the label, then " · detail". Its full contract (P7):
  - `accessibility:` "Inline text: its word says the state; the dot is hidden. It has no role and takes no focus."
  - `motion: :none`, `content_edges: %i[short long]`, `widths: :fluid`, `interface: %i[tone label detail]`;
  - `limits:` "It cannot be pressed and takes no focus.", "It draws four tones; the word, never the colour, says the state.";
  - `states: %i[ok warn danger off]`, `keys: []`, `slots: []`, `controller: nil`.
- Produces `Admin::SettingsScreen::AiState.of`, `STATES`, `TONES` and `MailStateComponent::TONES`, which Task 4's rows read.

- [ ] **Step 1: Write the failing tests.**
  - `state_chip_component_test.rb`:
    - `test "each tone draws its ground, its 6px dot and its word, the dot hidden from a screen reader"`;
    - `test "off is an outline with a hollow ring and dim words"`;
    - `test "a detail follows the word after a middle dot"`;
    - `test "an unknown tone is refused"`;
    - `test "it takes no focus and has no role"`.
  - `ai_state_test.rb`:
    - `test "off without a provider, no key with one, key saved with a key"`;
    - `test "a test's result gives connected or not connected, and each state has its tone"`.
  - `admin_contrast_test.rb`: `test "a state chip's word is 4.5:1 and its dot 3:1 on its tint, and off's edge 3:1 on the surface and the rail, in both schemes"`.
  - `ai_test_result_component_test.rb`: "connected" asserts the `ok` tone, "Connected" and "412 ms", and no `font-cs-mono`. The keys test stores a test string for `ai_state.connected`.
  - `mail_card_component_test.rb`: each of the four states draws its tone and its word (`data-mail-state` kept).
  - `system_check_row_component_test.rb`: `test "OK and Warning are keys, drawn by the state chip"`.
- [ ] **Step 2: Run them, and verify they fail.** `PGGSSENCMODE=disable bin/rails test test/components/admin/ui/state_chip_component_test.rb test/components/admin/settings_screen test/lib/admin_contrast_test.rb`.
- [ ] **Step 3: Implement.** Search the tests by hand for `CONNECTED ·`, `font-cs-mono` near the AI result, `bg-ok` and `bg-warn` dots near `mail_state` and the system check, `border-warn` on the check row and `data-ai-key-state`, and fix each hit in this task.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/lib test/components/admin test/integration/admin/settings_mail_test.rb test/integration/admin/ai_settings_test.rb test/integration/admin/system_status_test.rb test/integration/setup_early_steps_test.rb`.
  - After a build, one at a time: `admin/ai_settings_test.rb`, `admin/settings_mail_test.rb`, `admin/system_status_and_preview_test.rb`, `setup_wizard_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep. Check `pgrep`. Commit `feat: one state chip draws a system's state on Settings, the wizard and System status` (body: `Advances #117`).

---

### Task 2: One list of sections, the nav and the card frame (Q1, Q12, Q16)

**Files:**
- Create `app/values/settings_sections.rb`, with `test/values/settings_sections_test.rb`.
- Create `app/components/admin/settings_screen/card_component.{rb,html.erb}`, with a test and a preview (Q12):
  - the head is on `--cs-rail` (`.admin-settings-card__head`): the 22px `IconChipComponent` (`size: :small`), then `h2.text-h2` (20px, 600) with the section's word;
  - then the intro, in `text-small text-dim`, then `head_end` and `head_note`;
  - the card is `bg-surface shadow-1 rounded-card`, and the head's top corners take the card radius;
  - the frame has no words of its own, so there is no `card.*` key (P16).
- Modify the seven cards (`site`, `languages`, `publishing`, `forms`, `ai`, `mail`, `images`): each renders its body inside `CardComponent`, keeping its `id`, `data-controller` and anchors. Each passes its own intro (P16):
  - Forms, Images and Mail pass it from their own scope (they are converted);
  - Site, Languages, Publishing and AI pass today's literal, which Task 3 turns into a key, and they stay out of `CONVERTED` until then.

  Only their heads change in this task.
- Modify `app/components/admin/settings_screen/nav_component.{rb,html.erb}`, converted to keys whole (`nav.label` "Settings sections"):
  - `SECTIONS` and `sections_for` go; it reads `SettingsSections`, and each link has its section's chip before its word;
  - the current link (`aria-current="true"`, written by `admin--settings--nav`, unchanged) is drawn on `--cs-accent-tint` with ink words at 600, in place of the 2px ink bar (`content-spiel.tailwind.css:452`).
- Modify `test/components/previews/admin/settings_screen/nav_component_preview.rb` (P10): it builds its sections from `SettingsSections`. In `nav_component_test.rb`, "sections_for keeps the sections whose right the viewer holds" moves to `settings_sections_test.rb`.
- Modify `app/views/admin/settings/show.html.erb`, converted to keys whole (`admin.settings.show.*`: the title and the heading):
  - it passes no `save_label:`, since the bar's default is today's "Save", and adds no `save` key (P17);
  - it renders the nav with `SettingsSections.for { |permission| can?(permission) }`;
  - its header comment is rewritten without "cs-studio spec §6.1, handoff §4.5" and "decision D9".
- Create `config/locales/admin/settings.en.yml` (`admin.settings.show.*`), and move the `admin.settings.*` answers there from `settings_screen.en.yml`. Add `admin.components.settings_screen.sections.{site,languages,publishing,forms,ai,mail,images}` to `settings_screen.en.yml`.
- Modify `app/queries/jump/search.rb`: `SETTINGS_DESTINATIONS` goes. `settings_rows` maps `SettingsSections.for { |permission| AccessControl.holds?(actor, permission, channel: :admin) }` to rows titled `SETTINGS_TITLES.fetch(section.id)`: the seven, "Settings › Site" and so on.
- Modify `test/queries/jump/search_test.rb:48–63`: the order and the three new rows (Q16). Add `test "the Settings rows are SettingsSections', titled one each"`.
- Modify `test/lib/admin_i18n_test.rb`: `CONVERTED` gains `card_component.{rb,html.erb}`, `nav_component.{rb,html.erb}` and `app/views/admin/settings/show.html.erb`.
- Test: `test/components/admin/settings_screen/{card,nav}_component_test.rb`, `test/integration/admin/settings_test.rb`, `test/integration/admin/language_settings_test.rb`, `test/queries/jump/search_test.rb`, `test/components/previews_test.rb`, `test/system/admin/settings_test.rb`, `test/system/command_palette_test.rb`.

**Interfaces:**
- Produces `SettingsSections::Section` (`id`, `permission`, `family`, `icon`), with `SettingsSections::ALL`, `.for(&holds)`, `.ids` and `.find(id)`, which raises on an unknown id. The families and icons are Q1's.
- Produces `Admin::SettingsScreen::CardComponent.new(section:, intro: nil, **html)`, with the slots `head_end` and `head_note`. `NavComponent.new(sections:)` takes `Section`s.

- [ ] **Step 1: Write the failing tests.**
  - `settings_sections_test.rb`:
    - `test "the seven sections in the nav's order, each with its right, family and icon"`;
    - `test "for keeps the sections whose right is held, and find raises on an unknown id"`;
    - `test "each family is an icon chip's and each icon is drawn by the icon partial"`.
  - `card_component_test.rb`:
    - `test "the card is a section named by its heading, whose id is the section's anchor"`;
    - `test "the head carries the section's chip, its word, its intro, then the head slots"`;
    - `test "the card has no border of its own and its head is the rail's ground"`.
  - `nav_component_test.rb`: `test "each link carries its section's chip before its word"`, and the keys test with a stored string.
  - `settings_test.rb` (integration): `test "every card is drawn by the card frame, in the nav's order, for the rights the viewer holds"`.
  - `settings_test.rb` (system), on `visit_screen admin_settings_path`: "the section in view is the nav's current one, in ink with the bar, and follows the scroll" becomes `test "the section in view is the nav's current one, on the accent tint, and follows the scroll"`. It asserts the computed background is `--cs-accent-tint` and the weight 600.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests by hand for "in ink with the bar", `inset 2px 0 0`, `text-h2 text-ink` inside `admin-settings-card`, `NavComponent::SECTIONS`, `sections_for`, `Settings › ` and `SETTINGS_DESTINATIONS`, and fix each hit in this task.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/values test/components test/integration/admin/settings_test.rb test/integration/admin/language_settings_test.rb test/integration/admin/settings_forms_test.rb test/integration/admin/settings_images_test.rb test/queries/jump test/lib`, then `bin/rails zeitwerk:check`.
  - After a build, one at a time: `admin/settings_test.rb`, `command_palette_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: Settings' sections are one list; the nav and every card show the section's chip` (body: `Advances #117`).

---

### Task 3: The cards' bodies in keys, and their buttons (Q4, Q11)

**Files:**
- Modify these files, each converted to keys whole in its own scope (`settings_screen.<name>`), with today's words, and its intro moved to a key:
  - `site_card_component.*`, `languages_card_component.*`, `publishing_card_component.*`, `ai_card_component.*`;
  - `ai_key_component.*`, which keeps `data-ai-key-state` and the chip of Task 1;
  - `language_dialogs_component.*`, which is not converted today.
- Modify the Languages card:
  - "Turn off…" is `:danger_text`, small. Its unseen spacer on the default's row takes the same variant, so the rows still line up.
  - "Make default…" and "Add language" stay `:secondary`.
  - "Default" stays the neutral `BadgeComponent` (Q4).
- Modify `ai_key_component.html.erb`: "Save key" is `:secondary`, Replace `:secondary`, Remove… `:danger_text`, and Cancel stays `:tertiary`.
- Modify `mail_login_component.html.erb`: "Save login" is `:secondary` (Q11).
- Modify `test/lib/admin_i18n_test.rb`: `CONVERTED` gains every file converted here.
- Test: `test/components/admin/settings_screen/{site_card,languages_card,publishing_card,ai_card,ai_key,language_dialogs}_component_test.rb`, `test/integration/admin/{settings,language_settings,ai_settings,languages}_test.rb`, `test/system/admin/{settings,ai_settings,languages,settings_mail}_test.rb`.

- [ ] **Step 1: Write the failing tests.**
  - `languages_card_component_test.rb`:
    - `test "Turn off… is the danger text button, Make default… and Add language the secondary, and Default the neutral badge"`;
    - the keys test (a stored string for `languages_card.add`).
  - `ai_key_component_test.rb`: `test "Save key and Replace are secondary and Remove… danger text: the save bar is the screen's one primary"`.
  - `mail_card_component_test.rb`: the same for Save login.
  - Integration `settings_test.rb`: `test "the Settings screen draws one primary button, the save bar's"`.
    - It counts every element whose `class` holds every class of `ButtonComponent.classes(:primary)`, outside `dialog` and `[role=dialog]` elements (P27), and asserts one.
    - Its first assertion runs the same matcher over a sample fragment with two primaries and asserts two, so a weakened matcher fails.
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
- Create `app/components/admin/settings_screen/glance_component.{rb,html.erb}` and `glance_row_component.{rb,html.erb}` (P9), each with a test and a preview.
  - The rail is `aside.admin-settings-glance[aria-labelledby=settings-glance-heading]`, with `h2#settings-glance-heading` "At a glance".
  - It holds one `GlanceRowComponent` per section the viewer's cards show, among languages, ai, mail and images.
  - Each row is `#settings-glance-<id>`, a same-page link to `#<id>` (Q7). It holds the section's chip, its word and its state (Q6):
    - Languages: "3 languages" with "English is the default" under it, and no chip;
    - AI: `AiState` (Task 1);
    - Mail: `MailStateComponent::TONES` with `admin.mail.states.<state>.word` (P24);
    - Images: `ok` "Ready", `warn` "12 waiting", `danger` "2 failed" (both chips when both), `off` "No images yet".
  - Then the hint, in `text-small text-meta`.
  - Keys: `glance.{heading,hint,languages.count,languages.default,images.ready,images.waiting,images.failed,images.none}`, with `count` plurals. The AI and Mail words are Task 1's.
- Modify `app/views/admin/settings/show.html.erb`:
  - The screen is `div.admin-settings-layout` (`container: admin-settings / inline-size`), holding three items in document order: the nav's wrapper (the h1 and the nav), the rail, the cards' column.
  - The rail renders `GlanceComponent` with what the view already has: `MailSettings.current(@site_setting)`, the images progress, and `locales: Locales.enabled`, `default: Locales.default` (P26).
- Modify `app/assets/tailwind/content-spiel.tailwind.css`, after the lists' rail block (P14). The layout is drawn by grid areas, so no rule outside the container block names the rail:
  - one column below `lg`: `"nav" "glance" "cards"`;
  - from `lg` (the nav's existing window rule, which names only the layout): `170px minmax(0, var(--cs-form-max))`, with areas `"nav glance" "nav cards"`, the nav's sticky wrapper spanning both rows;
  - in the one `@container admin-settings (min-width: 1200px)` block (Q8): `170px minmax(0, var(--cs-form-max)) var(--cs-rail-width)`, with `--cs-rail-gap` between them and areas `"nav cards glance"`; spare width falls right of the rail;
  - `.admin-settings-glance` is `grid-area: glance`;
  - docked, it is on `--cs-rail` with `--cs-shadow-2` and `--cs-radius-rail`, `position: sticky; top: calc(var(--admin-top-offset) + var(--cs-sp-4))`;
  - below the threshold it is a compact card (`--cs-surface`, `--cs-shadow-1`, card radius).
- Modify `app/controllers/admin/settings_controller.rb`: `mail_test_streams` and `ai_test_result_stream` add the row's replace (the decisions table).
- Modify `app/controllers/admin/ai_keys_controller.rb`, `mail_logins_controller.rb` and `app/controllers/concerns/admin/carried_base.rb`: a saved or removed key or login adds its row's replace.
- Modify `test/lib/admin_design_rules_test.rb`:
  - "the editors' rail, the dashboard's and the lists' dock at one threshold" becomes `test "the editors' rail, the dashboard's, the lists' and Settings' dock at one threshold"`;
  - add `test "Settings' rail is laid out by the Settings area's own container, from the rail's tokens"`, shaped as the lists' rail test. It also holds that no `@media` block names `admin-settings-glance`.
- Modify `app/components/admin/ui/state_chip_component.rb` (P7): its contract gains `keyboard: ["test/system/admin/settings_test.rb", "the rail's states are words a keyboard passes over: each row is one link, and no chip takes the focus"]`. Modify `test/support/ui_contract.rb`: the StateChip entry leaves `KEYBOARD_NOT_YET`.
- Modify `test/lib/admin_i18n_test.rb`: `CONVERTED` gains `glance_component.{rb,html.erb}` and `glance_row_component.{rb,html.erb}`.
- Test: `test/components/admin/settings_screen/{glance,glance_row}_component_test.rb` (new), `test/integration/admin/{settings,settings_mail,ai_settings}_test.rb`, `test/lib/admin_design_rules_test.rb`, `test/lib/component_parts_test.rb`, `test/system/admin/{settings,ai_settings,settings_mail}_test.rb`.

**Interfaces:**
- Consumes `SettingsSections`, `StateChipComponent`, `AiState`, `MailStateComponent::TONES` and `CardComponent` (Tasks 1, 2).
- Produces:
  - `Admin::SettingsScreen::GlanceComponent.new(sections:, site_setting:, mail_settings:, images_progress:, locales:, default:, ai_result: nil)`;
  - `Admin::SettingsScreen::GlanceRowComponent.new(section:, site_setting:, mail_settings:, images_progress:, locales:, default:, ai_result: nil)`, with `.id_for(section_id) -> "settings-glance-<id>"`.

  The view and the streams draw rows only through `GlanceRowComponent`.

- [ ] **Step 1: Write the failing tests.**
  - `glance_row_component_test.rb`:
    - `test "languages: the count and the default, with no state chip"`;
    - `test "AI translation: Off, No key, Key saved, then Connected or Not connected after a test"`;
    - `test "mail: the four states' words and tones, as the Mail card draws them"`;
    - `test "images: Ready, waiting, failed, both, and No images yet"`;
    - `test "the row is one link to its card's anchor"`.
  - `glance_component_test.rb`:
    - `test "the rows are only the sections handed in, in their order, under the heading, then the hint"`.
  - Integration `settings_test.rb`:
    - `test "a viewer with languages.manage alone sees the languages row and no other state"` (Review Focus 3);
    - `test "the rail costs no statement of its own"`: `count_statements` with and without the rail are equal.
  - Integration `settings_mail_test.rb` and `ai_settings_test.rb`: `test "Test connection, Send test mail and a saved key update their rail row in the same answer"` (Review Focus 4). Each answer holds `turbo-stream[action=replace][target=settings-glance-<id>]` with the new word.
  - `admin_design_rules_test.rb`: the two tests above.
  - System `settings_test.rb`, on `visit_screen`:
    - `test "at 1600px the rail stands right of the cards, on the rail's ground, and stays in view down the page"`;
    - `test "at 1100px the rail is a card above the first card, beside the nav"`;
    - `test "the rail follows the Settings area's own width: a 1279px window docks it, a 1280px one does not"` (as the lists' tests, widths first);
    - `test "the rail's states are words a keyboard passes over: each row is one link, and no chip takes the focus"` (the Tab order: the nav, the rail's rows, then the first card's first control);
    - `test "a rail link with typed changes jumps to its card without asking"` (P14: no "Leave without saving?", the change still counted);
    - `test "saving a mail field puts the rail's Mail row back to Saved, not tested"` (Review Focus 4: `with_mail_state(:working)`, change Server, Save).
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Check every `turbo_stream.replace` that names a Settings part, and that the row's id is drawn once.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components test/integration/admin test/lib`, then `bin/rails zeitwerk:check`.
  - After a build, one at a time: `admin/settings_test.rb`, `admin/ai_settings_test.rb`, `admin/settings_mail_test.rb`, `admin/settings_images_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: Settings gets an At a glance rail with the state of languages, AI, mail and images` (body: `Advances #117`).

---

### Task 5: The save bar floats, names what changed and marks it (Q9, Q10)

**Scope.** The shared component, its controller and the stylesheet. They reach every non-contained bar: Settings, Groups, Users, Your account's profile form and the form builder. The only other edits are the five files that render a bar (their `save_label:`) and Settings' own cards (names and the server mark). No other screen's markup changes; Groups', Users', Your account's and the form builder's own cards wait for 7a and 7b.

**Files:**
- Create `app/javascript/saving/form_snapshot.js`, which holds `snapshot`'s key rules, moved whole from the controller with their comment.
- Modify `app/javascript/controllers/admin/saving/save_bar_controller.js`:
  - `snapshot()` and `changes` call the module;
  - `refresh()` writes the count with the names (`names`, `more`, `separator`);
  - `refresh()` writes the mark (decisions table) and shows the `dot` target only while something is unsaved;
  - the stuck observer and `data-stuck` go.
- Modify `app/components/admin/ui/save_bar_component.{rb,html.erb}` (Q9):
  - the default bar is `.admin-save-bar--floating`: `--cs-popover`, `rounded-card`, `shadow-3`, padded `12px 16px`, sticky at `bottom: var(--cs-sp-3)`, in the form's column;
  - an 8px accent dot (target `dot`), the count, then Discard (`:tertiary`, still `data-save-bar-cancel`) and Save (default label `save_changes`, primary) at the right;
  - "No unsaved changes" is in `text-meta`;
  - `contained: true` keeps its look and also reads `discard` (P11);
  - the contract's `keys` gain `save_changes discard names more separator` and lose `cancel` and `save` (P11);
  - its `script_states` lose `stuck` and gain `named: ["test/system/save_bar_test.rb", "the bar names up to three changed fields and how many more"]` and `marked: ["test/system/save_bar_test.rb", "a changed field carries the mark, and loses it when typed back"]`.
- Modify `config/locales/admin/ui.en.yml`, `save_bar`:
  - add `save_changes`, `discard`, `names`, `more` and `separator`;
  - delete `cancel` and `save`;
  - `blocked` becomes "Save or discard your changes first." (P11), which `admin--saving--pending-lock` shows too.
- Modify `app/assets/tailwind/content-spiel.tailwind.css`:
  - `.admin-save-bar[data-stuck]` goes;
  - `[data-save-bar-changed]:not(:has([aria-invalid="true"]))`: a well inside it takes `box-shadow: inset 0 -2px 0 var(--cs-accent)`, and any other control's label or legend takes the 8px accent dot after it (Q10);
  - a field that is also invalid shows its invalid edge alone.
- Modify `app/assets/tailwind/content-spiel.css`: `--cs-shadow-stuck` goes from both schemes (P13). Its only reader is the rule above.
- Modify `app/components/admin/settings_screen/values.rb` (P1): `changed_fields -> Array<String>` holds the `data-field-name` of each wrapper whose submitted value differs from the stored one. It is empty on a plain load.
- Modify the Settings cards (P1, P15). Each field a person can change has one wrapper with a `data-field-name`, and a `data-save-bar-name` where its label is not plain:
  - Site: per language, `title.<code>` and `tagline.<code>` ("%{language}: Title", "%{language}: Tagline"); `social_links` ("Social links"); `logo` ("Logo");
  - Languages: `languages.<code>.fallback` ("%{language}: Falls back to"); `language_order` ("Language order");
  - the others' wrappers already carry their field names, and their labels are plain.

  The names' keys are in each card's own scope, `settings_screen.<card>_card.names.*`. In a refused or stale re-render, each card writes `data-save-bar-changed="saved"` on the wrappers in `Values#changed_fields`.
- Modify `app/views/groups/_form.html.erb`, `users/_form.html.erb`, `accounts/edit.html.erb` and `forms_screen/builder_component.html.erb` only where a `save_label:` is the default's word. A screen's own word stays ("Save group", "Create group", "Change password", the builder's).
- Modify `test/lib/admin_design_rules_test.rb` (P6):
  - `ACCENT_FILL_ALLOWED` gains `save_bar_component.html.erb` ("the save bar's unsaved dot, beside its words");
  - the test "only a button, the checkbox, a count pill, the unread bubble and a progress bar carry the accent fill" becomes `test "only a button, the checkbox, a count pill, the unread bubble, a progress bar and the unsaved marks carry the accent fill"`, and its comment names the unsaved mark.
- Test:
  - `test/components/admin/ui/save_bar_component_test.rb`, `test/components/admin/settings_screen/*_card_component_test.rb`, `test/components/admin/settings_screen/values_test.rb` (new);
  - `test/integration/admin/settings_test.rb`;
  - `test/lib/{admin_contrast,admin_design_rules,script_messages,admin_i18n,component_parts}_test.rb`;
  - `test/system/save_bar_test.rb`, `test/system/admin/{settings,groups_editor,groups_members,users,account_password_answer,form_builder,pending_lock,messages}_test.rb`.

**Interfaces:**
- Produces `form_snapshot.js`:
  - `snapshot(form) -> { values, controls }`;
  - `changedKeys(initial, now) -> String[]`;
  - `NAMES_SHOWN = 3`;
  - `nameOf(control) -> String` (P2), in this order:
    1. `data-save-bar-name` on the control or its `[data-field-name]` wrapper;
    2. for a radio or a checkbox inside a `fieldset`, its legend;
    3. `label[for=id]` text without `.sr-only`;
    4. the enclosing legend;
    5. `aria-label`.
- The counting rule. `refresh()` counts the changed keys, plus one for each `[data-save-bar-changed="saved"]` wrapper that holds no changed key. It names the distinct wrappers of both, each once, by `nameOf`.
- `SaveBarComponent.new(form_id:, cancel_url:, save_label: nil, save_data: {}, contained: false)` keeps its signature. The targets are `bar`, `count`, `save`, `blocked` and `dot`.
- `Values#changed_fields -> Array<String>`.

- [ ] **Step 1: Write the failing tests.**
  - `save_bar_component_test.rb`:
    - `test "the bar floats: the popover ground, the card radius, elevation 3, and Discard before Save changes"`;
    - `test "Discard keeps the marker that exempts it from the leave guard"` (from "Cancel carries the marker…");
    - `test "a screen's own Save label is kept"`;
    - `test "a contained bar keeps its look and says Discard"`;
    - "Save comes before Cancel" becomes `test "the count comes first, then Discard, then Save at the end"`.
  - `values_test.rb`: `test "Values#changed_fields lists the wrappers whose typed value differs from the stored settings, per language and per row, and nothing on a plain load"` (Review Focus 1).
  - Integration `settings_test.rb`: `test "every control the Settings form submits has a name the bar can say"` (Review Focus 2). Parse the page and walk `#settings-form`'s named controls (not hidden unless `data-save-bar-track`, and not `data-save-bar-ignore`). Each has a `data-save-bar-name` on itself or its wrapper, a `legend` ancestor or a `label[for]`.
  - `admin_contrast_test.rb`:
    - `test "the changed mark is 3:1 or better on the field's fill and on the card, in both schemes"` (floor 6.9 / 7.1 on `--cs-surface`);
    - `test "the floating bar's words and dot read on the popover ground"`.
  - System `save_bar_test.rb`:
    - `test "the bar names up to three changed fields and how many more"` (change five fields on Settings: "5 unsaved changes · Provider, Server, Port and 2 more");
    - `test "a segmented control is named by its legend"` (P2: change Security, and the bar says "Security");
    - `test "a changed field carries the mark, and loses it when typed back"`;
    - "a footer stuck over the fields draws a stronger top edge and an elevation, and at the end of the form neither" becomes `test "the bar floats over the fields and at the end of the form alike"`;
    - "Cancel" becomes "Discard" in every test of the file, and `click_link "Cancel"` within the bar becomes `click_link "Discard"`.
  - System `settings_test.rb`:
    - `test "after a refused save the typed fields that differ from the saved settings carry the mark and the bar names them"` (Review Focus 1). Change Server and type an invalid Port, then Save. After the 422:
      - Server carries the changed mark;
      - Port shows its invalid edge and no changed mark (Q10);
      - the bar names both;
      - leaving asks.
    - "Back with a typed change asks first, and Cancel discards without asking" and "the footer's Cancel reloads the screen…" use Discard.
  - `pending_lock_test.rb` and `messages_test.rb`: "Save or cancel your changes first." becomes "Save or discard your changes first.".
  - `groups_editor_test.rb`, `groups_members_test.rb`, `users_test.rb`, `account_password_answer_test.rb` and `form_builder_test.rb`: every test that reads the bar's words ("Cancel", "No unsaved changes") or its stuck edge is fixed here, with no other change to those screens.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search `app/` and `test/` by hand for `data-stuck`, `shadow-stuck`, `stuckObserver`, `"Cancel"` near `.admin-save-bar`, `save_bar.cancel`, `save_bar.save`, "Save or cancel your changes" and `save_label: "Save"`, and fix each hit in this task.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components/admin test/integration/admin test/lib`.
  - After a build, one at a time: `save_bar_test.rb`, `admin/settings_test.rb`, `admin/groups_editor_test.rb`, `admin/groups_members_test.rb`, `admin/users_test.rb`, `admin/account_password_answer_test.rb`, `admin/form_builder_test.rb`, `admin/pending_lock_test.rb`, `admin/messages_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: the save bar floats, names what changed and marks each changed field` (body: `Advances #117`).

---

### Task 6: The wizard: progress, steps, one primary per step, its words in keys (Q2, Q3, Q13, Q14)

**Files:**
- Modify `app/views/layouts/setup.html.erb`, converted to keys whole by full key (`setup.layout.*`: `title`, `first_run`, `steps_label`, `done`, `optional`, `progress`):
  - the header keeps the wordmark (its `UPPER_TRACKED_ALLOWED` entry), with "First-run setup" in sans `text-small` meta;
  - the body is `max-w-[980px]`, with a 250px column and the card, 28px apart;
  - the card is `bg-surface rounded-rail shadow-2 p-11`, as drawn, and holds the insecure notice, the flash and the step.
- Create `app/views/setup/_steps.html.erb`, which reads full keys only (`setup.layout.*`, `setup.steps.<step>`), never `t(".…")` (P4). It stands on the page itself:
  - the progress bar (4px, `rounded-full`, `bg-accent` at `fraction` on a `bg-sunken` track, `aria-hidden`), then "Step %{number} of %{total}" in `text-small text-meta`;
  - then the steps, each with a 22px circle;
  - current: a `bg-accent text-on-accent` number on an `--cs-accent-tint` row with ink words at 600;
  - done: `bg-ok-tint text-ok-ink` with "✓" and "Done: " for a screen reader, which is the ok tone, never the Live fill (P5);
  - the rest: on `--cs-field-fill` in dim;
  - "Optional" is the meta word (`text-label text-meta`, Q13).
- Modify `app/helpers/setup_helper.rb`: `setup_progress(step)`. `setup_step_done?` stays.
- Modify `app/controllers/setup_controller.rb`, converted to keys whole (P3):
  - `LABELS` goes, and `step_label` reads `setup.steps.<step>`;
  - every English sentence the controller answers becomes `setup.flash.<name>`: the token's refusal, too many attempts, an existing admin, starter content added, setup complete, and the token name's error. Find them with `grep -n '"[A-Z]' app/controllers/setup_controller.rb`;
  - the comments lose "design spec 2026-09-26 §3-§4", "spec §7.1" and "Final fix wave (Important 3)".
- Modify `app/views/setup/{token,system_check,admin,site,languages,mcp_token,mcp_token_created,starter_content,review}.html.erb`, `_back.html.erb`, `_flash.html.erb` and `_system_check_results.html.erb` (P3), each converted to keys whole (`setup.<step>.*` by lazy lookup). The action row follows Q14:
  - the step's own secondary first ("Re-run checks"), then Back and Skip for now (`ButtonComponent.classes(:tertiary)`), then the primary last;
  - an advancing action is the primary: "Generate token", "Add starter content", "Finish setup";
  - on `token`, the welcome line (Q2: a 22px `structure` chip, "Welcome to Content·Spiel" in ink, `text-sm` at 600, `setup.token.welcome`), then the heading "Let's set up your site" and the drawn intro;
  - on `token`, Continue, then the `<details>` "Where do I find the log?" under the field, with Q3's words and keys and each command in `font-cs-mono`;
  - "Optional" beside an optional step's heading is the same meta word.
- Create `config/locales/setup.en.yml`. A test asserts that `setup.steps` holds exactly `SetupController::STEPS`.
- Modify `test/lib/admin_design_rules_test.rb` (P5, P6):
  - `ACCENT_FILL_ALLOWED` gains `app/views/setup/_steps.html.erb` ("the wizard's progress bar and the current step's number"), under the test name Task 5 gave;
  - `STATUS_FILL_FILES` gains it ("a done step's check, the ok tone");
  - `LIVE_SCHEDULED_FILES` is unchanged;
  - `MONO_ALLOWED` gains `app/views/setup/token.html.erb`'s log commands, if its entry does not already cover the file.
- Modify `test/lib/admin_i18n_test.rb`: `CONVERTED` gains the layout, `_steps`, the twelve views and partials, and `setup_controller.rb`.
- Test: `test/helpers/setup_helper_test.rb` (new), `test/integration/setup_{access,early_steps,optional_steps,site_steps,finish,redirect,attribution,fresh_database}_test.rb`, `test/lib/admin_contrast_test.rb`, `test/lib/admin_design_rules_test.rb`, `test/lib/admin_i18n_test.rb`, `test/system/setup_wizard_test.rb`.

**Interfaces:**
- Produces `SetupHelper#setup_progress(step) -> { number: Integer, total: Integer, fraction: Float }`, read by `_steps`.

- [ ] **Step 1: Write the failing tests.**
  - `setup_helper_test.rb`: `test "setup_progress is the step's place in nine, as a fraction rounded to two places"` (`token` → 1, 9, 0.11; `mail` → 5, 9, 0.56; `review` → 9, 9, 1.0).
  - Integration `setup_early_steps_test.rb`:
    - `test "the token step welcomes, says Step 1 of 9 and has one primary"`;
    - `test "a step names itself current, the earlier ones done in the ok tone, and Optional in words"`;
    - `test "setup.steps holds exactly the steps"`.
  - Integration `setup_optional_steps_test.rb`: `test "every step draws one primary, last in its row, its Back and Skip tertiary"`. It counts `ButtonComponent.classes(:primary)` on each step's page, with the matcher checked on a sample first.
  - `admin_contrast_test.rb`:
    - `test "the wizard's progress fill is 3:1 or better against its sunken track, in both schemes"`. A bar is a graphic. The spec's 6.9 / 7.1:1 is the accent on white, and the track is the card's `--cs-sunken`.
    - `test "the current step's words are 4.5:1 on the accent tint and its number on the accent"`;
    - `test "a done step's check is 3:1 or better on the ok tint"`.
  - System `setup_wizard_test.rb`:
    - "a fresh install goes from the token to a live homepage" reads the new words, and the step list's "Optional" is no longer "OPTIONAL";
    - add `test "Where do I find the log? opens the commands under the field and keeps the focus"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests by hand for `OPTIONAL`, "optional" in the step list, `Setup token` as a heading, `"Back"` links, `LABELS`, "Enter your setup token" and the controller's flash sentences, and fix each hit in this task.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/helpers test/integration/setup_*_test.rb test/lib`.
  - After a build: `setup_wizard_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: the setup wizard in E4: a progress bar, marked steps, one primary per step, and a welcome` (body: `Advances #117`).

---

### Task 7: One Mail form on Settings and in the wizard (Q14, Q15)

**Files:**
- Create `app/components/admin/settings_screen/host_value_component.rb`: a field the host sets, as the sunken box with "Set by the host".
  - It takes `MailSettings`' field names (`:server`), not columns.
  - A login half shows `MailLoginComponent::MASK` and never reads its value.
  - It replaces the card's three copies and the wizard's `host_box` lambda.
- Create `app/components/admin/settings_screen/mail_fields_component.{rb,html.erb}`, with a test and a preview:
  - two groups (Q15): Server, with a `media` chip (server, port, security, then the `login` slot), and Sender, with a `text` chip (sender name, sender address);
  - each group is `rounded-tile` on `--cs-paper`, `p-3`, with a `text-label text-meta` heading;
  - the security control is the one segmented control, inside a `fieldset` with its legend;
  - its radios carry `data-port` and `data-action="change->mail-port#security"`, and Port carries `data-mail-port-target="port"`;
  - each wrapper carries its `data-field-name` (Task 5's names follow).
- Modify `mail_card_component.{rb,html.erb}`:
  - its fields are `MailFieldsComponent` (`name_prefix: "site_setting"`, `id_prefix: "settings-"`), with `MailLoginComponent` in the `login` slot;
  - `FIELDS`, `SETTING`, `SECURITIES` and `PORTS` move to `MailFieldsComponent`;
  - the root gains `mail-port` in `data-controller`;
  - the ids `settings-mail_*` are kept.
- Modify `app/views/setup/mail.html.erb`, converted to keys whole (`setup.mail.*`):
  - its fields are `MailFieldsComponent` (`id_prefix: "setup-"`), with the two inline login fields in the slot;
  - the row follows Q14: Send test mail (secondary) with "Sends to <address> (your address)" in `text-small text-meta`, then Back, Skip for now and Continue, Continue last;
  - the hidden first "Continue" stays first in the form;
  - the outcome stays under the row.
- Create `app/javascript/controllers/mail_port_controller.js` (`mail-port`), with the rule and comment of the two it replaces.
- Delete `app/javascript/controllers/setup_mail_controller.js`.
- Modify `app/javascript/controllers/admin/settings/mail_controller.js`: `security`, the `port` target and `PORTS` go, and its header says the port is `mail-port`'s.
- Modify `test/lib/mail_guards_test.rb` (P25). `COLUMN_NAMERS` after this task:
  - gains `mail_fields_component.rb` and `.html.erb` ("the Settings form's and the wizard's Mail fields: the site's own value to edit; whether the host sets one is asked of MailSettings");
  - loses `mail_card_component.rb` and `.html.erb`, whose fields moved;
  - keeps `mail_login_component.rb`, `show.html.erb`, `setup_controller.rb` and `setup/mail.html.erb` (the inline login fields);
  - `host_value_component.rb` names no column and does not join.

  If the test disagrees, it shows which file the code made a namer. Write that file's reason, never a blanket entry.
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
    - `test "the security radios carry their port and mail-port's action, inside a fieldset with its legend"`.
  - `setup_mail_step_test.rb`: the two host-secret tests keep their assertions. Add `test "the step draws the shared Mail fields: the same groups and controls as Settings"`.
  - System `setup_wizard_test.rb`:
    - "the Mail step's security switch sets the port unless another port was typed" keeps its assertions;
    - add `test "Enter in a Mail field continues and sends no mail, whatever the row's order"` (Review Focus 5).
  - System `settings_mail_test.rb`: `test "the Mail card's security switch sets the port unless another port was typed"`, if no test holds it today.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search `app/` and `test/` by hand for `setup-mail`, `setup_mail_controller`, `admin--settings--mail-target="port"`, `#security`, `host_box` and `MailCardComponent::SECURITIES`/`PORTS`, and fix each hit in this task. A test that asserts a controller's absence by a fragment of its name is searched for too (CLAUDE.md).
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components/admin/settings_screen test/integration/setup_mail_step_test.rb test/integration/admin/settings_mail_test.rb test/lib`, then `bin/rails zeitwerk:check`.
  - After a build, one at a time: `setup_wizard_test.rb`, `admin/settings_mail_test.rb`, `save_bar_test.rb` (the Security name).
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `ref: Settings' Mail card and the wizard's Mail step draw one Mail form with one port rule` (body: `Advances #117`).

---

### Task 8: The reference, CLAUDE.md, the pull request and the Design System cards

**Files:**
- Modify `docs/reference/settings-languages-ai.md`, "Settings": `SettingsSections`; the card frame; the nav's chips and current look; the layout, its grid areas, container and threshold; "At a glance" (its rows, `GlanceRowComponent`, the streams that redraw them, and that it is a component and no query); `AiState`; the buttons' variants; and the "Describes" line gains the new files.
- Modify `docs/reference/mail.md` (P13): "Settings → Mail" and "The setup wizard's Mail step" name `MailFieldsComponent`, `HostValueComponent`, `mail-port` and the two groups. The "Describes" line (line 3) and line 104 change `setup_mail_controller.js` and `setup-mail` to `mail_port_controller.js` and `mail-port`.
- Modify `docs/reference/cs-studio-shell-and-dashboard.md:42` (P13): ⌘K's Settings rows are `SettingsSections`' seven, in the nav's order.
- Modify `docs/reference/save-rule-and-write-queue.md`, "The save rule" and "How the footer counts": the floating bar, Discard and "Save or discard your changes first."; the names (`form_snapshot.js`, `nameOf`'s order, `data-save-bar-name`); the mark, its one writer, and the invalid edge winning alone; the server's mark after a refused save, and the counting rule.
- Modify `docs/reference/design-system.md`:
  - a part "E4: Settings and the wizard": the card frame, the rail, the state chip and its tones, the floating bar and the mark, the wizard's progress and step list (the ok tone for a done step);
  - "Form placement": the bar floats, and the stuck state is gone;
  - the tokens part: `--cs-shadow-stuck` is gone;
  - the "Accent" paragraph (P6) names the unsaved marks (the bar's dot, the changed edge and dot) and the wizard's current step and progress beside the selection, and lists `ACCENT_FILL_ALLOWED` as it now stands;
  - "Status chips" names `StateChipComponent` as the system state's chip and `STATUS_FILL_FILES`' new members;
  - "Rules a change can break silently" gains:
    - the changed mark has one writer in the browser (`admin--saving--save-bar`), and **no guard** for a second script that writes it;
    - a system's state is `StateChipComponent`, and **no guard** for a screen that draws its own dot and word;
    - a Settings card is drawn by `CardComponent` from `SettingsSections`, and **no guard** for a card drawn outside it.
- Modify `docs/reference/i18n.md`: the Files table gains `config/locales/setup.en.yml` (`setup.*`) and `config/locales/admin/settings.en.yml`.
- Modify `CLAUDE.md`:
  - the Settings index line names `app/values/settings_sections.rb` and the glance components;
  - the mail index line names `mail_fields_component.rb` and `mail_port_controller.js` in place of `setup_mail_controller.js`;
  - "Where a script goes" lists the top level's `mail_port` in place of `setup_mail`;
  - the design-system line names `Admin::Ui::StateChipComponent`.
- Modify `CHANGELOG.md`, `## Unreleased`, Changed:
  - Settings shows each section's icon, a panel "At a glance" with the state of languages, AI translation, mail and images, and a save bar that floats at the foot and names what changed.
  - Every explicit save bar says "Discard" and "Save changes", and marks each changed field.
  - The setup wizard shows how far along it is, marks the current and finished steps, and opens with a welcome.
  - ⌘K offers every section of Settings.
- Test: `PGGSSENCMODE=disable bin/rails test test/lib`, `bin/rubocop`, `bin/rails zeitwerk:check`, `bin/brakeman`, `bin/changelog-guard main`.

- [ ] **Step 1: Write the reference, CLAUDE.md and CHANGELOG changes.**
- [ ] **Step 2: Run** the five checks. Expected: all pass.
- [ ] **Step 3: Write the PR body.**
  - "Supersedes #204–#211", with Task 0's table: each PR, what failed and why, and the gems that moved.
  - Findings: Advances #117.
  - "For the owner to check":
    - the answers that differ from the drawing (Q1, Q2, Q4, Q5, Q6, Q9, Q13, Q14);
    - the threshold (Q8);
    - ⌘K's three new rows (Q16);
    - System status's and the other save-bar screens' changes through the shared components;
    - the done step's ok tone (P5).
  - Documentation, in `/Users/dknafelj/src/contentspiel-docs`: the Settings pages (Site, Languages, AI translation, Mail, Images), "First-time setup", and the screenshots of Settings and of the wizard's steps, retaken in both themes and Settings at 1600px.
- [ ] **Step 4: The Design System cards to update**, for the design agent:
  - `StudioSettings`, `StudioWizard` and `StateChip`: from "Designed, not built" to built, with the names as built (`GlanceRowComponent`, `AiState`, `setup_progress`, `mail-port`) and the done step's mark as built;
  - `StudioCalmE4Setup`: its status to built;
  - `SaveBar` and `PatternSaving`: the floating bar and the mark built, the stuck state gone, the keys and the `dot` target named;
  - `FieldFrame` and `TextFields`: the changed state, and that the invalid edge wins alone;
  - `Alerts`: System status's row on the state chip;
  - `StudioRail`: "When to use / not" names Settings' rail;
  - `FoundationLayout`: Settings' area and its threshold.

  `test/support/design_system_entries.rb` changes only if a card is added or renamed in that change.
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
| #119 the reference docs' structure | not taken | paragraphs of five reference files change, not their structure |
| #112, #114, #116, #121, #122, #124, #128–#131, #135–#137, #140, #141, #143, #185 | not taken | no task changes their code |

## Browser tests

Run locally after `bin/rails tailwindcss:build`, one file at a time, only while the one-minute load is under 6, each prefixed with `PGGSSENCMODE=disable`.

**The implementer must run:**
- Task 0: `stale_node_test`, `shell_test`, `save_bar_test`, `admin/account_password_answer_test`, `theme_toggle_test`, `admin/presence_lists_test`, `dialog_test`, `admin/rich_text_test` (three times), and the 14 files whose `resize` changes.
- Task 1: `admin/ai_settings_test`, `admin/settings_mail_test`, `admin/system_status_and_preview_test`, `setup_wizard_test`.
- Task 2: `admin/settings_test`, `command_palette_test`.
- Task 3: `admin/settings_test`, `admin/ai_settings_test`, `admin/languages_test`, `admin/settings_mail_test`, `admin/settings_images_test`.
- Task 4: `admin/settings_test`, `admin/ai_settings_test`, `admin/settings_mail_test`, `admin/settings_images_test`.
- Task 5, every file that reads a save bar:
  - `save_bar_test` (Settings, and Your account's two forms);
  - `admin/settings_test`;
  - Groups: `admin/groups_editor_test`, `admin/groups_members_test`;
  - Users: `admin/users_test`;
  - Your account: `admin/account_password_answer_test`;
  - the form builder: `admin/form_builder_test`;
  - the shared hint: `admin/pending_lock_test`, `admin/messages_test`.
- Task 6: `setup_wizard_test`.
- Task 7: `setup_wizard_test`, `admin/settings_mail_test`, `save_bar_test`.

**Likely to change, left to CI** (the whole browser suite runs per PR):
- `theme_toggle_test` (Settings and the wizard in dark);
- `view_only_test` (a viewer without `settings.manage`);
- `invites_test` and `password_reset_test` (mail's state words);
- `admin/translations_test`, `admin/editing_merge_test` and `admin/notes_alert_test` (they read a save bar or Settings);
- every file Task 0 touched for `resize`.

A CI failure is fixed in the task that owns the file.

## Pre-flight

Done while writing this plan, then by the scan of 2026-11-08 (`.superpowers/sdd/2026-11-08-studio-e4-stage-5c/preflight-5c.md`, P1–P28, each ruled below).

- **Red mid-stack.**
  - Task 0 fixes, in itself, the three failures its bumps bring (the preview fixture, the stale-node prepend and the resize calls) and the sequence flake that blocked #205.
  - Task 1 changes the AI result's words from "● CONNECTED · 412 MS" to "Connected · 412 ms", and the check rows lose their warn border, and it fixes every test that reads either.
  - Task 2 changes ⌘K's order and fixes `search_test.rb:48–63` and `command_palette_test.rb:156`, the nav's test and its preview.
  - Task 5 changes "Cancel" to "Discard" and the blocked sentence in every save bar, and fixes every test that reads them.
  - Task 6 changes "OPTIONAL", the token step's heading and the controller's flash words.
  - Task 7 deletes `setup-mail`, and searches for its name and fragments by hand.
- **A file changed in two tasks.**
  - The seven cards' heads change in Task 2, and their bodies in Task 3 (four intros move to keys there).
  - The Settings cards' wrappers and names change in Task 5. The Mail card's fields change in Task 7, which moves its wrappers into `MailFieldsComponent` unchanged.
  - `show.html.erb` is converted in Task 2 (with no `save_label:`) and laid out in Task 4.
  - `settings_controller.rb`'s streams change in Task 4 only.
  - `ai_key_component.*` gets its chip in Task 1, and its keys and buttons in Task 3.
  - `mail_login_component.html.erb`'s variant changes in Task 3.
  - `state_chip_component.rb` is made in Task 1, and gains its `keyboard:` in Task 4.
- **Keys before their reader.**
  - `ai_state.*` arrives in Task 1, `sections.*` with the nav and the frame (Task 2), and `glance.*` with the rail (Task 4).
  - `save_bar.save_changes`, `discard`, `names`, `more` and `separator` arrive in Task 5, where `cancel` and `save` are deleted.
  - `setup.*` arrives in Task 6, and `setup.mail.*` in Task 7.
- **Guard lists.**
  - `STATUS_FILL_FILES` gains the chip and loses two files (Task 1), and gains `_steps` (Task 6).
  - `ACCENT_FILL_ALLOWED` gains the bar's dot (Task 5) and the steps (Task 6), under the renamed test.
  - `LIVE_SCHEDULED_FILES` is unchanged. `MONO_ALLOWED` loses the AI result (Task 1).
  - `KEYBOARD_NOT_YET` gains StateChip in Task 1 and loses it in Task 4.
  - `DesignSystemEntries` gains its three cards and v114's version in Task 1, and nothing joins `NOT_YET`.
  - `CONVERTED` grows in Tasks 1 to 7, each with its own files.
  - `COLUMN_NAMERS` changes in Task 7, as listed there.
  - Each list's "still used" test catches an allowance left behind.
- **Tests a mutation would not fail.**
  - The "one primary" tests (Tasks 3 and 6) run their matcher over a sample with a known count first.
  - The keys tests store a test string.
  - The rail's statement test compares with and without the rail.
  - The threshold tests check the widths first.
  - The refused-save test needs the server's mark: without it, the 422 shows no mark on Server. It also checks that Port shows no changed mark.
  - The names test walks the real form, so a new unnamed control fails it, and the Security test catches a radio named by its option.
- **Not reproduced while planning.** No test database existed in this worktree, so the #206 diagnosis rests on ViewComponent's diff (`render_preview` now `process(:previews)`) and Active Storage's `after_commit` upload, not on a run. Task 0 Step 1 runs it first.
- **History comments.** Every task ends on the grep in "Comment rule", run over the lines it added.

### Rulings

| P | Ruling | Why |
|---|---|---|
| P1 | As suggested, with Q10. The mechanism: each field a person can change has one wrapper with a `data-field-name`, per language (`title.<code>`), per row (`languages.<code>.fallback`), and for the social rows and the logo. `Values#changed_fields` returns those names. `refresh()` counts and names the union of its changed keys and the server-marked wrappers. The test asserts that Port, invalid and changed, shows its invalid edge only, and is named. | Q10: the invalid edge wins alone. Symbols could not address per-language or per-row fields. |
| P2 | As suggested: legend first for a radio or checkbox in a fieldset, plus the Security test. | The bar would say "STARTTLS". |
| P3 | As suggested: the controller's sentences become `setup.flash.*`, listed; `_system_check_results` joins. | A file is converted whole. |
| P4 | As suggested: `_steps` reads full keys only. | Lazy lookup would land in `setup.steps`. |
| P5 | As the controller ruled: the ok tone (`bg-ok-tint text-ok-ink`), `_steps` in `STATUS_FILL_FILES`, `LIVE_SCHEDULED_FILES` unchanged. The design agent is asked to confirm the exact mark; `StudioWizard` draws none. | Q4 and Q5 keep publishing's Live fill to publishing. |
| P6 | As suggested: the guard test is renamed and its comment widened (Task 5); Task 8 rewrites the Accent paragraph. | The unsaved marks and the current step are new accent uses. |
| P7 | As suggested: the full contract in Task 1; `keyboard:` in the component's file in Task 4. | A missing keyword raises at load. |
| P8 | As suggested: `keys` gains `ok warning`; the limits sentence changes; the lost warn border is said in the commit. | The contract would lie. |
| P9 | As suggested: `GlanceRowComponent`'s full signature, a test, a file-map row and `CONVERTED`. | An answer replaces one row. |
| P10 | As suggested: the preview and the moved test are named. | They read the removed constant. |
| P11 | As suggested: `blocked` reads "Save or discard your changes first."; `save` and `cancel` are deleted; a contained bar says Discard. | Words named a button that is gone. |
| P12 | **Ruled differently.** v114 already has the `StateChip` card (and `StudioSettings` and `StudioWizard`). So Task 1 adds the three to `ENTRIES` with `VERSION = "1794162664-ed4a"`, and nothing goes into `NOT_YET`. | The card exists, so no follow-up is needed. |
| P13 | As suggested: `cs-studio-shell-and-dashboard.md:42` and `mail.md`'s lines 3 and 104 join Task 8; the token's removal is unconditional in Task 5. | Its only reader is the rule Task 5 deletes. |
| P14 | As suggested: grid areas at three widths, the rail placed by `grid-area` only, and a test that a rail link asks nothing. | The rail needs a cell between `lg` and the threshold. |
| P15 | As suggested: `settings_screen.<card>_card.names.*`. | That is the components' scope. |
| P16 | As suggested: each card hands its own intro; four pass a literal until Task 3; the frame holds no `card.*` key. | The frame says nothing of its own. |
| P17 | As suggested: Task 2 passes no `save_label:` and adds no `save` key. | The key would be orphaned in Task 5. |
| P18 | As suggested: the two files leave the map; the dialogs are a firm item. | They are not converted, and the task changes neither file. |
| P19 | As suggested: `BadgeComponent` is dropped from the list. | No task changes it (Q4, Q13). |
| P20 | As suggested, settled by Q3: a native disclosure, its summary a tertiary-looking line. | It is not a button. |
| P21 | **Ruled differently:** the trailer stays `Claude Opus 5.5`, with the session link. | The coordinator's brief and the session's attribution both name Opus 5.5. |
| P22 | Settled: every answer followed its recommendation, so no task is ambiguous; Task 5's scope is written as a list of files. | — |
| P23 | As suggested: the chip draws with utilities, and `STATUS_FILL_FILES`' comment admits a status component that takes over screens' fills. | No stylesheet rule is needed. |
| P24 | As suggested: the rows read `MailStateComponent::TONES` and `AiState`; one key set for the AI words. | One rule, one place. |
| P25 | As suggested: `COLUMN_NAMERS` after Task 7 is listed file by file, with reasons. | The guard fails both ways. |
| P26 | As suggested: `locales:` and `default:` are handed in. | The rail runs no read of its own. |
| P27 | As suggested: the matcher excludes `[role=dialog]` too. | — |
| P28 | As suggested: the grep runs over the lines a task added (`git diff -U0`). | Whole files hold kept invariants that match ("no longer"). |
