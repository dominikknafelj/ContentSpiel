# Version history Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A History screen for a page or post that lists its published versions, compares any two (or one with the working version), and restores one as unpublished changes; and a Publish now dialog that offers to publish a scheduled record with its later changes.

**Architecture:** A version is a row of `published_versions` (`Publishing::Version`). Comparing generalises `Publishing::Changes` to two stored sides; restoring generalises `Publishing::DiscardChanges`' reconciliation into a shared module that both services include. The screen is a plain CS Studio screen (`Admin::HistoryController`, components in `app/components/admin/history_screen/`); the restore and Publish now dialogs follow the publishing dialogs' rules (drawn once, asked when they open, `_top` forms behind `admin--saving--queue-hold`).

**Tech Stack:** Rails 8.1, Minitest + fixtures, ViewComponent, Stimulus over import maps, Tailwind, Cuprite browser tests.

**Spec:** `docs/superpowers/specs/2026-11-16-version-history-design.md` (read it whole; rulings R1–R17, D9 and §11 are the requirements). Read `docs/reference/publishing.md` before any task, and `docs/reference/writing-tests.md` before writing a test (`test/system/README.md` before a browser test).

## Global Constraints

- Every commit ends with exactly these two lines, and commits name their paths explicitly (`git commit -- <paths>`):
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT`
- Work only in `/Users/dknafelj/src/ContentSpiel-history` (branch `version-history`). Never push, merge, rebase or force; never touch `/Users/dknafelj/src/ContentSpiel-media`, port 3100, the database `content_spiel_nordlicht` or `/Users/dknafelj/src/Nordlicht`.
- Test commands are prefixed `PGGSSENCMODE=disable`. A browser test file runs alone, only when `sysctl -n vm.loadavg`'s first figure is under 6 and no other `bin/rails test` runs (`pgrep -fl "rails test"`). Never run a build while tests run.
- Comments state invariants, hazards or reasons; never history or plan steps. No compatibility code.
- Every string a person reads in CS Studio is an i18n key (`config/locales/admin/<component folder>.en.yml`, `t(".key")`); the audit sentence goes in `Audit::Sentence`.
- Queries: Active Record, then Arel via `SqlNodes`, then SQL with `# sql: <reason>`; a query is a named scope or a method of the query object that owns it.
- Lock order: `ContentTypes.hold!` (through `ContentBlocks::Structure#lock_owner`), then the record's row, then block rows.
- A restore writes rows only through `Pages::Save`, `Posts::Save` and the block services; it never takes, rewrites or removes a copy, and never changes `published_at`, the slug or the tree.
- A record outside the viewer's scope answers 404 (`AccessControl.scope`), never 403.
- Words and look: the Design System card StudioHistory (saved under `.superpowers/sdd/2026-11-16-version-history/cards/`); where the plan and the card differ, the card wins.

## Review Focus

1. A version that holds an image deleted or trashed since: restore and discard both succeed, leave the image empty and count it (Task 2 pins it).
2. A restore pressed after a colleague saved the record since the dialog opened: refused with the stale sentence, nothing written (Task 3).
3. A restore while another tab holds a block of the record: refused by the controller, nothing written (Task 7).
4. Publish now "with the later changes" on a scheduled record that also has a pending change copy: the site shows the rows' new copy at once, the pending copy is withdrawn, the scheduled copy stays in history (Task 4).
5. A viewer with `pages.edit` but not `pages.publish` on a live page: sees the history, is offered no restore, and a forged restore POST is refused and audited as `access.denied` (Task 6 and Task 7).

---

### Task 1: Comparing two sides (`Changes.between`, `TextDiff`)

**Files:**
- Modify: `app/models/publishing/changes.rb`
- Create: `app/values/publishing/text_diff.rb`
- Test: `test/models/publishing/changes_test.rb`, `test/values/publishing/text_diff_test.rb`

**Interfaces:**
- Produces: `Publishing::Changes.between(record, from:, to:) -> Publishing::Changes`, each side a `Publishing::Version` of that record or the Symbol `:working` (the rows, `Snapshot.of(record)`); the same readers as today (`fields`, `blocks`, `locales`, `none?`) plus `sides -> [Hash, Hash]`, the two stored forms `{ "fields", "tags", "blocks" }` (was, now). `Changes.of` and `new(record, version)` keep their meaning.
- Produces: `Publishing::TextDiff.field(changes, name, locale:) -> Publishing::TextDiff::Entry` and `Publishing::TextDiff.block(changes, change, locale:) -> Entry` (`change` a `Changes::Block`), `Entry = Data.define(:label, :before, :after, :result)` where `result` is a `Translations::SourceDiff::Result` (`segments`, `too_long`, `formatting_only?`), or `nil` when the side is absent (an added or removed block).

- [ ] **Step 1: Write the failing tests** in `changes_test.rb`:
  - `"between two copies names what the later one changed, in either order"`: publish a page (copy 1), change its title and a block's body, `publish_changes` (copy 2); `Changes.between(page, from: v1, to: v2).fields` includes `"title"`, its `blocks.map(&:kind)` is `[:changed]`; swapping `from`/`to` gives the same names.
  - `"a version compared with the working version is the overview of the rows"`: `Changes.between(page, from: version, to: :working)` equals `Changes.new(page, version)` in `fields`, `blocks` and `locales`.
  - `"a block back under a new id between two copies is the block it was"`: delete a block, publish (copy 2), discard is not involved: re-create the same block content at the same place, publish (copy 3); `between(v1, v3).none?` is true.
  In `text_diff_test.rb`:
  - `"a title change in one language diffs words in that language only"`: `TextDiff.field(changes, "title", locale: :de).result.segments` holds the removed and added words; for `:en` (unchanged) `result.changed?` is false.
  - `"a rich-text body is compared as its Markdown"`: a block whose body gained a word → segments name that word; a body that only became bold → `result.formatting_only?`.
  - `"a body past the word limit says too long"`: 4001 words → `result.too_long` is true.
  - `"an added block has no before"`: `entry.before` nil, `entry.result` nil.
- [ ] **Step 2: Run them, expect failure** — `PGGSSENCMODE=disable bin/rails test test/models/publishing/changes_test.rb test/values/publishing/text_diff_test.rb` → NoMethodError `between`, NameError `TextDiff`.
- [ ] **Step 3: Implement.** Refactor `Changes#initialize` to take the two stored sides (`was:`, `now:`); `of` and `new(record, version)` build them as today; `between` builds each side from a version (`{ "fields" => v.snapshot["fields"], "tags" => v.snapshot["tags"] || [], "blocks" => v.blocks }`, the shape `initialize` already builds) or `Snapshot.of(record)` for `:working`. `TextDiff` reads the text of a field in a locale from a side (translated columns are `{ locale => value }`), a rich-text document through `RichText::Markdown` (its `to_markdown`-style reader in `app/models/rich_text/markdown.rb`), a block's text as its body in that locale, its caption and its `translated_settings`/`settings` values joined by schema label (`ContentModel::Definition::Field#label`, never `humanize`), and runs `Translations::SourceDiff.call(from:, to:)`.
- [ ] **Step 4: Run the two files and `test/models/publishing/` whole** — all pass.
- [ ] **Step 5: Commit** `feat: compare two published versions`.

### Task 2: One reconciliation for discard and restore; images and tags that are gone

**Files:**
- Create: `app/services/publishing/return_to.rb` (a module)
- Modify: `app/services/publishing/discard_changes.rb`
- Test: `test/services/publishing/discard_changes_test.rb`

**Interfaces:**
- Produces: `Publishing::ReturnTo` (included by a service that also includes `ContentBlocks::Structure`): `return_to!(version) -> ReturnTo::Outcome`, `Outcome = Data.define(:images_missing, :tags_missing)` (Integers). It writes the page's or post's rows to `version`'s content in the order DiscardChanges uses today (what the target lacks first, sections before their blocks, places last, only what differs), inside the caller's transaction and lock. It touches no copy and no pending copy.
- Produces: an image id in `version` that names no `Media::Asset`, or one in the trash, is written as `nil` (the hero, an image block's `media_asset_id`) and counted in `images_missing`; a rich-text image node is left as stored (it renders nothing, as a rebuilt copy does). A tag id that no longer exists is skipped and counted in `tags_missing`.

- [ ] **Step 1: Write the failing tests** in `discard_changes_test.rb`:
  - `"a discard of a copy whose image is in the trash leaves the image empty and succeeds"`: a published page with an image block showing image X; change the block's text in the rows; trash X behind the services (`X.update_columns(trashed_at: Time.current) # version: none (a test trashes an image the copy shows)`); discard → `result.ok?`, the block's `media_asset_id` is nil, the text is the copy's, `result.notice` includes `IMAGES_GONE`.
  - `"a discard leaves the existing tests green"`: no new test; the whole file and `test/integration/admin/publishing_test.rb` pass unchanged.
- [ ] **Step 2: Run, expect failure** (today the discard raises on the foreign key or refuses the image).
- [ ] **Step 3: Implement.** Move DiscardChanges' `restore_page`, `restore_post` and their helpers into `ReturnTo#return_to!`; DiscardChanges calls it, then withdraws the pending copy and settles the mark as today. The image check is one statement per call (`Media::Asset` ids present and not trashed, read through the model's own trash scope). A notice sentence for missing images joins `REMAINS` as a constant beside it (`IMAGES_GONE`, English as the existing service sentences are).
- [ ] **Step 4: Run** `test/services/publishing/ test/integration/admin/publishing_test.rb test/integration/public_drafts_test.rb` — all pass.
- [ ] **Step 5: Commit** `ref: discard returns to a copy through a shared reconciliation, leaving a gone image empty`.

### Task 3: `Publishing::RestoreVersion`

**Files:**
- Create: `app/services/publishing/restore_version.rb`
- Modify: `app/models/audit/sentence.rb` (verb `version_restored` for page and post: "restored version %{number} of "), `app/models/editing/signals.rb` (`page.version_restored`, `post.version_restored` => `SAVED`), `test/services/service_behaviour_contract_test.rb` (`EXPECTED_SERVICES` + factory), `app/models/audit/` filter lists if the audit screen's action filter enumerates actions
- Test: `test/services/publishing/restore_version_test.rb`, `test/models/audit/sentence_test.rb`

**Interfaces:**
- Consumes: `Publishing::ReturnTo#return_to!` (Task 2), `Changes.between` (Task 1).
- Produces: `Publishing::RestoreVersion.call(record, number:, shown_updated_at: NOT_ASKED, actor: Current.actor) -> ApplicationService::Result`; on success `result.record`, `result.notice` (nil or the missing images/tags sentence) and `result.value`, a Hash `{ number:, images_missing:, tags_missing:, pending_at: }` (`pending_at` the pending copy's `live_at` or nil). Refusals: `switched_off_refusal` first; `OwnerRule` (denied, audited); a number that is no copy of the record → `NOT_FOUND`; `shown_updated_at` given and not equal to the locked row's `updated_at` (to the microsecond) → `STALE` ("This page changed since you opened this. Look at the differences again." with "post" for a post); nothing differs → `NOTHING` ("Nothing to restore: the working version is already version %{number}."); a block type that left the registry → the discard's message. Each refusal writes nothing.
- Produces: event `page.version_restored` / `post.version_restored`, `coalesce: false`, `snapshot: nil`, metadata `{ "number" => n }` plus `"images_missing"`, `"tags_missing"` when not zero.

- [ ] **Step 1: Write the failing tests** (`restore_version_test.rb`), each with exact assertions:
  - `"restoring an older version writes its content into the rows and publishes nothing"`: page v1 title "One", v2 title "Two"; restore 1 → `page.reload.title == "One"`, `Publishing.current(page).number == 2`, `page.unpublished_changes_at` present, `PublicSite.content_version` unchanged.
  - `"a block deleted since comes back as a new block, one added since goes"`.
  - `"sections and their columns come back in the version's order"`.
  - `"a scheduled change stays scheduled"`: a pending copy exists; after restore `Publishing.pending(page)` is the same row and `result.value[:pending_at]` is its `live_at`.
  - `"a draft with copies is restored with no mark"`: unpublish, restore → rows changed, `unpublished_changes_at` nil, `published_at` nil.
  - `"a post's tags come back by id, a deleted tag is counted and not made"`: `result.value[:tags_missing] == 1`, `Tag.count` unchanged.
  - `"it records one event of its own with the number, and takes the settings row then the page's row first"` (copy the shape of the discard test of that name: `ContentSpiel::LockOrder` holds the order; assert the first locking statements).
  - `"a stale dialog is refused and writes nothing"`: `shown_updated_at: 1.minute.ago` → refused, rows unchanged, no event.
  - `"someone with edit and not publish cannot restore a live page, and the refusal is audited"`.
  - `"a step that fails rolls everything back"` (as the discard's, with a block type unregistered).
  - In `sentence_test.rb`: `"restored version 5 of Pricing"`.
- [ ] **Step 2: Run, expect failure** (NameError).
- [ ] **Step 3: Implement** on the shape of `DiscardChanges#call`: one transaction `requires_new`, `lock_owner(@record)`, `@record.reload`, the stale check against the locked row, the version by `Version.of(record).find_by(number:)`, `Changes.between(record, from: version, to: :working).none?` → `NOTHING`, `return_to!(version)`, then the mark as the save services left it (do not clear it), the event. Add it to `EXPECTED_SERVICES` with a factory as the discard's.
- [ ] **Step 4: Run** `test/services/publishing/ test/services/service_behaviour_contract_test.rb test/models/audit/ test/lib/publishing_guards_test.rb test/lib/version_bump_test.rb` — pass.
- [ ] **Step 5: Commit** `feat: restore a published version as unpublished changes`.

### Task 4: `Publishing::PublishNow` (D9)

**Files:**
- Create: `app/services/publishing/publish_now.rb`
- Modify: `app/controllers/admin/pages_controller.rb#publish`, `app/controllers/admin/posts_controller.rb#publish` (call the service with `with_changes: params[:with_changes] == "1"` and `shown_pending`), `test/services/service_behaviour_contract_test.rb`
- Test: `test/services/publishing/publish_now_test.rb`, `test/integration/public_drafts_test.rb`

**Interfaces:**
- Produces: `Publishing::PublishNow.call(record, with_changes: false, shown_pending: NOT_ASKED, now: Time.current) -> Result`. `with_changes: false` is exactly today's `Pages::Save`/`Posts::Save` `published: true` (it calls them). `with_changes: true` in one transaction (`lock_owner` first): `PublishChanges.call(record, at: now, shown_pending:)` when `Changes.of(record)` is not none, then the save service with `published: true`. Needs `publish` (the save services' rule). On a record that is not scheduled it is today's publish. `result.value[:with_changes]` says which was done.
- The controllers' toast keeps `published_now_notice` for `with_changes: false`; for `true` it is the key `published_with_changes` ("Published now, with the changes saved since it was scheduled.").

- [ ] **Step 1: Write the failing tests:**
  - `"publish now without the changes puts the scheduled copy on the site and leaves the later edits unpublished"` (today's behaviour, through the service).
  - `"publish now with the changes puts the rows on the site at once and keeps the scheduled copy as an older version"`: scheduled page v1 "One", rows edited to "Two"; `with_changes: true` → public page shows "Two", `Version.of(page).count == 2`, `unpublished_changes_at` nil.
  - `"with a change scheduled as well, publishing with the changes withdraws the pending copy"`.
  - `"a schedule moved since the dialog was read is refused"` (`shown_pending` mismatch, as `ShownSchedule`).
  - In `public_drafts_test.rb`: `"Publish now with the later changes, pressed in the editor, shows them to a visitor at once"` through `post publish_admin_page_path(page, with_changes: "1")` (use the route helper the existing publish test uses).
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement**; bulk publish (`Posts::BulkPublish` or its equivalent) and MCP's `update_post` are not changed.
- [ ] **Step 4: Run** `test/services/publishing/ test/integration/public_drafts_test.rb test/integration/admin/` — pass.
- [ ] **Step 5: Commit** `feat: publish now can take the changes saved since the schedule`.

### Task 5: `Publishing::History` (the list of versions)

**Files:**
- Create: `app/queries/publishing/history.rb`
- Test: `test/queries/publishing/history_test.rb`

**Interfaces:**
- Produces: `Publishing::History.new(record, page: 1, now: Time.current)` with `#rows -> [History::Row]`, `#pagination` (the app's `Pagination` value, 50 a page), `#working -> History::Working`; `Row = Data.define(:version, :number, :live_at, :publisher, :state)` with `state` one of `:on_site` (the copy in force of a record whose `published_at` has passed), `:scheduled` (the pending copy, or the copy in force of a scheduled record), `:earlier`; `publisher` a `User` or nil (nil = kept when history began). `Working = Data.define(:changes, :same_as)`: `changes` true when the mark is set, `same_as` the number of the copy in force when `Changes.of(record).none?`, else nil. `#find(number) -> Publishing::Version` or raises `ActiveRecord::RecordNotFound`. `#previous(number) -> Publishing::Version or nil`.
- Reads the copies without `snapshot` and `blocks` (`select` the list's columns) and their publishers in one statement (`includes(:created_by)` or a join).

- [ ] **Step 1: Write the failing tests:** `"versions are listed newest first with the copy in force on the site"`, `"a pending copy is scheduled"`, `"a scheduled record's copy in force is scheduled, not on the site"`, `"a first copy with no publisher has none"`, `"the list reads no content column"` (assert the SQL of `rows` names neither `snapshot` nor `blocks`), `"the working version is the same as the copy in force when nothing differs"`, `"51 copies make two pages"`.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the file** — pass.
- [ ] **Step 5: Commit** `feat: a record's published versions as a list`.

**The look of Tasks 6–10 is the Design System card StudioHistory** (v250, id `1794847307-3a01`), saved for implementers at `.superpowers/sdd/2026-11-16-version-history/cards/project/components/StudioHistory/README.md` (values, keys, words) and `preview.html` (the drawing). Where this plan's words and the card's differ, the card wins (it changed "On the site"/"Scheduled for…" to the status chips **Live** and **Scheduled**). Every new or moved component in `app/components/admin/ui/` takes the full component contract (`Admin::Ui::Contract`, `docs/reference/design-system.md`, "Component contract") with a Lookbook preview, a test and a `test/support/design_system_entries.rb` entry; a screen's component lives in its screen folder and joins `test/lib/component_screens_test.rb`'s map.

### Task 6: The shared changes overview, with diffs

**Files:**
- Move: `app/components/admin/editor_screen/changes_overview_component.{rb,html.erb}` → `app/components/admin/ui/changes_overview_component.{rb,html.erb}` (class `Admin::Ui::ChangesOverviewComponent`), its locale keys to `config/locales/admin/ui.en.yml` (or the ui folder's file the source-layout test names), its test and preview with it; every caller updated (`PublishingController#changes`, the publish dialog).
- Test: `test/components/admin/ui/changes_overview_component_test.rb`

**Interfaces:**
- Consumes: `Publishing::Changes` (incl. `between`, `sides`), `Publishing::TextDiff` (Task 1).
- Produces: `Admin::Ui::ChangesOverviewComponent.new(record:, changes:, holds:, locale:, detail: :names, lost: [], moved: [], url_options: {}, schedule_only: false)` (today's signature plus `detail:`). `detail: :diffs` draws, per the card: "Page fields"/"Post fields" with each changed field's label over a diff box (`WordDiffComponent` in `cs-paper`, `rounded-tile`, `px-3 py-2.5`), then "Blocks" with each block row (kind 72px, `BlockIconComponent` 22px, label, summary) and a changed block's diff box indented 84px; "Formatting changed" when `result.formatting_only?`; "The text is too long to compare word by word." when `result.too_long`; a move adds "now %{to}, was %{from}" (ordinals by position in reading order); "No differences." when `changes.none?`. `:names` draws exactly what it draws today.

- [ ] **Step 1: Write the failing tests:** `"the names detail draws the publish dialog's overview as before"` (move the existing tests; they pass unchanged against the new class name), `"the diffs detail draws each changed field's words, struck and added"`, `"a formatting-only change reads Formatting changed"`, `"a moved block says where it went"`, `"no differences says so"`.
- [ ] **Step 2: Run, expect failure** (the class does not exist under `Admin::Ui`).
- [ ] **Step 3: Move and extend; update callers; add the contract declaration, the preview examples (`names`, `diffs`, `none`) and the Design System entry.**
- [ ] **Step 4: Run** `test/components/admin/ test/lib/component_parts_test.rb test/lib/component_screens_test.rb test/components/admin/ui/contract_test.rb test/lib/source_layout_test.rb test/lib/admin_i18n_test.rb test/integration/admin/publishing_test.rb` — pass.
- [ ] **Step 5: Commit** `ref: the changes overview is a shared component and can draw word diffs`.

### Task 7: `Admin::Ui::ChoiceTileComponent`

**Files:**
- Create: `app/components/admin/ui/choice_tile_component.{rb,html.erb}`, its preview and test; the card's look in `content-spiel.tailwind.css` only if utilities cannot draw it.
- Test: `test/components/admin/ui/choice_tile_component_test.rb`

**Interfaces:**
- Produces: `Admin::Ui::ChoiceTileComponent.new(name:, value:, title:, line:, checked: false, id: nil, form: nil, html: {})`: a real `<input type="radio">` inside a `<label>` tile (1px `cs-line-strong`, `rounded-tile`, `p-3`; checked: accent edge on `cs-accent-tint`, drawn from `:has(:checked)`), the title at 600 and the line `text-small cs-dim`. The caller wraps tiles in `role="radiogroup"` with an `aria-label`.

- [ ] **Step 1: Write the failing tests:** `"a tile is a labelled radio with its title and line"`, `"a checked tile is checked"`; and the contract's keyboard test (arrow keys move between radios of a group: native, asserted on the markup the contract test reads).
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement with the contract declaration, preview and Design System entry (ChoiceFields' third control).**
- [ ] **Step 4: Run** the component's test, `test/components/admin/ui/contract_test.rb`, `test/lib/component_parts_test.rb`, `test/lib/admin_design_rules_test.rb` — pass.
- [ ] **Step 5: Commit** `feat: a choice tile, a radio with a title and a line`.

### Task 8: The History screen

**Files:**
- Modify: `config/routes.rb` (`get "pages/:id/history"` → `admin/history#show`, `defaults: { kind: "page" }`, `as: :page_history`; the same for posts, `as: :post_history`)
- Create: `app/controllers/admin/history_controller.rb`, `app/views/admin/history/show.html.erb`, `app/components/admin/history_screen/{version_row_component,comparison_component,versions_component}.{rb,html.erb}`, `config/locales/admin/history_screen.en.yml`
- Modify: the editor header's ⋯ menu (`app/components/admin/editor_screen/header_component.*`: "History" before "Activity", for a viewer who may see it), the record's Activity screen (a link to History), `test/lib/component_screens_test.rb` (`SCREENS`)
- Test: `test/integration/admin/history_test.rb`, `test/components/admin/history_screen/*_test.rb`

**Interfaces:**
- Consumes: `Publishing::History` (Task 5), `Changes.between` (Task 1), `Admin::Ui::ChangesOverviewComponent` `detail: :diffs` (Task 6).
- Produces: `GET admin_page_history_path(page, version: n, with: "previous" | "working" | m, locale: code, page: k)` and `admin_post_history_path(...)` (the prefix follows the admin routes' naming; use what `rails routes` prints). Defaults: `version` = the newest copy; `with` = `"previous"` (the working version when there is no previous); `locale` = the default language. The record is found through `AccessControl.scope(Current.actor, "<kind>s.edit", ...)`, missing → 404 (R4). `@may_restore` = `AccessControl::OwnerRule.refusal(record) { |key| can?(key, record) }.nil?` and the post's type switched on.
- Screen per the card: crumbs, head row (title, `RecordState` chips, "Back to editor"), `.admin-list-rail` with the comparison main column and the versions rail (rows link to `?version=n` keeping `with` and `locale`; chosen row `aria-current="true"`; `PaginationComponent` at its foot); below the threshold a disclosure (`<details>`) above the comparison; the empty state when the record has no copy. The comparison's selects live in one GET form with `admin--ui--auto-submit`.

- [ ] **Step 1: Write the failing tests** (`history_test.rb`): `"an editor sees a page's versions newest first, the copy in force marked Live"`, `"version 5 is compared with the version before it by default, and with the working version on asking"`, `"the language select names the languages that differ"`, `"a record outside the viewer's scope is not found"` (404), `"someone without edit is not found"` (404), `"someone with edit and not publish on a live page sees the history and no Restore"`, `"a page never published shows the empty state"`, `"the editor's menu offers History, and Activity links to it"`. Component tests: the version row's three lines, the working row, the chosen row's `aria-current`, "Kept when history began", the Scheduled chip on a pending copy.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement.** Every string a key under `admin.components.history_screen.*` (the card's list) or the view's own `admin.history.show.*`.
- [ ] **Step 4: Run** the new files, `test/lib/` whole (the guards: i18n, source layout, component screens, dependency direction, admin namespace shadow, design rules), `test/components/admin/editor_screen/header_component_test.rb` — pass. Then `bin/rails zeitwerk:check`.
- [ ] **Step 5: Commit** `feat: a page's and a post's History screen`.

### Task 9: Restoring from the History screen

**Files:**
- Create: `app/components/admin/history_screen/restore_dialog_component.{rb,html.erb}`
- Modify: `config/routes.rb` (`post "restore"` inside `scope "publishing/:kind/:id"`, `to: "publishing#restore"`, `as: :publishing_restore`), `app/controllers/admin/publishing_controller.rb#restore`, `config/locales/admin/history_screen.en.yml`, the comparison component (its Restore button opens the dialog)
- Test: `test/integration/admin/history_test.rb` (restore part), `test/components/admin/history_screen/restore_dialog_component_test.rb`

**Interfaces:**
- Consumes: `Publishing::RestoreVersion` (Task 3), `Admin::Ui::ChangesOverviewComponent` `detail: :names`, `Admin::EditingClaims` (the discard's hold refusal: reuse `refuse_discard_under_hold` or a sibling with the same rule).
- Produces: the dialog is rendered WITH the screen when Restore is offered (Ruling: the History screen has no autosave and no write queue to wait for, so the overview of version against working is read on the GET; the form carries `number` and `shown_updated_at` = the record's `updated_at.iso8601(6)` as read, and the service refuses a stale press). `DialogComponent` width `form`, `steady: true`; the card's sentence, overview (`detail: :names`), warn notice (`role: nil`) for the conditional lines, neutral notice for a schedule that stays; Cancel + "Restore version N". The form is `_top`, `button_to`/`form_with` POST to `publishing_restore`, behind `admin--saving--queue-hold`. Success redirects to the editor with the toast `history_screen.restored` / `restored_draft` plus the service's notice; a refusal redirects back to the History screen with the sentence as an alert toast.
- The conditional counts are computed for the dialog from `Changes.between(record, from: :working, to: version)` (blocks that come back: `added` entries whose id the rows do not have; blocks that go: `removed`, with their open note counts read once through `Notes.readable_threads`), images (version's image ids missing or trashed, one statement), tags (version's tag ids that do not exist).

- [ ] **Step 1: Write the failing tests:** `"restore writes the version into the rows, publishes nothing, and lands in the editor with the toast"`, `"restore is refused while another tab holds a block of the page, and nothing is written"` (claim a hold for another tab as `test/integration/admin/publishing_test.rb`'s discard test does), `"a restore pressed after a colleague's save is refused as stale"`, `"a forged restore by someone without publish on a live page is refused and audited"`, `"restoring a draft's version says Version N restored."`. Component: `"the dialog names a block that comes back without notes, an image that is gone and a schedule that stays"`, `"a version equal to the working version offers Close alone"`.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the files above and `test/integration/admin/publishing_test.rb` — pass.
- [ ] **Step 5: Commit** `feat: restore a version from the History screen`.

### Task 10: The Publish now dialog

**Files:**
- Create: `app/components/admin/editor_screen/publish_now_dialog_component.{rb,html.erb}`
- Modify: `app/components/admin/editor_screen/header_component.{rb,html.erb}` (a scheduled record's "Publish now" opens the dialog; a draft's "Publish" is unchanged), `app/controllers/admin/publishing_controller.rb#changes` (`part=publish_now`), `app/javascript/controllers/admin/editor/publish_dialog_controller.js` (if the part needs a value of its own), `config/locales/admin/editor_screen.en.yml`
- Test: `test/components/admin/editor_screen/publish_now_dialog_component_test.rb`, `test/integration/admin/publishing_test.rb`, `test/components/admin/editor_screen/header_component_test.rb`

**Interfaces:**
- Consumes: `Publishing::PublishNow` through the controllers' `publish` actions (Task 4: `with_changes` and `pending` params), `Admin::Ui::ChoiceTileComponent` (Task 7), `Admin::Ui::ChangesOverviewComponent` (`:names`).
- Produces: ONE dialog per scheduled record (Ruling: the card draws a ConfirmDialog for the no-changes case and a steady Dialog for the choice; both are one steady `DialogComponent` here, because the dialog is drawn once with the page and only its read on opening knows which case it is — cost: the no-changes form is a steady frame with one sentence). Drawn once with the page, outside every replaced part; while it reads: "Checking for changes saved since…"; the answer of `POST publishing_changes(part: "publish_now")` fills its body with either the sentence "It goes live now instead of at %{time}, as scheduled." and confirm "Publish now", or the line "Changes were saved after it was scheduled for %{time}.", the radiogroup "What goes live" of two `ChoiceTileComponent`s (`with_changes` "0" checked, "1"), the `<details>` "What changed since" with the overview, and a confirm whose label follows the chosen radio (a small Stimulus action on the dialog's controller, its words from `data-messages`). The form POSTs to the record's `publish` action with `with_changes` and `pending`, `_top`, behind `admin--saving--queue-hold`.

- [ ] **Step 1: Write the failing tests:** component: `"with no changes since, the dialog says when it would have gone live and offers Publish now"`, `"with changes since, the dialog offers the two choices, the scheduled version chosen"`; header: `"a scheduled record's Publish now opens the dialog; a draft's Publish posts at once"`; integration: `"part=publish_now answers the choice only when the rows changed since the schedule"`.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the files above, `test/components/admin/editor_screen/`, `test/lib/admin_i18n_test.rb` — pass.
- [ ] **Step 5: Commit** `feat: Publish now asks whether to take the changes saved since the schedule`.

### Task 11: Browser tests

**Files:**
- Create: `test/system/admin/version_history_test.rb`
- Modify: `test/system/admin/drafts_test.rb` (Publish now)

- [ ] **Step 1: Write the tests** (read `test/system/README.md` first; begin on `visit_editor`/`visit_screen`; never wait for a time):
  - `"History lists the versions, a version is compared with the one before it and with the working version, and restoring it lands in the editor with its text unpublished"`.
  - `"below the rail's threshold the versions fold above the comparison and choosing one closes them"`.
  - In `drafts_test.rb`: `"Publish now on a scheduled page with changes since: the scheduled version goes live by default, and the later changes when chosen"` (press with a save held on the wire, `delay_next`, as the file's other publishing tests).
- [ ] **Step 2: Run each file alone** (load under 6, no other test run): `PGGSSENCMODE=disable bin/rails test test/system/admin/version_history_test.rb`, then the drafts file — pass.
- [ ] **Step 3: Commit** `test: version history and Publish now in the browser`.

### Task 12: The record

**Files:**
- Modify: `docs/reference/publishing.md` (new sections "History", "Restore a version", "Publish now"; "What is not built" and the "Who writes a copy"/rules lines that change; `Publishing::ReturnTo`), `docs/reference/design-system.md` (the two shared components), `docs/reference/editors-and-translation-pair.md` (the ⋯ menu's History, the Publish now dialog), `CLAUDE.md` (the publishing line of the reference index names the History screen's files; the cases/rules list gains nothing unguarded unless a rule has no guard), `docs/roadmap.md` (row 202: history, compare and restore shipped; Publish now decided and shipped; "audit snapshots are the version basis" superseded by copies; the two write-queue gaps of "Closed by versioning" moved to "The write queue and Turbo"; "Drafts of live content"'s Publish now bullet and the image-discard bullet updated), `CHANGELOG.md` (`## Unreleased`: Added, Changed)
- [ ] **Step 1: Write the documentation** in the files' own style (rules a test holds name their test).
- [ ] **Step 2: Run** `test/lib/` whole (the docs and environment guards) and `bin/changelog-guard` if it runs locally — pass.
- [ ] **Step 3: Commit** `docs: version history`.

