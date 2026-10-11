# Live Refresh and Edit Reservations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** What someone else saves appears in an open page or post editor without a reload, and a block, a page's settings or a post that someone is changing is read-only for everyone else, who can take it over without losing anybody's text.

**Architecture:** A subscriber to the audit log's after-commit notification (`Editing::Signals`) turns content events into id-only signals on the record's stream; an open editor fetches the named part with a plain GET through the read scope and merges it around every form that holds unsaved text (`editing/merge`). Reservations are rows in `edit_reservations`, claimed by one atomic statement on a unique index (`Editing::Reservation`); the three autosave actions claim before they save and refuse a tab that does not hold the subject, and a held card is rendered read-only for its viewer, with no autosave controller. Taking over is the one audited write (`Editing::TakeOver`): a request the holder's tab answers after draining its write queue, or that the requester's tab passes over after 5 seconds.

**Tech Stack:** Rails 8.1, Postgres 17, Action Cable (Solid Cable in production, the `test` adapter in tests), Stimulus through importmap-rails, Turbo (pinned), ViewComponent, Tailwind v4, Minitest with fixtures, Capybara on Cuprite.

**Spec:** `docs/superpowers/specs/2026-10-11-live-editing-design.md` (binding). The look: `docs/superpowers/specs/2026-10-11-live-editing-handoff.md` (items 1 to 22, binding for every size, token, place and wording; where it and the spec differ on look, it wins). Read both before any task.

## Where the code disagrees with the design

Each was checked in the code; the plan builds the proposed way.

1. **§3.3, "the forwarding … is removed, if nothing else reads it".** Something else reads it: `Admin::TreeController#page_base_streams` and `admin--pages--tree` send and answer the same header (`X-Page-Base-Updated-At`) and the same field (`page-base-updated-at`), and `Pages::Move` changes the page's own columns (`parent_id`, `position`), so it does move the new `settings_changed_at`. **Plan:** the forwarding is removed from the block side only (`Admin::ContentBlocksController#page_base_streams`, the autosave script's `pageBaseId` value, `admin--editor--blocks`'s header); the tree's stays and compares `settings_changed_at` (Task 1).
2. **§3.1, `origin`.** `Live::Signals.origin` reads `Current.notes_tab`, which only the notes controllers set (`Admin::NoteContainer#note_tab`, `Admin::NoteInboxController`). Setting it for content requests would change notes: a block's delete sends `Notes::Remove`'s signal, and with an origin on it the deleting tab would skip the refresh of its own open drawer (`test/models/notes/signals_test.rb`, "deleting a block signals its page, whose drawer is still open, when the delete commits"). **Plan:** the same header, `X-Notes-Tab`, in the same shape, `Live::Signals::TAB`, is read by `Admin::BaseController` into a new `Current.editing_tab`, which only `Editing` reads (Task 2). `Current.notes_tab` and `Live::Signals.origin` are not touched.
3. **§5, "the card and the tile stop naming notes" and "the Add note menu item stays a named exception".** Both cannot hold in `test/lib/notes_boundary_test.rb`: `SLOT_HOSTS` refuses the word in code and comments, and a file may not be in `SLOT_HOSTS` and `NAMED_EXCEPTIONS` at once ("assert_empty NAMED_EXCEPTIONS.keys.flatten & SLOT_HOSTS"). **Plan:** the block card and the tile stay in `NAMED_EXCEPTIONS`, with the reason narrowed to the menu item, and a new test holds that neither renders a marker itself (Task 12).
4. **§3.2, "one block's card".** A section's card (`Admin::EditorScreen::SectionCardComponent`) contains the forms of every block in it, so it cannot be fetched and replaced as one card. **Plan:** a `saved` signal for a section is answered by fetching the list, which is merged unit by unit; a block in a section is fetched as its tile and its panel (Tasks 3 to 5).
5. **§4.3, "fields that are `readonly`".** The editors' fields are drawn by eight components (`Admin::Ui::FieldComponent`, `ChipInputComponent`, `Admin::Columns::PlainColumnComponent`, `SlugColumnComponent`, `RichTextColumnComponent`, `MediaColumnComponent`, the section's selects and its layout menu), none of which takes a read-only option; view-only today is `<fieldset disabled>`. **Plan:** the held form's fields are drawn as they are and rewritten once on the server by `Admin::EditorScreen::HeldFields` (text controls `readonly`, the rest `disabled`), with a component test that compares every control (Task 8). The browser's counterpart for the one form that turns read-only in place is `editing/freeze` (Task 9), which applies the same rule.
6. **Handoff 17, "the existing 'Copied' toast".** There is none: "Copied" is a status text beside the button (`admin--ui--clipboard#flash`, `admin--tokens--reveal`). **Plan:** "Copy my text" says "Copied" in a `role="status"` element inside the notice. Listed under "Open points for the owner" as a design question.
7. **§4.2, "release … with a beacon when the page is left" against §7, "every … release … goes through `saving/queue.js`".** A page that is unloading cannot wait for a queue. **Plan:** every claim, release, request and hand-over goes through the queue, except the one release sent at `pagehide`, a `fetch` with `keepalive: true` (it carries the tab header and the CSRF token, which `sendBeacon` cannot) (Task 9).

## File map

**Created**

| File | Its one responsibility |
|---|---|
| `db/migrate/20261011100000_add_settings_changed_at_to_pages.rb` | The column, filled from `updated_at` |
| `db/migrate/20261011110000_create_edit_reservations.rb` | The reservations table |
| `app/models/editing.rb` | The namespace: `HOLD`, `PASS_OVER`, `NOTICE`, `SWEEP_AFTER`, `subject_of`, `key` |
| `app/models/editing/signals.rb` | The mapping from audit events to signals, the stream's name, the holder signal |
| `app/models/editing/reservation.rb` | The reservation's statements, each one statement |
| `app/models/editing/rights.rb` | Which right a person lacks to change a page or post |
| `app/queries/editing/holds.rb` | The live reservations of one page or post, read once |
| `app/queries/editing/last_change.rb` | Who last changed a block, for the "Updated" mark |
| `app/services/editing/take_over.rb` | The one audited write: request, hand-over, pass-over |
| `app/jobs/editing/sweep.rb` | Deletes expired rows |
| `app/channels/editing/channel.rb` | The record's stream, through the read scope |
| `app/controllers/admin/editing_controller.rb` | The three GETs; claim, release, take over, hand over |
| `app/controllers/concerns/admin/editing_claims.rb` | Claim-or-refuse for the autosave actions and the claim action |
| `config/initializers/editing.rb` | Subscribes `Editing::Signals` to `Audit::NOTIFICATION` |
| `app/components/admin/editor_screen/live_region_component.rb` (+ `.html.erb`) | The element both scripts stand on, with their values |
| `app/components/admin/editor_screen/hold_strip_component.rb` (+ `.html.erb`) | The strip and notices (a), (b), (c) |
| `app/components/admin/editor_screen/held_fields.rb` | Rewrites a form's fields to read-only |
| `app/components/admin/editor_screen/updated_mark_component.rb` (+ `.html.erb`) | "Updated by Dana Weiss · just now" |
| `app/components/admin/editor_screen/holder_avatar_component.rb` (+ `.html.erb`) | The tile's 20px avatar, for the slot |
| `app/javascript/editing/merge.js` | The merge rule |
| `app/javascript/editing/freeze.js` | Makes a form's fields read-only in place |
| `app/javascript/editing/requests.js` | The plain GET and the queued POST, with the tab header |
| `app/javascript/controllers/admin/editing/live_controller.js` | Listens, fetches, merges, shows the "Updated" mark |
| `app/javascript/controllers/admin/editing/hold_controller.js` | Claims, releases, hands over, freezes a refused form |
| `docs/reference/live-editing.md` | The reference file |
| Tests | `test/models/editing/{signals,reservation,rights}_test.rb`, `test/models/editing_test.rb`, `test/queries/editing/{holds,last_change}_test.rb`, `test/services/editing/take_over_test.rb`, `test/jobs/editing/sweep_test.rb`, `test/channels/editing/channel_test.rb`, `test/integration/admin/editing_test.rb`, `test/integration/admin/editing_claims_test.rb`, `test/components/admin/editor_screen/{hold_strip_component,held_fields,updated_mark_component,holder_avatar_component}_test.rb`, `test/system/admin/editing_merge_test.rb`, `editing_live_test.rb`, `editing_holds_test.rb`, `editing_take_over_test.rb` |

**Modified**

| File | What changes |
|---|---|
| `app/models/page.rb` | `settings_changed_at` set before save |
| `app/models/current.rb` | `editing_tab` |
| `app/controllers/admin/base_controller.rb` | Reads the tab header |
| `app/controllers/concerns/admin/autosave_responses.rb` | The base is `autosave_base(record)`; the held refusal's streams |
| `app/controllers/admin/pages_controller.rb`, `posts_controller.rb`, `content_blocks_controller.rb` | Claim before save; the block side's page-base forwarding removed |
| `app/controllers/admin/tree_controller.rb` | Compares `settings_changed_at` |
| `app/services/content_blocks/destroy.rb` | `block.deleted` names its page in metadata |
| `app/models/audit/sentence.rb`, `app/queries/dashboard/feed.rb` | The take-over's sentence; a take-over is not a change |
| `app/components/admin/editor_screen/block_card_component.*`, `block_tile_component.*`, `section_card_component.*`, `section_lanes_component.*`, `section_group_component.*`, `page_settings_form_component.*`, `post_form_component.*`, `header_component.*` | Ids and unit marks; the strip's place; read-only when held; the slot |
| `app/components/admin/columns/rich_text_column_component.html.erb`, `app/javascript/controllers/admin/rich_text/editor_controller.js` | A `readOnly` value |
| `app/components/admin/ui/save_status_component.rb` | The state `:held` |
| `app/components/admin/slots.rb`, `config/initializers/admin_slots.rb`, `app/components/admin/notes_screen/marker_component.rb` | The slot `editor.block.markers`; notes' marker takes a slot's arguments |
| `app/views/admin/pages/show.html.erb`, `app/views/admin/posts/show.html.erb` | The live region; holds read once |
| `app/javascript/controllers/admin/saving/autosave_controller.js` | Announces the first change; the tab header; `pause()`; no page base |
| `app/javascript/controllers/admin/editor/blocks_controller.js`, `section_controller.js` | The tab header on block writes; `moving`, `toggled` and `closed` events; no page base |
| `app/javascript/controllers/admin/pages/tree_controller.js` | The tab header |
| `app/javascript/saving/queue_core.js`, `queue.js` | `quiet()` and `writeCount` exported |
| `config/importmap.rb`, `config/routes.rb`, `config/recurring.yml`, `db/schema.rb` | The folder's pin, the routes, the sweep, the schema |
| `config/locales/admin/editor_screen.en.yml`, `ui.en.yml` | The strings |
| `app/helpers/admin/messages_helper.rb` | Nothing: the scripts hold no wording (every sentence is rendered by the server) |
| `app/assets/tailwind/application.css` | `.admin-held`, the mark's fade |
| Guards | `test/support/service_calls.rb`, `test/services/service_behaviour_contract_test.rb`, `test/models/audit/sentence_test.rb`, `test/lib/notes_boundary_test.rb`, `test/integration/public_javascript_test.rb`, `test/integration/trash_visibility_test.rb`, `test/lib/admin_i18n_test.rb` (only if its `CONVERTED` list names a touched file) |
| Documents | `CLAUDE.md`, `docs/reference/save-rule-and-write-queue.md`, `content-blocks-and-types.md`, `presence.md`, `slots.md`, `editors-and-translation-pair.md`, the spec's "As built", `docs/roadmap.md` (alone) |

## Global Constraints

- Every test command is prefixed `PGGSSENCMODE=disable`. System tests need `bin/rails tailwindcss:build` first and run with `PARALLEL_WORKERS=6`; a named set of system files is run with `bin/rails test <files>`. Never two test commands at once. The output of a long run is redirected to a file, never piped through `grep`. Check `sysctl -n vm.loadavg` before a system run: a run on a loaded machine is not a result.
- **The write queue.** Every claim, release, take-over request, hand-over and save is sent through `app/javascript/saving/queue.js` (`enqueue`), never from a hand-built request beside it; the one exception is the release at `pagehide`. The live GETs are plain `fetch`es the queue neither holds nor counts (`quiet()` waits beside it, it takes no turn).
- **An open form holding unsaved changes is never fetched over and never removed**, and neither is anything else of its unit; a section's panels stay in the document. "Unsaved" is the write queue's own question: not `clean()`, `outstanding()`, or not `unchanged()`.
- **No Turbo page refresh, no morphing** (`test/lib/notes_guards_test.rb`), **and no broadcast but `Live::Signals`'**: `Live::Signals.later` is called only from a `module …::Signals` (`test/models/notes/signals_test.rb`).
- **A signal carries a kind, ids, a reason and an origin**, never text, a title or a name. Kinds and reasons are exactly: `content` with `saved`, `structure`, `gone`; `holder` with `claimed`, `released`, `requested`, `taken`. Every part a signal leads to is fetched through the read scope.
- **Not found, not forbidden.** A record outside the viewer's read scope, a trashed one and an unknown kind are a 404 on every editing route and a rejected subscription. A claim, a release, a take-over and a hand-over are refused exactly where the save would be: 404 outside the read scope, 403 without `edit`, or without `publish` for a published record.
- **A reservation never writes the record it is on and moves no base:** no `touch`, no `updated_at`, no `PublicSite.bump_version!`. Each of its statements is one atomic statement and takes no row lock; every write that goes around callbacks says `# version: none (a reservation is not content)` on its line (`test/lib/version_bump_test.rb`), and the one SQL string says `# sql: <reason>` (`test/lib/sql_strings_test.rb`).
- **A request without a tab id neither claims nor is refused.** The tab id is the header `X-Notes-Tab`, in the shape `Live::Signals::TAB` (`/\A[a-z0-9-]{8,40}\z/`), read into `Current.editing_tab`. A person's own other tab is someone else.
- **The lock order is untouched:** no editing code takes a row lock on a page, a post or a block, and none runs inside a content service's transaction. The only change to a content service is one metadata key in `ContentBlocks::Destroy`.
- **The service contract:** `Editing::TakeOver` is an `ApplicationService` that calls `authorize!(` and `record_event(`, has its entry in `EXPECTED_SERVICES` and its factory in `test/support/service_calls.rb`. `Editing::Reservation`'s claim, renew and release are not services and are not audited, as presence's marks are not; `CLAUDE.md` says so (Task 13).
- **No name, text or title in the audit event of a take-over:** ids in metadata, `snapshot: nil`.
- **Names:** the namespace is `Editing`; `Admin::Editing` is never defined (`test/lib/admin_namespace_shadow_test.rb` refuses it once `app/models/editing/` exists); the controller is the class `Admin::EditingController`; components are `Admin::EditorScreen::…`. Stimulus identifiers follow their files: `admin--editing--live`, `admin--editing--hold`.
- **Dependency direction:** nothing under `app/models`, `app/queries`, `app/services` names a component, a controller or a route (`test/lib/dependency_direction_test.rb`); the content side (`CONTENT_SOURCES` of `test/lib/notes_boundary_test.rb`) does not name `Editing::`.
- **Strings are keys** in `config/locales/admin/editor_screen.en.yml` (English only: the three locales are for public content). The scripts hold no wording: every sentence a person reads is rendered by the server. **Tokens, not colour literals** (`test/lib/admin_design_rules_test.rb`): `bg-sunken`, `border-line`, `border-line-strong`, `text-ink`, `text-meta`, `bg-paper`, `bg-warn-tint`, `text-warn-ink`, `border-warn`, `ease-cs`. **No inline event handlers:** behaviour through `data-action`.
- **The numbers:** `Editing::HOLD` is 2 minutes, `Editing::PASS_OVER` 5 seconds, `Editing::NOTICE` 6 seconds. They reach the scripts as values rendered from these constants (`data-admin--editing--hold-pass-over-value`, `-notice-value`, a strip's `data-editing-expires-in`), so a test shortens them on the element and nothing is tied by a comment.
- **System tests** wait on a condition, never on time: `assert_eventually`, `await_js`, `await_notes_live`, `assert_writes_settled`, `await_frames`; a `sleep` needs `# sleep: <reason>` on its line and is used only to show that nothing happens. Two people are two Capybara sessions (`using_session`). A reservation's clock is moved with `update_all(changed_at: …)` or `update_columns` carrying `# version: none (a system test moves a reservation's clock)`. A test that stubs `window.fetch` intercepts only its own request and passes every other one through. A test that resizes the window puts the size back in an `ensure`.
- A design question the handoff does not answer is not decided by the implementer: finish the rest and report it under "Design questions".
- Commits are conventional (`feat:`, `fix:`, `ref:`, `docs:`, `test:` and a sentence) and each ends with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
  ```
- Push nothing. Delete nothing outside the worktree. Dispatch no subagents.

## Review Focus

The five failure modes the spec implies and none of its listed tests (§8) covers, most likely first. Each is pinned by a test in the task that owns the code.

1. **A person reloads their own editor and finds their own block locked.** A full load makes a new tab id and the page is rendered before the old tab's release arrives, so the block they were typing in a second ago reads "You're editing this in another tab". They expect to go on typing. The release at `pagehide` and the fetch on the first confirmed subscription must clear it without a click. Tests: Task 9, "reloading the editor frees what this tab held, and the block is editable again without a click"; Task 5, "a confirmed subscription fetches the list and the record's form once".
2. **A list refresh arrives while a block is being dragged, or before this tab's own move has been answered.** The fetched list is older than what the person is doing; drawn, it snaps the block back and the move then lands on a list that no longer matches. They expect their drag to win. Tests: Task 5, "a structure signal that arrives during a drag is drawn after the drop, with the dropped block where it was dropped" and "an answer fetched before this tab's own write was queued is not drawn".
3. **A hold runs out exactly while its holder's save is on the wire, and a colleague claims in that moment.** The holder expects either a saved text or a clear refusal with the text kept, never a silent overwrite and never both people editable. Tests: Task 6, "a holder renewing and a stranger claiming at the boundary: exactly one holds afterwards" (two connections); Task 9, "a save refused because the hold lapsed and was taken keeps the text, read-only, with the notice".
4. **The same block has two forms: a section's hidden panel, and the pair on a translation tab.** A hold on a block in a section must make its hidden panel read-only and mark its tile, and a refresh must not replace a hidden panel that holds unsaved text or reopen a closed one. Tests: Task 4, "a hidden panel that holds unsaved text is the same element after a list merge, and stays hidden"; Task 7, "held by someone else: the strip is in its slot, the unit says held, the form has no autosave controller…" for a panel, and Task 12, "a held block's tile carries the avatar before the notes marker, and no Take over"; Task 5, "on a translation tab the card of the block is refreshed in that language".
5. **Someone loses the right to edit while they hold a block, or the block is moved into another container while it is held.** The hold must not outlive the right (the next save is the service's 403, a take-over needs no answer from them), and a moved block must keep its holder and its strip in its new shape. Tests: Task 10, "a holder who has lost the right cannot hand over, and the requester gets the block after the pass-over time"; Task 8, "a block moved into a section while held is still held, by the same tab".

---

### Task 1: The page settings form has a base of its own

**Files:**
- Create: `db/migrate/20261011100000_add_settings_changed_at_to_pages.rb`
- Modify: `app/models/page.rb`, `app/controllers/concerns/admin/autosave_responses.rb`, `app/components/admin/editor_screen/page_settings_form_component.rb`, `app/components/admin/editor_screen/block_card_component.rb`, `app/controllers/admin/content_blocks_controller.rb`, `app/controllers/admin/tree_controller.rb`, `app/javascript/controllers/admin/saving/autosave_controller.js`, `app/javascript/controllers/admin/editor/blocks_controller.js`, `app/javascript/saving/queue.js` (its header comment only), `db/schema.rb`
- Test: `test/models/page_test.rb`, `test/integration/admin/page_editor_test.rb`, `test/integration/admin/content_blocks_test.rb`, `test/integration/admin/tree_test.rb`, `test/system/admin/tree_test.rb`, `test/system/admin/notes_flow_test.rb`, `test/system/admin/presence_test.rb` (the last three only where they read `X-Page-Base-Updated-At` or `page-base-updated-at`)

**Interfaces:**
- Produces: `pages.settings_changed_at` (`datetime`, precision 6, not null). `Page#settings_changed_at` moves on every save that changes a column of the page other than `updated_at`, and never on `touch`, `update_columns` or `update_all`.
- Produces: `Admin::AutosaveResponses#autosave_base(record)` → `Time`: `record.settings_changed_at` for a `Page`, `record.updated_at` otherwise. The stale check, the base the answer writes and the settings form's rendered base all use it. Later tasks render a base only through it.
- Removes: `Admin::ContentBlocksController#page_base_streams`, `#page_base_was_current?`, `@page_updated_at_before_write`; the autosave script's `pageBaseId` value and its `X-Page-Base-Updated-At` header; `admin--editor--blocks`'s `pageBaseId`, its header and its `baseIds`. The tree's forwarding stays.

- [ ] **Step 1: Write the failing model tests.** Add to `test/models/page_test.rb`:

```ruby
test "settings_changed_at moves when a column of the page changes, and not when the page is only touched" do
  page = create_page(title: "Pricing")
  before = page.reload.settings_changed_at
  assert_not_nil before

  travel 1.minute do
    page.touch
    assert_equal before, page.reload.settings_changed_at, "a touch (a block's save) moved the settings base"
    assert_operator page.updated_at, :>, before

    page.update_columns(translation_sources: page.translation_sources) # version: none (a test's own bookkeeping write)
    assert_equal before, page.reload.settings_changed_at

    assert Pages::Save.call(page, translations: { "en" => { subtitle: "New" } }).ok?
    assert_operator page.reload.settings_changed_at, :>, before
  end
end

test "a block's save leaves its page's settings base where it was" do
  page = create_page(title: "Pricing")
  before = page.reload.settings_changed_at

  travel 1.minute do
    assert ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }).ok?
  end

  assert_equal before, page.reload.settings_changed_at
  assert_operator page.updated_at, :>, before
end
```

- [ ] **Step 2: Run them.** `PGGSSENCMODE=disable bin/rails test test/models/page_test.rb -n "/settings base|settings_changed_at/"`. Expected: 2 errors, `NoMethodError: undefined method 'settings_changed_at'`.

- [ ] **Step 3: The migration and the model.**

```ruby
# db/migrate/20261011100000_add_settings_changed_at_to_pages.rb
# The page settings form's own autosave base (live-editing spec §3.3). Every
# block write touches its page, so `updated_at` moved under someone who was in
# the settings although nobody else had changed them. Filled from `updated_at`
# so that a form open across the deploy is refused once at most.
class AddSettingsChangedAtToPages < ActiveRecord::Migration[8.1]
  def up
    add_column :pages, :settings_changed_at, :datetime
    execute "UPDATE pages SET settings_changed_at = updated_at"
    change_column_null :pages, :settings_changed_at, false
  end

  def down
    remove_column :pages, :settings_changed_at
  end
end
```

In `app/models/page.rb`, beside the existing `before_save` the file's header describes (read the comments there first; this one reads only the pending changes and writes one column of the same row):

```ruby
# The settings form's autosave base (live-editing spec §3.3). Moved whenever a
# column of the page itself is about to change, and by nothing else: a `touch`
# (every block write touches its page) runs no save callbacks, and
# `update_columns` and `update_all` go around them on purpose
# (`Translations::Confirm`'s bookkeeping must not make an open form stale).
# So someone in the settings is refused only when the SETTINGS changed.
SETTINGS_BASE_IGNORES = %w[updated_at settings_changed_at].freeze
before_save { self.settings_changed_at = Time.current if new_record? || (changed - SETTINGS_BASE_IGNORES).any? }
```

Run `bin/rails db:migrate` and keep `db/schema.rb`. Run Step 2's command again. Expected: 2 runs, 0 failures.

- [ ] **Step 4: Write the failing request tests.** In `test/integration/admin/page_editor_test.rb` (`sign_in_as` is `test/test_helpers/session_test_helper.rb`'s; the base is sent as `base_updated_at`):

```ruby
test "the settings form is saved on its base although a block of the page was saved since" do
  sign_in_as users(:one)
  page = create_page(title: "Pricing")
  base = page.reload.settings_changed_at.iso8601(6)
  travel(1.minute) { as(users(:two), channel: :admin) { assert ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }).ok? } }

  patch admin_page_path(page), params: { base_updated_at: base, page: { subtitle: "Saved" } }, as: :turbo_stream

  assert_response :ok
  assert_equal "Saved", page.reload.subtitle
  assert_includes response.body, %(value="#{page.settings_changed_at.iso8601(6)}")
end

test "the settings form is refused when the settings themselves were saved since" do
  sign_in_as users(:one)
  page = create_page(title: "Pricing")
  base = page.reload.settings_changed_at.iso8601(6)
  travel(1.minute) { as(users(:two), channel: :admin) { assert Pages::Save.call(page, translations: { "en" => { subtitle: "Theirs" } }).ok? } }

  patch admin_page_path(page), params: { base_updated_at: base, page: { subtitle: "Mine" } }, as: :turbo_stream

  assert_response :conflict
  assert_equal "Theirs", page.reload.subtitle
end
```

In `test/integration/admin/content_blocks_test.rb`: delete every test whose subject is `page_base_streams` or the header `X-Page-Base-Updated-At` (find them with `git grep -n "X-Page-Base-Updated-At\|page-base-updated-at" -- test/integration/admin/content_blocks_test.rb`) and add one in their place:

```ruby
test "a block's answer carries no base of the page settings form" do
  sign_in_as users(:one)
  page = create_page(title: "Pricing", published: false)
  block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }).record
  patch admin_page_content_block_path(page, block), params: { base_updated_at: block.updated_at.iso8601(6), block: { caption: "x" } },
    headers: { "X-Page-Base-Updated-At" => page.settings_changed_at.iso8601(6) }, as: :turbo_stream

  assert_response :ok
  assert_not_includes response.body, "page-base-updated-at"
end
```

Run `PGGSSENCMODE=disable bin/rails test test/integration/admin/page_editor_test.rb test/integration/admin/content_blocks_test.rb`. Expected: the three new tests fail (the first with 409, the third because the base is in the body).

- [ ] **Step 5: The concern, the component, the controllers.** In `app/controllers/concerns/admin/autosave_responses.rb`:

```ruby
# The time a record's autosave form holds as its base: what a save is compared
# against and what an answer hands back. A page's SETTINGS form holds
# `settings_changed_at` (live-editing spec §3.3): `updated_at` also moves with
# every block write, which would refuse someone in the settings for a
# colleague's block. Everything else holds `updated_at`.
def autosave_base(record) = record.is_a?(Page) ? record.settings_changed_at : record.updated_at
```

and use it in three places of the same file: `autosave_stream` writes `value: autosave_base(record).iso8601(6)`; `stale_base?` compares `Time.iso8601(base_updated_at) < autosave_base(record)`; `legacy_stale_after_save?` reads `previous = record.is_a?(Page) ? record.settings_changed_at_before_last_save : record.updated_at_before_last_save`. `Admin::EditorScreen::PageSettingsFormComponent#base_updated_at_value` becomes `page.settings_changed_at.iso8601(6)`.

In `Admin::ContentBlocksController`: delete `page_base_streams`, `page_base_was_current?`, the `@page_updated_at_before_write` line of `set_page` and every `*page_base_streams` and `streams.concat(page_base_streams)` in `create`, `update`, `destroy`, `reorder` and `duplicate`; rewrite the comments that explained them (the comment above `update`'s stale check loses its second sentence). In `Admin::TreeController#update`: `updated_at_before_move = page.settings_changed_at`, and `page_base_streams` answers `Page.where(id: page.id).pick(:settings_changed_at).iso8601(6)`; its comment says why this one stays (`Pages::Move` saves the page's own columns).

In `Admin::EditorScreen::BlockCardComponent.autosave_form_data`: remove the `"admin--saving--autosave-page-base-id-value"` line. In `autosave_controller.js`: remove the `pageBaseId` value, the page base in `requestHeaders()`, and reduce the `syncBases` call to the form's own base (`syncBases(text, [ ownBase?.id ].filter(Boolean))`); rewrite the two comments. In `blocks_controller.js`: remove `static pageBaseId`, the `baseIds` and the `before` callback of `addPageBase` (the listener keeps calling `holdTurboRequest(event)`; rename it `holdWrite` and `addPageBaseToUndo` `holdUndo`), the header in the reorder `fetch` and the `syncBases(answer.text, …)` line after it. `admin--pages--tree` is unchanged.

- [ ] **Step 6: Run** `PGGSSENCMODE=disable bin/rails test test/models test/integration/admin test/lib test/components`. Expected: 0 failures. Then `bin/rails tailwindcss:build` and `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/tree_test.rb test/system/admin/sections_test.rb test/system/admin/notes_flow_test.rb test/system/admin/presence_test.rb test/system/admin/page_editor_test.rb` (leave out a file that does not exist; `ls test/system/admin` first). Expected: 0 failures; an assertion that read the page base after a block save is rewritten to assert that the settings form saves (it is the same promise, kept another way).

- [ ] **Step 7: Commit.**

```bash
git add -A db app test
git commit -m "ref: the page settings form has a base of its own, so a block's save no longer makes it stale"
```

(with the two trailer lines of the Global Constraints, here and in every commit below).

---

### Task 2: Signals from the audit log, and the record's channel

**Files:**
- Create: `app/models/editing.rb`, `app/models/editing/signals.rb`, `app/channels/editing/channel.rb`, `config/initializers/editing.rb`, `test/models/editing/signals_test.rb`, `test/channels/editing/channel_test.rb`
- Modify: `app/models/current.rb`, `app/controllers/admin/base_controller.rb`, `app/services/content_blocks/destroy.rb`, `test/services/content_blocks/destroy_test.rb`

**Interfaces:**
- Consumes: `Audit::NOTIFICATION` (payload `{ event: }`), `Audit::Sentence::ACTIONS`, `Live::Signals.later(stream, payload)`, `Live::Signals::TAB`, `Live::RecordChannel`, `RecordKinds`.
- Produces:
  - `Current.editing_tab` → the tab id of the request, or nil.
  - `Editing.subject_of(record, block_id)` → the `ContentBlock` of that page with that id, the record itself for a nil or blank `block_id`, nil for a block that is not this record's (a post has none).
  - `Editing.key(subject)` → `"block-12"` for a block, `"record"` for a page or a post: the subject's name in the page (`data-editing-subject`).
  - `Editing::Signals.record_stream(record)` → `"editing:record:Page-3"`.
  - `Editing::Signals.heard(event)` → sends at most one `content` signal; never raises.
  - `Editing::Signals.holder(record, subject, reason)` → sends `{ kind: "holder", content_block_id:, reason:, origin: }` (used from Task 7).
  - `Editing::Signals::MAP` (`action => reason`) and `Editing::Signals::SILENT` (`action => why`), together every name in `Audit::Sentence::ACTIONS`.
  - `Editing::Channel`, subscribed with `{ channel: "Editing::Channel", type: "page" | "post", id: "3" }`.
  - `block.deleted` events carry `metadata["page_id"]`.

- [ ] **Step 1: Check each mapped event names its page** (done while this plan was written; repeat it, because a service may have changed): `git grep -n "record_event(" -- app/services/pages app/services/posts app/services/content_blocks app/services/trash app/services/translations`. The findings the code below relies on: `page.*` and `post.*` events have the page or post as their subject; `block.created`, `block.updated` and `block.translation_confirmed` have the block as their subject and the block exists after the commit, so its owner is read from its row; `block.reordered` has the page as its subject; `block.deleted` has the block as its subject **and the row is gone when the notification runs**, so its page cannot be read: `ContentBlocks::Destroy` gains `"page_id"` in that event's metadata. That is the only change to a content service.

- [ ] **Step 2: Write the failing tests.** `test/models/editing/signals_test.rb`:

```ruby
require "test_helper"

class Editing::SignalsTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @page = create_page(title: "Pricing", published: false)
    # An image block: its caption is a plain translated column a save can change.
    @block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "image" }).record
    @stream = Editing::Signals.record_stream(@page)
  end

  def sent(stream = @stream) = broadcasts(stream).map { |payload| ActiveSupport::JSON.decode(payload) }

  def only_new(stream = @stream)
    before = sent(stream).size
    yield
    sent(stream).drop(before)
  end

  test "every action the app records is mapped or silent, with a reason, and none is both" do
    known = Editing::Signals::MAP.keys + Editing::Signals::SILENT.keys
    assert_empty Audit::Sentence::ACTIONS - known, "content event names Editing::Signals does not know: map each to a reason, or list it in SILENT with why"
    assert_empty known - Audit::Sentence::ACTIONS, "Editing::Signals names actions nothing records"
    assert_empty Editing::Signals::MAP.keys & Editing::Signals::SILENT.keys
    Editing::Signals::SILENT.each { |action, why| assert_operator why.length, :>, 20, "#{action} needs its reason" }
    assert_empty Editing::Signals::MAP.values.uniq - %w[saved structure gone]
  end

  test "an action no list knows is reported and sends nothing" do
    event = Audit::Event.new(action: "block.exploded", subject_type: "ContentBlock", subject_id: @block.id)
    reported = []
    subscriber = Rails.error.subscribe(Class.new { define_method(:report) { |error, **| reported << error } }.new)

    assert_empty only_new { Editing::Signals.heard(event) }
    assert_equal 1, reported.size
  ensure
    Rails.error.unsubscribe(subscriber)
  end

  test "a block's save signals its page: content, saved, the block's id and nothing else" do
    signals = only_new { assert ContentBlocks::Save.call(@block, translations: { "en" => { caption: "x" } }).ok? }

    assert_equal [ { "kind" => "content", "content_block_id" => @block.id, "reason" => "saved" } ], signals
  end

  test "a save coalesced into an open event signals again" do
    assert ContentBlocks::Save.call(@block, translations: { "en" => { caption: "one" } }).ok?
    signals = only_new { assert ContentBlocks::Save.call(@block, translations: { "en" => { caption: "two" } }).ok? }

    assert_equal 1, signals.size
  end

  test "an added, duplicated, reordered and deleted block each signal structure, with no block id" do
    added = only_new { ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }) }
    copied = only_new { assert ContentBlocks::Duplicate.call(@block).ok? }
    ids = @page.content_blocks.reload.top_level.reorder(:position, :id).ids
    moved = only_new { assert ContentBlocks::Reorder.call(@page, ids.reverse).ok? }
    deleted = only_new { assert ContentBlocks::Destroy.call(@block).ok? }

    [ added, copied, moved, deleted ].each do |signals|
      assert_equal [ { "kind" => "content", "content_block_id" => nil, "reason" => "structure" } ], signals
    end
  end

  test "a section's fold signals structure" do
    section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "three" } }).record
    ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text", section_id: section.id, section_column: 3 })
    signals = only_new do
      assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "two" } }).ok?
    end

    assert_equal %w[structure], signals.map { |signal| signal["reason"] }
  end

  test "the page's own save signals saved with no block, and a post's its post" do
    page_signals = only_new { assert Pages::Save.call(@page, translations: { "en" => { subtitle: "s" } }).ok? }
    post = create_post(title: "News", published: false)
    post_signals = only_new(Editing::Signals.record_stream(post)) { assert Posts::Save.call(post, translations: { "en" => { excerpt: "e" } }).ok? }

    assert_equal [ { "kind" => "content", "content_block_id" => nil, "reason" => "saved" } ], page_signals
    assert_equal [ { "kind" => "content", "content_block_id" => nil, "reason" => "saved" } ], post_signals
  end

  test "trashing a page signals gone" do
    assert_equal %w[gone], only_new { assert Trash::Move.call(@page).ok? }.map { |signal| signal["reason"] }
  end

  test "the tab that made the change is named, and a junk id is left out" do
    named = Current.set(editing_tab: "tab-12345678") { only_new { ContentBlocks::Save.call(@block, translations: { "en" => { caption: "a" } }) } }
    junk = Current.set(editing_tab: "<script>") { only_new { ContentBlocks::Save.call(@block, translations: { "en" => { caption: "b" } }) } }

    assert_equal "tab-12345678", named.sole["origin"]
    assert_not junk.sole.key?("origin")
  end

  test "nothing is sent for a write that is rolled back, and a signal that fails does not fail the write" do
    rolled = only_new do
      ActiveRecord::Base.transaction do
        ContentBlocks::Save.call(@block, translations: { "en" => { caption: "gone" } })
        raise ActiveRecord::Rollback
      end
    end
    assert_empty rolled

    Live::Signals.stub(:later, ->(*) { raise "the cable is away" }) do
      assert ContentBlocks::Save.call(@block, translations: { "en" => { caption: "kept" } }).ok?
    end
    assert_equal "kept", @block.reload.caption
  end

  test "a note, a sign-in and a library image's save signal nothing on the page's stream" do
    assert_empty only_new { Editing::Signals.heard(Audit::Event.new(action: "note.started", subject_type: "Page", subject_id: @page.id)) }
    assert_empty only_new { Editing::Signals.heard(Audit::Event.new(action: "session.created")) }
  end
end
```

`test/channels/editing/channel_test.rb`, in the shape of `test/channels/presence/channel_test.rb` (same `connect_as`):

```ruby
require "test_helper"

class Editing::ChannelTest < ActionCable::Channel::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")
  end

  def connect_as(user) = stub_connection(current_user: user, session_id: user.sessions.create!.id)

  test "a reader is subscribed to the record's stream, built from the record that was found" do
    connect_as users(:reader)
    subscribe type: "page", id: @page.id

    assert subscription.confirmed?
    assert_has_stream "editing:record:Page-#{@page.id}"
  end

  test "a record out of scope, a trashed one, an unknown kind and a bad id are rejected alike" do
    connect_as @stranger
    subscribe type: "page", id: @page.id
    assert subscription.rejected?

    connect_as users(:one)
    assert Trash::Move.call(@page).ok?
    [ { type: "page", id: @page.id }, { type: "tag", id: 1 }, { type: "page", id: "1 OR 1=1" } ].each do |params|
      subscribe(**params)
      assert subscription.rejected?, params.inspect
    end
  end

  test "the channel offers a client no action" do
    assert_empty Editing::Channel.action_methods.to_a
  end
end
```

Run `PGGSSENCMODE=disable bin/rails test test/models/editing test/channels/editing`. Expected: errors, `NameError: uninitialized constant Editing`.

- [ ] **Step 3: Build.**

```ruby
# app/models/editing.rb
# Live refresh and edit reservations (live-editing spec; the look is its
# handoff). Two things live here.
#
# LIVE REFRESH: what someone saves appears in every other open editor of that
# page or post. `Editing::Signals` hears the audit log's after-commit
# notification and says, on the record's stream, THAT something changed (a
# kind, ids, a reason); the editor fetches the part through the read scope.
#
# RESERVATIONS: a block, a page's settings or a post that someone is changing
# is theirs for `HOLD` after their last saved change (`Editing::Reservation`),
# read-only for everyone else, who can take it over (`Editing::TakeOver`).
#
# A RESERVATION IS NOT CONTENT. Claiming, renewing and releasing are not
# `ApplicationService`s and are not audited (as presence's marks are not):
# they write only their own row, never the record, and they would flood the
# log. Taking over is the one audited write. Nothing here knows notes or
# presence, and the content side does not know this module: the only thing a
# content service does for it is name a deleted block's page in the event it
# already records.
module Editing
  # How long a reservation lasts after its holder's last saved change.
  HOLD = 2.minutes
  # How long a take-over waits for the holder's tab to hand over.
  PASS_OVER = 5.seconds
  # How long "Taken over by ..." and "Updated by ..." stay on screen.
  NOTICE = 6.seconds
  # The sweep's age. Nothing depends on it: every read ignores a row after HOLD.
  SWEEP_AFTER = 10.minutes

  # What a request names with `block_id`: that block of this page, or the
  # record itself (a page's settings, a post). Nil for a block that is not
  # this record's: the caller answers 404.
  def self.subject_of(record, block_id)
    return record if block_id.blank?
    return unless record.is_a?(Page)

    id = block_id.to_s[/\A\d{1,18}\z/] or return
    record.content_blocks.find_by(id:)
  end

  # The subject's name in the page (`data-editing-subject`) and in a request.
  def self.key(subject) = subject.is_a?(ContentBlock) ? "block-#{subject.id}" : "record"
end
```

```ruby
# app/models/editing/signals.rb
module Editing
  # What live editing says, and to whom (live-editing spec §3.1, §4.2).
  #
  # THE SOURCE IS THE AUDIT LOG. Every content write records an event, and
  # `Audit.record` publishes `Audit::NOTIFICATION` once the outermost
  # transaction has committed, also for an event coalesced into an earlier
  # one. `heard` is subscribed to it (`config/initializers/editing.rb`) and
  # maps the event's ACTION to a signal, so no content service names this
  # feature, and a write through the MCP server or the console is covered like
  # one from CS Studio. `MAP` and `SILENT` together hold every action in
  # `Audit::Sentence::ACTIONS` (`test/models/editing/signals_test.rb` fails
  # for one neither knows): a new write path is covered by a line here, not by
  # a call someone has to remember.
  #
  # A SIGNAL SAYS ONLY THAT SOMETHING CHANGED: `kind` "content", the block's
  # id (nil for the record itself and for the list's structure), a `reason`
  # and the tab that caused it. Never text. It is sent on the stream of the
  # page or post, to which `Editing::Channel` subscribes through the read
  # scope, and what it leads to is fetched through that scope again.
  #
  # NEVER RAISES. It runs inside the request that made the write, after the
  # commit: an exception here would turn a saved block into an error page.
  module Signals
    SAVED = "saved".freeze
    STRUCTURE = "structure".freeze
    GONE = "gone".freeze

    MAP = {
      "page.updated" => SAVED, "page.published" => SAVED, "page.unpublished" => SAVED, "page.moved" => SAVED,
      "page.translation_confirmed" => SAVED, "page.trashed" => GONE, "page.purged" => GONE,
      "post.updated" => SAVED, "post.published" => SAVED, "post.unpublished" => SAVED, "post.scheduled" => SAVED,
      "post.translation_confirmed" => SAVED, "post.trashed" => GONE, "post.purged" => GONE,
      "block.created" => STRUCTURE, "block.deleted" => STRUCTURE, "block.reordered" => STRUCTURE,
      "block.updated" => SAVED, "block.translation_confirmed" => SAVED
    }.freeze

    SILENT = {
      "page.created" => "nobody has an editor open on a page that did not exist",
      "post.created" => "nobody has an editor open on a post that did not exist",
      "page.restored" => "a trashed page has no open editor: its editor answers 404",
      "post.restored" => "a trashed post has no open editor: its editor answers 404",
      "ai.translated" => "it writes nothing: the suggestions go to the tab that asked",
      "media.uploaded" => "library images are not live in this step (spec section 9)",
      "media.updated" => "library images are not live in this step (spec section 9)",
      "media.trashed" => "library images are not live in this step (spec section 9)",
      "media.restored" => "library images are not live in this step (spec section 9)",
      "media.purged" => "library images are not live in this step (spec section 9)",
      "media.translation_confirmed" => "library images are not live in this step (spec section 9)",
      "settings.translation_confirmed" => "site settings are saved explicitly and have no live editor",
      "settings.updated" => "site settings are saved explicitly and have no live editor",
      "tag.renamed" => "it touches the posts that carry the tag; their open forms are refused as stale, as before (roadmap)",
      "tag.deleted" => "it touches the posts that carry the tag; their open forms are refused as stale, as before (roadmap)",
      "tag.merged" => "it touches the posts that carry the tag; their open forms are refused as stale, as before (roadmap)"
    }.merge(
      (Audit::Sentence::NOTE_VERBS.keys + Audit::Sentence::SPECIAL_ACTIONS).index_with { "not a change to a page's or a post's content" },
      %w[user.created user.updated user.deleted group.created group.updated group.deleted token.issued token.revoked]
        .index_with { "an account, a group or a token is not content" }
    ).freeze

    module_function

    def record_stream(record) = "editing:record:#{record.class.polymorphic_name.delete(":")}-#{record.id}"

    # The audit notification's listener.
    def heard(event)
      reason = MAP[event.action]
      unless reason
        raise ArgumentError, "Editing::Signals knows no action #{event.action.inspect}" unless SILENT.key?(event.action)

        return
      end

      type, id, block_id = place(event)
      return unless type && id

      block_id = nil unless reason == SAVED && !structural?(event)
      reason = STRUCTURE if structural?(event)
      send_to("editing:record:#{type}-#{id}", kind: "content", content_block_id: block_id, reason:)
    rescue StandardError => error
      Rails.logger.warn("Editing signal not sent (#{event&.action}): #{error.class}")
      Rails.error.report(error, handled: true)
    end

    # A change of holder (spec §4.2): every other tab fetches that card again.
    def holder(record, subject, reason)
      send_to(record_stream(record), kind: "holder", content_block_id: (subject.id if subject.is_a?(ContentBlock)), reason:)
    end

    def send_to(stream, payload)
      origin = Current.editing_tab.to_s[Live::Signals::TAB]
      Live::Signals.later(stream, origin ? payload.merge(origin:) : payload)
    end

    # [ owner type, owner id, block id ] of the page or post an event is about.
    # A block that still exists is read from its row (one indexed read, after
    # the commit); a deleted one from the metadata `ContentBlocks::Destroy`
    # writes. A block of a post has no editor of its own and no signal.
    def place(event)
      return [ event.subject_type, event.subject_id, nil ] unless event.subject_type == "ContentBlock"

      if event.action == "block.deleted"
        page_id = event.metadata.to_h["page_id"]
        return page_id.is_a?(Integer) ? [ "Page", page_id, nil ] : nil
      end

      owner_type, owner_id = ContentBlock.where(id: event.subject_id).pick(:owner_type, :owner_id)
      owner_type == "Page" ? [ "Page", owner_id, event.subject_id ] : nil
    end

    # A save that moved blocks between a section's columns (a fold) redraws the
    # list, like a move. Its event is never coalesced, so its metadata is its own.
    def structural?(event) = event.action == "block.updated" && event.metadata.to_h["folded_block_ids"].present?

    private_class_method :send_to, :place, :structural?
  end
end
```

`block.reordered`'s subject is the page, so `place` answers it through the first line. If `Audit::Sentence::ACTIONS` holds a name not listed above, the first test says which: add it to `MAP` or `SILENT` and say in the report what you chose and why. (Task 10 records three more actions, `page.taken_over`, `post.taken_over` and `block.taken_over`, and adds them to `SILENT` there.)

```ruby
# app/channels/editing/channel.rb
module Editing
  # The stream of one page or post (live-editing spec §3.1), found through the
  # read scope at subscribe time and rejected alike for a record out of scope,
  # trashed, missing or of an unknown kind, by `Live::RecordChannel`. It
  # offers a client no action and writes nothing: both hooks are private.
  class Channel < Live::RecordChannel
    private

    def stream_name_for(record) = Signals.record_stream(record)
  end
end
```

```ruby
# config/initializers/editing.rb
# Live refresh hears the audit log (live-editing spec §3.1). The notification
# is named by its string, not by `Audit::NOTIFICATION`, so that no application
# constant is loaded while Rails boots; `test/models/editing/signals_test.rb`
# ("a block's save signals its page") fails if the two ever differ. The block
# names `Editing::Signals` each time it runs, so a development reload is
# followed. Subscribed once per process: an initializer runs once.
ActiveSupport::Notifications.subscribe("audit.content_spiel") do |*, payload|
  Editing::Signals.heard(payload[:event])
end
```

`app/models/current.rb`, after `notes_tab`:

```ruby
# The opaque id of the browser tab a CS Studio request came from: the header
# `X-Notes-Tab`, in the shape `Live::Signals::TAB`, read for EVERY admin
# request by `Admin::BaseController`. Only `Editing` reads it: as the
# `origin` of its signals and as the tab that holds a reservation. It is not
# `notes_tab`, which only the notes controllers set: a content request that
# set that one would put an origin on `Notes::Remove`'s signal, and the tab
# that deleted a block would skip the refresh of its own notes drawer.
attribute :editing_tab
```

`app/controllers/admin/base_controller.rb`, directly after `before_action { Current.channel = :admin }`:

```ruby
before_action { Current.editing_tab = request.headers["X-Notes-Tab"].to_s[Live::Signals::TAB] }
```

`app/services/content_blocks/destroy.rb`: the event becomes

```ruby
# `page_id`: the block's row is gone when the audit notification runs after
# the commit, and whoever hears it (live refresh) could not find the page.
record_event("block.deleted", subject: @block, metadata: metadata.merge("page_id" => @block.owner_id))
```

and `test/services/content_blocks/destroy_test.rb` gains "the deleted block's event names its page" (`assert_equal page.id, Audit::Event.where(action: "block.deleted").last.metadata["page_id"]`).

- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test test/models test/channels test/services test/lib test/integration/admin`. Expected: 0 failures. `bin/rails zeitwerk:check`. Expected: "All is good!". The guards admitted here need no edit: `test/models/notes/signals_test.rb` finds `Live::Signals.later` in a file that says `module Signals`, and `test/lib/admin_namespace_shadow_test.rb` now derives `Editing` from `app/models/editing/`; confirm both pass and say so in the report.

- [ ] **Step 5: Commit** `feat: a content write signals the page or post it belongs to, from the audit log's notification`.

---

### Task 3: The parts an editor fetches

**Files:**
- Create: `app/controllers/admin/editing_controller.rb`, `app/queries/editing/last_change.rb`, `app/javascript/controllers/admin/editing/live_controller.js` (an empty controller until Task 5), `app/components/admin/editor_screen/live_region_component.rb` (+ `.html.erb`), `app/components/admin/editor_screen/updated_mark_component.rb` (+ `.html.erb`), `test/integration/admin/editing_test.rb`, `test/queries/editing/last_change_test.rb`, `test/components/admin/editor_screen/updated_mark_component_test.rb`
- Modify: `config/routes.rb`, `app/components/admin/editor_screen/block_card_component.rb` + `.html.erb`, `block_tile_component.html.erb`, `section_card_component.html.erb`, `page_settings_form_component.html.erb`, `post_form_component.html.erb`, `app/views/admin/pages/show.html.erb`, `app/views/admin/posts/show.html.erb`, `config/locales/admin/editor_screen.en.yml`, `test/integration/trash_visibility_test.rb`

**Interfaces:**
- Consumes: `Admin::RecordOfKind#record_of_kind(name, id)`, `Editing.subject_of`, `Editing.key`, `Admin::ContentBlocksController`'s way of drawing a card (`SectionCardComponent.for`, `draws?`, `BlockOutline`).
- Produces, routes (inside the admin scope, after presence's):
  ```ruby
  scope "editing/:kind/:id", constraints: { kind: /page|post/, id: /\d+/ } do
    get "blocks", to: "editing#blocks", as: :editing_blocks
    get "blocks/:block_id", to: "editing#block", as: :editing_block, constraints: { block_id: /\d+/ }
    get "record", to: "editing#record", as: :editing_record
  end
  ```
  `admin_editing_blocks_path(kind: "page", id: 3, locale: "de")`, `admin_editing_block_path(kind:, id:, block_id:)`, `admin_editing_record_path(kind:, id:)`. Each answers an HTML fragment with no layout and `Cache-Control: no-store`; 404 for a record out of scope, trashed or of another kind, for `blocks` of a post and for a block that is not this page's.
  - `blocks` → the children of `#content-blocks-list`, as `pages/show.html.erb` draws them.
  - `block` → the elements that are this block in this editor: its card (`#content_block_<id>`) for a top-level block or on a translation tab; its tile (`#content_block_<id>`) and its panel (`#block-<id>-panel`) for a block in a section on the default tab. For a block that is a section (`SectionCardComponent.draws?`): **204**, and the caller fetches `blocks`. A block deleted since: **410**, empty body until Task 9 fills it. With `mark=1` the card carries the "Updated" mark.
  - `record` → `#page-settings` for a page; `#post-form` for a post (from Task 7 on, preceded by the header's notice area, `#editor-notice`, which is where a post's strip stands).
- Produces, in the markup (the merge reads exactly these):
  - `data-editing-unit` on what is replaced or kept as one: every block card wrapper (`:list`, `:panel`, `:group`), the section's own form (`#section-<id>-form`), `#page-settings`, `#post-form`. Each also carries `data-editing-subject="<Editing.key>"`.
  - `data-editing-part` on what is always replaced: a tile.
  - `id="page-settings"` on the settings `<details>`, `id="post-form"` on the post's `<form>`.
  - `<span data-editing-mark-slot></span>` in a card's header, after the name and its marker (after the panel title in a panel).
- Produces: `Admin::EditorScreen::LiveRegionComponent.new(record:, locale:, url_options:)`, with content: a `div#editing` with `data-controller="admin--editing--live"`, `data-live-part="waiting"`, and the values `kind`, `id`, `blocks-url`, `block-url` (with the literal `:block_id` left in it: `admin_editing_block_path(kind:, id:, block_id: "BLOCK").sub("BLOCK", ":block_id")`), `record-url`, `notice` (`Editing::NOTICE.in_milliseconds`). Task 9 adds the hold controller and its values to the same element, Task 11 two more values.
- Produces: `Editing::LastChange.for(block, viewer:)` → `Editing::LastChange::Change = Data.define(:user, :at)` or nil (nil when the newest change was the viewer's own, or there is none). `Admin::EditorScreen::UpdatedMarkComponent.new(change:)`, which renders nothing for nil.

- [ ] **Step 1: Write the failing tests.** `test/queries/editing/last_change_test.rb`:

```ruby
require "test_helper"

class Editing::LastChangeTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing", published: false)
    @block = as(users(:one), channel: :admin) { ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "image" }).record }
  end

  test "the newest change by someone else is named, with its time" do
    travel(1.minute) { as(users(:two), channel: :admin) { assert ContentBlocks::Save.call(@block, translations: { "en" => { caption: "x" } }).ok? } }

    change = Editing::LastChange.for(@block, viewer: users(:one))

    assert_equal users(:two), change.user
    assert_in_delta 1.minute.from_now.to_f, change.at.to_f, 2
  end

  test "the viewer's own newest change is no change to tell them about, and a block nobody changed has none" do
    assert_nil Editing::LastChange.for(@block, viewer: users(:one))
    assert_nil Editing::LastChange.for(ContentBlock.new, viewer: users(:one))
  end

  test "a note and a take-over on the block are not changes" do
    as(users(:two), channel: :admin) { Audit.record("note.started", subject: @block, snapshot: nil) }

    assert_nil Editing::LastChange.for(@block, viewer: users(:one))
  end

  test "it is two statements at most: the event, and its user" do
    assert_operator capture_sql { Editing::LastChange.for(@block, viewer: users(:two)) }.size, :<=, 2
  end
end
```

`test/integration/admin/editing_test.rb`:

```ruby
require "test_helper"

class Admin::EditingTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing", published: false)
    @block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "image" }).record
    @section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "two" } }).record
    @inside = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text", section_id: @section.id, section_column: 1 }).record
    @stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")
    sign_in_as users(:one)
  end

test "the list is the page's cards, top-level blocks and the section with its tiles and panels, and nothing else of the page" do
  get admin_editing_blocks_path(kind: "page", id: @page.id)

  assert_response :ok
  assert_equal "no-store", response.headers["Cache-Control"]
  assert_select "#content_block_#{@block.id}[data-editing-unit][data-editing-subject='block-#{@block.id}']"
  assert_select "#content_block_#{@section.id} #block-#{@inside.id}-panel[data-editing-unit][hidden]"
  assert_select "#content_block_#{@section.id} #content_block_#{@inside.id}[data-editing-part]"
  assert_select "#page-settings", false
  assert_select "html > head > title", false, "a fragment, not a page"
end

test "a top-level block is its card; a block in a section is its tile and its panel; a section is 204" do
  get admin_editing_block_path(kind: "page", id: @page.id, block_id: @block.id)
  assert_select "#content_block_#{@block.id}[data-editing-unit]", 1

  get admin_editing_block_path(kind: "page", id: @page.id, block_id: @inside.id)
  assert_select "#content_block_#{@inside.id}[data-editing-part]", 1
  assert_select "#block-#{@inside.id}-panel[data-editing-unit]", 1

  get admin_editing_block_path(kind: "page", id: @page.id, block_id: @section.id)
  assert_response :no_content
end

test "on a translation tab the block's card is drawn in that language" do
  get admin_editing_block_path(kind: "page", id: @page.id, block_id: @inside.id, locale: "de")

  assert_select "#content_block_#{@inside.id}[data-editing-unit]", 1
  assert_select "#block-#{@inside.id}-panel", false
end

test "with mark=1 the card says who changed it, and never for the viewer's own change" do
  travel(1.minute) { as(users(:two), channel: :admin) { assert ContentBlocks::Save.call(@block, translations: { "en" => { caption: "x" } }).ok? } }
  users(:two).update!(name: "Dana Weiss")

  get admin_editing_block_path(kind: "page", id: @page.id, block_id: @block.id, mark: 1)
  assert_select "#content_block_#{@block.id} [data-editing-mark]", text: /Updated by Dana Weiss/

  get admin_editing_block_path(kind: "page", id: @page.id, block_id: @block.id)
  assert_select "[data-editing-mark]", false
end

test "the record's form: the settings for a page, the form for a post, each a unit with the base its next save needs" do
  get admin_editing_record_path(kind: "page", id: @page.id)
  assert_select "#page-settings[data-editing-unit][data-editing-subject=record] input#page-base-updated-at[value=?]", @page.settings_changed_at.iso8601(6)

  post = create_post(title: "News", published: false)
  get admin_editing_record_path(kind: "post", id: post.id)
  assert_select "#post-form[data-editing-unit][data-editing-subject=record] input#post-base-updated-at[value=?]", post.updated_at.iso8601(6)
end

test "outside the read scope, in the trash, of another page and of an unknown kind every part is not found" do
  other = create_page(title: "Other", published: false)
  foreign = ContentBlocks::Save.call(ContentBlock.new(owner: other), attributes: { block_type: "rich_text" }).record
  get admin_editing_block_path(kind: "page", id: @page.id, block_id: foreign.id)
  assert_response :not_found

  get "/cs-studio/editing/media/1/record"
  assert_response :not_found

  post = create_post(title: "News")
  get "/cs-studio/editing/post/#{post.id}/blocks"
  assert_response :not_found

  sign_in_as @stranger
  [ admin_editing_blocks_path(kind: "page", id: @page.id), admin_editing_block_path(kind: "page", id: @page.id, block_id: @block.id),
    admin_editing_record_path(kind: "page", id: @page.id) ].each do |path|
    get path
    assert_response :not_found, path
  end
end

test "a block deleted since is gone, not missing" do
  id = @block.id
  assert ContentBlocks::Destroy.call(@block).ok?

  get admin_editing_block_path(kind: "page", id: @page.id, block_id: id)

  assert_response :gone
end

test "a reader gets the parts, view-only" do
  sign_in_as users(:reader)
  get admin_editing_blocks_path(kind: "page", id: @page.id)

  assert_response :ok
  assert_select "form[data-controller~='admin--saving--autosave']", false
end

test "the list costs the same statements for 3 blocks as for 30" do
  three = capture_sql { get admin_editing_blocks_path(kind: "page", id: @page.id) }.size
  27.times { ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }) }
  thirty = capture_sql { get admin_editing_blocks_path(kind: "page", id: @page.id) }.size

  assert_equal three, thirty
end
end
```

(The tests between `setup` and the final `end` are shown at the file's left margin for width; indent them into the class.) In `test/integration/trash_visibility_test.rb`, in the file's own style: "a trashed page's and a trashed post's editing parts are not served" (the three GETs for each, 404).

Run `PGGSSENCMODE=disable bin/rails test test/queries/editing test/integration/admin/editing_test.rb`. Expected: errors (`uninitialized constant Editing::LastChange`, no route).

- [ ] **Step 2: The query.**

```ruby
# app/queries/editing/last_change.rb
module Editing
  # Who last changed a block, for the "Updated by Dana Weiss" mark an editor
  # shows when a colleague's save arrives (handoff 10). Read from the audit
  # log, as "Changed by ..." is. The viewer's own change is nobody to name
  # (handoff 22). A note on the block and a take-over are not changes
  # (`Dashboard::Feed::NOT_A_CHANGE`).
  module LastChange
    Change = Data.define(:user, :at)

    module_function

    def for(block, viewer:)
      return unless block.persisted?

      event = Audit::Event.where(subject_type: "ContentBlock", subject_id: block.id)
        .where.not(action: Dashboard::Feed::NOT_A_CHANGE).where.not(user_id: nil)
        .order(last_occurred_at: :desc, id: :desc).includes(:user).first
      return if event.nil? || event.user.nil? || event.user_id == viewer&.id

      Change.new(user: event.user, at: event.last_occurred_at)
    end
  end
end
```

(`Audit::Event` has `belongs_to :user, optional: true`; `includes(:user)` is the second statement the test allows.)

- [ ] **Step 3: The marks in the markup.** In `BlockCardComponent#wrapper_attributes` both branches gain `editing_unit: "", editing_subject: ::Editing.key(block)` in their `data:`. In `block_card_component.html.erb`, add `<span data-editing-mark-slot><%= render updated_mark %></span>`: after `<%= render note_marker %>` in the `:list` and `:group` branches, and after the `<h3>` in the `panel?` branch; the component gains `updated_by: nil` in `initialize` and `def updated_mark = Admin::EditorScreen::UpdatedMarkComponent.new(change: @updated_by)`. The tile's root element gains `data-editing-part`. `section_card_component.html.erb`'s settings form gains `data: form_data.merge(editing_unit: "", editing_subject: ::Editing.key(section))`. `page_settings_form_component.html.erb`'s `<details>` gains `id="page-settings" data-editing-unit data-editing-subject="record"`; `post_form_component.html.erb`'s `form_with` gains `id: "post-form"` and the same two data attributes.

```ruby
# app/components/admin/editor_screen/updated_mark_component.rb
module Admin
  module EditorScreen
    # "Updated by Dana Weiss · just now" (handoff 10): in a card's header for a
    # few seconds after a colleague's save arrived. Drawn only in the answer to
    # the editor's own fetch (`Admin::EditingController#block` with `mark=1`);
    # `admin--editing--live` takes it away after `Editing::NOTICE`. Not
    # announced (handoff 21): no live region, no role.
    class UpdatedMarkComponent < AdminComponent
      def initialize(change:)
        @change = change
      end

      def render? = @change.present?

      def name = ::PersonName.of(@change.user)

      def at = @change.at
    end
  end
end
```

```erb
<%# app/components/admin/editor_screen/updated_mark_component.html.erb %>
<span data-editing-mark class="admin-editing-mark shrink-0 text-xs text-meta"><%= t(".updated_by", name: name) %> · <%= render Admin::Ui::TimeAgoComponent.new(time: at) %></span>
```

`config/locales/admin/editor_screen.en.yml` gains, under `admin.components.editor_screen`, `updated_mark: { updated_by: "Updated by %{name}" }`. Its component test: renders the name through `PersonName.of` (a user without a name shows the part of the address before the at sign), a name with markup in it is text, nil renders nothing.

- [ ] **Step 4: The controller, the routes, the live region.**

```ruby
# app/controllers/admin/editing_controller.rb
module Admin
  # What an open editor fetches when it is told something changed
  # (live-editing spec §3.2), and from Task 7 on the reservation's four
  # writes. A class, never `Admin::Editing`, which would shadow `Editing::`.
  #
  # EVERY PART IS FOUND THROUGH THE READ SCOPE and drawn for its viewer as
  # they are now: a record out of scope, in the trash or of a kind with no
  # editor is a 404, and so is a block of another page. The answers are
  # fragments (no layout), fetched with a plain `fetch` the write queue
  # neither holds nor counts, and kept by no cache.
  class EditingController < BaseController
    include RecordOfKind

    PLACEMENT = "placement".freeze

    before_action { response.set_header("Cache-Control", "no-store") }
    before_action :set_record

    # The children of `#content-blocks-list`, as the page view draws them.
    def blocks
      raise ActiveRecord::RecordNotFound unless @record.is_a?(Page)

      preload_blocks
      outline = BlockOutline.new(@record.content_blocks)
      top = outline.top_level
      editable = helpers.can_edit?(@record)
      render html: helpers.safe_join(top.each_with_index.map { |block, index| view_context.render(card_for(block, outline:, editable:, first: index.zero?, last: index == top.size - 1)) })
    end

    # One block, as this editor shows it. 204 for a section: its card holds
    # other blocks' forms, so the caller fetches the list. 410 for a block
    # deleted since.
    def block
      raise ActiveRecord::RecordNotFound unless @record.is_a?(Page)

      block = @record.content_blocks.find_by(id: params[:block_id])
      return block_gone if block.nil?

      preload_blocks
      outline = BlockOutline.new(@record.content_blocks)
      return head(:no_content) if Admin::EditorScreen::SectionCardComponent.draws?(block, outline:)

      editable = helpers.can_edit?(@record)
      change = params[:mark].present? ? ::Editing::LastChange.for(block, viewer: Current.user) : nil
      render html: helpers.safe_join(parts_of(block, outline:, editable:, change:).map { |part| view_context.render(part) })
    end

    # The record's own form: a page's settings, a post's form.
    def record
      form = if @record.is_a?(Page)
        Admin::EditorScreen::PageSettingsFormComponent.new(page: @record, locale: admin_locale, url_options: admin_url_options)
      else
        Admin::EditorScreen::PostFormComponent.new(post: @record, locale: admin_locale, url_options: admin_url_options, slot_context: {}, form_only: true)
      end
      render form, layout: false
    end

    private

    def set_record
      @record = record_of_kind(params[:kind], params[:id])
    end

    # A block that is not this page's and one that never existed are a 404; a
    # block this page's audit log says was deleted is a 410. Asked of the
    # event `ContentBlocks::Destroy` writes, which names its page.
    def block_gone
      deleted = Audit::Event.where(action: "block.deleted", subject_type: "ContentBlock", subject_id: params[:block_id].to_i)
        .order(id: :desc).first
      raise ActiveRecord::RecordNotFound unless deleted && deleted.metadata["page_id"] == @record.id

      head :gone
    end

    def preload_blocks
      ActiveRecord::Associations::Preloader.new(records: [ @record ], associations: [ { content_blocks: { media_asset: Media::Asset::VARIANT_INCLUDES } } ]).call
    end

    def card_for(block, outline:, editable:, first:, last:)
      common = { page: @record, locale: admin_locale, url_options: admin_url_options, first:, last:, editable: }
      if Admin::EditorScreen::SectionCardComponent.draws?(block, outline:)
        Admin::EditorScreen::SectionCardComponent.for(section: block, outline:, **common)
      else
        Admin::EditorScreen::BlockCardComponent.new(block:, **common)
      end
    end

    # The elements that are this block: its card; or, in a section on the
    # default tab, its tile and its panel (on a translation tab a block in a
    # section is a card of its section's group).
    def parts_of(block, outline:, editable:, change:)
      common = { page: @record, block:, locale: admin_locale, url_options: admin_url_options }
      if block.section_id.nil?
        top = outline.top_level
        [ Admin::EditorScreen::BlockCardComponent.new(**common, editable:, first: top.first == block, last: top.last == block, updated_by: change) ]
      elsif admin_locale == ::Locales.default
        [ Admin::EditorScreen::BlockTileComponent.new(**common, editable:),
          Admin::EditorScreen::BlockCardComponent.new(**common, editable:, placement: :panel, updated_by: change) ]
      else
        [ Admin::EditorScreen::BlockCardComponent.new(**common, editable:, placement: :group, updated_by: change) ]
      end
    end
  end
end
```

Read `Admin::EditorScreen::SectionGroupComponent` before relying on `placement: :group` for a block in a section on a translation tab, and build the card with exactly the arguments that component passes. `PostFormComponent` gains `form_only: false`: with it true the template renders the `<form>` alone, without the header above it (wrap the header's `render` in `<% unless form_only? %>`). `helpers.can_edit?` is `AccessControlHelper#can_edit?`; if it is not reachable from a controller, include the helper module in the controller class and say so.

Add the routes of the Interfaces block to `config/routes.rb` after presence's two, with a comment in the file's style (the scope's shape, why `kind` is not `media`).

```ruby
# app/components/admin/editor_screen/live_region_component.rb
module Admin
  module EditorScreen
    # The element an editor's live scripts stand on (live-editing spec §6):
    # around the page's settings and blocks, or a post's form. It is a part of
    # the page that holds a cable subscription of its own, so the server
    # renders `data-live-part="waiting"` and the script writes "answered"
    # (`live/state`; `await_notes_live` in the system tests waits for it).
    # Everything the scripts need from the server is a value here: they hold
    # no address, no number and no wording.
    class LiveRegionComponent < AdminComponent
      def initialize(record:, locale:, url_options: {})
        @record = record
        @locale = locale
        @url_options = url_options
      end

      def kind = ::RecordKinds.of(@record).name

      def region_data
        route = { kind: kind, id: @record.id, **@url_options }
        {
          controller: "admin--editing--live", live_part: "waiting",
          "admin--editing--live-kind-value": kind, "admin--editing--live-id-value": @record.id,
          "admin--editing--live-blocks-url-value": (helpers.admin_editing_blocks_path(**route) if @record.is_a?(::Page)),
          "admin--editing--live-block-url-value": (helpers.admin_editing_block_path(**route, block_id: 0).sub("/blocks/0", "/blocks/:block_id") if @record.is_a?(::Page)),
          "admin--editing--live-record-url-value": helpers.admin_editing_record_path(**route),
          "admin--editing--live-notice-value": ::Editing::NOTICE.in_milliseconds
        }.compact
      end
    end
  end
end
```

```erb
<%# app/components/admin/editor_screen/live_region_component.html.erb %>
<%= tag.div id: "editing", data: region_data do %><%= content %><% end %>
```

In `pages/show.html.erb` wrap the `PageSettingsFormComponent` render, `#content-blocks-alert` and the `<section class="admin-content-blocks">` (not the header, not the notes drawer) in `<%= render Admin::EditorScreen::LiveRegionComponent.new(record: @page, locale: admin_locale, url_options: admin_url_options) do %> … <% end %>`. In `posts/show.html.erb` wrap the `PostFormComponent` render the same way. The header stays outside: nothing in it is fetched.

- [ ] **Step 5: Run** `PGGSSENCMODE=disable bin/rails test test/queries test/integration test/components test/lib`. Expected: 0 failures (the layout guard "every admin identifier written in the app has a controller file" fails until Task 5 adds `live_controller.js`: create the file now with the body `import { Controller } from "@hotwired/stimulus"` / `export default class extends Controller {}` and a one-line comment that Task 5 fills it).

- [ ] **Step 6: Commit** `feat: the parts of an editor can be fetched one by one, through the read scope`.

---
### Task 4: The merge rule is one module

**Files:**
- Create: `app/javascript/editing/merge.js`, `test/system/admin/editing_merge_test.rb`
- Modify: `config/importmap.rb` (after the `notes` pin: `pin_all_from "app/javascript/editing", under: "editing", preload: "admin"`, with a comment in the file's style), `test/integration/public_javascript_test.rb` (`ADMIN_ONLY` gains `editing/`), `app/components/admin/editor_screen/section_card_component.html.erb` (two ids)

**Interfaces:**
- Consumes: the marks of Task 3 (`data-editing-unit`, `data-editing-part`, the ids).
- Produces, from `editing/merge`:
  - `holds(unit, unsaved)` → boolean: whether one of the unit's OWN forms (not those of a unit nested in it) is unsaved. `unsaved(form)` is the caller's predicate.
  - `mergeList(list, fresh, { unsaved })` → `{ kept: Element[], gone: Element[] }`. `list` is `#content-blocks-list` on screen, `fresh` an element whose children are the server's cards. Every unit that `holds` unsaved text stays THE SAME ELEMENT and is not moved unless two such units changed places; everything else is replaced by what was fetched. A kept unit the answer no longer has stays and gets `data-editing-gone="true"`.
  - `mergeUnits(root, fresh, { unsaved })` → `{ replaced: Element[], kept: Element[], missing: boolean }`: each child of `fresh` replaces the element of the same id inside `root`, unless that element is a unit holding unsaved text (kept) or is not there or is of the other shape (`missing`: the caller fetches the list).
  - `anchored(root, draw)` → what `draw()` returned, with the scroll adjusted so the block that has the focus, or else the first one in view, is where it was on screen (handoff 12).
  - A card that stays or is replaced keeps its state: a collapsed card is collapsed, the open panel of a section is open and its tile says so, the focus is put back on the control of the same id.
- The module touches the document only inside `list` or `root`, opens no connection, fetches nothing and reads no controller. The section card's header gets `id="section-<id>-header"` and its body already has `id="section-<id>-body"`: **every ancestor of a unit, up to the list, has an id**, which is what lets a section be merged in place around a panel that stays.

- [ ] **Step 1: Write the module's tests first.** The project has no JavaScript test runner: a system test imports the module in the browser (as `test/system/admin/notes_merge_test.rb` does). `test/system/admin/editing_merge_test.rb`:

```ruby
require "application_system_test_case"

class Admin::EditingMergeSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing", published: false)
    @first = add_block
    @second = add_block
    @section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "two" } }).record
    @inside = add_block(section_id: @section.id, section_column: 1)
    sign_in_via_form(users(:one))
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    # `window.Stimulus` is the application, as `app/javascript/controllers/application.js` exposes it; if this app does
    # not, reach the application the way `test/system/admin/notes_merge_test.rb` reaches its module and controllers.
    page.execute_script(<<~JS)
      window.__merge = import("editing/merge")
      window.__unsaved = (form) => {
        const autosave = window.Stimulus.getControllerForElementAndIdentifier(form, "admin--saving--autosave")
        return Boolean(autosave) && (!autosave.clean() || autosave.outstanding() || !autosave.unchanged())
      }
      window.__fresh = async (path) => {
        const body = new DOMParser().parseFromString(await (await fetch(path)).text(), "text/html").body
        return body
      }
    JS
  end

  def add_block(**placement)
    ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text", **placement }).record
  end

  def card(block) = "#content_block_#{block.id}"

  def panel(block) = "#block-#{block.id}-panel"

  # Types into the block's caption-like plain field without letting the debounce send it: the autosave's debounce is
  # raised on the form first, so the form is unsaved for as long as the test needs.
  def type_unsaved(block, text, within: card(block))
    page.execute_script("document.querySelector(#{"#{within} form[data-controller~='admin--saving--autosave']".to_json}).setAttribute('data-admin--saving--autosave-debounce-value', 600000)")
    field = find("#{within} .ProseMirror", visible: :all)
    field.click
    field.send_keys(text)
  end

  def merge_list
    page.evaluate_async_script(<<~JS, "/cs-studio/editing/page/#{@page.id}/blocks")
      const [ path, done ] = arguments
      Promise.all([ window.__merge, window.__fresh(path) ]).then(([ merge, fresh ]) => {
        const list = document.getElementById("content-blocks-list")
        const result = merge.anchored(list, () => merge.mergeList(list, fresh, { unsaved: window.__unsaved }))
        done({ kept: result.kept.map((each) => each.id), gone: result.gone.map((each) => each.id) })
      })
    JS
  end

  test "a card that holds unsaved text is the same element with its text after a list merge, and a clean one is replaced" do
    type_unsaved(@first, "half a sentence")
    page.execute_script("window.__a = document.querySelector(#{card(@first).to_json}); window.__b = document.querySelector(#{card(@second).to_json})")
    as(users(:two), channel: :admin) { assert ContentBlocks::Save.call(@second, translations: { "en" => { body: rich_doc("Theirs") } }).ok? }

    result = merge_list

    assert_equal [ "content_block_#{@first.id}" ], result["kept"]
    assert page.evaluate_script("window.__a === document.querySelector(#{card(@first).to_json})")
    assert_not page.evaluate_script("window.__b === document.querySelector(#{card(@second).to_json})")
    assert_selector "#{card(@first)} .ProseMirror", text: "half a sentence"
    assert_selector "#{card(@second)} .ProseMirror", text: "Theirs"
  end
end
```

`rich_doc(markdown)` is `test/support/content_helper.rb`'s. Add, in the same file and the same style, each with the element identity held in a `window` variable before the merge and compared with `===` after it:

  - "a replaced card carries the base its next save needs" (after the colleague's save, `#block-<second>-base-updated-at`'s value equals `@second.reload.updated_at.iso8601(6)`).
  - "an added block appears in its place, a moved one snaps to its place and a deleted one goes, with no card of the list left twice" (the colleague adds a block, reverses the order with `ContentBlocks::Reorder`, deletes `@second`; after the merge the ids of `#content-blocks-list > [data-block-id]` equal the server's top-level order and are unique).
  - "a block deleted while its form holds unsaved text stays, marked gone" (`result["gone"]` is its id, the element is the same, `data-editing-gone="true"`).
  - "a hidden panel that holds unsaved text is the same element after a list merge, and stays hidden" (open `@inside`'s tile, type, close the panel through the tile with the debounce raised so nothing is sent; merge; `===`, `hidden`, the text is there). **Review Focus 4.**
  - "the open panel of a section is open after a merge and its tile says so; a collapsed card stays collapsed" (`aria-expanded="true"` on the tile's face; `[data-block-body].hidden` on the collapsed card and `aria-expanded="false"` on its name).
  - "a section's own unsaved setting stays while its lanes take a colleague's new tile" (change the section's background select with the debounce raised; the colleague adds a block to column 2; after the merge `#section-<id>-form` is the same element with the chosen value, and the new tile is in the second lane).
  - "two cards that both hold unsaved text keep both texts when their order changed" (the one case a kept element is moved).
  - "merging the same answer twice changes nothing the second time" (`list.innerHTML` equal, and the same elements).
  - "the block being read does not move on screen when a card is added above it" (scroll so `@section`'s card is at the top; the colleague adds three blocks and moves them to the top with `Reorder`; `getBoundingClientRect().top` of the section's card differs by less than 2 before and after). The window is not resized.
  - "one block's answer replaces its card and nothing else; a card holding unsaved text is kept; an answer of the other shape is reported missing" (`mergeUnits` with `/cs-studio/editing/page/<id>/blocks/<block>`; for the last, the colleague moves `@first` into the section before the fetch: `missing` is true and the list is untouched).
  - "the focus is on the same field after its card was replaced" (focus a clean card's `.ProseMirror`, merge, `document.activeElement` is inside the new card).
  - "a part that shows an alert is not replaced" (put a `role="alert"` element into `#editor-notice` of a post editor, call `mergeUnits` with an answer holding an empty `#editor-notice`: the alert is still there and the element is in `kept`).

Run: `bin/rails tailwindcss:build && PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/editing_merge_test.rb`. Expected: every test fails at `import("editing/merge")` (the specifier does not resolve).

- [ ] **Step 2: Write the module.**

```js
// app/javascript/editing/merge.js
//
// THE MERGE RULE of live editing (live-editing spec §3.2), and nothing else:
//
//   A FORM THAT HOLDS CHANGES NOT YET SAVED IS NEVER REPLACED, AND NEITHER IS
//   ANYTHING ELSE OF ITS UNIT. EVERYTHING ELSE IS REPLACED BY WHAT WAS FETCHED.
//
// A UNIT (`data-editing-unit`) is what is replaced or kept as one: a block's
// card (in the list, as a section's panel, in a translation tab's group), a
// section's own settings form, the page settings panel, a post's form. A
// PART (`data-editing-part`, a section's tile) holds no form and is always
// replaced. "Unsaved" is the caller's question (`unsaved(form)`): the write
// queue's own, asked of the form's autosave controller.
//
// A KEPT UNIT IS THE SAME ELEMENT AFTERWARDS, AND IS NOT MOVED. Moving an
// element takes it out of the document and puts it back: its Stimulus
// controllers disconnect and connect, the rich-text editor is mounted again
// and the caret is gone, under someone who is typing. So the list is not
// replaced and the kept units put back into it; the list is RECONCILED
// AROUND them: what does not stay is removed, what was fetched is inserted
// before, between and after what stays, and an element that is the ancestor
// of a kept unit (a section's card, its body, its panels) stays too and is
// reconciled inside, level by level, matched by id. That is why every
// ancestor of a unit up to the list has an id. The one time a kept unit is
// moved is when two kept units changed places.
//
// A kept unit the answer no longer has (its block was deleted) stays where
// it is, marked `data-editing-gone`; the caller puts the notice on it.
//
// This module touches the document only inside the element it is handed. It
// opens no connection, fetches nothing, raises no toast and knows no
// controller. Its tests are `test/system/admin/editing_merge_test.rb`.

const UNIT = "[data-editing-unit]"
// Set by a script on an element that stays, and not the server's to take away.
const RUNTIME = [ "inert", "data-picked", "data-notes-active", "data-editing-stays" ]

// Whether one of the unit's own forms is unsaved. A section's settings form
// is itself the unit; a card's forms are those not inside a nested unit.
export function holds(unit, unsaved) {
  const forms = unit.matches("form") ? [ unit ] : [ ...unit.querySelectorAll("form") ].filter((form) => form.closest(UNIT) === unit)
  return forms.some(unsaved)
}

export function mergeList(list, fresh, { unsaved }) {
  const keep = new Set([ ...list.querySelectorAll(UNIT) ].filter((unit) => unit.id && holds(unit, unsaved)))
  const gone = []
  withState(list, () => reconcile(list, [ ...fresh.children ], keep, gone))
  return { kept: [ ...keep ], gone }
}

export function mergeUnits(root, fresh, { unsaved }) {
  const result = { replaced: [], kept: [], missing: false }
  withState(root, () => {
    for (const twin of [ ...fresh.children ]) {
      const live = twin.id ? document.getElementById(twin.id) : null
      if (!live || !root.contains(live) || live.matches(UNIT) !== twin.matches(UNIT)) { result.missing = true; continue }
      if (live.matches(UNIT) && holds(live, unsaved)) { result.kept.push(live); continue }
      // A notice the person has not dealt with ("Changed elsewhere", lost
      // work) is theirs to dismiss: a part that shows one is not replaced.
      if (!live.matches(UNIT) && live.querySelector("[role=alert]")) { result.kept.push(live); continue }
      live.replaceWith(twin)
      result.replaced.push(twin)
    }
  })
  return result
}

// Runs `draw` and puts the block the person is in, or else the first one in
// view, back where it was on screen.
export function anchored(root, draw) {
  const inFocus = document.activeElement?.closest?.("[data-block-id], [data-editing-unit]")
  const anchor = (inFocus && root.contains(inFocus) && inFocus) ||
    [ ...root.querySelectorAll("[data-block-id]") ].find((card) => !card.closest("[hidden]") && card.getBoundingClientRect().bottom > 0)
  const top = anchor?.getBoundingClientRect().top
  const result = draw()
  const now = anchor && (anchor.isConnected ? anchor : anchor.id && document.getElementById(anchor.id))
  if (now && top !== undefined) {
    const moved = now.getBoundingClientRect().top - top
    if (moved !== 0) scrollerOf(root).scrollTop += moved
  }
  return result
}

const carries = (element, keep) => keep.has(element) || [ ...keep ].some((unit) => element.contains(unit))

// Makes `container`'s children those of `fresh`, in that order, around what stays.
function reconcile(container, fresh, keep, gone) {
  const wanted = new Set(fresh.map((each) => each.id).filter(Boolean))
  for (const child of [ ...container.children ]) {
    if (!carries(child, keep)) { child.remove(); continue }
    if (wanted.has(child.id)) continue
    // It stays although the answer has no such element: its block is gone.
    child.setAttribute("data-editing-stays", "true")
    for (const unit of keep) if ((unit === child || child.contains(unit)) && !gone.includes(unit)) { unit.dataset.editingGone = "true"; gone.push(unit) }
  }
  let after = null
  for (const twin of fresh) {
    const live = twin.id ? [ ...container.children ].find((child) => child.id === twin.id) : null
    if (live && !keep.has(live)) {
      syncAttributes(live, twin)
      reconcile(live, [ ...twin.children ], keep, gone)
    }
    const node = live || twin
    let expected = after ? after.nextElementSibling : container.firstElementChild
    while (expected && expected !== node && expected.hasAttribute("data-editing-stays")) expected = expected.nextElementSibling
    if (node !== expected) container.insertBefore(node, expected)
    after = node
  }
}

function syncAttributes(live, twin) {
  for (const { name } of [ ...live.attributes ]) if (!twin.hasAttribute(name) && !RUNTIME.includes(name)) live.removeAttribute(name)
  for (const { name, value } of [ ...twin.attributes ]) if (live.getAttribute(name) !== value) live.setAttribute(name, value)
}

// What the person did to the screen and the server knows nothing of: which
// cards are collapsed, which panel of a section is open, where the focus is.
function withState(root, draw) {
  const collapsed = [ ...root.querySelectorAll("[data-block-body].hidden") ].map((body) => body.id).filter(Boolean)
  const open = [ ...root.querySelectorAll("[data-admin--editor--section-target~='panel']:not([hidden])") ].map((panel) => panel.id).filter(Boolean)
  const focused = document.activeElement && root.contains(document.activeElement) ? document.activeElement : null
  const focusedId = focused?.id || focused?.closest("[id]")?.id

  draw()

  for (const id of collapsed) {
    const body = document.getElementById(id)
    if (!body || !root.contains(body)) continue
    body.classList.add("hidden")
    root.querySelector(`[aria-controls="${CSS.escape(id)}"]`)?.setAttribute("aria-expanded", "false")
  }
  for (const id of open) {
    const panel = document.getElementById(id)
    if (!panel || !root.contains(panel)) continue
    panel.hidden = false
    root.querySelector(`.admin-block-tile__face[aria-controls="${CSS.escape(id)}"]`)?.setAttribute("aria-expanded", "true")
  }
  if (focused && !focused.isConnected && focusedId) {
    const again = document.getElementById(focusedId)
    const target = again?.matches("input, textarea, select, button, [contenteditable=true]") ? again : again?.querySelector("[contenteditable=true], input:not([type=hidden]), textarea, select, button")
    target?.focus({ preventScroll: true })
  }
}

function scrollerOf(element) {
  for (let each = element.parentElement; each; each = each.parentElement) {
    const overflow = getComputedStyle(each).overflowY
    if ((overflow === "auto" || overflow === "scroll") && each.scrollHeight > each.clientHeight) return each
  }
  return document.scrollingElement
}
```

Before relying on `withState`'s panel part, read `openId` in `admin--editor--section`: if it is a remembered value and not read from which panel is not `hidden`, the restore must go through that controller's state instead; say in the report which it is. In `section_card_component.html.erb` give the available section's header `<div class="flex flex-wrap items-center gap-2 p-3">` the id `section-<id>-header` (a component method `header_id`).

- [ ] **Step 3: Run** Step 1's command. Expected: 0 failures. Then `PGGSSENCMODE=disable bin/rails test test/lib test/integration/public_javascript_test.rb`. Expected: 0 failures ("a topic's plain modules are in the folder of the same name" passes because `controllers/admin/editing/` exists since Task 3).

- [ ] **Step 4: Commit** `feat: "replace what was fetched, keep what is unsaved" is one module, editing/merge`.

---

### Task 5: An open editor shows what someone else saved

**Files:**
- Create: `app/javascript/editing/requests.js`, `test/system/admin/editing_live_test.rb`
- Modify: `app/javascript/controllers/admin/editing/live_controller.js` (the stub of Task 3), `app/javascript/saving/queue_core.js`, `app/javascript/saving/queue.js`, `app/javascript/controllers/admin/saving/autosave_controller.js`, `app/javascript/controllers/admin/editor/blocks_controller.js`, `app/javascript/controllers/admin/pages/tree_controller.js`, `app/components/admin/editor_screen/live_region_component.html.erb`, `config/locales/admin/editor_screen.en.yml`, `app/assets/tailwind/application.css`

**Interfaces:**
- Consumes: `Editing::Channel`; the three GETs and the region's values (Task 3); `editing/merge` (Task 4); `listen`, `TAB` from `live/connection`; `settle` from `live/state`.
- Produces, from `saving/queue`: `quiet()` → a promise that resolves once the queue is idle (nothing queued, no form outstanding), taking no turn in it and counting as no write; `writeCount()` re-exported from `saving/queue_state`.
- Produces, from `editing/requests`: `TAB_HEADER` (`"X-Notes-Tab"`); `get(url)` → `{ status, fragment, text }` (`fragment` the parsed body element for a 200, else null; `text` the body as sent; `status` 0 when the request failed or was redirected to sign-in; never rejects); `post(url, params)` → `{ status, text }` (form-encoded, with the CSRF token and the tab header; never rejects). The module also puts the tab header on every Turbo request of the document (`turbo:before-fetch-request`).
- Produces: every write of an editor carries the tab header: the autosave's PATCH, the block reorder's `fetch`, every Turbo form, the tree move's `fetch`.
- Produces, events on the region (`#editing`): `admin--editing--live:merged` (`detail: { part, replaced, kept, gone }`), `admin--editing--live:deleted` (`detail: { blockId, unit }`, for a deleted block whose unit was kept), and it listens to `admin--editing--hold:refresh` (`detail: { subject, discard }`; Task 9 sends it).
- Produces, from `admin--editor--blocks`: the bubbling event `admin--editor--blocks:moving` (`detail: { moving: true | false }`): true when a drag starts (`onStart`) and when the keyboard picks a block up (`pickUp`), false when the move's request has been answered and drawn, when it was cancelled, and on every early return of `move`.

- [ ] **Step 1: Write the failing system tests.** `test/system/admin/editing_live_test.rb`, two people as two Capybara sessions, in the shape of `test/system/admin/presence_test.rb` (`join`, `await_notes_live`, `LIVE = 8`):

```ruby
require "application_system_test_case"

class Admin::EditingLiveSystemTest < ApplicationSystemTestCase
  LIVE = 8

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @me = users(:one).tap { |user| user.update!(name: "Olga Braun") }
    @dana = users(:two).tap { |user| user.update!(name: "Dana Weiss") }
    @page = create_page(title: "Pricing", published: false)
    @block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }).record
    sign_in_via_form(@me)
  end

  teardown { page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}") }

  def open_page(path = "/cs-studio/pages/#{@page.id}")
    visit path
    await_notes_live
  end

  def join(name, user, path: "/cs-studio/pages/#{@page.id}")
    using_session(name) do
      sign_in_via_form(user)
      visit path
      await_notes_live
      yield if block_given?
    end
  end

  def card(block) = "#content_block_#{block.id}"

  def type_in(block, text)
    find("#{card(block)} .ProseMirror").click
    find("#{card(block)} .ProseMirror").send_keys(text)
  end

  test "what a colleague types and saves appears in my open editor, with who and when, and my reload is not needed" do
    open_page
    join(:dana, @dana) do
      type_in(@block, "Prices from May")
      assert_writes_settled
    end

    assert_selector "#{card(@block)} .ProseMirror", text: "Prices from May", wait: LIVE
    assert_selector "#{card(@block)} [data-editing-mark]", text: "Updated by Dana Weiss", wait: LIVE
    assert_no_selector "#toasts [role=status], #toasts [role=alert]"
  end
end
```

Add, in the same file and style (each waits with `assert_selector …, wait: LIVE`, `assert_eventually` or `await_js`; a colleague's write that needs no second browser is made with `as(@dana, channel: :admin) { … }` through the service, which signals exactly as a request does, without an origin):

  - "the mark goes after its time, and is gone at once with reduced motion" (set `data-admin--editing--live-notice-value` to `300` on `#editing` before the colleague's save; `assert_no_selector "[data-editing-mark]", wait: LIVE`).
  - "my own save draws no mark and fetches nothing" (count requests to `/cs-studio/editing/` with a `window.fetch` wrapper that passes every request through and only counts; type, `assert_writes_settled`, `await_frames`; the count is 0 and there is no mark). This is the origin test: it fails if a write is sent without the tab header.
  - "the next save of a refreshed card is saved, not refused as stale" (after the colleague's save appears, type in the same card; `assert_writes_settled`; no `#changed-elsewhere`; the block holds both texts).
  - "an added block appears, a moved one snaps to its place and a deleted one goes, with no mark" (three service calls by the colleague; after each, the ids of `#content-blocks-list > [data-block-id]` equal the server's order; `assert_no_selector "[data-editing-mark]"`).
  - "a card I am typing in is not replaced by a colleague's save of the same block, and my save is then refused as before" (raise the debounce on the card's form, type, the colleague saves the block; hold the element in a `window` variable and compare with `===` after `await_frames`; my text is in it).
  - "a block deleted under my unsaved text stays, with my text" (the same, then `ContentBlocks::Destroy`; the card is there with `data-editing-gone="true"`).
  - "the settings form takes a colleague's saved subtitle, and mine is saved afterwards although they saved blocks in between" (the spec's §8 last case: the colleague saves a block, I change the subtitle, `assert_writes_settled`, no `#changed-elsewhere`, the page holds my subtitle).
  - "a post's form takes a colleague's save" (a post editor in both sessions; `#post-form` shows the colleague's excerpt).
  - "on a translation tab the card of the block is refreshed in that language" (open `?locale=de` with German enabled the way the translation system tests enable it; the colleague saves the block's German body; it appears). **Review Focus 4.**
  - "a hidden tab fetches nothing, and catches up once when it is seen" (hide the document as `presence_test.rb`'s `hide_document` does; the colleague saves twice and adds a block; the request counter stays 0; `show_document`; exactly one request to `…/blocks` and one to `…/record`; the list is current).
  - "a confirmed subscription fetches the list and the record's form once" (the counter after `await_notes_live` is one of each). **Review Focus 1.**
  - "after the socket drops and comes back the editor catches up" (`import("live/connection")` then drop the socket the way `test/system/admin/live_connection_test.rb` or `notes_live_test.rb` does it; the colleague saves meanwhile; after the reconnect the text is there).
  - "a structure signal that arrives during a drag is drawn after the drop, with the dropped block where it was dropped" (three blocks; start a pointer drag of the first with `drag_pointer`'s first half as `test/system/admin/sections_test.rb` does and hold it; the colleague adds a block; `await_frames`: the list has no new card; drop below the second; `assert_writes_settled`; the list equals the server's order, with my block where I dropped it and the colleague's block present). **Review Focus 2.**
  - "an answer fetched before this tab's own write was queued is not drawn" (stub `window.fetch` so that ONLY the request whose URL ends in `/editing/page/<id>/blocks` is held, and every other one is passed through unchanged; the colleague adds a block; `await_js` until one request is held; move my first block down through its menu; release the held answer; `assert_writes_settled`; the list equals the server's order). **Review Focus 2.**
  - "a page trashed under me says so and offers the way back" (the colleague trashes the page with `Trash::Move`; `assert_selector "#editor-notice [data-editing-missing]", wait: LIVE`, with a link to the pages screen).
  - "a refreshed card keeps the count on its notes marker" (a note on the block; the colleague saves the block; the marker of the new card shows the count).
  - "live refresh uses no Turbo request: no visit, no frame load, no stream" (listeners on `turbo:before-fetch-request`, `turbo:before-stream-render` and `turbo:visit` count while a colleague's save arrives: 0).

Run `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/editing_live_test.rb`. Expected: every test fails (nothing arrives).

- [ ] **Step 2: The queue's two exports.** In `app/javascript/saving/queue_core.js`, after `busy`:

```js
// Resolves once the queue is idle: nothing queued or in flight and no form
// with an edit still to send. For a READ that must not be older than this
// tab's own writes (live editing's fetches): it waits beside the queue. It
// takes no turn, is counted as no write and tells no form to send early
// (unlike `drained`), so a reader never changes what the writers do.
export async function quiet() {
  while (!idle()) {
    await chain()
    await new Promise((resolve) => setTimeout(resolve, 25))
  }
}
```

In `app/javascript/saving/queue.js`: add `quiet` to the re-export from `saving/queue_core` and `export { writeCount } from "saving/queue_state"`; one sentence in the façade's header says who uses the two (`controllers/admin/editing/live_controller.js`).

- [ ] **Step 3: The requests module and the tab header.**

```js
// app/javascript/editing/requests.js
import { TAB } from "live/connection"

// The requests of live editing, and the tab's id on every write of an editor.
//
// THE TAB HEADER. The server reads `X-Notes-Tab` (the name it had when only
// notes sent it) into `Current.editing_tab` for every CS Studio request: it
// is the `origin` of a signal, so the tab that saved skips its own echo, and
// it is who holds a reservation. A write sent without it is nobody's: it
// claims nothing and its own tab would fetch what it has just drawn. Turbo's
// requests get it here; the three hand-built ones (`admin--saving--autosave`,
// `admin--editor--blocks`' reorder, `admin--pages--tree`'s move) add it
// themselves from `TAB_HEADER`.
export const TAB_HEADER = "X-Notes-Tab"

document.addEventListener("turbo:before-fetch-request", (event) => {
  const headers = event.detail.fetchOptions?.headers
  if (headers && !headers[TAB_HEADER]) headers[TAB_HEADER] = TAB
})

// A plain GET of one part. Not a Turbo request: the write queue neither
// holds nor counts it, and nobody who listens to Turbo's events hears it.
export async function get(url) {
  try {
    const response = await fetch(url, { headers: { Accept: "text/html", [TAB_HEADER]: TAB }, credentials: "same-origin" })
    if (response.redirected) return { status: 0, fragment: null, text: "" }
    const text = await response.text()
    const fragment = response.status === 200 ? new DOMParser().parseFromString(text, "text/html").body : null
    return { status: response.status, fragment, text }
  } catch {
    return { status: 0, fragment: null, text: "" }
  }
}

export function headers() {
  return { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content, [TAB_HEADER]: TAB, Accept: "text/vnd.turbo-stream.html, application/json" }
}

// A POST of a reservation's write. The CALLER puts it in the write queue.
export async function post(url, params = {}, options = {}) {
  try {
    const response = await fetch(url, { method: "POST", headers: headers(), body: new URLSearchParams(params), credentials: "same-origin", ...options })
    return { status: response.redirected ? 0 : response.status, text: await response.text() }
  } catch {
    return { status: 0, text: "" }
  }
}
```

In `autosave_controller.js`: `import { TAB_HEADER } from "editing/requests"` and `import { TAB } from "live/connection"`; `requestHeaders()` gains `[TAB_HEADER]: TAB`. In `blocks_controller.js`: the reorder `fetch`'s headers gain the same; so do the two `fetch`es of `admin--pages--tree`. The header comment of `live/connection.js` gains editing as a user.

- [ ] **Step 4: The `moving` event.** In `blocks_controller.js`: a method `sayMoving(moving) { this.dispatch("moving", { detail: { moving } }) }`; call `this.sayMoving(true)` in `sortableOptions`' `onStart` and in `pickUp`; wrap the body of `move` in `try { … } finally { this.sayMoving(false) }` (its `await this.queueMove(…)` resolves when the answer has been drawn or the block put back, and the early returns are covered); call `this.sayMoving(false)` at the end of `cancel`. Read `queueMove`, `sendMove` and `takeTurn` to confirm the awaited promise resolves only then; if a path resolves earlier, say so in the report and dispatch from where the turn ends.

- [ ] **Step 5: The live script.**

```js
// app/javascript/controllers/admin/editing/live_controller.js
import { Controller } from "@hotwired/stimulus"
import { listen, TAB } from "live/connection"
import { settle } from "live/state"
import { quiet, writeCount } from "saving/queue"
import { get } from "editing/requests"
import { anchored, mergeList, mergeUnits } from "editing/merge"

// LIVE REFRESH of an open page or post editor (live-editing spec §3.2). On
// the element `Admin::EditorScreen::LiveRegionComponent` renders.
//
// It hears, on the record's stream (`Editing::Channel`), THAT something
// changed -- a kind, a block's id, a reason -- and fetches that part with a
// plain GET through the read scope, as its viewer may see it now: one block,
// the block list (`structure`), or the record's own form. What comes back is
// handed to `editing/merge`, which never replaces a form that holds unsaved
// changes. The tab that made the change skips its own signal (`origin`).
//
// AN ANSWER IS DRAWN ONLY IF IT IS THE NEWEST THING THIS TAB KNOWS:
// - each part has a number, and an answer whose number is not the part's
//   newest is dropped (two fetches of one part can overtake each other);
// - a fetch waits until this tab's write queue is quiet (`quiet()`), and an
//   answer during whose flight this tab queued a write (`writeCount()`) is
//   dropped and asked for again: it was read before that write;
// - the list is not fetched or drawn while a block is being dragged or is
//   picked up by the keyboard (`admin--editor--blocks:moving`): it is owed,
//   and paid when the move has been answered.
//
// A HIDDEN DOCUMENT FETCHES NOTHING; it owes everything and pays once when it
// is seen. Whenever the subscription is confirmed (the first time and after
// every reconnect) the list and the record's form are fetched once: a signal
// sent while the socket was down was not heard.
//
// A 404 means the record is gone or no longer the viewer's to read: the
// editor says so in the header's notice area and offers the way back.
//
// It writes nothing, sends nothing through the write queue and uses no Turbo
// request, visit, frame or stream (`test/system/admin/editing_live_test.rb`).
export default class extends Controller {
  static targets = [ "missing" ]
  static values = { kind: String, id: String, blocksUrl: String, blockUrl: String, recordUrl: String, notice: { type: Number, default: 6000 } }

  connect() {
    this.asked = new Map()
    this.owed = new Set()
    this.timers = new Set()
    this.moving = false
    const listener = Object.assign((signal) => this.heard(signal), {
      connected: () => { this.say("answered"); this.catchUp() },
      rejected: () => this.say("answered"),
      disconnected: () => this.say("waiting")
    })
    // One order and the id as a string: the pool's key is the params' JSON.
    this.stop = listen({ channel: "Editing::Channel", type: this.kindValue, id: String(this.idValue) }, listener)
    if (this.stop.up) listener.connected()
    else if (this.stop.settled) this.say("answered")

    this.seen = () => { if (!document.hidden) this.pay() }
    this.moved = (event) => { this.moving = event.detail.moving; if (!this.moving) this.pay() }
    this.asked_for = (event) => this.refresh(event.detail)
    document.addEventListener("visibilitychange", this.seen)
    this.element.addEventListener("admin--editor--blocks:moving", this.moved)
    this.element.addEventListener("admin--editing--hold:refresh", this.asked_for)
  }

  disconnect() {
    this.stop?.()
    document.removeEventListener("visibilitychange", this.seen)
    this.element.removeEventListener("admin--editor--blocks:moving", this.moved)
    this.element.removeEventListener("admin--editing--hold:refresh", this.asked_for)
    this.timers.forEach(clearTimeout)
    settle(document.body)
  }

  say(word) {
    this.element.setAttribute("data-live-part", word)
    settle(document.body)
  }

  heard(signal) {
    if (signal.origin === TAB) return
    if (signal.kind !== "content" && signal.kind !== "holder") return
    if (signal.reason === "gone") return this.want("record")
    if (signal.reason === "structure") return this.want("blocks")
    this.want(signal.content_block_id ? `block:${signal.content_block_id}` : "record", { mark: signal.kind === "content" })
  }

  // The hold script asks for a subject's part again: a hold that lapsed, a
  // refused form that is discarded (`discard`: its unit may be replaced
  // although its form is not clean).
  refresh({ subject, discard = false }) {
    if (discard) document.querySelector(`[data-editing-unit][data-editing-subject="${CSS.escape(subject)}"]`)?.setAttribute("data-editing-discard", "true")
    this.want(subject === "record" ? "record" : `block:${subject.replace("block-", "")}`)
  }

  catchUp() {
    if (this.hasBlocksUrlValue) this.want("blocks")
    this.want("record")
  }

  want(part, options = {}) {
    if (document.hidden) { this.owed.add("blocks").add("record"); return }
    if (this.moving && part !== "record") { this.owed.add(part); return }
    this.fetch(part, options)
  }

  pay() {
    if (document.hidden || this.moving) return
    const owed = [ ...this.owed ]
    this.owed.clear()
    // The list holds every block: a block owed beside it needs no fetch of its own.
    owed.filter((part) => !(part.startsWith("block:") && owed.includes("blocks"))).forEach((part) => this.want(part))
  }

  async fetch(part, options = {}) {
    if (part === "blocks" && !this.hasBlocksUrlValue) return
    const number = (this.asked.get(part) || 0) + 1
    this.asked.set(part, number)
    const newest = () => this.asked.get(part) === number && this.element.isConnected

    await quiet()
    if (!newest()) return
    const writes = writeCount()
    const answer = await get(this.urlFor(part, options))
    if (!newest()) return
    if (writeCount() !== writes) return this.fetch(part, options)
    if (document.hidden || (this.moving && part !== "record")) { this.owed.add(part); return }
    this.draw(part, answer)
  }

  urlFor(part, { mark = false } = {}) {
    if (part === "blocks") return this.blocksUrlValue
    if (part === "record") return this.recordUrlValue
    const url = new URL(this.blockUrlValue.replace(":block_id", part.slice("block:".length)), window.location.origin)
    if (mark) url.searchParams.set("mark", "1")
    return url.toString()
  }

  draw(part, answer) {
    if (answer.status === 404) return this.gone()
    if (part === "blocks") {
      if (!answer.fragment) return
      const list = this.element.querySelector("#content-blocks-list")
      const result = anchored(list, () => mergeList(list, answer.fragment, { unsaved: this.unsaved }))
      result.gone.forEach((unit) => this.dispatch("deleted", { detail: { blockId: unit.dataset.blockId, unit } }))
      return this.dispatch("merged", { detail: { part, replaced: [], ...result } })
    }
    if (part === "record") {
      if (!answer.fragment) return
      return this.dispatch("merged", { detail: { part, gone: [], ...mergeUnits(this.element, answer.fragment, { unsaved: this.unsaved }) } })
    }
    // One block. 204: a section, whose card holds other blocks' forms. 410:
    // deleted since. Either way the list says what is true now.
    if (answer.status === 204 || answer.status === 410) return this.want("blocks")
    if (!answer.fragment) return
    const result = anchored(this.element, () => mergeUnits(this.element, answer.fragment, { unsaved: this.unsaved }))
    if (result.missing) return this.want("blocks")
    result.replaced.forEach((unit) => this.fade(unit.querySelector("[data-editing-mark]")))
    this.dispatch("merged", { detail: { part, gone: [], ...result } })
  }

  // The write queue's own question, put to a form the merge would replace.
  // A unit whose text the person has discarded is nobody's to keep.
  unsaved = (form) => {
    if (form.closest("[data-editing-discard]")) return false
    const autosave = this.application.getControllerForElementAndIdentifier(form, "admin--saving--autosave")
    return Boolean(autosave) && (!autosave.clean() || autosave.outstanding() || !autosave.unchanged())
  }

  // "Updated by ..." stays for `notice` and fades over 200ms (handoff 10);
  // with reduced motion it goes at once.
  fade(mark) {
    if (!mark) return
    const later = (act, ms) => { const timer = setTimeout(() => { this.timers.delete(timer); act() }, ms); this.timers.add(timer) }
    later(() => {
      if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return mark.remove()
      mark.classList.add("admin-editing-mark--leaving")
      later(() => mark.remove(), 200)
    }, this.noticeValue)
  }

  // The record is in the trash, deleted or no longer this viewer's: said once,
  // in the header's notice area, with the way back; nothing is fetched again.
  gone() {
    this.stop?.()
    const notice = document.getElementById("editor-notice")
    if (notice && this.hasMissingTarget && !notice.querySelector("[data-editing-missing]")) notice.replaceChildren(this.missingTarget.content.cloneNode(true))
  }
}
```

`live_region_component.html.erb` gains, inside the element, `<template data-admin--editing--live-target="missing">` holding a `role="alert"` bar in the markup of `changed_elsewhere_component.html.erb` (`bg-warn-tint text-warn-ink`, 13px) with `data-editing-missing`, the sentence `t(".missing")` ("This page was moved to the trash or deleted, or you can no longer open it." for a page; `missing_post` for a post) and a link `t(".back")` ("Back to pages" / "Back to posts") to `admin_pages_path` / `admin_posts_path` with `data-turbo-frame="_top"`. In `application.css`, beside the other admin component rules: `.admin-editing-mark { transition: opacity 200ms var(--ease-cs); } .admin-editing-mark--leaving { opacity: 0; }` (use the token the file already uses for `ease-cs`; no colour is written).

- [ ] **Step 6: Run** Step 1's command (0 failures), then `PGGSSENCMODE=disable bin/rails test test/lib test/integration`, then `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/sections_test.rb test/system/admin/tree_test.rb test/system/admin/notes_flow_test.rb test/system/admin/notes_live_test.rb test/system/admin/presence_test.rb test/system/admin/promotion_hold_test.rb`. Expected: 0 failures, no assertion edited.

- [ ] **Step 7: Commit** `feat: an open editor shows what someone else saved, part by part, around what is being typed`.

---

### Task 6: Reservations in the database

**Files:**
- Create: `db/migrate/20261011110000_create_edit_reservations.rb`, `app/models/editing/reservation.rb`, `app/models/editing/rights.rb`, `app/queries/editing/holds.rb`, `app/jobs/editing/sweep.rb`, `test/models/editing/reservation_test.rb`, `test/models/editing/rights_test.rb`, `test/models/editing_test.rb`, `test/queries/editing/holds_test.rb`, `test/jobs/editing/sweep_test.rb`
- Modify: `config/recurring.yml`, `db/schema.rb`

**Interfaces:**
- Table `edit_reservations`: `subject_type` string, `subject_id` bigint, `record_type` string, `record_id` bigint, `user_id` bigint (FK users, cascade), `tab` string, `changed_at` datetime, all not null; `requested_by_id` bigint (FK users, nullify), `requested_tab` string, `requested_at` datetime; no timestamps; unique index `index_edit_reservations_on_subject` on `[subject_type, subject_id]`; index `index_edit_reservations_on_record` on `[record_type, record_id]`. No foreign key to the subject or the record: a deleted block's row expires and is swept.
- `Editing::Reservation` (every method one statement, no row lock, no callback, nothing but its own row):
  - `.claim(subject:, record:, user:, tab:, now: Time.current)` → `:taken` (this tab holds it now and did not before), `:renewed` (it held it and still does), `:refused` (another tab holds it live).
  - `.release(subject:, user:, tab:)` → true when it deleted the row.
  - `.request(subject:, by:, tab:, now: Time.current)` → true when a live row of ANOTHER tab now carries the request (`requested_at` is kept when the same tab asks again).
  - `.hand_over(subject:, user:, tab:, now: Time.current)` → true when the row passed from that holder to its requester.
  - `.pass_over(subject:, by:, tab:, now: Time.current)` → true when the row passed to the requester whose request is `Editing::PASS_OVER` old or older.
  - `.holder_of(subject, now: Time.current)` → the live row with its `user` loaded, or nil.
  - scopes `live(now = Time.current)`, `of(subject)`, `on(record)`.
- `Editing::Rights.missing(actor, record)` → the permission key the actor lacks to change that page or post (`"pages.edit"`, `"pages.publish"`, …), or nil.
- `Editing::Holds.on(record, viewer:, tab:, now: Time.current)` → an object read with ONE statement (plus one for the users): `#of(subject)` → the live `Reservation` or nil; `#other(subject)` → the live reservation unless it is this viewer's in this tab (a person's own other tab IS other; a nil `tab` makes every hold other); `#own_user?(reservation)` → the holder is the viewer in another tab; `#any?`. `Editing::Holds.none` answers nil to everything.
- `Editing::Sweep` (`ApplicationJob`), every 5 minutes in every environment.

- [ ] **Step 1: Write the failing tests.** `test/models/editing/reservation_test.rb`:

```ruby
require "test_helper"

class Editing::ReservationTest < ActiveSupport::TestCase
  A = "tab-aaaaaaaa".freeze
  B = "tab-bbbbbbbb".freeze

  setup do
    @page = create_page(title: "Pricing", published: false)
    @block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }).record
    @olga = users(:one)
    @dana = users(:two)
    @now = Time.current.change(usec: 0)
  end

  def claim(user, tab, at: @now, subject: @block) = Editing::Reservation.claim(subject:, record: @page, user:, tab:, now: at)

  test "the first claim takes, the same tab's next renews, and anyone else is refused: another person, and the same person's other tab" do
    assert_equal :taken, claim(@olga, A)
    assert_equal :renewed, claim(@olga, A, at: @now + 30.seconds)
    assert_equal :refused, claim(@dana, B, at: @now + 40.seconds)
    assert_equal :refused, claim(@olga, B, at: @now + 40.seconds)

    row = Editing::Reservation.sole
    assert_equal [ "ContentBlock", @block.id, "Page", @page.id, @olga.id, A ], row.values_at(:subject_type, :subject_id, :record_type, :record_id, :user_id, :tab)
    assert_equal @now + 30.seconds, row.changed_at
  end

  test "a row is live until HOLD after its last change: one instant before it is refused, at it the row is taken" do
    claim(@olga, A)

    assert_equal :refused, claim(@dana, B, at: @now + Editing::HOLD - 0.001)
    assert_equal @olga.id, Editing::Reservation.holder_of(@block, now: @now + Editing::HOLD - 0.001).user_id
    assert_nil Editing::Reservation.holder_of(@block, now: @now + Editing::HOLD)
    assert_equal :taken, claim(@dana, B, at: @now + Editing::HOLD)
    assert_equal [ @dana.id, B ], Editing::Reservation.sole.values_at(:user_id, :tab)
  end

  test "the holder's own claim after its row expired takes it again, and says so" do
    claim(@olga, A)
    assert_equal :taken, claim(@olga, A, at: @now + Editing::HOLD + 1)
  end

  test "a page's settings and a post are subjects too, each its own" do
    post = create_post(title: "News", published: false)
    assert_equal :taken, claim(@olga, A, subject: @page)
    assert_equal :taken, Editing::Reservation.claim(subject: post, record: post, user: @dana, tab: B, now: @now)
    assert_equal :taken, claim(@dana, B)
    assert_equal 3, Editing::Reservation.count
  end

  test "release deletes only the row of that tab" do
    claim(@olga, A)

    assert_not Editing::Reservation.release(subject: @block, user: @dana, tab: B)
    assert_not Editing::Reservation.release(subject: @block, user: @olga, tab: B)
    assert Editing::Reservation.release(subject: @block, user: @olga, tab: A)
    assert_equal 0, Editing::Reservation.count
  end

  test "a request is written on another tab's live row, keeps its time when asked again, and is nothing on one's own or an expired row" do
    claim(@olga, A)

    assert_not Editing::Reservation.request(subject: @block, by: @olga, tab: A, now: @now)
    assert Editing::Reservation.request(subject: @block, by: @dana, tab: B, now: @now + 1)
    assert Editing::Reservation.request(subject: @block, by: @dana, tab: B, now: @now + 3)
    assert_equal [ @dana.id, B, @now + 1 ], Editing::Reservation.sole.values_at(:requested_by_id, :requested_tab, :requested_at)
    assert_not Editing::Reservation.request(subject: @block, by: @dana, tab: B, now: @now + Editing::HOLD + 5)
  end

  test "the holder's renewal keeps a pending request; a claim of the expired row drops it" do
    claim(@olga, A)
    Editing::Reservation.request(subject: @block, by: @dana, tab: B, now: @now + 1)

    claim(@olga, A, at: @now + 2)
    assert_equal @dana.id, Editing::Reservation.sole.requested_by_id

    claim(users(:reader), "tab-cccccccc", at: @now + Editing::HOLD + 10)
    assert_nil Editing::Reservation.sole.requested_by_id
  end

  test "hand-over passes the row to the requester, once, and only from the holder's tab" do
    claim(@olga, A)
    assert_not Editing::Reservation.hand_over(subject: @block, user: @olga, tab: A, now: @now), "nobody asked"
    Editing::Reservation.request(subject: @block, by: @dana, tab: B, now: @now + 1)

    assert_not Editing::Reservation.hand_over(subject: @block, user: @olga, tab: B, now: @now + 2)
    assert Editing::Reservation.hand_over(subject: @block, user: @olga, tab: A, now: @now + 2)
    assert_equal [ @dana.id, B, @now + 2, nil, nil, nil ], Editing::Reservation.sole.values_at(:user_id, :tab, :changed_at, :requested_by_id, :requested_tab, :requested_at)
    assert_not Editing::Reservation.hand_over(subject: @block, user: @olga, tab: A, now: @now + 3)
  end

  test "pass-over gives the row to the requester once the request is PASS_OVER old, not a moment before, and to nobody else" do
    claim(@olga, A)
    Editing::Reservation.request(subject: @block, by: @dana, tab: B, now: @now)

    assert_not Editing::Reservation.pass_over(subject: @block, by: @dana, tab: B, now: @now + Editing::PASS_OVER - 0.001)
    assert_not Editing::Reservation.pass_over(subject: @block, by: users(:reader), tab: B, now: @now + Editing::PASS_OVER)
    assert Editing::Reservation.pass_over(subject: @block, by: @dana, tab: B, now: @now + Editing::PASS_OVER)
    assert_equal [ @dana.id, B ], Editing::Reservation.sole.values_at(:user_id, :tab)
  end

  test "every statement is one statement, takes no lock and writes nothing but its own row" do
    version = PublicSite.current_content_version
    stamps = [ @page.reload.updated_at, @page.settings_changed_at, @block.reload.updated_at ]
    events = Audit::Event.count

    statements = capture_sql do
      claim(@olga, A)
      claim(@olga, A, at: @now + 1)
      Editing::Reservation.request(subject: @block, by: @dana, tab: B, now: @now + 2)
      Editing::Reservation.hand_over(subject: @block, user: @olga, tab: A, now: @now + 3)
      Editing::Reservation.pass_over(subject: @block, by: @olga, tab: A, now: @now + 4)
      Editing::Reservation.release(subject: @block, user: @dana, tab: B)
    end

    assert_equal 6, statements.size
    assert statements.all? { |sql| sql.include?("edit_reservations") }
    assert statements.none? { |sql| sql.match?(/FOR UPDATE|\bpages\b|\bcontent_blocks\b|\bposts\b/i) }
    assert_equal stamps, [ @page.reload.updated_at, @page.settings_changed_at, @block.reload.updated_at ]
    assert_equal version, PublicSite.current_content_version
    assert_equal events, Audit::Event.count
  end
end

# Two connections at once need rows the other connection can see, so this
# class runs outside the test transaction and names subjects that do not
# exist (a reservation has no foreign key to its subject).
class Editing::ReservationRaceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  teardown { Editing::Reservation.delete_all } # version: none (a test's own rows)

  def subject_and_record = [ ContentBlock.new(id: 9_000_000_001), Page.new(id: 9_000_000_001) ]

  def at_once(callers)
    gate = Queue.new
    threads = callers.map do |caller|
      Thread.new { ActiveRecord::Base.connection_pool.with_connection { gate.pop; caller.call } }
    end
    callers.size.times { gate << :go }
    threads.map(&:value)
  end

  test "two tabs claiming a free subject at once: one takes it, the other is refused, and there is one row" do
    subject, record = subject_and_record
    20.times do
      Editing::Reservation.delete_all # version: none (a test's own rows)
      results = at_once([ [ users(:one), "tab-aaaaaaaa" ], [ users(:two), "tab-bbbbbbbb" ] ].map do |user, tab|
        -> { Editing::Reservation.claim(subject:, record:, user:, tab:) }
      end)

      assert_equal %i[refused taken], results.sort
      assert_equal 1, Editing::Reservation.count
    end
  end

  test "a holder renewing and a stranger claiming at the boundary: exactly one holds afterwards" do
    subject, record = subject_and_record
    20.times do
      Editing::Reservation.delete_all # version: none (a test's own rows)
      start = Time.current - Editing::HOLD
      Editing::Reservation.claim(subject:, record:, user: users(:one), tab: "tab-aaaaaaaa", now: start)
      results = at_once([
        -> { Editing::Reservation.claim(subject:, record:, user: users(:one), tab: "tab-aaaaaaaa") },
        -> { Editing::Reservation.claim(subject:, record:, user: users(:two), tab: "tab-bbbbbbbb") }
      ])

      assert_equal 1, results.count(:taken), results.inspect
      assert_equal 1, results.count(:refused), results.inspect
      assert_equal 1, Editing::Reservation.count
    end
  end
end
```

(The second race is **Review Focus 3** on the server: the row had expired, so whichever statement runs first takes it and the other finds a live row of another tab.) `test/models/editing_test.rb`: `Editing::PASS_OVER < Editing::HOLD`, `Editing::SWEEP_AFTER > Editing::HOLD`; `Editing.subject_of(page, nil)` is the page, with a block's id that block, with another page's block nil, with `"abc"` nil, for a post with any block id nil; `Editing.key`. `test/models/editing/rights_test.rb`: an owner lacks nothing; `users(:reader)` lacks `"pages.edit"`; someone with `pages.edit` and without `pages.publish` lacks nothing on a draft and `"pages.publish"` on a published page (build the group the way `test/services/pages/save_test.rb` does for the same case); the same for a post. `test/queries/editing/holds_test.rb`: `of`, `other` (another person's is other; mine in tab A viewed from tab A is not; mine in tab A viewed from tab B is, and `own_user?` is true; with a nil tab every hold is other); an expired row is nobody's; a deleted holder's row is skipped; the statement count is the same for 1 hold and for 20; `Holds.none`. `test/jobs/editing/sweep_test.rb`: deletes a row `SWEEP_AFTER + 1.minute` old, keeps one `SWEEP_AFTER - 1.minute` old.

Run `PGGSSENCMODE=disable bin/rails test test/models/editing test/models/editing_test.rb test/queries/editing test/jobs/editing`. Expected: errors (`uninitialized constant Editing::Reservation`).

- [ ] **Step 2: The migration.**

```ruby
# db/migrate/20261011110000_create_edit_reservations.rb
# Who is changing a block, a page's settings or a post right now (live-editing
# spec §4.1). One row per subject, by the unique index every claim is made on.
# `record` is the page or post whose stream a change of holder is signalled
# on. No foreign key to the subject or the record: a deleted block's row is
# ignored after `Editing::HOLD` and swept. An ordinary table, as presence's
# is (Rails' schema dumper does not record UNLOGGED).
class CreateEditReservations < ActiveRecord::Migration[8.1]
  def change
    create_table :edit_reservations do |t|
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.references :user, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :tab, null: false
      t.datetime :changed_at, null: false
      t.references :requested_by, index: false, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :requested_tab
      t.datetime :requested_at

      t.index %i[subject_type subject_id], unique: true, name: "index_edit_reservations_on_subject"
      t.index %i[record_type record_id], name: "index_edit_reservations_on_record"
    end
  end
end
```

- [ ] **Step 3: The model.**

```ruby
# app/models/editing/reservation.rb
module Editing
  # One subject (a block, a page's settings, a post) held by one browser tab
  # of one person (live-editing spec §4). `changed_at` is the holder's last
  # saved change or claim; the row is LIVE until `changed_at + Editing::HOLD`
  # and counts as no row from that instant on, whatever the sweep has done.
  # `requested_*` is a pending take-over: who asked, from which tab, when.
  #
  # EVERY METHOD IS ONE STATEMENT on the unique index of the subject, so two
  # tabs can never both hold one; none takes a row lock, none runs a callback
  # and none writes anything but its own row: no `touch`, nothing of the
  # record, no audit event, no content version. The clock is the caller's
  # (`now:`), handed to the statement as a value, so a test asks about any
  # instant without moving time.
  #
  # NOT A SERVICE (`CLAUDE.md`): a reservation is not content, nobody asks for
  # one by name and it is gone in two minutes; audited, it would flood the
  # log. The one audited write is `Editing::TakeOver`.
  class Reservation < ApplicationRecord
    self.table_name = "edit_reservations"

    belongs_to :user
    belongs_to :requested_by, class_name: "User", optional: true
    belongs_to :subject, polymorphic: true, optional: true
    belongs_to :record, polymorphic: true, optional: true

    # Live at `now`: changed less than HOLD ago.
    scope :live, ->(now = Time.current) { where(arel_table[:changed_at].gt(now - Editing::HOLD)) }
    scope :of, ->(subject) { where(subject_type: subject.class.polymorphic_name, subject_id: subject.id) }
    scope :on, ->(record) { where(record_type: record.class.polymorphic_name, record_id: record.id) }

    # Inserts the row, or takes an expired one, or renews the tab's own; a
    # live row of another tab is left as it is and the statement returns
    # nothing. `renewed` is read from the row as it stood before the
    # statement. A pending request survives the holder's own renewal and goes
    # with an expired row.
    CLAIM = <<~SQL.squish.freeze # sql: INSERT ... ON CONFLICT DO UPDATE ... WHERE has no Arel node, and a claim must be one statement
      WITH before AS (
        SELECT user_id, tab, changed_at FROM edit_reservations WHERE subject_type = :subject_type AND subject_id = :subject_id
      )
      INSERT INTO edit_reservations (subject_type, subject_id, record_type, record_id, user_id, tab, changed_at)
      VALUES (:subject_type, :subject_id, :record_type, :record_id, :user_id, :tab, :now)
      ON CONFLICT (subject_type, subject_id) DO UPDATE
        SET record_type = EXCLUDED.record_type, record_id = EXCLUDED.record_id,
            user_id = EXCLUDED.user_id, tab = EXCLUDED.tab, changed_at = EXCLUDED.changed_at,
            requested_by_id = CASE WHEN edit_reservations.changed_at > :cutoff THEN edit_reservations.requested_by_id END,
            requested_tab = CASE WHEN edit_reservations.changed_at > :cutoff THEN edit_reservations.requested_tab END,
            requested_at = CASE WHEN edit_reservations.changed_at > :cutoff THEN edit_reservations.requested_at END
        WHERE edit_reservations.changed_at <= :cutoff
           OR (edit_reservations.user_id = EXCLUDED.user_id AND edit_reservations.tab = EXCLUDED.tab)
      RETURNING (SELECT user_id = :user_id AND tab = :tab AND changed_at > :cutoff FROM before) AS renewed
    SQL

    class << self
      def claim(subject:, record:, user:, tab:, now: Time.current)
        statement = sanitize_sql_array([ CLAIM, {
          subject_type: subject.class.polymorphic_name, subject_id: subject.id,
          record_type: record.class.polymorphic_name, record_id: record.id,
          user_id: user.id, tab:, now:, cutoff: now - Editing::HOLD
        } ])
        rows = connection.exec_query(statement, "Editing claim") # sql: the statement above # version: none (a reservation is not content)
        return :refused if rows.empty?

        rows.first["renewed"] ? :renewed : :taken
      end

      def release(subject:, user:, tab:)
        of(subject).where(user_id: user.id, tab:).delete_all.positive? # version: none (a reservation is not content)
      end

      # Someone asks for a subject another tab holds. `requested_at` is kept
      # when the same tab asks again: the pass-over time runs from the first ask.
      def request(subject:, by:, tab:, now: Time.current)
        same = arel_table[:requested_by_id].eq(by.id).and(arel_table[:requested_tab].eq(tab))
        requested_at = Arel::Nodes::Case.new.when(same).then(arel_table[:requested_at]).else(Arel::Nodes.build_quoted(now))
        of(subject).live(now).where.not(user_id: by.id, tab:)
          .update_all(requested_by_id: by.id, requested_tab: tab, requested_at:).positive? # version: none (a reservation is not content)
      end

      # The holder's tab lets go: the row is the requester's from now.
      def hand_over(subject:, user:, tab:, now: Time.current)
        pass(of(subject).where(user_id: user.id, tab:).where.not(requested_by_id: nil), now)
      end

      # The holder's tab did not answer in PASS_OVER: the requester takes the row.
      def pass_over(subject:, by:, tab:, now: Time.current)
        pass(of(subject).where(requested_by_id: by.id, requested_tab: tab).where(arel_table[:requested_at].lteq(now - Editing::PASS_OVER)), now)
      end

      def holder_of(subject, now: Time.current) = of(subject).live(now).includes(:user).first

      private

      def pass(rows, now)
        rows.update_all(user_id: arel_table[:requested_by_id], tab: arel_table[:requested_tab], changed_at: now, # version: none (a reservation is not content)
          requested_by_id: nil, requested_tab: nil, requested_at: nil).positive?
      end
    end
  end
end
```

If `test/lib/sql_strings_test.rb` or `test/lib/version_bump_test.rb` asks for its comment on another line than written here (each reads "on its line or the line above"), move the comment and leave the statement. `where.not(user_id:, tab:)` is `NOT (user_id = … AND tab = …)` in Rails 6.1 and later: the SQL the "one statement" test prints must say that, not two separate `!=`.

```ruby
# app/models/editing/rights.rb
module Editing
  # The right a person lacks to change a page or a post, by the rule the save
  # services apply (`ContentBlocks::OwnerPermissions`, `Pages::Save`,
  # `Posts::Save`): `edit`, and `publish` too once the record is published,
  # because autosave writes the live record. A reservation is claimed,
  # released and taken over exactly where a save would be allowed.
  module Rights
    module_function

    def missing(actor, record)
      prefix = AccessControl::Checker::BLOCK_OWNER_PREFIX.fetch(record.class.name)
      keys = [ "#{prefix}.edit" ]
      keys << "#{prefix}.publish" if record.published_at.present?
      keys.find { |key| !AccessControl.allowed?(actor, key, record) }
    end
  end
end
```

```ruby
# app/queries/editing/holds.rb
module Editing
  # The live reservations of one page or post, read ONCE for a whole screen:
  # every card, tile and form asks this object, so an editor costs the same
  # statements for 3 blocks as for 30. `viewer` and `tab` say whose screen it
  # is: a hold is OTHER unless it is this person's in this very tab (their
  # other tab is someone else, and so is everyone when the tab is unknown).
  class Holds
    def self.on(record, viewer:, tab:, now: Time.current)
      rows = Reservation.on(record).live(now).includes(:user, :requested_by).to_a.select(&:user)
      new(rows, viewer:, tab:)
    end

    def self.none = new([], viewer: nil, tab: nil)

    def initialize(rows, viewer:, tab:)
      @rows = rows.index_by { |row| [ row.subject_type, row.subject_id ] }
      @viewer = viewer
      @tab = tab
    end

    def any? = @rows.any?

    def of(subject) = @rows[[ subject.class.polymorphic_name, subject.id ]]

    def other(subject)
      hold = of(subject)
      hold unless hold.nil? || mine?(hold)
    end

    def own_user?(hold) = @viewer.present? && hold.user_id == @viewer.id

    private

    def mine?(hold) = own_user?(hold) && @tab.present? && hold.tab == @tab
  end
end
```

```ruby
# app/jobs/editing/sweep.rb
module Editing
  # Every 5 minutes (config/recurring.yml): deletes reservations nobody has
  # renewed for `Editing::SWEEP_AFTER`. It signals nothing and nothing depends
  # on it: every read ignores a row after `Editing::HOLD`.
  class Sweep < ApplicationJob
    queue_as :default

    def perform
      Reservation.where(changed_at: ...Editing::SWEEP_AFTER.ago).delete_all # version: none (a reservation is not content)
    end
  end
end
```

`config/recurring.yml`: in each of the three environments, after `presence_sweep`:

```yaml
  editing_sweep:
    class: Editing::Sweep
    queue: default
    schedule: every 5 minutes
```

- [ ] **Step 4: Run** `bin/rails db:migrate`, then Step 1's command (0 failures), then `PGGSSENCMODE=disable bin/rails test test/lib test/models`. Expected: 0 failures. `bin/rails zeitwerk:check`: "All is good!".

- [ ] **Step 5: Commit** `feat: an edit reservation is a row claimed by one statement on its unique index`.

---

### Task 7: A held card is rendered read-only, with the strip

**Files:**
- Create: `app/components/admin/editor_screen/hold_strip_component.rb` (+ `.html.erb`), `app/components/admin/editor_screen/held_fields.rb`, `test/components/admin/editor_screen/hold_strip_component_test.rb`, `test/components/admin/editor_screen/held_fields_test.rb`
- Modify: `app/components/admin/editor_screen/block_card_component.rb` + `.html.erb`, `block_tile_component.rb`, `section_card_component.rb` + `.html.erb`, `section_lanes_component.rb`, `section_group_component.rb`, `page_settings_form_component.rb` + `.html.erb`, `post_form_component.rb` + `.html.erb`, `header_component.rb` + `.html.erb`, `app/components/admin/columns/rich_text_column_component.html.erb`, `app/javascript/controllers/admin/rich_text/editor_controller.js`, `app/views/admin/pages/show.html.erb`, `app/views/admin/posts/show.html.erb`, `app/controllers/admin/editing_controller.rb`, `app/controllers/admin/content_blocks_controller.rb`, `config/locales/admin/editor_screen.en.yml`, `app/assets/tailwind/application.css`, existing component tests of the touched components, `test/integration/admin/editing_test.rb`

**Interfaces:**
- Consumes: `Editing::Holds` (Task 6), `Editing.key`, `PersonName.of`, `PersonName.initials`, `Admin::Ui::AvatarComponent`, `Admin::Ui::ButtonComponent`.
- Produces: every component that draws a block or a record's form takes `holds:` (an `Editing::Holds`; nil means "ask once yourself": `Editing::Holds.on(page, viewer: Current.user, tab: Current.editing_tab)`), and hands the same object down: `BlockCardComponent`, `BlockTileComponent`, `SectionCardComponent` (and `.for`), `SectionLanesComponent`, `SectionGroupComponent`, `PageSettingsFormComponent`, `PostFormComponent`; `HeaderComponent` takes `hold_strip:` (a component or nil) and draws it inside `#editor-notice`.
- Produces: `Admin::EditorScreen::HoldStripComponent.new(subject:, hold:, viewer:, own: false, kind: :held)` and `.slot_id(subject)` → `"block-12-hold"`, `"page-hold"`, or `"editor-notice"` for a post. Kinds: `:held` (handoff 1, 13, 18), `:lost` (handoff 14), `:deleted` (handoff 15; `hold` is nil and `actor:` the user who deleted, or nil). Every strip carries `data-admin--editing--hold-target="strip"`, `data-editing-subject`, `data-editing-kind`; a `:held` strip also `data-editing-expires-in` (milliseconds until the hold lapses, from `hold.changed_at + Editing::HOLD`), `data-editing-taken-text` (notice (a)'s sentence) and `data-editing-announce` (handoff 19's sentence).
- Produces: `Admin::EditorScreen::HeldFields.call(html)` → the same markup with every text control `readonly` and every other control `disabled`.
- Produces: a held unit's markup: no `admin--saving--autosave` on its form, `data-editing-held="true"` on the unit, the fieldset's class `admin-held`, the card's border `border-line-strong`, a "Take over" item in the card's menu, and the rich-text field with no toolbar and `data-admin--rich-text--editor-read-only-value="true"`.
- The strip's slot element is ALWAYS rendered (empty unless held): `<div id="block-12-hold" data-editing-strip-slot></div>` between a card's header row and its body, `<div id="page-hold" …>` at the top of the settings panel; for a post the slot is the header's `#editor-notice`.

- [ ] **Step 1: Write the failing component tests.** `hold_strip_component_test.rb` (render with `render_inline`; `@dana` named "Dana Weiss", `@olga` "Olga Braun"), one test per line of the handoff:

```ruby
test "a block someone else holds: their avatar, the sentence in 13px ink, Take over, on the sunken strip (handoff 1, 2)" do
  render_inline Admin::EditorScreen::HoldStripComponent.new(subject: @block, hold: hold_by(@dana), viewer: @olga)

  assert_selector "div.bg-sunken.border-b.border-line.flex.items-center.gap-2[data-admin--editing--hold-target=strip][data-editing-subject='block-#{@block.id}'][data-editing-kind=held]"
  assert_selector "span.size-6[aria-hidden=true]", text: "DW"
  assert_selector "p.text-ink", text: "Dana Weiss is editing this block"
  assert_selector "button[data-action='admin--editing--hold#takeOver']", text: "Take over"
  assert_no_selector "[role=alert]"
end
```

and: "a post: 'is editing this post'"; "the page settings: 'is editing these settings'"; "one's own other tab: the own avatar (`bg-ink text-paper`) and 'You're editing this in another tab' (handoff 18)"; "the strip says in how many milliseconds the hold lapses, never less than 0" (`data-editing-expires-in` within 1000 of `Editing::HOLD.in_milliseconds - 30_000` for a hold 30 seconds old); "it carries the sentences the script shows later: 'Taken over by Dana Weiss' and 'Dana Weiss took over this block' (handoff 13, 19)"; "lost: the warn alert, role alert, 'Dana Weiss is editing this block. Your changes weren't saved.', Copy my text and Discard (handoff 14, 20)" (`div.bg-warn-tint.text-warn-ink.border.border-warn[role=alert]`, the two buttons with `admin--editing--hold#copy` and `#discard`, a `[role=status]` for "Copied"); "lost, when the hold has lapsed meanwhile: 'Someone else changed this block. Your changes weren't saved.'" (`hold: nil`); "deleted: 'Dana Weiss deleted this block. Your changes weren't saved.', Copy my text and Remove (handoff 15)"; "deleted by nobody we can name: 'This block was deleted. …'"; "a name is text, whatever was typed as one" (a user named `<b>x</b>`); "no colour literal and no lock icon (handoff 5)".

`held_fields_test.rb`:

```ruby
test "text controls are readonly, the rest is disabled, hidden fields and values are untouched" do
  html = %(<input type="hidden" name="base_updated_at" value="t"><input type="text" name="a" value="x &amp; y"><textarea name="b">text</textarea>
           <select name="c"><option selected>one</option></select><input type="checkbox" name="d" checked><button type="button">Choose</button>)

  page = Capybara.string(Admin::EditorScreen::HeldFields.call(html))

  assert page.has_css?("input[name=a][readonly][value='x & y']:not([disabled])")
  assert page.has_css?("textarea[name=b][readonly]", text: "text")
  assert page.has_css?("select[name=c][disabled]") && page.has_css?("input[name=d][disabled][checked]") && page.has_css?("button[disabled]")
  assert page.has_css?("input[type=hidden][name=base_updated_at]:not([readonly]):not([disabled])", visible: :all)
end
```

In the block card's, the section card's, the settings form's and the post form's component tests add, for each: "held by someone else: the strip is in its slot, the unit says held, the form has no autosave controller, every control is readonly or disabled and holds the same name and value as the editable form's" (render both, compare `[name, value]` of every `input, textarea, select`), "held by the viewer in this tab: drawn as ever" and "held by nobody: the slot is there and empty". For the block card also: "the card's border is line-strong and its menu has Take over (handoff 2, 3)", "the rich-text field has no toolbar and says read-only (handoff 7)". For the tile and the section: "a held block in a section: its panel is read-only and its tile carries the avatar" stays for Task 12's slot; here assert the panel only. **Review Focus 4.** In `test/integration/admin/editing_test.rb`: "the fetched card is editable for the tab that holds it and read-only for everyone else, the holder's other tab included" (three GETs of the block with the header `X-Notes-Tab` set to the holder's tab, to another tab of the holder, and for another user); "the list costs the same statements with a hold on every block, for 3 blocks as for 30".

Run `PGGSSENCMODE=disable bin/rails test test/components/admin/editor_screen test/integration/admin/editing_test.rb`. Expected: the new tests fail.

- [ ] **Step 2: The strip.**

```ruby
# app/components/admin/editor_screen/hold_strip_component.rb
module Admin
  module EditorScreen
    # What stands between a card's header and its form while someone else is
    # changing the block (live-editing handoff 1, 13 to 20), and the two
    # notices that take its place: `:lost` (the viewer's own save or claim was
    # refused: a tie, or a tab that woke after a take-over) and `:deleted`
    # (the block was deleted under unsaved text). For the page settings it
    # stands at the top of the panel, for a post in the header's notice area.
    #
    # EVERY SENTENCE the hold script shows later is rendered here, so the
    # script holds no wording: "Taken over by ..." (shown for
    # `Editing::NOTICE` in the tab the block was taken from) and the polite
    # announcement of a change of holder.
    #
    # A name is drawn as text (`PersonName.of`), never as markup.
    class HoldStripComponent < AdminComponent
      KINDS = %i[held lost deleted].freeze

      def self.slot_id(subject)
        case subject
        when ::ContentBlock then "block-#{subject.id}-hold"
        when ::Page then "page-hold"
        else "editor-notice"
        end
      end

      def initialize(subject:, hold:, viewer:, own: false, kind: :held, actor: nil)
        raise ArgumentError, "unknown hold strip kind #{kind.inspect}" unless KINDS.include?(kind)

        @subject = subject
        @hold = hold
        @viewer = viewer
        @own = own
        @kind = kind
        @actor = actor
      end

      def render? = @kind != :held || @hold.present?

      def held? = @kind == :held

      def own? = @own

      def person = @kind == :deleted ? @actor : @hold&.user

      def name = person && ::PersonName.of(person)

      def initials = ::PersonName.initials(name.to_s)

      # "block", "post" or "settings": the three things that can be held.
      def noun
        case @subject
        when ::ContentBlock then "block"
        when ::Post then "post"
        else "settings"
        end
      end

      def sentence
        return t(".own_tab") if held? && own?
        return t(".#{@kind}.#{noun}", name: name) if name

        t(".#{@kind}_unknown.#{noun}")
      end

      def expires_in = [ ((@hold.changed_at + ::Editing::HOLD - Time.current) * 1000).ceil, 0 ].max

      def strip_data
        data = { "admin--editing--hold-target": "strip", editing_subject: ::Editing.key(@subject), editing_kind: @kind }
        return data unless held?

        data.merge(editing_expires_in: expires_in, editing_holder: @hold.user_id,
          editing_taken_text: t(".taken.#{noun}", name: name), editing_announce: t(".announce.#{noun}", name: name))
      end

      def last_action = @kind == :lost ? [ t(".discard"), "admin--editing--hold#discard" ] : [ t(".remove"), "admin--editing--hold#remove" ]
    end
  end
end
```

```erb
<%# app/components/admin/editor_screen/hold_strip_component.html.erb %>
<% if held? %>
  <%# Handoff 1 and 18: the strip. Neutral, never an alert: nothing is wrong. %>
  <%= tag.div class: "flex items-center gap-2 border-b border-line bg-sunken px-3.5 py-2", data: strip_data do %>
    <%= render Admin::Ui::AvatarComponent.new(initials: initials, size: :md, tone: own? ? :own : :other) %>
    <p class="min-w-0 flex-1 text-[13px] text-ink" data-editing-strip-text><%= sentence %></p>
    <%= render Admin::Ui::ButtonComponent.new(label: t(".take_over"), size: :small,
          data: { action: "admin--editing--hold#takeOver", editing_subject: ::Editing.key(@subject) }) %>
  <% end %>
<% else %>
  <%# Handoff 14, 15 and 20: lost work is announced at once. Warn, never danger. %>
  <%= tag.div role: "alert", class: "flex flex-wrap items-center gap-2 border border-warn bg-warn-tint px-3.5 py-2 text-[13px] text-warn-ink", data: strip_data do %>
    <p class="min-w-0 flex-1"><%= sentence %></p>
    <span role="status" class="shrink-0" data-editing-copied data-copied="<%= t(".copied") %>" data-copy-failed="<%= t(".copy_failed") %>"></span>
    <%= render Admin::Ui::ButtonComponent.new(label: t(".copy"), size: :small,
          data: { action: "admin--editing--hold#copy", editing_subject: ::Editing.key(@subject) }) %>
    <%= render Admin::Ui::ButtonComponent.new(label: last_action.first, variant: :ghost, size: :small,
          data: { action: last_action.last, editing_subject: ::Editing.key(@subject) }) %>
  <% end %>
<% end %>
```

Check `Admin::Ui::ButtonComponent`'s options before writing the template: "the shared small default button" is its default variant at `size: :small` (read the component; if its default variant has a name, pass it), and "small ghost" is `variant: :ghost, size: :small` as the block card's Close button uses. `config/locales/admin/editor_screen.en.yml`, under `admin.components.editor_screen.hold_strip`:

```yaml
        hold_strip:
          take_over: "Take over"
          own_tab: "You're editing this in another tab"
          copy: "Copy my text"
          copied: "Copied"
          copy_failed: "Couldn't copy. Select the text and copy it yourself."
          discard: "Discard"
          remove: "Remove"
          held:
            block: "%{name} is editing this block"
            post: "%{name} is editing this post"
            settings: "%{name} is editing these settings"
          taken:
            block: "Taken over by %{name} · just now"
            post: "Taken over by %{name} · just now"
            settings: "Taken over by %{name} · just now"
          announce:
            block: "%{name} took over this block"
            post: "%{name} took over this post"
            settings: "%{name} took over these settings"
          lost:
            block: "%{name} is editing this block. Your changes weren't saved."
            post: "%{name} is editing this post. Your changes weren't saved."
            settings: "%{name} is editing these settings. Your changes weren't saved."
          lost_unknown:
            block: "Someone else changed this block. Your changes weren't saved."
            post: "Someone else changed this post. Your changes weren't saved."
            settings: "Someone else changed these settings. Your changes weren't saved."
          deleted:
            block: "%{name} deleted this block. Your changes weren't saved."
          deleted_unknown:
            block: "This block was deleted. Your changes weren't saved."
```

- [ ] **Step 3: The read-only fields.**

```ruby
# app/components/admin/editor_screen/held_fields.rb
module Admin
  module EditorScreen
    # Makes the fields of a form someone else holds read-only (live-editing
    # spec §4.3, handoff 6): a text control is `readonly`, so its text stays
    # selectable and at full contrast, and a control HTML cannot make
    # read-only (a select, a checkbox, a radio, a file input, a button) is
    # `disabled`. Hidden fields are left alone.
    #
    # ONE PASS OVER THE RENDERED FORM, here, rather than a read-only option on
    # each of the eight components that draw a field: a field component added
    # later is covered the day it is rendered in an editor, and the editable
    # and the held form cannot drift apart (the component tests compare every
    # control's name and value). The browser's counterpart, for the one form
    # that turns read-only in place, is `editing/freeze.js`: the same two
    # lists.
    module HeldFields
      TEXT = "input:not([type=hidden]):not([type=checkbox]):not([type=radio]):not([type=file]):not([type=button]):not([type=submit]), textarea".freeze
      OTHER = "select, input[type=checkbox], input[type=radio], input[type=file], button".freeze

      module_function

      def call(html)
        fragment = Nokogiri::HTML5.fragment(html.to_s)
        fragment.css(TEXT).each { |field| field["readonly"] = "readonly" }
        fragment.css(OTHER).each { |field| field["disabled"] = "disabled" }
        fragment.to_html.html_safe # rubocop:disable Rails/OutputSafety -- markup this app has just rendered, parsed and written out again
      end
    end
  end
end
```

(If `bin/rubocop` reports the disable comment as unneeded, remove it; if `bin/brakeman` warns, do not add an ignore: say so in the report.)

- [ ] **Step 4: The components.** In `BlockCardComponent`: `initialize` gains `holds: nil`; add

```ruby
def holds = @holds ||= ::Editing::Holds.on(page, viewer: Current.user, tab: Current.editing_tab)

# The reservation that makes this card read-only for its viewer: someone
# else's, or the viewer's own in another tab. Nil for a viewer who could not
# edit anyway: they see the view-only card, and no strip.
def hold = editable? ? holds.other(block) : nil

def held? = hold.present?

def hold_strip = Admin::EditorScreen::HoldStripComponent.new(subject: block, hold: hold, viewer: Current.user, own: hold.present? && holds.own_user?(hold))

def hold_slot_id = Admin::EditorScreen::HoldStripComponent.slot_id(block)

def form_data = editable? && !held? ? self.class.autosave_form_data(block) : {}

def fields(&content) = held? ? Admin::EditorScreen::HeldFields.call(capture(&content)) : capture(&content)
```

`wrapper_attributes` adds `editing_held: true` to `data` when `held?`; the wrapper's class uses `border-line-strong` instead of `border-line` when `held?`. In the template: directly after the header row's closing `</div>` (before the unavailable hint) `<div id="<%= hold_slot_id %>" data-editing-strip-slot><%= render hold_strip if held? %></div>`; the fieldset becomes `tag.fieldset disabled: !editable?, class: [ "contents", ("admin-view-only" unless editable?), ("admin-held" if held?) ]` and its whole content is wrapped in `<%= fields do %> … <% end %>`; the rich-text column gets `editable: editable? && !held?`; the editor's menu (the `editable?` branch) gains, when `held?`, as its first item `tag.button t(".take_over"), type: "button", class: menu_item_class, data: { action: "admin--editing--hold#takeOver", editing_subject: ::Editing.key(block) }`. `SectionCardComponent` gets the same five methods for its section and `<div id="…" data-editing-strip-slot>` between its header and its body; it hands `holds:` to its lanes and to every panel. `PageSettingsFormComponent` and `PostFormComponent` the same for the record (`holds.other(page)`); the settings panel's slot is the first element inside `<details>` after `<summary>`; the post form hands `hold_strip: (hold_strip if held?)` to `HeaderComponent`, whose template renders it inside `#editor-notice` (`<div id="editor-notice"><%= render @hold_strip if @hold_strip %></div>`, on one line so `:empty` still holds without one). `ReferenceCardComponent.options_for(…, confirmable: editable?)` becomes `confirmable: editable? && !held?` in each. With `form_only: true` (the editing fetch) `PostFormComponent` renders `<div id="editor-notice"><%= render hold_strip if held? %></div>` before its form, on one line, so the fetched answer puts a post's strip into the header's notice area and takes it away again (`mergeUnits` leaves that area alone while it shows an alert); add to `test/integration/admin/editing_test.rb` "a post's record answer carries the notice area, with the strip when someone else holds the post and empty when nobody does".

`rich_text_column_component.html.erb`: the element that carries `data-controller="admin--rich-text--editor"` gains `data-admin--rich-text--editor-read-only-value="<%= !editable? %>"`. `editor_controller.js`: `static values` gains `readOnly: Boolean`; `connect` reads `this.readOnly = this.readOnlyValue || this.element.closest("fieldset[disabled]") !== null`, and the comment there gains one sentence (a field someone else holds is read-only without a disabled fieldset); add the public method

```js
// A form that turned read-only in place (`editing/freeze`): the document
// stays as typed, for copying, and nothing more is written into it.
lock() {
  this.readOnly = true
  this.editor?.setEditable(false)
  this.element.querySelector("[role=toolbar]")?.setAttribute("hidden", "")
}
```

`application.css`, beside `.admin-view-only`: `.admin-held :is(input, textarea)[readonly], .admin-held :is(select, input, button):disabled, .admin-held .admin-rich-text-editor { @apply border-line bg-paper text-ink opacity-100; }` (handoff 6, 7; read how `.admin-view-only` is written and follow it).

- [ ] **Step 5: One read of the holds per screen.** `pages/show.html.erb`: before the header, `<% holds = Editing::Holds.on(@page, viewer: Current.user, tab: Current.editing_tab) %>`, handed to `PageSettingsFormComponent`, every `SectionCardComponent.for` and every `BlockCardComponent` of the list. `posts/show.html.erb` the same for the post form. `Admin::EditingController#blocks`, `#block` and `#record` build one and hand it to everything they render (`def holds = @holds ||= ::Editing::Holds.on(@record, viewer: Current.user, tab: Current.editing_tab)`). `Admin::ContentBlocksController`: `block_card_component`, `card_for`, `panel_component` and `tile_component` hand over one memoised `holds` the same way (after the action's write).

- [ ] **Step 6: Run** `PGGSSENCMODE=disable bin/rails test test/components test/integration test/lib`. Expected: 0 failures. Then `bin/rails tailwindcss:build && PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/sections_test.rb test/system/admin/view_only_test.rb test/system/admin/editing_merge_test.rb test/system/admin/editing_live_test.rb` (leave out a file that does not exist). Expected: 0 failures.

- [ ] **Step 7: Commit** `feat: a block, a page's settings or a post someone else holds is drawn read-only, with who holds it`.

---

### Task 8: A save is a claim, and a tab that does not hold is refused

**Files:**
- Create: `app/controllers/concerns/admin/editing_claims.rb`, `test/integration/admin/editing_claims_test.rb`
- Modify: `app/controllers/admin/editing_controller.rb`, `app/controllers/admin/pages_controller.rb`, `posts_controller.rb`, `content_blocks_controller.rb`, `app/components/admin/ui/save_status_component.rb`, `config/locales/admin/ui.en.yml`, `config/routes.rb`

**Interfaces:**
- Consumes: `Editing::Reservation.claim` / `.release` / `.holder_of`, `Editing::Rights.missing`, `Editing::Signals.holder`, `Editing.subject_of`, `Admin::EditorScreen::HoldStripComponent` (`kind: :lost`, `.slot_id`), `Current.editing_tab`.
- Produces, routes (in the `editing/:kind/:id` scope): `post "claim", to: "editing#claim", as: :editing_claim` and `post "release", to: "editing#release", as: :editing_release`. Both take an optional `block_id` (absent: the record itself). `claim` → 204 when the tab holds the subject now (or sent no tab id: nothing was claimed), **409 with the Turbo Streams below** when another tab holds it, 403 without the right, 404 out of scope or for a block that is not this page's. `release` → 204 always for someone who may edit (it deletes only the tab's own row).
- Produces, `Admin::EditingClaims` (private methods for a controller that also includes `AutosaveResponses`):
  - `claim_for(subject, record:)` → `:taken`, `:renewed`, `:refused`, or nil when nothing was claimed (no tab id, nobody signed in, or the right to save is missing: then the service's own 403 answers). Signals `holder` / `claimed` when it took.
  - `refuse_held(subject, status_id:, error_prefix:)` → renders, at 409: the status line in the new state `:held`, the `:lost` strip into `HoldStripComponent.slot_id(subject)` (`turbo_stream.update`), and the removal of `toast-<prefix>`.
  - `release_claim(subject, record:)` → deletes the tab's row and signals `holder` / `released` when it did.
- Produces: `Admin::Ui::SaveStatusComponent` state `:held` (`admin.components.ui.save_status.held`: "Not saved — someone else is editing this").
- The order in each autosave action: claim; refused → `refuse_held`; then the stale check, which releases a claim this request has just TAKEN when it refuses (a refused form saves nothing more and must not hold the block for two minutes); then the service.

- [ ] **Step 1: Write the failing request tests.** `test/integration/admin/editing_claims_test.rb` (`TAB_A = "tab-aaaaaaaa"`, `TAB_B = "tab-bbbbbbbb"`; `@page` is a draft page and `@block` an IMAGE block of it, whose `caption` a save can change; the helper is

```ruby
def autosave(block, text, tab: nil)
  patch admin_page_content_block_path(@page, block), as: :turbo_stream, headers: { "X-Notes-Tab" => tab }.compact,
    params: { base_updated_at: block.reload.updated_at.iso8601(6), block: { caption: text } }
end
```

):

```ruby
test "a save claims the block for its tab, and a save from a tab that does not hold it is refused and writes nothing" do
  sign_in_as users(:one)
  autosave(@block, "mine", tab: TAB_A)
  assert_response :ok
  assert_equal [ users(:one).id, TAB_A ], Editing::Reservation.sole.values_at(:user_id, :tab)
  events = Audit::Event.count
  stamp = @block.reload.updated_at

  sign_in_as users(:two)
  autosave(@block, "theirs", tab: TAB_B)

  assert_response :conflict
  assert_equal "mine", @block.reload.caption
  assert_equal stamp, @block.updated_at
  assert_equal events, Audit::Event.count, "a refused save is not audited"
  assert_select "turbo-stream[action=update][target='block-#{@block.id}-hold'] template [role=alert]", text: /is editing this block\. Your changes weren't saved\./
  assert_select "turbo-stream[target='block-#{@block.id}-save-status'] template", text: /Not saved/i
  assert_no_match(/base-updated-at/, response.body, "a refusal hands back no base")
end
```

and, each a test: "the holder's own other tab is refused like anyone else"; "a save with no tab id is saved and claims nothing, also while someone holds the block" (the spec's script client); "the page settings and a post are claimed and refused the same way, each by its own subject" (the settings held by A do not refuse B's block save, and the reverse); "a section's settings form is its block's"; "an expired hold is taken by the next save, and the holder signal says claimed" (`update_all(changed_at: 3.minutes.ago) # version: none (a test moves a reservation's clock)`, then assert one `holder` / `claimed` broadcast on `Editing::Signals.record_stream(@page)` with `content_block_id` and the origin); "a renewal signals nothing"; "someone without the right to edit claims nothing: the save is the service's 403 and there is no row" (`users(:reader)`); "a published page needs publish to claim" ; "a stale save by a tab that took the block with this request lets it go again, and one by the holder keeps it"; "claim: 204 and a row; 409 with the same streams when held; 403 for a reader; 404 outside the scope, for a trashed page and for another page's block"; "release deletes the tab's own row and signals released; someone else's release deletes nothing and signals nothing"; "a block moved into a section while held is still held, by the same tab" (A saves the block; B, with the right, moves it into a section through `reorder` with `moved_from`; the row is unchanged; B's GET of the block answers the panel with the strip naming A). **Review Focus 5.** "moving, adding, duplicating and deleting ignore a hold" (B's `create`, `reorder`, `duplicate`, `destroy` on a page whose blocks A holds: each succeeds; spec D4). "a write through the MCP channel holds nothing and is not refused" (`as(token, channel: :mcp) { ContentBlocks::Save.call(...) }` while held: ok, no row).

Run `PGGSSENCMODE=disable bin/rails test test/integration/admin/editing_claims_test.rb`. Expected: failures (no route, no claim).

- [ ] **Step 2: The concern.**

```ruby
# app/controllers/concerns/admin/editing_claims.rb
module Admin
  # A SAVE IS A CLAIM (live-editing spec §4.2). The three autosave actions
  # and `Admin::EditingController#claim` ask here before anything is written:
  # the request's tab takes the subject, renews it, or is refused because
  # another tab holds it live. A refusal is a 409 like a stale save's, so the
  # autosave script pauses the form the same way; nothing is written and
  # nothing audited.
  #
  # WHO CLAIMS NOTHING. A request with no tab id (a script, a client without
  # JavaScript, the MCP server) neither claims nor is refused. Someone who
  # may not save the record claims nothing either: the service answers them
  # with its 403, and a person who can only read can never hold a block
  # against the people who can edit it.
  #
  # The check and the save are not one transaction, like the stale check
  # beside it: two saves within one request's length can both pass, and the
  # stale check stays underneath.
  module EditingClaims
    extend ActiveSupport::Concern

    private

    def claim_for(subject, record:)
      tab = Current.editing_tab
      return unless tab && Current.user && ::Editing::Rights.missing(Current.actor, record).nil?

      outcome = ::Editing::Reservation.claim(subject:, record:, user: Current.user, tab:)
      ::Editing::Signals.holder(record, subject, "claimed") if outcome == :taken
      outcome
    end

    def refuse_held(subject, status_id:, error_prefix:)
      strip = Admin::EditorScreen::HoldStripComponent.new(subject:, hold: ::Editing::Reservation.holder_of(subject), viewer: Current.user, kind: :lost)
      render status: :conflict, turbo_stream: [
        turbo_stream.replace(status_id, Admin::Ui::SaveStatusComponent.new(id: status_id, state: :held, live: live_record?(subject))),
        turbo_stream.update(Admin::EditorScreen::HoldStripComponent.slot_id(subject), strip),
        turbo_stream.remove("toast-#{error_prefix}")
      ]
    end

    def release_claim(subject, record:)
      tab = Current.editing_tab
      return unless tab && Current.user

      ::Editing::Signals.holder(record, subject, "released") if ::Editing::Reservation.release(subject:, user: Current.user, tab:)
    end
  end
end
```

`SaveStatusComponent`: `:held` joins `STATES` and its `case` (`when :held then t(".held")`), styled as `:stale` is; `ui.en.yml` gains `held`. In the three autosave actions, `include EditingClaims` and replace the first line. `Admin::ContentBlocksController#update`:

```ruby
ids = { status_id: Admin::EditorScreen::BlockCardComponent.status_id(block), error_prefix: Admin::EditorScreen::BlockCardComponent.error_prefix(block) }
claim = claim_for(block, record: @page)
return refuse_held(block, **ids) if claim == :refused
if refuse_stale_autosave(block, **ids, reload_url: admin_page_path(@page, **admin_url_options))
  release_claim(block, record: @page) if claim == :taken
  return
end
```

`Admin::PagesController#update` the same with `@page`, `record: @page`, `status_id: "page-save-status", error_prefix: "page"`; `Admin::PostsController#update` with `@post` and `"post-save-status"`, `"post"`. `release_claim` after a render writes no second response: it only deletes and signals.

- [ ] **Step 3: The two actions.** In `Admin::EditingController` (`include AutosaveResponses` and `include EditingClaims`):

```ruby
# The tab claims a subject ahead of its first save (spec §4.2): sent through
# the write queue when a clean form gets its first change.
def claim
  subject = subject!
  return forbidden! if ::Editing::Rights.missing(Current.actor, @record)
  return refuse_held(subject, **status_ids(subject)) if claim_for(subject, record: @record) == :refused

  head :no_content
end

# The tab lets go: a block's form was closed, or the page was left.
def release
  subject = subject!
  return forbidden! if ::Editing::Rights.missing(Current.actor, @record)

  release_claim(subject, record: @record)
  head :no_content
end
```

with, private:

```ruby
# The block `block_id` names, or the record itself; a block that is not this
# record's is not found. (A full `def`: `or raise` after an endless one would
# bind to the definition, not to its body.)
def subject!
  ::Editing.subject_of(@record, params[:block_id]) or raise ActiveRecord::RecordNotFound
end

def status_ids(subject)
  case subject
  when ContentBlock then { status_id: Admin::EditorScreen::BlockCardComponent.status_id(subject), error_prefix: Admin::EditorScreen::BlockCardComponent.error_prefix(subject) }
  when Page then { status_id: "page-save-status", error_prefix: "page" }
  else { status_id: "post-save-status", error_prefix: "post" }
  end
end
```

Add the two routes. The `Cache-Control` filter stays for all actions.

- [ ] **Step 4: Run** Step 1's command (0 failures), then `PGGSSENCMODE=disable bin/rails test test/integration test/services test/lib test/models`. Expected: 0 failures: no existing test sends a tab header, so none claims.

- [ ] **Step 5: Commit** `feat: a save claims what it changes, and a tab that does not hold it is refused before anything is written`.

---

### Task 9: The hold script

**Files:**
- Create: `app/javascript/controllers/admin/editing/hold_controller.js`, `app/javascript/editing/freeze.js`, `test/system/admin/editing_holds_test.rb`
- Modify: `app/javascript/controllers/admin/saving/autosave_controller.js`, `app/javascript/controllers/admin/editor/blocks_controller.js` (`toggle`), `app/javascript/controllers/admin/editor/section_controller.js` (`close`), `app/components/admin/editor_screen/live_region_component.rb`, `app/controllers/admin/editing_controller.rb` (`block_gone`), `test/integration/admin/editing_test.rb`

**Interfaces:**
- Consumes: the claim and release routes (Task 8); the strip's attributes (Task 7); `enqueue`, `drained` from `saving/queue`; `post`, `get` from `editing/requests`; the live script's events `admin--editing--live:deleted` and its listener for `admin--editing--hold:refresh` (Task 5).
- Produces, from `admin--saving--autosave`: the bubbling event `admin--saving--autosave:dirty` (`detail: { subject }`, the `data-editing-subject` of the form's unit) when a form that is clean, idle and unchanged gets a change; the method `pause()` (ends the form's saves as a 409 does: `paused`, `failed`, no timer).
- Produces: `admin--editor--section:closed` (`detail: { blockId }`) from `close`, after `sendNow(panel)`; `admin--editor--blocks:toggled` (`detail: { blockId, hidden }`) from `toggle`.
- Produces: the region carries `admin--editing--hold` beside `admin--editing--live`, with the values `claim-url`, `release-url`, `block-url` (the same template as the live script's), `hold` (`Editing::HOLD.in_milliseconds`), `pass-over` (`Editing::PASS_OVER.in_milliseconds`), `notice` (`Editing::NOTICE.in_milliseconds`). Task 11 adds `take-over-url` and `hand-over-url`.
- Produces, from `editing/freeze`: `freeze(form, { lock })` makes every text control `readOnly`, disables the rest, calls `lock(element)` for each rich-text editor element and marks the form `data-editing-frozen="true"`.
- Produces: `GET …/blocks/:block_id` for a deleted block answers 410 **with the `:deleted` strip as its body**, naming who deleted it when the page's own `block.deleted` event says so.
- `admin--editing--hold` keeps `held`, a Map of subject → the time this tab last claimed it; Task 11 reads it.

- [ ] **Step 1: Write the failing system tests.** `test/system/admin/editing_holds_test.rb`, with `editing_live_test.rb`'s setup and helpers (`open_page`, `join`, `card`, `type_in`), plus:

```ruby
def expire(subject = @block)
  Editing::Reservation.of(subject).update_all(changed_at: 3.minutes.ago) # version: none (a system test moves a reservation's clock)
end

def held_by(user, subject = @block) = Editing::Reservation.holder_of(subject)&.user_id == user.id

test "typing in a block makes it read-only for the colleague, with who holds it, and closing or leaving frees it" do
  join(:dana, @dana)
  open_page
  type_in(@block, "Prices")
  assert_writes_settled
  assert held_by(@me)

  using_session(:dana) do
    assert_selector "#{card(@block)}[data-editing-held=true] [data-editing-kind=held]", text: "Olga Braun is editing this block", wait: LIVE
    assert_no_selector "#{card(@block)} form[data-controller~='admin--saving--autosave']"
    assert_no_selector "#{card(@block)} [role=toolbar]"
    assert_selector "#{card(@block)} .ProseMirror[contenteditable=false]", text: "Prices"
  end

  visit "/cs-studio/pages"
  using_session(:dana) do
    assert_no_selector "#{card(@block)}[data-editing-held]", wait: LIVE
    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave']"
  end
  assert_not held_by(@me)
end
```

and, each a test in that style:

  - "the claim is sent through the write queue, ahead of the block's first save" (a pass-through `window.fetch` wrapper records method and path of every request; after typing and `assert_writes_settled`: the POST to `/claim` comes before the PATCH, and exactly one claim was sent for three bursts of typing).
  - "reading reserves nothing: opening, focusing and leaving a field without a change sends no claim" (spec D2).
  - "closing a block's form in a section releases it, after its last save" (the recorded order is PATCH, then POST `/release`; the colleague's tile loses its strip).
  - "collapsing a card releases it".
  - "an expired hold frees the colleague's card without anyone doing anything" (`expire`; on the colleague's `#editing` the strip's `data-editing-expires-in` is rewritten to `200` through `page.execute_script`, as the presence tests shorten a value; the card becomes editable).
  - "when a hold lapsed and the colleague changed the block, my open form shows their text" (spec D3: `expire`, the colleague types and saves; my card shows it and is read-only, held by them).
  - "a tie: my claim loses, my text stays in read-only fields with the notice, Copy my text copies it and Discard shows the block as it is" (my `window.fetch` is stubbed so that ONLY the POST to `/claim` is held and every other request passes through; I type; `Editing::Reservation.claim(subject: @block, record: @page, user: @dana, tab: "tab-dddddddd")`; release the held request; `assert_selector "#{card(@block)} [role=alert]", text: "Dana Weiss is editing this block. Your changes weren't saved."`; the editor is `contenteditable=false` and still holds my text; no PATCH was sent; grant the clipboard permission the way `test/system/admin/tokens_test.rb` or the clipboard tests do and assert `navigator.clipboard.readText()` holds my text and the status says "Copied"; press Discard: the card is the server's, with the strip naming Dana, and no leave prompt is owed (`assert_writes_settled`)).
  - "a save refused because the hold lapsed and was taken keeps the text, read-only, with the notice" (I hold the block; my `window.fetch` holds ONLY my next PATCH of this block; I type; `expire`; the colleague claims through the model; release the PATCH: 409, the notice, my text kept, and the block's row unchanged). **Review Focus 3.**
  - "a block deleted under my unsaved text: the notice names who deleted it, Copy my text works and Remove takes the card away" (debounce raised; `as(@dana) { ContentBlocks::Destroy.call(@block) }`; `[role=alert]` "Dana Weiss deleted this block. Your changes weren't saved."; Remove; the card is gone and `assert_writes_settled`).
  - "my own second tab is someone else: 'You're editing this in another tab'" (a second session signed in as `@me`; the strip has the own avatar; nothing in the header changed).
  - "reloading the editor frees what this tab held, and the block is editable again without a click" (type, settle, `visit current_path`-style full reload with `page.driver.browser.refresh` or the suite's way; `await_notes_live`; `assert_no_selector "[data-editing-kind=held]", wait: LIVE`; type again and settle; the text is saved). **Review Focus 1.**
  - "Back to an editor after a Turbo visit away shows no strip of my own" (type, settle, `click_frame_link` to another page of the tree, `page.go_back`, `await_notes_live`; no held strip; the block saves).
  - "a reader's editor claims nothing and shows who is editing" (`users(:reader)` in the second session sees the strip without "Take over"; see Step 4).
  - "the settings form and a post are held like a block" (one test each: the strip at the top of the settings panel; for a post, in `#editor-notice`, and the post form read-only).
  - "a held page's blocks can still be added, moved and deleted by the colleague" (spec D4; the colleague's move of the held block succeeds and my form keeps my text).
  - "leaving the editor with a held block asks nothing and loses nothing" (the leave guard is not raised by a reservation).

Run `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/editing_holds_test.rb`. Expected: failures (nothing claims before the first save; no strip actions).

- [ ] **Step 2: The autosave script's two additions, and the two events.** In `autosave_controller.js`:

```js
  // THE FIRST CHANGE OF A CLEAN FORM (live-editing spec §4.2): said once per
  // burst of typing, before the debounce is even started, so whoever claims
  // the record for this tab (`admin--editing--hold`) queues its claim ahead
  // of the save. A form with a save pending or on the wire has said it.
  announce() {
    if (this.timer || this.busy || this.pending || this.unchanged()) return
    this.dispatch("dirty", { detail: { subject: this.element.closest("[data-editing-subject]")?.dataset.editingSubject } })
  }

  // Ends this form's saves as a 409 does, without a request: its claim was
  // refused before it had sent anything. The text stays in the fields.
  pause() {
    this.paused = true
    this.failed = true
    this.pending = false
    if (this.timer) clearTimeout(this.timer)
    if (this.retryTimer) clearTimeout(this.retryTimer)
    this.timer = this.retryTimer = null
  }
```

and call `this.announce()` as the first statement after the `paused` guard in `queue()` and in `saveNow()`. In `section_controller.js#close`, after `this.sendNow(panel)`: `this.dispatch("closed", { detail: { blockId: id } })`. In `blocks_controller.js#toggle`, when `hidden !== undefined`: `this.dispatch("toggled", { detail: { blockId: this.cardFor(event)?.dataset.blockId, hidden } })`.

- [ ] **Step 3: The modules.**

```js
// app/javascript/editing/freeze.js
//
// Makes a form read-only IN PLACE (live-editing spec §4.3): the one form that
// is not rendered read-only by the server is one that holds unsaved text when
// its claim or its save is refused. Its text stays where it was typed, to be
// copied. The same two lists as `Admin::EditorScreen::HeldFields` on the
// server: a text control is `readOnly` (selectable, full contrast), anything
// HTML cannot make read-only is disabled. `lock(element)` is called for each
// rich-text editor: the caller knows its controller.
const TEXT = "input:not([type=hidden]):not([type=checkbox]):not([type=radio]):not([type=file]):not([type=button]):not([type=submit]), textarea"
const OTHER = "select, input[type=checkbox], input[type=radio], input[type=file], button"

export function freeze(form, { lock = () => {} } = {}) {
  if (!form || form.dataset.editingFrozen === "true") return
  form.dataset.editingFrozen = "true"
  form.querySelector("fieldset")?.classList.add("admin-held")
  for (const field of form.querySelectorAll(TEXT)) field.readOnly = true
  for (const field of form.querySelectorAll(OTHER)) field.disabled = true
  for (const editor of form.querySelectorAll("[data-controller~='admin--rich-text--editor']")) lock(editor)
}

// What the person typed, as plain text, field by field: for "Copy my text".
export function textOf(form) {
  const fields = [ ...form.querySelectorAll(`${TEXT}, .admin-rich-text-editor .ProseMirror`) ]
  return fields.map((field) => ("value" in field ? field.value : field.innerText).trim()).filter(Boolean).join("\n\n")
}
```

```js
// app/javascript/controllers/admin/editing/hold_controller.js
import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { enqueue } from "saving/queue"
import { get, post } from "editing/requests"
import { freeze, textOf } from "editing/freeze"

// THE TAB'S SIDE OF A RESERVATION (live-editing spec §4.2 to §4.4). One per
// editor, on the element `Admin::EditorScreen::LiveRegionComponent` renders;
// it hears the forms of the screen through events and owns no form.
//
// - CLAIMS a subject when a clean form gets its first change
//   (`admin--saving--autosave:dirty`), through the write queue, so the claim
//   is answered before that form's save is sent. A save renews the hold on
//   the server, so a subject claimed less than half a hold ago is not
//   claimed again.
// - RELEASES it when a block's form is closed (a section's panel, a collapsed
//   card) and when the editor is left, through the queue and so after the
//   form's last save. At `pagehide` nothing can wait for a queue: that one
//   release is a `fetch` with `keepalive`.
// - A REFUSED CLAIM OR SAVE (a 409 whose streams put the `lost` notice into
//   the card) turns that form read-only in place and pauses its autosave:
//   the text stays to be copied. "Discard" asks the live script for the card
//   as the server has it; "Remove" takes a deleted block's card away.
// - A STRIP THAT SAYS SOMEONE ELSE HOLDS a subject says in how long the hold
//   lapses (`data-editing-expires-in`, from the server's `Editing::HOLD`). A
//   renewal sends no signal, and neither does a lapse, so at that time the
//   part is asked for again: it comes back editable, or with a new time.
//
// It holds no wording and no address: every sentence is in the markup the
// server rendered and every URL is a value.
export default class extends Controller {
  static targets = [ "strip" ]
  static values = { claimUrl: String, releaseUrl: String, blockUrl: String, hold: Number, passOver: Number, notice: Number }

  connect() {
    this.held = new Map()
    this.timers = new Map()
    this.listeners = [
      [ "admin--saving--autosave:dirty", (event) => this.claim(event.detail.subject) ],
      [ "admin--editor--section:closed", (event) => this.release(`block-${event.detail.blockId}`) ],
      [ "admin--editor--blocks:toggled", (event) => { if (event.detail.hidden) this.release(`block-${event.detail.blockId}`) } ],
      [ "admin--editing--live:deleted", (event) => this.deleted(event.detail) ]
    ]
    this.listeners.forEach(([ name, act ]) => this.element.addEventListener(name, act))
    this.leaving = () => this.letGo()
    window.addEventListener("pagehide", this.leaving)
  }

  // A Turbo visit away: what this tab holds is released behind the saves the
  // visit waited for. A task queued here outlives its page and is still sent.
  disconnect() {
    this.listeners.forEach(([ name, act ]) => this.element.removeEventListener(name, act))
    window.removeEventListener("pagehide", this.leaving)
    this.timers.forEach(clearTimeout)
    ;[ ...this.held.keys() ].forEach((subject) => this.release(subject))
  }

  params(subject) { return subject === "record" ? {} : { block_id: subject.slice("block-".length) } }

  claim(subject) {
    if (!subject || !this.hasClaimUrlValue) return
    const last = this.held.get(subject)
    if (last && Date.now() - last < this.holdValue / 2) return
    this.held.set(subject, Date.now())
    enqueue(async () => {
      const answer = await post(this.claimUrlValue, this.params(subject))
      if (answer.status === 204) return
      this.held.delete(subject)
      // Held by another tab: the answer's streams put the notice into the
      // card, and `stripTargetConnected` does the rest.
      if (answer.status === 409) Turbo.renderStreamMessage(answer.text)
    })
  }

  release(subject) {
    if (!this.held.delete(subject)) return
    enqueue(() => post(this.releaseUrlValue, this.params(subject)))
  }

  letGo() {
    for (const subject of this.held.keys()) post(this.releaseUrlValue, this.params(subject), { keepalive: true })
    this.held.clear()
  }

  stripTargetConnected(strip) {
    const subject = strip.dataset.editingSubject
    this.held.delete(subject)
    if (strip.dataset.editingKind !== "held") return this.lose(subject)

    const lapse = Number(strip.dataset.editingExpiresIn)
    if (Number.isFinite(lapse)) this.later(strip, () => this.dispatch("refresh", { detail: { subject } }), lapse + 250)
  }

  stripTargetDisconnected(strip) {
    clearTimeout(this.timers.get(strip))
    this.timers.delete(strip)
  }

  later(key, act, ms) {
    clearTimeout(this.timers.get(key))
    this.timers.set(key, setTimeout(() => { this.timers.delete(key); act() }, ms))
  }

  unitOf(subject) { return this.element.querySelector(`[data-editing-unit][data-editing-subject="${CSS.escape(subject)}"]`) }

  formOf(subject) {
    const unit = this.unitOf(subject)
    return unit?.matches("form") ? unit : unit?.querySelector("form[data-controller~='admin--saving--autosave']")
  }

  // This tab's text was not saved and will not be: the form stays as typed,
  // read-only, and sends nothing more.
  lose(subject) {
    const form = this.formOf(subject)
    if (!form) return
    this.application.getControllerForElementAndIdentifier(form, "admin--saving--autosave")?.pause()
    freeze(form, { lock: (editor) => this.application.getControllerForElementAndIdentifier(editor, "admin--rich-text--editor")?.lock() })
  }

  async copy(event) {
    const strip = event.currentTarget.closest("[data-editing-kind]")
    const status = strip.querySelector("[data-editing-copied]")
    const form = this.formOf(event.currentTarget.dataset.editingSubject)
    try {
      await navigator.clipboard.writeText(form ? textOf(form) : "")
      status.textContent = status.dataset.copied
    } catch {
      status.textContent = status.dataset.copyFailed
    }
  }

  // The refused text is given up: the unit may be replaced although its form
  // is not clean. For a post the notice is outside the unit and goes here.
  discard(event) {
    const subject = event.currentTarget.dataset.editingSubject
    if (subject === "record") event.currentTarget.closest("[data-editing-kind]")?.remove()
    this.dispatch("refresh", { detail: { subject, discard: true } })
  }

  // A deleted block's card, its tile and its panel go.
  remove(event) {
    const id = event.currentTarget.dataset.editingSubject.slice("block-".length)
    this.element.querySelectorAll(`#content_block_${CSS.escape(id)}, #block-${CSS.escape(id)}-panel`).forEach((each) => each.remove())
  }

  // A block was deleted while its form holds unsaved text (the list merge
  // kept its unit): the server words the notice, with who deleted it.
  async deleted({ blockId, unit }) {
    const answer = await get(this.blockUrlValue.replace(":block_id", blockId))
    const slot = unit.querySelector("[data-editing-strip-slot]") || document.getElementById(`block-${blockId}-hold`)
    if (answer.status !== 410 || !slot || !answer.text) return
    slot.replaceChildren(...new DOMParser().parseFromString(answer.text, "text/html").body.children)
  }
}
```

`LiveRegionComponent#region_data`: `controller: "admin--editing--live admin--editing--hold"` and the six values of the Interfaces block, the two URLs from `helpers.admin_editing_claim_path(**route)` and `admin_editing_release_path(**route)`. `Admin::EditingController#block_gone` renders the notice instead of `head :gone`:

```ruby
render Admin::EditorScreen::HoldStripComponent.new(subject: ContentBlock.new(id: params[:block_id].to_i), hold: nil, viewer: Current.user,
  kind: :deleted, actor: deleted.user), status: :gone, layout: false
```

and `test/integration/admin/editing_test.rb`'s "a block deleted since is gone, not missing" also asserts the body: "… deleted this block. Your changes weren't saved." with the deleter's name, and "This block was deleted." when the block went with its section (no event of its own: build that case and expect a 404, since nothing names its page; the script then shows no notice and the card keeps its text and its `data-editing-gone` mark. Say in the report that a block deleted WITH ITS SECTION has no notice (c), and list it under "Design questions").

- [ ] **Step 4: A reader sees who is editing.** In the four components of Task 7, `hold` answered nil for a viewer who cannot edit. Change it to `holds.other(subject)` for everyone, keep the fields as `editable?` decides, and give `HoldStripComponent` `take_over: true` (the components pass `take_over: editable?`), which leaves the button out; the card's menu item stays inside the `editable?` branch. Update the component tests ("a reader sees the strip without Take over").

- [ ] **Step 5: Run** Step 1's command (0 failures), then the unit suite `PGGSSENCMODE=disable bin/rails test`, then `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/editing_live_test.rb test/system/admin/editing_merge_test.rb test/system/admin/sections_test.rb test/system/admin/save_bar_test.rb test/system/admin/notes_flow_test.rb test/system/admin/promotion_hold_test.rb`. Expected: 0 failures. A system test that counts requests of an editor and now sees a `/claim` is corrected by counting the PATCHes it meant; no promise is weakened.

- [ ] **Step 6: Commit** `feat: a tab claims what it starts to change, lets go when it is done, and keeps a refused text for copying`.

---

### Task 10: Taking over, on the server

**Files:**
- Create: `app/services/editing/take_over.rb`, `test/services/editing/take_over_test.rb`
- Modify: `app/controllers/admin/editing_controller.rb`, `config/routes.rb`, `app/models/audit/sentence.rb`, `app/queries/dashboard/feed.rb`, `app/models/editing/signals.rb` (`SILENT`), `test/models/audit/sentence_test.rb` (`DYNAMIC_SITES`), `test/services/service_behaviour_contract_test.rb` (`EXPECTED_SERVICES`), `test/support/service_calls.rb`, `test/integration/admin/editing_claims_test.rb`

**Interfaces:**
- Consumes: `Editing::Reservation.request` / `.hand_over` / `.pass_over` / `.claim` / `.of`, `Editing::Signals.holder`, `ApplicationService`.
- Produces: `Editing::TakeOver.new(subject, record:, tab:, hand_over: false, actor: Current.actor)`; `#call` → `ApplicationService::Result` (record: the subject); `#outcome` afterwards, one of:
  - `:taken`: the requester's tab holds the subject now (a pass-over); audited, signalled `taken`.
  - `:requested`: the holder's tab was asked; signalled `requested`; not audited (the transfer is).
  - `:claimed`: nobody held it live, the tab simply claimed; signalled `claimed`; not audited.
  - `:handed` (`hand_over: true`): the row passed to the requester; audited, signalled `taken`.
  - `:nothing` (`hand_over: true`): this tab did not hold it, or nobody had asked.
- Produces: the events `block.taken_over`, `page.taken_over`, `post.taken_over` on the content record, `snapshot: nil`, `metadata: { "from_user_id" => Integer, "to_user_id" => Integer, "answered" => true | false }`, never coalesced. Their sentence: "<actor> took over editing <subject>".
- Produces, routes: `post "take_over", to: "editing#take_over", as: :editing_take_over` and `post "hand_over", to: "editing#hand_over", as: :editing_hand_over`, each with the optional `block_id`; each answers `{ "state": "<outcome>" }` as JSON, 403 without the right, 404 out of scope, 422 without a tab id.

- [ ] **Step 1: Write the failing tests.** `test/services/editing/take_over_test.rb` (`A` the holder's tab, Olga's; `B` the requester's, Dana's; `take(at:)` calls the service as Dana inside `travel_to`):

```ruby
test "asking writes the request and tells the holder's tab; nothing is audited and nobody's row has moved" do
  hold_as(@olga, A)

  service = as(@dana) { Editing::TakeOver.new(@block, record: @page, tab: B) }
  assert_no_difference -> { Audit::Event.count } do
    assert service.call.ok?
  end

  assert_equal :requested, service.outcome
  assert_equal [ @olga.id, A, @dana.id, B ], Editing::Reservation.sole.values_at(:user_id, :tab, :requested_by_id, :requested_tab)
  assert_equal [ { "kind" => "holder", "content_block_id" => @block.id, "reason" => "requested" } ], signals
end

test "the hand-over passes the row, audits once on the block with both ids and no text, and tells everyone" do
  hold_as(@olga, A)
  as(@dana) { Editing::TakeOver.call(@block, record: @page, tab: B) }

  service = as(@olga) { Editing::TakeOver.new(@block, record: @page, tab: A, hand_over: true) }
  assert_difference -> { Audit::Event.where(action: "block.taken_over").count }, 1 do
    assert service.call.ok?
  end

  event = Audit::Event.where(action: "block.taken_over").last
  assert_equal :handed, service.outcome
  assert_equal [ @dana.id, B ], Editing::Reservation.sole.values_at(:user_id, :tab)
  assert_equal({ "from_user_id" => @olga.id, "to_user_id" => @dana.id, "answered" => true }, event.metadata)
  assert_equal [ "ContentBlock", @block.id, nil ], [ event.subject_type, event.subject_id, event.snapshot ]
  assert_equal "taken", signals.last["reason"]
  assert_equal @block.reload.updated_at, @stamp, "a take-over wrote the block"
end
```

and: "asked again before the pass-over time it is still a request, with its first time kept; at the pass-over time the row is the requester's, with the same event marked as not answered"; "an expired hold is simply claimed: no request, no event"; "a subject nobody holds is claimed"; "taking over from one's own other tab works the same"; "anyone who may save it may take it back"; "a hand-over from a tab that does not hold it, or with nobody asking, does nothing and audits nothing"; "without the right it is denied, with one access.denied, and the row is untouched" (`users(:reader)`; on a published page, someone with `edit` and without `publish`); "a holder who has lost the right cannot hand over, and the requester gets the block after the pass-over time" (Olga holds; remove her from her editing group the way `test/services/pages/save_test.rb` builds such a user; Dana asks; Olga's hand-over is denied and the row is still Olga's; `travel Editing::PASS_OVER + 1` and Dana's second call answers `:taken`). **Review Focus 5.** "the event names nobody and nothing: its metadata is two ids and a flag" ; "a page's settings and a post are taken over with their own event"; "a take-over is not a change: the dashboard's 'by' and 'Changed by …' skip it" (`Audit::ChangeSince.for(@block, since: 1.hour.ago, viewer: @olga)` is nil after one); "the sentence reads 'took over editing'" (in `test/models/audit/sentence_test.rb`'s own table of sentences). In `editing_claims_test.rb`: the two routes' answers (JSON states, 403, 404, 422 without the header).

Run `PGGSSENCMODE=disable bin/rails test test/services/editing test/models/audit test/services/service_behaviour_contract_test.rb test/services/service_contract_test.rb`. Expected: errors (`uninitialized constant Editing::TakeOver`).

- [ ] **Step 2: The service.**

```ruby
# app/services/editing/take_over.rb
module Editing
  # The one audited write of live editing (live-editing spec §4.4): a subject
  # passes from the tab that holds it to someone who asked for it.
  #
  # THE REQUESTER'S CALL (`hand_over: false`), in this order:
  # 1. its own request is `Editing::PASS_OVER` old and was not answered: the
  #    row is passed over, on what was saved (`answered: false`);
  # 2. another tab holds the subject live: the request is written on its row
  #    and that tab is told (`requested`). It drains its write queue and
  #    calls this service with `hand_over: true`;
  # 3. nobody holds it live: the tab simply claims.
  #
  # THE HOLDER'S CALL (`hand_over: true`) passes the row to whoever asked
  # (`answered: true`). The holder needs the right as well: someone who lost
  # it since cannot hand over, and the requester's second call takes the row.
  #
  # Each step is one statement of `Editing::Reservation`; none locks a row or
  # writes the record. The event is on the content record and holds two ids
  # and a flag: no name, no text, no snapshot.
  #
  # lock: none (a reservation's statements are atomic by its unique index, and no content row is written)
  class TakeOver < ApplicationService
    PREFIX = { "ContentBlock" => "block", "Page" => "page", "Post" => "post" }.freeze

    attr_reader :outcome

    def initialize(subject, record:, tab:, hand_over: false, actor: Current.actor)
      @subject = subject
      @record = record
      @tab = tab.to_s[Live::Signals::TAB]
      @hand_over = hand_over
      @actor = actor
    end

    def call
      refused = edit_keys.find { |key| !authorize!(key, @record) }
      return denied(refused, @record) if refused

      user = actor_user
      return failure(@subject, [ "Taking over needs a signed-in person and a browser tab." ]) unless user.is_a?(User) && @tab

      Reservation.transaction { @hand_over ? hand_over(user) : take(user) }
      success(@subject)
    end

    private

    def edit_keys
      prefix = AccessControl::Checker::BLOCK_OWNER_PREFIX.fetch(@record.class.name)
      [ "#{prefix}.edit", ("#{prefix}.publish" if @record.published_at.present?) ].compact
    end

    def take(user)
      before = Reservation.of(@subject).first
      if Reservation.pass_over(subject: @subject, by: user, tab: @tab)
        passed(from: before.user_id, to: user.id, answered: false, outcome: :taken)
      elsif Reservation.request(subject: @subject, by: user, tab: @tab)
        @outcome = :requested
        Signals.holder(@record, @subject, "requested")
      else
        claimed = Reservation.claim(subject: @subject, record: @record, user:, tab: @tab)
        Signals.holder(@record, @subject, "claimed") if claimed == :taken
        # Refused: someone took it between the two statements. The tab asks again.
        @outcome = claimed == :refused ? :requested : :claimed
      end
    end

    def hand_over(user)
      before = Reservation.of(@subject).first
      return @outcome = :nothing unless Reservation.hand_over(subject: @subject, user:, tab: @tab)

      passed(from: user.id, to: before.requested_by_id, answered: true, outcome: :handed)
    end

    def passed(from:, to:, answered:, outcome:)
      @outcome = outcome
      record_event("#{PREFIX.fetch(@subject.class.name)}.taken_over", subject: @subject, snapshot: nil, coalesce: false,
        metadata: { "from_user_id" => from, "to_user_id" => to, "answered" => answered })
      Signals.holder(@record, @subject, "taken")
    end
  end
end
```

(The `# lock: none` line is for a reader; `test/lib/notes_guards_test.rb` asks it only of notes services.) `Audit::Sentence`: `CONTENT_VERBS` gains `"taken_over" => [ "took over editing ", "" ]`; `CONTENT_ACTIONS`' `"page"` and `"post"` lists gain `taken_over`; `BLOCK_ACTIONS` gains `block.taken_over`; read `block_parts` and give it the verb's phrase the way `translation_confirmed` has one. `Dashboard::Feed::NOT_A_CHANGE` gains the three names (`Audit::ChangeSince` and `Editing::LastChange` read that list). `Editing::Signals::SILENT` gains the three with the reason "a take-over sends its own holder signal (Editing::TakeOver)". `test/models/audit/sentence_test.rb`: `DYNAMIC_SITES` gains `"app/services/editing/take_over.rb" => %w[page.taken_over post.taken_over block.taken_over]`, with its comment.

- [ ] **Step 3: The contract.** `EXPECTED_SERVICES` gains `Editing::TakeOver` (in the list's alphabetical place). `test/support/service_calls.rb`, `FACTORIES`:

```ruby
# A request the holder's tab did not answer in time: the call that passes the
# block over, which is the one that writes an event. The control is the
# requester, a person: a take-over has no meaning for the trusted actor.
"Editing::TakeOver" => lambda {
  page, (block,) = draft_page_with_blocks
  Editing::Reservation.claim(subject: block, record: page, user: users(:two), tab: "tab-holder-01", now: 20.seconds.ago)
  Editing::Reservation.request(subject: block, by: users(:one), tab: "tab-asker-001", now: 10.seconds.ago)
  { call: -> { Editing::TakeOver.call(block, record: page, tab: "tab-asker-001") }, permission: "pages.edit", on: page, control_actor: users(:one) }
},
```

Read the contract's two generic tests ("reports every id as not found to an actor who can read nothing", "for a reader") before running: if either needs an entry of its own for a service whose argument is a record and not an id, add what it asks for and nothing more.

- [ ] **Step 4: The two actions.**

```ruby
# Someone asks for what another tab holds (spec §4.4), or asks again after
# the pass-over time.
def take_over = transfer(hand_over: false)

# The holder's tab, having sent what it held, lets the requester have it.
def hand_over = transfer(hand_over: true)
```

private:

```ruby
def transfer(hand_over:)
  service = ::Editing::TakeOver.new(subject!, record: @record, tab: Current.editing_tab, hand_over:)
  result = service.call
  return forbidden!(result.errors.to_sentence) if result.denied?
  return head(:unprocessable_entity) unless result.ok?

  render json: { state: service.outcome }
end
```

and the two routes.

- [ ] **Step 5: Run** Step 1's command, then `PGGSSENCMODE=disable bin/rails test`. Expected: 0 failures (`test/models/editing/signals_test.rb`'s first test now needs the three `SILENT` lines, and has them).

- [ ] **Step 6: Commit** `feat: taking over a block is asked of its holder's tab, passed over after five seconds, and audited`.

---

### Task 11: Taking over, in the browser

**Files:**
- Create: `test/system/admin/editing_take_over_test.rb`
- Modify: `app/javascript/controllers/admin/editing/hold_controller.js`, `app/javascript/controllers/admin/editing/live_controller.js`, `app/components/admin/editor_screen/live_region_component.rb`, the four templates that hold a strip slot (`block_card_component.html.erb`, `section_card_component.html.erb`, `page_settings_form_component.html.erb`, `header_component.html.erb`)

**Interfaces:**
- Consumes: the take-over and hand-over routes (Task 10); the strip's `data-editing-taken-text`, `data-editing-announce`, `data-editing-holder` (Task 7); `drained` from `saving/queue`; `held` (Task 9).
- Produces: the live script dispatches `admin--editing--live:holder` (`detail: { subject, reason }`) for every `holder` signal it hears, before it fetches. The region gains the values `take-over-url` and `hand-over-url`. Beside every strip slot stands `<span class="sr-only" aria-live="polite" data-editing-announcer></span>` (handoff 19).
- Produces, in `admin--editing--hold`: the action `takeOver`; `handOver(subject)`.

- [ ] **Step 1: Write the failing system tests.** `test/system/admin/editing_take_over_test.rb`, with the helpers of `editing_holds_test.rb` and `def shorten(name, ms) = page.execute_script("document.getElementById('editing').setAttribute('data-admin--editing--hold-#{name}-value', #{ms})")`:

```ruby
test "taking over a block someone is typing in: their unsaved text arrives first, the block is mine with it, and theirs says who took it" do
  open_page
  join(:dana, @dana) do
    type_in(@block, "Saved text. ")
    assert_writes_settled
    page.execute_script("document.querySelector(#{"#{card(@block)} form".to_json}).setAttribute('data-admin--saving--autosave-debounce-value', 600000)")
    type_in(@block, "Not yet saved.")
  end
  assert_selector "#{card(@block)} [data-editing-kind=held]", text: "Dana Weiss is editing this block", wait: LIVE

  within(card(@block)) { press "Take over" }

  assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror", text: "Saved text. Not yet saved.", wait: LIVE
  assert_no_selector "#{card(@block)} [data-editing-kind=held]"
  assert_equal @me.id, Editing::Reservation.holder_of(@block).user_id
  event = Audit::Event.where(action: "block.taken_over").sole
  assert_equal({ "from_user_id" => @dana.id, "to_user_id" => @me.id, "answered" => true }, event.metadata)

  using_session(:dana) do
    assert_selector "#{card(@block)} [data-editing-strip-text]", text: "Taken over by Olga Braun", wait: LIVE
    assert_selector "#{card(@block)} [data-editing-announcer]", text: "Olga Braun took over this block", visible: :all
    assert_selector "#{card(@block)} .ProseMirror[contenteditable=false]", text: "Saved text. Not yet saved."
    assert_no_selector "#toasts [role=status], #toasts [role=alert]"
  end
end
```

and: "the notice becomes the ordinary strip after its time" (`shorten("notice", 300)` in the holder's session before the take-over; then "Olga Braun is editing this block"); "from a tab that does not answer: after the pass-over time the block is mine on what was saved" (the holder is a row made through the model with a tab no browser has; `shorten("pass-over", 300)`; press Take over; the card is editable; the event says `"answered" => false`); "a tab that wakes after it was passed over keeps its unsaved text, read-only, with the notice" (Dana's session holds ONLY its own POST to `/hand_over` in a `window.fetch` stub and has unsaved text with the debounce raised; I take over with a short pass-over time; then her debounce is put back to `50` and a key is typed: her save is refused, the `lost` notice names me, her text is in the read-only field); "taking over from my own other tab"; "Dana takes the block back"; "the card's menu has Take over and it does the same" (handoff 2; opened with `open_editor_menu`-style helper of the card's "⋯"); "a post is taken over from the header's notice area"; "the settings form is taken over from the strip at the top of its panel"; "an expired hold is simply mine at the press" (`expire` first: no event, the card editable); "a take-over raises no leave prompt and moves no base" (after it, `#block-<id>-base-updated-at` in my card equals `@block.reload.updated_at.iso8601(6)` and my next edit is saved); "a reader has no Take over".

Run `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/editing_take_over_test.rb`. Expected: failures at the press (no action `takeOver`).

- [ ] **Step 2: Build.** In `live_controller.js#heard`, after the kind check and before the `want` calls:

```js
    if (signal.kind === "holder") {
      const subject = signal.content_block_id ? `block-${signal.content_block_id}` : "record"
      this.dispatch("holder", { detail: { subject, reason: signal.reason } })
    }
```

In `hold_controller.js`: add `takeOverUrl: String, handOverUrl: String` to the values, `import { drained, enqueue } from "saving/queue"`, the listener `[ "admin--editing--live:holder", (event) => { if (event.detail.reason === "requested") this.handOver(event.detail.subject) } ]`, a `this.lost = new Set()` and `this.holders = new Map()` in `connect`, and:

```js
  // "Take over" on a strip or in a card's menu (handoff 2). The answer says
  // whether the subject is this tab's already (nobody held it, or the holder
  // was passed over) or whether its holder's tab was asked: then the block
  // arrives with that tab's hand-over (a `holder` signal the live script
  // fetches on), or this tab asks once more after the pass-over time.
  takeOver(event) {
    const subject = event.currentTarget.dataset.editingSubject
    const ask = () => enqueue(async () => {
      const answer = await post(this.takeOverUrlValue, this.params(subject))
      let state = null
      try { state = JSON.parse(answer.text).state } catch { /* not an answer of ours: a 403 page, a sign-in redirect */ }
      if (state === "taken" || state === "claimed") {
        this.held.set(subject, Date.now())
        this.dispatch("refresh", { detail: { subject } })
      } else if (state === "requested") {
        this.later(`ask:${subject}`, () => { if (this.heldByOther(subject)) ask() }, this.passOverValue + 100)
      }
    })
    ask()
  }

  heldByOther(subject) { return this.stripTargets.some((strip) => strip.dataset.editingSubject === subject && strip.dataset.editingKind === "held") }

  // Someone asked for what this tab holds: everything typed is sent first
  // (`drained` tells every form to send and waits for the queue), then the
  // subject is let go. A drain that did not end clean hands over all the
  // same: a refused text stays in its form and is refused again, with the notice.
  async handOver(subject) {
    if (!this.held.has(subject)) return
    await drained()
    enqueue(async () => {
      const answer = await post(this.handOverUrlValue, this.params(subject))
      if (answer.status !== 200) return
      this.held.delete(subject)
      this.lost.add(subject)
      this.dispatch("refresh", { detail: { subject } })
    })
  }
```

and extend `stripTargetConnected` for a `held` strip, after the lapse timer:

```js
    const holder = strip.dataset.editingHolder
    const changed = this.holders.has(subject) && this.holders.get(subject) !== holder
    this.holders.set(subject, holder)
    clearTimeout(this.timers.get(`ask:${subject}`))
    // Handoff 19: a change of holder is announced politely, on that card.
    if (changed || this.lost.has(subject)) this.announcerFor(strip)?.replaceChildren(strip.dataset.editingAnnounce)
    // Handoff 13: in the tab the subject was taken from, the strip reads
    // "Taken over by ..." for `notice`, then what it always reads.
    if (this.lost.delete(subject)) {
      const text = strip.querySelector("[data-editing-strip-text]")
      const usual = text.textContent
      text.textContent = strip.dataset.editingTakenText
      this.later(`notice:${subject}`, () => { if (text.isConnected) text.textContent = usual }, this.noticeValue)
    }
```

with `announcerFor(strip) { return strip.closest("[data-editing-strip-slot]")?.parentElement.querySelector("[data-editing-announcer]") || document.querySelector("#editor-notice ~ [data-editing-announcer]") }`, and in `stripTargetDisconnected` set `this.holders` to remember that the subject has no holder (`this.holders.set(strip.dataset.editingSubject, null)`), so the next holder is a change. Add the announcer element after each slot in the four templates (for the post, directly after `#editor-notice` in the header). `LiveRegionComponent` gains the two URL values.

- [ ] **Step 3: Run** Step 1's command (0 failures), then `PGGSSENCMODE=disable bin/rails test test/components test/lib`, then `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/editing_holds_test.rb test/system/admin/editing_live_test.rb`. Expected: 0 failures.

- [ ] **Step 4: Commit** `feat: Take over asks the holder's tab, which sends what it holds and lets go, and nothing typed is lost`.

---

### Task 12: The slot on a block, with the tile's avatar and the notes marker in it

**Files:**
- Create: `app/components/admin/editor_screen/holder_avatar_component.rb` (+ `.html.erb`), `test/components/admin/editor_screen/holder_avatar_component_test.rb`
- Modify: `app/components/admin/slots.rb`, `config/initializers/admin_slots.rb`, `app/components/admin/notes_screen/marker_component.rb`, `app/components/admin/editor_screen/block_card_component.rb` + `.html.erb`, `block_tile_component.rb` + `.html.erb`, `section_card_component.rb`, `section_lanes_component.rb`, `section_group_component.rb`, `app/views/admin/pages/show.html.erb`, `app/controllers/admin/editing_controller.rb`, `app/controllers/admin/content_blocks_controller.rb`, `config/locales/admin/editor_screen.en.yml`, `test/components/admin/slots_test.rb`, `test/lib/notes_boundary_test.rb`, the block card's and the tile's component tests

**Interfaces:**
- Consumes: `Admin::Slots`, `Admin::Ui::SlotComponent`, `Admin::Ui::TooltipComponent`, `Admin::Ui::AvatarComponent`, `Editing::Reservation`.
- Produces: the slot name `editor.block.markers`, hosted by the block card's header (where the marker stands today, in the `:list` and `:group` branches) and by the tile (in the marker's place). A component in it is built as `component.new(record: block, viewer:, data:, label: <the block's label>, placement: :card | :tile, **)` (`label:`, not `name:`, which is `SlotComponent`'s own keyword for the slot).
- Registered, in this order: `Admin::EditorScreen::HolderAvatarComponent` with `loader: HolderAvatarComponent.loader`, then `Admin::NotesScreen::MarkerComponent`.
- `HolderAvatarComponent.loader` → `->(blocks, viewer:) { { block id => Editing::Reservation } }`, ONE statement for any number of blocks (plus one for the users), live rows only. The component draws only for `placement: :tile` and only a hold that is not the viewer's in this tab: a 20px avatar (`size: :sm`; the own tone for the viewer's other tab) with the shared tooltip and accessible text "Dana Weiss is editing this block" (handoff 4). No "Take over" on the tile.
- `BlockCardComponent`, `BlockTileComponent`, `SectionCardComponent`, `SectionLanesComponent` and `SectionGroupComponent` take `markers:` (what `Admin::Slots.load("editor.block.markers", blocks, viewer:)` answered; nil: the component loads for its own block) and hand it down, beside `holds:`.
- `Admin::NotesScreen::MarkerComponent.new(record: nil, subject: record, label: nil, name: label, viewer: nil, data: nil, **)`: a slot hands it `record:` and `label:`, its other callers (`git grep -n "MarkerComponent.new" -- app`) go on passing `subject:` and `name:`; its markup is unchanged.

- [ ] **Step 1: Tests first.** `holder_avatar_component_test.rb`: nothing for `placement: :card`; nothing without a hold; nothing for the viewer's own hold in this tab (`Current.set(editing_tab: …)`); the 20px avatar with the tooltip's words for someone else; the own tone and "You're editing this in another tab" for the viewer's other tab; a name is text; the loader is the same number of statements for 3 blocks and for 30 and leaves out an expired row. `test/components/admin/slots_test.rb`: the name is known. The tile's component test: "a held block's tile carries the avatar before the notes marker, and no Take over" (**Review Focus 4**, with Task 7's panel test); the card's and the tile's: the notes marker's markup is what it was (the assertions that exist stay as they are). An integration test in `test/integration/admin/editing_test.rb`: "the page editor costs the same statements for 3 blocks as for 30 with both features on every block". `test/lib/notes_boundary_test.rb`:

```ruby
# The marker on a block is a slot's (`editor.block.markers`); what is left in
# these files is the menu's "Add note" item, a named exception above.
BLOCK_MARKER_HOSTS = %w[
  app/components/admin/editor_screen/block_card_component.rb app/components/admin/editor_screen/block_card_component.html.erb
  app/components/admin/editor_screen/block_tile_component.rb app/components/admin/editor_screen/block_tile_component.html.erb
].freeze

test "the block card and the tile draw no marker themselves: they draw the slot" do
  BLOCK_MARKER_HOSTS.each do |path|
    source = Rails.root.join(path).read
    assert_no_match(/MarkerComponent|note_marker/, source, "#{path} names a marker: it belongs to the slot editor.block.markers")
  end
  assert BLOCK_MARKER_HOSTS.select { |path| path.end_with?(".erb") }.all? { |path| Rails.root.join(path).read.include?("editor.block.markers") }
end
```

and the two `NAMED_EXCEPTIONS` reasons for these files become "the block card's Add note menu item: a slot when a second feature puts an item into a block's menu (the marker is in the slot editor.block.markers)" and the tile's likewise. `SLOT_HOSTS` and its `assert_equal 11` are not changed (see "Where the code disagrees", 3). Run: FAIL.

- [ ] **Step 2: Build.** `Admin::Slots::NAMES` gains `editor.block.markers`. The avatar:

```ruby
# app/components/admin/editor_screen/holder_avatar_component.rb
module Admin
  module EditorScreen
    # Who is changing a block, on its tile in a section (live-editing handoff
    # 4): a 20px avatar before the notes marker. A slot component
    # (`editor.block.markers`); on a card it draws nothing, the strip says it.
    class HolderAvatarComponent < AdminComponent
      # One statement for every block of a screen (and one for the users).
      def self.loader
        lambda do |blocks, viewer:|
          next {} unless viewer.is_a?(::User) && blocks.any?

          ::Editing::Reservation.live.where(subject_type: "ContentBlock", subject_id: blocks.map(&:id)).includes(:user).index_by(&:subject_id)
        end
      end

      def initialize(record:, viewer:, data: nil, placement: nil, **)
        @block = record
        @viewer = viewer
        @hold = data
        @placement = placement
      end

      def render? = @placement == :tile && @hold&.user.present? && !mine?

      def own? = @hold.user_id == @viewer&.id

      def name = ::PersonName.of(@hold.user)

      def words = own? ? t(".own_tab") : t(".held", name: name)

      private

      # The viewer's hold in this very tab is no news to them. The tab is the
      # request's: a tile is drawn for the tab that asked for it.
      def mine? = own? && Current.editing_tab.present? && @hold.tab == Current.editing_tab
    end
  end
end
```

Its template: a `span` carrying `Admin::Ui::TooltipComponent.host_data`, the avatar (`size: :sm`, `tone: own? ? :own : :other`), a `span.sr-only` with `words`, and the tooltip component with `words`, in the way `Admin::PresenceScreen::RowMarkerComponent`'s template builds its tooltip (read it and follow it). Strings: `admin.components.editor_screen.holder_avatar.held` ("%{name} is editing this block") and `.own_tab`. In the card and the tile replace `render note_marker` with `render Admin::Ui::SlotComponent.new(name: "editor.block.markers", record: block, viewer: Current.user, loaded: markers, label: label, placement: :card)` (`:tile` on the tile) and delete `note_marker`; `def markers = @markers ||= Admin::Slots.load("editor.block.markers", [ block ], viewer: Current.user)`. The three screen-level callers (the page view, `Admin::EditingController`, `Admin::ContentBlocksController`) load once for all the page's blocks and hand `markers:` down wherever they hand `holds:`. Register the two in `config/initializers/admin_slots.rb`, the avatar first, with a comment.

- [ ] **Step 3: Run** `PGGSSENCMODE=disable bin/rails test test/components test/integration test/lib`, then `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/notes_markers_test.rb test/system/admin/sections_test.rb test/system/admin/editing_holds_test.rb` and add to `editing_holds_test.rb` "a held block in a section shows its holder's avatar on the tile, and opening the tile shows the strip" (two sessions). Expected: 0 failures; no notes assertion edited.

- [ ] **Step 4: Commit** `ref: a block has a markers slot, with who is editing it and the notes marker registered in it`.

---

### Task 13: Documents, and the whole branch verified

**Files:** Create `docs/reference/live-editing.md`; Modify `CLAUDE.md`, `docs/reference/save-rule-and-write-queue.md`, `content-blocks-and-types.md`, `presence.md`, `slots.md`, `editors-and-translation-pair.md`, `access-control-and-audit.md`, `docs/superpowers/specs/2026-10-11-live-editing-design.md` (an "As built" section only), `docs/roadmap.md` (alone).

- [ ] **Step 1: `docs/reference/live-editing.md`**, in the shape of `docs/reference/presence.md` (the `> Describes:` line listing every file of the file map; then the incidents behind each rule as they happened while building, not as planned): what it is and is not (no co-editing; one person types in a block); the signal source and the mapping, with `SILENT` and why a new action must be placed; `Current.editing_tab` and why it is not `notes_tab`; the three fetches, the 204 and the 410; the merge rule, units and parts, why a kept unit is not moved, what "unsaved" is, the scroll anchor; the three conditions under which an answer is not drawn; the settings base (`settings_changed_at`) and why the tree's forwarding stayed; the table and the five statements, with the claim's SQL explained clause by clause; who claims nothing; the order claim, stale check, service; read-only as rendered, `HeldFields` and `freeze`; the hold script's rules, the lapse timer and why a renewal sends no signal; take-over step by step with the three outcomes; the slot; "In tests" (two sessions, how a reservation's clock is moved, which values are shortened, the fetch stubs that take only their own request); and "What is not built".
- [ ] **Step 2: `CLAUDE.md`.** In the reference index: "Before changing live refresh, reservations or taking over (`app/models/editing/`, `app/services/editing/`, `app/queries/editing/`, `app/channels/editing/`, `app/controllers/admin/editing_controller.rb`, `app/javascript/editing/`, `app/javascript/controllers/admin/editing/`), read `docs/reference/live-editing.md`." Under "Rules a change can break silently", each in the file's style and naming its test by its exact name: a content event name belongs in `Editing::Signals::MAP` or `SILENT`; an editing signal carries a kind, a block id, a reason and an origin; a form that holds unsaved changes is never replaced or removed by a refresh, and a kept unit is not moved; every ancestor of a unit up to the list has an id; a live fetch is a plain GET through the read scope and its answer is dropped when this tab wrote meanwhile; a reservation's statement is one statement, locks nothing and writes nothing of the record; claiming, renewing and releasing are not services and are not audited, taking over is; a request without a tab id neither claims nor is refused, and someone without the right claims nothing; a held form has no autosave controller; every claim, release, request and hand-over goes through the write queue, the `pagehide` release excepted; the page settings form's base is `settings_changed_at`; `Admin::Editing` is never defined; every editor write carries `X-Notes-Tab`. Update the rules that named `X-Page-Base-Updated-At` on a block's answer, the autosave rule ("carries the record's `base_updated_at`") and the slot hosts' sentence. The unit suite reads `CLAUDE.md`: run `PGGSSENCMODE=disable bin/rails test test/lib` after editing it.
- [ ] **Step 3: The other reference files:** `save-rule-and-write-queue.md` (the settings base; a held save's 409 beside the stale one; `quiet()`; the claim ahead of the first save; what was removed), `content-blocks-and-types.md` (`block.deleted`'s `page_id`; the unit marks and ids on the cards; "Moves" ignore a hold), `presence.md` and `slots.md` (the new slot in the table; the block card and tile in "What was not extracted" reworded; editing as the third user of `Live::Signals`, `Live::RecordChannel` and `live/connection`), `editors-and-translation-pair.md` (the live region, the strip's places), `access-control-and-audit.md` (the three `*.taken_over` events and that they are not changes).
- [ ] **Step 4: The spec's "As built" section** (its body is not rewritten): the seven points of "Where the code disagrees with the design" as they ended, and anything else that departed while building, each with its reason.
- [ ] **Step 5: Commit** Steps 1 to 4 as `docs: live refresh and edit reservations — the reference file, the rules and the spec as built`.
- [ ] **Step 6: `docs/roadmap.md`, alone** (re-read it first; reword no entry on plugins): step 3 of "Collaboration on content" shipped, with the line in the shipped table; under the seams entry, the block card's marker is now a slot and the deletion hook was not needed (a reservation expires), with its trigger left as it is; the gaps this build leaves, where the roadmap groups them, at least the ones under "Open points for the owner" below and: no rate limit on claims (spec §9), a subscription not re-judged when rights change, Safari and a throttled hidden holder tab checked by hand only, `X-Notes-Tab` and `data-notes-live` keeping notes' names. Commit `docs: the roadmap — live refresh and edit reservations shipped, with what they left open`.
- [ ] **Step 7: Verify on the last commit**, one command at a time, totals verbatim in the report: `bin/rubocop`; `bin/brakeman`; `bin/bundler-audit`; `bin/importmap audit`; `bin/rails zeitwerk:check`; `PGGSSENCMODE=disable bin/rails test`; `bin/rails tailwindcss:build`; `sysctl -n vm.loadavg`; `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test:system > tmp/system.log 2>&1` and read the end of the log. Expected: no offences, no warnings, "All is good!", 0 failures and 0 errors in both suites.

---

## Open points for the owner

What the spec and the handoff do not settle, what was chosen here, and what it costs if it is wrong.

1. **The page settings strip's wording.** Handoff 9 says "the same strip as a block" and gives no sentence. Chosen: "Dana Weiss is editing these settings". Cost if wrong: one locale key. A design question for Claude Design.
2. **"Copied".** Handoff 17 names an existing toast that does not exist. Chosen: the word in a status element inside the notice. Cost: a small rework if a toast is wanted (the layout has only an error toast template).
3. **The status line of a save refused by a hold.** Not in the handoff. Chosen: "Not saved — someone else is editing this", a new state `:held` styled like "Changed elsewhere". Cost: one key and one state.
4. **What a colleague's publish or unpublish refreshes.** The spec fetches "the page's settings form, or the post's form"; the publish state and the "Saved to site" wording live in the header, which nothing fetches. Chosen: as the spec says. Cost: after a colleague publishes, an open editor's header says Draft until reload, and its next save is the service's 403 if the viewer lacks `publish`.
5. **Tags.** Renaming, deleting or merging a tag touches the posts that carry it; that sends no signal here (the event names the tag, not the posts). Chosen: silent, so an open post form is refused as stale exactly as today. Cost: one known surprise; the fix is a `post_ids` list in those three events.
6. **A clean card that has the focus is replaced.** The spec protects unsaved text, not a caret. Chosen: replaced, the focus put back on the same field, the caret's position lost. Cost: someone reading with the cursor in a field sees it jump to the start when a colleague saves that very block.
7. **Read-only by rewriting the rendered form** (`HeldFields`, Nokogiri) instead of a read-only option on eight field components. Cost if wrong: a field whose markup does not survive a parse and a write (the component tests compare every control); the fallback is the option, component by component.
8. **A translation tab's section group** is merged in place only as far as its elements have ids; a group without them stays as it is until reload when one of its cards holds unsaved text. Nothing is lost, something may be stale. Cost: ids on that component if it matters.
9. **The page's holds are read twice per screen:** once for the strips (`Editing::Holds`) and once by the slot's loader, because the slot contract hands a component only what its own loader read. Cost: one indexed statement per editor load.
10. **A hold's lapse and renewal send no signal.** Other tabs ask again when the time their strip was rendered with runs out. Cost: one small GET per held card every two minutes at most while someone keeps typing; the alternative is a signal per save.
11. **A block deleted together with its section** has no event of its own, so a tab with unsaved text in it gets no notice (c): the card stays, marked gone, with its text. Cost: the notice is missing in that one case; the fix is the section's `deleted_block_ids` read in `block_gone`.
12. **`Editing::Channel` accepts a library image** (every registered kind), although nothing is ever signalled on its stream. Harmless; said so nobody is surprised.
13. **A person whose right to edit is removed keeps a hold until it lapses** (two minutes) unless someone takes it over, which needs no answer from them.
