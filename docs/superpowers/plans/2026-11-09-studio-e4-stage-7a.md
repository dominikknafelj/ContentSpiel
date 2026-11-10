# CS Studio in E4, Stage 7a (the content-side screens) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The media library and its picker, Trash, Translations, Forms (list, builder, submissions, a submission) and the audit log take E4. The media panel becomes a rail with Image · Notes tabs where the library is 1200px wide or more, and the grid's tiles stand at elevation 1. Each list screen is a heading, a filter, and one card holding the table. Every state is said in its word, and none is red. A record's kind is its icon chip beside its word, wherever it is listed. Every word these screens still say in English becomes a key. Settings' card frame becomes a shared component that the form builder also draws. The stage-6 avatar stacks stop overlapping (Q23).

**Architecture:**
- The shared looks that a second screen now needs move to `app/components/admin/ui/` with the full contract:
  - `Admin::Ui::RecordChipComponent` draws a record kind's chip and word. Trash, Translations, the media rail's "Used on" and the notes rows draw it.
  - `Admin::Ui::SettingsCardComponent` is Settings' card frame (Q17). Settings and the form builder draw it.
  - One stylesheet class, `.admin-tile`, draws a tile at rest, under the pointer and when selected. The media tiles, the upload tiles and Translations' language tiles use it.
- The media rail reuses the editors' rail parts (`RailTabsComponent`, `RailPanelComponent`, `RailSlotComponent`, `admin--ui--rail`) inside one wrapper of its own, `#media-rail`. It docks by the library's own container, `admin-media`. The Notes tab reaches it through a new panel slot, `media.rail.tabs`, so the Media screen never names notes. `RailSlotComponent` is told which slot it draws.
- No query, service, route or model changes, except two things. The trash list hands each row the actor facts the audit log already builds (`Audit::Sentence::Actor`). `Admin::Slots::NAMES` gains a name.

**Tech Stack:** Rails 8.1, ViewComponent 4.23 with Lookbook previews, Tailwind v4 (`tailwindcss-rails`), Turbo frames and streams, Stimulus over import maps, Minitest with Capybara on Cuprite 0.20.

**Spec:** `docs/superpowers/specs/2026-11-06-studio-e4-design.md` (approved 2026-11-06). Sections used:
- "The design, as decided": the four roles and status, buttons, one type voice, radii and elevations;
- "Every screen, and its stage": the rows "Media library and picker", "Trash", "Translations", "Forms: list, builder, submissions, deliveries" and "Audit log";
- "The rule for a screen the artifact does not draw", rules 1 to 6;
- "Stage 7: every remaining screen", the bullet 7a;
- "Architecture-review findings", "The guard after E4" and "Constraints".

The drawing is the Design System artifact (https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT) at version `1794259911-f251`, on the cards `StudioTrash`, `StudioTranslations`, `StudioForms` and `StudioAuditLog`, and on `StudioMediaGrid`'s "Gaps" (the media rail). Implementers do not read or edit the artifact. It belongs to the design agent.

**One pull request** on branch `studio-e4-7a`, made from `main` at 08913a2a, targeting `main`.

---

## Design answers

These are binding. The source is `.superpowers/sdd/2026-11-09-studio-e4-stage-7a/design-answers-7a.md` (git-ignored, Q1–Q23), which an implementer reads beside their task. The owner chose on 2026-11-09, and every choice follows the recommendation:
- **Q4:** the media rail docks at 1200px of the library. From 760px to 1199px it keeps today's 340px column card, and below 760px it stacks under the grid.
- **Q13:** Translations' language summaries are tiles with a selected outline.
- **Q17:** the builder's cards take Settings' card frame, and `SettingsScreen::CardComponent` moves to `Admin::Ui::SettingsCardComponent`.
- **Q19:** the audit log is one card with sticky day bands.

In short (the figures are light / dark):

- **Shared (Q1–Q3).**
  - No screen but Media takes a rail. None uses `.admin-list-rail` or `ListStateComponent`.
  - Sizes: `text-[13px]` becomes `text-small`, `text-[15px]` becomes `text-body`, and `text-xs` beside a label becomes `text-label`.
  - Hand-drawn `border border-line` boxes go: the preview's box, the summary cards, the delete zones, the facts grid's outer cells, the dashed "Add field" box and the audit subject chip. A table keeps its grouping lines inside its one card, and a control keeps its `field-line` frame.
  - `danger` stays only on a destructive confirm and on `danger_text` triggers.
  - A table card scrolls sideways inside itself, with its first column sticky. The page never scrolls sideways. Below 640px a heading row's actions wrap under the heading.
- **Media (Q4–Q9).**
  - The rail is 360px (`--cs-rail-width`) on the `rail` ground at `shadow-2` and `rounded-rail`, sticky, with its panel scrolling inside itself. It is capped at `--cs-content-max` and centred past it.
  - Tabs: "Image" and "Notes". The Notes tab carries the count as the people bubble ("3"), or "2 new" on the accent. Image is the default; `?notes=open` and a thread link open Notes.
  - Close is last, top-right: tertiary small, the `x` icon, "Close panel". It closes the panel and gives focus back to the tile. Escape does the same.
  - The Image tab, in order:
    1. the title in `text-h2`;
    2. the preview on `sunken` at `rounded-tile`, with no border;
    3. the facts `dl` (`text-label` keys in `meta`, values in `ink`);
    4. Download original (tertiary small) and its hint;
    5. the language tabs with the save line;
    6. Title, Alt and Caption as wells;
    7. "Used on", each row the 20px chip of its kind and the title as a link;
    8. the `media.panel.sections` slot;
    9. a `line` rule, then Move to trash (see ruling C3).
  - The Notes tab with no thread shows "No notes on this image yet." (13px `meta`) over the ready composer. A viewer who may not write sees the line alone. Below 1200px there are no tabs, and Notes is the section at the panel's end, with the same empty line.
  - Tiles:
    - rest: `rounded-tile bg-surface shadow-1`, with no border;
    - hover: `shadow-2`;
    - selected or pressed: `shadow-1` with a 2px `accent` outline at 2px offset (6.89 / 7.08 on surface, 6.26 / 7.87 on paper);
    - loading: the blurred tiny preview under the lazy thumbnail (`blur(12px)`, scale 1.1, clipped), or `sunken` with no preview.
  - The picker keeps its dialog and its fixed columns, and takes the same tiles and toolbar. The drop overlay stays.
- **Trash (Q10–Q12).**
  - The heading row is "Trash" and "Empty trash…" (`danger_text`). There is no primary.
  - The retention line is `text-small meta`, with "Change" as a tertiary small link.
  - Then the type tabs, then one card holding the table.
  - The columns:
    - Item: a 40px thumbnail at `rounded-tile`, the title at 14px/500, the subpage sentence in `text-small meta`;
    - Type: the 20px chip and its word;
    - Trashed: a `:sm` avatar, the name and "· 2h ago";
    - Deletes: the retention words in `text-label meta`, with "Today" and "Tomorrow" in `warn-ink` (7.61 / 9.83);
    - the actions: Restore (secondary small), or Restore under with its select, and "Delete now…" (`danger_text` small).
  - Empty: "The trash is empty.", and per type "No pages in the trash." and so on.
- **Translations (Q13–Q15).**
  - The language tiles are `.admin-tile` links. Each holds the name (14px/600), "72% done" (`text-label`), a 4px `ok` bar on a `sunken` track (4.29 / 5.73), and "↻ 3 outdated" in `warn-ink` or "12 missing" in `meta`. The current tile has the selected outline and `aria-current`.
  - The matrix is one card. Its header row is sticky, and the Item column is sticky at the left, both on `surface`.
  - A row's type is the 20px chip and its word. The row ends with its verb ("Translate", `dim`, `accent` on hover and focus), and the row is `paper` under the pointer.
  - The chips are unchanged.
  - The type filter is the filter bar's segments with Clear.
  - "Translate all" and its pending box keep the suggestion look.
  - Empty: "Everything is translated."
- **Forms (Q16–Q18).**
  - The list: "Forms", its intro, and "New form" (primary). The warnings stay the warn box. One card holds the table. In Submissions, a failure count is `StateChipComponent :warn` "2 not delivered".
  - The builder:
    - the 760px form column, holding the tabs and the language tabs;
    - the cards in the Settings frame, with the `form` chip;
    - a field is a `paper` row at `rounded-tile`, its head holding the type's Badge, the label, "Required" in `text-label`, ↑ ↓ as tertiary icon buttons, and Remove;
    - "Add a field" is a `paper` well of secondary small type buttons;
    - the delete zone becomes a `line` rule and its `danger_text` button;
    - an invalid field takes the shared invalid edge;
    - Save stays the floating save bar.
  - A submission:
    - the Answers card, its values in `text-body`;
    - the Deliveries card, one row per destination: a `StateChipComponent` (ok "Sent" with "· 14:05", off "Waiting" or "Sending", warn "Not delivered"), the reason in `text-small warn-ink`, and "Send again" (secondary small).
  - No state is red.
- **Audit log (Q19–Q21).**
  - Above the list, the filter bar: the subject is the chip input's chip with ×, then Clear.
  - One card. Each day is a `paper` band, its date in `text-label meta` (5.71 / 7.08), sticky under the top bar.
  - A row:
    - the time in `text-label meta`, tabular;
    - the `:sm` avatar;
    - the sentence in 14px `ink`, names at 500;
    - the channel chip;
    - for a security event, a `StateChipComponent :warn` "Security";
    - the key in mono `text-label meta`;
    - `paper` under the pointer.
  - "Newer" and "Load older" are tertiary small, under the card.
  - The event page:
    - the breadcrumb in `text-label`;
    - the sentence as `text-h1`;
    - one facts card, whose `dl` grid is divided by `line` inside it;
    - the Changes card, with Field in mono and the word diff whose removed words are struck through in `ink` with a `meta` line on `sunken` (14.47 / 11.53).
- **Words (Q22).** Every literal these screens still say becomes a key, together with the new words: "No notes on this image yet.", "The trash is empty.", "Everything is translated.", "Security", "Add a field", "Not delivered", "Sent", "Waiting" and "Sending".
- **The stage-6 fix (Q23).**
  - Avatar stacks stop overlapping. They stand 2px apart at every size, with "+N" 2px after the last circle, and have no ground ring.
  - On a tree row the title is `flex: 1 1 7rem; min-width: 7rem`, and the markers do not shrink.
  - Under `@container admin-tree-row (max-width: 200px)`, the circles and "+N" give way to one `:more` circle holding the number of people here ("3"), with the same sentence and tooltip.
  - Two circles and "+N" take 70px, and one circle and "+N" take 46px.

**Component mapping** (v `1794259911-f251`):

| Component | Card |
|---|---|
| `Admin::Ui::RecordChipComponent` (new) | `IconChip` (covered) |
| `Admin::Ui::SettingsCardComponent` (moved from `SettingsScreen::CardComponent`) | `StudioSettings` (covered); `StudioForms` names it |
| `Admin::MediaLibrary::*`, the media rail | `StudioMediaGrid` |
| `Admin::TrashScreen::*` | `StudioTrash` |
| `Admin::TranslationScreen::*` | `StudioTranslations` |
| `Admin::FormsScreen::*` | `StudioForms` |
| `Admin::AuditScreen::*` | `StudioAuditLog` |

## Global Constraints

- **Design first.** An implementer who meets a look, a word or a state that neither this plan, the answers nor the drawing settles stops and reports **NEEDS_CONTEXT**, naming the gap. The design agent answers in the artifact, and the answer goes back to the same implementer.
- **The public site keeps its look.** No file under `app/assets/tailwind/themes/`, `app/components/blocks/`, `app/components/posts/`, `app/components/public/`, `app/views/layouts/public/` or `app/views/pages/` changes, and no `th-*` token does. `app/components/media/picture_component.*` is the public site's, and is not touched.
- **CLAUDE.md binds every task.** In particular:
  - A list or search over pages, posts, images or forms hides trashed records itself. No task changes a query.
  - Notes never write the record. A core screen draws the slot and never names notes (`test/lib/notes_boundary_test.rb`, which keeps the media panel and the Media view clear of the word, comments included).
  - The media panel's form saves through the write queue, with its `base_updated_at`. The rail moves no form and clones nothing.
  - Whatever a script writes into the page is taken back before Turbo's snapshot.
  - The publish, discard and cancel dialogs are not on these screens. The confirm dialogs stay outside the part an autosave's answer replaces (`#media-panel-title`, the tile, the counts).
  - Never define `Admin::<Domain>`. A screen's components stay in the screen's folder.
  - Dependency direction: no model, query or value learns a component.
- **No compatibility code.** A moved or renamed constant, class, method, key or CSS custom property keeps no alias. Every caller, test, preview, comment and reference doc is changed in the task that moves it. `git grep` for the old name prints nothing outside `docs/superpowers/` (history) and `CHANGELOG.md`.
- **No admin string is a literal.**
  - A component's keys are `admin.components.<folder>.*` in `config/locales/admin/<folder>.en.yml`, and a `ui/` component's are in `ui.en.yml`.
  - A view's keys are under `admin.<screen>.<view>.*` in `config/locales/admin/<screen>.en.yml`. New files: `media.en.yml` (`admin.media`), `trash.en.yml` (`admin.trash`), `trash_screen.en.yml`, `translations.en.yml` (`admin.translations`), `audit_events.en.yml` (`admin.audit_events`) and `audit_screen.en.yml`. Each holds exactly its scope (`test/lib/source_layout_test.rb`).
  - A script's words come from the server's `data-messages`, read with `messages(element).t`.
  - A key is added in the task whose code reads it. A file converted to keys joins `test/lib/admin_i18n_test.rb`'s `CONVERTED` in that task.
  - `Audit::Sentence`'s English stays, as named out of scope in `docs/reference/i18n.md`.
- **The component contract.**
  - A component in `app/components/admin/ui/` declares `Admin::Ui::Contract`, and has a component test, a preview example per previewable state, and a Design System entry (`test/support/design_system_entries.rb`).
  - A new or moved component is not on `UiContract::MADE_BEFORE_CONTRACT`, which is at its limit of 40 and only shrinks. It names a keyboard browser test in `keyboard:`. A component that takes no focus names the test that holds that the keyboard passes over it. `KEYBOARD_NOT_YET` stays empty.
  - A component used by more than one screen that a task touches moves to `ui/` (the rule the stage-6 PR wrote into `docs/reference/design-system.md`, "Component contract").
- **Buttons are the shared button.** A link drawn as a button takes `Admin::Ui::ButtonComponent.classes(variant, size:)`. One primary per area: "Upload images", "New form", and the builder's save bar. Trash, Translations, the audit log and the submissions screens draw none.
- **Status in words, never red.** `danger` appears only on `danger_text` triggers and destructive confirms. Retention, delivery, security and translation states are ok, warn or off, each with its word.
- **No new border for depth.** A tile or card is an elevation (`shadow-1`/`2`). Grouping lines stay inside a card. A radius is a radius token, a shadow is an elevation token, and a colour is a token (`test/lib/admin_design_rules_test.rb`).
- **Contrast is measured** (`test/lib/admin_contrast_test.rb`) in both schemes, at the answers' figures rounded down to one decimal.
- **Layers.** No raw z-index. A sticky header, column or band uses `--cs-z-*`. **Motion:** nothing new moves, and a tile's hover changes its elevation only (no transform).
- **Comment rule (#117).** A comment states a current invariant, a hazard or a reason. It never states a plan step, a review round, "handoff §4.6", "spec §", "B19", "bug 7", "design pass", "Task 18" or what used to be there, and these screens are full of such references. Every task rewrites the comments of the files it changes. Its last step before its commit runs this grep over the lines the task added (`git diff -U0 main... -- <files> | grep '^+'`), and the grep prints nothing:

  ```
  grep -n "spec §\|handoff [0-9§B]\|handoff,\|Task [0-9]\|round [0-9]\|final review\|[Rr]uling [A-Z]\?[0-9]\|decision D\?[0-9]\|fix wave\|ledger C-\|design answer\|design pass\|bug [0-9]\|\bB[0-9][0-9]\?\b\|Q[0-9][0-9]\?\b\|old name\|used to\|no longer"
  ```

  The plan's wording is never copied into a comment.
- **Tests and the machine.**
  - On macOS every test command is prefixed with `PGGSSENCMODE=disable`. The worktree runs `bin/rails db:test:prepare` once, before its first test.
  - Browser tests run only after `bin/rails tailwindcss:build`, never during a build or beside a running `bin/dev`. They run one file per command, and only while the first figure of `sysctl -n vm.loadavg` is under 6 and no `rails test` runs (`pgrep -f "rails test"` prints nothing).
  - A browser test begins on `visit_screen` or `visit_editor`. A test this stage rewrites moves its bare `visit … await_admin_controllers` onto them (#133).
  - Cuprite 0.20: after anything the page redraws, a test reads a node through a retrying selector, and never holds a node found before the redraw. `evaluate_async_script` drops a sole falsy argument.
  - No new browser file. New unit files are weighed by their count (`bin/test-shard`). A moved component's test moves with `git mv`.
  - **No test run is left in the background** when a task ends. Its last step checks that `pgrep -f "rails test"` prints nothing.
- Commits follow conventional commits and end with:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT`
  A task that carries a finding says so in its body ("Advances #117").

## Review Focus

1. **Escape in the media rail.** Escape closes the rail only when the focus is inside the rail and not in a text field, a select, the notes (whose composer and thread take their own Escape) or an open dialog or menu. A person who presses Escape while typing an alt text keeps both the panel and their text, and the autosave still lands. Task 5:
   - `test "Escape closes the rail and puts the focus on the tile; Escape in the alt field, in the notes' composer or in the trash dialog does not, and the alt text typed is saved"` (browser, `media_library_test`).
2. **The rail at its thresholds and across a choice.** At 1199px and 1200px of the library (not of the window), with the tree folded or not, choosing another tile keeps the open tab: Notes stays Notes while the URL advances. A thread link opens Notes docked and the section below 1200px. `#notes` is in the document once at every width. Task 5:
   - `test "the library docks the rail at 1200px of its own width, keeps the 340px card from 760px and stacks under the grid below; the notes frame is in the page once"`;
   - `test "a thread link opens the Notes tab where the rail docks and the Notes section where it does not; choosing another tile keeps the tab"` (both browser, `media_library_test`).
3. **Sticky headers inside a sideways scroller.** A sticky element cannot stick to the window from inside an `overflow-x: auto` box. The matrix's header must still stay visible when the page scrolls (ruling C6), its Item column must stay at the left when the card scrolls sideways, and the top bar must stay over both. Task 7:
   - `test "the matrix's header row stays in view as its rows scroll, the Item column stays at the left as the card scrolls sideways, and the top bar stays over both"` (browser, `translations_test`; the test at line 488 is folded into it).
4. **The type chip for a kind with no module.** Translations lists "Site settings", and Trash lists forms. Every kind a list can show has a chip and a word, and an unknown kind is refused loudly rather than drawn bare. Task 1: `test "every kind Trash and Translations can list has a chip, and an unknown kind is refused"` (component, `record_chip_component_test`).
5. **People and the narrow row.** With three people on a deep page in a 220px column, the title keeps 7rem, the presence marker gives way to one count circle, and the script keeps that count true as people come and go. A title is never cut to "Our s…" by its markers. Task 3:
   - `test "a deep row in a narrow column keeps 7rem of title, shows one count circle for three people, and the script keeps the count as one leaves"` (browser, `presence_lists_test`).

---

## Decisions the spec left open (not looks)

| Question | Decision | Why |
|---|---|---|
| Where a kind's chip comes from | `Admin::Ui::RecordChipComponent.new(kind:, label: nil)`, with `KINDS = { "page" => :pages, "post" => :posts, "media" => :media, "form" => :forms, "settings" => :settings }`, a `StudioModules` name each. It draws `IconChipComponent` at `:xsmall` with the module's icon and family, `aria-hidden`. With a `label`, it is `span.inline-flex.items-center.gap-1.5` holding the chip and the word in `text-small text-dim`. An unknown kind raises `ArgumentError`. `NotesScreen::RecordRow#record_chip` draws it, and its `MODULES` goes. | Four screens draw the same chip (the notes rows, Trash, Translations, "Used on"). The "combine same-job components" rule puts one in `ui/`. The module's family is the sidebar's, so a kind is the same colour everywhere. |
| The trashed-by avatar | `TrashScreen::ListComponent#who_actor(item) -> Audit::Sentence::Actor` is built from the same two sources as `who_label`. `RowComponent` takes `actor:` beside `who:`. `ActorAvatarComponent.new(actor:, size: :lg)` gains `size:` (`:lg` or `:sm`, anything else refused), and the `SLOT` follows the size. | The avatar knows actors as the audit log's facts. A second shape would be a second rule for "a deleted user" and "System". |
| The Settings frame's interface | `Admin::Ui::SettingsCardComponent.new(heading_id:, heading:, icon:, family:, intro: nil, **html)`, with the slots `head_end`, `head_note` and `heading_mark` kept. It has no default `id`: a caller hands one in `**html`. Settings' cards call `render Admin::Ui::SettingsCardComponent.new(**Admin::SettingsScreen::SectionCard.options(section, self), id: …)`. The new module `app/components/admin/settings_screen/section_card.rb` holds `self.word_key(section)` (moved from `CardComponent`, read by `NavComponent` and `GlanceRowComponent`) and `self.options(section, view) -> { heading_id:, heading:, icon:, family: }`. The builder hands `heading_id: "form-card-<name>"`, its heading key, `icon: :clipboard_list` and `family: :form`. | A shared frame knows no Settings section. Settings' own mapping stays in its folder. |
| The submission's cards | `SubmissionComponent`'s Answers and Deliveries cards take the same frame. `BuilderComponent::CARD_CLASS` and `CARD_HEAD_CLASS` go, and the Destinations and Placements cards draw the frame too. | One job, one frame. The `admin-settings-card` class is then drawn only by the component. |
| The media rail's markup | `#media-library.admin-media-library` (`container: admin-media / inline-size`) holds the head, the toolbar and `.admin-media-library__grid`. In the grid there is `.admin-media-library__main` (the grid list and its pagination) and, with a tile selected, `#media-rail.admin-media-rail` with `data-controller="admin--ui--rail"`. The rail holds `RailTabsComponent` (Image, plus the slot's tabs), the Image `RailPanelComponent` (holding `PanelComponent`), the `RailSlotComponent` of `media.rail.tabs`, and Close last. `--admin-rail-docked` is set on `.admin-media-rail` inside `@container admin-media (min-width: 1200px)`. | The editors' parts and script, not a copy. One wrapper is sticky in both the docked and the middle range, and the editor's grid rules (header height, measures) do not apply to it. |
| The rail's slot | `Admin::Slots::NAMES` gains `media.rail.tabs`. `RailSlotComponent.new(slot:, rail_id:, record:, viewer:, reserved: [], **context)` reads `Admin::Slots.entries(slot)`. Every caller passes it: the post form, `admin/pages/show`, `Admin::Answers::RailTabStreams` (`slot: "editor.rail.tabs"`), the preview, and the tests. In `config/initializers/admin_slots.rb`, `NotesScreen::MediaSectionComponent` moves from `media.panel.sections` to `media.rail.tabs` and answers `tab_key` "notes", `tab_label`, `tab_count`, `tab_count_data` and `tab_current?` (`?notes=open` or a `thread`). `media.panel.sections` keeps its place in the Image tab, with nothing registered. | The rail does not name notes, as `notes_boundary_test` holds. A slot name is the host's, and a host that asks for another is one keyword. |
| The Notes tab's bubble | `RailTabsComponent`'s count span gains `data-tab-count`. One rule draws `.admin-rail__tab [data-tab-count]` as the people bubble, and `[data-tab-count][data-unread]` as the accent bubble. It is the editors' Notes tab too. `drawer_controller.js#paint` writes `notes.script.marker.new` ("%{count} new") into a `total` target that carries `data-notes-total-words` while something is unread, and the plain number otherwise. Both Notes tabs carry the attribute, and the header button does not. | Q5's bubble, with the word "new" so the colour is not the only cue. `paint()` already keeps the count and `data-unread` true on the `total` targets. |
| Close | A link, not a `<button>`: `link_to close_path` with `ButtonComponent.classes(:tertiary, size: :small)`, the `x` icon, and `TooltipComponent.host_data` with "Close panel" as its `aria-label` and tooltip. It is the rail's last child, absolute top-right, and the Image tab's title row keeps `pr-10`. It keeps `click->admin--media--panel#close` and the tile id param. | A close is a navigation that advances the address and works without script. `ButtonComponent` draws only a `<button>`, so the link takes its look, as the wizard's links do. |
| Escape | `admin--media--panel#escape` runs on `keydown.esc` on `#media-rail`. It does nothing when `event.defaultPrevented`, when the target is an `input`, `textarea`, `select` or `[contenteditable]`, when it is inside `#media-notes`, or when an open `dialog` or `[role=menu]` holds it. Otherwise it clicks the Close link, which brings the focus back to the tile. | Review Focus 1. Escape belongs to the innermost thing that takes it. |
| The middle range | `@container admin-media (min-width: 760px)`: the grid is `minmax(0, 1fr) 340px`, gap `--cs-sp-6`, and the rail is `surface`, `shadow-1`, `rounded-card`, sticky under `--admin-top-offset`, scrolling inside itself, with its tabs hidden and every panel shown. `(min-width: 1200px)`: `minmax(0, 1fr) var(--cs-rail-width)`, gap `--cs-rail-gap`, the `rail` ground, `shadow-2`, `rounded-rail`, the tabs shown, and a panel without `[data-current]` hidden. Here `.admin-media-library__head` and `__grid` take `max-width: var(--cs-content-max); margin-inline: auto`. Below 760px there is one column. The window's `lg:` classes go. | Q4. The same docked rules as the other rails, written in this container's block, since a container query cannot be shared across names. |
| A tile's look | One class in `content-spiel.tailwind.css`: `.admin-tile` (`border-radius: var(--cs-radius-tile); background: var(--cs-surface); box-shadow: var(--cs-shadow-1)`). `@media (hover: hover)`, `.admin-tile:hover` takes `var(--cs-shadow-2)`. `.admin-tile:is([aria-current="true"], [aria-pressed="true"])` takes `outline: 2px solid var(--cs-accent); outline-offset: 2px; box-shadow: var(--cs-shadow-1)`. `TileComponent::CARD` and `PICK_CARD` draw it, as do `upload_tiles.js` (from the upload controller's `tile-class` value) and `SummaryCardComponent`. | Three screens draw the same tile, so there is one rule. The selected look is a selection, an accent outline (a named use, below). |
| The blurred preview | `TileComponent` draws `<img src="<%= asset.preview_data_url %>" alt="" aria-hidden="true" class="absolute inset-0 size-full scale-110 object-cover blur-md">` under the thumbnail, when the asset has both a made width and a preview. `LibraryImageComponent` is unchanged. | `blur-md` is 12px. The face already clips (`overflow-hidden`). |
| The upload tiles' words | `upload_tiles.js`'s `TEXTS` go. The upload controller's element carries `data-messages` with `admin.components.media_library.uploads.{uploading,failed,offline,dismiss,status_done,status_failed}`, read with `messages(element).t`. | Q22, with the artifact's planned keys. |
| A sticky table header | `.admin-table-scroll` in `content-spiel.tailwind.css` is `overflow: auto; max-height: calc(100dvh - var(--admin-top-offset) - var(--cs-sp-4) * 2); overscroll-behavior: auto`. Its `thead th` is `position: sticky; top: 0; z-index: var(--cs-z-raised); background: var(--cs-surface)`, and its first column is `position: sticky; left: 0` on `surface`. The matrix uses it. Trash takes only the sideways scroll and the sticky first column (`.admin-table-scroll--x`, with no `max-height`). | Ruling C6. |
| The day bands | `DayListComponent` draws one `<div class="rounded-card bg-surface shadow-1">`. Each day is a `<section aria-labelledby>` whose `h2` is `sticky top-(--admin-top-offset) z-(--cs-z-raised) bg-paper px-4 py-1.5 text-label text-meta`, followed by its `<ul>`. The first band's top corners take the card's radius. | One card (Q19). The card has no `overflow` of its own, so the bands stick to the window. |
| WordDiff's removed words | `WordDiffComponent`'s `:delete` becomes `text-ink bg-sunken line-through decoration-meta`. The `:insert` look is unchanged. This reaches the translation pair's reference card too. | Q21 calls it "the look the translation pair chose". It is one shared component. Red was a danger fill on something that is no failure. |
| The Trash heading | "Today" when `days_left` is 0, "Tomorrow" at 1, and "In %{count} days" otherwise. The first two carry `text-warn-ink`. `RetentionTagComponent` reads `trash_screen.retention_tag.{never,today,tomorrow,in_days,kept,deleted_on}`. | Q11 names "Tomorrow". |
| A security event | `RowComponent` and `EventHeaderComponent` draw `StateChipComponent.new(tone: :warn, label: t(".security"))` before the key (the row), or inside the Action value (the header), when `sentence.security`. The key is `text-meta` always, and `key_class` and `action_class` go. | Q20: colour with words. |
| The type-scale guard | `test/lib/admin_design_rules_test.rb` gains `CONTENT_SIDE_SCREENS`, a list of globs that each screen task grows by its own folders. `test "the content-side screens draw no off-scale size and no hand-drawn box"` refuses `text-\[\d+px\]`, `text-xs`, `rounded-cs border border-line(?:-strong)?\b`, `border-dashed` and `!border-danger` in them, with `HAND_BOX_ALLOWED` (path to reason) admitting the drop overlay's dashed accent frame. | Q2 holds only while something reads it. |

---

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `test/support/design_system_entries.rb`, `ui/record_chip_component.*` (new) with its test and preview, `notes_screen/record_row.rb`, `ui/actor_avatar_component.rb`, `ui/word_diff_component.rb`, `app/views/admin/shared/_icon.html.erb` (`arrow_up`, `arrow_down`), `content-spiel.tailwind.css` (`.admin-tile`, `.admin-table-scroll`), `test/lib/{admin_design_rules,admin_contrast}_test.rb` | the shared parts | 1 |
| `settings_screen/card_component.*` → `ui/settings_card_component.*` (moved), `settings_screen/section_card.rb` (new), the seven Settings cards, `nav_component.rb`, `glance_row_component.rb`, the test and preview (moved), `settings_screen.en.yml`, `ui.en.yml`, `admin_i18n_test.rb` | Q17's frame | 2 |
| `ui/avatar_component.rb`, `ui/presence_marker_component.*`, `presence_screen/people_component.*`, `notes_screen/{avatar,open_thread_row}_component.*`, `posts_screen/table_component.html.erb`, `controllers/admin/presence/list_controller.js`, `content-spiel.tailwind.css` (`.admin-tree-row`, `.admin-presence-marker`, `.admin-notes-threads`) | Q23 | 3 |
| `media_library/{grid,tile,toolbar}_component.*`, `app/views/admin/media/{index,picker}.html.erb`, `app/components/media/picker_component.*`, `app/javascript/media/upload_tiles.js`, `controllers/admin/media/upload_controller.js`, `media_library.en.yml`, `media.en.yml` (new) | the grid, the tiles, the picker and their words | 4 |
| `media_library/panel_component.*`, `app/views/admin/media/index.html.erb`, `ui/rail_slot_component.rb`, `ui/rail_tabs_component.*`, `admin/slots.rb`, `config/initializers/admin_slots.rb`, `notes_screen/media_section_component.*`, `controllers/admin/media/panel_controller.js`, `controllers/admin/notes/drawer_controller.js` (`paint`), `post_form_component.html.erb`, `admin/pages/show.html.erb`, `answers/rail_tab_streams.rb`, `content-spiel.tailwind.css` (`.admin-media-library`, `.admin-media-rail`, the tab bubble), `notes.en.yml` | the media rail | 5 |
| `trash_screen/*`, `app/views/admin/trash/index.html.erb`, `trash_screen.en.yml` (new), `trash.en.yml` (new) | Trash | 6 |
| `translation_screen/{matrix,summary_card}_component.*`, `app/views/admin/translations/index.html.erb`, `translation_screen.en.yml`, `translations.en.yml` (new) | Translations | 7 |
| `forms_screen/{list,builder,field_row,choice_row,destinations,placements,trash_zone,tabs}_component.*`, `forms_screen.en.yml` | the forms list and the builder | 8 |
| `forms_screen/{submissions_list,submission}_component.*`, `app/views/admin/form_submissions/*`, `forms_screen.en.yml` | the submissions | 9 |
| `audit_screen/*`, `app/views/admin/audit_events/*`, `audit_screen.en.yml` (new), `audit_events.en.yml` (new) | the audit log | 10 |
| `docs/reference/{design-system,media,trash,translations,forms,notes,presence,slots,i18n,settings-languages-ai,access-control-and-audit}.md`, `CLAUDE.md`, `CHANGELOG.md` | the reference, the PR and the cards | 11 |

---

### Task 1: The shared parts, and the Design System's copy

**Files:**
- Modify `test/support/design_system_entries.rb`:
  - `VERSION = "1794259911-f251"`;
  - `ENTRIES` gains `StudioAuditLog StudioForms StudioNotesInbox StudioTranslations StudioTrash` (the artifact's five cards that the list lacks);
  - `COVERED_BY["Admin::Ui::RecordChipComponent"] = "IconChip"`.
- Create `app/components/admin/ui/record_chip_component.rb`, as in the decisions table. Contract:
  - `accessibility:` "The chip is hidden from a screen reader; the word beside it, or the caller's own text, names the kind.";
  - `motion: :none`, `content_edges: %i[short long]`, `widths: :fluid`, `interface: %i[kind label]`;
  - `limits:` "It draws only the kinds of KINDS, each the chip of its CS Studio module, and refuses any other." and "It takes no focus and cannot be pressed.";
  - `states: %i[page post media form settings labelled]`, `keys: []`, `slots: []`, `controller: nil`;
  - `keyboard: ["test/system/admin/trash_test.rb", "a trash row's type is its chip and its word, and the keyboard passes from the row's Restore to its Delete now… with no stop on the type"]`.
- Preview `test/components/previews/admin/ui/record_chip_component_preview.rb`, with an example per state.
- Modify `app/components/admin/notes_screen/record_row.rb`: `record_chip(kind)` renders `RecordChipComponent.new(kind:)`, and `MODULES` goes.
- Modify `app/components/admin/ui/actor_avatar_component.rb`: `initialize(actor:, size: :lg)`, with `SLOTS = { lg: "flex size-7 …", sm: "flex size-[22px] …" }`. `interface:` gains `size`, and `limits:` says "It draws in a 28px or a 22px slot.". Its preview gains `small`.
- Modify `app/components/admin/ui/word_diff_component.rb` (decisions table). Its comment says removed words are struck through, not red.
- Modify `app/views/admin/shared/_icon.html.erb`: add `arrow_up` and `arrow_down` (Lucide's paths, 24-box, stroke as the others).
- Modify `app/assets/tailwind/content-spiel.tailwind.css`: add `.admin-tile` and `.admin-table-scroll` (and `--x`), as in the decisions table, each with a comment saying what it draws and who draws it.
- Modify `test/lib/admin_design_rules_test.rb`:
  - add `CONTENT_SIDE_SCREENS = []` (each screen task fills it), `HAND_BOX_ALLOWED = {}`, and the type-scale test (decisions table), with a pattern test whose samples `text-[13px]`, `text-xs`, `rounded-cs border border-line`, `border-dashed` and `!border-danger` match, and `text-small`, `border-b border-line` and `text-xs-foo` do not;
  - add `test "a tile is .admin-tile: elevation 1 at rest, 2 under a pointer, and the accent outline when selected or pressed; never a transform"`.
- Modify `test/lib/admin_contrast_test.rb`:
  - `test "a selected tile's accent outline is 3:1 on surface and on paper"`, with floors 6.8 / 7.0 on surface and 6.2 / 7.8 on paper;
  - `test "removed words are ink on sunken at 4.5:1"`, with floors 14.4 / 11.5.
- Test: `test/components/admin/ui/{record_chip,actor_avatar,word_diff}_component_test.rb`, `test/components/admin/notes_screen/{inbox_row,open_thread_row}_component_test.rb`, `test/components/previews_test.rb`, `test/lib/{component_parts,admin_design_rules,admin_contrast}_test.rb`, `test/components/admin/ui/contract_test.rb`.

**Interfaces:**
- Produces:
  - `Admin::Ui::RecordChipComponent.new(kind:, label: nil)` and `RecordChipComponent::KINDS`;
  - `Admin::Ui::ActorAvatarComponent.new(actor:, size: :lg)`;
  - the classes `.admin-tile`, `.admin-table-scroll` and `.admin-table-scroll--x`;
  - the icons `arrow_up` and `arrow_down`;
  - `CONTENT_SIDE_SCREENS` and `HAND_BOX_ALLOWED`, for Tasks 4 to 10 to grow.

- [ ] **Step 1: Write the failing tests.**
  - `record_chip_component_test.rb`:
    - `test "a kind is its module's chip: pages structure, posts lists, media media, forms form, settings code"`, asserting the family class `IconChipComponent::FAMILIES` names for each;
    - `test "with a label it is the chip and the word, the chip hidden from a screen reader"`;
    - Review Focus 4's test, iterating `TrashScreen::RowComponent::TYPE_KEYS.values` and `Admin::TranslationsController::TYPES.keys` and asserting `ArgumentError` for `"tag"`.
  - `actor_avatar_component_test.rb`: `test "size sm draws the 22px circle in a 22px slot, and an unknown size is refused"`.
  - `word_diff_component_test.rb`: `test "removed words are struck through in ink on sunken, never a danger fill, and keep their Removed cue"`.
  - The guard and contrast tests above.
- [ ] **Step 2: Run them, and verify they fail.** `PGGSSENCMODE=disable bin/rails test test/components/admin/ui test/lib/admin_design_rules_test.rb test/lib/admin_contrast_test.rb test/lib/component_parts_test.rb`.
- [ ] **Step 3: Implement.** Search the tests for `text-danger-ink bg-danger-tint` near a diff and for `MODULES.fetch`, and fix each hit.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components test/lib`.
  - After a build, one file at a time: `admin/translation_status_test.rb` (the diff), `admin/note_inbox_test.rb` (the record chip).
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep and check `pgrep`. Commit `feat: a record kind's chip, the tile, the small actor avatar and struck-through removed words, shared by the content-side screens` (body: `Advances #117`).

---

### Task 2: Settings' card frame becomes a shared component (Q17)

**Files:**
- `git mv` `app/components/admin/settings_screen/card_component.{rb,html.erb}` to `app/components/admin/ui/settings_card_component.{rb,html.erb}`, and its test and preview to `test/components/admin/ui/settings_card_component_test.rb` and `test/components/previews/admin/ui/settings_card_component_preview.rb`. The class becomes `Admin::Ui::SettingsCardComponent` (decisions table).
  - The template renders `IconChipComponent.new(icon:, family:, size: :small)` and `h2#heading_id` with `heading`.
  - The section's classes stay `admin-settings-card rounded-card bg-surface shadow-1`, and the head stays `bg-rail`.
  - Contract:
    - `accessibility:` "A section named by its heading; it takes no focus of its own.";
    - `motion: :none`, `content_edges: %i[none long]`, `widths: :from_container`, `interface: %i[heading_id heading icon family intro head_end head_note heading_mark]`;
    - `limits:` "It says nothing of its own: the heading and the intro are the caller's, already read." and "An id in html is the section's; a class is appended.";
    - `states: %i[rest intro head_end head_note heading_mark]`, `keys: []`, `slots: %i[head_end head_note heading_mark]`, `controller: nil`;
    - `keyboard: ["test/system/admin/form_builder_test.rb", "a builder card takes no Tab stop: the keyboard goes from the form's name field to its first field's controls"]`.
- Create `app/components/admin/settings_screen/section_card.rb` (decisions table).
- Modify the seven `settings_screen/*_card_component.html.erb` to render the shared frame with `SectionCard.options`. `publishing_card` passes `id: "settings-publishing-card"`. Modify `nav_component.rb:29` and `glance_row_component.rb:62` to call `SectionCard.word_key`.
- Modify `app/values/settings_sections.rb:2` and `app/views/admin/settings/show.html.erb:4` (their comments) to name the new frame.
- Modify `test/support/design_system_entries.rb`: `COVERED_BY["Admin::Ui::SettingsCardComponent"] = "StudioSettings"`.
- Modify `test/lib/admin_i18n_test.rb:123–124`: the two paths follow the move, and `section_card.rb` joins.
- Test: the moved test, `test/components/admin/settings_screen/*_test.rb`, `test/integration/admin/settings_test.rb`, `test/components/previews_test.rb`, `test/lib/{component_parts,source_layout,admin_i18n}_test.rb`, `test/components/admin/ui/contract_test.rb`.

**Interfaces:**
- Produces `Admin::Ui::SettingsCardComponent.new(heading_id:, heading:, icon:, family:, intro: nil, **html)` with the slots `head_end`, `head_note` and `heading_mark`, and `Admin::SettingsScreen::SectionCard.options(section, view)` and `.word_key(section)`. Tasks 8 and 9 render the frame.

- [ ] **Step 1: Write the failing tests.** In the moved test:
  - `test "the card is a section named by its heading, whose id is the caller's"`, a rewrite of the section-anchor test;
  - `test "it knows no Settings section: heading, icon and family are handed in"`, which renders it with `heading_id: "form-card-fields"`, `icon: :clipboard_list` and `family: :form`;
  - keep "the card has no border of its own and its head is the rail's ground".
  - In `settings_test.rb`: "every card is drawn by the card frame, in the nav's order, for the rights the viewer holds" keeps passing.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Then `git grep -n "SettingsScreen::CardComponent\|settings_screen/card_component" -- app test config docs/reference CLAUDE.md` prints nothing (Task 11 rewrites the two reference lines).
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components test/lib test/integration/admin/settings_test.rb`, and `bin/rails zeitwerk:check`.
  - After a build: `admin/settings_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `ref: Settings' card frame is the shared Admin::Ui::SettingsCardComponent` (body: `Advances #117`).

---

### Task 3: Avatar stacks side by side, and a title that keeps its room (Q23)

**Files:**
- Modify `app/components/admin/ui/avatar_component.rb`:
  - `RINGS` and the `ring:` keyword go. Every caller of a ring is a stack, which this task stops overlapping (checked while planning: `PeopleComponent`, `PresenceMarkerComponent`, `NotesScreen::AvatarComponent` through `OpenThreadRowComponent`).
  - `.new(initials:, size:, tone: :other, here: false)`.
  - `interface:` and `limits:` drop rings, and the preview drops its ring examples.
- Modify `app/components/admin/notes_screen/avatar_component.rb`: `ring:` goes.
- Modify `app/components/admin/presence_screen/people_component.{rb,html.erb}`: `Size` loses `ground`, the circles stand in `flex gap-0.5` (2px), and every `-ml-1.5` goes.
- Modify `app/components/admin/notes_screen/open_thread_row_component.html.erb`: the same, with `gap-0.5` and no `-ml-1.5`.
- Modify `app/components/admin/ui/presence_marker_component.{rb,html.erb}`:
  - the circles and the two "+N" stand 2px apart (`gap-0.5` on the root);
  - a fourth part, `data-presence-count`: `AvatarComponent.new(initials: count_label, size: :sm, tone: :more)`, where `count_label` is the count, or `ui.avatar.many` ("9+") above 9;
  - `states:` gains `one_count`, and `limits:` gains "Under 200px of its tree row it is one circle holding the count.".
- Modify `app/javascript/controllers/admin/presence/list_controller.js` `show()`: it writes `[data-presence-count]`'s circle text (the count, or `messages(marker).t("ui.avatar.many")` above 9) beside what it writes today, as text, only where it differs.
- Modify `app/assets/tailwind/content-spiel.tailwind.css`:
  - `.admin-presence-marker`'s negative margin goes, and so do `--admin-avatar-ground` on `.admin-tree-row`, `:hover`, `--selected` and `.admin-notes-threads` (both blocks), and `hover:[--admin-avatar-ground…]` and `data-[selected]:[--admin-avatar-ground…]` in `posts_screen/table_component.html.erb`;
  - `.admin-tree-row` gains `container: admin-tree-row / inline-size`;
  - `.admin-tree-row__title` becomes `flex: 1 1 7rem; min-width: 7rem`, and `.admin-tree-row__trailing` (and the markers in it) `flex-shrink: 0`;
  - `.admin-presence-marker > [data-presence-count]` is `display: none`, and `@container admin-tree-row (max-width: 200px)` hides every other part of the marker and shows the count;
  - the comment above the marker says the circles stand apart, the column rule (260px) decides the usual case, and the row rule is the floor.

  First check that the tree's geometry guard ("a tree's geometry is its four tokens, written once") and `tree_item_parity_test` allow a row to be a size container and its title a basis of `7rem`. If either refuses, report NEEDS_CONTEXT.
- Modify `test/lib/admin_design_rules_test.rb:850–855, 969–974`: the ground assertions go. Add:
  - `test "an avatar stack never overlaps and draws no ground ring"`, which refuses `-ml-` beside an `AvatarComponent` render in `app/components`, a negative `margin-inline-start` in `.admin-presence-marker` rules, and `--admin-avatar-ground` anywhere;
  - `test "a tree row's title keeps 7rem and the marker gives way to one count circle under 200px of the row"`.
- Test:
  - `test/components/admin/ui/{avatar,presence_marker}_component_test.rb`, `test/components/admin/presence_screen/people_component_test.rb`, `test/components/admin/notes_screen/open_thread_row_component_test.rb`, `test/lib/admin_design_rules_test.rb`;
  - browser `admin/presence_lists_test.rb`, `admin/presence_test.rb`, `admin/note_inbox_test.rb`.

**Interfaces:**
- Produces `Admin::Ui::AvatarComponent.new(initials:, size:, tone: :other, here: false)`. The marker's `[data-presence-count]` is the fourth part `admin--presence--list` writes.

- [ ] **Step 1: Write the failing tests.**
  - `avatar_component_test.rb`: "here adds the inner people ring, and a ground ring is drawn outside it" becomes `test "here adds the inner people ring, and there is no outer ring"`. "an unknown size, tone or ring is refused" becomes "an unknown size or tone is refused", plus `assert_raises(ArgumentError) { AvatarComponent.new(initials: "DW", size: :sm, ring: :paper) }`.
  - `presence_marker_component_test.rb`: `test "the circles and +N stand 2px apart with no ring, and the count circle holds the number, 9+ past nine"`.
  - `people_component_test.rb`:
    - "here before away, each in order of arrival, each circle over the one before by 6px" becomes `"… each circle 2px after the one before"`;
    - the "paper ring" and "ring in the surface colour" assertions go from the tests at :49 and :220.
  - `presence_lists_test.rb`:
    - the test at :142's measure (`overlap` at :123) asserts `2` and its ring check at :173 goes;
    - `test "two circles and +N take 70px on a posts row, and one circle and +N take 46px in a narrow tree column"`;
    - Review Focus 5's test.
  - `presence_test.rb`: wherever it measures the panel's circles or reads a ring (:173 keeps the here ring; the ring at :482–486 goes), assert a 2px gap.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** `git grep -n "admin-avatar-ground\|RINGS\|ring: :" -- app test` prints only `ContentTypeDotComponent::RINGS` and the mind graph's dot classes.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components test/lib`.
  - After a build, one file at a time: `admin/presence_lists_test.rb`, `admin/presence_test.rb`, `admin/note_inbox_test.rb`, `admin/tree_test.rb`, `admin/tree_item_parity_test.rb`, `admin/posts_list_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `fix: avatar stacks stand side by side, and a tree row's title keeps 7rem before its people give way to one count` (body: `Advances #117`).

---

### Task 4: The media grid, its tiles, the picker, and their words (Q8, Q9, Q22)

**Files:**
- Modify `app/components/admin/media_library/tile_component.{rb,html.erb}`:
  - `CARD` becomes `"admin-tile group block w-full overflow-hidden text-left focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"`, and `PICK_CARD = CARD`;
  - `card_class` goes, and the selected look is `.admin-tile`'s from `aria-current` / `aria-pressed`;
  - the face's box draws the blurred preview (decisions table);
  - "No alt" and "Unused" read `t(".no_alt")` and `t(".unused")`.
- Modify `grid_component.html.erb`: its empty states read `grid.empty.{title,description,picker_description,no_matches,no_matches_description,clear}`.
- Modify `toolbar_component.{rb,html.erb}`: `SEGMENTS`' labels become keys (`toolbar.segments.{all,unused,missing_alt,untranslated,mine}`), as do the search's label and placeholder, "Show", "Filter" and "Clear".
- Modify `app/views/admin/media/index.html.erb`: "Media", "Upload images", the hint and "Drop images to upload" read `admin.media.index.*`. The upload controller's `button-class` value becomes `tile-class` and `button-class`, and its `data-messages` carries the upload keys (decisions table).
- Modify `app/views/admin/media/picker.html.erb` and `app/components/media/picker_component.*` only where they draw a tile, a literal or a hand-drawn edge.
- Modify `app/javascript/media/upload_tiles.js` and `controllers/admin/media/upload_controller.js`: `TEXTS` goes, and `buildTile(name)` takes the tile class and the words from the controller.
- Create `config/locales/admin/media.en.yml`. Grow `media_library.en.yml` (`tile`, `grid`, `toolbar`, `uploads`).
- Modify `test/lib/admin_i18n_test.rb`: `CONVERTED` gains `media_library/{grid,tile,toolbar}_component.*`, `app/views/admin/media/{index,picker}.html.erb` and `app/javascript/media/upload_tiles.js`. Add the script to `test/lib/script_messages_test.rb`'s list if it names one.
- Modify `test/lib/admin_design_rules_test.rb`:
  - `CONTENT_SIDE_SCREENS` gains `app/components/admin/media_library/*`, `app/views/admin/media/*` and `app/components/media/picker_component.*`;
  - `HAND_BOX_ALLOWED` gains `app/views/admin/media/index.html.erb` ("the drop overlay's dashed accent frame: creating is violet").
- Test:
  - `test/components/admin/media_library/{tile,grid,toolbar}_component_test.rb`, `test/components/media/picker_component_test.rb`, `test/integration/admin/media_*_test.rb`;
  - browser `admin/media_library_test.rb`, `admin/media_picker_test.rb`.

**Interfaces:**
- Consumes `.admin-tile` (Task 1).
- Produces `TileComponent::CARD` (one string for both modes). Task 5 keeps the tile's `dom_id`.

- [ ] **Step 1: Write the failing tests.**
  - `tile_component_test.rb`:
    - "the selected tile has aria-current and the accent ring; others have neither" becomes `test "every tile is .admin-tile with no border; the selected one has aria-current, and only it"`;
    - "the size shows in mono once the dimensions are known" becomes `test "the size shows as a label once the dimensions are known"`, asserting `text-label`;
    - `test "a tile with a made width draws the blurred preview under its thumbnail, hidden from a screen reader; one with no preview draws none"`.
  - `grid_component_test.rb`: `test "the empty states are keys, and the filtered one offers Clear filters"`.
  - `media_library_test.rb` (browser): `test "a tile rises under the pointer, and the chosen one has the accent outline 2px out"`, which reads the computed `box-shadow` (it equals `--cs-shadow-2`'s resolved value) and the outline's width and offset.
  - `media_picker_test.rb`: `test "the picker's tiles are the library's: a pressed tile has the accent outline, and the columns stay 2 to 6"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests for `border-accent ring-[3px]`, `aria-pressed:ring`, `rounded-cs border`, `TEXTS`, and English the tests read (they keep it: the keys hold the same words). Fix each hit.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components test/lib test/integration/admin`.
  - After a build, one file at a time: `admin/media_library_test.rb`, `admin/media_picker_test.rb`, `admin/filter_bar_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: the media grid's tiles stand at elevation 1 with the accent outline when chosen, and its words are keys` (body: `Advances #117`).

---

### Task 5: The media rail, with Image · Notes (Q4–Q7)

**Files:**
- Modify `app/views/admin/media/index.html.erb` into the markup of the decisions table. `admin--media--panel` sits on `.admin-media-library__grid`. The rail is drawn only with a tile selected. The view never names notes.
- Modify `app/components/admin/media_library/panel_component.{rb,html.erb}` into the Image tab's content, in Q6's order:
  - the title `text-h2` in `#media-panel-title`, keeping `title_content`;
  - the head row is the title and the `media.panel.header` slot, with `pr-10` for Close;
  - the preview's frame is `rounded-tile bg-sunken overflow-hidden`, with no border;
  - the facts' values are `text-ink`;
  - Download original is `ButtonComponent.classes(:tertiary, size: :small)`;
  - "Used on" rows render `RecordChipComponent.new(kind:)` before the title link, and its heading is `text-h3`;
  - the trash zone is a `border-t border-line` rule, then the button (ruling C3);
  - every literal becomes a key (`panel.*`): the facts, "Used on", its three sentences, `in_use_reason`, `retention_help`, `trash_only_message`, `ROLE_LABELS`, the view-only labels and sentence, `ALT_PLACEHOLDER`, the dialog's words and "Close panel".

  `close_path` and the "×" move out of the panel to the rail (decisions table, "Close"). `#media-panel` keeps its id, `tabindex="-1"` and its target.
- Modify `app/components/admin/ui/rail_slot_component.rb` (`slot:`) and its callers (decisions table, "The rail's slot"). `interface:` gains `slot`.
- Modify `app/components/admin/slots.rb` (`NAMES` gains `media.rail.tabs`), and `config/initializers/admin_slots.rb`.
- Modify `app/components/admin/notes_screen/media_section_component.{rb,html.erb}`:
  - it answers the tab methods;
  - its heading carries `admin-media-rail__section-heading`, hidden where the rail docks;
  - with no thread and a viewer who may write, the frame's empty list says `t("admin.components.notes_screen.rail_panel.empty_image")` ("No notes on this image yet.") over the composer. Find where the frame's list draws its empty line (`notes_screen/list_component`) and give it the record's noun for an image.
- Modify `app/components/admin/ui/rail_tabs_component.html.erb` and `rail_tab_component.rb`: the count span gains `data-tab-count`. Modify `controllers/admin/notes/drawer_controller.js#paint` (decisions table, "The Notes tab's bubble"). The editors' `NotesScreen::RailPanelComponent#tab_count_data` and `MediaSectionComponent#tab_count_data` add `notes_total_words: true`. Add `admin.notes.script.marker.new` if it is not there (stage 6 added it).
- Modify `app/javascript/controllers/admin/media/panel_controller.js`: add `escape(event)` (decisions table, "Escape"). `close` and `moveFocus` are unchanged, and the tile's selector follows `TileComponent`.
- Modify `app/assets/tailwind/content-spiel.tailwind.css`:
  - `.admin-media-library` and its two container blocks, `.admin-media-rail` and its Close (decisions table);
  - the tab bubble's rule, `[data-tab-count]` and `[data-unread]` (people tint and people ink, accent and on-accent), joining `PEOPLE_RULES` in the design rules test.
- Modify `test/lib/admin_design_rules_test.rb`:
  - "…dock at one threshold" gains `assert_equal [ "1200px", "760px" ].sort, css.scan(/@container admin-media \(min-width: ([^)]+)\)/).flatten.sort`;
  - "every docked composition and its head row centre past --cs-content-max" gains `"admin-media" => [ ".admin-media-library__head", ".admin-media-library__grid" ]`, and its `outside` list gains `admin-media`;
  - "every docked composition grows to --cs-content-max…" gains `"admin-media" => /\.admin-media-library__grid\s*\{([^}]*)\}/`;
  - `test "the Media screen's panel is laid out by the library's own width, never a window media query"` refuses `lg:` in `app/views/admin/media/index.html.erb` and any `@media` naming `admin-media`.
- Modify `test/lib/notes_boundary_test.rb` only if the media view is not yet held clear of the word "notes". Add it if missing.
- Test:
  - `test/components/admin/media_library/panel_component_test.rb`, `test/components/admin/ui/{rail_slot,rail_tabs}_component_test.rb`, `test/components/admin/notes_screen/media_section_component_test.rb`, `test/components/admin/slots_test.rb`, `test/controllers/admin/answers/rail_tab_streams_test.rb`, `test/components/admin/editor_screen/post_form_component_test.rb`, `test/lib/{admin_design_rules,notes_boundary,admin_i18n}_test.rb`, `test/integration/admin/media_*_test.rb`;
  - browser `admin/media_library_test.rb`, `admin/presence_test.rb` (the panel's row), `admin/note_files_test.rb`, `admin/notes_rail_test.rb`.

**Interfaces:**
- Consumes `RecordChipComponent` (Task 1) and `TileComponent.dom_id` (Task 4).
- Produces `RailSlotComponent.new(slot:, rail_id:, record:, viewer:, reserved: [], **context)` and the slot `media.rail.tabs`. Every caller of `RailSlotComponent` passes `slot:`.

- [ ] **Step 1: Write the failing tests.**
  - `rail_slot_component_test.rb`: `test "it draws the tabs registered at the slot it is told, and none of another slot's"`. Its existing tests pass `slot: "editor.rail.tabs"`.
  - `media_section_component_test.rb`:
    - `test "it is the Notes tab: key notes, its label, the open count as the drawer's total that speaks new, current with notes=open or a thread"`;
    - `test "with no thread a writer sees No notes on this image yet. over the composer, and a reader the line alone"` (integration, if the empty line is drawn by the frame's answer).
  - `panel_component_test.rb`:
    - `test "the Image tab: the title in text-h2, a borderless preview, the facts, Download original, the tabs, the wells, Used on with each record's chip, the sections slot, then the trash after a rule"`;
    - `test "the panel draws no close of its own; the rail does"`.
  - `media_library_test.rb` (browser):
    - Review Focus 1 and 2's tests;
    - `test "Image and Notes are tabs where the rail docks: arrows move between them, Home and End go to the ends, and the Notes tab's bubble says 2 new while unread"`;
    - "by keyboard: choosing a tile moves focus into the panel, and closing it returns focus to that tile; a plain load steals none" keeps passing, with Close found by its name "Close panel".
  - `presence_test.rb`: the panel's row measurement at :482–490 now asserts the people stand 8px after the name and Close is the rail's last child, top-right (`closeLast`, with `beforeClose` gone).
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests for `lg:grid-cols-[minmax(0,1fr)_340px]`, `"×"`, `media.panel.sections` with notes, `#media-notes h3`, `NOTES · `, `text-lg font-semibold`, and `RailSlotComponent.new(` without `slot:`. Fix each hit. Then `git grep -n "Admin::Slots.entries(\"editor.rail.tabs\")" -- app` prints nothing.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components test/lib test/controllers test/integration/admin`.
  - After a build, one file at a time: `admin/media_library_test.rb`, `admin/presence_test.rb`, `admin/note_files_test.rb`, `admin/notes_rail_test.rb`, `admin/editor_rail_test.rb`, `admin/notes_drawer_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: the media panel is a rail with Image and Notes tabs where the library has the room` (body: `Advances #117`, `Advances #127` (a second host of the rail's panel slot)).

---

### Task 6: Trash (Q10–Q12)

**Files:**
- Modify `app/views/admin/trash/index.html.erb`:
  - the heading row is "Trash" with Empty trash at its end, wrapping below 640px;
  - the retention line is `text-small text-meta`, and "Change" is `ButtonComponent.classes(:tertiary, size: :small)`;
  - every word is `admin.trash.index.*`.
- Modify `trash_screen/list_component.{rb,html.erb}`:
  - the table sits in `.admin-table-scroll--x` inside the card, its Item column sticky;
  - `who_actor(item)` (decisions table);
  - `YOU`, `EMPTY_STATES`, `HIDDEN_ITEMS`, the subpage sentence and the column heads become keys (`list.*`). "(untitled)" reads `list.untitled`.
- Modify `row_component.{rb,html.erb}`:
  - `actor:` arrives, and Trashed is `ActorAvatarComponent.new(actor:, size: :sm)`, the name, and "· " with the time;
  - Type is `RecordChipComponent.new(kind: type_key, label: t(".types.#{type_key}"))`;
  - the image's thumbnail is `size-10 rounded-tile`;
  - the title is `font-medium`;
  - Restore is `size: :small`;
  - `TYPE_LABELS`, `NO_PARENT`, `in_use_reason`, the purge dialog's words and "Restore under" become keys.
- Modify `retention_tag_component.rb` (decisions table, "The Trash heading") and `empty_trash_component.*`, `tabs_component.*` (`TABS`' labels, and "Filter by type": `tabs.label`).
- Create `config/locales/admin/trash_screen.en.yml` and `config/locales/admin/trash.en.yml`.
- Modify `test/lib/admin_i18n_test.rb` (`CONVERTED`: the five components and the view) and `test/lib/admin_design_rules_test.rb` (`CONTENT_SIDE_SCREENS`: `trash_screen/*`, `app/views/admin/trash/*`).
- Modify `test/lib/admin_contrast_test.rb`: `test "a retention of today or tomorrow is warn ink at 4.5:1 on surface and on paper"`, with floors 7.6 / 9.8.
- Test: `test/components/admin/trash_screen/*_test.rb`, `test/integration/admin/trash_*_test.rb`, browser `admin/trash_test.rb`.

**Interfaces:**
- Consumes `RecordChipComponent`, `ActorAvatarComponent(size: :sm)` and `.admin-table-scroll--x` (Task 1).
- Produces `TrashScreen::RowComponent.new(item:, retention_days:, who:, actor:, …)`.

- [ ] **Step 1: Write the failing tests.**
  - `retention_tag_component_test.rb`: `test "today and tomorrow are words in warn ink, a later day In N days in meta, and never is Never"`.
  - `row_component_test.rb`:
    - `test "the type is the kind's chip and its word, the trasher a small avatar beside the name"`;
    - `test "an image's thumbnail is 40px on the tile radius"`.
  - `list_component_test.rb`: `test "the table scrolls sideways inside its card with the Item column sticky"`.
  - `trash_test.rb` (browser):
    - the keyboard test named in Task 1's contract;
    - "tabs carry their counts, and a page whose parent is in the trash restores under a chosen one" keeps passing.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests for `"In 1 day"`, `text-meta` on the type cell, `font-semibold text-ink` on a title, and `size-12`. Fix each hit.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components test/lib test/integration/admin test/integration/trash_visibility_test.rb`.
  - After a build: `admin/trash_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: Trash takes E4: the type as its chip, who trashed it as an avatar, and today and tomorrow in words` (body: `Advances #117`).

---

### Task 7: Translations (Q13–Q15)

**Files:**
- Modify `app/views/admin/translations/index.html.erb`:
  - the intro and its sentence, "Type", "All", "Filter" and "Clear" are `admin.translations.index.*`;
  - the summary row is `grid-cols-[repeat(auto-fit,minmax(15rem,1fr))] gap-3`, unchanged;
  - the segments' labels are `index.types.<type>` ("Pages", "Images", "Site settings"), and the matrix's are `matrix.types.<type>` ("Page"). `Admin::TranslationsController::TYPES` keeps only `permission:`, and `label:` and `short:` go with no alias. Their readers are the view, `MatrixComponent#type_label` and any test that reads them.
- Modify `translation_screen/summary_card_component.{rb,html.erb}`:
  - the whole tile is the link (`.admin-tile flex flex-col gap-2 px-4 py-3.5`, `aria-current`), with no border;
  - the name is `text-sm font-semibold`, "72% done" is `text-label text-meta`, and the bar is `h-1 rounded-full bg-sunken` with `bg-ok` inside;
  - the line is "↻ 3 outdated" in `text-warn-ink` or "12 missing" in `text-meta`, or "All translated";
  - `link_label` and `counts`' words become `summary_card.*` keys.
- Modify `matrix_component.{rb,html.erb}`:
  - the scroller is `.admin-table-scroll`;
  - the Type cell is `RecordChipComponent.new(kind: item.type, label: t(".types.#{item.type}"))`;
  - the verb is `text-dim group-hover:text-accent group-focus-within:text-accent` (the row gains `group`);
  - "Item", "Type", "Action", "Everything is translated." and "Site settings · title, tagline" become keys.
- Modify `test/lib/admin_design_rules_test.rb`:
  - `CONTENT_SIDE_SCREENS` gains `translation_screen/{matrix,summary_card}_component.*` and `app/views/admin/translations/*`;
  - `STATUS_FILL_FILES` keeps `summary_card_component.html.erb` (`bg-ok`, the bar).
- Modify `test/lib/admin_contrast_test.rb`: `test "a language tile's ok bar is 3:1 on its sunken track"`, with floors 4.2 / 5.7.
- Modify `test/lib/admin_i18n_test.rb` (`CONVERTED`).
- Test: `test/components/admin/translation_screen/*_test.rb`, `test/integration/admin/translations_*_test.rb`, browser `admin/translations_test.rb`, `admin/translation_status_test.rb`.

**Interfaces:**
- Consumes `.admin-tile`, `.admin-table-scroll` and `RecordChipComponent` (Task 1).

- [ ] **Step 1: Write the failing tests.**
  - `summary_card_component_test.rb`:
    - `test "a language is one tile link with no border; the current one has aria-current"`;
    - `test "the bar is ok on a sunken track, and outdated says ↻ with its count in warn ink, missing its count in meta"`.
  - `matrix_component_test.rb`: `test "a row's type is the kind's chip and its word, and the table scrolls inside its own bounded box"`.
  - `translations_test.rb` (browser): Review Focus 3's test, and the test at :488 is folded into it.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests for `border-accent` on a summary, `underline decoration-accent`, `bg-line` on a bar, `isolate overflow-x-auto` and `data-translation-matrix-scroll`. Fix each hit, and keep the `data-` hook if a test reads it.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components test/lib test/integration/admin`.
  - After a build, one file at a time: `admin/translations_test.rb`, `admin/translation_status_test.rb`, `admin/filter_bar_test.rb`, `admin/dashboard_test.rb` (it links to `?language=`).
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: Translations takes E4: a tile per language, the matrix in one card with a sticky head, and each type as its chip` (body: `Advances #117`).

---

### Task 8: The forms list and the builder (Q16, Q17)

**Files:**
- Modify `forms_screen/list_component.{rb,html.erb}`:
  - the Submissions cell shows the count, then `StateChipComponent.new(tone: :warn, label: t(".not_delivered", count:))` ("%{count} not delivered") in place of the warn Badge;
  - the table sits in `.admin-table-scroll--x`;
  - `WARN_CLASS` keeps the warn box and loses any `danger`.
- Modify `builder_component.{rb,html.erb}`:
  - the Form, Fields and After submitting cards render `Admin::Ui::SettingsCardComponent.new(heading_id: "form-card-<name>", heading: t(".<name>_card"), icon: :clipboard_list, family: :form)`;
  - `CARD_CLASS` and `CARD_HEAD_CLASS` go;
  - the name field's error is `aria: { invalid: true }` and the shared invalid edge, not `!border-danger`;
  - "Add a field" is `div.rounded-tile.bg-paper.p-3` with `p.text-label.text-meta` "Add a field" (`.add_field`, its value changed) over the type buttons;
  - `text-[13px]` becomes `text-small`.
- Modify `destinations_component.*` and `placements_component.*` the same way (`heading_id: "form-destinations"`, `"form-placements"`).
- Modify `field_row_component.{rb,html.erb}`:
  - the row is `admin-form-field-row rounded-tile bg-paper`, with no shadow, and its head has no `border-b`;
  - "Required" is `text-label text-meta`;
  - ↑ and ↓ are `ButtonComponent.new(label: t(".up", label:), icon: :arrow_up, variant: :tertiary, size: :small)` and the `arrow_down` twin (the icon button's name is its label, so the `aria-label` goes);
  - the invalid edge is the shared one;
  - the type's Badge, the label and Remove stay.
- Modify `choice_row_component.*`: ↑ ↓ the same, and `text-[13px]` becomes `text-small`.
- Modify `trash_zone_component.{rb,html.erb}`: the zone is `border-t border-line pt-4 mt-2` at the end of the column, with its heading `text-h3`, its body `text-small text-dim` and the button. Its words stay (ruling C4).
- Modify `forms_screen.en.yml`: `list.not_delivered` (one/other), and `builder.add_field` "Add a field".
- Modify `app/javascript/controllers/admin/forms/builder_controller.js` only if it reads `.border-b`, `CARD_CLASS` or the ↑ ↓ text. Search it first.
- Modify `test/lib/admin_design_rules_test.rb`:
  - `CONTENT_SIDE_SCREENS` gains `forms_screen/*` and `app/views/admin/forms/*`;
  - `STATUS_FILL_FILES` loses `forms_screen/list_component.rb` if it no longer draws a fill (its stale-entry test says so).
- Test: `test/components/admin/forms_screen/{list,builder,field_row,choice_row,destinations,placements,trash_zone}_component_test.rb`, `test/integration/admin/forms_*_test.rb`, browser `admin/form_builder_test.rb`.

**Interfaces:**
- Consumes `SettingsCardComponent` (Task 2), `StateChipComponent`, and the icons `arrow_up` / `arrow_down` (Task 1).

- [ ] **Step 1: Write the failing tests.**
  - `builder_component_test.rb`:
    - `test "the builder's cards are the shared card frame with the form chip, and no card draws its own head"`;
    - `test "Add a field is a paper well titled in a label, its types secondary buttons, with no dashed edge"`;
    - `test "an invalid name is aria-invalid with the shared edge, never a danger border"`.
  - `field_row_component_test.rb`: `test "a field is a paper row on the tile radius; up and down are icon buttons named by their labels"`.
  - `list_component_test.rb`: `test "a form with failed deliveries says 2 not delivered in a warn state chip, never a badge or red"`.
  - `form_builder_test.rb` (browser): Task 2's keyboard test. "add three fields, move the last to the top, remove one, Save…" keeps passing with the icon buttons found by their names.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests for `CARD_CLASS`, `border-dashed`, `!border-danger`, `"↑"`, `"↓"`, `admin-delete-zone`, `rounded-card bg-surface shadow-1` on a field row, and `BadgeComponent` in the list. Fix each hit.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components test/lib test/integration/admin`.
  - After a build, one file at a time: `admin/form_builder_test.rb`, `admin/trash_test.rb` (a form's trash), `admin/settings_test.rb` (the frame).
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: the forms list and builder take E4: Settings' card frame, fields as paper rows, and a failed delivery as a warn state` (body: `Advances #117`).

---

### Task 9: A form's submissions, and one submission (Q18)

**Files:**
- Modify `forms_screen/submissions_list_component.{rb,html.erb}`:
  - the keeping line is `text-small text-meta`, and "Delete all…" stays `danger_text`;
  - in one card with `.admin-table-scroll--x`: Received (a time link), Summary, Language (a neutral `BadgeComponent`), Page, and a `StateChipComponent :warn` "Not delivered" on a row whose delivery failed.
- Modify `submission_component.{rb,html.erb}`:
  - the Answers and Deliveries cards render `SettingsCardComponent` (`heading_id: "submission-answers"` and `"submission-delivery"`, `icon: :clipboard_list`, `family: :form`), and `CARD_CLASS`, `CARD_HEAD_CLASS`, `CHIP_CLASS` and `chip_border` go;
  - the answers' values are `text-body`;
  - a delivery's state is `StateChipComponent`: `:ok` "Sent" with `detail:` the time ("14:05"), `:off` "Waiting" or "Sending", `:warn` "Not delivered";
  - the reason is `text-small text-warn-ink`, and Send again is `:secondary, size: :small`;
  - the delete zone is a `border-t border-line` rule, then its words and button.
- Modify `app/views/admin/form_submissions/*` only for a literal or a hand-drawn edge.
- Modify `forms_screen.en.yml`: `submission.states.{sent,waiting,sending,not_delivered}` and `submissions_list.not_delivered`.
- Modify `test/lib/admin_design_rules_test.rb`:
  - `CONTENT_SIDE_SCREENS` gains `app/views/admin/form_submissions/*`;
  - `STATUS_FILL_FILES` loses `submission_component.html.erb` once its dots go.
- Modify `test/lib/admin_contrast_test.rb` only if `StateChipComponent`'s ok and warn pairs are not measured yet: floors 7.0 / 8.0 (ok) and 6.5 / 8.3 (warn).
- Test: `test/components/admin/forms_screen/{submissions_list,submission}_component_test.rb`, `test/integration/admin/form_submissions_*_test.rb`, browser `admin/form_builder_test.rb` (the Submissions tab).

**Interfaces:**
- Consumes `SettingsCardComponent` (Task 2) and `StateChipComponent`.

- [ ] **Step 1: Write the failing tests.**
  - `submission_component_test.rb`:
    - `test "each delivery's state is a state chip in its word: Sent with its time, Waiting, Sending, Not delivered in warn, never red"`;
    - `test "the answers and deliveries are the shared card frame, and the delete zone is a rule, not a box"`.
  - `submissions_list_component_test.rb`: `test "a submission whose delivery failed says Not delivered in a warn state chip, and its language is a neutral badge"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests for `data-delivery-state` (kept), `chip_border`, `bg-ok` or `bg-warn` in a delivery, and `admin-delete-zone`. Fix each hit.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components test/lib test/integration/admin`.
  - After a build: `admin/form_builder_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: a form's submissions and deliveries say their state with the state chip, in the shared card frame` (body: `Advances #117`).

---

### Task 10: The audit log (Q19–Q21)

**Files:**
- Modify `app/views/admin/audit_events/index.html.erb`:
  - the heading, the empty states and "Newer" / "Load older" are `admin.audit_events.index.*`;
  - "Newer" and "Load older" take `ButtonComponent.classes(:tertiary, size: :small)`, in a row under the card.
- Modify `audit_screen/toolbar_component.{rb,html.erb}`:
  - the subject chip is the chip input's chip, with its × button. `ChipInputComponent#chip_class(chip)` builds that chip's classes today. Lift its fixed part into `ChipInputComponent::CHIP_CLASS`, and have both the chip input and the toolbar read it;
  - `CHANNELS` and `DATES` labels and the selects' blanks become keys (`toolbar.*`).
- Modify `day_list_component.{rb,html.erb}` (decisions table, "The day bands"). `label_for`'s "Today" and "Yesterday" become keys if they are literals.
- Modify `row_component.{rb,html.erb}`:
  - the time is `w-28 shrink-0 text-label text-meta tabular-nums`;
  - `ActorAvatarComponent.new(actor:, size: :sm)`;
  - the sentence is `text-sm text-ink`, with the names at `font-medium` in `SentenceComponent`;
  - the security chip comes before the key (decisions table), and the key is `font-cs-mono text-label text-meta`;
  - the time link's `aria-label` ("%{time}, details of this change") becomes a key.
- Modify `event_header_component.{rb,html.erb}`:
  - the breadcrumb is `text-label`;
  - the facts card is a `dl` grid whose cells are divided by `line` inside the card and not on its outer edge, the way the implementer chooses (for example, `gap-px bg-line` behind cells on `surface`, inside `overflow-hidden rounded-card`), with no `border-r` on a last column;
  - the Action value carries the security chip, and the cell labels become keys.
- Modify `changes_component.{rb,html.erb}`: "Changes", "Field", "Before", "After", "Changed" and "No field changes recorded." become keys, and Field is `font-cs-mono text-label`.
- Modify `sentence_component.rb` only for the names' weight.
- Create `config/locales/admin/audit_screen.en.yml` and `config/locales/admin/audit_events.en.yml`.
- Modify `test/lib/admin_design_rules_test.rb`:
  - `CONTENT_SIDE_SCREENS` gains `audit_screen/*` and `app/views/admin/audit_events/*`;
  - `MONO_ALLOWED` keeps its three audit entries.
- Modify `test/lib/admin_contrast_test.rb`: `test "a day band's date is meta at 4.5:1 on paper"`, with floors 5.7 / 7.0.
- Modify `test/lib/admin_i18n_test.rb` (`CONVERTED`).
- Test: `test/components/admin/audit_screen/*_test.rb`, `test/integration/admin/audit_*_test.rb`, browser `admin/audit_log_test.rb`, `admin/filter_bar_test.rb`.

**Interfaces:**
- Consumes `ActorAvatarComponent(size: :sm)` (Task 1), `StateChipComponent`, and `WordDiffComponent`'s removed look (Task 1).

- [ ] **Step 1: Write the failing tests.**
  - `day_list_component_test.rb`: `test "every day is a sticky paper band inside one card, never a card per day"`.
  - `row_component_test.rb`:
    - `test "a security event says Security in a warn state chip before its key, and the key is meta like any other"`;
    - `test "the sentence is ink and the avatar the small circle"`.
  - `event_header_component_test.rb`: `test "the facts are one card divided inside, and a security action carries the Security chip"`.
  - `audit_log_test.rb` (browser): `test "a day's band stays under the top bar while its rows scroll, and gives way to the next day's"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests for `text-warn-ink` on a key, `text-dim` on a sentence, `mb-4` sections per day, `border-line-strong` on the subject chip, and `text-xs`. Fix each hit.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components test/lib test/integration/admin`.
  - After a build, one file at a time: `admin/audit_log_test.rb`, `admin/filter_bar_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: the audit log is one card with sticky day bands, and a security event says so in words` (body: `Advances #117`).

---

### Task 11: The reference, CLAUDE.md, the pull request and the Design System cards

**Files:**
- Modify `docs/reference/design-system.md`:
  - add a part "E4: the content-side screens":
    - the media rail (its container, the two widths, the wrapper, the tabs, Close and Escape);
    - `.admin-tile`, the tile's blurred preview, and `.admin-table-scroll`;
    - Trash, Translations, Forms and the audit log, each in two or three sentences;
    - the type-scale guard;
  - "Accent" names the selected tile's outline as a selection;
  - "Shared components" gains `RecordChipComponent`, `SettingsCardComponent`, `ActorAvatarComponent`'s `:sm` and `WordDiffComponent`'s removed look;
  - "The avatar" says stacks stand 2px apart with no ring, and gives the tree row's 7rem and its count circle;
  - "Rules a change can break silently" gains:
    - Escape in the media rail belongs to the innermost thing that takes it, and **no guard** for a new field or widget in the rail that does not stop it;
    - `.admin-tile` is the only tile look, and **no guard** for a hand-drawn tile with its own shadow;
    - a sticky table head stands in `.admin-table-scroll`, and **no guard** for a sticky head inside a plain `overflow-x-auto`, which sticks to nothing.
- Modify `docs/reference/media.md` ("CS Studio's Media module", "Notes on an image", "Who else has an image open"): the rail, the tabs, the slot `media.rail.tabs`, Close last, the keys.
- Modify `docs/reference/slots.md` and `design-system.md`'s "Screen slots": `media.rail.tabs`, and `RailSlotComponent`'s `slot:`.
- Modify `docs/reference/notes.md`: the media section as the Notes tab, its empty line, and the tab's bubble with "new".
- Modify `docs/reference/presence.md`: the stacks and the row's count circle.
- Modify `docs/reference/trash.md`, `translations.md`, `forms.md` and `access-control-and-audit.md` ("CS Studio" parts): the screens' looks in a sentence each.
- Modify `docs/reference/settings-languages-ai.md` ("The card frame"): `Admin::Ui::SettingsCardComponent` and `SectionCard`.
- Modify `docs/reference/i18n.md`: the six new locale files in "Files", and drop from "Left over" anything this stage converted.
- Modify `CLAUDE.md`:
  - the design-system index line names `RecordChipComponent`, `SettingsCardComponent` and `.admin-tile`;
  - the media index line names the rail and `media.rail.tabs`;
  - the Settings index line's `card_component.rb` becomes `app/components/admin/ui/settings_card_component.rb` with `section_card.rb`;
  - the presence index line's slots list gains `media.rail.tabs`;
  - "Rules a change can break silently" gains the three no-guard rules above, under `docs/reference/design-system.md`.
- Modify `test/support/design_system_entries.rb`: ask the controller for the artifact's index id at this time (the implementer does not read the artifact), and set `VERSION` to it if it differs from `1794259911-f251`.
- Modify `CHANGELOG.md`, `## Unreleased`, Changed:
  - The media library's panel is a rail with Image and Notes tabs where the library is wide enough, and its tiles rise under the pointer and show the chosen one with an outline.
  - Trash, Translations, Forms and the audit log take CS Studio's new look: a record's kind is shown by its icon, every state in words and none in red, Translations has a tile per language, and the audit log is one list with its days as headings.
  - People's circles in a stack stand side by side, and a page's title in a narrow tree keeps its room.
- Modify `CHANGELOG.md`, "For a gem or an outside caller": `Admin::Ui::RailSlotComponent` takes `slot:`, and the slot `media.rail.tabs` exists. `Admin::Ui::AvatarComponent` takes no `ring:`. `Admin::SettingsScreen::CardComponent` is `Admin::Ui::SettingsCardComponent`. List the last two under "Removed" too, if the section's rule asks for that.
- Test: `PGGSSENCMODE=disable bin/rails test test/lib`, `bin/rubocop`, `bin/rails zeitwerk:check`, `bin/brakeman`, `bin/changelog-guard main`.

- [ ] **Step 1: Write the reference, CLAUDE.md and CHANGELOG changes.** Then run `gh issue list --label architecture-review --state open` again, and take in the task that owns the code any new issue whose code a task rewrote.
- [ ] **Step 2: Run** the five checks. Expected: all pass.
- [ ] **Step 3: Write the PR body.**
  - Findings: Advances #117 (every task) and #127 (a second host of the rail's panel slot). The architecture-review check (below).
  - "For the owner to check": rulings C3 (Move to trash keeps its "…" and its dialog), C4 (the form's zone keeps "Move to trash…"), C5 (the submission's cards take the frame too), C6 (the matrix's bounded scroller) and C7 (the removed words' look reaches the translation pair).
  - Documentation, in `/Users/dknafelj/src/contentspiel-docs`, for all three readers:
    - **Editors:** `docs/editors/media/the-media-library.md` (the rail, its tabs, Close and Escape, the tiles), `docs/editors/trash/the-trash.md`, `docs/editors/translating/keep-translations-up-to-date.md` (the language tiles and the matrix), `docs/editors/forms/collect-answers-with-a-form.md` (the list, the builder's cards and fields, a delivery's state), `docs/editors/working-together/notes-on-content.md` (notes on an image as a tab) and `who-else-has-this-open.md` (circles side by side, the count on a narrow row), `docs/editors/pages/read-the-page-tree.md` (a narrow row). Retake the screenshots of each in both themes.
    - **Administrators:** `docs/administrators/people/the-audit-log.md` (one list, day headings, "Security"), and `docs/administrators/site/site-settings.md` only if it describes the card frame (otherwise none).
    - **Integrators:** `docs/integrators/theming/extending-cs-studio.md` (`media.rail.tabs`, `RailSlotComponent`'s `slot:`, `SettingsCardComponent`, no avatar ring) and `docs/integrators/how-it-works/how-the-cms-is-put-together.md` if it names the moved frame.
- [ ] **Step 4: The Design System cards to mark built**, for the design agent after merge:
  - `StudioMediaGrid`: the rail as built (`#media-rail`, `admin-media`, the two widths, Close last, Escape, `media.rail.tabs`), the tiles (`.admin-tile`, the blurred preview), the keys, and its "Gaps" closed;
  - `StudioTrash`, `StudioTranslations`, `StudioForms` and `StudioAuditLog`: their status to built, with C3 to C7 named;
  - `IconChip`: `RecordChipComponent` and its five kinds;
  - `StudioSettings`: `Admin::Ui::SettingsCardComponent` (its interface and its second user);
  - `ActorAvatar`: the `:sm` size;
  - `StudioTranslationPair`: the removed words' look;
  - `Avatar` and `PresenceMarker`: stacks side by side, no ring, the count circle;
  - `StudioTree`: the title's 7rem;
  - `StudioRail`: a second host (media), `slot:`, and the tab's bubble;
  - `FoundationIcons`: `arrow_up` and `arrow_down`.
- [ ] **Step 5: Check no test run is left**: `pgrep -f "rails test"` prints nothing.
- [ ] **Step 6: Commit** `docs: E4 stage 7a in the reference, CLAUDE.md and the changelog` (body: `Advances #117`).

---

## Architecture-review findings

Checked on 2026-11-09 against every open issue labelled `architecture-review` (`gh issue list --label architecture-review --state open`). Task 11 runs the check again.

| Issue | Taken | Why |
|---|---|---|
| #117 comments about invariants | advances, every task | the media, trash, translations and audit files carry "handoff §4.6", "B19", "bug 7", "design pass round 2, Task 18" and "spec §"; each task rewrites the comments of the files it touches |
| #127 slots fit one shape | advances, Task 5 | the rail's panel slot gets a second host (`media.rail.tabs`), and `RailSlotComponent` is told its slot instead of naming the editor's. The list column and save-answer contributions remain |
| #133 entry cost of a system test | not taken | its remainder (shorter names) is not in these files; the rewritten tests begin on `visit_screen` |
| #130 audit events as an extension point | not taken | Task 10 changes how events are drawn, not how they are recorded or registered |
| #132 split the largest scripts | not taken | `panel_controller.js` (85 lines) gains one action, and `drawer_controller.js#paint` gains one branch; neither is a file the finding names |
| #116 a library-image field type | not taken | no field type changes |
| #119 the reference docs' structure | not taken | paragraphs of the reference files change, not their structure |
| #112, #114, #121, #122, #124, #128, #129, #131, #135–#138, #141–#143, #185 | not taken | no task changes their code |

## Browser tests

Run locally after `bin/rails tailwindcss:build`, one file per command, only while the one-minute load is under 6 and no `rails test` runs, each prefixed with `PGGSSENCMODE=disable`. The spec's files for 7a are all run: `media_library_test`, `media_picker_test`, `trash_test`, `translations_test`, `translation_status_test`, `form_builder_test`, `audit_log_test` and `note_files_test`.

**The implementer must run:**
- Task 1: `admin/translation_status_test`, `admin/note_inbox_test`.
- Task 2: `admin/settings_test`.
- Task 3: `admin/presence_lists_test`, `admin/presence_test`, `admin/note_inbox_test`, `admin/tree_test`, `admin/tree_item_parity_test`, `admin/posts_list_test`.
- Task 4: `admin/media_library_test`, `admin/media_picker_test`, `admin/filter_bar_test`.
- Task 5: `admin/media_library_test`, `admin/presence_test`, `admin/note_files_test`, `admin/notes_rail_test`, `admin/editor_rail_test`, `admin/notes_drawer_test`.
- Task 6: `admin/trash_test`.
- Task 7: `admin/translations_test`, `admin/translation_status_test`, `admin/filter_bar_test`, `admin/dashboard_test`.
- Task 8: `admin/form_builder_test`, `admin/trash_test`, `admin/settings_test`.
- Task 9: `admin/form_builder_test`.
- Task 10: `admin/audit_log_test`, `admin/filter_bar_test`.

**Likely to change, left to CI** (the whole browser suite runs per PR):
- `theme_toggle_test` (the new screens in dark);
- `admin/settings_mail_test`, `admin/settings_images_test`, `admin/ai_settings_test`, `admin/languages_test` (the moved frame);
- `admin/mind_graph_list_test` (the tree row's title basis);
- `admin/notes_flow_test`, `admin/notes_live_test` (the tab's bubble);
- `admin/view_only_test` (the media panel's reader view).

A CI failure is fixed in the task that owns the file.

## Pre-flight

Done while writing this plan, against `main` at 08913a2a, the answers (Q1–Q23) and the artifact at `1794259911-f251`.

- **Red mid-stack.**
  - Task 1 changes `WordDiffComponent` (the translation pair's card) and the notes rows' chip.
  - Task 2 moves a class seven Settings cards render.
  - Task 3 drops a keyword every avatar stack passes, and makes the tree row a size container.
  - Task 5 adds a required keyword to `RailSlotComponent`, which the editors render.

  Each fixes the tests it breaks.
- **A file changed in two tasks.**
  - `app/views/admin/media/index.html.erb`: the words and the upload controller's values in Task 4, the layout in Task 5.
  - `content-spiel.tailwind.css`: Tasks 1, 3, 5 and 7, each in its own rules.
  - `admin_design_rules_test.rb`: `CONTENT_SIDE_SCREENS` is made in Task 1 and grown in Tasks 4 and 6 to 10.
  - `forms_screen.en.yml`: Tasks 8 and 9.
  - `design_system_entries.rb`: Tasks 1 and 2, then a check in Task 11.
  - `presence_test.rb`: the stacks in Task 3, the panel's row in Task 5.
- **Keys before their reader.** Each key arrives in the task that reads it. `rail_panel.empty_image` arrives in Task 5, the tab bubble's `marker.new` was added by stage 6, and the upload words arrive in Task 4.
- **Guard lists.**
  - `MADE_BEFORE_CONTRACT` is unchanged and stays at 40. The two new `ui/` components are not on it, and `KEYBOARD_NOT_YET` stays empty.
  - `PEOPLE_RULES` gains the tab bubble's rule (Task 5).
  - `STATUS_FILL_FILES` may lose two forms entries (Tasks 8 and 9), and its stale-entry test says when.
  - `CONVERTED` grows in Tasks 2 and 4 to 10.
  - `HAND_BOX_ALLOWED` holds the drop overlay alone.
- **Tests a mutation would not fail.**
  - The type-scale guard's pattern test carries samples that match and samples that do not.
  - The record chip's test iterates the real kind lists, not a copy.
  - The docking guards read the container's widths, and fail on a third width.
  - The stack guard refuses `--admin-avatar-ground` anywhere, so a ring brought back fails.
- **Not reproduced while planning.** No test database exists in this worktree, so nothing was run. Two things are read from CSS's rules and Tailwind's documentation, not tried: whether a tree row can be a size container without changing its measured height, and whether `blur-md` is 12px in this Tailwind build. Task 3 and Task 4 try them first.
- **History comments.** Every task ends on the grep in "Comment rule", run over the lines it added.

### Conflicts found, and rulings

| C | Conflict | Ruling | Why |
|---|---|---|---|
| C1 | Q7 says the Notes tab is "the editors' Notes tab, `NotesScreen::RailPanelComponent`". That component is the drawer, a slide-over below the rail's threshold. Q7 also says that below 1200px Notes "stays the section at the panel's end, as today (`MediaSectionComponent`)". Two components would put `turbo-frame#notes` in the page twice. | The Notes tab is `MediaSectionComponent`, registered at `media.rail.tabs`, with one frame that is the docked tab's panel and the section below. The editors' tab and this one share the tab's bubble and the frame's views. | One frame per page. Q7's two widths are met by one element. |
| C2 | Q5 names "the shared icon button" for Close, but `ButtonComponent` draws only `<button>`, and Close is a navigation that advances the address. | A link with `ButtonComponent.classes(:tertiary, size: :small)`, the `x` icon and the shared tooltip. | It keeps Back, works without script, and looks like the button. |
| C3 | Q6 writes "Move to trash" with no "…", "it can be undone". Today it opens a confirm dialog, as every Move to trash in CS Studio does (the editor header, the posts list, the bulk bar, the forms list), and an ellipsis marks a dialog. | **For the owner.** Keep "Move to trash…" and its dialog. Dropping both would change behaviour (the spec allows layout only) and make the media panel the one place that trashes on a single press. | The spec's non-goals. If the owner wants no dialog everywhere, that is one change across all five places. |
| C4 | Q17 calls the builder's zone "Delete this form…", while a form goes to the trash and its button today says "Move to trash…". | The words stay "Move to trash…". | "Delete" would misdescribe a restorable move. |
| C5 | Q18 names the submission's "Answers card" and "Deliveries card" without saying which frame they take. They share `BuilderComponent::CARD_CLASS` today. | They take `SettingsCardComponent` with the form chip. | One job, one frame. The constant they share goes. |
| C6 | Q13 wants the matrix's header "sticky under the top bar" with "its own sideways scroll". A sticky element inside an `overflow-x: auto` box sticks to that box, not to the window, so both cannot hold. | **For the owner.** The matrix scrolls inside a box at most the window's height (`.admin-table-scroll`), and its head sticks to the top of that box. The page still never scrolls sideways. | CSS has no other way. The alternative is to drop the sideways scroll and let the page scroll, which Q3 refuses. |
| C7 | Q21 calls the struck-through removed words "the look the translation pair chose". The code's `WordDiffComponent`, the translation pair's, draws them on the danger tint. | `WordDiffComponent` takes the struck-through look, which reaches the translation pair's reference card too. | It is one shared component, and Q2 forbids red for what is no failure. |
| C8 | Q11 names "Tomorrow", which the code never says ("In 1 day"). | "Tomorrow" at one day left, in `warn-ink`. | The answer's words. |
| C9 | Q16 names `Admin::Ui::NoticeComponent tone: :warn` "where built". It is not built. | The existing warn box stays, with no danger. | The answer's own fallback. |
| C10 | Q23 removes `RINGS[:ground]` "if nothing else uses them". Every ring of any kind (paper, surface, ground) is passed only by a stack. | `RINGS` and `ring:` go entirely, from `AvatarComponent` and `NotesScreen::AvatarComponent`. | No compatibility code: a keyword no caller passes is not kept. |
| C11 | Q23's count circle reads "3". Its words above nine are not given. | The count, or "9+" above nine (`ui.avatar.many`), as the "+N" circle reads. | The marker has one rule for a number that does not fit. |
| C12 | Q5 draws the Notes tab with a NoteMarker bubble. The tab's count is kept by `paint()`, which writes a plain number. | The tab's count is drawn as the bubble by one rule, and `paint()` writes "N new" while unread into a total that opts in (`data-notes-total-words`). This applies to the editors' Notes tab too. | The colour is not the only cue, and there is one look for one job. |
| C13 | `test/support/design_system_entries.rb` lacks `StudioNotesInbox` as well as the four new cards. | Task 1 adds all five. | The list is a copy of the artifact's. |
