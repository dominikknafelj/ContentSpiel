# Media Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give CS Studio one media library that hero images, image blocks and rich-text images all point at. Alt text and caption are defaults on the image that each use can override. Responsive WebP variants are generated in the background. A usage index backs "used on…", the Unused filter and safe deletion. One picker is used everywhere.

**Architecture:**
- **Domain namespace:** `Media::` (`MediaAsset` becomes `Media::Asset`). Records reference assets directly (`pages.hero_media_asset_id`, `content_blocks.media_asset_id`); rich-text `image` nodes keep `asset_id`.
- **Usage index:** a derived `media_usages` table, rebuilt by `Media::UsageIndex` from services.
- **Rendering:** goes through one `Media::PictureComponent`.
- **Writes:** go through `Media::Upload` / `Save` / `Destroy` under the existing `AccessControl` and `Audit` machinery.

**Tech Stack:** Rails 8.1, Postgres (jsonb, FKs), Active Storage with `image_processing` and `ruby-vips` (preprocessed variants on Solid Queue), Mobility jsonb, ViewComponent and Lookbook, Hotwire and importmap (Tiptap editor), Minitest with fixtures, Capybara on **Cuprite** for system tests.

**Spec:** `docs/superpowers/specs/2026-09-29-media-library-design.md`. Read it before any task.

## Global Constraints

**Naming and data**
- Namespace `Media::`, files in `app/models/media/`, services in `app/services/media/`, components in `app/components/media/`. `MediaAsset` becomes `Media::Asset`, and the table `media_assets` is unchanged.
- The table is `media_usages`, with columns `media_asset_id` (FK, `on_delete: :restrict`, not null), `owner_type`, `owner_id`, `role`, and `locale` (nullable). There's a unique index on `(media_asset_id, owner_type, owner_id, role, locale)` and an index on `(owner_type, owner_id)`.
- Roles are exactly `hero`, `block_image` and `rich_text`.
- The new columns are `pages.hero_media_asset_id` and `content_blocks.media_asset_id` (FK to `media_assets`, `on_delete: :restrict`, nullable), plus `media_assets.title` (string, not null) and translated `alt` / `caption` (Mobility jsonb).

**Images**
- Variant names are exactly `w480`, `w960`, `w1600` and `w2400`: `resize_to_limit` to that width, never upscaled, WebP, `preprocessed: true`. GIFs get no variants.
- Allowed types stay png, jpeg, gif and webp (byte-sniffed), with a 10 MB maximum. SVG stays refused. **The logo stays a separate `SiteSetting` attachment.**
- Alt and caption resolution is `override.presence`, then the asset's default in the locale, then the Mobility fallback. It lives only in `Media::Asset#alt_text(override:, locale:)` and `#caption_text(override:, locale:)`.

**Permissions, events and process**
- Permissions: `media.upload` (existing: upload, browse, pick) and `media.manage` (new: edit and delete any image). A user can always edit or delete their own uploads (`created_by_id`). The seeded Admin and Editor groups get `media.manage`.
- Audit event names are exactly `media.uploaded`, `media.updated` and `media.deleted`.
- Cleanup is manual only. `Media::Destroy` refuses while any usage exists.
- Commits use conventional messages and end with exactly `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never skip hooks.
- Long, load-bearing comments are the codebase norm.
- Before each commit, run `PARALLEL_WORKERS=1 bin/rails test` and `bin/rubocop`. UI tasks also run `bin/rails test:system` (Cuprite). The test DB is shared, so only one agent runs tests at a time.

## Review Focus

1. **Re-uploading the same file.** An editor uploads a file already in the library. Expected: a second asset is created (no silent dedupe on upload; dedupe only happens in the migration), and both are listed. (Task 6)
2. **Rich-text image in some locales only.** An image is used in the `de` body only, then removed from `de`. Expected: its `rich_text` usage for `de` disappears, while the `en` usage of another image is untouched, and "Unused" updates. (Task 3)
3. **A variant job fails or is slow** (corrupt image, vips error). Expected: the public page still renders the original. `srcset` omits the missing sizes, and nothing returns a 500. (Tasks 2, 5)
4. **Deleting an asset while a page still points at it**, through a race or a forged request. Expected: refused. The service checks usage and the DB FK restricts; the database error becomes a validation failure, not a 500. (Task 6)
5. **Picking an asset the user can't use.** A forged `hero_media_asset_id` for a non-existent id, or from an actor without `media.upload`. Expected: a validation or permission failure, with the page unchanged. (Task 6)

---

### Task 1: Rename `MediaAsset` to `Media::Asset`

**Files:**
- Move: `app/models/media_asset.rb` → `app/models/media/asset.rb` (`class Media::Asset < ApplicationRecord`; `self.table_name = "media_assets"` if Rails doesn't infer it).
- Modify: every reference found by `grep -rn "MediaAsset" app test config db/seeds.rb lib`. That covers:
  - models: rich-text built-ins and markdown, the audit snapshot, and `public_site`'s `content_version`;
  - services (`MediaAssets::Create` stays for now);
  - controllers (`Admin::MediaAssetsController` stays);
  - MCP tools and tests;
  - migrations under `db/migrate`: leave old migrations untouched, and if one references the constant, define a local model in the migration instead.
- Rename fixtures if any: `test/fixtures/media_assets.yml` needs `_fixture: model_class: Media::Asset`.
- Keep polymorphic data correct:
  - `active_storage_attachments.record_type`: a data migration `db/migrate/<ts>_rename_media_asset_type.rb` updates `MediaAsset` to `Media::Asset`, with a reversible `down`.
  - `audit_events.subject_type` is append-only by trigger. **Ruling:** don't rewrite it. The audit UI's subject resolver (`Admin::AuditEventsController::SUBJECT_TYPES` and `Admin::AuditEventsHelper`) maps the legacy `"MediaAsset"` to `Media::Asset`, with a comment. New events store `"Media::Asset"`.

**Interfaces:**
- **Produces:** the `Media::Asset` constant with all existing behaviour; `media_assets` data unchanged.

- [ ] **Step 1:** Run `grep -rn "MediaAsset\|media_asset" app test config lib db/seeds.rb` and list the hits in the report.
- [ ] **Step 2:** Move and rename the class and every reference. Write the type data migration for `active_storage_attachments.record_type`.
- [ ] **Step 3:** Add a test: `test/models/media/asset_test.rb` is the renamed existing test, plus one asserting that an existing attachment row whose `record_type` was `"MediaAsset"` resolves after the migration. Also test that audit events recorded before the rename still show their subject label and link.
- [ ] **Step 4:** Run `bin/rails db:migrate`, `db:test:prepare`, `PARALLEL_WORKERS=1 bin/rails test` and `bin/rubocop`. Expected: all green, and `grep -rn "MediaAsset" app lib config` shows only migration history.
- [ ] **Step 5:** Commit with `git commit -m "refactor: rename MediaAsset to Media::Asset"`.

---

### Task 2: Asset title, translated defaults, variants and resolvers

**Files:**
- Create: `db/migrate/<ts>_add_library_fields_to_media_assets.rb`. It adds `title` (string, not null, default `""`), plus `alt` and `caption` as jsonb (default `{}`), and backfills `title` from each blob's filename without the extension.
- Modify: `app/models/media/asset.rb`:
  - `translates :alt, :caption`;
  - `before_validation` sets `title` from the file name when it's blank;
  - the variants below;
  - `#srcset`, `#src`, `#alt_text`, `#caption_text`.
- Test: `test/models/media/asset_test.rb` (extended).

**Interfaces:**
- **Produces:**
  - `Media::Asset::VARIANT_WIDTHS = { w480: 480, w960: 960, w1600: 1600, w2400: 2400 }`
  - `#srcset` → Array of `[url_path, width]` for processed variants only (empty for GIF)
  - `#src` → the original's path
  - `#alt_text(override:, locale: I18n.locale)` → String
  - `#caption_text(override:, locale: I18n.locale)` → String or nil
  - `#variable_image?` → false for GIF

- [ ] **Step 1: Write the failing tests.**
  - The title defaults from the file name (`hero-photo.jpg` gives `hero-photo`) and stays editable.
  - `alt_text`:
    - returns the override when present;
    - otherwise the `de` default;
    - otherwise the `en` fallback when `de` is empty;
    - otherwise `""` when nothing is set.
  - `caption_text`: the same order.
  - Variants:
    - after `perform_enqueued_jobs`, a 3000px-wide PNG has processed `w480`…`w2400`, and `srcset` lists four widths;
    - an 800px image's `srcset` has only `w480` (never upscaled; skip widths ≥ original);
    - a GIF has an empty `srcset`;
    - before jobs run, `srcset` is empty.
  - Review Focus 3: stub the variant processing to raise. `srcset` still returns without raising, and the error is logged.
- [ ] **Step 2:** Run `bin/rails test test/models/media/asset_test.rb`. Expected: FAIL.
- [ ] **Step 3: Implement.** Declare the variants inside `has_one_attached :file do |attachable| … end` using `attachable.variant :w480, resize_to_limit: [480, nil], format: :webp, preprocessed: true` (and so on). Skip variants for GIFs by only building `srcset` from variants whose width is below the original width, when the file is variable and not a GIF. Check `processed?` via `file.variant(name).processed?` and rescue processing errors to `[]`. Write a comment explaining that pages never wait for a variant.
- [ ] **Step 4:** Run the test, the full suite and rubocop. Expected: PASS.
- [ ] **Step 5:** Commit with `git commit -m "feat: give library images titles, translated defaults and responsive variants"`.

---

### Task 3: The usage index

**Files:**
- Create: `db/migrate/<ts>_create_media_usages.rb` (per Global Constraints), `app/models/media/usage.rb`, `app/models/media/usage_index.rb`, `lib/tasks/media.rake` (`media:reindex`).
- Test: `test/models/media/usage_index_test.rb`

**Interfaces:**
- **Consumes:** `pages.hero_media_asset_id` and `content_blocks.media_asset_id`. Those arrive in Task 4. This task adds the columns early in its own migration, only if Task 4's migration doesn't exist yet. **Ruling:** the `media_usages` migration in this task also adds both reference columns and their FKs, and Task 4 only migrates data and drops the old attachments. That way the index can be tested now.
- **Produces:**
  - `Media::Usage` (`belongs_to :media_asset, class_name: "Media::Asset"`, `belongs_to :owner, polymorphic: true`, `ROLES = %w[hero block_image rich_text]`);
  - `Media::UsageIndex.refresh(owner)`, which handles Page, ContentBlock and Post (other owners are a no-op). A destroyed owner leaves 0 rows;
  - `Media::UsageIndex.rebuild_all`;
  - `Media::Asset has_many :usages`, `#used?`, `#usages_summary`;
  - scope `Media::Asset.unused`.

- [ ] **Step 1: Write the failing tests.**
  - Refreshing a page with a hero asset gives one `hero` row. Clearing the hero gives 0 rows.
  - A block with an image gives a `block_image` row.
  - A post whose `en` body has two image nodes (assets A and B) and whose `de` body has A gives rows (A,en), (B,en), (A,de).
  - Review Focus 2: removing A from `de` and refreshing leaves (A,en) and (B,en).
  - A block owned by a page, with a rich-text body containing an image, gives a `rich_text` row owned by the block.
  - After a refresh, a destroyed owner has 0 rows.
  - `rebuild_all` equals the union of per-owner refreshes.
  - `Media::Asset.unused` excludes used assets.
  - The FK restricts deleting an asset referenced by a page (raises `ActiveRecord::InvalidForeignKey`).
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3: Implement.** For rich text, read the raw body per locale (`read_attribute(:body)` as a Hash of locale ⇒ document) and collect `RichText::Document.new(doc).references` of type image (use the existing `references` API; check its shape). Replace an owner's rows in one transaction: delete them, then insert them.
- [ ] **Step 4:** Run the tests, the full suite and rubocop. Expected: PASS.
- [ ] **Step 5:** Commit with `git commit -m "feat: index where each library image is used"`.

---

### Task 4: Move hero images and image blocks onto library assets

**Files:**
- Create:
  - `db/migrate/<ts>_move_images_into_media_library.rb`. It is a data migration: for each `Page` hero attachment and each `ContentBlock` image attachment, it finds or creates a `Media::Asset` per blob checksum, re-attaching the same blob, sets the reference, copies the filename into title, then deletes the old attachment rows (not the blobs). It is reversible: `down` re-creates the attachments from the references. It uses lightweight models defined in the migration where practical.
  - `lib/tasks/media.rake` gains `media:orphans`. It lists blobs with no attachments, and `CONFIRM=1` purges them.
- Modify:
  - `app/models/page.rb`: remove `has_one_attached :hero_image`; add `belongs_to :hero_media_asset, class_name: "Media::Asset", optional: true`.
  - `app/models/content_block.rb` and `app/models/block_types/image.rb`: remove `has_one_attached :image`; add `belongs_to :media_asset, class_name: "Media::Asset", optional: true`. The image block type validates presence of the asset where it validated the image before.
  - Every reader of `hero_image` / `block.image`: `app/views/pages/show.html.erb`, `app/components/blocks/image_component.*`, the audit snapshot, and seeds/starter content. Point them at the asset and render through `url_for(asset.file)` for now; Task 5 swaps in the picture component.
  - Temporarily keep the admin upload fields working: a hero or block upload now creates a `Media::Asset` via `Media::Upload` (a thin stub in this task if Task 6 hasn't landed; **ruling:** create `Media::Upload` here with the behaviour of `MediaAssets::Create`, and have `MediaAssets::Create` delegate to it). Then set the reference. Task 8 replaces the upload fields with the picker.
- Test: `test/migrations/move_images_into_media_library_test.rb`, plus updates to page and block tests and fixtures.

**Interfaces:**
- **Produces:** `Page#hero_media_asset`, `ContentBlock#media_asset`, `Media::Upload.call(file:, actor:)` → Result(asset), and the rake tasks `media:orphans` and `media:reindex`.

- [ ] **Step 1: Write the failing tests** (migration test pattern from `test/migrations/`):
  - Two pages with identical hero files and one block with a different image give two assets, with checksums deduped.
  - The references are set, and the titles come from the file names.
  - The old attachments are gone, and the blobs are kept.
  - `media_usages` is rebuilt.
  - `down` restores the attachments.
  - `media:orphans` lists an unattached blob, and `CONFIRM=1` purges it.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3: Implement.** Also run the data migration against the dev DB and put its output in the report.
- [ ] **Step 4:** Run `bin/rails db:migrate`, `db:test:prepare`, the full suite, `bin/rails test:system` and rubocop. Expected: PASS. Public pages still show hero and block images.
- [ ] **Step 5:** Commit with `git commit -m "feat: move hero images and image blocks into the media library"`.

---

### Task 5: `Media::PictureComponent` everywhere images render

**Files:**
- Create: `app/components/media/picture_component.rb` and `.html.erb`, plus a Lookbook preview.
- Modify:
  - the public hero in `app/views/pages/show.html.erb`;
  - `app/components/blocks/image_component.*`;
  - `app/components/rich_text/image_component.*`, whose `src:/alt:/caption:` interface becomes `asset:` plus overrides; update `RichText::BuiltIns`' image render;
  - admin thumbnails where the asset is shown (block card and hero field), which use the `w480` variant or the original.
- Test: `test/components/media/picture_component_test.rb`, plus updates to the rich-text render tests and the block/page render tests.

**Interfaces:**
- **Produces:** `Media::PictureComponent.new(asset:, alt:, sizes: "100vw", css_class: nil)`, which renders `<img src srcset sizes width height alt loading="lazy" decoding="async">`. `alt` is already resolved.

- [ ] **Step 1: Write the failing tests.**
  - Processed variants appear in `srcset`, and width/height come from the asset.
  - `alt` is escaped (`<script>` in the alt shows as text).
  - An unprocessed asset renders `src` only, with no `srcset` attribute (Review Focus 3).
  - The rich-text image uses the node's alt when present and the asset default otherwise; the same holds for the caption.
  - The image block uses the block's `alt`/`caption` overrides, else the defaults.
  - The page hero uses `hero_alt`, else the default.
  - A deleted asset renders nothing.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the full suite, the system tests and rubocop. Expected: PASS.
- [ ] **Step 5:** Commit with `git commit -m "feat: render every image through one responsive picture component"`.

---

### Task 6: Media services, permissions and usage refresh in the write path

**Files:**
- Create: `app/services/media/upload.rb` (final form; replaces `MediaAssets::Create`, so delete that and update its callers), `app/services/media/save.rb` and `app/services/media/destroy.rb`.
- Modify:
  - `app/models/access_control/built_ins.rb` (`media.manage`, label "Manage media");
  - `app/models/access_control/seeds.rb` and a data migration that grants `media.manage` to the existing built-in Admin and Editor groups, idempotently;
  - the grants fixtures;
  - `Pages::Save` and `ContentBlocks::Save`, which accept `hero_media_asset_id` / `media_asset_id`;
  - `Pages::Save`, `ContentBlocks::Save`, `Posts::Save`, `Pages::Destroy`, `Posts::Destroy` and `ContentBlocks::Destroy`, which call `Media::UsageIndex.refresh(owner)` inside their transaction;
  - `app/models/audit/snapshot.rb`, whose page and block snapshots include the reference ids and whose asset snapshot covers title, alt, caption and file metadata.
- Test: `test/services/media/{upload,save,destroy}_test.rb`, plus additions to the authorization matrix and the service contract test (automatic).

**Interfaces:**
- **Produces:**
  - `Media::Upload.call(file:, actor:)` → Result(asset) (needs `media.upload`)
  - `Media::Save.call(asset, attributes: { title: }, translations: { locale => { alt:, caption: } }, actor:)` → Result (needs `media.manage` or ownership)
  - `Media::Destroy.call(asset, actor:)` → Result (needs `media.manage` or ownership; refused while `asset.used?`, with the message "This image is used on …" listing up to 3 usages plus "and N more")

- [ ] **Step 1: Write the failing tests.**
  - Upload records `media.uploaded` with `created_by`.
  - Review Focus 1: uploading the same file twice gives two assets.
  - Save by the owner of an upload works. Save by someone else without `media.manage` is denied. Save with `media.manage` works and records `media.updated` with the changes.
  - Destroy of an unused asset works and records `media.deleted`. Destroy of a used asset is refused, and the message names the page.
  - Review Focus 4: a destroy whose usage check passes while the FK still restricts (simulate a reference row that isn't indexed) returns a failure, not a 500.
  - `Pages::Save` with `hero_media_asset_id`:
    - a valid asset sets it and refreshes the usages;
    - Review Focus 5: an unknown id fails validation;
    - Review Focus 5: an actor without `media.upload` is denied;
    - clearing the hero (`nil`) removes the usage.
  - The same three cases apply to `ContentBlocks::Save`.
  - Saving a post with an image in its body refreshes the `rich_text` usages, and destroying the post removes them.
  - The seeded Admin and Editor groups hold `media.manage`; Author doesn't.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement. Rescue `ActiveRecord::InvalidForeignKey` in `Media::Destroy` into a failure.
- [ ] **Step 4:** Run the full suite and rubocop. Expected: PASS.
- [ ] **Step 5:** Commit with `git commit -m "feat: upload, edit and delete library images through permissioned, audited services"`.

---

### Task 7: The Media module in CS Studio

**Files:**
- Create:
  - `app/controllers/admin/media_controller.rb` (index/show/create/update/destroy; `require_permission "media.upload"`; update and destroy authorize through the services);
  - views and components: `app/components/admin/media/grid_component.*`, `detail_component.*` and their Lookbook previews;
  - `app/javascript/controllers/admin/media_upload_controller.js` (multi-file drag and drop, one request per file, inline errors);
  - `app/views/admin/media/*`.
- Modify: the admin layout sidebar (a "Media" entry with an icon), `config/routes.rb`, and `Admin::MediaAssetsController` (the editor's JSON upload endpoint, which keeps working through `Media::Upload`).
- Test: `test/integration/admin/media_test.rb`, `test/system/admin/media_library_test.rb`

- [ ] **Step 1: Write the failing tests.**
  - Access: the grid needs `media.upload` (403 otherwise).
  - Grid and filters: search by title, alt and filename; filters for unused and mine; 48 per page with next/prev; a constant query count for 10 vs 60 assets.
  - Detail panel:
    - shows "Used on" with links;
    - Delete is disabled with a reason when the image is used;
    - edits autosave through `Media::Save` per locale;
    - a user without `media.manage` who isn't the owner sees read-only fields.
  - Upload: several files succeed; an SVG shows an inline error.
  - System: upload two files by the file input, see them in the grid, open one, set a German alt text, and see it persist.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement. Use the existing confirm-dialog component for Delete.
- [ ] **Step 4:** Run the full suite, the system tests and rubocop. Expected: PASS.
- [ ] **Step 5:** Commit with `git commit -m "feat: browse, upload, edit and delete images in the CS Studio media library"`.

---

### Task 8: One picker for hero images, image blocks and rich text

**Files:**
- Create:
  - `app/components/media/picker_component.*`: a modal with a Library tab (search and paginated grid; returns an asset id) and an Upload tab (through the existing JSON endpoint), plus a Lookbook preview;
  - `app/javascript/controllers/admin/media_picker_controller.js`, which emits `media-picker:picked` with `{ id, url, alt, title }`.
- Modify:
  - The page settings hero field (`app/views/admin/shared/_hero_image_field.html.erb`, `Admin::PageSettingsFormComponent`) and the image block card (`Admin::BlockCardComponent`, `Admin::Columns::ImageColumnComponent`). Each gets a thumbnail, **Choose/Change** (opens the picker), **Remove**, and a hidden `hero_media_asset_id` / `media_asset_id` field that dispatches `input` so autosave saves it.
  - Per-use alt and caption fields show the asset's default as their placeholder.
  - Remove the old file-upload params (`Admin::FileParams` hero/image handling) and their "explicit remove" logic.
  - `app/javascript/controllers/admin/rich_text_controller.js`: the image button opens the picker, or edits the alt of a selected image as today, and inserts `image{asset_id}` from the picked id. It no longer uploads directly.
- Test: updates to the page, block and rich-text system tests, plus `test/system/admin/media_picker_test.rb`.

- [ ] **Step 1: Write the failing tests** (Cuprite, native clicks):
  - Choose an existing library image as a page hero; the public page renders it with `srcset` once variants are processed (`perform_enqueued_jobs`).
  - Upload through the picker's Upload tab into an image block.
  - In a post body, insert the same library image via the picker.
  - The Media module's "Used on" lists the page, the block and the post.
  - Remove the hero, and the usage disappears.
  - Keyboard: Escape closes the picker, and focus returns to the button.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement. Keep the picker free of browser dialogs.
- [ ] **Step 4:** Run the full suite, the system tests (twice) and rubocop. Expected: PASS.
- [ ] **Step 5:** Commit with `git commit -m "feat: pick library images for heroes, image blocks and rich text"`.

---

### Task 9: MCP `list_media` and `get_media`

**Files:**
- Create: `app/mcp/mcp/tools/list_media.rb` and `get_media.rb`, and register them where the MCP server lists its tools.
- Modify: tool descriptions (mention `::image{asset="ID" alt="…"}`).
- Test: `test/integration/mcp_media_test.rb`

- [ ] **Step 1: Write the failing tests.**
  - `list_media(query:)` finds by title and alt. `unused: true` filters.
  - Each entry has id, title, alt, width, height and usage count.
  - `get_media(id)` returns the usages as `{type, id, title}`, listing only owners the token can read (unreadable ones are counted, not named).
  - A token without `media.upload` gets a permission tool error.
  - An unknown id gives "Image not found".
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the full suite and rubocop. Expected: PASS.
- [ ] **Step 5:** Commit with `git commit -m "feat: let MCP clients find library images"`.

---

### Task 10: Docs and final verification

**Files:**
- Modify:
  - `CLAUDE.md`: add a "Media library" architecture subsection in the file's style, covering `Media::Asset`, `Media::Usage`/`UsageIndex`, the references, the alt resolver, the variants, `Media::PictureComponent`, the picker, the services, the permissions and the rake tasks. Update the "Rich text" section's image mentions.
  - `docs/roadmap.md`: mark the media library done and remove the interim-state row about unreferenced MediaAssets and ActionText orphans (point to `media:orphans`). Add the spec §8 out-of-scope items as open rows.

- [ ] **Step 1:** Update the docs.
- [ ] **Step 2: Full verification.** All green:
  - `PARALLEL_WORKERS=1 bin/rails test`;
  - `bin/rails test:system` (twice);
  - `bin/rubocop`, `bin/brakeman -q --no-pager`, `bin/bundler-audit`, `bin/importmap audit`;
  - `bin/rails zeitwerk:check`;
  - `bin/rails db:reset` (seeds create at least one library image used as a hero), then `bin/rails media:reindex` and `bin/rails media:orphans`.
- [ ] **Step 3:** Commit with `git commit -m "docs: record the media library"`.
