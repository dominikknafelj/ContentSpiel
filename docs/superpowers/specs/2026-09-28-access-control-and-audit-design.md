# Access control and audit log

Sub-project 5 of the own-admin roadmap. The design was approved in brainstorming on 2026-09-28. This document is the binding spec for the implementation plan.

## 1. Purpose

- **Permissions.** Who may do what in CS Studio and through MCP is decided by **groups** that carry **grants** from a code-defined permission registry.
  - Grants can be scoped by content type, page-tree branch and "own".
  - Permissions govern reading as well as writing.
- **Audit log.** Every change (and every refused attempt, sign-in and sign-out) is recorded append-only, with:
  - who made it, through which channel, and when;
  - the changed fields;
  - a copy of the record after the change.
- **Seams for later.**
  - Plugins can register permissions and subscribe to audit events.
  - Phase 3 approval chains will assign steps to these groups.
  - Phase 3 versioning will build on the audit copies.

**Success:**
- An author cannot edit someone else's post, publish, or open Users, whether in CS Studio or through a limited MCP token.
- A group limited to one page branch sees and edits only that branch.
- Every change can be traced to a person, channel, time and field-level diff.

## 2. Decisions (from brainstorming)

| Topic | Decision |
|---|---|
| Model | **Groups carry permissions** (Craft/TYPO3 style). Users belong to any number of groups. The four roles become seeded groups. **Owner is a protected user flag**, not a group. |
| Granularity | Actions, plus scopes by **content type**, **page-tree branch** and **own** (posts). |
| Audit detail | Action, changed fields (old → new), **and a full copy of the record after the change**. Browsing and restoring versions is Phase 3. |
| MCP tokens | A token is limited to **one group**. It may do what both that group **and** its user allow. |
| Reading | Permissions also filter **reading** everywhere: lists, tree, search, link targets, mind graph, preview, MCP. |
| Architecture | A **permission registry plus one central checker**, in-house. Code is namespaced by domain: `AccessControl::` and `Audit::`. |

## 3. `AccessControl`

### 3.1 Permission registry

`AccessControl::Permissions` works like the other registries (`ContentModel::Registry`):
- **Definitions** are frozen and reset/re-registered in `config/initializers/types.rb`'s `to_prepare`.
- **Names:** plugin permissions must be `owner/name`; built-in keys are unprefixed. A duplicate raises `AccessControl::DuplicatePermission`.
- **Each permission declares:**
  - `key`, e.g. `posts.edit`;
  - `label` and `area`, used by the group editor;
  - `subject`: `Post`, `Page`, `ContentBlock`, or `nil` for admin-area permissions;
  - `action`: `read`, `create`, `edit`, `publish`, `move`, `delete` or `manage`;
  - `scopes`: a subset of `content_type`, `branch` and `own`.

`AccessControl::BuiltIns.register` defines:

| Area | Keys | Scopes |
|---|---|---|
| Posts | `posts.read`, `posts.create`, `posts.edit`, `posts.publish`, `posts.delete` | `content_type`, `own` |
| Pages | `pages.read`, `pages.create`, `pages.edit`, `pages.publish`, `pages.move`, `pages.delete` | `branch` |
| Content | `tags.manage`, `media.upload` | — |
| Administration | `settings.manage`, `languages.manage`, `users.manage`, `groups.manage`, `tokens.manage` (other people's tokens), `system_status.view`, `audit.view` | — |

**Content-type scope values:**
- The `content_type` choices are read live from `ContentTypes`, so plugin types are listed automatically.
- A grant scoped to a content type that is later unregistered simply never matches. It is not an error.

**Blocks** follow their page's `pages.*` permissions (`ContentBlocks::*` checks `pages.edit` on the owning page). Blocks owned by a post, via the polymorphic owner, follow `posts.edit`.

### 3.2 Data

| Table / column | Columns and rules |
|---|---|
| `access_control_groups` | `name` (unique, case-insensitive), `description`, `built_in` (boolean). Built-in groups can be edited but not deleted. |
| `access_control_memberships` | `user_id`, `group_id`, unique pair; cascade on user or group delete. |
| `access_control_grants` | `group_id`, `permission` (string key), `scope` (jsonb, default `{}`, e.g. `{"content_types": ["blog"], "page_ids": [12], "own": true}`). Validated against the registry: the key must exist and the scope keys must be among the permission's `scopes`. |
| `users.owner` | boolean, default false. At least one owner must always exist. Only owners may change `owner`. |
| `api_tokens.group_id` | foreign key to `access_control_groups`, not null. On group delete the token is revoked; the delete confirmation says so. |
| `posts.author_id` | foreign key to `users`, nullable. Set to the actor's user on create. On user delete it is nullified, so "own" no longer matches for anyone. |

Models: `AccessControl::Group`, `AccessControl::Membership`, `AccessControl::Grant`.

### 3.3 Actors and decisions

`AccessControl.allowed?(actor, action_key, record = nil)` → Boolean.
`AccessControl.scope(actor, action_key, relation)` → the relation filtered to what the actor may act on.

| Actor | Rule |
|---|---|
| `User` with `owner` | Allowed everything. |
| `User` | Allowed if any grant of any of their groups matches. |
| `ApiToken` (active) | Allowed if a grant of the token's group matches **and** the token's user is allowed, i.e. the intersection. |
| Revoked token, nil user, unknown actor | Denied. |
| `nil` actor with channel `:setup`, `:console` or `:system` | Allowed: trusted code paths. The setup wizard is already gated by its setup token. |

**Matching a grant:**
- The permission key must match.
- Every scope key set on the grant must match (AND):
  - `content_types`: the record's `content_type` is in the list;
  - `page_ids`: the page (or the block's owning page) is at or below one of the listed roots, via `page_hierarchies`;
  - `own`: the post's `author_id` equals the actor's user id.
- Grants combine with OR.

**Implication:** any write key for a subject (`create`, `edit`, `publish`, `move`, `delete`) also satisfies `read` within the same scope.

**Action rules:**
- **Create post:** `posts.create` scoped to its content type. There is no record yet, so `own` always matches on create.
- **Create page:** `pages.create` on the **parent's** branch.
- **Move page:** `pages.move` on the page **and** `pages.create` on the target parent's branch.
- **Delete page:** `pages.delete` on the page. Deleting a page with children is already refused.
- **Editing a published record requires `publish`** in addition to `edit`. This is an interim rule: autosave writes live content (known interim state until pending revisions, Phase 3).
- **Publishing, unpublishing or scheduling** requires `publish`.
- **Changing `author_id`** requires `posts.edit` without an `own` scope.
- **Users:**
  - `users.manage` covers creating, editing and deleting other users and setting group memberships.
  - Any user may change their own password.
  - `owner` changes are owner-only. The last owner can't be demoted or deleted; this replaces "last user", keeping the lock from Task 8's fix wave.
- **Tokens:**
  - Anyone signed in may issue and revoke **their own** tokens.
  - A token's group must be one whose permissions the user holds. Owners may choose any group; others may choose a group only if every grant in it is also allowed to them.
  - `tokens.manage` covers other people's tokens.
- **Groups:** `groups.manage`. A non-owner can't grant a permission they don't hold themselves (no privilege escalation), and can't edit a group they're a member of if doing so would widen their own permissions.

**Scopes for reading** (`AccessControl.scope`):
- `scope` builds one SQL condition (an OR of the matching grants) for `Post`, `Page` and `ContentBlock`; branches go through a `page_hierarchies` subquery.
- It is used by:
  - CS Studio lists (posts, pages tree, tags usage);
  - link-target search, related-post search and the mind graph (`PostGraph`);
  - the `/preview` controller;
  - MCP list/get tools.
- **The page tree** also returns the ancestors of every readable page, marked `context_only`. They are rendered greyed out, can't be opened, and have no actions.
- **Not found, not forbidden:** a record outside the actor's read scope is answered as not found (404 in CS Studio and preview, a "not found" tool error in MCP), so its existence isn't disclosed.

**Performance:**
- The actor's grants are loaded once per request and memoised on `Current`.
- `allowed?` over a list uses the preloaded grants plus the closure-table ancestors, loaded in one query per page set. There are no per-row queries.

### 3.4 Enforcement points

- **Services:** `ApplicationService#authorize!(action_key, record)` calls `AccessControl.allowed?(Current.actor, …)`.
  - On denial it returns `failure(record, "You don't have permission to <label>")` and records `access.denied` (§4.3).
  - Every service calls it before writing.
- **Direct writes are removed.** Every controller that still writes without a service gets one, e.g. `Settings::Save`, `MediaAssets::Create`, `StarterContent` via a service, and `Users::UpdatePassword`. The plan inventories them with a grep for `.save`, `.update` and `.destroy` in `app/controllers`.
- **Controllers:**
  - `Admin::BaseController` gains `require_permission(key)` for admin areas, which renders a 403 page.
  - Record controllers load records through `AccessControl.scope`, which gives a 404 when out of scope.
  - The sidebar and buttons use a helper `can?(key, record = nil)`.
- **MCP:** tools set `Current.actor` to the token (as today), use `AccessControl.scope` for reads, and rely on the services for writes.
  - Refusals are tool errors carrying the message.
  - The server instructions/description state the token's group name.

## 4. `Audit`

### 4.1 Data

`audit_events` (model `Audit::Event`):

| Column | Contents |
|---|---|
| `action` | e.g. `post.updated` (string, indexed) |
| `actor_type` / `actor_id` | the `User` or `ApiToken` |
| `user_id` | the acting user, denormalised; nil for system/console/setup |
| `channel` | `admin`, `mcp`, `setup`, `console` or `system` |
| `subject_type` / `subject_id` | the record (nullable for area-level events) |
| `subject_label` | the title/name at the time, so the event still reads well after deletion |
| `field_changes` | jsonb `{field => [old, new]}` (not `changes`, which is an ActiveRecord dirty-tracking method) |
| `snapshot` | jsonb, the full record after the change (§4.2) |
| `metadata` | jsonb, event-specific extras (e.g. the denied permission, the failed sign-in email) |
| `request_id`, `ip` | request context |
| `occurred_at` | when the event started |
| `last_occurred_at` | when it last grew by coalescing |

Indexes: `(subject_type, subject_id, occurred_at)`, `(user_id, occurred_at)`, `(action, occurred_at)`.

**Append-only:**
- The model rejects updates and destroys, with one exception: the coalescing extension in §4.2.
- A DB trigger raises on `DELETE` and on `UPDATE` of any column other than `field_changes`, `snapshot` and `last_occurred_at`.

### 4.2 Recording

`Audit.record(action, subject: nil, field_changes: {}, snapshot: nil, metadata: {})`:
- **Context:** it reads the actor, channel, request id and IP from `Current`. `ApplicationService#record_event` delegates to it.
- **Transaction:** it writes inside the caller's transaction, so a rolled-back save leaves no event.
- **Coalescing:**
  - An `*.updated` event for the same subject by the same actor within **10 minutes** of the previous one's `last_occurred_at` extends that event: `field_changes` merged (the original old value, the latest new value), `snapshot` replaced, `last_occurred_at` bumped.
  - `access.denied` events coalesce the same way, per actor, permission and subject.
  - All other actions never coalesce.
- **Snapshots** come from `Audit::Snapshot.for(record)`, one serializer per subject type:
  - posts and pages: saved attributes, translations, typed fields, tags, relations, block ids in order;
  - blocks: attributes, translations, settings;
  - users: email, owner flag, group ids;
  - groups: name and grants;
  - tokens: name, user, group, `revoked_at`;
  - settings: the site settings.
- **Never stored:** password digests, token digests or raw tokens, or any attribute matching `Rails.application.config.filter_parameters`. Rich-text bodies appear in `field_changes` as `"<locale> body"` → `{digest_before, digest_after}` and in the snapshot as the full document. The snapshot is the version basis for Phase 3.
- **Hook:** after the transaction commits, each new or extended event is published as `ActiveSupport::Notifications.instrument("audit.content_spiel", event:)`. That is the plugin hook.

### 4.3 Event catalogue

| Area | Actions |
|---|---|
| Posts | `post.created`, `post.updated`, `post.published`, `post.unpublished`, `post.scheduled`, `post.deleted` |
| Pages | `page.created`, `page.updated`, `page.published`, `page.unpublished`, `page.moved`, `page.deleted` |
| Blocks | `block.created`, `block.updated`, `block.reordered`, `block.deleted` |
| Tags, media | `tag.renamed`, `tag.deleted`, `media.uploaded` |
| Settings, languages | `settings.updated`, `language.enabled`, `language.disabled`, `language.configured` |
| Users, groups, tokens | `user.created`, `user.updated`, `user.deleted`, `user.owner_changed`, `group.created`, `group.updated`, `group.deleted`, `token.issued`, `token.revoked` |
| Other | `starter_content.added` |
| Sessions | `session.created`, `session.destroyed`, `session.failed` (email in `metadata`, no user) |
| Access | `access.denied` (permission and subject in `metadata`) |

Adding a service without an event is caught by a test that walks every `ApplicationService` subclass (§7).

## 5. CS Studio

- **Groups module** (`groups.manage`):
  - A list with member counts.
  - An editor with name, description, members, and every registry permission grouped by `area` as checkboxes.
  - A ticked scoped permission shows its scope controls:
    - a content-type multi-select;
    - an "own only" checkbox;
    - a page-branch picker (tree with checkboxes, storing branch root ids).
  - Delete uses the existing confirm-dialog pattern and names the tokens it will revoke.
- **Users module:** adds group checkboxes and an Owner toggle (owners only; disabled for the last owner). A "Change my password" screen is reachable by every user from the account menu.
- **AI assistant tokens:**
  - The create form requires a group, defaulting to **Read only**, and lists only the groups the user may assign.
  - The list shows each token's group.
  - Everyone sees and manages their own tokens; `tokens.manage` shows everyone's.
- **Audit log module** (`audit.view`):
  - A paginated list, newest first: time, who (user and token name), channel, action, and a subject link if the record still exists.
  - Filters: user, action, subject type, subject, date range.
  - The event page shows the changes table (old/new; bodies as "changed") and a collapsible pretty-printed snapshot.
  - Post, page and user editors get an **Activity** link that opens the log filtered to that record; it is visible with `audit.view`.
- **Everywhere:**
  - Sidebar modules and action buttons (Publish, Delete, Move, Add child page, Add block, Upload) are shown only when `can?`.
  - A readable but not editable record shows a **View only** badge. Its fields are disabled and autosave is not attached.
  - The 403 page matches the product layout.

**Seeded groups:**

| Group | Grants |
|---|---|
| Admin | every built-in permission (unscoped) |
| Editor | `posts.*`, `pages.*` (unscoped), `tags.manage`, `media.upload` |
| Author | `posts.read`, `posts.create`, `posts.edit` (own), `media.upload`, `pages.read` |
| Read only | `posts.read`, `pages.read` |

Owners are users with the flag.

## 6. Migration, setup and seeds

- **New tables and columns** per §3.2 and §4.1.
- **Data migration:**
  - seed the four groups (idempotent, by name);
  - every existing user becomes an owner;
  - every existing token gets the Admin group;
  - every existing post gets the first owner (lowest id) as `author_id`.
- **Setup wizard:** the account it creates is an owner. The wizard's MCP-token step assigns the Admin group; the wizard explains that the token can be narrowed later.
- **Dev seeds:** also create `author@example.com` in the Author group with a dev password, and print it with the existing seed output.

## 7. Testing

- **`AccessControl` unit tests:**
  - each scope type;
  - AND within a grant, OR across grants;
  - read implied by writes;
  - owners;
  - token intersection;
  - revoked tokens;
  - system actors;
  - create, move and published-edit rules;
  - privilege-escalation guards for groups and token groups.
- **`AccessControl.scope`:** SQL correctness for combined scopes, branch subqueries and tree context ancestors, with no N+1 (query-count assertions).
- **Service table test:** every `ApplicationService` subclass calls `authorize!` and records at least one event (a guard against forgetting either).
- **`Audit` tests:**
  - coalescing window and keys;
  - snapshot and changes contents;
  - secrets never present;
  - rollback leaves no event;
  - the append-only trigger;
  - the notification hook fires after commit.
- **Integration (CS Studio)** per seeded group: sidebar visibility, 403 vs 404, filtered lists and tree, view-only records, token group choices.
- **MCP** with a Read-only token and an Author token: reads filtered, forbidden writes are tool errors, and allowed writes are audited with channel `mcp` and the token as actor.
- **System tests:** the group editor with scope pickers, and an author's editing session producing one coalesced audit event.

## 8. Known interim states and seams

- **Editing a published record needs `publish`**, because autosave writes live content. This goes away with pending revisions (Phase 3).
- **Pages have no author**, so there is no "own" scope for pages.
- **Audit log:** no export or retention settings; it grows without limit.
- **Versioning:** snapshots exist, but there is no version browsing or restore (Phase 3 versioning builds on `audit_events.snapshot`).
- **Approval chains** (Phase 3) will reference `AccessControl::Group`; nothing here blocks them.
- **Not in scope yet:** 2FA, session lists and per-field permissions.

## 9. Out of scope

- Approval chains and releases.
- Version restore.
- Audit export and retention.
- 2FA.
- Session management UI.
- Per-field permissions.
- Page authorship.
- Admin-defined (non-code) permissions.

## Amendments (during implementation)

- **Publish-only changes need only `publish`** (final fix wave). A save of a stored post or page that asks for nothing but a publish-state change (`published`/`published_at`, no translations, no other attribute) is judged on `posts.publish`/`pages.publish` alone, not `edit` as well, so a "Publishers" group (read + publish) can publish, unpublish and schedule from CS Studio's header buttons and through MCP's `update_post(published:)`. Every other change keeps §3.3's rules (edit, plus publish when already published).
- **`audit.view` is not content-scoped** (final fix wave). The log's events carry snapshots of every record, whatever else the viewer may read, so the permission is labelled "View audit log (all content)" and should be granted accordingly.
- **Managing a group needs its rights** (final fix wave). Taking members out of a group, removing or narrowing its grants, deleting it, or changing a user's membership in it requires, for a non-owner, every grant the group holds as it stands (`AccessControl.can_manage_group?`). Renaming a group doesn't.
- **A token is never an owner** (final fix wave). Wherever an owner is waved through (owner flags, owner accounts, granting and assigning groups), an `ApiToken` actor, even an owner's, is judged on its effective rights: its group intersected with its user.
- **The public site runs on an untrusted `:public` channel** (final fix wave), so a nil actor there is denied, never mistaken for the trusted console case.
