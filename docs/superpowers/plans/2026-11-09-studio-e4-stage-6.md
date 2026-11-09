# CS Studio in E4, Stage 6 (working together) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notes, presence and live editing take E4, as drawn on `StudioCalmE4Together`, in one people hue. Avatars are rose circles with 11px initials, a ring that says here or away, and a "+N" circle. A note count is a rose bubble, and unread for you is the accent bubble that says "3 new". The page tree and the posts list show who is on a row as avatars. The Notes screen ("Notes for you") gets an All · Unread · Mentions filter, rows with the author's avatar and the record's chip, a "● New" chip, and a rail of open threads. A held block gets the hold strip on the people tint, and a held or discussed block gets one people outline. "Updated by" leads with the colleague's avatar and a short glow, and a take-over says "Taken over by you". The shared tabs (`TabLinksComponent`) take the filter bar's current tab. Finding #140 closes: `Notes.name_of` is inlined and `User#display_name` is renamed.

**Architecture:**
- Two people tokens, `--cs-people` and `--cs-people-tint`, are aliases of the icon pair. The guard admits them in a closed list of files and stylesheet rules.
- `Admin::Ui::AvatarComponent` is the one circle, in three sizes, four tones (`:more` is the "+N" circle) and an optional "here" ring. The scripts that build a circle in the browser use one module, `app/javascript/ui/avatar.js`, which a test holds to the component's classes.
- A shared look moves to `ui/` with the full contract. A feature's slot entry stays in the feature's folder: it keeps its loader and words, and renders the shared part. So `Admin::Ui::NoteMarkerComponent` (the count bubble) is drawn by `NotesScreen::RowPillComponent`, the media tile and Waiting for you. `Admin::Ui::PresenceMarkerComponent` (the avatar stack) is drawn by `PresenceScreen::RowMarkerComponent`. `EditorScreen::BlockIconComponent` gains its second screen (the inbox row), so it moves to `Admin::Ui::BlockIconComponent`.
- The Notes screen reads `Dashboard::NotesForYou` through one `show:` keyword. Its rail reads `Dashboard::OpenThreads`, which gains each row's newest two authors.
- Live editing changes markup and the stylesheet. The one new script path, the take-over mark, goes through a plain module (`app/javascript/editing/marks.js`), so `hold_controller.js` does not grow.

**Tech Stack:** Rails 8.1, ViewComponent 4.23 with Lookbook previews, Tailwind v4 (`tailwindcss-rails`), Turbo frames and streams, Stimulus over import maps, Action Cable (Solid Cable), Minitest with Capybara on Cuprite 0.20.

**Spec:** `docs/superpowers/specs/2026-11-06-studio-e4-design.md` (approved 2026-11-06). Sections used:
- "Decided on 2026-11-06", items 16 and 17;
- "The design, as decided": the four roles (People) and status;
- "Every screen, and its stage": the rows "Note markers, row pills", "Notes screen and inbox", "Presence" and "Live editing";
- "Stage 6: working together", in full;
- "Architecture-review findings" (#140 closes), "The guard after E4" ("People are circles and bubbles", the 11px rule) and "Constraints".

The drawing is `StudioCalmE4Together` in the Design System artifact (https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT). The answers were written at v153 (index `1794231049-d0b3`), and the card mapping at v155 (index `1794231176-96fb`). The cards involved are `Avatar`, `NoteMarker`, `PresenceMarker`, `StudioHeldStrip`, `StudioFilterBar` and `StudioNotesThread`. Implementers do not read or edit the artifact. It is the design agent's.

**One pull request** on branch `studio-e4-6`, made from `main` at faace458, targeting `main`.

---

## Design answers

Binding. The source is `.superpowers/sdd/2026-11-09-studio-e4-stage-6/design-answers-6.md` (git-ignored, Q1–Q24 and the component mapping), which an implementer reads beside their task. The owner chose on 2026-11-09, and all four choices follow the recommendations:
- **Q11:** the order is All · Unread · Mentions, and All is the default. `TabLinksComponent`'s current tab is redrawn now, and the redraw reaches Waiting for you's filter, the Trash tabs and the form builder's tabs.
- **Q12:** no "Open" button per row. The row is one link that ends in the "Open thread" verb.
- **Q3:** your own avatar is a solid people fill with surface initials.
- **Q18:** held and discussed blocks share one 2px people outline, and the notes outline loses its accent.

In short:
- **Tokens (Q1).** `--cs-people: var(--cs-ic-people)` and `--cs-people-tint: var(--cs-ic-people-bg)`, with Tailwind colours `people` and `people-tint`. There are no new values. The pairs measured, light / dark: on the tint 7.22 / 9.03, on surface 8.59 / 10.13, on paper 7.81 / 11.26, on sunken 7.07 / 9.04, on rail 7.55 / 8.98, on chrome 8.59 / 10.82, and on popover 8.59 / 8.02.
- **Avatar (Q2–Q5).**
  - Sizes: `:lg` 28px, `:md` 26px, `:sm` 22px. Every size draws its initials at 11px, weight 600, uppercase, `leading-none`.
  - Tones: `:other` is the people tint with people initials. `:own` is a solid people fill with surface initials. `:away` is a surface fill, meta initials and a dashed `field-line` 1.5px border.
  - "Here" is a 1.5px solid people ring inside the circle. The 2px separating ring in the ground's colour is drawn outside it.
  - "+N" is a circle of the same size, `sunken` fill and `ink` text, `aria-hidden`, reading "9+" above 9. Overlap is −6px at 22 and 26px, and −8px at 28px.
  - Circles shown before "+N": the editor header 3 (1 below `lg`), the rail's panel 2, a posts row 3, a tree row 2.
- **Note marker (Q6–Q8, Q22).**
  - Add stays as it is.
  - Read: a pill 20px high (18px on a tile and in the tree), with the people tint, no border, an outline bubble glyph (12px) and the count at 11px weight 600.
  - Unread for you: the accent fill with `on-accent` words, a filled bubble (`message_square_filled`, new), the count and "new" ("3 new").
  - Hover on a pressable pill underlines the count. `--on-image` keeps a 2px surface ring.
  - Accessible names: "3 open notes", and unread "3 open notes, new for you".
  - The sidebar's Notes count stays the accent bubble.
- **Presence in rows (Q9, Q10).** A stack of `:sm` avatars from `here_people`: at most two in the tree and three in the posts list, then "+N". The row's end holds presence, then the notes pill, then the translation marker, 6px apart. The tooltip and the `sr-only` sentence are unchanged. The ring follows the row's ground: chrome in the tree, sunken on the selected tree row, surface on the posts list. Narrow: one avatar and "+N" at a tree row of 260px or less (a container query on the row), and on a posts list under 640px.
- **Notes screen (Q11–Q16).**
  - The filter: `?show=all|unread|mentions`, with "All 14", "Unread 2", "Mentions 1", and a count of 0 still shown.
  - The inbox row's grid is `26px 1fr auto`:
    - the author's `:md` avatar, or a message icon on a sunken circle when nobody;
    - the sentence, 14px ink, the name at 600 unread and 500 read, and `dim` on a read row;
    - the where line: the record's 20px chip, then "Rich text · …" at 13px dim;
    - the excerpt, 13px meta, one line;
    - in the end column the time, 11px meta, over the verb, and "● New" in place of the dot.
  - "● New" is the accent-tint pill with accent words and a 6px accent dot, 5.68 / 6.25.
  - "Mark all read" is a small secondary in the heading row, shown only while something is unread. The screen has no primary.
  - The rail of open threads, on `.admin-list-rail`:
    - "Open threads" (`text-h3`) over the line "Unresolved notes on pages, posts and images";
    - rows from `Dashboard::OpenThreads`, at most 8: the chip, the title, "3 notes · 2h ago", and the last two people's `:sm` avatars and "+N";
    - then "And 4 more on other pages" (no link), and "No open threads." when there are none;
    - below the threshold it is a card *after* the inbox card.
  - Empty states: "Nothing for you yet" with "When someone mentions you or replies to you, it shows here.", "No unread notes", "No mentions yet".
- **Live editing (Q17–Q21).**
  - The hold strip (held) is on the people tint, with a 1px `line` rule under it and no border. Its sentence is 13px ink, with the name at 600 ("Dana Weiss is editing this block."), 14.78 / 11.53. It shows the holder's `:md` avatar with the here ring, or `:own`. Take over is the small secondary (accent words on the tint 5.79 / 6.31, its edge 3.03 / 3.71). The status stays meta (5.29 / 5.68). Below 480px of the card the button wraps under the sentence. The strip is neutral, never warn, and the lost and deleted strips are unchanged.
  - The people outline is `outline: 2px solid var(--cs-people); outline-offset: -2px` (8.59 / 10.13 on the card). It is drawn for held and for notes-active, and replaces both old edges. A section takes it outside its frame (`outline-offset: 2px`).
  - The holder's avatar: `:sm` with the here ring.
  - "Updated by": the colleague's `:sm` avatar before "Updated by Dana Weiss · 2 min ago" (12px meta). For the mark's 6 seconds the card glows (`box-shadow: 0 0 0 4px color-mix(in oklab, var(--cs-people) 20%, transparent)`, 200ms in, 600ms out, on `--cs-ease`). There is no glow under reduced motion and none on a held card.
  - After a take-over the head says "Taken over by you · just now" for 6 seconds.
- **Not in this stage (Q24):** the thread's look, the Notes tab and the composer. Only their avatars change.

**Component mapping** (v155; the design agent confirmed the card names, and the new components are named so their own name is their card):

| Component | Card |
|---|---|
| `Admin::Ui::NoteMarkerComponent` (the drawing moved out of `NotesScreen::RowPillComponent`, and the look `NotesScreen::MarkerComponent` shares) | NoteMarker |
| `Admin::Ui::PresenceMarkerComponent` (the drawing moved out of `PresenceScreen::RowMarkerComponent`) | PresenceMarker |
| `Admin::Ui::AvatarComponent` | Avatar |
| `Admin::Ui::TabLinksComponent` | StudioFilterBar (it was StudioDashboardCards) |
| `EditorScreen::HolderAvatarComponent` (stays in `editor_screen/`) | StudioHeldStrip, drawing Avatar's circle |
| `Admin::Ui::BlockIconComponent` (moved, ruling C10) | **provisional** `IconChip`, for the design agent to confirm |

## Global Constraints

- **Design first.** An implementer who meets a look, a word or a state that neither this plan, the answers nor the drawing settle stops and reports **NEEDS_CONTEXT**, naming the gap. The design agent answers in the artifact, and the answer goes back to the same implementer.
- **The public site keeps its look.** No file under `app/assets/tailwind/themes/`, `app/components/blocks/`, `app/components/posts/`, `app/components/public/`, `app/views/layouts/public/` or `app/views/pages/` changes, and no `th-*` token.
- **CLAUDE.md binds every task.** In particular:
  - Notes never write the record. A name is text: a script writes it with `textContent`, and the server escapes it.
  - A link into the notes frame or to a record's notes does not prefetch (`data-turbo-prefetch="false"`).
  - A new list or count of notes narrows through `Notes.readable_threads`, and joins `test/integration/trash_visibility_test.rb`.
  - Presence and notes stay in their slots (`config/initializers/admin_slots.rb`). A core screen draws the slot and does not name the feature (`test/lib/notes_boundary_test.rb`).
  - No Turbo morphing, no `turbo_refreshes_with`, no `broadcast_refresh` (`test/lib/notes_guards_test.rb`).
  - The live-editing rules the tests hold do not change: read-only at full contrast, no lock, warn for lost text, arrivals fade in and nobody fades out. A frozen card keeps `data-card-edge="held"`, and `data-card-edge` stays out of `editing/merge.js`'s `RUNTIME`.
  - Whatever a script writes into the page is taken back before Turbo's snapshot.
  - Never define `Admin::<Domain>`. Dependency direction: `Dashboard::*` and `Presence::Roster` know no component.
  - Queries are Active Record, then Arel through `SqlNodes`, then SQL with `# sql:`.
- **No compatibility code.** A renamed or moved constant, method or key keeps no alias. Every caller, test, comment and reference doc is changed in the task that renames it: `git grep` for the old name prints nothing outside `docs/superpowers/` (history) and `CHANGELOG.md`.
- **No admin string is a literal.**
  - A `ui/` component's keys are `admin.components.ui.<name>.*` in `config/locales/admin/ui.en.yml`.
  - The notes components', the Notes screen's (`admin.note_inbox.*`) and the drawer script's (`admin.notes.script.*`) keys stay in `config/locales/admin/notes.en.yml`, the one exception file (`test/lib/source_layout_test.rb`).
  - Presence's keys are in `presence_screen.en.yml`, and the editor's in `editor_screen.en.yml`.
  - A script's words come from `data-messages` or ready-made from the server.
  - A key is added in the task whose code reads it. A file converted to keys joins `test/lib/admin_i18n_test.rb`'s `CONVERTED` in that task.
- **The component contract.**
  - A component in `app/components/admin/ui/` declares `Admin::Ui::Contract` and has a component test, a preview example per previewable state, and a Design System entry (`test/support/design_system_entries.rb`).
  - A component that is new or moved into `ui/` is not in `UiContract::MADE_BEFORE_CONTRACT`, which can only shrink. It names a keyboard browser test in `keyboard:`. A component that takes no focus names the test that holds that the keyboard passes over it, as `StateChipComponent` does: `ui_contract.rb` admits no `keyboard: nil` for it, and no reason without a test. `KEYBOARD_NOT_YET` stays empty at merge.
  - `AvatarComponent`, `TabLinksComponent` and `IconChipComponent` are on `MADE_BEFORE_CONTRACT`. They change their declarations, and may keep `keyboard: nil`.
- **People are circles and bubbles.** The people tokens and their utilities appear only in the files and stylesheet rules on `PEOPLE_HUE_ALLOWED` and `PEOPLE_RULES` (Task 2), which each task grows by its own entries. They never appear in `ButtonComponent` or beside a button's classes.
- **Buttons are the shared button.** "Mark all read" and Take over are `:secondary, size: :small`, and the Notes screen draws no primary. A new accent fill or tint pair that is no button joins `ACCENT_FILL_ALLOWED` or `TINT_PAIR_ALLOWED` with its reason, in the task that draws it.
- **Layers.** No raw z-index. **Motion:** the glow and every fade hold still under `prefers-reduced-motion`.
- **Contrast is measured** (`test/lib/admin_contrast_test.rb`) in both schemes, at the answers' figures rounded down to one decimal.
- **Comment rule (#117).** A comment states a current invariant, a hazard or a reason. It never states a plan step, a review round, "handoff 32", "spec §", "decision D3", "Ruling 7" or what used to be there. The notes, presence and editing files are full of these. Every task rewrites the comments of the files it changes. Its last step before its commit runs this grep over the lines the task added (`git diff -U0 main... -- <files> | grep '^+'`), and it prints nothing:

  ```
  grep -n "spec §\|handoff [0-9§]\|handoff,\|Task [0-9]\|round [0-9]\|final review\|[Rr]uling [A-Z]\?[0-9]\|decision D\?[0-9]\|fix wave\|ledger C-\|design answer\|Q[0-9][0-9]\?\b\|old name\|used to\|no longer"
  ```

  The plan's wording is never copied into a comment.
- **Tests and the machine.**
  - On macOS every test command is prefixed with `PGGSSENCMODE=disable`. The worktree runs `bin/rails db:test:prepare` once before its first test.
  - Browser tests run only after `bin/rails tailwindcss:build`, never during a build or beside a running `bin/dev`. They run one file per command, and only while the first figure of `sysctl -n vm.loadavg` is under 6 and no `rails test` runs (`pgrep -f "rails test"` prints nothing).
  - A browser test begins on `visit_screen` or `visit_editor`. A test this stage rewrites moves its bare `visit … await_admin_controllers` onto them (#133).
  - Cuprite 0.20: a test reads a node through a retrying selector (`assert_selector`, `find` with its text or attribute) after anything the page redraws, and never holds a node found before the redraw. `evaluate_async_script` drops a sole falsy argument, so pass an object (`{ value: false }`) or a second argument.
  - No new browser file. The tests join the files named in each task. New unit files are weighed by their count (`bin/test-shard`). No task deletes a test file except a moved component's own (moved with `git mv`).
  - **No test run is left in the background** when a task ends. Its last step checks that `pgrep -f "rails test"` prints nothing.
- Commits follow conventional commits and end with:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT`
  A task that carries a finding says so in its body ("Closes #140", "Advances #117").

## Review Focus

1. **Somebody arrives after the list was drawn.** The tree and the posts list are drawn with their avatars, and `admin--presence--list` keeps them true afterwards. The script must write the new person's initials into a circle, show "+1" when a fourth person arrives on a posts row (a third on a tree row), and take both back when they leave. It writes only text and `hidden`, never redraws the row, and a name with markup stays text. Task 5:
   - `test "an arrival after the list was drawn adds their initials as text, a fourth on a posts row shows +1, and leaving takes both back; the row is never redrawn"` (browser, `presence_lists_test`);
   - `test "a name with markup reaches the circle and the tooltip as text"` (the same file).
2. **A narrow tree column with many people.** At 220px the tree row shows one avatar and "+N", which the script must keep right as people come and go. Ten or more people read "9+". Task 5: `test "at the tree's narrowest a row shows one avatar and +N, and the script keeps both counts"` (browser), and `test "+N past nine reads 9+"` (component, `avatar_component_test`).
3. **The filter and the read scope.** Mentions counts and lists only deliveries on threads the viewer may read now. A mention on a record they lost the right to, or that is in the trash, is neither listed nor counted, and a page past the end keeps its scope. Task 6:
   - `test "counts answers all, unread and mentions in one statement, and a delivery on a record outside the read scope or in the trash is in none of them"`;
   - `test "a page past the end of Mentions says so and links back to Mentions"` (integration).
4. **The rail of open threads beyond its rows.** "And N more" counts only records the viewer may read, never trashed ones. A person who wrote only on a resolved thread, or on a thread the viewer may not read, is not among a row's avatars. Task 7: `test "a row's people are the newest two who wrote on its open threads the viewer may read, and the more line counts only readable records"` (query test), and the rail joins `trash_visibility_test.rb`.
5. **Two edges at once.** The block cases are a held block whose thread is also open, a held block whose type is gone, and a chosen section that is held. Each shows one edge: the people outline for held and discussed, the danger edge for unavailable, and the accent for chosen. An "Updated by" glow never stands with the people outline, and reduced motion draws no glow. Task 8:
   - `test "held and discussed blocks share one people outline, under the unavailable edge and the chosen section"` (design rules);
   - `test "an Updated by mark glows the card for its six seconds, not on a held card and not under reduced motion"` (browser, `editing_merge_test`).

---

## Decisions the spec left open (not looks)

| Question | Decision | Why |
|---|---|---|
| `User#display_name`'s new name (#140) | `User#name_or_email`, and `Invitation#name_or_email` with it. Each returns the name, or the whole address when there is no name. `Mail::Address#display_name=` in `MailSettings` is Mail's own API and keeps its name. | The name says what comes back, including the whole address. It matches `User.name_or_email_containing`, the scope that searches the same two columns, and stands clearly apart from `PersonName.of`, the short name. `full_name` would be false when the address stands in, and `label` says nothing. The users list draws users and invitations through one call (`row.display_name`), so both rename together. |
| Where a shared look goes, and where a feature's slot entry stays | A look used by more than one screen moves to `ui/` with the full contract (`NoteMarkerComponent`, `PresenceMarkerComponent`, `BlockIconComponent`). The slot entries `NotesScreen::RowPillComponent` and `PresenceScreen::RowMarkerComponent` stay. They keep their loader and their words, and render the `ui/` part. `NotesScreen::MarkerComponent`, the block's button, stays as well: it is drawn on the editor only, its script wiring is the drawer's, and it shares only the stylesheet's look. | See ruling C1. The slot pattern keeps a feature's components in the feature's folder, so that it can change without core files changing (`docs/reference/slots.md`). `notes.en.yml` exists so that notes' words stay out of core files. A `ui/` part that knows no feature honours both. |
| `AvatarComponent`'s interface | `.new(initials:, size:, tone: :other, ring: nil, here: false)`. `SIZES` `lg` `size-7`, `md` `size-[26px]`, `sm` `size-[22px]`, each `text-count font-semibold`. `TONES` `other` `bg-people-tint text-people`, `own` `bg-people text-surface`, `away` `border-[1.5px] border-dashed border-field-line bg-surface text-meta`, `more` `bg-sunken text-ink`. `RINGS` `paper`, `surface`, `ground` (`ring-2 ring-(--admin-avatar-ground)`, a ground the host's stylesheet sets). `here: true` adds `inset-ring-[1.5px] inset-ring-people`. `.more_label(count) -> String` reads `avatar.more` ("+%{count}"), or `avatar.many` ("9+") above 9. | The here ring and the separating ring are two box-shadow layers. Tailwind v4's `ring` and `inset-ring` compose them, and neither is an arbitrary `shadow-[…]`, which the elevation guard refuses. If the build does not compose them, Task 2 reports NEEDS_CONTEXT rather than write a shadow. `:ground` lets a tree row's selection, a stylesheet state, change the ring (Q9's sunken). |
| The scripts' circles | `app/javascript/ui/avatar.js`: `export function avatar(initials, { size = "sm", tone = "other" } = {}) -> HTMLSpanElement`, `aria-hidden`, the letters as `textContent`. `mind_graph/card_notes.js` and `admin/notes/composer_controller.js` import it. `avatar_component_test` holds that its class strings equal `SIZES` and `TONES` for `sm`, `md`, `other` and `own`. | Two scripts copy the classes by hand today. One module, held to the component, is one place to change. |
| The filter's reads | `Dashboard::NotesForYou::SHOWS = %i[all unread mentions]`, with `rows(limit: 5, offset: 0, show: :all)`, `total(show: :all)` and `counts -> { all:, unread:, mentions: }`. `counts` is one statement, `COUNT(*) FILTER (…)` through `SqlNodes`. Mentions is `reason: "mention"` (the answer's `rows(reason: "mention")`, spelt as the one keyword). | Unread needs a scope too, and one keyword keeps the parameter's mapping in one place. Three tabs and one count statement do not grow with the rows. |
| The rail's people | `Dashboard::OpenThreads::Row` gains `authors` (`Array<User>`, newest first, at most 2) and `author_count` (`Integer`). `#more_records -> Integer` is `record_keys.size - rows.size`. The authors come from one statement for all the rows, a new `Notes::Message.authors_per_container` scope: one row per container and author with that author's newest message time, inside the readable unresolved threads. The dashboard's use is unchanged. | Q15 draws two people per row, and `OpenThreads` reads one. The count of queries must not grow with the rows. |
| The take-over mark | `UpdatedMarkComponent.new(change: nil, taken_over: false)`. Taken over reads `updated_mark.taken_over` ("Taken over by you") with "just now". `LiveRegionComponent` renders it once in `<template data-admin--editing--hold-target="takenOver">`. `app/javascript/editing/marks.js` exports `showMark(unit, template)`, which puts a clone in the unit's `[data-editing-mark-place]`, and `fadeMark(mark, { after })`, which is `live_controller.js`'s `fade`, moved. `hold_controller.js` calls both where `takeOver` learns the take-over stood. | Q21 needs the head to speak after a take-over, and the hold script holds no wording. A template is the existing pattern (the deleted strip). `hold_controller.js` (783 lines, #132) gains two calls, not a body. |
| The people outline's rule | No element carries a new class. One stylesheet rule, under a comment naming it "the people frame", has the selector list `.admin-block-card[data-card-edge="held"]`, `.admin-block-card:where(:not(.admin-section-card))[data-notes-active]` and `.admin-block-tile[data-notes-active]`. The frozen-section rule draws the same outline at `outline-offset: 2px`. The unavailable edge and `[data-chosen]` are written after it and win. | See ruling C6: a state edge is an outline from `data-card-edge` or `data-notes-active`, never a class a script adds. |
| A 20px chip | `IconChipComponent::SIZES` gains `xsmall: "size-5"`. `BlockIconComponent::PLACES` gains `row: :xsmall`. | Q12 and Q15 draw a 20px chip, and the chip has 24 and 22 only. |
| The presence stack's words in the browser | `RowMarkerComponent.words(here)` answers `{ count:, label:, initials: }`, the initials of the people `Roster` names, through `PersonName.initials(PersonName.of(user))`. The "+N" words come from the marker's `data-messages` (`ui.avatar.more`, `ui.avatar.many`), read with `messages(element).t`. | The script draws circles it already holds and computes no letters (`PersonName`'s rule). The words stay the server's. |

---

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `app/models/notes.rb`, `app/models/user.rb`, `app/models/invitation.rb`, `app/values/person_name.rb`, every caller of `Notes.name_of` and `display_name` (`app/`, `test/`), `docs/reference/{notes,presence,users-groups-tokens,trash,cs-studio-shell-and-dashboard}.md`, `docs/roadmap.md` | #140 | 1 |
| `content-spiel.css`, `content-spiel.tailwind.css` (`@theme` colours), `ui/avatar_component.rb` and its preview and test, `app/javascript/ui/avatar.js` (new), `mind_graph/card_notes.js`, `controllers/admin/notes/composer_controller.js`, `presence_screen/people_component.*`, `ui.en.yml` (`avatar`), `presence_screen.en.yml` (`people.more` goes), `test/lib/{admin_design_rules,admin_contrast}_test.rb` | the people tokens and the circle | 2 |
| `ui/tab_links_component.*` and its preview and test, `test/support/design_system_entries.rb` | the filter bar's current tab, the card copy | 3 |
| `ui/note_marker_component.*` (new), `notes_screen/{row_pill,marker}_component.*`, `media_library/tile_component.html.erb`, `dashboard_screen/waiting_row_component.html.erb`, `app/views/admin/shared/_icon.html.erb` (`message_square_filled`), `controllers/admin/notes/drawer_controller.js` (`paint`), `content-spiel.tailwind.css` (`.admin-notes-marker`), `notes.en.yml`, `ui.en.yml` | the note bubble | 4 |
| `ui/presence_marker_component.*` (new), `presence_screen/row_marker_component.*`, `config/initializers/admin_slots.rb`, `controllers/admin/presence/list_controller.js`, `app/controllers/admin/presence_controller.rb`, `content-spiel.tailwind.css` (`.admin-tree-row`, `.admin-presence-marker`) | avatars in the rows | 5 |
| `app/queries/dashboard/notes_for_you.rb`, `app/controllers/admin/note_inbox_controller.rb`, `app/views/admin/note_inbox/index.html.erb`, `notes_screen/inbox_row_component.*`, `editor_screen/block_icon_component.rb` → `ui/block_icon_component.rb` (moved) and every caller, `ui/icon_chip_component.rb` (`xsmall`), `notes.en.yml` | the Notes screen's list | 6 |
| `app/queries/dashboard/open_threads.rb`, `app/models/notes/message.rb` (`authors_per_container`), `notes_screen/open_threads_component.*` and `open_thread_row_component.*` (new), `index.html.erb` (the layout), `content-spiel.tailwind.css` (`.admin-notes-threads`), `test/integration/trash_visibility_test.rb` | the rail of open threads | 7 |
| `editor_screen/{hold_strip,holder_avatar,updated_mark,live_region,block_card}_component.*`, `app/javascript/editing/marks.js` (new), `controllers/admin/editing/{hold,live}_controller.js`, `content-spiel.tailwind.css` (the state edges, the glow), `editor_screen.en.yml` | live editing | 8 |
| `docs/reference/{design-system,notes,presence,live-editing,cs-studio-shell-and-dashboard,i18n,slots}.md`, `CLAUDE.md`, `CHANGELOG.md` | the reference, the rule, the PR and the cards | 9 |

---

### Task 1: One short name and one whole name (closes #140)

**Files:**
- Modify `app/models/notes.rb:28–40`: delete `name_of` and its comment. What the comment says that is still true (the short name is `PersonName.of`, and a name set later shows everywhere) moves to `app/values/person_name.rb`'s header. That header is rewritten: `PersonName.of` is the short name, and `User#name_or_email` the whole one.
- Replace `Notes.name_of(x)` with `PersonName.of(x)` at every call site:
  - `notes_screen/person_name_component.rb:12`;
  - `notes_screen/reactions_component.rb:103`;
  - `controllers/admin/note_mentions_controller.rb:33`;
  - `controllers/admin/note_threads_controller.rb:50`;
  - `models/notes/mentions.rb:48`;
  - `test/integration/admin/note_names_test.rb:104,106`, `note_reactions_test.rb:107`;
  - `test/system/admin/note_reactions_test.rb:77,141`.

  Rewrite the comments that name it: `person_name_component.rb:6`, `note_mentions_controller.rb:3`, `notes/mentions.rb:38`, `note_names_test.rb:5`. The reference lines are `docs/reference/notes.md:21,189`, `presence.md:102` and `docs/roadmap.md:693`.
- Rename `User#display_name` (`app/models/user.rb:74`, with the comment at :22) and `Invitation#display_name` (`app/models/invitation.rb:71`) to `name_or_email`, in every caller: the 83 lines `git grep -n display_name -- app lib test docs/reference` lists today, except `MailSettings`' `address.display_name =`.
- Test: `test/models/user_test.rb`, `test/models/invitation_test.rb`, `test/values/person_name_test.rb`, `test/integration/admin/note_names_test.rb`, every file the rename touches.

**Interfaces:**
- Produces `User#name_or_email -> String` and `Invitation#name_or_email -> String`. `PersonName.of(user) -> String` is the one short name. Every later task calls these, never `display_name` or `Notes.name_of`.

- [ ] **Step 1: Write the failing tests.**
  - `user_test.rb`: `test "name_or_email is the name, else the whole address"`.
  - `invitation_test.rb`: the same for an invitation.
  - `note_names_test.rb`: `test "a note names a person by PersonName.of, and Notes has no name of its own"`, which asserts `PersonName.of(users(:two)) == "two"` and `assert_not_respond_to Notes, :name_of`.
- [ ] **Step 2: Run them, and verify they fail.** `PGGSSENCMODE=disable bin/rails test test/models/user_test.rb test/models/invitation_test.rb test/integration/admin/note_names_test.rb`.
- [ ] **Step 3: Implement.** Then `git grep -n "name_of(\|display_name" -- app lib config test docs/reference CLAUDE.md` prints only `MailSettings`' line and `Notes::Heading`'s unrelated `name_of` helper in `test/queries/notes/heading_test.rb` (a local method; leave it).
- [ ] **Step 4: Run.** `PGGSSENCMODE=disable bin/rails test test/models test/values test/integration/admin test/components/admin test/queries test/controllers`. After a build, one file at a time: `admin/note_reactions_test.rb`, `admin/users_test.rb`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep. Check `pgrep`. Commit `ref: one short name (PersonName.of) and one whole name (name_or_email)` (body: `Closes #140`, `Advances #117`).

---

### Task 2: The people tokens and the one circle (Q1–Q5)

**Files:**
- Modify `app/assets/tailwind/content-spiel.css`: write `--cs-people: var(--cs-ic-people);` and `--cs-people-tint: var(--cs-ic-people-bg);` once, in the first `:root` block beside the icon pair. They follow the dark re-values through the aliases.
- Modify `app/assets/tailwind/content-spiel.tailwind.css` `@theme`: add `--color-people: var(--cs-people);` and `--color-people-tint: var(--cs-people-tint);`.
- Modify `app/components/admin/ui/avatar_component.rb` (decisions table). Its contract changes:
  - `interface: %i[initials size tone ring here]`;
  - `states: %i[other own away more here]`;
  - `keys: %w[more many]`;
  - `limits:` "It is told the initials and knows nothing of users.", "It draws three sizes, four tones and three rings, and anything else is refused.", "Its letters are 11px at every size.";
  - `keyboard: nil` (made before the contract).
- Modify `test/components/previews/admin/ui/avatar_component_preview.rb`: an example per state, each at the three sizes.
- Add `admin.components.ui.avatar.more` ("+%{count}") and `.many` ("9+") to `config/locales/admin/ui.en.yml`.
- Create `app/javascript/ui/avatar.js` (decisions table). Modify `mind_graph/card_notes.js` (its `AVATAR*` constants go) and `controllers/admin/notes/composer_controller.js:442–447` to call it.
- Modify `app/components/admin/presence_screen/people_component.{rb,html.erb}`:
  - a here person is `here: true` and `:other`, and an away person is `:away`;
  - the "+N" circle is `AvatarComponent.new(initials: AvatarComponent.more_label(n), size:, tone: :more, ring:)`;
  - `Size`'s `more:` member goes;
  - the header is `:md` and the panel `:sm`, as today;
  - `people.more` leaves `presence_screen.en.yml`.
- Callers that keep their API and change their look only: `NotesScreen::AvatarComponent` (`row` → `:md`, `message` → `:sm`), `ActorAvatarComponent`, `HoldStripComponent`, `HolderAvatarComponent` (its here ring is Task 8's).
- Modify `test/lib/admin_design_rules_test.rb`:
  - `PEOPLE_HUE = /ic-people|(?<![\w-])(?:bg|text|ring|inset-ring|outline|border|fill|stroke)-people(?:-tint)?(?![\w-])|--cs-people/`;
  - `PEOPLE_HUE_ALLOWED` becomes an explicit Hash of path to reason. Today's entries are the chip and the avatar, plus `app/javascript/ui/avatar.js` ("the scripts' circle, held to the component's classes") and `content-spiel.css` ("where the two aliases are written"). The `Dir[…]` of the four old paths goes;
  - add `PEOPLE_RULES`, the stylesheet selectors that may name `--cs-people`. It starts empty, and Tasks 4, 5 and 8 grow it;
  - add `test "the stylesheet draws the people hue only in the people's rules"`, which reads `content-spiel.tailwind.css` rule by rule (`css_rules`, the existing parser);
  - add `test "every people allowance and rule is still used"`;
  - `HAND_BUILT_AVATAR_ALLOWED`: the two scripts go, and `app/javascript/ui/avatar.js` comes in;
  - the 11px test becomes `design_offences(/text-\[(?:[0-9]|10)px\]/)`, and its comment says an avatar's letters join it.

  First `git grep -n "text-\[[89]px\]" -- app` and fix every hit in this task.
- Modify `test/lib/admin_contrast_test.rb`:
  - `test "the people hue reads 7:1 or better on every CS Studio ground, and on its own tint, in both schemes"`, with Q1's figures as floors (7.2 / 9.0 on the tint, 8.5 / 10.1 on surface, 7.8 / 11.2 on paper, 7.0 / 9.0 on sunken, 7.5 / 8.9 on rail, 8.5 / 10.8 on chrome, 8.5 / 8.0 on popover);
  - `test "an avatar's tones: own's surface letters 4.5:1 on people, away's meta 4.5:1 and its dashed edge 3:1 on surface and chrome, more's ink 4.5:1 on sunken"`.
- Test: `test/components/admin/ui/{avatar,actor_avatar}_component_test.rb`, `test/components/admin/presence_screen/people_component_test.rb`, `test/components/admin/notes_screen/*`, `test/components/previews_test.rb`, `test/lib/{admin_design_rules,admin_contrast,component_parts}_test.rb`, `test/components/admin/ui/contract_test.rb`.

**Interfaces:**
- Produces `Admin::Ui::AvatarComponent.new(initials:, size:, tone: :other, ring: nil, here: false)` and `AvatarComponent.more_label(count) -> String`. The `RINGS` are `paper surface ground`, where `:ground` reads `--admin-avatar-ground` from the stylesheet. Also the Tailwind colours `people` and `people-tint`, `ui/avatar.js`'s `avatar(initials, { size, tone })`, and `PEOPLE_HUE_ALLOWED` and `PEOPLE_RULES` for later tasks to grow.

- [ ] **Step 1: Write the failing tests.**
  - `avatar_component_test.rb`:
    - `test "every size draws its initials at 11px, weight 600, upper-case"`;
    - `test "other is the people tint with people letters, own the solid people fill with surface letters, away a dashed edge on surface"`;
    - `test "here adds the inner people ring, and a ground ring is drawn outside it"`;
    - `test "+N past nine reads 9+"`;
    - `test "the scripts' circle is the component's: ui/avatar.js holds its size and tone classes"`;
    - `test "an unknown size, tone or ring is refused"`.
  - `people_component_test.rb`: `test "a here person's circle has the here ring, an away person's is the away tone, and +N is the more circle"`.
  - The guard and contrast tests above. Each guard's pattern test gains samples (`bg-people`, `inset-ring-people`, `var(--cs-people)` match; `people_component`, `peoples` do not).
- [ ] **Step 2: Run them, and verify they fail.** `PGGSSENCMODE=disable bin/rails test test/components/admin/ui/avatar_component_test.rb test/components/admin/presence_screen test/lib/admin_design_rules_test.rb test/lib/admin_contrast_test.rb`.
- [ ] **Step 3: Implement.** Search the tests by hand for `size-6 text-[9px]`, `text-[8px]`, `border-line-strong bg-sunken`, `bg-ink text-paper` near an avatar, `people.more`, and `AVATAR_OWN`. Fix each hit.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components test/lib test/integration/admin/presence_test.rb`.
  - After a build, one file at a time: `admin/presence_test.rb`, `admin/mind_graph_notes_test.rb`, `admin/note_composer_test.rb`, `admin/editing_held_test.rb`, `admin/dashboard_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: people are rose circles: two people tokens and one avatar, drawn by the server and the scripts alike` (body: `Advances #117`).

---

### Task 3: The filter bar's current tab, and the Design System copy (Q11)

**Files:**
- Modify `app/components/admin/ui/tab_links_component.{rb,html.erb}`, as the coordinator relayed from the StudioFilterBar card:
  - the `<nav>` is `rounded-cs border border-field-line bg-surface`;
  - each link is `px-3 py-1.5 text-sm text-dim`, with `border-r border-line last:border-r-0`, and its count `text-count`;
  - the current link is `bg-ink font-semibold text-paper`, its count in paper, with no inset ring;
  - a link that is not current takes `hover:bg-sunken`;
  - focus is a 2px accent outline inside (`focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-accent`), and on the current one a paper ring 4px inside it (`focus-visible:inset-ring-4 focus-visible:inset-ring-paper`).

  Its comment names its four users: the Notes filter, Waiting for you, the Trash tabs and the form builder's tabs.
- Modify `test/support/design_system_entries.rb`:
  - `VERSION = "1794231176-96fb"`;
  - `ENTRIES` gains `NoteMarker` and `PresenceMarker`;
  - `COVERED_BY["Admin::Ui::TabLinksComponent"] = "StudioFilterBar"`.
- Modify `test/lib/admin_contrast_test.rb`: `test "a tab's words are 4.5:1 on the surface, the current one's on ink, and the focus outline 3:1 on the surface and on the current tab's paper ring"`.
- Test: `test/components/admin/ui/tab_links_component_test.rb`, its preview (rest, with_counts), `test/components/admin/dashboard_screen/waiting_panel_component_test.rb`, `test/components/admin/{trash,forms}_screen/tabs_component_test.rb`, `test/lib/component_parts_test.rb`.

**Interfaces:**
- Produces the same `TabLinksComponent.new(tabs:, label:, link_data: {})`, which Task 6 renders.

- [ ] **Step 1: Write the failing tests.**
  - `tab_links_component_test.rb`:
    - `test "the current tab is the ink segment with paper words at 600 and no inset ring; the others dim"`;
    - `test "the frame is the field line on the surface, the cs radius, with a line rule between the segments"`.
  - The contrast test above.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests for `ring-inset ring-paper`, `rounded-button border border-field-line` and `text-meta hover:bg-sunken`. Fix each hit.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components test/lib`.
  - After a build, one file at a time: `admin/trash_test.rb`, `admin/form_builder_test.rb`, `admin/dashboard_test.rb` (Waiting for you's filter).
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: the shared tabs take the filter bar's current tab` (body: `Advances #117`).

---

### Task 4: The note bubble (Q6–Q8, Q22)

**Files:**
- Create `app/components/admin/ui/note_marker_component.{rb,html.erb}`, with a test and a preview (examples `read`, `unread`, `small`, `on_image`, `link`).
  - With an `href` it is a link, `a.admin-notes-marker.no-underline[data-has-notes]`, named by `label`. Without one it is `span.admin-notes-marker.admin-notes-marker--readonly[role=img][data-has-notes]` with `aria-label` and `title`, or `aria-hidden` when `aria_hidden: true` (Waiting for you, whose row's link reads it).
  - Inside: `message_square` and the count. Unread (`data-unread`): `message_square_filled`, and `t(".unread", count:)` ("%{count} new").
  - `size: :row` is 20px and `:small` is 18px. `on_image: true` adds `--on-image`.
  - It knows no feature: the caller hands it the count, unread and the label.
- Create the icon `message_square_filled` in `app/views/admin/shared/_icon.html.erb`: `message_square`'s path, `fill="currentColor"` and no stroke.
- Modify `notes_screen/row_pill_component.{rb,html.erb}`: it keeps `loader`, `render?` and `post_path`, and renders `NoteMarkerComponent`. A post's pill is a link (`size: :row`) and a page's is `:small`. The label is `t(".open_notes", count:)`, or `t(".open_notes_unread", count:)` ("%{count} open notes, new for you", new in `notes.en.yml`).
- Modify `media_library/tile_component.html.erb:10` and `dashboard_screen/waiting_row_component.html.erb:18` to render `NoteMarkerComponent`, with their own words. Both stay `NAMED_EXCEPTIONS` in `notes_boundary_test` (they still name notes).
- Modify `notes_screen/marker_component.html.erb` (the block's button): a third span `admin-notes-marker__unread` holds `message_square_filled`. The stylesheet shows it instead of `__open` while `[data-unread]` is on.
- Modify `controllers/admin/notes/drawer_controller.js` `paint()`:
  - an unread marker's number reads `text.t("notes.script.marker.new", { count })`;
  - its label is `notes.script.marker.open_unread` (keys new in `notes.en.yml`, under `admin.notes.script.marker`).
- Modify `content-spiel.tailwind.css` (`.admin-notes-marker`, :1410–1465), and rewrite its comment:
  - `[data-has-notes]` is `background: var(--cs-people-tint); color: var(--cs-people); border-color: transparent`;
  - `[data-unread]` is `background: var(--cs-accent); color: var(--cs-on-accent)`;
  - a pressable pill's hover underlines its count and changes no fill;
  - `--on-image` keeps `box-shadow: 0 0 0 2px var(--cs-surface)`;
  - the old `line-strong` edge and the accent-tint unread go.

  `PEOPLE_RULES` gains the `[data-has-notes]` rules. `PEOPLE_HUE_ALLOWED` gains nothing: the component draws through the class.
- Modify `test/lib/admin_contrast_test.rb`:
  - `test "a read note bubble is 7:1 on its tint and an unread one 4.5:1 on the accent, in both schemes"`;
  - `test "the on-image bubble's surface ring reads on a photo's placeholder"`.
- Modify `test/lib/admin_i18n_test.rb`: `CONVERTED` gains `note_marker_component.{rb,html.erb}`.
- Contract (`NoteMarkerComponent`):
  - `accessibility:` "A link named by its label when it has an address, otherwise an image named by its label or hidden where its row's link reads it; unread is said in words, not only by its fill.";
  - `motion: :none`, `content_edges: %i[short long]`, `widths: :fluid`, `interface: %i[count label unread href size on_image aria_hidden id data]`;
  - `limits:` "It knows no feature: the count, unread and the label are its caller's.", "It draws nothing at a count of 0.";
  - `states: %i[read unread small on_image link hover focus]`, `keys: %w[unread]`, `slots: []`, `controller: nil`;
  - `keyboard: ["test/system/admin/notes_markers_test.rb", "the notes bubble's keyboard: a posts row's bubble is one Tab stop that opens the post's notes, and the tree's and a tile's take none"]`.
- Test:
  - `test/components/admin/ui/note_marker_component_test.rb` (new);
  - `test/components/admin/notes_screen/{row_pill,marker}_component_test.rb`, `test/components/admin/media_library/tile_component_test.rb`, `test/components/admin/dashboard_screen/waiting_row_component_test.rb`;
  - `test/lib/{admin_design_rules,admin_contrast,component_parts,notes_boundary}_test.rb`;
  - browser `admin/notes_markers_test.rb`, `admin/note_inbox_test.rb`, `admin/media_library_test.rb`.

**Interfaces:**
- Produces `Admin::Ui::NoteMarkerComponent.new(count:, label:, unread: false, href: nil, size: :row, on_image: false, aria_hidden: false, id: nil, data: {})`, which Task 6's rows do not use (they have "● New") and Task 7's rail does not draw.

- [ ] **Step 1: Write the failing tests.**
  - `note_marker_component_test.rb`:
    - `test "read is the people bubble with the outline glyph and the count"`;
    - `test "unread is the accent bubble with the filled glyph and says 3 new"`;
    - `test "with an address it is a link named by its label, without one an image, or hidden where its row's link names it"`;
    - `test "nothing at a count of 0"`.
  - `row_pill_component_test.rb`: `test "a post's pill is the bubble as a link to its notes, a page's the small image, and unread is named new for you"`.
  - `notes_markers_test.rb` (browser):
    - the keyboard test above;
    - `test "an unread block marker says 3 new beside the filled glyph and is named new for you"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests by hand for `admin-notes-marker--readonly` built by hand, `accent-tint` near a marker, `line-strong` near a marker, and the pill's old "without an icon". Fix each hit.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components test/lib test/integration/admin`.
  - After a build, one file at a time: `admin/notes_markers_test.rb`, `admin/notes_drawer_test.rb`, `admin/note_inbox_test.rb`, `admin/media_library_test.rb`, `admin/tree_test.rb`, `admin/posts_list_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: a note count is the people bubble, and unread for you the accent bubble that says new` (body: `Advances #117`).

---

### Task 5: Who is on a row, as avatars (Q9, Q10)

**Files:**
- Create `app/components/admin/ui/presence_marker_component.{rb,html.erb}`, with a test and a preview (`nobody`, `one`, `many`).
  - It draws `span.admin-presence-marker` (`hidden` at count 0) holding `shown` circle slots: `AvatarComponent` `:sm`, `:other`, `here: true`, `ring: :ground`, each `data-presence-avatar`, hidden past `people.size`.
  - It also draws a wide "+N" circle (`data-presence-more`, count − shown), a narrow one (`data-presence-more-narrow`, count − 1), the `sr-only` label (`data-presence-marker-label`) and the shared tooltip.
  - Its `data-messages` carries `ui.avatar.more` and `ui.avatar.many`.
  - `data:` is merged onto the root, so the slot entry keeps its `presence_marker`, `presence_id`, `presence_count`, target and tooltip data.
- Modify `presence_screen/row_marker_component.{rb,html.erb}`:
  - it keeps `loader`, `render?`, `lead`, `said` and `marker_data`;
  - `words(here)` adds `initials:` (decisions table);
  - it renders `PresenceMarkerComponent` with `shown:` from its registration;
  - the `user` icon and the mono count go;
  - its comment's "count in 11px mono" and the handoff numbers go.
- Modify `config/initializers/admin_slots.rb`: `tree.row.markers` passes `shown: 2`, and `posts.row.title` passes `shown: 3`.
- Modify `app/controllers/admin/presence_controller.rb#here`: the JSON carries `initials` through `words`.
- Modify `controllers/admin/presence/list_controller.js`:
  - `show(marker, count, label, initials)` writes each `[data-presence-avatar]`'s `textContent` and `hidden`, and both "+N" texts from `messages(marker).t`;
  - it writes only what differs, as text;
  - its header says it draws circles it holds and computes no letters.
- Modify `content-spiel.tailwind.css`:
  - `.admin-tree-row { container: admin-tree-row / inline-size; --admin-avatar-ground: var(--cs-chrome); }` and `.admin-tree-row--selected { --admin-avatar-ground: var(--cs-sunken); }`;
  - `.admin-presence-marker` sets the overlap (−6px) and `--admin-avatar-ground: var(--cs-surface)` where no row sets it, and shows the wide "+N" and hides the narrow one;
  - `@container admin-tree-row (max-width: 260px)` and `@container admin-list (max-width: 639px)` hide every circle but the first and the wide "+N", and show the narrow one.

  Check first that the tree's geometry guard ("a tree's geometry is its four tokens, written once") lets a row be a size container. If it does not, report NEEDS_CONTEXT.
- Modify `test/lib/admin_design_rules_test.rb`:
  - `PEOPLE_HUE_ALLOWED` gains nothing (the avatar draws the hue);
  - `test "a row's people narrow by the row's own width, never the window"`: the two container blocks exist, and no `@media` block names `admin-presence-marker`.
- Contract (`PresenceMarkerComponent`):
  - `accessibility:` "No Tab stop and no role: its words are visually hidden text, part of the row's link name where it is joined, and the tooltip; the circles are hidden from a screen reader.";
  - `motion: :none`, `content_edges: %i[none short many]`, `widths: :fixed_width`, `interface: %i[people count label shown data]`;
  - `limits:` "It knows no feature: the people's letters, the count and the words are its caller's.", "It is kept true by admin--presence--list, which writes only its text and hidden.";
  - `states: %i[nobody one many]`, `keys: []`, `slots: []`, `controller: nil`;
  - `keyboard: ["test/system/admin/presence_lists_test.rb", "a row's people take no Tab stop: the keyboard passes from the row's link to the next, and the row's words name them"]`.
- Test:
  - `test/components/admin/ui/presence_marker_component_test.rb` (new), `test/components/admin/presence_screen/row_marker_component_test.rb`, `test/components/admin/slots_test.rb`, `test/integration/admin/presence_test.rb`;
  - `test/lib/{admin_design_rules,component_parts}_test.rb`;
  - browser `admin/presence_lists_test.rb`.

**Interfaces:**
- Consumes Task 2's `AvatarComponent` (`ring: :ground`, `here:`) and `more_label`.
- Produces `Admin::Ui::PresenceMarkerComponent.new(people:, count:, label:, shown:, data: {})`, where `people` is an `Array<String>` of initials. `RowMarkerComponent.words(here) -> { count:, label:, initials: }`.

- [ ] **Step 1: Write the failing tests.**
  - `presence_marker_component_test.rb`:
    - `test "it draws shown circles of initials with the here ring, hidden past the people, then +N"`;
    - `test "nobody is a hidden marker that still holds its slots"`;
    - `test "the circles and +N are hidden from a screen reader; the label is the one text"`.
  - `row_marker_component_test.rb`:
    - `test "words carry the named people's initials beside the count and the label"`;
    - the existing tests lose the `user` icon and the mono count.
  - `presence_lists_test.rb` (browser):
    - Review Focus 1 and 2's tests;
    - the keyboard test above;
    - "the tree's row shows a marker when someone else is on that page, the count from two, …" becomes `test "the tree's row shows the avatars of whoever else is on that page, and loses them when they leave; the row is never redrawn"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests by hand for `presence-marker-count`, `name: :user` in a marker, `text-count leading-none` and `[data-presence-marker] svg`. Search for a controller's absence asserted by a fragment of its name (CLAUDE.md). Fix each hit.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components test/lib test/integration/admin/presence_test.rb test/controllers`.
  - After a build, one file at a time: `admin/presence_lists_test.rb`, `admin/presence_test.rb`, `admin/tree_test.rb`, `admin/tree_column_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: the page tree and the posts list show who else is on a row as avatars` (body: `Advances #117`).

---

### Task 6: The Notes screen's list (Q11–Q14, Q16)

**Files:**
- Modify `app/queries/dashboard/notes_for_you.rb` (decisions table):
  - `SHOWS`, `rows(…, show:)`, `total(show:)`, `counts`;
  - `scoped(show)` is private: `mine`, `mine.unread` or `mine.where(reason: "mention")`;
  - `counts` goes through `SqlNodes` (a `COUNT(*) FILTER (WHERE …)` node per scope), with its line saying what it answers.
- Modify `app/controllers/admin/note_inbox_controller.rb#index`:
  - `@show = Dashboard::NotesForYou::SHOWS.find { |show| show.to_s == params[:show] } || :all`;
  - `@counts = @inbox.counts`;
  - pagination by `total(show: @show)`;
  - a page link and the out-of-range link keep `show` unless it is `:all`.

  Its header comment says the three scopes.
- Modify `app/views/admin/note_inbox/index.html.erb`:
  - the heading row: the h1, and "Mark all read" as `button_to … class: Admin::Ui::ButtonComponent.classes(:secondary, size: :small)` while `notes_badge_count.positive?`;
  - under it the filter, `TabLinksComponent.new(tabs:, label: t(".filters.label"))`, its tabs All, Unread, Mentions with `@counts`, each `href` `admin_notes_path(show:)` (no `show` for All), the current one `@show`;
  - the list card;
  - the empty state per scope (Q16).

  Task 7 adds the layout and the rail.
- Modify `notes_screen/inbox_row_component.{rb,html.erb}` (Q12, Q13):
  - the grid is `grid-cols-[26px_1fr_auto]`;
  - the 7px dot and the `sr-only` "Unread" go;
  - the avatar is `NotesScreen::AvatarComponent` (`:row` is `:md`). The nobody circle is the `sunken` circle with `message_square`, 26px;
  - the sentence is `text-sm`: unread ink with the name at 600, read `text-dim` with the name at 500;
  - the where line: the record's chip, `IconChipComponent` `size: :xsmall` with page `structure`/`pages`, post `content`/`posts` (as the dashboard's rows draw it) and image `media`/`media`, or for a block `Admin::Ui::BlockIconComponent.new(definition:, place: :row, block:)`, then the words at 13px dim;
  - the excerpt at 13px meta, one line;
  - the end column: the time (`text-count text-meta`) over the verb, and on an unread row the New chip, `span[data-inbox-new].inline-flex.items-center.gap-1.rounded-pill.bg-accent-tint.px-2.text-count.font-semibold.text-accent` with a 6px `bg-accent` dot (`aria-hidden`) and `t(".new")`.

  The row is still one link, and the verb is still its last child.
- Move `app/components/admin/editor_screen/block_icon_component.rb` to `app/components/admin/ui/block_icon_component.rb` (`git mv`, with its test), as `Admin::Ui::BlockIconComponent`. Its `PLACES` gains `row: :xsmall`. Every caller is updated: `block_card_component.html.erb`, `block_picker_component.html.erb`, `block_tile_component.rb`, `section_card_component.html.erb`, `answers/block_drawing.rb` and `_icon.html.erb`'s comment. So is the guard "a block type's icon is drawn only through BlockIconComponent" (its `except:` path). It declares its contract:
  - `accessibility:` "Decoration hidden from a screen reader: the type's name always stands beside it.";
  - `motion: :none`, `content_edges: %i[none]`, `widths: :fixed_width`, `interface: %i[definition place block]`;
  - `limits:` "A type that names no icon draws nothing.", "Only an icon that follows its block carries an id.";
  - `states: %i[picker card tile section row]`, `keys: []`, `slots: []`, `controller: nil`;
  - `keyboard: ["test/system/admin/note_inbox_test.rb", "an inbox row is one Tab stop: its avatar, chips and New take no focus"]`.

  It gets a preview (one example per place) and `COVERED_BY["Admin::Ui::BlockIconComponent"] = "IconChip"`, provisional, for the design agent (Task 9 lists it).
- Modify `app/components/admin/ui/icon_chip_component.rb`: `SIZES` gains `xsmall: "size-5"`, its limits sentence names three sizes, and its preview gains `xsmall`.
- `config/locales/admin/notes.en.yml`:
  - add `admin.note_inbox.index.filters.{label,all,unread,mentions}` ("Show", "All", "Unread", "Mentions");
  - add `index.empty.all.{title,description}`, `index.empty.unread`, `index.empty.mentions` (Q16's words);
  - add `admin.components.notes_screen.inbox_row.new` ("New");
  - remove `inbox_row.unread` and `index.empty`.
- Modify `test/lib/admin_design_rules_test.rb`: `TINT_PAIR_ALLOWED` gains `inbox_row_component.html.erb` ("the New chip: unread and for you, never pressable"). `ACCENT_FILL_ALLOWED`'s inbox row reason becomes "the New chip's dot".
- Modify `test/lib/admin_contrast_test.rb`: `test "the New chip's accent words and dot hold on the accent tint, in both schemes"`, at the floor the accent-on-tint test already uses (5.7 / 6.2 as it rounds).
- Test:
  - `test/queries/dashboard/notes_for_you_test.rb`, `test/integration/admin/note_inbox_test.rb`, `test/components/admin/notes_screen/inbox_row_component_test.rb`;
  - `test/components/admin/ui/{block_icon,icon_chip}_component_test.rb`, `test/components/admin/dashboard_screen/*`;
  - `test/lib/*`;
  - browser `admin/note_inbox_test.rb`, `admin/dashboard_test.rb`.

**Interfaces:**
- Consumes Task 3's `TabLinksComponent` and Task 2's avatar.
- Produces `Dashboard::NotesForYou::SHOWS`, `#rows(limit:, offset:, show:)`, `#total(show:)`, `#counts -> { all: Integer, unread: Integer, mentions: Integer }`, and `Admin::Ui::BlockIconComponent.new(definition:, place:, block: nil)` with `PLACES` `picker card tile section row`.

- [ ] **Step 1: Write the failing tests.**
  - `notes_for_you_test.rb`:
    - `test "show unread lists the unread deliveries and mentions the mention deliveries, each in the inbox's order"`;
    - Review Focus 3's counts test, which asserts one statement (`assert_queries_count(1)`).
  - `note_inbox_test.rb` (integration):
    - `test "the filter's tabs carry their counts, a count of 0 included, and the shown scope is the current tab"`;
    - `test "an unknown show is All"`;
    - Review Focus 3's out-of-range test;
    - `test "each scope's empty list says its own sentence"`;
    - `test "Mark all read is a small secondary, shown only while something is unread, and the screen draws no primary"`.
  - `inbox_row_component_test.rb`:
    - `test "an unread row has the New chip and no dot or hidden Unread; a read row's sentence is dim"`;
    - `test "the where line leads with the record's chip, and a block's type chip for a note on a block"`.
  - `note_inbox_test.rb` (browser):
    - the keyboard test above;
    - `test "Mentions narrows the list to mentions, its tab current, and a row still opens its thread"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests by hand for `EditorScreen::BlockIconComponent`, `grid-cols-[7px_24px_1fr_auto]`, `setup_secondary_link_class` on the inbox, the `sr-only` "Unread" and `.empty`. Fix each hit.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/queries test/integration/admin test/components test/lib test/controllers`, then `bin/rails zeitwerk:check`.
  - After a build, one file at a time: `admin/note_inbox_test.rb`, `admin/dashboard_test.rb`, `admin/editor_header_test.rb`, `admin/sections_adding_test.rb` (the picker's and the tiles' block icons).
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: Notes for you filters All, Unread and Mentions, and each row shows who and where` (body: `Advances #117`).

---

### Task 7: The rail of open threads (Q15)

**Files:**
- Modify `app/models/notes/message.rb`: add the scope `authors_per_container`, with a line saying what it answers. It answers `container_type`, `container_id`, `author_id` and `MAX(created_at)` per container and author, built with Arel through `SqlNodes`, never a string. It is merged with the threads the caller narrows.
- Modify `app/queries/dashboard/open_threads.rb` (decisions table): `Row` gains `authors` and `author_count`, read in one statement for all rows inside `unresolved.merge(listed)`, and `more_records` is added. Its header says the count of statements, which is still the same for one row as for eight.
- Create `app/components/admin/notes_screen/open_threads_component.{rb,html.erb}`: `OpenThreadsComponent.new(threads:)`, which takes a `Dashboard::OpenThreads`.
  - It draws `section.admin-list-rail__rail.admin-notes-threads[aria-labelledby=open-threads-heading]`, with `h2#open-threads-heading.text-h3` "Open threads" and the line in `text-small text-meta`.
  - Then a `ul` of `OpenThreadRowComponent`s, then `t(".more", count: threads.more_records)` when it is positive, or `t(".empty")` when there are no rows.
- Create `app/components/admin/notes_screen/open_thread_row_component.{rb,html.erb}`: `OpenThreadRowComponent.new(row:)`.
  - It is one `link_to note_route_path(row.route)` with `data: { turbo_frame: "_top", turbo_prefetch: false }`.
  - It holds the record's `IconChipComponent` `:xsmall` (Task 6's families), the title (`text-sm text-ink truncate`, or "(untitled)"), and under it `t(".line", count: row.count, time:)` ("%{count} notes · %{time}", with `TimeAgoComponent`).
  - At its end are `row.authors`' `:sm` avatars (`NotesScreen::AvatarComponent` with `viewer:`), overlapping, then a `:more` circle when `row.author_count > row.authors.size`.
- Modify `app/controllers/admin/note_inbox_controller.rb#index`: `@threads = Dashboard::OpenThreads.new(actor: Current.actor, limit: 8)`.
- Modify `app/views/admin/note_inbox/index.html.erb`: the screen is `div.admin-list-rail`, with `__head` (the h1 and Mark all read) and `__grid` holding, in document order:
  1. the filter;
  2. the list card;
  3. `OpenThreadsComponent`.

  The docked rail is placed by the grid (column 2, rows 1 to 2). Below the threshold it falls after the list (ruling C5).
- Modify `content-spiel.tailwind.css`:
  - `.admin-notes-threads` is a card below the threshold (`--cs-surface`, `--cs-shadow-1`, `--cs-radius-card`, `margin-top: 1rem`), written before the `@container admin-list (min-width: 1200px)` block;
  - inside that block it takes `margin-top: 0`;
  - the block's comment says that an information rail follows the list in the document, as a filter or a detail stands before it.
- Modify `test/lib/admin_design_rules_test.rb`, the lists' rail test: `assert_match(/\.admin-notes-threads\s*\{[^}]*margin-top:\s*0/, docked.first)`, and the card rule stands before the docked block.
- Modify `test/integration/trash_visibility_test.rb`: the Notes screen's rail joins it (a trashed page with an open thread is not a row and not counted in "And N more").
- `config/locales/admin/notes.en.yml`: add `admin.components.notes_screen.open_threads.{heading,line,empty,more}` (`more` as `one`/`other`: "And %{count} more on other pages") and `open_thread_row.line` (`one`/`other`).
- Test:
  - `test/queries/dashboard/open_threads_test.rb`, `test/models/notes/message_test.rb`;
  - `test/components/admin/notes_screen/{open_threads,open_thread_row}_component_test.rb` (new);
  - `test/integration/admin/note_inbox_test.rb`, `test/integration/trash_visibility_test.rb`, `test/lib/admin_design_rules_test.rb`;
  - browser `admin/note_inbox_test.rb`, `admin/dashboard_test.rb`.

**Interfaces:**
- Consumes Task 6's controller and view, and Task 2's avatar and `more_label`.
- Produces `Dashboard::OpenThreads::Row#authors -> Array<User>`, `#author_count -> Integer`, `OpenThreads#more_records -> Integer`, and `Notes::Message.authors_per_container`.

- [ ] **Step 1: Write the failing tests.**
  - `open_threads_test.rb`:
    - `test "each row names the newest two people who wrote on its open threads and how many wrote, in the same statements for one row as for eight"`;
    - Review Focus 4's test;
    - `test "more_records is the readable records with open threads beyond the rows"`.
  - `open_thread_row_component_test.rb`:
    - `test "a row is one link to the record's notes that does not prefetch, with its chip, title, count line and two avatars then +N"`;
    - `test "an untitled record reads (untitled)"`.
  - `open_threads_component_test.rb`:
    - `test "the rail is a section named by its heading, says how many more, and says No open threads. with none"`.
  - `note_inbox_test.rb` (browser): `test "the rail of open threads docks beside the list from 1200px of the list's width, and falls after it below"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests by hand for `max-w-[880px]` on the Notes screen. Fix each hit.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/queries test/models/notes test/components/admin/notes_screen test/integration test/lib`.
  - After a build, one file at a time: `admin/note_inbox_test.rb`, `admin/dashboard_test.rb` (Waiting for you reads `OpenThreads`).
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: the Notes screen has a rail of open threads` (body: `Advances #117`).

---

### Task 8: Live editing in the people hue (Q17–Q21)

**Files:**
- Modify `editor_screen/hold_strip_component.{rb,html.erb}`, the held branch (Q17):
  - the strip is `@container flex flex-wrap items-center gap-2 border-b border-line bg-people-tint px-3.5 py-2`;
  - the sentence is `text-small text-ink`, its name at 600 (the key becomes `held_html` with `name:` as a `tag.strong`, and the name escaped);
  - the avatar is `:md`, `:own` or `:other`, with `here: true` for `:other`;
  - Take over stays `:secondary, size: :small`;
  - below 480px of the strip the button takes a full row at the start (`@max-[480px]:basis-full`, or what the build offers for a container's max width).

  The lost and deleted branches are unchanged. `PEOPLE_HUE_ALLOWED` gains the template ("the hold strip's ground").
- Modify `editor_screen/holder_avatar_component.html.erb`: `here: true` for `:other`.
- Modify `editor_screen/updated_mark_component.{rb,html.erb}` (decisions table):
  - the colleague's `:sm` avatar (`:other`) before the words, at `text-label text-meta`;
  - `taken_over: true` reads `t(".taken_over")` ("Taken over by you") and `t(".just_now")`, with no avatar.
- Modify `editor_screen/block_card_component.html.erb`: the head always holds `span[data-editing-mark-place]`, where the updated mark stands when there is one. It stays an `EDITOR_CARDS` file, so no border utility is added.
- Modify `editor_screen/live_region_component.html.erb`: add the `takenOver` template.
- Create `app/javascript/editing/marks.js` (`showMark`, `fadeMark`). Modify `controllers/admin/editing/live_controller.js` (`fade` becomes `fadeMark`) and `hold_controller.js`. A take-over that stood calls `showMark(unit, this.takenOverTarget)`, then `fadeMark(mark, { after: this.noticeValue })`. Add the `takenOver` target.
- Modify `content-spiel.tailwind.css`:
  - the state edges (:1354–1371, :1397) become the people frame of the decisions table. Its comment says one outline for held and discussed, the section's outside its frame, and the unavailable edge and the chosen section written after it;
  - the glow: `.admin-block-card:has([data-editing-mark]:not(.admin-editing-mark--leaving)):not([data-card-edge="held"])` takes `box-shadow: var(--cs-shadow-1), 0 0 0 4px color-mix(in oklab, var(--cs-people) 20%, transparent)`, with a transition on `box-shadow` of 200ms in and 600ms out on `--cs-ease`;
  - under `@media (prefers-reduced-motion: reduce)` there is no glow and no transition;
  - `PEOPLE_RULES` gains the frame's and the glow's selectors.
- Modify `test/lib/admin_design_rules_test.rb`:
  - the two state-edge tests (:240–:272) are rewritten as Review Focus 5's test;
  - `test "a tile's states are elevations"` still passes, since the outline is no border;
  - `EDITOR_CARDS` is unchanged.
- Modify `test/lib/admin_contrast_test.rb:158–172, :243`:
  - the held edge is the people outline, `test "the people outline is 3:1 or better on the card, the tile, the canvas and a section's head, in both schemes"`;
  - `test "the held strip's words, its Take over and its edge hold on the people tint"` (Q17's figures);
  - the notes-active accent assertion goes.
- `config/locales/admin/editor_screen.en.yml`: `hold_strip.held_html`, and `updated_mark.taken_over` and `.just_now`.
- Test:
  - `test/components/admin/editor_screen/{hold_strip,holder_avatar,updated_mark,live_region,block_card}_component_test.rb`, `held_fields_test.rb`;
  - `test/lib/{admin_design_rules,admin_contrast}_test.rb`;
  - browser `admin/editing_held_test.rb`, `admin/editing_take_over_test.rb`, `admin/editing_merge_test.rb`, `admin/changed_elsewhere_test.rb`, `admin/editing_holds_test.rb`, `admin/notes_markers_test.rb`.

**Interfaces:**
- Consumes Task 2's avatar.
- Produces `UpdatedMarkComponent.new(change: nil, taken_over: false)`, `editing/marks.js` (`showMark(unit, template) -> Element`, `fadeMark(mark, { after: Number })`) and the target `admin--editing--hold-target="takenOver"`.

- [ ] **Step 1: Write the failing tests.**
  - `hold_strip_component_test.rb`: `test "the held strip is on the people tint with the holder's name at 600, their avatar ringed as here, and Take over the small secondary"`.
  - `updated_mark_component_test.rb`:
    - `test "the colleague's avatar stands before Updated by"`;
    - `test "taken over says Taken over by you · just now, with no avatar"`.
  - `holder_avatar_component_test.rb`: `test "a colleague's avatar is ringed as here"`.
  - Browser:
    - `editing_take_over_test.rb`: `test "after a take-over the head says Taken over by you for six seconds, then the mark fades"`;
    - `editing_merge_test.rb`: Review Focus 5's glow test;
    - `notes_markers_test.rb`: "the block whose thread is open is marked, and unmarked when the drawer shows the list again" asserts the computed outline colour is `--cs-people`'s.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests by hand for `bg-sunken px-3.5 py-2`, `outline: 2px solid var(--cs-field-line)` and `var(--cs-accent)` near `data-notes-active`, `fade(` in `live_controller.js`, and `admin-editing-mark`. Fix each hit.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components/admin/editor_screen test/lib test/integration/admin/editing_test.rb test/controllers/admin/answers`.
  - After a build, one file at a time: `admin/editing_held_test.rb`, `admin/editing_take_over_test.rb`, `admin/editing_merge_test.rb`, `admin/changed_elsewhere_test.rb`, `admin/editing_holds_test.rb`, `admin/editing_live_test.rb`, `admin/notes_markers_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: live editing in the people hue: the hold strip, one people outline, and Updated by with its avatar` (body: `Advances #117`, `Advances #132` for `editing/marks.js`).

---

### Task 9: The reference, the rule, CLAUDE.md, the pull request and the Design System cards

**Files:**
- Modify `docs/reference/design-system.md`:
  - a part "E4: working together": the people tokens and where they may stand, the avatar (sizes, tones, rings, "+N"), the note bubble's three states, the presence stack and its narrowing, the Notes screen's filter, rows, New chip and rail, the hold strip, the people outline and the glow;
  - "Component contract": the new rule, in one paragraph — **a component used by more than one screen that a stage touches moves to `app/components/admin/ui/` and takes the full contract (states with previews, keys, a Design System entry, and a keyboard browser test, or the test that holds that the keyboard passes over it). Being moved, it is not on `MADE_BEFORE_CONTRACT`. A feature's slot entry stays in the feature's folder and renders the shared part.** It names this stage's three, `NoteMarker`, `PresenceMarker` and `BlockIcon`;
  - the "Accent" paragraph names the unread bubble and the New chip;
  - "Rules a change can break silently" gains:
    - a presence stack's circles are written by `admin--presence--list` alone, from the server's initials, and **no guard** for a second writer;
    - a component shared by a second screen moves to `ui/`, and **no guard**: a convention held at review;
    - `ui/avatar.js` is the scripts' one circle, held to the component for `sm` and `md`, and **no guard** for the `lg` size in a script.
- Modify `docs/reference/notes.md`: the markers (the bubble, `NoteMarkerComponent`, `message_square_filled`, "3 new"), the Notes screen's filter (`SHOWS`, `counts`) and its rail (`OpenThreads#authors`, `more_records`), and `PersonName.of` in place of `Notes.name_of` (if Task 1 left any).
- Modify `docs/reference/presence.md`: the row stack, `PresenceMarkerComponent`, `words`' initials, the narrowing containers, and the ground ring.
- Modify `docs/reference/live-editing.md`: the strip, the people outline, the glow, the take-over mark, and `editing/marks.js`.
- Modify `docs/reference/slots.md`: one paragraph on a slot entry rendering a shared `ui/` part.
- Modify `docs/reference/cs-studio-shell-and-dashboard.md`: Waiting for you's bubble and the tabs' look.
- Modify `docs/reference/i18n.md`, if its tables list the moved keys.
- Modify `CLAUDE.md`:
  - "Where a component goes": add the sentence "A component used by more than one screen that a change touches moves to `app/components/admin/ui/` and takes the full contract; a feature's slot entry stays in the feature's folder and renders it.";
  - the design-system index line names `AvatarComponent`'s people tones, `NoteMarkerComponent`, `PresenceMarkerComponent`, `BlockIconComponent` and `ui/avatar.js`;
  - the content-blocks line's `editor_screen/block_icon_component.rb` becomes `ui/block_icon_component.rb`;
  - the notes, presence and live-editing index lines name the new files;
  - the "Rules a change can break silently" bullets that name `BlockIconComponent`'s path follow it.
- Modify `test/support/design_system_entries.rb`: ask the controller for the artifact's index id at this time (the implementer does not read the artifact), and set `VERSION` to it if it differs from `1794231176-96fb`.
- Modify `CHANGELOG.md`, `## Unreleased`, Changed:
  - People in CS Studio are rose circles with their initials, and a note count is a rose bubble; unread notes for you are the accent bubble that says how many are new.
  - The page tree and the posts list show who else is on a page or post as avatars.
  - Notes for you can show All, Unread or Mentions, shows who wrote and where on each row, and lists the open threads beside the list.
  - A block someone else is editing has a rose strip and outline, and "Updated by" shows who.
  - The tabs of Waiting for you, Trash and the form builder mark the current tab as the filter bar does.
- Test: `PGGSSENCMODE=disable bin/rails test test/lib`, `bin/rubocop`, `bin/rails zeitwerk:check`, `bin/brakeman`, `bin/changelog-guard main`.

- [ ] **Step 1: Write the reference, CLAUDE.md and CHANGELOG changes.**
- [ ] **Step 2: Run** the five checks. Expected: all pass.
- [ ] **Step 3: Write the PR body.**
  - Findings: Closes #140. Advances #117 and #132 (`editing/marks.js`). The check of the open `architecture-review` issues (below).
  - "For the owner to check":
    - ruling C1 (shared looks in `ui/`, slot entries kept);
    - the rail after the list (C5);
    - rows that show here people only (C3);
    - the posts pill now has its glyph (C15);
    - `TabLinksComponent`'s redraw on Trash and the form builder;
    - "And 4 more on other pages" for posts and images too (C17).
  - Documentation, in `/Users/dknafelj/src/contentspiel-docs`, for all three readers:
    - **Editors:** `docs/editors/working-together/notes-on-content.md` (the bubble, "new", Notes for you's filter and the rail), `who-else-has-this-open.md` (avatars in the tree and the posts list), `live-refresh-and-edit-reservations.md` (the strip, the outline, "Updated by", "Taken over by you"), `docs/editors/getting-started/signing-in-and-finding-your-way.md` (the Notes item's count). Also the screenshots of each, retaken in both themes.
    - **Administrators:** `docs/administrators/people/users-and-owners.md`, if it shows a person's circle or names `display_name`; otherwise "none".
    - **Integrators:** `docs/integrators/theming/extending-cs-studio.md` and `docs/integrators/how-it-works/how-the-cms-is-put-together.md` (a slot entry renders a shared `ui/` part; `PersonName.of` and `User#name_or_email`).
- [ ] **Step 4: The Design System cards to update**, for the design agent:
  - `Avatar`: the sizes, tones, rings and "+N" as built (`AvatarComponent`, `ui/avatar.js`);
  - `NoteMarker`: built as `Admin::Ui::NoteMarkerComponent` (count, label, unread, href, size, on_image, aria_hidden), the block's button `NotesScreen::MarkerComponent` with it, and `message_square_filled`;
  - `PresenceMarker`: built as `Admin::Ui::PresenceMarkerComponent`, with its narrowing;
  - `StudioFilterBar`: TabLinks' four users;
  - `StudioHeldStrip`: the strip, the outline, `HolderAvatarComponent`, the Updated and Taken over marks, the glow;
  - `StudioNotesThread`: the avatars only;
  - `IconChip`: the `xsmall` size, and confirm or rename `BlockIconComponent`'s card (provisionally `IconChip`);
  - `FoundationIcons`: `message_square_filled`;
  - `StudioCalmE4Together`: its status to built.
- [ ] **Step 5: Check no test run is left**: `pgrep -f "rails test"` prints nothing.
- [ ] **Step 6: Commit** `docs: E4 stage 6 in the reference and CLAUDE.md, and the shared-component rule` (body: `Advances #117`).

---

## Architecture-review findings

Checked on 2026-11-09 against every open issue labelled `architecture-review` (`gh issue list --label architecture-review --state open`). Task 9 runs the check again, and a new issue whose code a task rewrote is taken in that task.

| Issue | Taken | Why |
|---|---|---|
| #140 one name for a person's short name | closes, Task 1 | the spec: stage 6 redraws every avatar and name |
| #117 comments about invariants | advances, every task | the notes, presence and editing files carry "handoff 32", "spec §5.1", "decision D3", "Ruling 7"; each task rewrites the comments of the files it touches |
| #132 split the largest scripts and controllers | advances, Task 8 | `hold_controller.js` (783 lines) is touched for the take-over mark, and the mark's show and fade go to `editing/marks.js` with `live_controller.js`'s fade, so neither controller grows. The rest (`table_controller.js`, the rich-text editor controller, the posts and pages controllers) is not stage 6's |
| #127 slots fit one shape | not taken | the slots keep their shape: `RowPill` and `RowMarker` keep their registrations, with `shown:` as an option. The posts table's Notes column header is not touched |
| #133 entry cost of a system test | not taken | its remainder (shorter names) is not in these files; the rewritten tests begin on `visit_screen` or `visit_editor` |
| #119 the reference docs' structure | not taken | paragraphs of six reference files change, not their structure |
| #143 Solid Cable polling | not taken | presence and notes keep their subscriptions; nothing new listens |
| #112, #114, #116, #121, #122, #124, #128–#131, #135–#138, #141, #142, #185 | not taken | no task changes their code |

## Browser tests

Run locally after `bin/rails tailwindcss:build`, one file per command, only while the one-minute load is under 6 and no `rails test` runs, each prefixed with `PGGSSENCMODE=disable`.

**The implementer must run:**
- Task 1: `admin/note_reactions_test`, `admin/users_test`.
- Task 2: `admin/presence_test`, `admin/mind_graph_notes_test`, `admin/note_composer_test`, `admin/editing_held_test`, `admin/dashboard_test`.
- Task 3: `admin/trash_test`, `admin/form_builder_test`, `admin/dashboard_test`.
- Task 4: `admin/notes_markers_test`, `admin/notes_drawer_test`, `admin/note_inbox_test`, `admin/media_library_test`, `admin/tree_test`, `admin/posts_list_test`.
- Task 5: `admin/presence_lists_test`, `admin/presence_test`, `admin/tree_test`, `admin/tree_column_test`.
- Task 6: `admin/note_inbox_test`, `admin/dashboard_test`, `admin/editor_header_test`, `admin/sections_adding_test`.
- Task 7: `admin/note_inbox_test`, `admin/dashboard_test`.
- Task 8: `admin/editing_held_test`, `admin/editing_take_over_test`, `admin/editing_merge_test`, `admin/changed_elsewhere_test`, `admin/editing_holds_test`, `admin/editing_live_test`, `admin/notes_markers_test`.

**Likely to change, left to CI** (the whole browser suite runs per PR):
- `theme_toggle_test` (people in dark);
- `admin/notes_rail_test`, `admin/notes_flow_test`, `admin/notes_live_test`, `admin/notes_view_only_test`, `admin/note_files_test`, `admin/messages_test` (avatars and bubbles);
- `admin/mind_graph_list_test` (the tree's row container);
- `admin/audit_log_test` (the actor's circle);
- `admin/users_test` (the rename).

A CI failure is fixed in the task that owns the file.

## Pre-flight

Done while writing this plan, against `main` at faace458, the answers (v153 and v155's mapping) and the coordinator's brief.

- **Red mid-stack.**
  - Task 2 changes every avatar's size and tone. It fixes the tests that read `size-6`, `text-[8px]`/`[9px]`, `bg-sunken` or `bg-ink` on a circle, and the presence "+N" key.
  - Task 4 changes the pill's markup on four screens.
  - Task 5 removes the `user` icon and the mono count that `presence_lists_test` reads.
  - Task 6 moves `BlockIconComponent` and changes the inbox row that the dashboard's card draws too.
  - Task 8 rewrites the state-edge guards.

  Each fixes the tests it breaks.
- **A file changed in two tasks.**
  - `notes_screen/inbox_row_component.*`: its avatar size in Task 2, its row in Task 6.
  - `note_inbox_controller.rb` and `index.html.erb`: the filter in Task 6, the layout and the rail in Task 7.
  - `admin_design_rules_test.rb`: the people lists are made in Task 2 and grown in Tasks 4, 5 and 8.
  - `design_system_entries.rb`: Task 3, then a check in Task 9.
  - `content-spiel.tailwind.css`: Tasks 2, 4, 5, 7 and 8, each in its own rules.
  - `hold_strip_component` and `holder_avatar_component`: their look in Task 2, their ring and ground in Task 8.
- **Keys before their reader.** `avatar.more` and `.many` arrive in Task 2, `note_marker.unread` and the pill's `open_notes_unread` in Task 4, the filter's and the New chip's keys in Task 6, the rail's in Task 7, and the strip's and marks' in Task 8. `presence_screen.people.more` and `inbox_row.unread` are deleted where their reader goes.
- **Guard lists.**
  - `PEOPLE_HUE_ALLOWED` and `PEOPLE_RULES` are made in Task 2 and grown in Tasks 4, 5 and 8.
  - `HAND_BUILT_AVATAR_ALLOWED` loses two scripts and gains `ui/avatar.js` (Task 2).
  - `TINT_PAIR_ALLOWED` gains the inbox row, and `ACCENT_FILL_ALLOWED`'s inbox row reason changes (Task 6).
  - `MADE_BEFORE_CONTRACT` is unchanged, and `KEYBOARD_NOT_YET` stays empty: each new or moved component names its keyboard test in its own task.
  - `DesignSystemEntries` gains `NoteMarker` and `PresenceMarker`, and moves TabLinks and BlockIcon (Tasks 3 and 6).
  - `notes_boundary_test`'s `NAMED_EXCEPTIONS` keep the media tile and Waiting for you.
  - `CONVERTED` grows in Tasks 4 to 8.
- **Tests a mutation would not fail.**
  - The people guards' pattern tests carry samples that match and do not.
  - `PEOPLE_RULES` has a "still used" test.
  - The avatar script test compares strings with the component's constants, not copies.
  - The counts test asserts one statement.
  - The open threads test asserts the same statements for one row and eight.
- **Not reproduced while planning.** No test database exists in this worktree, so nothing was run. Whether Tailwind 4 composes `ring-2` with `inset-ring-[1.5px]`, and whether `@max-[480px]:` builds, are read from Tailwind's documentation, not tried. Task 2 and Task 8 try them first.
- **History comments.** Every task ends on the grep in "Comment rule", run over the lines it added.

### Conflicts found, and rulings

| C | Conflict | Ruling | Why |
|---|---|---|---|
| C1 | The brief moves `NotesScreen::MarkerComponent`, `RowPillComponent` and `PresenceScreen::RowMarkerComponent` into `ui/` under new names. But they are the notes and presence features' slot entries: their loaders read `Notes::Counts` and `Presence::Roster`, and their words live in `notes.en.yml` and `presence_screen.en.yml`. The slot pattern (`docs/reference/slots.md`) and `source_layout_test`'s one exception (`notes.en.yml`, "moving them … would put notes' strings in core files") keep a feature's components and words out of core files. | **Ruled differently, for the owner to confirm.** The shared *drawing* moves to `ui/` with the full contract (`NoteMarkerComponent`, `PresenceMarkerComponent`), knowing no feature. The slot entries keep their names, loaders and words, and render it. The block's button (`MarkerComponent`) stays: only the editor draws it, and it shares only the stylesheet's look. If the owner wants the literal move instead, Tasks 4 and 5 change their file lists, not their tests. | It keeps the rule "a shared look in `ui/`" and the slot boundary both true. The media tile and Waiting for you, which draw the same bubble by hand, draw it through the one component. |
| C2 | Whether `HolderAvatarComponent` moves. | It stays in `editor_screen/` (the design agent: its one user is `editor.block.markers`). | Not drawn outside the editor. |
| C3 | Q9 draws `:away` in rows, but the loader (`here_people`) returns people who are here only, and "someone who is only away does not count". | Rows draw here people only: `:other` with the here ring. `:away` stays in the header's and the panel's `PeopleComponent`. | The spec: "from what the loader already returns". |
| C4 | Q15 draws the last two people per row, and `OpenThreads` reads one (`last_author`). | `Row#authors` and `#author_count`, from one more statement for all rows. | The count of statements must not grow with the rows. |
| C5 | Q15 puts the rail after the list below the threshold. But the lists' rail rule says "the rail comes before the list at every width". | An information rail follows the list in the document. The grid docks it in column 2 from row 1, so nothing is moved by script, and the focus order is heading, filter, list, rail. The comment and `design-system.md` say a filter or detail rail stands before and an information rail after. | Q15: "it is information, not a filter". The order is the document's at every width. |
| C6 | Q18 names "one class, `.admin-people-frame`". But a state edge is "an outline from `data-card-edge` or `data-notes-active`, never" a mark a script adds, and a frozen card's edge is never written by the merge. | No class. One rule with a selector list of the existing marks (decisions table). A section never has `data-notes-active` (a section has no marker: notes' own rule), so its outline comes from the frozen form alone, at offset 2px. `[data-chosen]` and unavailable win. | The people frame is a rule, not an element's class, and nothing a script writes changes. |
| C7 | Q4's here ring is a box-shadow, while the elevation guard refuses arbitrary `shadow-[…]`, and the separating ring is a box-shadow too. | Tailwind 4's `inset-ring` with `ring`, which compose. | No arbitrary shadow, and both rings stand. |
| C8 | Q11 names `rows(reason: "mention")`, and Unread needs a scope too. | `show:`, one keyword for three scopes. | One mapping from the parameter. |
| C9 | Q21's mark needs a script path, and the hold script holds no wording. | A server template, plus `editing/marks.js`. | The deleted strip's pattern. #132: the controller does not grow. |
| C10 | Q12 draws a block's type chip on the inbox row. The guard draws a type's icon only through `EditorScreen::BlockIconComponent`, which would then serve two screens. | It moves to `Admin::Ui::BlockIconComponent` with the full contract (the new rule), with `place: :row`. Its card is provisionally `IconChip`. | The rule Task 9 writes, applied to the first component that meets it. |
| C11 | Q12 and Q15 draw a 20px chip, and `IconChipComponent` has 24 and 22. | `xsmall: "size-5"`. | The answer's size. The name `:sm` is the avatar's, so the chip's follows its own scale. |
| C12 | The brief gave `VERSION` 1794231049-d0b3, the coordinator's later message 1794231176-96fb, and the file holds 1794187215-67d0. | Task 3 writes 1794231176-96fb, and Task 9 re-asks the controller. | The latest word. |
| C13 | The spec says "its `CLAUDE.md` bullet deleted" for `name_of`. | `CLAUDE.md` names `Notes.name_of` nowhere today (#149 removed it). Task 1 changes the code, the comments and the reference files, and Task 9 checks `CLAUDE.md` again. | — |
| C14 | `Invitation#display_name` has the same rule, and the users list duck-types rows. | It is renamed with `User`'s. | One name for one rule. |
| C15 | Q6 gives every pill its glyph, while the posts pill today has "no icon". | The glyph everywhere. The PR body says so. | Q6. |
| C16 | Q10's "a row whose title would be cut to under 8 characters" cannot be read by a stylesheet. | The tree's container threshold (260px) alone. | The answer's own mechanism is the container query. |
| C17 | Q15's "And 4 more on other pages" is said of posts and images too. | The answer's words, flagged for the owner. | A wording question is the design agent's. |
| C18 | Q22, the sidebar's bubble. | Already the accent fill (`sidebar_component.rb:88`). No change; Task 4 checks it. | — |
| C19 | The Trash tabs' label "Filter by type" is a literal. | Left for 7a. Task 3 changes the look only. | Not converted in this stage. |
