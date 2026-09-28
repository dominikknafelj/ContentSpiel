# Access Control and Audit Log Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give CS Studio and MCP permissions and an audit log:
- group-based permissions from a code registry, scoped by content type, page branch and "own", enforced in services and for reading everywhere;
- an append-only audit log with field changes and snapshots.

**Architecture:**
- **`AccessControl::`** (app/models/access_control/) holds the permission registry, the group, membership and grant models, and one checker (`AccessControl.allowed?`, `AccessControl.scope`).
- **`Audit::`** (app/models/audit/) holds `Audit::Event`, `Audit.record` and the snapshot serializers.
- **`ApplicationService`** calls both through its existing `authorize!` / `record_event` seams.
- **Controllers, MCP tools and the page tree** read through `AccessControl.scope`.

**Tech Stack:** Rails 8.1, Postgres (jsonb, closure table `page_hierarchies`, a PL/pgSQL trigger), Minitest + fixtures, Capybara system tests (scripted `press` helper, `await_admin_controllers`), ViewComponent + Lookbook, Hotwire, importmap.

**Spec:** `docs/superpowers/specs/2026-09-28-access-control-and-audit-design.md`. Read §3–§6 before any task.

## Global Constraints

**Namespaces**
- Code lives in the `AccessControl::` and `Audit::` namespaces under `app/models/access_control/` and `app/models/audit/`. Services stay in `app/services/<plural>/`.
- Tables: `access_control_groups`, `access_control_memberships`, `access_control_grants`, `audit_events`. New columns: `users.owner`, `api_tokens.group_id`, `posts.author_id`.

**Permissions**
- **Built-in keys** (exact):
  - posts: `posts.read`, `posts.create`, `posts.edit`, `posts.publish`, `posts.delete`;
  - pages: `pages.read`, `pages.create`, `pages.edit`, `pages.publish`, `pages.move`, `pages.delete`;
  - content: `tags.manage`, `media.upload`;
  - administration: `settings.manage`, `languages.manage`, `users.manage`, `groups.manage`, `tokens.manage`, `system_status.view`, `audit.view`.
- **Grant scope** is jsonb, with keys limited to `content_types` (array of strings), `page_ids` (array of integers), `own` (boolean).
- **Plugin permission names** must be `owner/name`. A duplicate raises `AccessControl::DuplicatePermission`.
- **Seeded groups** (exact names): `Admin`, `Editor`, `Author`, `Read only`.
- **Denial message:** `"You don't have permission to #{permission.label.downcase}"`.

**Audit**
- **Changes column** is named `field_changes`, never `changes`.
- **Coalescing window** is exactly 10 minutes, measured from `last_occurred_at`.
- **Notification name** is `audit.content_spiel`, published after commit.

**Process and conventions**
- The code paths for setup, console and system actors (a nil actor with channel `:setup`, `:console`, `:system`, or nil) are allowed.
- Commits follow conventional commits and end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never skip hooks.
- Long, load-bearing comments are the codebase norm; explain non-obvious invariants where they are enforced.
- Before each commit, run `PARALLEL_WORKERS=1 bin/rails test` and `bin/rubocop`. Tasks touching UI also run `bin/rails test:system`.
- The test DB is shared, so only one agent runs tests at a time.

## Review Focus

1. **Token privilege escalation.** A non-owner creates a token with a group that holds permissions they lack, or edits a group they belong to so that it widens their own rights. Expected: refused with a permission message (Tasks 3, 8).
2. **Out-of-scope record by id.** An author opens `/cs-studio/posts/<someone else's id>`, calls MCP `get_post` for a page outside their branch, or previews it. Expected: not found, not forbidden, and not the content (Tasks 7, 10).
3. **Stale grants.** A grant scoped to a page branch whose root page was deleted, or to a content type no longer registered. Expected: it matches nothing, is never an error, and the group editor still loads (Tasks 3, 8).
4. **Autosave of a record the user may only read.** Nothing is sent and nothing is audited. A forged PATCH gets a permission failure plus one coalesced `access.denied` event (Tasks 6, 7).
5. **Secrets in the audit log.** A user event, a token event or a failed sign-in never contains a password digest, token digest, raw token or password (Tasks 5, 6).

---

### Task 1: The permission registry

**Files:**
- Create: `app/models/access_control.rb` (module plus errors), `app/models/access_control/permissions.rb`, `app/models/access_control/permission.rb`, `app/models/access_control/built_ins.rb`
- Modify: `config/initializers/types.rb` (reset and register in `to_prepare`)
- Test: `test/models/access_control/permissions_test.rb`

**Interfaces:**
- **Produces:**
  - `AccessControl::Permissions.register(key, label:, area:, subject: nil, action:, scopes: [])` → `AccessControl::Permission` (Data: `key label area subject action scopes`), plus `.fetch(key)`, `.find(key)`, `.all`, `.keys`, `.reset!`, `.for_subject(klass)`.
  - `AccessControl::DuplicatePermission`, `AccessControl::UnknownPermission`.
  - `AccessControl::BuiltIns.register`.
  - Content types are read live, not snapshotted: `AccessControl::Permissions.content_type_choices` → `ContentTypes.names`.

- [ ] **Step 1: Write the failing tests**

```ruby
require "test_helper"

class AccessControl::PermissionsTest < ActiveSupport::TestCase
  teardown { Rails.application.reloader.prepare! }

  test "built-ins are registered with areas, subjects and scopes" do
    edit = AccessControl::Permissions.fetch("posts.edit")
    assert_equal "Posts", edit.area
    assert_equal Post, edit.subject
    assert_equal :edit, edit.action
    assert_equal %i[content_type own], edit.scopes
    assert_equal %i[branch], AccessControl::Permissions.fetch("pages.move").scopes
    assert_nil AccessControl::Permissions.fetch("users.manage").subject
  end

  test "every spec key exists" do
    keys = %w[posts.read posts.create posts.edit posts.publish posts.delete
              pages.read pages.create pages.edit pages.publish pages.move pages.delete
              tags.manage media.upload settings.manage languages.manage users.manage
              groups.manage tokens.manage system_status.view audit.view]
    assert_equal keys.sort, AccessControl::Permissions.keys.sort
  end

  test "plugin permissions must be prefixed and unique" do
    AccessControl::Permissions.register("shop/orders.manage", label: "Manage orders", area: "Shop", action: :manage)
    assert_raises(AccessControl::DuplicatePermission) { AccessControl::Permissions.register("shop/orders.manage", label: "x", area: "Shop", action: :manage) }
    assert_raises(ArgumentError) { AccessControl::Permissions.register("Bad Key", label: "x", area: "x", action: :manage) }
  end

  test "unknown scope names are rejected at registration" do
    assert_raises(ArgumentError) { AccessControl::Permissions.register("shop/x.read", label: "x", area: "x", action: :read, scopes: [ :galaxy ]) }
  end
end
```

- [ ] **Step 2: Run** `bin/rails test test/models/access_control/permissions_test.rb`. Expect it to fail (uninitialized constant).
- [ ] **Step 3: Implement.**
  - **Key format:** `/\A([a-z][a-z0-9_]*\/)?[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\z/`.
  - **Allowed scopes:** `%i[content_type branch own]`.
  - **Areas:** the `area` strings are `"Posts"`, `"Pages"`, `"Content"` and `"Administration"`.
  - **Labels** (used by the denial message): e.g. `posts.edit` → `"Edit posts"`, `pages.move` → `"Move pages"`, `users.manage` → `"Manage users"`.
  - **Initializer:** register in `config/initializers/types.rb` after the type registries: `AccessControl::Permissions.reset!` then `AccessControl::BuiltIns.register`, with a comment matching the file's existing style.
- [ ] **Step 4: Run** the test, then the full suite. Expect them to pass.
- [ ] **Step 5: Commit** with `git commit -m "feat: add the access control permission registry"`.

---

### Task 2: Groups, memberships, grants, owners and the data migration

**Files:**
- Create:
  - `db/migrate/<ts>_create_access_control.rb`: the three tables, `users.owner` (boolean, default false, null false), `api_tokens.group_id` (FK), `posts.author_id` (FK to users, nullable, `on_delete: :nullify`);
  - `db/migrate/<ts>_seed_access_control_groups.rb` (data migration; see Step 3);
  - `app/models/access_control/group.rb`, `membership.rb`, `grant.rb`, `app/models/access_control/seeds.rb` (`AccessControl::Seeds.ensure_built_in_groups!`).
- Modify:
  - `app/models/user.rb`: `has_many :memberships`, `has_many :groups, through:`. Replace `ensure_not_last_owner` with a real owner check that keeps the lock and `prepend: true`, and add `validate :at_least_one_owner` for demotion.
  - `app/models/api_token.rb`: `belongs_to :group, class_name: "AccessControl::Group"`; `ApiToken.generate!(user, group:)`.
  - `app/models/post.rb`: `belongs_to :author, class_name: "User", optional: true`.
  - `db/seeds.rb`.
  - `test/fixtures/users.yml`: `one` is an owner, `two` is not.
  - New fixtures: `test/fixtures/access_control/groups.yml` with the four groups, plus `grants.yml` and `memberships.yml`.
- Test: `test/models/access_control/group_test.rb`, `grant_test.rb`, additions to `test/models/user_test.rb`, `test/migrations/access_control_seed_test.rb`

**Interfaces:**
- **Produces:**
  - `AccessControl::Group` (`name`, `description`, `built_in`, `has_many :grants`, `has_many :users, through: :memberships`, `has_many :api_tokens`);
  - `AccessControl::Grant` (`permission`, `scope` Hash; `#permission_definition` → `AccessControl::Permission`; `#scope_content_types`, `#scope_page_ids`, `#scope_own?`);
  - `User#owner?`, `User#groups`;
  - `AccessControl::Seeds.ensure_built_in_groups!` → the Hash name→group, idempotent;
  - `AccessControl::Seeds::BUILT_IN` (the §5 table as data).

- [ ] **Step 1: Write the failing tests.** Cover each of these:
  - **Grant validity:** a grant with an unknown key is invalid; a grant whose scope has a key the permission doesn't allow (`page_ids` on `posts.edit`) is invalid; `content_types` must be an array of strings and `page_ids` an array of integers.
  - **Group names:** the name is unique case-insensitively.
  - **Built-in groups:** a built-in group can't be destroyed (`errors[:base]`), but its grants can change.
  - **Owners:** demoting or destroying the last owner fails; a second owner makes it possible; destroy is refused *before* dependents are touched (`prepend: true`); the lock takes `User.lock` inside the transaction (assert the SQL contains `FOR UPDATE` via `assert_queries_match`).
  - **Data migration:** run `ensure_built_in_groups!` twice and get four groups, not eight. Then run the backfill method (`AccessControl::Seeds.backfill!`) on a DB with users, tokens and posts. Expect: all users are owners, tokens are in Admin, and posts have the lowest-id owner as author.
- [ ] **Step 2: Run** the tests. They should fail.
- [ ] **Step 3: Implement.**
  - **The data migration** calls `AccessControl::Seeds.ensure_built_in_groups!` and `AccessControl::Seeds.backfill!` through lightweight SQL-safe models defined inside the migration where practical. If you call app models, comment why that's acceptable (greenfield; the plan's ruling).
  - **Group contents** come from spec §5 (Admin = every built-in key unscoped; Editor; Author with `posts.edit` `{own: true}`; Read only).
  - **`db/seeds.rb`:** also create `author@example.com` (password from the existing dev pattern), in Author, and print it.
- [ ] **Step 4: Run** `bin/rails db:migrate`, `db:test:prepare`, the new tests and the full suite. They should pass. Also run `bin/rails db:rollback STEP=2 && bin/rails db:migrate`; it should succeed.
- [ ] **Step 5: Commit** with `git commit -m "feat: add groups, grants, owners and post authors"`.

---

### Task 3: The checker — `AccessControl.allowed?`

**Files:**
- Create: `app/models/access_control/checker.rb`, `app/models/access_control/actor_grants.rb` (loads and memoises an actor's grants; for tokens, both the token-group grants and the user grants)
- Modify:
  - `app/models/access_control.rb`: `allowed?`, `permitted_groups_for(user)`, `can_assign_group?(user, group)`, `can_grant?(user, key, scope)`;
  - `app/models/current.rb`: `attribute :access_grants` memo.
- Test: `test/models/access_control/checker_test.rb`

**Interfaces:**
- **Consumes:** Tasks 1–2.
- **Produces:**
  - `AccessControl.allowed?(actor, key, record = nil, channel: Current.channel)` → Boolean;
  - `AccessControl.trusted?(actor, channel)`;
  - `AccessControl.can_assign_group?(user, group)` (spec §3.3 tokens rule);
  - `AccessControl.can_grant?(user, key, scope = {})` (no privilege escalation);
  - `AccessControl.page_branch_ids(page)`: the ancestor ids, including the page itself, via `page.self_and_ancestor_ids`.

- [ ] **Step 1: Write the failing tests** (table style where it helps). Each bullet names the grants it builds from fixtures:
  - **Owner and trusted actors:**
    - an owner is allowed any key;
    - a nil actor with channel `:setup`, `:console`, `:system` or nil is allowed;
    - a nil actor on `:admin` or `:mcp` is denied.
  - **Grant matching:**
    - a `posts.edit` grant with `{content_types: ["blog"]}` allows a blog post and denies a `now_update` post;
    - `{own: true}` allows a post whose `author_id` is the user and denies other posts;
    - a combined `{content_types: ["blog"], own: true}` needs both;
    - two grants, one blog and one `now_update`, allow both (OR);
    - `pages.edit` with `{page_ids: [branch_root.id]}` allows the root and a grandchild, and denies a sibling branch;
    - a block's permission follows its owning page (`ContentBlock` → `pages.edit` on `block.owner`), and a post-owned block follows `posts.edit` on the post.
  - **Implication and create:**
    - write implies read: a `posts.edit` grant allows `posts.read` in the same scope;
    - on create (`record` is a new post with `content_type` set), `own` matches;
    - `pages.create` is checked against the parent passed as `record.parent`.
  - **Tokens:**
    - a token whose group allows `posts.edit`, on a user who lacks it, is denied;
    - a user who has it, with a token group lacking it, is denied;
    - both having it is allowed;
    - a revoked token is denied.
  - **Stale scopes** (Review Focus 3): a grant `{page_ids: [deleted_id]}` matches nothing and doesn't raise; `{content_types: ["gone"]}` matches nothing.
  - **Escalation checks:**
    - `can_grant?` is false for a key or wider scope the user lacks and true for owners;
    - `can_assign_group?` is false when any grant in the group exceeds the user (Review Focus 1).
  - **Memoisation:** the grants are loaded once per request; assert with `assert_queries_count` across 20 `allowed?` calls.
- [ ] **Step 2: Run** the tests. They should fail.
- [ ] **Step 3: Implement.**
  - **Matching** follows spec §3.3 exactly.
  - **"Wider scope"** for `can_grant?`: the requested grant is covered if some grant the user holds for the same key has every scope key the requested one has, each at least as permissive. That means content_types ⊇, page_ids such that every requested root is at or below a held root, and an own-restricted held grant can't cover an unrestricted request. Document this in a comment.
  - **`Current.access_grants`** is keyed by actor.
- [ ] **Step 4: Run** the tests and the full suite. They should pass.
- [ ] **Step 5: Commit** with `git commit -m "feat: decide permissions from groups, scopes, owners and tokens"`.

---

### Task 4: Read scopes — `AccessControl.scope` and the tree context

**Files:**
- Create: `app/models/access_control/scoping.rb`
- Modify: `app/models/access_control.rb` (`scope`, `tree_visibility`)
- Test: `test/models/access_control/scoping_test.rb`

**Interfaces:**
- **Consumes:** Task 3's grant loading.
- **Produces:**
  - `AccessControl.scope(actor, key, relation)` → a relation (`relation.none` when nothing matches; the unscoped relation for owners and trusted actors). It supports `Post`, `Page` and `ContentBlock` relations, and `key` is a read or write key (write keys imply read, so `:read` filtering uses read and write grants).
  - `AccessControl.tree_visibility(actor)` → `{ readable: Set[page_ids], context: Set[ancestor ids not readable] }`.

- [ ] **Step 1: Write the failing tests:**
  - Each scope type as SQL, compared against the result of `allowed?` for every fixture record (property-style: `scope(actor, "posts.read", Post.all).to_a.sort == Post.all.select { allowed?(…) }.sort`), for four actors: an author with own blog; an editor branch-limited to one subtree; a token intersection; and read only.
  - Blocks via their owning page or post.
  - `tree_visibility` returns the ancestors of a readable deep page as context, not readable.
  - Query count: `scope` issues at most one extra query for loading grants (memoised). `tree_visibility` for 200 pages makes a constant number of queries.
- [ ] **Step 2: Run** the tests. They should fail.
- [ ] **Step 3: Implement.**
  - Build `OR`-ed Arel or SQL fragments per grant:
    - `content_type IN (...)`;
    - `author_id = ?`;
    - `id IN (SELECT descendant_id FROM page_hierarchies WHERE ancestor_id IN (...))`.
  - For the token intersection, apply both the user's and the group's condition sets with AND.
  - Use bind parameters only, never interpolation.
- [ ] **Step 4: Run** the tests and the full suite. They should pass.
- [ ] **Step 5: Commit** with `git commit -m "feat: filter reads by permission, including the page-tree context"`.

---

### Task 5: The audit log

**Files:**
- Create:
  - `db/migrate/<ts>_create_audit_events.rb`: the table per spec §4.1, the indexes, and a PL/pgSQL trigger `audit_events_append_only` that raises on DELETE and on UPDATE of any column except `field_changes`, `snapshot` and `last_occurred_at`. Create it with `execute` in reversible `up`/`down`. `schema.rb` can't carry triggers; Step 3 says how fresh databases get it.
  - `db/triggers/audit_events_append_only.sql` and `lib/tasks/db_triggers.rake`.
  - `app/models/audit.rb` (`Audit.record`), `app/models/audit/event.rb`, `app/models/audit/snapshot.rb` (serializers per subject), `app/models/audit/coalescer.rb`.
- Modify:
  - `app/services/application_service.rb`: `record_event(action, subject: nil, field_changes: {}, metadata: {})` delegates to `Audit.record`, and snapshots via `Audit::Snapshot.for(subject)`;
  - `app/models/current.rb`: `attribute :request_id, :ip_address`;
  - `app/controllers/application_controller.rb` and `app/controllers/mcp_controller.rb`: set `Current.request_id` and `Current.ip_address`.
- Test: `test/models/audit/event_test.rb`, `test/models/audit/record_test.rb`, `test/models/audit/snapshot_test.rb`

**Interfaces:**
- **Produces:**
  - `Audit.record(action, subject: nil, field_changes: {}, snapshot: nil, metadata: {})` → `Audit::Event`;
  - `Audit::Event` scopes: `for_subject(record)`, `by_user(user)`, `recent`;
  - `Audit::Snapshot.for(record)` → a Hash;
  - `Audit::Snapshot.field_changes_for(record)` → a Hash built from `record.saved_changes` plus translation diffs, with bodies summarised;
  - `Audit::COALESCE_WINDOW = 10.minutes`;
  - the notification `audit.content_spiel` with payload `{ event: }`.

- [ ] **Step 1: Write the failing tests:**
  - **Recording:**
    - an event records the actor (User or ApiToken), `user_id` (the token's user for tokens), channel, request id, IP, `subject_label` (the post title at the time) and snapshot;
    - it survives the subject's deletion, and `subject_label` is still readable.
  - **Coalescing:**
    - two `post.updated` events by the same actor within 10 minutes make one event: `field_changes` keeps the first old value and the last new value, the snapshot is the latest, and `last_occurred_at` advances;
    - after 10 minutes, or by another actor, they make two events;
    - `post.published` never coalesces;
    - `access.denied` coalesces per actor, permission and subject.
  - **Transactions:** an event recorded inside a transaction that rolls back is gone; the notification fires only after commit (subscribe in the test).
  - **Append-only:** `event.destroy` raises or returns false; a raw `DELETE` raises `ActiveRecord::StatementInvalid`; a raw UPDATE of `action` raises; an UPDATE of `last_occurred_at` succeeds.
  - **Secrets** (Review Focus 5): snapshots of `User` and `ApiToken` contain no `password_digest`, `token_digest` or raw token; any key matching `filter_parameters` is dropped; a body change appears as `{"en body" => {"digest_before" => …, "digest_after" => …}}`.
- [ ] **Step 2: Run** the tests. They should fail.
- [ ] **Step 3: Implement.**
  - **Trigger ruling:** keep `schema.rb`. The migration creates the function and trigger via `execute`. Add `db/triggers/audit_events_append_only.sql`, plus a small `lib/tasks/db_triggers.rake` that enhances `db:schema:load` and `db:test:prepare` to apply it, so fresh test and CI databases get the trigger. Test that the trigger exists in the test DB (query `pg_trigger`).
  - **Notification:** publish via `ActiveRecord.after_all_transactions_commit { ActiveSupport::Notifications.instrument(...) }`.
- [ ] **Step 4: Run** `bin/rails db:migrate`, `db:test:prepare`, the tests and the full suite. They should pass. Also do a fresh load: `bin/rails db:drop db:create db:schema:load RAILS_ENV=test` (then `db:test:prepare`), and check the trigger is present.
- [ ] **Step 5: Commit** with `git commit -m "feat: add the append-only audit log"`.

---

### Task 6: Enforce and audit in every service

**Files:**
- Modify:
  - `app/services/application_service.rb`: `authorize!(key, record)` → Boolean via `AccessControl.allowed?(actor, key, record)`; `denied(key, record)` records `access.denied` and returns a failure with the §Global message; an `actor` reader defaulting to `Current.actor`.
  - Every service in `app/services/**`:
    - posts: `save`, `destroy`;
    - pages: `save`, `move`, `destroy`;
    - content_blocks: `save`, `reorder`, `destroy`;
    - tags: `rename`, `destroy`;
    - locales: `enable`, `disable`, `configure`;
    - users: `save`, `destroy`;
    - api_tokens: `issue`, `revoke`.

    Each one:
    - checks the right key(s) per spec §3.3 (create vs edit, publish when publish state changes or the record is already published, move plus create on the target parent, `posts.edit` unscoped for an `author_id` change);
    - sets `post.author_id` on create;
    - writes the §4.3 events inside the transaction.
- Create the services for the remaining direct writes:
  - `app/services/settings/save.rb` (used by `Admin::SettingsController` and `SetupController#update` / `#update_languages`);
  - `app/services/media_assets/create.rb` (used by `Admin::MediaAssetsController`);
  - `app/services/users/update_password.rb` (used by `Admin::PasswordsController#update`, the reset flow; actor nil with channel `:admin` is **allowed** because the reset token already authenticated the change, so pass `actor: @user` and document it);
  - `app/services/starter_contents/add.rb` (wraps `StarterContent.add_once!`).

  Refactor those controllers to call them.
- Modify `app/controllers/admin/sessions_controller.rb`: record `session.created`, `session.destroyed` and `session.failed` via `Audit.record`, with the failed email in `metadata` and no password.
- Test:
  - `test/services/authorization_matrix_test.rb` (table-driven);
  - `test/services/service_contract_test.rb` (walks `ApplicationService.descendants` after `Rails.application.eager_load!`: each `#call` source contains `authorize!(` and `record_event(`, or an explicit `# audit: none (reason)` comment — keep this list to zero if possible);
  - updates to each service's existing tests.

**Interfaces:**
- **Consumes:** Tasks 3 and 5.
- **Produces:** services return `Result.failure(record, ["You don't have permission to …"])` on denial; `Settings::Save.call(site, attributes:, actor:)`, `MediaAssets::Create.call(file:, actor:)`, `Users::UpdatePassword.call(user, password:, password_confirmation:, actor:)`, `StarterContents::Add.call(actor:)`.

- [ ] **Step 1: Write the failing tests.**
  - **Authorization matrix:** rows of `[service call, actor fixture, expected ok?, expected event action]` covering:
    - an author creating a blog post (ok, `post.created`, `author_id` set);
    - an author editing another person's post (denied, `access.denied`);
    - an author publishing (denied);
    - an author editing their own already-published post (denied: the published-edit rule);
    - an editor moving a page into a branch they can't create in (denied);
    - a read-only user editing a block (denied);
    - an owner doing anything (ok);
    - the setup channel with a nil actor (ok);
    - a token intersection denying.
  - **A forged PATCH** by a read-only user produces exactly one `access.denied` event even when repeated (coalesced) — Review Focus 4.
  - **Sessions:** a failed sign-in creates `session.failed` whose metadata has the email and no password key.
- [ ] **Step 2: Run** the tests. They should fail.
- [ ] **Step 3: Implement.** Use this pattern in every service:

```ruby
def call
  return denied("posts.create", @post) if @post.new_record? && !authorize!("posts.create", @post)
  # ... further checks ...
  Post.transaction do
    # ... save ...
    record_event(@post.previously_new_record? ? "post.created" : "post.updated", subject: @post, field_changes: Audit::Snapshot.field_changes_for(@post))
  end
end
```

Keep each service's rule comments in the codebase's comment style.
- [ ] **Step 4: Run** the full suite. Existing service tests need an authorized actor: set `Current.actor = users(:one)` (owner) in `test_helper.rb`'s `ActiveSupport::TestCase` setup only where tests don't set their own. Prefer an explicit helper `as_owner { ... }` and update the tests. It should pass.
- [ ] **Step 5: Commit** with `git commit -m "feat: enforce permissions and record audit events in every service"`.

---

### Task 7: CS Studio enforcement — areas, record scopes, buttons, view-only

**Files:**
- Modify:
  - `app/controllers/admin/base_controller.rb`:
    - `require_permission(key)` renders `admin/errors/forbidden` with 403;
    - a `can?(key, record = nil)` helper;
    - `admin_scope(relation, key = "…read")`.
  - Every admin controller: area controllers call `require_permission`; record controllers load via `AccessControl.scope`, so a record out of scope raises `ActiveRecord::RecordNotFound` and gives a 404. The controllers are `pages`, `posts`, `content_blocks`, `tree`, `tags`, `settings`, `languages`, `users`, `api_tokens`, `system_status`, `mind_graph`, `link_targets`, `media_assets` and `starter_contents`.
  - `app/controllers/preview_controller.rb`: preview reads go through `AccessControl.scope`.
  - `app/models/post_graph.rb`: `PostGraph.call(actor:)` filters.
  - `app/views/layouts/admin.html.erb`: sidebar entries use `can?`.
  - The page tree component: pages in `context` are greyed out, not links, with no actions.
  - The page and post editors: action buttons use `can?`. A **View only** badge shows when the user can read but can't edit; fields are disabled and the `admin--autosave` data-controller isn't attached.
- Create: `app/views/admin/errors/forbidden.html.erb` (product layout), `test/integration/admin/access_control_test.rb`
- Test: `test/integration/admin/access_control_test.rb`, `test/system/admin/view_only_test.rb`

**Interfaces:**
- **Consumes:** Tasks 3, 4 and 6.
- **Produces:** the `can?` helper and `require_permission` for later modules.

- [ ] **Step 1: Write the failing tests** (integration), signing in as author, editor (branch-limited) and read-only users from fixtures:
  - **Sidebar:** each group sees only the modules they can open.
  - **Area access:** `GET <admin>/users` as an author → 403.
  - **Out-of-scope records** (Review Focus 2): `GET <admin>/posts/<other's post>` as an author → 404; preview of an out-of-scope page → 404.
  - **Lists and tree:** the posts list shows only readable posts; the tree renders context ancestors as greyed out and unlinked.
  - **Pickers:** link-target search and related-post search return only readable targets; the mind graph JSON has only readable nodes.
  - **Buttons:** Publish, Delete and Move are absent when not allowed.
  - **System test:** a read-only user opening a post sees "View only", the fields are disabled, and typing sends no PATCH (count requests via a JS hook, as the existing autosave test does).
- [ ] **Step 2: Run** the tests. They should fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full suite and `bin/rails test:system`. They should pass.
- [ ] **Step 5: Commit** with `git commit -m "feat: enforce permissions across CS Studio"`.

---

### Task 8: Groups module, users (groups and owner), my password, token groups

**Files:**
- Create:
  - `app/services/groups/save.rb` and `app/services/groups/destroy.rb`. Save validates `can_grant?` for every grant; destroy revokes the group's tokens and records a `token.revoked` event per token.
  - `app/controllers/admin/groups_controller.rb` (index/new/create/edit/update/destroy, `require_permission "groups.manage"`).
  - The views and components: `app/components/admin/permission_matrix_component.*` (checkboxes by area, scope controls) and the Lookbook previews.
  - `app/javascript/controllers/admin/branch_picker_controller.js` (page-tree checkboxes that write `page_ids`).
  - `app/controllers/admin/accounts_controller.rb` ("Change my password", signed-in users, via `Users::UpdatePassword` with the current password required).
- Modify:
  - `app/services/users/save.rb`: `group_ids`; `owner` (owners only).
  - `app/controllers/admin/users_controller.rb` and its views (group checkboxes, an owner toggle hidden for non-owners and disabled for the last owner).
  - `app/services/api_tokens/issue.rb`: `group:` is required and checked with `AccessControl.can_assign_group?`.
  - `app/controllers/admin/api_tokens_controller.rb` and its views: a group select limited to assignable groups, defaulting to Read only; the list shows the group; users see their own tokens unless they have `tokens.manage`.
  - The admin layout's account menu: a "Change password" link.
  - `config/routes.rb`.
- Test: `test/integration/admin/groups_test.rb`, `test/services/groups/save_test.rb`, `test/integration/admin/accounts_test.rb`, updates to `users_test.rb` and `api_tokens_test.rb`, `test/system/admin/groups_editor_test.rb`

**Interfaces:**
- **Consumes:** Tasks 2, 3, 6 and 7.
- **Produces:** `Groups::Save.call(group, attributes: { name:, description:, member_ids:, grants: [{ permission:, scope: }] }, actor:)`, `Groups::Destroy.call(group, actor:)`.

- [ ] **Step 1: Write the failing tests:**
  - **Groups:**
    - create a group with `posts.edit` scoped to blog and own, then edit it;
    - a built-in group can't be deleted;
    - deleting a custom group revokes its tokens, and the confirmation names them;
    - a non-owner with `groups.manage` can't add a permission they lack, can't widen a group they're a member of, and can't widen a scope (Review Focus 1);
    - a group whose grant references a deleted branch root or a no-longer-registered content type still loads in the editor, and the stale values are shown as removed (Review Focus 3).
  - **Users:** a user's groups are saved; a non-owner can't see or change `owner`; the last owner can't be demoted.
  - **Tokens:** an author issuing a token can choose only Read only or Author; forging `group_id` = Admin fails.
  - **My password:** a wrong current password fails; a success signs out other sessions.
  - **System test:** tick `pages.edit`, pick a branch in the picker, save; the grant's `page_ids` is saved.
- [ ] **Step 2: Run** the tests. They should fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full suite and the system tests. They should pass.
- [ ] **Step 5: Commit** with `git commit -m "feat: manage groups, owners, token groups and your own password in CS Studio"`.

---

### Task 9: Audit log module and Activity links

**Files:**
- Create:
  - `app/controllers/admin/audit_events_controller.rb` (index with filters, show; `require_permission "audit.view"`).
  - `app/views/admin/audit_events/*`.
  - `app/components/admin/audit_changes_component.*` with a Lookbook preview (the old/new table; bodies as "changed").
- Modify:
  - the post, page and user editors: an **Activity** link (`can?("audit.view")`) to `admin_audit_events_path(subject_type:, subject_id:)`;
  - the layout sidebar;
  - `config/routes.rb`.
- Test: `test/integration/admin/audit_events_test.rb`

- [ ] **Step 1: Write the failing tests:**
  - **Access:** the list is newest first and requires `audit.view` (an author gets 403).
  - **Filters:** by user, action, subject type, subject and date range. Pagination covers 50 per page (use the existing pattern if there is one, else a simple `limit`/`offset` with next/prev).
  - **Event page:** the show page renders `field_changes` and the snapshot. HTML in a snapshot value is escaped (a title `<script>` renders as text).
  - **Links:** an event whose subject was deleted shows the label without a link; the Activity link filters to its record.
- [ ] **Step 2: Run** the tests. They should fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full suite and the system tests. They should pass.
- [ ] **Step 5: Commit** with `git commit -m "feat: browse the audit log in CS Studio"`.

---

### Task 10: MCP under permissions

**Files:**
- Modify:
  - `app/mcp/mcp/tools/{list_posts,get_post,create_post,update_post}.rb`: reads go through `AccessControl.scope(Current.actor, "posts.read", …)`; out of scope → a "Post not found" tool error; write denials → a tool error with the service message.
  - `app/controllers/mcp_controller.rb`: the server instructions mention the token's group (e.g. "This token acts as <user> limited to the <group> group").
- Test: `test/integration/mcp_access_control_test.rb`

- [ ] **Step 1: Write the failing tests:**
  - **Read only token:** `list_posts` returns only readable posts; `create_post` → a tool error with "You don't have permission to create posts"; `get_post` for an unreadable post → "not found" (Review Focus 2).
  - **Author token:** creating a blog post works; the audit event has `channel: "mcp"`, the actor is the token and `user_id` is its user; updating someone else's post fails.
  - **Instructions:** the initialize response text includes the group name.
- [ ] **Step 2: Run** the tests. They should fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full suite. It should pass.
- [ ] **Step 5: Commit** with `git commit -m "feat: apply permissions to MCP tools"`.

---

### Task 11: Setup wizard, docs and final verification

**Files:**
- Modify:
  - `app/controllers/setup_controller.rb`: the created account is an owner (via `Users::Save` on channel `:setup`); the MCP-token step issues with the Admin group, and the copy says the token can be narrowed in CS Studio.
  - `docs/roadmap.md`: mark roles, permissions and the audit log done; add the spec §8 interim states (published-edit needs publish; audit grows without limit; no page authors).
  - `CLAUDE.md`: an "Access control and audit" architecture section in the file's style, covering the registry, the checker, scopes, owners, tokens, services as the enforcement point, audit coalescing, snapshots, the trigger and the notification hook. Update the Auth section.
  - `README.md` if it describes users or roles.
- Test: update `test/system/setup_wizard_test.rb` and the setup integration tests.

- [ ] **Step 1:** Update the tests for the setup changes (the owner flag; the token group is Admin). Run them; they should fail.
- [ ] **Step 2:** Implement the setup changes, then update the docs.
- [ ] **Step 3: Full verification.** All of these should be green:
  - `PARALLEL_WORKERS=1 bin/rails test`;
  - `bin/rails test:system` (twice);
  - `bin/rubocop`, `bin/brakeman -q --no-pager`, `bin/bundler-audit`, `bin/importmap audit`;
  - `bin/rails zeitwerk:check`;
  - `bin/rails db:reset` (seeds create the owner and the author), then sign in as the author with a runner check: `bin/rails runner 'u=User.find_by(email_address: "author@example.com"); puts AccessControl.allowed?(u, "users.manage")'` should print `false`.
- [ ] **Step 4: Commit** with `git commit -m "docs: record access control and the audit log; setup creates an owner"`.
