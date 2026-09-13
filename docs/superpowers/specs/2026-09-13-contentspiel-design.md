# ContentSpiel — Personal Software Development Site with Avo CMS

Date: 2026-09-13
Status: Draft for review

## 1. Overview

A Rails 8 application, named `ContentSpiel`, that serves the owner's
personal software-development site — a resume/experience timeline, a
blog, and a "now" update log — authored through an Avo-powered admin
CMS. Content is also manageable programmatically through an embedded
MCP server, so an AI agent session can create or update content
directly.

This is a separate project from the owner's existing `photofolio` app,
sharing its general Rails/Tailwind/Hotwire conventions but not its
codebase, database choice, or deploy target.

The project is built cleanly enough to be reused as a template later,
but this spec deliberately does not design that reuse — see
[Out of scope](#9-out-of-scope--deferred).

## 2. Goals

- Publish three kinds of content (resume entries, blog posts, now-page
  updates) from one coherent data model.
- Manage that content through Avo, with room to add a second author
  role later without a redesign.
- Allow the same content to be created/edited via an MCP server, so
  agent sessions can perform content operations directly.
- Support full multi-language content translation from day one.
- Be good at SEO: structured data, sitemaps, social preview tags.
- Support rich embeds (YouTube, PDF) in post bodies.
- Provide an admin-facing "mind graph" view of how posts relate to
  each other.
- Provide a first-run setup wizard so the app is usable immediately
  after `rails db:create db:migrate` with no console commands.

## 3. Tech stack

- Rails 8, following Rails/omakase defaults wherever a choice isn't
  otherwise specified in this document.
- **Postgres** (not sqlite, unlike photofolio) — chosen for native
  `jsonb` and because the Mobility translation backend used for i18n
  is jsonb-based.
- Tailwind CSS, Hotwire (Turbo + Stimulus), importmap-rails for JS
  (matches photofolio's asset approach).
- ActionText (rich text) + Active Storage (file attachments).
- solid_queue / solid_cache for background jobs/caching (Rails 8
  default), even though Postgres is the primary datastore.
- Rails 8's built-in authentication generator
  (`bin/rails generate authentication`) for the admin `User` model —
  chosen over Devise since a single-admin site doesn't need Devise's
  extra strategies/features, and adding a `role` column later isn't
  blocked by this choice either way.
- `avo` gem for the admin CMS.
- `mobility` gem for translatable attributes (jsonb backend).
- `sitemap_generator` gem for `sitemap.xml`.
- Testing via Rails' default minitest + fixtures (no RSpec/FactoryBot).
- Deploy target: explicitly **not decided** in this spec (see
  [Out of scope](#9-out-of-scope--deferred)). This spec covers local
  development and application architecture only.

## 4. Data model

### `Post`

The shared model behind all three content types.

| Column | Type | Notes |
|---|---|---|
| `content_type` | enum (`blog`, `resume_entry`, `now_update`) | Not translatable. Structural. |
| `title` | string | Translatable (Mobility). |
| `slug` | string | Translatable (Mobility). Unique per `(locale, content_type)`. |
| `body` | ActionText rich text | Translatable (Mobility's ActionText backend). Supports file attachments (PDF) natively; supports a custom YouTube attachable (see [§8](#8-rich-content--embeds)). |
| `excerpt` | string | Translatable (Mobility). Optional. Used for SEO meta description / blog list previews. |
| `published_at` | datetime, nullable | Not translatable — one publish date regardless of locale. `nil` = draft. |
| `metadata` | jsonb | Not translatable. Structural, content-type-specific data: for `resume_entry`, holds `company`, `role_type` (`ic` or `lead`), `start_date`, `end_date`. Empty/unused for `blog` and `now_update`. |

Ordering: resume timeline and now-page archive both order by
`metadata->>'start_date'` (resume) or `published_at` (now updates),
descending. `metadata.start_date` / `metadata.end_date` are stored as
ISO 8601 date strings (`YYYY-MM-DD`), so lexicographic sort on the
jsonb text value matches chronological order.

### `Tag` + join table

Plain `has_many :through`, no gem. Tag `name` is **not** translatable
in v1 — tags are treated as internal categorization labels, not
user-facing translated copy. This is an explicit simplification, not
an oversight.

### `PostRelation` (mind-graph edges)

Self-referential join table: `post_id`, `related_post_id`. Rows are
stored directionally but treated as **undirected** edges everywhere
they're read (graph view, any future "related posts" UI) — a
relation created from A→B is equivalent to B→A, and duplicate reverse
rows are prevented at the model level (validation, not a DB
constraint, to keep the migration simple).

Populated via an explicit multi-select field in Avo's `Post` form —
**not** by parsing `[[wiki-link]]` syntax out of body text. Parsing
can be added later as an additional way to create the same
`PostRelation` rows, without changing this table's shape.

### `SiteSetting`

Singleton (single row, enforced at the model level). Holds:
`title`, `tagline`, `social_links` (jsonb), `logo` (Active Storage
attachment), `default_locale`. Editable via Avo after initial setup.

### `ApiToken`

Backs MCP authentication. Stores a hashed token (never the raw value
after generation), so it can be regenerated/revoked from Avo without
a redeploy. One active token is sufficient for v1 (no per-client
scoping).

### `User`

Rails 8 generated auth model (`email`, `password_digest`, plus its
`Session` model for session-based login). Single admin account for
v1. No `role` column yet — adding one later is a normal migration and
isn't blocked by any decision in this spec.

## 5. Admin (Avo)

- One `Post` Avo resource, with a `content_type` filter/scope so it
  behaves like three logical sections (Resume, Blog, Now) inside one
  admin, rather than three separate resources.
- `Post` form includes a locale switcher/tabs (via Mobility's Rails
  integration) so each translatable field can be edited per-locale.
- `Tag` resource, referenced from `Post` via a tags field.
- `SiteSetting` resource (effectively a single-record settings page).
- `ApiToken` resource with a "regenerate" action.
- A custom Avo page/tool for the **mind graph**: renders `Post` nodes
  and `PostRelation` edges via a lightweight JS force-directed graph
  library (pinned through importmap, no separate bundler). Admin-only
  in v1; a public-facing version is deferred (see
  [§9](#9-out-of-scope--deferred)).

## 6. Public site & routes

Locale-prefixed routes throughout (e.g. `/en/blog`, `/es/blog`), with
a locale switcher in the layout and fallback to the default locale
when a translation is missing for the current locale.

- `/:locale/` — landing/intro.
- `/:locale/resume` — experience timeline from `content_type:
  resume_entry` posts, ordered by `metadata.start_date` descending,
  visually distinguishing IC vs. lead roles (`metadata.role_type`).
- `/:locale/blog` and `/:locale/blog/:slug` — list + show.
- `/:locale/now` — the latest `now_update` post, with older ones
  listed below as an archive.

## 7. SEO

- Per-page `<title>`, meta description (from `excerpt` or
  `SiteSetting`), canonical URL.
- Open Graph + Twitter Card tags driven by each post's title/excerpt.
- `hreflang` alternate-language `<link>` tags on every translatable
  page, pointing at the equivalent URL in each supported locale.
- `sitemap.xml` generated via `sitemap_generator`, covering all
  published posts across all locales.
- JSON-LD structured data: `Article` schema on blog post pages,
  `Person`/`ProfilePage` schema on the resume page.

## 8. Rich content & embeds

- **PDFs**: handled by ActionText's built-in file-attachment support
  (Active Storage) — attaching a PDF in the rich text editor already
  works with no custom code.
- **YouTube**: a custom `ActionText::Attachable` (a standard Rails
  extension point, not a bespoke hack) that lets an editor paste a
  YouTube URL and have it render as an embedded, responsive iframe
  both in Avo's editor preview and on the public page.

## 9. Mind graph

- Data: `Post` nodes + `PostRelation` edges (see [§4](#4-data-model)).
- v1 is **admin-only**, inside Avo, to help the owner see how their
  own content interlinks while authoring.
- A public-facing version (visitors exploring the site as a graph) is
  a likely future phase, deferred until the admin version proves
  useful — the underlying edge data doesn't need to change to support
  it later.
- Edges are created explicitly (a multi-select "related posts" field
  in Avo), not by parsing links out of body text.

## 10. MCP server

- Mounted inside the same Rails app (e.g. at `/mcp`), not a separate
  process — runs wherever the app is deployed, whenever that's
  decided.
- Authenticated via a bearer token checked against `ApiToken`.
- Exposes tools to list, get, create, and update `Post` records across
  all three content types, including locale as a parameter (an agent
  can create/update a specific locale's translation of a post).
- Does not expose `SiteSetting`, `ApiToken`, or `User` management —
  scoped to content operations only in v1.

## 11. Setup wizard

- `/setup` is reachable only while `User.none?` — the app redirects
  here automatically on first boot, and the route becomes
  inaccessible (404 or redirect to home) once an admin account
  exists.
- **Step 1 (required)**: create the first admin account (email +
  password), backed by the Rails 8 auth generator's `User` model.
- **Step 2 (required)**: site identity/branding — populates
  `SiteSetting` (title, tagline, social links, logo, default locale).
  This is what feeds the SEO defaults in [§7](#7-seo).
- **Step 3 (optional, skippable)**: generate the MCP bearer token
  (creates the `ApiToken` row) and display the raw value once. Can
  also be done later from Avo.
- **Step 4 (optional, skippable)**: seed one sample `Post` per
  content type (blog/resume/now) so the site isn't empty on first
  load.
- The supported locale *list* itself (which locales exist, e.g. `en`,
  `es`) is a code-level config (`available_locales`), not something
  the wizard edits — the wizard only sets which of those is default.

## 12. Internationalization

- `title`, `slug`, `excerpt`, and `body` on `Post` are translatable
  via the `mobility` gem, using its jsonb backend (a natural fit given
  the Postgres choice in [§3](#3-tech-stack)).
- Initial supported locales: **English (default) + Spanish**. Adding
  a third locale later is a content-entry task (translate existing
  posts) plus a one-line config change (`available_locales`), not a
  code change to the translation infrastructure itself.
- `slug` uniqueness is scoped per `(locale, content_type)` — the same
  slug string can exist in different locales or across different
  content types without conflict.
- Missing translations fall back to the default locale (Mobility's
  fallback feature) rather than rendering blank.

## 13. Testing strategy

Rails default minitest + fixtures:

- Model tests: `Post` validations (slug uniqueness scoping,
  `content_type` enum), `PostRelation` (no duplicate reverse edges),
  `SiteSetting` (singleton enforcement), `ApiToken` (hashing,
  regeneration).
- Request tests: each public route (`/resume`, `/blog`,
  `/blog/:slug`, `/now`) for both supported locales, and for the
  default-locale-fallback behavior when a translation is missing.
- Request tests for the MCP endpoint: rejects unauthenticated/invalid
  tokens, accepts valid tool calls, rejects malformed tool input.
- Request tests for the setup wizard: `/setup` reachable only when no
  `User` exists; each step's required validations; skipping the
  optional steps leaves the app in a usable state.

## 14. Out of scope / deferred

Explicitly not designed in this spec — real future considerations,
but not needed to ship v1:

- Multi-tenant SaaS (multiple independent owners/sites in one
  deployment).
- A generic self-hostable template/starter for other people to clone
  and reskin.
- Deploy target and configuration (Kamal/Hetzner or otherwise).
- Full project-portfolio case-study pages (separate from the resume
  timeline).
- Roles/permissions beyond a single admin account.
- `[[wiki-link]]` parsing as a way of creating `PostRelation` edges.
- A public-facing (visitor-viewable) mind-graph view.
