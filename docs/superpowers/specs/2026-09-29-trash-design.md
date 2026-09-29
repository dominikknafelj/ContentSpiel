# Trash

Sub-project 6b of the own-admin roadmap, built after 6a (media library, PR #31). Approved in brainstorming on 2026-09-29. This is the binding spec for the implementation plan.

## 1. Purpose

Every delete in CS Studio is permanent today; `docs/roadmap.md` lists "Deletes are permanent" as a known interim state and "Trash / soft delete + restore" as a Must.

This sub-project adds a trash for pages, posts and library images:
- deleting moves an item to the trash, where it can be restored;
- trashed items vanish at once from the public site, every CS Studio list, search and MCP;
- the trash is emptied by hand or automatically after a configurable retention period.

**Success:**
- An editor deletes a section of the site by mistake and gets it back with one Restore, subpages, blocks, tags and images included.
- A trashed page's URL answers 404 straight away and can be reused by a new page.
- Nothing disappears permanently until someone empties the trash or the retention period runs out.
- An image used by something in the trash can't be deleted permanently.

## 2. Decisions (from brainstorming)

| Topic | Decision |
|---|---|
| What goes to the trash | **Pages, posts and library images.** A trashed page keeps its blocks. Deleting a single block, a tag, a group, a user or a token stays permanent (block undo belongs to Phase 3 versioning). |
| Pages with children | **The whole branch goes together.** Restoring the page brings the branch back. A subpage can't be restored on its own while its parent is trashed, except by choosing a new parent. |
| Emptying | **Automatic after `trash_retention_days` (default 30, 0 = off), plus by hand** (one item, or Empty trash). |
| Unused-image cleanup | **Not in this piece.** Images reach the trash only when someone deletes them. The roadmap row stays open. |
| Permissions | **Existing delete rights** for moving, restoring and purging one item; new **`trash.empty`** (Admin only) for emptying everything. |
| URLs | **Freed at once.** The public site answers 404; a slug taken meanwhile is suffixed on restore (`about-2`). |
| Implementation | **A `trashed_at` column, filtered at the existing narrowing points** (`AccessControl.scope`, the public finders), with a guard test. No `default_scope`, no separate trash table. |

## 3. Data

### 3.1 Columns

`pages`, `posts` and `media_assets` each get:
- `trashed_at` (datetime, nullable, indexed);
- `trashed_by_id` (FK to `users`, nullable, `on_delete: :nullify`).

`pages` also gets `trash_root_id` (FK to `pages`, nullable, `on_delete: :nullify`): the page the editor actually trashed. It is the same for the whole branch that went with it.

`site_settings` gets `trash_retention_days` (integer, not null, default 30, must be ≥ 0).

### 3.2 Model API

A concern, `Trashable`, is included in `Page`, `Post` and `Media::Asset`:
- scopes `.kept` (`trashed_at IS NULL`) and `.trashed`;
- `#trashed?`;
- `belongs_to :trashed_by, class_name: "User", optional: true`.

There is **no `default_scope`**. Hiding trashed rows is the job of the narrowing points in §5.

## 4. Services (`Trash::`)

All three are `ApplicationService` subclasses: they authorize, record audit events and run in one transaction.

### 4.1 `Trash::Move`

`Trash::Move.call(record)` handles a `Page`, a `Post` or a `Media::Asset`.

- **Page:**
  - The homepage is refused, as today.
  - The page and every kept descendant get `trashed_at` = now, `trashed_by_id` = the actor and `trash_root_id` = the page.
  - Descendants already in the trash keep their own values.
  - Blocks, closure-tree rows and `position` are untouched.
- **Post:** gets `trashed_at` and `trashed_by_id`. Tags and relations are untouched.
- **Image:** refused while a `media_usages` row belongs to a kept owner, with the existing "used on …" message. Usage rows from trashed owners don't block the move.
- **URLs (pages and posts):** every `public_paths` row of every moved record is deleted, current rows and old redirects alike, so each URL can be reused at once.
- **Timestamps:** `updated_at` is touched on every moved record, which moves `PublicSite.content_version` (§5.3).
- **Audit:** records `page.trashed`, `post.trashed` or `media.trashed`. A page's metadata lists the ids of the descendants that came along.

### 4.2 `Trash::Restore`

`Trash::Restore.call(record, parent: nil)`

- **Page:**
  - Clears `trashed_at`, `trashed_by_id` and `trash_root_id` on the page and on every page whose `trash_root_id` is the page.
  - Descendants trashed separately earlier stay in the trash.
  - A page that was trashed as part of someone else's branch (`trash_root_id` ≠ its own id) is refused unless `parent:` is given. If its root is still in the trash, the message says to restore the root instead.
  - A page whose parent has been purged (the parent row is gone) must be given `parent:`.
  - With `parent:`, the page is moved under that parent (which must be kept and editable by the actor: `pages.move`), at the end of the siblings, and restored together with its own branch. That branch is the pages trashed with it, i.e. its descendants that share its `trash_root_id`.
- **Post** and **image:** clear the fields.
- **Slugs (pages and posts):**
  - Each restored record's slug is checked per locale against kept records, using the existing uniqueness rules.
  - A taken slug gets the first free `-2`, `-3`, … suffix.
  - The result lists every changed slug as `{ record, locale, from, to }`.
- **URLs:** `public_paths` are rebuilt through the existing path code for every restored page and post.
- **Audit:** records `page.restored`, `post.restored` or `media.restored`, with the slug changes in metadata.

### 4.3 `Trash::Purge`

`Trash::Purge.call(record)` handles a trashed record only; a kept record is refused.

- **Page:** permanently deletes the page's branch, meaning the pages with its `trash_root_id` plus the page itself, deepest first. It runs through the existing permanent-delete logic, which covers blocks, `media_usages` rows and closure rows. The children check doesn't apply inside a branch being purged.
  - A branch member with a kept child is refused. That child was restored with a new parent, so it isn't a child any more; the check exists as a guard.
- **Post:** permanently deletes it through the existing logic (tags, relations, usages).
- **Image:** refused while *any* `media_usages` row points at it, including rows from trashed owners. Otherwise it's deleted and its file purged, as today.
- **Audit:** records `page.purged`, `post.purged` or `media.purged`, with a snapshot taken before the delete.

### 4.4 `Trash::Empty` and the retention job

- **`Trash::Empty.call`** needs `trash.empty`. It purges everything in the trash in this order:
  1. page branches, roots only;
  2. posts;
  3. images, after pages and posts so that their usages are gone first.

  Items that can't be purged are skipped and reported in the result. They're never a hard failure.
- **`Trash::PurgeExpiredJob`:**
  - runs daily from `config/recurring.yml`, listed for every environment;
  - does nothing when `trash_retention_days` is 0;
  - otherwise purges, in the same order, items whose `trashed_at` is older than the retention period. For a page branch, the root's `trashed_at` counts.
  - It runs on the `:system` channel with a nil actor, so its events show "System".
  - Skipped items are logged. A failing item doesn't stop the run.

### 4.5 What happens to today's services

- `Pages::Destroy`, `Posts::Destroy` and `Media::Destroy` stop being reachable from CS Studio. Their permanent-delete bodies become private collaborators of `Trash::Purge`.
- The Delete buttons call `Trash::Move`.
- `ContentBlocks::Destroy`, `Tags::Destroy`, `Users::Destroy` and `Groups::Destroy` are unchanged and stay permanent.
- The service contract test covers the new services.

## 5. Keeping trashed items out of sight

### 5.1 CS Studio and MCP

- **Scope:** `AccessControl.scope` adds `.kept` for `Page` and `Post`, and for `ContentBlock` it adds "the owner is kept".
- **Trash scope:** `AccessControl.scope(actor, key, relation, channel:, trashed: true)` returns only trashed rows. It's used by the Trash screen alone.
- **Where the scope applies:** every CS Studio list, the page tree, link-target and related-post search, the mind graph, `/preview` and MCP's list/get/update tools. Loading a trashed record by id answers 404.
- **Images:** the media grid, the picker, `Media::Search` and MCP's `list_media`/`get_media` return kept images only. `Media::Choosing` refuses a trashed image, which reads as "doesn't exist".
- **Usage display:** an image whose only usages come from trashed owners shows "Used only by items in the trash" in its detail panel, and it isn't counted as unused.

### 5.2 Public site

- **Pages:** `Page.find_by_full_path` finds no path for a trashed page. It also requires `kept`.
- **Posts:** `ContentBlock#listed_posts` and post permalink resolution add `.kept`, so a trashed post 404s and drops out of listings.
- **Everything else:** navigation, the sitemap, related posts, and internal-link and image rendering skip trashed records. An internal link to a trashed page or post renders as plain text, like a dead link today.
- **Preview:** a trashed record 404s on `/preview` too.

### 5.3 Cache

`PublicSite.content_version` already uses `max(updated_at)` and the counts of pages, posts, public paths and assets.
- Moving and restoring touch `updated_at` and change `public_paths`.
- Purging changes the counts.

So cached renders and ETags go stale without new inputs. A test pins this.

### 5.4 Guard test

`test/integration/trash_visibility_test.rb` exercises every narrowing point in §5.1–§5.2 with one kept and one trashed record of each type, and fails if the trashed one shows up. A new list added later must be added here, which a comment says.

## 6. Permissions

| Action | Needs |
|---|---|
| Move a page, or restore/purge one | `pages.delete` on the page (scopes apply). Restoring under a new parent also needs `pages.move` there. |
| Move a post, or restore/purge one | `posts.delete` on the post (scopes apply) |
| Move an image, or restore/purge one | `media.manage`, or being its uploader with `media.upload` (`Media::Ownership`) |
| Empty trash | the new `trash.empty` (registered in `AccessControl::BuiltIns`, area "Trash"; granted to the built-in Admin group by a data migration and `AccessControl::Seeds`) |
| Change `trash_retention_days` | `settings.manage` |

The Trash screen is in the sidebar for anyone who holds any of `pages.delete`, `posts.delete`, `media.manage`, `media.upload` or `trash.empty`. It lists only the items the viewer could restore.

## 7. CS Studio

- **Trash screen:** `Admin::TrashController`, at `<ADMIN_PATH>/trash`.
  - Filter tabs: All, Pages, Posts, Images. The list is newest first, about 50 per page.
  - Each row shows the title (a thumbnail for images), the type, who trashed it and when, and "Deleted permanently in N days" (hidden when retention is 0).
  - A page branch is one row with "+N subpages", expandable to list them.
  - **Restore:**
    - A page that needs a parent opens a parent picker, which reuses the page picker used for link targets, limited to pages the actor may move pages under.
    - The flash names the restored item and any changed slug ("Restored 'About' as about-2 (the URL was taken)").
  - **Delete permanently:** confirms through the existing confirm-dialog component. It's disabled with the reason for an image that's still in use.
  - **Empty trash:** for `trash.empty` holders, with a confirm dialog that states the count.
- **Delete buttons** on the page, post and image screens:
  - They become **Move to trash**.
  - The confirm text says the item can be restored. For a page with subpages it says "This also moves N subpages to the trash".
  - After trashing, CS Studio goes back to the list with a flash that includes an **Undo** link (a Restore of that item).
- **Settings module:** gains "Empty trash automatically after [N] days (0 = never)".
- **Browser dialogs:** none; the confirm-dialog component throughout.

## 8. MCP

MCP has no delete tools, so nothing changes there except visibility (§5.1). Trash tools are out of scope.

## 9. Testing

- **Migrations:** the columns and indexes; `trash.empty` granted to Admin; the retention default is 30.
- **`Trash::Move`:**
  - each type;
  - a branch and its `trash_root_id`;
  - a descendant already trashed keeps its own values;
  - the homepage is refused;
  - an image used by a kept owner is refused, but not one used only by trashed owners;
  - `public_paths` are removed;
  - the audit event, with the actor and the moved descendants.
- **`Trash::Restore`:**
  - a branch comes back together;
  - a separately trashed descendant stays in the trash;
  - a subpage alone is refused and succeeds with `parent:`;
  - a page whose parent was purged needs `parent:`;
  - a slug conflict per locale gives `-2`, and the next free suffix after that;
  - `public_paths` are rebuilt;
  - the audit event.
- **`Trash::Purge` and `Trash::Empty`:**
  - branch order;
  - an image used by a trashed owner is refused, and succeeds after that owner is purged;
  - usages and files are gone;
  - skipped items are reported;
  - `Empty` needs `trash.empty`.
- **`Trash::PurgeExpiredJob`:**
  - an item just under or just over the period;
  - 0 disables it;
  - a branch goes by its root's date;
  - the ordering;
  - one failing item doesn't stop the run;
  - its events come from System.
- **Permissions:**
  - scoped delete rights for move, restore and purge (an Author limited to own posts can trash and restore only their own);
  - `pages.move` for restoring under a new parent;
  - the Trash list is filtered per viewer;
  - "not found, not forbidden" for trashed records loaded by id.
- **Visibility guard test** (§5.4), plus the public 404, listings, the sitemap, navigation, internal links rendered as text, and `content_version` changing on move, restore and purge.
- **System tests (Cuprite):**
  - trash a page with subpages and see it gone from the tree and the public site;
  - restore it from the Trash screen;
  - Undo from the flash;
  - purge an unused image;
  - Empty trash.

## 10. Out of scope and interim states

**Out of scope** (recorded in `docs/roadmap.md`):
- automatic cleanup of unused images, which can now build on the trash;
- trash for blocks, tags, groups, users and tokens;
- MCP trash tools;
- 410 Gone for trashed URLs.

**Interim states resolved:** "Deletes are permanent" (roadmap, known interim states).

**Interim states introduced:** none. A trashed page's old redirect rows are dropped with its current paths and aren't recreated on restore; this is intended, since the URLs were free in the meantime.
