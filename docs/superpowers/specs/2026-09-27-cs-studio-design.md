# CS Studio: the admin shell MVP

Sub-project 3 of 7 on the way to ContentSpiel's own admin (`docs/roadmap.md`, Phase 2). Design approved in brainstorming on 2026-09-27. This document is the binding spec for the implementation plan.

## 1. Purpose

Editors get their own admin, **CS Studio**. It replaces Avo for the everyday content work:
- building and reordering the page tree;
- editing pages with inline, type-specific blocks;
- writing posts with typed fields and tags;
- publishing, scheduling and unpublishing;
- previewing;
- editing every enabled language against the primary language.

**Success:** an editor completes the product review's core content stories (docs/product/2026-09-26-backend-product-review.md §4 "Authoring & editing", "Pages & navigation", "Publishing workflow & preview", "Translations") without opening Avo.

**Builds on:**
- **Foundations:** services, `PublicSite::Urls`, `/preview`, `Locales`.
- **Open types:** the `BlockTypes`/`ContentTypes`/`FieldGroups` registries, `ContentModel::FieldSet`, and view components.

Rich text stays ActionText/Trix; Tiptap is sub-project 4.

**Greenfield:** interim behaviour that depends on a later roadmap item is acceptable when it's visible to editors and tracked (see §7).

## 2. Decisions (from brainstorming)

| Decision | Chosen | Rejected |
|---|---|---|
| MVP scope | Content core: Pages (tree + editor + blocks), Posts, Tags, publish/schedule/preview. Settings, users, tokens and system status stay in Avo until sub-project 6. | Adding settings/languages; everything Avo does now. |
| Admin path | Configurable `ADMIN_PATH` (env, read at boot), default **`/cs-studio`**. Sign-in and password reset move under it. `/admin` invites scanners. | `/admin`. |
| Saving | **Autosave**: debounced per field/block, straight to the record (interim, §7). | One form with Save; per-block Save buttons. |
| Languages | One language switcher for the whole editor. In a non-default language each translatable field shows the **primary-language original as read-only text**, with a reserved slot for a later AI "Translate" action. | Per-field tabs (Avo today); side-by-side translate mode (later, maybe). |
| Technology | Server-rendered Hotwire: Turbo Frames for the columns, Turbo Streams for autosave responses, Stimulus controllers, SortableJS via importmap; admin UI kit as view components. | JS islands (React/Vue: needs a build, conflicts with import maps); plain full-page forms. |

## 3. Routing and access

- **`ADMIN_PATH`:**
  - `config/initializers/admin_path.rb` reads `ENV.fetch("ADMIN_PATH", "cs-studio")` once;
  - the value is validated as a single URL-safe segment and exposed as `ContentSpiel::ADMIN_PATH`;
  - routes use `scope ContentSpiel::ADMIN_PATH, module: :admin, as: :admin`.
- **Routes inside the scope:**
  - `/` → pages home;
  - `pages/:id`, `pages/:page_id/content_blocks` (create/update/destroy/reorder);
  - `tree` (move/reorder);
  - `posts`, `posts/:id`;
  - `tags`;
  - `sign-in` (the former `SessionsController`);
  - `password` (the former `PasswordsController`).
- **Public routes removed:** `/session` and `/passwords` go away (greenfield). `after_authentication_url` points to the admin home, and so does `request_authentication`'s sign-in redirect.
- **Route order:** declared before the public catch-alls and `/preview`. `Setup::RedirectConstraint` stays in front of everything.
- **No shadowing:** a root child page whose slug (any locale) equals the first segment of `ADMIN_PATH` is invalid ("is reserved for the admin"). Validate it in `Page` alongside the slug checks.
- **Avo:** stays mounted at `/avo` behind the same sign-in, and is linked from the modules column as "(old admin)" for settings, users, API tokens and system status. The preview banner's "Edit" link, sign-in landing and any "edit" links point at CS Studio.

## 4. Shell

### 4.1 Controllers

- **`Admin::BaseController < ApplicationController`:**
  - layout `admin`;
  - `Current.channel = :admin`;
  - `authorize!` no-op hook for roles (sub-project 5);
  - `admin_locale`: the `?locale=` param if it's in `Locales.enabled`, else `Locales.default`, and a helper for building links that keep it.
- **Resource controllers:**
  - `Admin::PagesController` (show/new/create/update/destroy + publish actions);
  - `Admin::ContentBlocksController` (create/update/destroy/reorder);
  - `Admin::TreeController` (move);
  - `Admin::PostsController` (index/new/create/show/update/destroy + publish actions);
  - `Admin::TagsController` (index/update/destroy);
  - `Admin::SessionsController` and `Admin::PasswordsController` (moved).
- **Writes** go only through services: `Pages::Save`/`Move`/`Destroy`, `ContentBlocks::Save`/`Reorder`, `Posts::Save`, plus a `Tags::Rename`/`Tags::Destroy` pair (new, small).

### 4.2 Layout (`layouts/admin.html.erb`, product `--cs-*` tokens, product Tailwind build)

- **Modules column:**
  - Pages, Posts and Tags, each with an icon and label;
  - a divider, then "(old admin)" links to Avo (Settings, Users, API tokens, System status);
  - at the bottom: the theme toggle and sign-out.
  - It collapses to icons on narrow screens.
- **Page tree column** (Pages module only; resizable and collapsible, a drawer on narrow screens):
  - one node per page: title in the admin locale (with fallback), a status dot (draft / scheduled with its date on hover / live), child count;
  - the selected node is highlighted;
  - "+" on hover adds a child;
  - drag handles reorder and reparent;
  - Turbo Frame `tree`, re-rendered after structural changes.
- **Content column:** Turbo Frame `content`. Tree clicks and module links target it and advance the URL.
- **Visual source:** the Claude Design project "Content Spiel design system" backend screens and the existing product tokens. Mobile gets basic usability only.

### 4.3 Admin UI kit (view components, `app/components/admin/`)

- **Components:** `ButtonComponent`, `StatusBadgeComponent`, `LanguageSwitcherComponent`, `SaveStatusComponent`, `TreeNodeComponent`, `BlockCardComponent`, `BlockPickerComponent`, `EmptyStateComponent`, `ConfirmDialogComponent`.
- **Field components:** one per field type, rendered from a `ContentModel::Definition::Field`: string, text, integer, boolean, date, url, select, content_type, tag, group and groups (nested fieldset / repeatable list).
- **Column fields:** components for the columns a type opts into (`body` → Trix, `image` → upload, `caption`, `alt`), plus page and post column fields (title, slug with URL preview, excerpt, meta fields, hero image and alt).
- **Previews:** every component has Lookbook previews.
- **Tailwind:** the product build adds `@source` for `app/components/admin` and `app/views/admin`.

## 5. Editors

### 5.1 Page editor (`pages/:id?locale=xx`)

- **Header:**
  - title and public URL (copy + open);
  - status badge;
  - actions: Preview (new tab, `/preview/...`), Publish now / Unpublish / Schedule… (datetime), Delete (leaf pages only; disabled with a reason otherwise).
- **"Page settings" (collapsible):** title, slug + URL preview, page type, subtitle, hero image + alt (landing), and meta title/description under "SEO".
- **Blocks:**
  - Each block is a card with its type label, drag handle and collapse toggle, and a "⋯" menu (Duplicate, Move up/down, Delete).
  - The fields come from the block definition's schema plus its `uses` columns.
  - "+ Add block" between cards and at the end opens a picker listing `BlockTypes.all` by label.
- **New page:**
  - "+" in the tree or "Add subpage" asks for a title only, then creates through `Pages::Save` (the slug fills itself) and opens the editor;
  - a draft by default.

### 5.2 Post editor and list

- **List (`posts`):**
  - filters: content type (registry), status, tag, title search;
  - columns: title, type (label + colour), status, publish date, tags, languages filled;
  - "New post" asks for the content type first.
- **Editor (`posts/:id?locale=xx`):**
  - the page editor's shell, autosave and language behaviour;
  - the content type is fixed after creation;
  - title, slug + URL preview, excerpt, body (Trix);
  - the content type's typed fields, with `group` as a nested fieldset and `groups` as an add/remove/reorder list;
  - tag input: comma-separated with autocomplete, new tags created on save through `Posts::Save` `tag_names`;
  - the canonical URL, or "Not listed on any page yet — add a post list block for this type".

### 5.3 Tags (`tags`)

- A list with post counts, inline rename and delete (only unused tags, or with a confirmation that it removes the tag from N posts).
- `Tags::Rename` re-syncs public paths for posts listed by tag-filtered blocks. This closes the foundations follow-up "tag rename doesn't resync".

## 6. Autosave and languages

### 6.1 Autosave

- **Controller:** a Stimulus `autosave` controller per form (the page settings form, each block card, the post form). It sends a PATCH after 1s of inactivity and immediately on blur, and runs one request at a time, queueing the latest.
- **Endpoints:** each form saves to its own endpoint, sending only that form's fields plus `locale`. Translated values go into `translations[locale]` and untranslated ones into `attributes`, split by the definition's field schema (column fields by the model's `translates` list).
- **Responses:** Turbo Stream actions:
  - replace the `save-status` element ("Saving…" → "Saved hh:mm" / "Couldn't save — N problems");
  - replace the form's error slots (per-field messages keyed by the service Result's per-field errors);
  - for create, insert the new block card.
- **Trix:** saves on `trix-change` (debounced). Attachments keep using ActionText direct upload.
- **Reorder** (drag in the block list or the tree) posts ordered IDs / parent+position immediately.
- **Concurrency:** each form carries the record's `updated_at` as loaded. A save whose base is older than the record answers with a warning status ("Changed elsewhere — reload to see the latest"). The save still applies (last write wins); there's no merging.
- **Offline or failed request:** the status shows "Not saved — retrying" and the controller retries with backoff (3 tries), then "Not saved — check your connection".

### 6.2 Languages

- **Switcher:** a language switcher in the content header lists `Locales.enabled`, with a dot marking languages that have empty *required* translated fields. Switching reloads the content frame with `?locale=`.
- **Non-default language:** each translatable input shows the primary-language (`Locales.default`) value as read-only text beside or under it, labelled with the language name. An empty slot `data-translate-slot` is reserved per field for a later "Translate from <primary>" action (AI assistant, roadmap Phase 3).
- **Untranslated fields** render once, labelled "Same in all languages".

## 7. Known interim states (tracked; add to docs/roadmap.md)

- **Autosave writes live:** on a published page or post, edits appear on the public site as you type. The editor header says so ("Live — changes appear on the site as you edit"). This is resolved by pending revisions (Phase 3 "Versioning", then release management): autosave will write a draft revision, and publishing will apply it.
- **Avo is still mounted** for settings, users, tokens and system status until sub-project 6, and removed in sub-project 7.
- **No trash:** deletes are permanent (with confirmation) until sub-project 6.

## 8. Error handling

- Service error Results become per-field messages in the form, and the save status shows the count.
- Delete of a page with children: the button is disabled with a reason. A direct request gets a 422 with the service error.
- Unknown block or content types (a removed plugin): the card shows "Unavailable type — <name>" with Delete only; lists show the raw type name.
- Stale `?locale=` (disabled language): falls back to the default language.
- Unauthenticated requests go to `<ADMIN_PATH>/sign-in`. Setup-required redirects still win.

## 9. Testing

- **Integration tests (most coverage):**
  - every endpoint: page and post create/update (translated vs untranslated split, per-field errors as Turbo Streams), block create/update/destroy/reorder, tree move, publish/schedule/unpublish, tag rename/delete (with the path resync);
  - the `locale` param and fallback;
  - the stale-`updated_at` warning;
  - `ADMIN_PATH` routing including sign-in, and the reserved slug;
  - the Avo links.
- **Component tests + Lookbook previews** for the admin UI kit and every field component.
- **System tests** (scripted clicks like the setup wizard test; about 5):
  - autosave updates the status line and persists;
  - drag-reorder blocks;
  - drag-move a page in the tree;
  - adding a block through the picker;
  - switching language shows the primary original and saves into the selected language;
  - editing a repeatable group (add, reorder, remove) on a test-only content type.
- **Regression:** existing tests stay green. Sign-in and password tests move to the new paths.

## 10. Out of scope

- Roles/permissions and the audit log (sub-project 5).
- Trash, media library, dashboard, settings/users/tokens/languages screens, invites, admin i18n (sub-project 6).
- Removing Avo (sub-project 7).
- Pending revisions / drafts of live content and release management (Phase 3).
- Tiptap (sub-project 4).
- The AI translate action (only the slot exists).
- Real-time collaboration.
- Full mobile editing.
