# ContentSpiel — Page Tree & Content Blocks

Date: 2026-09-13
Status: Draft for review

## 1. Overview

A `Page` model forming the site's entire public navigation tree
(via the `closure_tree` gem), replacing the fixed `/resume`, `/blog`,
`/now` routes described in the original design spec. Each `Page` is
composed of an ordered list of `ContentBlock` records. `Post` (the
model from the Foundation plan — `content_type`: `blog`,
`resume_entry`, `now_update`) is unchanged and stays a separate
content type; it never becomes a page itself. Pages pull `Post`
content in only through a dedicated `post_list` content block.

This mirrors TYPO3's own architecture: a page tree of navigable
nodes, each built from content elements, with structured domain
records (like blog posts) living outside the tree and rendered into
a page via a "plugin" content element.

This spec supersedes the "Public site & SEO" item in the original
spec's roadmap
(`docs/superpowers/specs/2026-09-13-contentspiel-design.md`) — that
item was never implemented, so there is no existing routing/view code
to migrate away from, only the Foundation plan's data layer and Avo
admin to build on top of.

## 2. Goals

- Let the site owner build and rearrange the public site's structure
  (pages, nesting, navigation) without touching code.
- Compose each page from a small set of well-understood block types:
  rich text, image, and a "post list" block that embeds `Post`
  content (a blog listing, a resume timeline, the latest now-update).
- Support both list and single-item views through the same page (a
  "Blog" page both lists posts and serves each post's permalink)
  without a page-tree node per `Post`.
- Carry the original spec's i18n (English/German/Spanish) and SEO
  commitments into the new page/block model.

## 3. Data model

### `Page`

- Tree: `closure_tree` (`acts_as_tree`), giving `parent`/`children`
  and ancestor/descendant queries. Sibling ordering uses
  `closure_tree`'s own `order_siblings_by` support (backed by a
  `position`-style column it manages) rather than a hand-rolled
  ordering mechanism — the Avo admin's "position field" in §5 is
  this same gem-managed column, not a separate concept. Exactly one
  `Page` may have no parent — the root, mapping to `/` — enforced by
  a singleton-style validation (same pattern as `SiteSetting`).
- `page_type`: enum (`standard`, `landing`). Determines which
  page-level fields are meaningful and which layout renders.
- Translatable (Mobility, matching `Post`): `title`, `slug`,
  `subtitle` (used only when `page_type: landing`), `meta_title`,
  `meta_description`.
- Not translatable: `page_type`, `published_at`, `hero_image`
  (Active Storage attachment, used only when `page_type: landing`).
- Slug uniqueness is scoped to siblings (same `parent_id`) per
  locale — not the full computed path. A page's full URL path is
  derived from its ancestors' translated slugs in the requested
  locale; because slugs vary by locale, the full path is computed
  and cached per-locale (a small jsonb column, e.g. `cached_paths:
  {"en" => "/about/team", "de" => "/ueber-uns/team"}`), recomputed on
  save whenever the page's own slug or its position in the tree
  changes.
- Deleting a `Page` that still has children is rejected — children
  must be reparented or removed first (matches the destroy-guard
  instinct already applied to `User`/`ApiToken` in the Foundation
  plan's final review).

### `ContentBlock`

- Shared-shape model (same pattern as `Post`): one table, one
  `block_type` enum, not STI, not per-type models. Real-world
  precedent: TYPO3's `tt_content` table works exactly this way, as do
  Craft CMS's Matrix blocks.
- `page_id`, `block_type` (enum: `rich_text`, `image`, `post_list`),
  `position` (plain integer — ordering among a page's own blocks;
  this list doesn't need its own tree, just sibling order).
- `rich_text`: `has_rich_text :body` (ActionText, translatable via
  Mobility's ActionText backend, matching `Post#body`).
- `image`: `has_one_attached :image` (Active Storage) plus a
  translatable `caption`.
- `post_list`: filter criteria stored in a jsonb `settings` column —
  `content_type` (validated against `Post.content_types`), optional
  `tag`, `limit`. Not translatable (the criteria are structural, like
  `Post#metadata`).

## 4. Public routing & rendering

A single catch-all route (locale-prefixed, e.g. `/en/*path`) resolves
any request path against the `Page` tree using each page's
per-locale cached path.

**List vs. detail resolution.** There is no `Page` node per `Post` —
so an individual post's permalink (e.g. `/en/blog/my-post-slug`)
is resolved as a fallback when the full path doesn't match a `Page`
exactly: the resolver treats the last path segment as a candidate
`Post` slug and the remaining segments as a `Page` path. If that
`Page` exists and has a `post_list` block, and a `Post` matching that
block's `content_type`/tag criteria has the trailing slug, the single
`Post` renders inside the `Page`'s layout in place of the list.
Otherwise: 404. This is the same pattern Wagtail's
`RoutablePageMixin` and TYPO3's plugin content elements both use for
a listing page that also serves detail views — not a novel mechanism
built for this project.

Root `Page` (`parent: nil`) resolves to `/` (and `/en/`, `/de/`,
`/es/`).

## 5. Avo admin

- `Page` resource: a parent picker (closure_tree-backed), a
  `position` field for sibling ordering, `page_type`, and hero fields
  (`subtitle`, `hero_image`) shown only when `page_type: landing`.
- `ContentBlock`s are edited as a nested/inline list directly on the
  `Page` form (add, reorder via `position`, remove) — not a separate
  top-level Avo resource.
- No custom drag-and-drop tree widget in v1 (YAGNI) — the parent
  picker plus `position` field is enough to build and rearrange the
  tree.

## 6. Internationalization

Consistent with the original spec's i18n commitment (§12): `Page`'s
`title`/`slug`/`subtitle`/`meta_title`/`meta_description` and
`ContentBlock`'s `rich_text` body / `image` caption are all
Mobility-translatable, using the same jsonb backend as `Post`.
Locales stay English (default), German, Spanish. A page missing a
translation in the current locale falls back to the default locale,
same as `Post`.

## 7. SEO

`Page#meta_title`/`meta_description` (falling back to `title`/an
excerpt-like value) feed the per-page `<title>`, meta description,
and Open Graph tags described in the original spec's SEO section
(§7). Sitemap generation walks the `Page` tree (via `closure_tree`)
across all locales, rather than enumerating a fixed route list.

## 8. Error handling

- Exactly one root `Page` may exist — a second parent-less `Page` is
  rejected (singleton-style validation, same shape as `SiteSetting`).
- A `Page` with children cannot be destroyed until its children are
  reparented or destroyed first.
- `closure_tree` itself rejects a page becoming its own ancestor.
- An unmatched path (no `Page`, no post-detail fallback) is a
  standard 404.
- Slug uniqueness is validated per-locale, scoped to `parent_id`
  (siblings), not against the full computed path.

## 9. Testing

- **Model tests:** root-singleton validation; sibling-scoped slug
  uniqueness per locale; `ContentBlock` type-specific behavior (rich
  text body persists, image attaches, `post_list` settings validate
  `content_type` against `Post.content_types`); destroy-blocked while
  children exist.
- **Request tests:** nested-page path resolution across all three
  locales; the list-vs-detail fallback for `post_list` blocks (both a
  list render and a single-`Post` render through the same `Page`);
  404 for an unmatched path.
- **Avo tests:** creating and reordering a page's content blocks
  inline; the parent picker; hero fields appearing only for
  `page_type: landing`.

## 10. Out of scope / deferred

- A visual drag-and-drop tree editor in Avo (parent picker + position
  field is v1's mechanism).
- Page versioning/revision history.
- Multiple independent root pages (multi-site) — single root only.
- Anything already deferred by the original spec (§14): multi-tenant
  SaaS, a self-hostable template for others, deploy/Kamal
  configuration, roles/permissions beyond one admin, `[[wiki-link]]`
  parsing, a public-facing mind-graph view.
