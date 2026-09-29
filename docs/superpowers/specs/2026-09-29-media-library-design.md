# Media library

Sub-project 6a of the own-admin roadmap: the first piece of sub-project 6. The pieces are 6a media, 6b trash, 6c dashboard, 6e translation helpers, 6d invites and 6f German admin UI, built in that order. The design was approved in brainstorming on 2026-09-29. This document is the binding spec for the implementation plan.

## 1. Purpose

Images today live in four separate places, each stored on its own:
- page hero images (`Page has_one_attached :hero_image`);
- image blocks (`ContentBlock has_one_attached :image`);
- rich-text images (`MediaAsset`, referenced by id from the document);
- the site logo (`SiteSetting has_one_attached :logo`).

As a result, a picture used twice is stored twice, and there's no library to browse or reuse from. Unused uploads are never cleaned up (roadmap interim state), and nothing produces responsive sizes.

This sub-project gives CS Studio **one media library** that every image use points to, with:
- per-use alt text and caption that fall back to the image's own defaults;
- responsive WebP sizes generated in the background;
- a usage index behind "used on…", the "Unused" filter and safe deletion;
- one picker for hero images, image blocks and rich text.

**Success:**
- An editor uploads a photo once and uses it as a hero image, in an image block and inline in a post.
- Its alt text is written once but can differ where the context needs it.
- Public pages serve right-sized WebP files without layout shift.
- An image that's in use can't be deleted.
- The library shows exactly where each image is used.

## 2. Decisions (from brainstorming)

| Topic | Decision |
|---|---|
| Storage | **One library.** Hero images, image blocks and rich-text images all reference a library image. The **logo stays separate**, because logos are often SVG and the library refuses SVG (it can carry script). |
| Alt text and caption | **Default on the image, overridable per use.** The image holds translated defaults; each use may override them and falls back to the default when empty. |
| Responsive sizes | **Generated in the background after upload** (Active Storage preprocessed variants on Solid Queue). Pages list only the sizes that already exist and never wait for one. |
| Cleanup | **Manual.** The library has an "Unused" filter and deleting an image in use is refused. A one-off command removes blobs nothing references. Automatic cleanup waits for Trash (6b). |
| References | **A direct reference on each record** (`pages.hero_media_asset_id`, `content_blocks.media_asset_id`; rich text keeps `asset_id` in the document) plus a **derived usage table** (`media_usages`) rebuilt by the services. The existing translated alt and caption fields become the per-use overrides. |
| Namespace | Domain namespace `Media::`. `MediaAsset` is renamed to `Media::Asset`; its table `media_assets` is unchanged. |

## 3. Data

### 3.1 `Media::Asset` (table `media_assets`)

**Existing behaviour, kept:**
- `has_one_attached :file`;
- byte-sniffed type limited to png, jpeg, gif and webp;
- a maximum of 10 MB;
- the blob's content type is forced to the sniffed type;
- `width`, `height`, `byte_size`, `content_type` and `created_by_id`.

**New:**
- **`title`** (string, not null): defaults to the file name without its extension, and is editable.
- **`alt` and `caption`**: translated through Mobility jsonb, with the same fallbacks as the rest of the app.
- **Named variants:** `w480`, `w960`, `w1600` and `w2400`.
  - Each resizes to fit that width without upscaling (a variant wider than the original is never made) and converts to WebP.
  - Each is declared `preprocessed: true`.
  - GIFs get no variants, so animations are kept.
- **`#srcset`**: returns only the variants whose representation has already been processed (`variant.processed?`), with their widths. `#src` is the original URL.
- **`#alt_text(override:, locale: I18n.locale)` and `#caption_text(override:, locale:)`**: the one resolver for alt and caption. It returns `override.presence`, then the image's default in `locale`, then the usual fallback.

### 3.2 `Media::Usage` (table `media_usages`)

| Column | Notes |
|---|---|
| `media_asset_id` | FK, not null, `on_delete: :restrict` |
| `owner_type` / `owner_id` | `Page`, `ContentBlock` or `Post` |
| `role` | `hero`, `block_image` or `rich_text` |
| `locale` | nil for hero and block image; the document's locale for `rich_text` |

Unique index on `(media_asset_id, owner_type, owner_id, role, locale)`, plus an index on `(owner_type, owner_id)`.

Nobody edits `media_usages` directly. `Media::UsageIndex.refresh(owner)` recomputes one owner's rows from its current state:
- a page's hero;
- a block's image;
- rich-text `image` nodes across every locale of a post's or block's body.

`Media::UsageIndex.rebuild_all` recomputes the whole table. A rake task, `media:reindex`, calls it.

### 3.3 References

| Record | Reference | Per-use override fields |
|---|---|---|
| `Page` | `hero_media_asset_id` (FK, restrict, nullable) | existing translated `hero_alt` |
| `ContentBlock` (image type) | `media_asset_id` (FK, restrict, nullable) | existing translated `alt`, `caption` |
| Rich-text `image` node | `asset_id` attribute (unchanged) | the node's `alt`, `caption` |

`has_one_attached :hero_image` on `Page` and `has_one_attached :image` on `ContentBlock` are removed after the migration.

### 3.4 Migration

1. Add the columns and tables. Add `title`, `alt` and `caption` to `media_assets`.
2. For every page hero and block image attachment:
   - create a `Media::Asset` that re-attaches the **same blob**, so nothing is copied;
   - reuse one asset per blob checksum, so identical files collapse into one image;
   - set the reference;
   - copy the attachment's file name into `title`.
3. Run `Media::UsageIndex.rebuild_all`.
4. Remove the old `hero_image` and `image` attachment rows. The blobs stay; they now belong to the assets.
5. Run a separate rake task, `media:orphans`. It lists blobs with no attachments; with `CONFIRM=1` it purges them. This covers the ActionText import leftovers.

The migration is reversible in structure. On `down`, the attachments are restored from the references.

## 4. Rendering

- **`Media::PictureComponent`** takes `asset:`, `alt:`, `sizes:` and `class:`. It renders an `<img>` with:
  - `src` pointing at the original;
  - `srcset` built from `asset.srcset`, which lists only processed variants;
  - `sizes`;
  - `width` and `height`, which prevent layout shift;
  - `loading="lazy"` and `decoding="async"`.
  - The `alt` passed in is already resolved.
- **Where it's used:** the public hero image, the image block component and `RichText::ImageComponent` all render through it, with their overrides resolved via `alt_text` and `caption_text`.
- **Cache:** the rich-text render cache key already includes `PublicSite.content_version`, which counts media assets, so editing an image's default alt text invalidates rendered bodies.
- **Missing images:** if an asset has been deleted, the public site renders nothing for it, as today.

## 5. Permissions, services, audit and MCP

### 5.1 Permissions and services

- **Permissions** (registry): `media.upload` already exists; `media.manage` is new.
  - `media.upload`: upload, browse the library and choose images.
  - `media.manage`: edit any image's title, alt and caption, and delete images. A user can always edit or delete their own uploads.
  - Seeds: Admin and Editor get `media.manage`; Author keeps `media.upload`.
  - The library itself isn't read-scoped; anyone holding `media.upload` sees every image.
- **Services:**
  - `Media::Upload`: replaces `MediaAssets::Create`. Records `media.uploaded`.
  - `Media::Save`: edits title and translations. Records `media.updated`, with field changes.
  - `Media::Destroy`: refuses while any `media_usages` row exists, with an error message that lists where the image is used, and records `media.deleted`. The database's `restrict` foreign keys back this up.
  - `Pages::Save` and `ContentBlocks::Save` accept `hero_media_asset_id` and `media_asset_id`. Choosing an image requires `media.upload` and an existing asset.
  - `Pages::Save`, `ContentBlocks::Save`, `Posts::Save` and all destroy services call `Media::UsageIndex.refresh(owner)` inside their transaction. A destroyed owner's rows are removed.
  - The contract test covers the new services.
- **Audit snapshots:** a page's snapshot records `hero_media_asset_id`; a block's records `media_asset_id`.

### 5.2 MCP

- **New tools:**
  - `list_media(query:, unused:)`: returns id, title, alt, dimensions and usage count, for use in `::image{asset=…}`.
  - `get_media(id:)`: returns id, title, alt, caption, dimensions and the list of usages.
  - Both require the token to hold `media.upload`.
- **Uploading through MCP** is out of scope.

## 6. CS Studio

- **Media module**, in the sidebar for anyone with `media.upload`:
  - **Grid:** thumbnails from the `w480` variant, falling back to the original; a search box covering title, alt and filename; filters for all, unused and uploaded by me; about 48 per page; constant-query rendering.
  - **Upload:** drag and drop or a file picker, several files at once, each through `Media::Upload`, with per-file errors shown inline.
  - **Detail panel:**
    - preview, type, size and dimensions;
    - title;
    - alt text and caption per locale, using the standard language switcher and autosave;
    - **Used on**: links to each page, post and block;
    - **Delete**, disabled while the image is used, with the reason shown.

    Editing and deleting are gated per §5.1.
- **`Media::PickerComponent`** is one modal with a **Library** tab (search and pick) and an **Upload** tab, and it returns an asset id. It's used for:
  - the page hero image (replacing the hero upload field and its explicit-remove handling);
  - the image block's image;
  - the rich-text editor's image button (replacing its direct-upload popover).

  Each place shows a thumbnail, **Change**, **Remove**, and per-use alt and caption fields whose placeholders show the image's default in the current locale.
- No browser dialogs: use the existing confirm-dialog component for delete.

## 7. Testing

- **Migration:**
  - hero and block images become assets that reuse the blob;
  - identical files collapse into one asset;
  - references are set;
  - usages are rebuilt;
  - rollback restores the attachments.
- **`Media::UsageIndex`:** all three sources, rich text per locale, refresh on save and destroy, and `rebuild_all` giving the same result.
- **Deletion:** `Media::Destroy` refuses while the image is in use (the service and the database FK), and succeeds when it's unused. Also check permissions and ownership, including editing your own upload.
- **Alt and caption resolver:** override, then the image's default, then the fallback locale.
- **Variants:** processed by a job after upload; `srcset` lists only processed variants; no upscaling; GIFs are skipped.
- **Audit:** `media.uploaded`, `media.updated` and `media.deleted`, carrying the actor and the changes.
- **MCP:** `list_media` and `get_media`, including a token without `media.upload`.
- **System tests (Cuprite):**
  - upload in the library;
  - pick an image as a hero, see it rendered with `srcset` on the public page;
  - pick the same image inside rich text;
  - see "Used on";
  - Delete is disabled while the image is used.

## 8. Out of scope and interim states

**Out of scope** (recorded in `docs/roadmap.md`):
- video and document files;
- cropping and a focal point;
- folders and tags for media;
- automatic cleanup (after Trash, 6b);
- uploads through MCP;
- moving the logo into the library, which would need SVG sanitising.

**Interim state:** until a variant has been processed, a page serves the original file.
