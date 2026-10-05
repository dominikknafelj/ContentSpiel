# CS Studio design pass, round 3 (settings, media, people, system) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the remaining CS Studio screens to the v3 handoff — Settings (with Languages merged in), Media, Groups, Users, the AI assistant, Tags, Trash, the Audit log, System status, Change password, the Mind graph and the public preview banner — and land the three small data changes they need (token names, the AI key's saved date, the audit log naming a token).

**Architecture:** Rounds 1 and 2 built every shared part; this round composes them into the configuration and system screens. Three groundwork tasks come first because later tasks stand on them: the explicit-save footer learns to guard every way of leaving a screen and to tell other controls that changes are pending (Settings needs both); API tokens get a required name that the audit log copies at write time, so "via <token name>" survives a deleted token; and Settings gets one service call that saves site fields and language order together. Settings then stops autosaving and becomes one form with one footer, the Languages screen folds into it, and Media's detail page becomes a side panel on the grid. No permission rule changes anywhere: where the handoff draws a locked or read-only state, the view asks the same predicate the service already enforces.

**Tech Stack:** Rails 8.1, ViewComponent + Lookbook, Tailwind v4 (`bin/rails tailwindcss:build`), Stimulus via importmap (no npm), Minitest (no fixtures for content: `ContentHelper`), Cuprite system tests.

**Spec:** `docs/superpowers/specs/2026-10-03-cs-studio-design-pass-design.md` — §3, §4, §5.4, §5.6 and §8. Visual reference: `docs/design/cs-studio-handoff-v3/` — `README.md` §4.5–§4.9, §9, §10, and the mockups `Studio Settings`, `Studio Media`, `Studio Groups`, `Studio Group Edit`, `Studio Users`, `Studio User Edit`, `Studio AI Assistant`, `Studio Tags`, `Studio Trash`, `Studio Audit Log`, `Studio Audit Event`, `Studio System Status`, `Studio Change Password`, `Studio Mind Graph`, `Studio Modals`, `Studio States v3`, `Setup Wizard` (`.dc.html`). Where the spec and the handoff disagree, the spec wins.

**Code inventory:** the controller hands each implementer the relevant section of a code inventory (signatures, template outlines, routes, services, the tests that pin today's markup and copy) taken at the start of this round: inventory A (Settings, Languages, AI key, System status, Change password, preview banner), B (Media, Trash, Tags, Audit log, Mind graph), C (Groups, Users, tokens, setup token step). It is a snapshot: where it and the code disagree, the code wins.

## Decisions made in this plan

The spec and handoff leave these open; each is decided here so implementers don't guess. The product owner reviews this list with the plan.

| # | Topic | Decision |
|---|---|---|
| D1 | Token deleted, name in old events | `audit_events` gains `actor_label` (string, nullable), written once at record time with the token's name. "via <name>" reads it, so it survives the token row being deleted with its group or user. Deletion behaviour is unchanged. |
| D2 | Token name rules | Required, stripped, 1–60 characters, unique per user among that user's *active* tokens (case-insensitive). Existing tokens are named "Token 1", "Token 2", … per user by id. The raw token stays 64 hex characters (no `cs_mcp_` prefix). |
| D3 | Token reveal | Stays its own no-store, non-cached document rendered by the POST (never a redirect, never in flash), now drawn as the AI assistant page with the warn box in step 1 and the token filled into the config. |
| D4 | Settings save | One form, one footer, a normal PATCH: success redirects to the same URL with a toast "Settings saved"; a refusal re-renders at 422 with the error summary. It carries `base_updated_at`; a save on a stale base is refused (409) with "Settings were changed elsewhere since you opened this screen. Reload to see the latest — your changes are still in the form." |
| D5 | Site fields and language order together | `Settings::Save` gains `languages:` (the complete ordered entries); it calls `Locales::Configure` inside its own transaction, so one Save is all-or-nothing and records `settings.updated` and/or `language.configured`. |
| D6 | All-languages Site form (handoff B32) | Adopted: title and tagline inputs for every enabled language are in the form at once; the language tabs become in-page buttons that only switch which pair is visible. `?locale=` picks the tab shown first. Field names `site_setting[translations][<code>][title]`, ids `settings-<code>-title`. |
| D7 | "Falls back to" | A single select per language. It stores a one-element list (or none). A language that had several fallbacks shows the first; the others are dropped the next time that row's fallback is changed and saved. |
| D8 | Default language | Its own instant action behind a dialog: `Locales::MakeDefault` (needs `languages.manage`), event `language.default_changed`. The dialog's "(N items)" is the number of distinct records holding a translation today (a `translation_states` row that isn't `missing`), counted at render. |
| D9 | Who opens Settings | The module opens for `settings.manage` **or** `languages.manage`; each card and its nav link render only for its own right (Languages: `languages.manage`; Site, Publishing, AI: `settings.manage`). Services enforce the same split. |
| D10 | Instant actions while changes are pending | Add language, Turn off, Default, Test connection, Save key, Remove key and Replace are disabled while the main form has unsaved changes, with the hint "Save or cancel your changes first." |
| D11 | AI key date | `site_settings.ai_api_key_saved_at`; an existing key has none and reads "Key saved" alone. Format "added 2 Oct" (with the year when it isn't this year), in the site time zone. |
| D12 | Media detail URL | The panel lives at `/media?selected=ID` (with the grid's filters and page kept). `GET /media/:id` redirects there (303), so every existing link keeps working. The "Mine" filter stays as a fifth segment (nothing an editor can do today is lost). |
| D13 | Media filters | "Missing alt" = the default-language alt is blank. "Untranslated" = `missing` in any target language (hidden with one language). Counts respect the search but not the segment. |
| D14 | Picker | Click selects a tile, "Use image" confirms, double-click does both. Upload stays inside the picker as a header button; the first finished upload is selected. |
| D15 | Group editor states | Rows, not a grid: eleven rows (Posts ×5, Pages ×6) with scope chips and "Edit scope". A group the viewer can't manage as it stands (`AccessControl.can_manage_group?` false) is **read-only** (handoff C37); the service keeps its finer rule as the backstop. Inside an editable form a single grant the viewer can't hand out is a locked tick that is still submitted. |
| D16 | Group members | A chip input over a new `GET /<admin>/users/suggest` (needs `groups.manage`); owners are not offered ("Owners already have every permission"), an owner already stored as a member stays until removed. |
| D17 | Users read-only states | One public predicate, `Users::Manageability.for(actor, user)` → `:editable`, `:owner_protected`, `:outranked`, shared by the services and the view. |
| D18 | Owner changes | "Make owner…" and "Remove owner rights…" are instant dialogs posting `PATCH users/:id/owner`; `Users::Save` still decides. |
| D19 | Last sign-in | Derived from `session.created` audit events (one grouped query per list page); no new column. |
| D20 | Tags merge | `Tags::Merge.call(source, into:)`: posts get the target (no duplicates), the source is deleted, every carrying post is touched (open forms go stale), listing blocks naming the source are repointed to the target, one `tag.merged` event on the target with the source's name and the post count. No undo. |
| D21 | Trash rows | Roots only, as today ("Includes N subpages: …" names up to three). A missing `trashed_by` reads the name from the `*.trashed` audit event when there is one, else "System". |
| D22 | Audit "N saves" | `audit_events.occurrences` (integer, default 1), incremented when an event coalesces; the model guard and the Postgres trigger allow that one more column. |
| D23 | Audit paging | Stays "Load older" over `offset`; day headers are drawn per loaded page. Date presets are `range=today|7|30|90|custom` with `from`/`to` only for custom. |
| D24 | Leave dialog copy | "Leave without saving?" · "You have N unsaved changes on this screen." · **Keep editing** (primary) / **Discard changes**. |
| D25 | Account screen | Keeps the name form (spec §5.1) above the password card; both keep their own footer. |
| D26 | Preview banner | "Exit preview" goes to the record's public URL when it is live, else to its editor. Colours come from two new theme tokens that don't switch with the theme. |
| D27 | Mind graph | Tag nodes for tags on at least two readable posts, joined to those posts; related-post edges as today. Filter (All / Related / Tags) is client-side. Colours from `colour_index`, a retired type in `meta`. |

## Global Constraints

- Server-rendered ERB and ViewComponents, Tailwind v4, Hotwire. New JS is a Stimulus controller in `app/javascript/controllers/admin/` (identifier `admin--<name>`). No React, no npm.
- Every new or changed component has a Lookbook preview in `test/components/previews/admin/` and a test in `test/components/admin/`.
- Tokens only: no raw colour literals and no `dark:` variants (`test/lib/admin_design_rules_test.rb`). Red (`danger*`) only for destructive actions and failures; translation states never use red.
- Never define `Admin::Media`, `Admin::Trash`, `Admin::Translations`, `Admin::AI`, `Admin::Ai` or `Admin::Dashboard`. Screen components live under `Admin::…Screen::` — new this round: `Admin::SettingsScreen::`, `Admin::GroupsScreen::`, `Admin::UsersScreen::`, `Admin::TokensScreen::`, `Admin::AuditScreen::`; existing: `Admin::MediaLibrary::`, `Admin::TrashScreen::`.
- **Form placement:** inside the shell a form starts at the left edge of the content area; nothing is centred except the 403 and 404 messages (`test/lib/admin_design_rules_test.rb` fails on `mx-auto`). Widths: about 420px for single fields, 560px for a simple form, up to 880–1000px for a form with grids or a matrix.
- Forms cannot nest. Dialog forms live once in the layout or as siblings of the screen's form, and reach its fields with the `form=` attribute where needed.
- No inline event handlers (`test/lib/inline_handlers_test.rb`). Dialogs open with `data: dialog_trigger(id)`.
- Admin strings stay hard-coded English, each sentence one string.
- **No permission rule changes.** Every write goes through an `ApplicationService` with `authorize!` and `record_event` (`test/services/service_contract_test.rb`). Out-of-scope records are "not found", never "forbidden". Trashed records stay hidden at every list, search and picker (`test/integration/trash_visibility_test.rb` — add each new one).
- No part of an API token or the AI key is ever rendered after creation, logged or audited. The token reveal is never a redirect and never cached.
- **The save rule:** content autosaves through the write queue (`app/javascript/autosave/queue.js`; do not change it, `autosave_controller.js`, `queue_hold_controller.js` or `blocks_controller.js` — stop and report if a task seems to need it); configuration uses the explicit-save footer (`Admin::SaveBarComponent`, always visible, Save first); single actions are instant behind a dialog where destructive.
- A control that sets a value programmatically dispatches a bubbling `input` or `change` on the real form control, so the footer or autosave sees it.
- Content is created in tests with `ContentHelper` (`create_page`, `create_post`, `create_media_asset`, `rich_doc`, `with_locales`); integration tests sign in with `sign_in_as(users(:one))`, system tests with `sign_in_via_form(users(:one))`. This Minitest has no `stub`.
- Prefix every test command with `PGGSSENCMODE=disable`. Run `bin/rails tailwindcss:build` before system tests, and the full system suite with `PARALLEL_WORKERS=6`. Never run tests in the background. A system test never waits for an element that only a `hover:` style reveals (the CI browser can't hover): click it with `visible: :all`.
- Edit `app/assets/tailwind/content-spiel.tailwind.css` with targeted edits only; never rewrite it.
- Long, load-bearing comments are the norm: keep the ones that still apply, correct the ones your change makes false, and comment new non-obvious logic at the same density.
- Commits: conventional subjects, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Leaving Settings with unsaved changes, every way there is.** A sidebar link, a link inside the content area, a language tab, Back, closing the tab, and an instant action's own redirect: each either asks first or can't happen while changes are pending, and "Discard changes" really discards. A typed-but-unsaved field is never lost silently and never saved by accident. Pinned in Task 1 and Task 5.
2. **One Save, two rights.** A viewer with only `languages.manage` (or only `settings.manage`) posts a forged form containing the other card's fields: nothing of the other card is written, one `access.denied` is recorded, and their own card's change is not half-applied. Pinned in Task 4.
3. **A group form that submits less than it shows.** Locked ticks, kept pages the viewer can't open, a retired content type, an owner who is a member: saving an untouched form must change nothing (no grant removed, no member dropped, no 403), and the footer must read "No unsaved changes". Pinned in Tasks 10 and 11.
4. **Tokens after their owner is gone.** A token whose user or group was deleted: its past events still read "<user or 'a deleted user'> via <token name>", the list no longer shows it, nothing raises. A token named with markup or 60 emoji renders escaped and unbroken. Pinned in Task 2.
5. **Merging tags where posts carry both.** Merge A into B when some posts have A, some B, some both, one is trashed, and a listing block filters by A: no duplicate join row, every carrier ends with B exactly once, the block lists the same posts as before, an open post form is refused as stale instead of re-creating A. Pinned in Task 13.

## File structure

New (each component `*.rb` + `*.html.erb` unless noted):

| File | Responsibility |
|---|---|
| `app/javascript/controllers/admin/pending_lock_controller.js` | Disables instant actions while a save-bar form has unsaved changes |
| `db/migrate/*_add_name_to_api_tokens.rb`, `*_add_actor_label_and_occurrences_to_audit_events.rb`, `*_add_ai_api_key_saved_at_to_site_settings.rb` | The round's schema changes |
| `app/components/admin/channel_chip_component` | ADMIN / MCP chip (audit log, dashboard feed) |
| `app/components/admin/tokens_screen/{create_step,connect_step,table}_component` | The AI assistant's numbered flow and tokens table |
| `app/services/locales/make_default.rb` | Changes the default language (instant action) |
| `app/components/admin/settings_screen/{nav,site_card,languages_card,publishing_card,ai_card,ai_key}_component` | Settings, one card per section |
| `app/javascript/controllers/admin/{settings_tabs,repeat_rows,sortable_rows,ai_settings}_controller.js` | In-page language tabs; social-link rows; pending drag order; Replace key / Test connection rules |
| `app/controllers/admin/ai_keys_controller.rb` | Save and remove the AI key (its own immediate form) |
| `app/components/admin/media_library/{toolbar,tile,panel}_component` | Media filter segments, the tile with chips, the side panel |
| `app/javascript/controllers/admin/{media_drop,media_select}_controller.js` | Drop-anywhere upload with progress tiles; select + "Use image" in the picker |
| `app/components/admin/groups_screen/{list,permission_row,scope_editor,toggle_list,members,delete_zone}_component` | Groups list and editor |
| `app/controllers/admin/user_suggestions_controller.rb` | `GET users/suggest` for the members chip input |
| `app/services/users/manageability.rb` | "May this actor change this user" as one public answer |
| `app/components/admin/users_screen/{list,group_cards,owner_zone,delete_zone}_component` | Users list and editor |
| `app/services/tags/merge.rb` | Merge one tag into another |
| `app/models/audit/sentence.rb` | One human sentence per audit action |
| `app/components/admin/audit_screen/{toolbar,day_list,row,event_header,changes}_component` | Audit log and event page |
| `app/components/admin/system_check_row_component` | A system check row with chip, command box and Copy |
| `app/components/public/preview_bar_component` (in the public theme's scan path) | The preview banner |
| `app/components/admin/mind_graph_legend_component` | Legend and filter for the mind graph |

Modified: `app/javascript/controllers/admin/save_bar_controller.js`, `Admin::SaveBarComponent`, the admin layout's leave dialog, `ApiToken`, `ApiTokens::Issue`, `Audit` / `Audit::Coalescer` / `Audit::Event` / `db/triggers/audit_events_append_only.sql`, `Dashboard::Activity` and its row component, `SetupController` and the setup token views, `Settings::Save`, `Admin::SettingsController`, `Admin::LanguageTabsComponent`, `Jump::Search`, `Admin::MediaController` and views, `Media::PickerComponent`, `Media::Search`, the groups and users controllers and views, `Admin::PermissionMatrixComponent`, `branch_picker_controller.js`, `Admin::TagsController` and views, the trash screen components, `Admin::AuditEventsController` and views, `Setup::SystemCheck`, the account views, `PostGraph` and the mind-graph JS, `CLAUDE.md`, `docs/roadmap.md`.

Deleted: `Admin::LanguagesController` and its view (routes redirect to Settings), `Admin::SettingsFormComponent`, `app/views/admin/media/show.html.erb` as a full page, the per-row delete dialogs on the users list, `Admin::AuditChangesComponent` (replaced by `AuditScreen::ChangesComponent`).

---

### Task 1: The explicit-save footer guards every exit and reports pending changes

**Files:**
- Modify: `app/javascript/controllers/admin/save_bar_controller.js`, `app/components/admin/save_bar_component.{rb,html.erb}`, `app/helpers/admin/save_bar_helper.rb`, `app/views/layouts/admin.html.erb` (the leave dialog), `test/system/save_bar_test.rb`, `test/components/admin/save_bar_component_test.rb`
- Create: `app/javascript/controllers/admin/pending_lock_controller.js`, `test/system/admin/pending_lock_test.rb`

**Interfaces:**
- Produces:
  - The leave guard also covers Turbo **frame navigations inside `#content`** (a GET carrying `Turbo-Frame: content`, held in `turbo:before-fetch-request` the way the write queue holds one) and the browser's **Back/Forward** (`turbo:before-visit` doesn't fire for a restoration visit: the editor screens of this footer are never restored from cache — `turbo-cache-control: no-cache` on any page that renders an `admin--save-bar` form — and `popstate` with unsaved changes re-pushes the current URL and opens the dialog).
  - The footer's **Cancel** is the one frame navigation that never asks (it carries `data-save-bar-cancel`).
  - Snapshot: a control is one key per *position among same-named controls* (`site_setting[social_links][][name]` rows count separately), and a hidden input counts when it carries `data-save-bar-track` (chip inputs, sortable row order). Everything else as today.
  - `admin--save-bar` dispatches `admin--save-bar:state` on `document` (`detail: { unsaved: Boolean, count: Number }`) on connect and on every change, and exposes nothing else.
  - `admin--pending-lock` (on any element): while any save-bar form on the page is unsaved, every `[data-admin--pending-lock-target="control"]` inside it is disabled (a link gets `aria-disabled="true"` and its click is swallowed) and the `hint` target shows "Save or cancel your changes first."; both revert when the form is clean.
  - Leave dialog copy (D24): title "Leave without saving?", body "You have N unsaved changes on this screen." ("You have unsaved changes on this screen." when the count is 0), buttons **Keep editing** (primary, autofocus) and **Discard changes**.

- [ ] **Step 1: Failing system tests** in `test/system/save_bar_test.rb` (edit-user screen as the subject): a link inside the content area (the page's "Activity" link made a frame link for the test, or the users list's breadcrumb) with a typed change opens the dialog, "Keep editing" stays with the text intact, "Discard changes" leaves; Back with a typed change opens the dialog and the URL is unchanged after "Keep editing"; the footer's Cancel leaves without asking; two repeated-name rows count as two changes; a tracked hidden input counts as one; the dialog body names the count. In `pending_lock_test.rb` (a throwaway Lookbook-style test page is not available: use the edit-user screen and wrap its "Activity" link in a `pending-lock` in the test's own preview component `test/components/previews/admin/pending_lock_preview.rb`): the control is disabled and the hint visible after typing, enabled again after reverting.
- [ ] **Step 2: Run them, expect FAIL** (no frame guard, no `popstate` guard, old dialog copy, no controller).
- [ ] **Step 3: Implement.** Keep the module-level `instances` set and the single dialog. The frame hold must not double-handle a request the write queue already holds (check `event.defaultPrevented`; register on `document`, after the queue's `window`-level listener has had its turn is not guaranteed — so skip when no save-bar form is unsaved, and when the queue's `busy()` is true let the queue go first by returning). `beforeunload` stays. Update the layout's dialog markup and `[data-leave-confirm]` handling to the new buttons.
- [ ] **Step 4: Update** the existing save-bar tests for the new copy ("Stay"/"Leave" → "Keep editing"/"Discard changes") without weakening what they prove.
- [ ] **Step 5: Run** `test/system/save_bar_test.rb`, `pending_lock_test.rb`, `password_field_test.rb`, `admin/groups_editor_test.rb`, the component tests. PASS.
- [ ] **Step 6: Commit.** `feat: the save footer guards frame links and Back, counts repeated rows, and reports pending changes`

---

### Task 2: Token names, and the audit log remembers them

**Files:**
- Create: `db/migrate/*_add_name_to_api_tokens.rb`, `db/migrate/*_add_actor_label_and_occurrences_to_audit_events.rb`, `app/components/admin/channel_chip_component.{rb,html.erb}` (+ test, preview)
- Modify: `app/models/api_token.rb`, `app/services/api_tokens/issue.rb`, `app/models/audit.rb`, `app/models/audit/coalescer.rb`, `app/models/audit/event.rb`, `app/models/audit/snapshot.rb`, `db/triggers/audit_events_append_only.sql`, `app/queries/dashboard/activity.rb`, `app/components/admin/dashboard_screen/activity_row_component.{rb,html.erb}`, `app/helpers/admin/audit_events_helper.rb`, `app/views/admin/groups/edit.html.erb` (dialog names tokens), `db/schema.rb`, tests

**Interfaces:**
- Produces:
  - `api_tokens.name` (string, null: false). Migration: add nullable, backfill `'Token ' || ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY id)`, then `null: false`. `ApiToken::MAX_NAME_LENGTH = 60`; `normalizes :name` (strip); validates presence, length, and uniqueness per `user_id` among `active` tokens, case-insensitively (message "is already the name of one of this user's active tokens").
  - `ApiToken.generate!(user, group: <Admin group>, name: nil)` — `name: nil` picks the next free "Token N" for that user, so existing callers and tests keep working.
  - `ApiTokens::Issue.call(user, group:, name:, actor: Current.actor)` — a blank name fails with "Name can't be blank" on the token; metadata of `token.issued` gains `"name"`.
  - `audit_events.actor_label` (string, nullable): `Audit.record` writes `Current.actor.name` when the actor is an `ApiToken`, nil otherwise. `audit_events.occurrences` (integer, null: false, default 1): `Audit::Coalescer` adds 1 when it merges into an open row. `Audit::Event`'s update guard and the trigger allow `occurrences` beside the three coalescing columns; the trigger file is re-applied by the migration.
  - `Audit::Event#via_label` → the token name (`actor_label`, else `"an API token"` for an old event with none) when `actor_type == "ApiToken"`, else nil.
  - `Admin::ChannelChipComponent.new(channel:)` → "ADMIN" (meta) / "MCP" (accent) / "SETUP", "CONSOLE", "SYSTEM" (meta), mono 11px, with an `aria-label`.
  - Dashboard feed and audit list read "<user> via <token name>" with the user's own round avatar and the MCP chip (spec §5.4, handoff A6). `Dashboard::Activity::Row` gains `via_label` (replacing `via_token`).

- [ ] **Step 1: Failing tests.** Model: the migration's backfill names per user by id (test with `ActiveRecord::Migration` up on rows inserted with `insert_all`, following `test/migrations/*`); name rules (blank, 61 characters, duplicate among active, same name allowed once the first is revoked, another user's same name allowed); `generate!` without a name picks "Token N". Service: `Issue` refuses a blank name with no token created and no event. Audit: an event recorded with a token actor carries `actor_label`; after `ApiToken.delete_all` the event's `via_label` still reads the name; an old event (`actor_label` nil, token actor) reads "an API token"; coalescing bumps `occurrences`; an update of any other column is still refused by the model **and** by raw SQL (`update_all`). Review Focus 4: a name of `<script>x</script>` and one of 60 emoji render escaped in the feed row and the audit row (component tests), the token's user deleted → "a deleted user via <name>".
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** the migrations, model, service, audit changes, chip and the two readers. Update `Audit::Snapshot` (the ApiToken snapshot gains `name`; `label_for` returns the name). The group delete dialog lists tokens as "<name> — <user>".
- [ ] **Step 4: Update** the tests that pinned "via an API token" (`activity_row_component_test`, `dashboard_test`, `activity_test`, the preview) and the snapshot tests.
- [ ] **Step 5: Run** `test/models/api_token_test.rb`, `test/models/audit`, `test/services/api_tokens`, `test/queries/dashboard`, `test/components/admin/dashboard_screen`, `test/integration/admin/{dashboard,api_tokens,groups,audit_events}_test.rb`, `test/migrations`. Then the whole unit suite (the `generate!` default must keep every other test green). PASS.
- [ ] **Step 6: Commit.** `feat: API tokens have names, and audit events remember which token acted`

---

### Task 3: The AI assistant screen and the setup wizard's token step

**Files:**
- Create: `app/components/admin/tokens_screen/{create_step,connect_step,table}_component.{rb,html.erb}` (+ tests, previews)
- Modify: `app/controllers/admin/api_tokens_controller.rb`, `app/views/admin/api_tokens/{index,create}.html.erb`, `app/views/admin/api_tokens/_connection.html.erb`, `app/javascript/controllers/admin/token_reveal_controller.js`, `app/controllers/setup_controller.rb`, `app/views/setup/{mcp_token,mcp_token_created,review}.html.erb`, tests (`api_tokens_test`, `ai_assistant_and_graph_test`, `setup_optional_steps_test`, `setup_attribution_test`, `setup_wizard_test`)

**Interfaces:**
- Consumes: Task 2 (`ApiTokens::Issue.call(user, group:, name:)`, `ApiToken#name`).
- Produces:
  - `/<admin>/api_tokens`: h1 "Connect an AI assistant", then **1 · Create a token** (Name — required, placeholder "claude-desktop"; Group select with the selected group's description on one line beneath, updated on change; **Create token**), **2 · Add it to your assistant** (the MCP URL and the client configuration, each with **Copy**), then the **Tokens** table: Name, Acts as, Group, Created, Last used (IP on a second line, "Never"), Status (Active / Revoked), **Revoke…**; revoked rows stay listed, dimmed. No masked token column.
  - Create is still a non-Turbo POST answered by a rendered document (D3): the same page with, inside step 1, a warn box "Copy this token now. It won't be shown again.", the raw token (`#api-token-value`) and **Copy token**, and the token filled into step 2's configuration. `Cache-Control: no-store`, `turbo-cache-control: no-cache`, secrets blanked on `pagehide`. A validation failure re-renders the page at 422 with the error under Name and the typed name kept (it used to redirect with a flash).
  - Revoke dialog: title "Revoke “<name>”?", body "The assistant acting as <user> through this token loses access at once. The token stays listed as revoked, and its past changes stay in the audit log.", confirm **Revoke token** (danger).
  - Setup wizard step "Connect an AI agent": a required **Token name** input ("Helps you recognise which assistant is using it. The token acts as you; revoke it any time in Studio › AI assistant."), **Generate token**; the created page says "This is the only time the full token is shown. Copy it into your agent's config now."; the review step gains a row "MCP token: <name> (created)" or "Skipped" (the name is kept in the session; never the token).

- [ ] **Step 1: Failing tests.** Integration: the three sections and the table columns; create with a name shows the warn box, the token once, the config containing it, `no-store`; reloading the list shows no token; blank name → 422 with the error under the field and no token created; duplicate name → 422; revoke dialog copy; a viewer without `tokens.manage` sees only their own tokens (kept); revoked row dimmed with no Revoke button. Setup: the step refuses a blank name (422, no token); with a name it creates a token of that name; the review row.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Build** the three components and switch both views to them (the reveal document renders the same components with `raw_token:`). The group description line needs no request: the select's options carry `data-description`, a few lines in a small `admin--group-hint` controller swap the text.
- [ ] **Step 4: Setup wizard** form, created page and review row.
- [ ] **Step 5: System test** (extend `ai_assistant_and_graph_test.rb`): fill Name, **Create token**, the token is `\h{64}`, **Copy token**, **Done**/reload shows the table with the name and no token; Back doesn't show it.
- [ ] **Step 6: Run** the named tests plus `test/integration/admin/invariants_test.rb`, `access_control_test.rb`. PASS.
- [ ] **Step 7: Commit.** `feat: AI assistant as a numbered flow with named tokens; the setup wizard asks for a token name`

---

### Task 4: Settings services — one Save, the default language, the key's date

**Files:**
- Create: `db/migrate/*_add_ai_api_key_saved_at_to_site_settings.rb`, `app/services/locales/make_default.rb`, `test/services/locales/make_default_test.rb`
- Modify: `app/services/settings/save.rb`, `app/services/locales/configure.rb` (callable inside another service's transaction), `app/models/site_setting.rb`, `app/models/translations/state_index.rb` (a reader for D8's count), `test/services/settings/save_test.rb`, `test/services/translation_state_parity_test.rb`, `test/services/authorization_matrix_test.rb`, `db/schema.rb`

**Interfaces:**
- Produces:
  - `Settings::Save.call(site, attributes: {}, translations: {}, languages: nil, actor:)` — `languages:` is the complete ordered list `[{ "code" =>, "fallbacks" => [..] }]`; when given it needs `languages.manage` and is applied through `Locales::Configure` inside the same transaction (D5). `attributes` / `translations` still need `settings.manage`. Either part refused → nothing is written, one `access.denied`. `default_locale` is no longer accepted in `attributes` from CS Studio's form (the setup wizard still passes it; the controller in Task 5 never permits it).
  - `Locales::MakeDefault.call(code, actor: Current.actor)` — needs `languages.manage`; the language must be enabled; carries title and tagline as today (`carry_translations_into_new_default_locale`), `Translations::StateIndex.rebuild_all` synchronously, event `language.default_changed` with `field_changes: { "default_locale" => [old, new] }`. A no-op when already the default.
  - `Translations::StateIndex.translated_record_count` → the number of distinct `(record_type, record_id)` with a row whose state isn't `missing`, over kept records (D8).
  - `site_settings.ai_api_key_saved_at` (datetime, nullable), set in `Settings::Save#write_ai_key` beside the key and cleared with it; `SiteSetting#ai_api_key_saved_on` → a Date in the site zone or nil.

- [ ] **Step 1: Failing tests.** `Settings::Save`: `languages:` reorders and sets fallbacks and records `language.configured`; site fields + languages in one call write both and record both events; Review Focus 2 — an actor with only `languages.manage` passing `attributes: { time_zone: … }` and `languages:` is denied, nothing written, one `access.denied`; the mirror case for `settings.manage` only; an invalid site field rolls the language order back. `MakeDefault`: permission, a disabled code refused, title carried, `rebuild_all` ran (states of a translated page flip), the event. Key date: set on save, nil on removal, untouched by an unrelated save. Parity test: add a scenario for `MakeDefault`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** `Locales::Configure` must not open a second top-level transaction when called from `Settings::Save` (use `requires_new: true` or share the work in a private class method both call) and must still record its own event.
- [ ] **Step 4: Run** `test/services/{settings,locales}`, the parity and authorization tests, `test/integration/setup_site_steps_test.rb` (the wizard still saves). PASS.
- [ ] **Step 5: Commit.** `feat: Settings::Save takes language order; Locales::MakeDefault; the AI key remembers when it was saved`

---

### Task 5: Settings — the screen, one form, one footer

**Files:**
- Create: `app/components/admin/settings_screen/{nav,site_card,publishing_card}_component.{rb,html.erb}`, `app/javascript/controllers/admin/{settings_tabs,repeat_rows}_controller.js`, tests, previews
- Modify: `app/controllers/admin/settings_controller.rb`, `app/views/admin/settings/show.html.erb`, `app/components/admin/language_tabs_component.{rb,html.erb}` (a `mode: :buttons` variant), `app/controllers/admin/base_controller.rb` (`MODULES`: Settings opens for either right), `app/queries/jump/search.rb`, `app/controllers/concerns/admin/autosave_responses.rb` (comment only), tests
- Delete: `app/components/admin/settings_form_component.*` and its test and preview

**Interfaces:**
- Consumes: Task 1 (footer, pending lock), Task 4 (`Settings::Save` with `languages:`).
- Produces:
  - `/<admin>/settings`: a two-column layout at up to 1100px — an in-page nav at the left (Site, Languages, Publishing, AI translation; scroll anchors `#site`, `#languages`, `#publishing`, `#ai`; only the links for cards the viewer may manage, D9), and one card per section. One `<form id="settings-form">` wraps the Site and Publishing cards and the pending fields of the other two (Tasks 6 and 7 render their pending fields with `form="settings-form"`); one `Admin::SaveBarComponent` at the bottom of the column (save label "Save").
  - **Site card** — header with `Admin::LanguageTabsComponent(mode: :buttons)`; per language a pair "TITLE · TRANSLATABLE" / "TAGLINE · TRANSLATABLE" (`site_setting[translations][<code>][title]`, id `settings-<code>-title`; a non-default language shows the original in the reference card and the Translate / Suggest update / Still correct controls as the editors do); then Logo (`Admin::FileDropComponent` with a 44px preview or a "NONE" tile, help "PNG, JPEG, GIF or WebP. Without a logo the site title is shown.", "Remove logo" checkbox when one is stored), Time zone (help "Used for scheduled publishing."), and Social links (rows of Label + URL with ×, **+ Add link**; one empty row when there are none; names `site_setting[social_links][<n>][name|url]`).
  - **Publishing card** — "Keep trashed items for [N] days after an item is trashed." with help "Set to 0 to keep trashed items until someone empties the trash."
  - `PATCH /<admin>/settings` (D4): permits `translations: { code => [:title, :tagline] }`, `:logo`, `:remove_logo`, `:time_zone`, `:trash_retention_days`, `:ai_provider`, `:ai_model`, `social_links`, `languages` and `base_updated_at`; success → 303 to `admin_settings_path(locale:)` with notice "Settings saved"; failure → 422 re-render with `Admin::ErrorSummaryComponent` (field ids per locale), `save_bar_form_data(dirty: true)`; stale base → 409 re-render with the banner from D4. Never a Turbo Stream.
  - ⌘K: the four Settings destinations become anchors on the one screen (`#site`, `#languages`, `#publishing`, `#ai`), each behind its card's right.

- [ ] **Step 1: Failing tests.** Integration (`settings_test.rb`, rewritten for the form): every language's title and tagline inputs are in the page; a save of two languages' titles at once writes both and records one `settings.updated`; a blank default-language title → 422 with the summary linking `#settings-en-title` and the typed German kept; the logo upload, keep and remove; the time-zone safeguards (kept from today); social links in row order with a dropped half-empty row and the scheme error; retention validation; a stale base → 409 and nothing written; D9 — a `languages.manage`-only user gets the screen with only the Languages nav link and card, a `settings.manage`-only user without it, a user with neither gets the 403 page; a forged field outside the viewer's right is refused by the service (Task 4) and shown as the 403. ⌘K destinations. Component tests for the three components.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Build** the components and the controller action; remove the autosave wiring, `form_stream`, `logo_field_stream`, the `base_updated_at` stream and `SettingsFormComponent`. `admin--settings-tabs` switches the visible pair, keeps `aria-selected`, and never navigates; the missing/outdated markers per tab stay. `admin--repeat-rows` adds a row from a `<template>` and removes one, dispatching `change`. Translation suggestions keep working per language (ids now include the code — update `data-translate-input` and the suggestion box ids together, and the two suggestion tests that pin `settings-title`).
- [ ] **Step 4: System test** `test/system/admin/settings_test.rb` (Review Focus 1): type a German title on the Deutsch tab, switch tabs (no dialog, both values still there), the footer reads "1 unsaved change"; click a sidebar link → the Leave dialog → "Keep editing"; add a social link row, remove it → "1 unsaved change" again; **Save** → toast "Settings saved", values persisted in both languages; a typed change then Back → dialog; **Cancel** discards without asking. Replace the two system tests that relied on Settings autosaving (`autosave_test.rb:239` — move its empty-file-input subject to the page editor's hero or delete it if that is covered; `translations_test.rb:489` — press Save instead of waiting for the status).
- [ ] **Step 5: Run** the settings integration and system tests, `translation_suggestions_test.rb`, `translation_layout_guard_test.rb`, `jump/search_test.rb`, `command_palette_test.rb`, `access_control_test.rb`, `shell_test.rb`. PASS.
- [ ] **Step 6: Commit.** `feat: Settings is one form with a save footer, every language's site text at once, and sections by permission`

---

### Task 6: Settings › Languages

**Files:**
- Create: `app/components/admin/settings_screen/languages_card_component.{rb,html.erb}`, `app/javascript/controllers/admin/sortable_rows_controller.js`, tests, preview
- Modify: `app/controllers/admin/languages_controller.rb` (keeps `create`, `destroy`; gains `make_default`; `index` and `update` go), `config/routes.rb` (`GET settings/languages` → 301 to `settings#languages` anchor; `patch settings/languages/:id/default`), `app/views/admin/settings/show.html.erb`, tests (`language_settings_test.rb`, `locales/*`)
- Delete: `app/views/admin/languages/index.html.erb`

**Interfaces:**
- Consumes: Task 1 (`admin--pending-lock`, tracked hidden inputs), Task 4 (`languages:` on `Settings::Save`, `Locales::MakeDefault`, `translated_record_count`), Task 5 (the form).
- Produces:
  - The **Languages card** (only with `languages.manage`): one row per enabled language — drag handle (keyboard path: Space, arrows, Space, Escape), native name + path (`/` for the default, `/<code>` otherwise), a **Default** radio, a **Falls back to** select (the other enabled languages plus "None (default)"; the default's own select is disabled and reads "None (default)"), **Turn off…** (not on the default). Below: **Add language** (select of supported, not-enabled languages + button).
  - **Pending** (in `settings-form`, saved by the footer): the order (`site_setting[languages][][code]` as tracked hidden inputs in row order) and each fallback (`site_setting[languages][][fallback]`). `admin--sortable-rows` reuses the block list's SortableJS options and keyboard path but only rewrites the DOM order and dispatches `change`; nothing is sent until Save.
  - **Instant, each behind a dialog, disabled while changes are pending (D10):**
    - Default: choosing another radio opens "Make <Name> the default?" — "<Name> moves to / and <Old> to /<old>. Existing links to <Old> pages without /<old> will open the <Name> version, or show “not found” where there is none." and the warn line "<Name> becomes the source language, so every translation is marked outdated (N items)." — **Change default language** (primary). Cancel puts the radio back. Posts `PATCH settings/languages/<code>/default`.
    - Turn off: "Turn off <Name>?" — "<Name> disappears from the language switcher and /<code> pages show “not found”. Translations are kept, so turning it back on restores them." — **Turn off <Name>** (primary, not red: nothing is destroyed).
    - Add language: instant, no dialog.
    Each answers with a 303 back to `settings#languages` and a toast ("<Name> is now the default language", "<Name> turned off", "<Name> added").

- [ ] **Step 1: Failing tests.** Integration: the card's rows and controls; a Save with a new order and a fallback writes both through `Settings::Save` (one request, events as Task 4); a single-fallback select over a language that had two shows the first and, once changed and saved, stores only the new one (D7), while an untouched row keeps its stored list; `make_default` (permission, disabled code 422, redirect and toast, states rebuilt); Turn off and Add as today's `destroy`/`create` with the new toasts; `GET /settings/languages` redirects; the dialog shows the count from `translated_record_count`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Build** the card, the controller actions and `admin--sortable-rows`.
- [ ] **Step 4: System test** (in `test/system/admin/settings_test.rb`): reorder by keyboard (Space, ArrowDown, Space) → "1 unsaved change" → Save → the language tabs elsewhere follow the new order; with a pending change the Default radios, Turn off and Add are disabled and the hint shows; after Save, choose another Default → the dialog with its count → confirm → the tabs' default changes and the site title carried over.
- [ ] **Step 5: Run** the settings tests, `test/services/locales`, `translation_state_parity_test.rb`, `jump/search_test.rb`. PASS.
- [ ] **Step 6: Commit.** `feat: Languages live in Settings — drag order and fallbacks on Save, default and on/off as instant actions`

---

### Task 7: Settings › AI translation

**Files:**
- Create: `app/components/admin/settings_screen/{ai_card,ai_key}_component.{rb,html.erb}`, `app/controllers/admin/ai_keys_controller.rb` (+ routes `resource :ai_key, only: %i[update destroy]` under settings), `app/javascript/controllers/admin/ai_settings_controller.js`, tests, previews
- Modify: `app/controllers/admin/settings_controller.rb` (`test_ai_connection` measures the time), `app/views/admin/settings/show.html.erb`, tests (`ai_settings_test.rb` integration and system)
- Delete: `app/views/admin/settings/_ai_key_field.html.erb`, `_ai_test_result.html.erb`

**Interfaces:**
- Consumes: Task 1, Task 4 (`ai_api_key_saved_on`), Task 5.
- Produces:
  - The **AI translation card** (with `settings.manage`): Provider select and Model input are pending fields of `settings-form`. The key is a chip — "● Key saved · added 2 Oct" (or "Key saved" alone, D11; "No key yet" when unset) with **Replace** / **Remove…** (or **Add key** when unset). Replace swaps the chip for an input + **Save key** / **Cancel** (client-side; the input is never pre-filled and has its own form). No part of the key is ever rendered.
  - `PATCH /<admin>/settings/ai_key` (saves) and `DELETE` (removes, behind the existing confirm "Remove the API key?"): each answers with a Turbo Stream replacing only the key component and a toast ("API key saved" / "API key removed"), so the page and its state stay. Both are disabled while the main form has unsaved changes (D10).
  - **Test connection**: disabled while Provider or Model differ from their saved values — hint "Save provider and model first. Tests the saved settings." — and while changes are pending. Result inline: "● CONNECTED · 412 MS" (ok ink, mono) or the provider's message in danger ink.

- [ ] **Step 1: Failing tests.** Integration: chip states (unset, set without a date, set with a date this year and last year); save key → stream with the chip, the key encrypted, `ai_api_key_saved_at` set, never in the response or log; a blank key → 422 with the error in the key component; remove; the unreadable-key cases kept from today; Test connection OK shows the milliseconds, the failure message, "isn't set up", 403 without `settings.manage`; provider and model are saved by the main Save, an unregistered provider refused at the field.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Build.** `admin--ai-settings` compares the two inputs with their `data-saved-value` to gate Test connection, and handles Replace / Cancel.
- [ ] **Step 4: System test** (rewrite `test/system/admin/ai_settings_test.rb`): Add key → the chip, the page never contains the key; change the model → Test connection disabled with the hint → Save → Test connection → "CONNECTED · … MS"; Remove… → confirm → "No key yet".
- [ ] **Step 5: Run** both `ai_settings_test.rb` files and the settings tests. PASS.
- [ ] **Step 6: Commit.** `feat: AI translation card — the key as a chip with its own form, Test connection against the saved settings`

---

### Task 8: Media — the grid with a side panel

**Files:**
- Create: `app/components/admin/media_library/{toolbar,tile,panel}_component.{rb,html.erb}`, tests, previews
- Modify: `app/controllers/admin/media_controller.rb`, `app/views/admin/media/index.html.erb`, `app/models/media/search.rb` (filters and counts), `app/components/admin/media_library/{grid,detail}_component.*`, every caller of `admin_medium_path` that means "open this image" (Jump::Search, dashboard rows, the matrix, trash Undo), tests (`media_test.rb`, `translation_status_test.rb`, `translation_layout_guard_test.rb`, `translations_overview_test.rb`, `trash_visibility_test.rb`, `media_picker_test.rb`)
- Delete: `app/views/admin/media/show.html.erb`

**Interfaces:**
- Produces:
  - `Media::Search.new(q:, filter:, actor:)` with `filter` ∈ `all | unused | missing_alt | untranslated | mine` and `#counts` → `{ all:, unused:, missing_alt:, untranslated:, mine: }` in one grouped query, respecting `q` but not the segment (D13). "Missing alt" is a SQL condition on the default-language key of the `alt` jsonb (`COALESCE(btrim(alt ->> :default), '') = ''`); "Untranslated" joins `translation_states` (`record_type = 'Media::Asset'`, `state = 'missing'`, target languages), kept only; hidden with one language.
  - `/media?selected=ID` (+ `q`, `filter`, `page`, `locale`): the grid at the left (48 tiles a page) and a 340px panel at the right; with nothing selected the grid takes the width. `GET /media/:id` → 303 to `/media?selected=:id` keeping `locale` (D12). An id the viewer can't open or a trashed one is the 404 as today.
  - **Toolbar:** search (instant), segments All / Unused / Missing alt / Untranslated / Mine with counts, **Upload images** in the header.
  - **Tile:** thumbnail, title, chips `NO ALT` (warn) and `UNUSED` (meta); the selected tile has an accent ring and `aria-current`.
  - **Panel** (`Admin::MediaLibrary::PanelComponent`): preview, file info in mono (type · size · dimensions · uploaded by, when), language tabs (links that keep `selected`), Title, Alt text (warn border when the default-language alt is empty), Caption — the existing autosaving detail form with its translation pair stacked (the panel is narrower than 880px) — "Used on" links ("Only by items in the trash: …" names only owners the viewer may read), and **Move to trash…** with "Kept in Trash for N days." (or "Kept in Trash until someone empties it."); disabled with the reason while a kept page or post uses it. A viewer who may not edit sees plain text and "Only the uploader or a media manager can edit this image." (handoff B19).

- [ ] **Step 1: Failing tests.** `Media::Search`: each filter and the counts (an asset with alt only in German is "missing alt" when English is the default; an asset with no state rows isn't "untranslated"; a trashed asset never counts). Integration: `?selected=` renders the panel with the form; `GET /media/:id` redirects with the locale kept; every former caller lands on the panel; the segments' counts; the chips; the view-only panel; trash visibility pairs for the two new filters and the counts.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Build** the three components and the controller; move the detail form into the panel unchanged in behaviour (it still autosaves through the write queue; its `:saved_over` wording stays).
- [ ] **Step 4: Update** the tests that fetched `/media/:id` as a page, and the layout guard to render the panel.
- [ ] **Step 5: System test** `test/system/admin/media_library_test.rb`: click a tile → the panel opens and the URL carries `selected`; edit Alt → saved, the `NO ALT` chip goes; the Missing alt segment count drops by one; switch to Deutsch in the panel → the stacked pair.
- [ ] **Step 6: Run** the media, translation and trash-visibility tests. PASS.
- [ ] **Step 7: Commit.** `feat: Media is a grid with a side panel, filter segments with counts and tile chips`

---

### Task 9: Media — drop-anywhere upload and the picker

**Files:**
- Create: `app/javascript/controllers/admin/{media_drop,media_select}_controller.js`, tests
- Modify: `app/views/admin/media/index.html.erb`, `app/components/media/picker_component.{rb,html.erb}`, `app/javascript/controllers/admin/media_picker_controller.js` (and `media_upload_controller.js`), `app/controllers/admin/media_assets_controller.rb`, `app/controllers/admin/media_controller.rb` (a frame-scoped grid for the picker), tests (`media_picker_test.rb`, `rich_text_test.rb` image flow, `media_assets_test.rb`)

**Interfaces:**
- Consumes: Task 8 (`Media::Search`, the toolbar and tile components).
- Produces:
  - **Drop anywhere** on the Media screen (only for a `media.upload` holder, only for drags that carry files): a full-content overlay "Drop images to upload"; each file becomes a progress tile at the start of the grid (name, a bar, "Uploading…", then the real tile; a failure shows the reason and **Dismiss**). Uploads go one at a time through the existing upload endpoint; a finished upload doesn't reload the page.
  - **The picker** (880 dialog, in the layout) reuses the toolbar and tiles inside its own Turbo Frame (`media-picker-grid`): instant search and the segments without leaving the dialog; **×** at the top; a footer "1 selected · Cancel · **Use image**". Click selects, **Use image** confirms, double-click does both (D14); the choice still comes back to the opener through the existing event. **Upload** in the picker's header shows progress tiles first and selects the first finished upload (handoff C36b). A viewer without `media.upload` gets no picker: the field offers **Remove** only, with the hint "You can't choose images." (kept from today).
  - Escape inside the picker's search clears the search first; a second Escape closes the dialog.

- [ ] **Step 1: Failing tests.** Integration: the picker's frame endpoint renders tiles for a query and a segment, read-gated on `media.upload`, kept only; the upload endpoint's JSON carries what a tile needs. System (`media_picker_test.rb`, rewritten where it pinned the Library/Upload tabs and the Search button): open from a hero field → type to filter (no button) → click a tile → "1 selected" → **Use image** → the field shows it and autosaves; double-click picks at once; upload a file in the picker → a progress tile → it is selected → **Use image**; Escape clears the search, then closes. `media_library_test.rb`: dropping a file on the page (dispatch a `drop` with a `DataTransfer` built in the page) shows a progress tile and then the image, with no reload.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Build.** The picker's filter form targets its own frame (the shared `filter_form_options` takes a `frame:`); `admin--auto-submit` already takes the form's own frame target.
- [ ] **Step 4: Run** the picker, rich-text image, hero and image-block system tests, `trash_visibility_test.rb`. PASS.
- [ ] **Step 5: Commit.** `feat: drop images anywhere on Media; the picker reuses the grid with instant search and select-then-use`

---

### Task 10: Groups — the list and the permission rows

**Files:**
- Create: `app/components/admin/groups_screen/{list,permission_row,scope_editor,toggle_list}_component.{rb,html.erb}`, tests, previews
- Modify: `app/controllers/admin/groups_controller.rb`, `app/views/admin/groups/{index,_form,new,edit}.html.erb`, `app/javascript/controllers/admin/{permission_matrix,branch_picker}_controller.js`, `app/components/admin/permission_matrix_component.*` (reduced to composing the new parts, or deleted in favour of them), tests (`groups_test.rb`, `groups_editor_test.rb`)

**Interfaces:**
- Produces (the posted param shape **does not change**: `group[grants][<key>][enabled|content_types[]|own|page_ids[]]`):
  - **Groups list:** a card table — Name (+ "Built-in" tag and description), Members, Tokens (active tokens bound to the group) — each row one link to its editor (the name is the link, stretched over the row; no Edit buttons); **New group** in the header; the line "Built-in groups can be changed but not deleted. Deleting a custom group removes its permissions from its members and revokes its AI tokens."
  - **Editor**, up to 1000px: Name and Description, then **Posts** and **Pages** as eleven rows (`GroupsScreen::PermissionRowComponent`): a checkbox, the short label (Read, Create, Edit, Publish, Move, Move to trash — presentation only; the registry's labels and the denial copy are untouched), the key in mono with `title` = the key, scope chips at the right ("All content types", a chip with the type dot per chosen type, "Own only"; "All pages" or "Under <page>" per branch root, "+N" past three), and **Edit scope** / **Done** opening the row's `ScopeEditorComponent` in place.
  - **Posts scope:** a content-type multi-select (none ticked = all) and an **Own only** toggle with the help "Only posts the user wrote." (the copy follows the rule that exists).
  - **Pages scope:** the branch tree, tri-state — ✓ chosen, – an ancestor of a chosen page (`indeterminate`, never submitted), greyed ✓ a page included by a chosen ancestor (disabled, never submitted). A stored root the viewer can't open stays as a hidden input and the line "A page you can't open (kept)" below the tree (its place in the tree is not disclosed).
  - **Removed type:** a stored content type that is no longer registered shows as a warn chip "! <name> · this type no longer exists" with **Remove**; it is carried as a hidden input until Remove is pressed, so an untouched save keeps it (today it was dropped silently — `Groups::Save` already tolerates the unknown value as a dead scope; verify, and if it refuses, keep today's drop-on-save and make the chip informational, saying so in the report).
  - **Other permissions:** three cards of toggles — Content (`tags.manage`, `media.upload`, `media.manage`, `ai.translate`), Administration (`settings.manage`, `languages.manage`, `users.manage`, `groups.manage`, `tokens.manage`), Oversight (`system_status.view`, `audit.view`, `trash.empty`); a plugin permission lands in a fourth card named by its own area.
  - Scope chips update live as the editor changes (the controller rewrites the chip row from the ticked boxes).

- [ ] **Step 1: Failing tests.** Components: a row with no scope, a mixed scope, a removed type, an unreadable kept page; the tri-state tree's server-rendered states; the toggle cards' grouping including a fake plugin permission. Integration: the list (token counts in one grouped query; a query-count check with 2 and 10 groups), the editor's rows keep every existing input name (`groups_test.rb`'s param-shape assertions stay), Review Focus 3 — open a group holding a kept page, a removed type and scoped grants, submit the form exactly as rendered (build the params from the rendered inputs in the test) → no change, no event beyond none, 303.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Build.** `branch_picker_controller.js` gains the partial state (`indeterminate = true` on ancestors of a chosen box) and dispatches `change`; `permission_matrix_controller.js` opens/closes scope editors and rewrites chips.
- [ ] **Step 4: System test** (`groups_editor_test.rb`): tick Edit pages → **Edit scope** → tick "About" → "Team" beneath is greyed ✓ and "Home" shows – → **Done** → the chip "Under About" → Save → stored `page_ids == [about.id]`; untick a content type in a posts row → the chip row changes → the footer counts the change.
- [ ] **Step 5: Run** the groups tests, `save_bar_test.rb`, `test/services/groups`. PASS.
- [ ] **Step 6: Commit.** `feat: groups list with token counts; the group editor as permission rows with scope chips and a tri-state branch tree`

---

### Task 11: Groups — members, locked ticks, delete zone, view-only

**Files:**
- Create: `app/components/admin/groups_screen/{members,delete_zone}_component.{rb,html.erb}`, `app/controllers/admin/user_suggestions_controller.rb` (+ route `get "users/suggest"` before `resources :users`), tests, previews
- Modify: `app/views/admin/groups/{_form,edit}.html.erb`, `app/components/admin/groups_screen/permission_row_component.*`, `app/controllers/admin/groups_controller.rb`, tests

**Interfaces:**
- Consumes: Task 1 (tracked hidden inputs), Task 2 (token names), Task 10.
- Produces:
  - **Members:** `Admin::ChipInputComponent` (`name: "group[member_ids][]"`, chips = current members by `display_name` with the email as hint, hidden inputs tracked by the footer) over `GET /<admin>/users/suggest?q=` (needs `groups.manage`; up to 8 users matching name or email, owners left out) with the help "Owners aren't listed: they already have every permission." An owner who is already a member stays as a chip until removed (D16).
  - **Locked tick** (D15): in an editable form, a grant the viewer couldn't hand out (`AccessControl.can_grant?(Current.actor, key, scope)` false) renders as a greyed filled box with "You can't grant this" and is carried by hidden inputs (enabled + its scope), so it is still submitted. The check runs once per held grant with the page branches preloaded (no query per row).
  - **View-only:** when `AccessControl.can_manage_group?(Current.actor, group)` is false the whole form is inside `<fieldset disabled>` styled `.admin-view-only`, the notice reads "This group has permissions you can't hand out, so you can only view it.", and there is no footer and no delete zone (handoff C37).
  - **Delete zone** (custom groups the viewer can manage): "Delete this group" — "N members lose its permissions. N AI tokens are revoked." — **Delete group…** → dialog "Delete “<name>”?" — "Its N members lose these permissions, and its N AI tokens are revoked. Users themselves are not deleted." with the tokens named ("<token> — <user>") — **Delete group** (danger). A built-in group shows "A built-in group can be changed but not deleted." instead.
  - Save label "Save group" / "Create group"; after a save the editor stays, with the toast "Group saved".

- [ ] **Step 1: Failing tests.** Suggest endpoint: permission (403 without `groups.manage`), owners excluded, the query bound, a limit of 8. Integration: members saved through chips (add, remove, an owner member kept when untouched — Review Focus 3); a locked grant survives an untouched save and can't be unticked by a forged param (the service's refusal is the backstop: 403 and one `access.denied`); the view-only state for a `groups.manage` holder who can't manage the Admin group — no footer, no delete zone, the notice, every input disabled, and a forged PATCH still refused; the delete zone's counts and the dialog naming tokens; built-in note.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Build.**
- [ ] **Step 4: System test:** add a member by typing part of an email → chip → "1 unsaved change" → **Save group** → the member is stored; **Delete group…** → the dialog names the token → confirm → the list, the toast "Group deleted".
- [ ] **Step 5: Run** the groups tests, `test/services/groups`, `access_control_test.rb`, `authorization_matrix_test.rb`. PASS.
- [ ] **Step 6: Commit.** `feat: group members as chips, locked ticks, a delete zone, and a view-only state for groups you can't manage`

---

### Task 12: Users

**Files:**
- Create: `app/services/users/manageability.rb`, `app/components/admin/users_screen/{list,group_cards,owner_zone,delete_zone}_component.{rb,html.erb}`, tests, previews
- Modify: `app/services/users/{owner_protection,save,destroy,update_password}.rb` (use `Manageability`), `app/controllers/admin/users_controller.rb` (+ route `patch users/:id/owner`), `app/views/admin/users/{index,new,edit,_access_fields}.html.erb`, tests (`users_test.rb`, `save_bar_test.rb`, `test/services/users`)

**Interfaces:**
- Produces:
  - `Users::Manageability.for(actor, user, channel: Current.channel)` → `:editable`, `:owner_protected` (a non-owner looking at an owner) or `:outranked` (the user holds a group the actor can't manage). `Users::OwnerProtection`'s private predicates delegate to it, so the services and the view can't drift.
  - **Users list:** a card table whose rows are links to the editor — avatar (initial, round), name or email with the email beneath when there is a name, "(you)", an **OWNER** tag, group chips ("No groups"), last sign-in (`Admin::TimeAgoComponent`, "Never") from one grouped query over `session.created` events for the listed users (D19). **New user** in the header. No Edit or Delete buttons in rows.
  - **Editor** (up to 880px, the heading is the user's `display_name`, "Last signed in <time ago>." beneath): Name, Email; on edit **Set a new password…** discloses the two password fields (blank still means "keep"); on new the password fields with Show and the meter; **Groups** as cards in a two-column grid (the card is the label: checkbox, name, description; tinted when ticked; a group the viewer can't assign is a sunken card with a greyed box and "You can't grant this group.", still carried when ticked); "Manage groups →" for a `groups.manage` holder. Save label "Save user" / "Create user".
  - **Owner zone** (owners only, below the form, a dashed card): for a non-owner "Owners can do everything, whatever their groups, and are the only ones who can change who is an owner." + **Make owner…**; for an owner + **Remove owner rights…**; for the last owner the button is disabled with "<Name> is the only owner, so their owner rights can't be removed." The dialogs: "Make <name> an owner?" — "Owners have every permission, including managing other owners and removing your owner rights." — **Make owner**; "Remove owner rights from <name>?" — "They keep their groups and the permissions those give." — **Remove owner rights**. Both post `PATCH users/:id/owner` (`owner=1|0`) → `Users::Save` → 303 back with a toast (D18), and are disabled while the form has unsaved changes.
  - **Delete zone** (edit only): **Delete user…** → "Delete <name>?" — "They can't sign in any more and their AI tokens stop working. Their pages, posts and media stay; posts they wrote are left without an author." (your own account: "This is your own account — deleting it signs you out.") — **Delete user** (danger). Disabled for the last owner with the reason.
  - **Read-only states** (handoff B28): `:owner_protected` → the form in `<fieldset disabled>` with "Only owners can change other owners."; `:outranked` → "This user has permissions you don't have, so you can't change them."; neither has a footer, owner zone or delete zone.

- [ ] **Step 1: Failing tests.** `Manageability`: the three answers, a nil trusted actor, a token actor, yourself. Services still refuse exactly what they refused (their tests unchanged). Integration: the list's columns with one query for last sign-ins (2 vs 10 users); the group cards keep `user[group_ids][]` and the locked carry; the owner endpoint (owner only; a non-owner's forged PATCH refused with one `access.denied`; the last owner can't be demoted — message kept); the delete zone and its two bodies; the two read-only states with a forged PATCH still refused; "Set a new password…" leaves the password alone when untouched.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Build**; remove the per-row dialogs from the list.
- [ ] **Step 4: System test** `test/system/admin/users_test.rb`: open a user from the list row, tick a group card → "1 unsaved change" → **Save user**; **Make owner…** → confirm → the OWNER tag in the list; with a typed change the owner and delete buttons are disabled with the hint.
- [ ] **Step 5: Run** the users tests, `save_bar_test.rb` (its edit-user subject: update selectors, keep what it proves), `password_field_test.rb`, `accounts_test.rb`. PASS.
- [ ] **Step 6: Commit.** `feat: users list with last sign-in; the user editor with group cards, an owner zone and read-only states`

---

### Task 13: Tags — inline rename, the row menu, Merge

**Files:**
- Create: `app/services/tags/merge.rb`, `test/services/tags/merge_test.rb`
- Modify: `app/controllers/admin/tags_controller.rb` (+ route `post tags/:id/merge`), `app/views/admin/tags/index.html.erb`, `app/services/tags/{rename,destroy}.rb` (share the "affected content types / carriers" helper), tests (`tags_test.rb`, `trash_visibility_test.rb`, `translation_state_parity_test.rb` if tags touch states — they don't; `service_contract_test.rb` picks the new service up)

**Interfaces:**
- Produces:
  - `Tags::Merge.call(source, into:, actor: Current.actor)` (D20) — needs `tags.manage`; `into` must be another tag; in one transaction: every post carrying `source` gets `into` unless it has it, `source`'s join rows go, every carrier post is touched (so an open post form is refused as stale, as Rename and Destroy do), every `post_list` block whose `settings["tag"]` names `source` (case-insensitively) is pointed at `into`'s name and its listing paths resynced, `source` is destroyed, one `tag.merged` event (subject `into`, metadata `{ "merged" => source.name, "posts" => N }`).
  - **Tags list:** a card table — Name (click to rename inline; the row's existing autosave), Posts (the number of kept posts the viewer can read, linking to the posts list filtered by that tag), ⋯ (`Admin::MenuComponent`: **Merge into…**, divider, **Delete tag…**). No red buttons in rows.
  - **Merge dialog** (460): "Merge “<name>” into…" — a tag picker (`Admin::ChipInputComponent`, `single: true`, no create, the source excluded) — "Its N posts get the chosen tag and “<name>” is deleted. This can't be undone." — **Merge tags** (primary). One dialog in the page, filled from the row's trigger.
  - **Delete dialog:** "Delete “<name>”?" — "It is removed from N posts. The posts themselves stay." (with no posts: "No posts use it.") — **Delete tag** (danger).

- [ ] **Step 1: Failing tests.** Review Focus 5 in `merge_test.rb`: posts with A only, B only, both, a trashed post with A → every carrier has B exactly once, A is gone, `PostTag` has no duplicate; a listing block filtering by "A" (and one by "a") lists the same posts before and after; carriers' `updated_at` moved and an open post form's autosave is refused (integration); `into == source` refused; a non-`tags.manage` actor denied with one event; one `tag.merged` event with the metadata.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** the service, the action (303 + toast "Merged “A” into “B”"), the list and the two dialogs.
- [ ] **Step 4: System test** (extend the tags system test or add `test/system/admin/tags_test.rb`): rename inline; ⋯ → **Merge into…** → pick → **Merge tags** → the source row is gone and the target's count rose; the post count link opens the filtered posts list.
- [ ] **Step 5: Run** the tags tests, `posts_test.rb` (the stale-form tests), `trash_visibility_test.rb`. PASS.
- [ ] **Step 6: Commit.** `feat: merge tags; the tags list with inline rename, post links and a row menu`

---

### Task 14: Trash

**Files:**
- Modify: `app/controllers/admin/trash_controller.rb`, `app/components/admin/trash_screen/{list,row}_component.{rb,html.erb}`, `app/views/admin/trash/index.html.erb`, tests (`trash_test.rb` integration and system, `trash_visibility_test.rb`)
- Create: `app/components/admin/trash_screen/tabs_component.{rb,html.erb}` (+ test, preview)

**Interfaces:**
- Produces:
  - **Tabs** with counts — All, Pages, Posts, Images (roots the viewer may act on, the same numbers as the sidebar badge) — and **Empty trash…** in the header as a `danger_text` button (only with `trash.empty`).
  - **Rows** (D21): title + type; for a page "Includes N subpages: A, B, C" (up to three names the viewer may read, then "and N more"); "<who> · <time ago>" where who is "You", the user's name, the name from the record's `*.trashed` audit event when `trashed_by` is gone, else "System"; the retention tag in mono — "IN 30 DAYS", "TODAY", or "NEVER" when retention is 0 — with the exact date as tooltip; **Restore** (secondary) and **Delete now…** (`danger_text`). A branch member shown on its own (its root is gone from the trash) offers inline **Restore under** [select of `AccessControl.creatable_parents`] + **Restore**. **Delete now…** disabled shows the reason as tooltip and as a second line (e.g. "Still used by 2 items in the trash").
  - **Empty trash dialog:** "Empty the trash?" — "This deletes N pages, N posts and N images for good. It can't be undone." (only the kinds present) — **Empty trash** (danger).
  - The retention line under the heading: "Items are deleted for good after N days." with **Change** linking `settings#publishing` for a `settings.manage` holder.

- [ ] **Step 1: Failing tests.** Integration: tab counts equal `TrashController.badge_count` per type and respect the viewer's rights; the who-label in its four cases (one query for the listed rows' events, not one per row); the three retention tags (travel to the last day for "TODAY"); the subpage sentence names only readable pages; inline Restore under; the disabled Delete now reason; the dialog's sentence per mix; the Change link's permission. `trash_visibility_test.rb` unchanged in meaning.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Build.**
- [ ] **Step 4: System test** (`trash_test.rb`): switch tabs (counts shown), **Restore under** a chosen parent, **Delete now…** → confirm, **Empty trash…** → confirm → the empty state.
- [ ] **Step 5: Run** the trash tests. PASS.
- [ ] **Step 6: Commit.** `feat: trash with counted tabs, who and when, retention tags and inline restore-under`

---

### Task 15: Audit log and the event page

**Files:**
- Create: `app/models/audit/sentence.rb`, `app/components/admin/audit_screen/{toolbar,day_list,row,event_header,changes}_component.{rb,html.erb}`, tests, previews
- Modify: `app/controllers/admin/audit_events_controller.rb`, `app/views/admin/audit_events/{index,show}.html.erb`, `app/helpers/admin/audit_events_helper.rb`, `app/queries/dashboard/activity.rb` (uses `Audit::Sentence` for its sentences), tests (`audit_events_test.rb`, dashboard tests)
- Delete: `app/components/admin/audit_changes_component.*`

**Interfaces:**
- Consumes: Task 2 (`via_label`, `occurrences`, `Admin::ChannelChipComponent`).
- Produces:
  - `Audit::Sentence.for(event, viewer:)` → `Sentence(parts:, subject_label:, subject_path:, security:)` — one English sentence per action name recorded anywhere in `app/` (inventory B §4.2 lists them; the test below fails on a new action without one), "You" when the event's user is the viewer, the subject linked only when the viewer may open it (else plain text, never a 403 link), a generic fallback "<actor> did <action> on <subject>" for a plugin's action. `security: true` for `session.failed`, `access.denied`, `user.owner_changed`, `token.issued`, `token.revoked`, `user.deleted`, `group.deleted` (their key is drawn in warn ink).
  - **List:** events grouped under day headers ("Today", "Yesterday", "Mon 5 Oct"), each row: time ("16:05", or "16:05–16:31" for a coalesced span), avatar, the sentence ("… via <token name>" for a token), the channel chip, and the raw key in mono at the right; the row links to the event page. **Load older** stays (D23) and repeats a day header only when the day changes.
  - **Toolbar:** one row of drop-downs — User, Action, Type, Channel (All / Admin / MCP / Other), **Date** (Today, Last 7 days, Last 30 days, Last 90 days, Custom…; Custom shows From and To inline) — applied on change. `subject_type` + `subject_id` still filter (the editors' Activity links), shown as a removable chip "About this <type>" instead of a text field.
  - **Event page:** header with the sentence, "16:05–16:31 · 12 saves" from `occurrences`, the actor, channel chip, request id and IP in mono; then the field changes — a text field as the word diff (`Translations::SourceDiff`, the reference card's del/ins style with the hidden "Removed:" / "Added:" cues), grouped per language ("2 FIELDS · DEUTSCH"); a rich-text or digest-only change reads "Changed"; other values as old → new. **Older event** / **Newer event** follow the list's order with the current filters.

- [ ] **Step 1: Failing tests.** `Audit::Sentence`: one test per action family, "You", an unreadable subject as plain text, a deleted subject by its stored label, the token "via"; a test that greps `app/` for `record_event("…")` / `Audit.record("…")` action names and fails for any without a sentence. Integration: day headers across a day boundary in the site zone; the span and the saves count; each filter and preset (`range=7` etc., `custom` with dates); the subject chip; the channel filter; the event page's diff for a title change in two languages; `audit.view` required (403), the editors' Activity link still lands filtered.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Build.** `Dashboard::Activity` takes its sentences from `Audit::Sentence` so the feed and the log can't word the same event differently (its `ACTIONS` allow-list and SQL scoping stay).
- [ ] **Step 4: Run** the audit and dashboard tests. PASS.
- [ ] **Step 5: Commit.** `feat: audit log with day headers, human sentences, a filter row with date presets, and a diffing event page`

---

### Task 16: System status, Change password, the preview banner

**Files:**
- Create: `app/components/admin/system_check_row_component.{rb,html.erb}`, `app/components/public/preview_bar_component.{rb,html.erb}` (+ tests, previews)
- Modify: `app/models/setup/system_check.rb`, `app/views/admin/system_status/show.html.erb`, `app/views/setup/_system_check_results.html.erb`, `app/javascript/controllers/admin/clipboard_controller.js` (a `text` value beside `url`), `app/views/admin/accounts/edit.html.erb`, `app/services/users/update_password.rb` (the message), `app/javascript/controllers/password_field_controller.js` (strength sentences), `app/views/layouts/application.html.erb`, `app/views/layouts/public/_preview_banner.html.erb`, `app/assets/tailwind/themes/default/*` (two tokens), tests

**Interfaces:**
- Produces:
  - `Setup::SystemCheck::Result = Data.define(:label, :status, :message, :command, :docs)` (`command` and `docs` nil for most). The mail warning's message becomes "Password reset by email isn't configured." with `command: %(bin/rails runner 'User.find_by(email_address: "you@example.com").update!(password: "a new password")')`.
  - **System status** (900px): h1, the summary "3 of 4 checks passed · last run 17:30" (site zone), **Run checks again**; warnings first; each row a status chip (Warning: warn dot and border; OK: ok dot), the name, the message, and — when there is a command — a code box with **Copy**. The setup wizard's system-check step renders the same rows.
  - **Account screen** (D25): the name form as today, then the password card (560px): subtitle "You'll stay signed in here. Other sessions are signed out."; a wrong current password shows under that field as "That's not your current password." (and in the summary); the meter's line reads "Too short. Use 12 or more characters." / "Fair. A few unrelated words work well." / "Good." / "Strong."; "Forgot your current password?" links the reset flow from the card's footer row.
  - **Preview banner** (D26): a 36px bar fixed at the top of the public layout, outside the content column, the page pushed down by the same height: "PREVIEW · <title> · <Draft|Scheduled|Live> · <language's own name>", **Edit** (the record's editor in that language) and **Exit preview**. Colours from two new theme tokens (`--th-preview-bg`, `--th-preview-ink`) that are the same in light and dark.

- [ ] **Step 1: Failing tests.** System check: the mail result's fields; the summary's count and time; warnings sorted first; the Copy button carries the command. Accounts: the per-field message and the new subtitle; the name form still saves. `password_field_test.rb`: the four sentences. Preview: the bar's text for a draft page in German, the Edit link with `locale`, Exit preview's two destinations, the headers (`no-store`, `noindex`) kept; the design-rules test still passes for the layout files.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Build** the three.
- [ ] **Step 4: Run** `test/models/setup`, `system_status_test.rb`, the setup tests, `accounts_test.rb`, `password_field_test.rb`, `save_bar_test.rb`, `preview_test.rb`, `test/lib`. PASS.
- [ ] **Step 5: Commit.** `feat: system status with a summary and copyable commands; change-password copy; the preview bar`

---

### Task 17: Mind graph

**Files:**
- Create: `app/components/admin/mind_graph_legend_component.{rb,html.erb}` (+ test, preview)
- Modify: `app/queries/post_graph.rb` (or wherever `PostGraph` lives — inventory B §5), `app/controllers/admin/mind_graph_controller.rb`, `app/views/admin/mind_graph/show.html.erb`, the graph's Stimulus controller, tests (`post_graph_test`, `mind_graph_test`, `ai_assistant_and_graph_test.rb`)

**Interfaces:**
- Produces (D27):
  - `PostGraph` data: post nodes `{ id, title, type, colour_index, status, url }` (no hex colour), tag nodes `{ id: "tag-<id>", name, count }` for tags on at least two readable posts, edges `{ source, target, kind: "related" | "tag" }`. Read-scoped as today; trashed posts never appear.
  - Nodes are coloured by `--cs-cat-<colour_index>` through CSS classes (a retired type in `meta`); a draft or scheduled post is a ring, a live one filled; tag nodes are small squares in `meta`.
  - A **legend** beside the graph: one entry per content type present (dot + name), "Tag", "Draft or scheduled", and the two edge kinds; a **filter** — All, Related, Tags — that hides the other edge kind and the nodes left without an edge (client-side).
  - **Empty state** (in the box): "Link posts with Related posts, or give them shared tags, to see connections." when there are posts but no edges; "No posts yet." with none.
  - The box still fills the view and keeps every node and label inside it (round 1's fix).

- [ ] **Step 1: Failing tests.** `PostGraph`: tag nodes only for tags on ≥ 2 readable posts, tag edges, no node for an unreadable or trashed post, `colour_index` per type, no `color` key. Integration: the legend lists only present types; the empty states. System: the filter hides tag nodes and their edges; nodes stay inside the box after the simulation settles.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Build.**
- [ ] **Step 4: Run** the graph tests and `test/lib/admin_design_rules_test.rb` (no hex left in the JS). PASS.
- [ ] **Step 5: Commit.** `feat: mind graph coloured by type with tag nodes, a legend and a filter`

---

### Task 18: Sweep, docs and visual check

**Files:**
- Modify: `CLAUDE.md`, `docs/roadmap.md`, `docs/superpowers/specs/2026-10-03-cs-studio-design-pass-design.md` (status of round 3), `test/lib/admin_design_rules_test.rb` (pin what this round removed)

- [ ] **Step 1: Sweep.** `git grep` for what this round removed must return nothing outside docs history: `SettingsFormComponent`, `admin/languages/index`, `AuditChangesComponent`, `via an API token`, `API token #`, the old leave-dialog labels, `settings-save-status`. No dead Stimulus controller, importmap pin, route, partial, preview or CSS left behind. Every component added this round has a preview and a test.
- [ ] **Step 2: `CLAUDE.md`.** Rewrite what this round made false — verify each sentence against the code: the save rule (Settings on the footer; what the leave guard covers; `admin--pending-lock`), Settings and Languages (one form, sections by right, `Locales::MakeDefault`, the key's own endpoint and date), Media (panel, filters, drop upload, picker), Groups and Users (rows, scopes, locked and read-only states, `Users::Manageability`, the owner endpoint), tokens (`name`, `actor_label`, the AI assistant flow), Tags (`Tags::Merge`), Trash rows, the Audit log (`Audit::Sentence`, `occurrences`), System status, the preview bar, the Mind graph, the controller list, the new `…Screen` namespaces. Describe the system as it is; no history.
- [ ] **Step 3: Roadmap.** Mark the design pass done. Close the rows this round resolves (the leave-guard gaps, language drag reorder, Languages fallback ticks, "via an API token", the trash/audit items). Add a row for each interim state the round leaves — collected from the task reports — in the existing format.
- [ ] **Step 4: Static checks.** `bin/rubocop`, `bin/brakeman`, `bin/importmap audit`, `bin/bundler-audit`: clean, or fix what this round introduced.
- [ ] **Step 5: Full suites.** `PGGSSENCMODE=disable bin/rails test`; `bin/rails tailwindcss:build`; `PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system`, twice. PASS.
- [ ] **Step 6: Visual check.** Screenshot every screen this round touched, light and dark, at 1400 and 1100 wide, into `tmp/screenshots/cs-studio-after-round-3/` and compare with the mockups; report differences as a table (screen, what differs, severity). Fix only what is plainly wrong; list the rest.
- [ ] **Step 7: Commit.** `docs: CS Studio after round 3` (and a `chore:` commit for the sweep if it changed code).
