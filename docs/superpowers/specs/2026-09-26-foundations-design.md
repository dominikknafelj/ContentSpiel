# Foundations: languages, public URLs, resolver, services

Sub-project 1 of 7 on the way to ContentSpiel's own admin (see `docs/roadmap.md`, Phase 1). Status: design approved in brainstorming on 2026-09-26; this document is the binding spec for the implementation plan.

## 1. Purpose

The own admin, roles, the audit log, versioning, SEO, feeds, caching and runtime languages all need the same few seams. This sub-project builds them, so later sub-projects only plug into them:

- a runtime language model (enabled languages are a site setting, not code);
- one table holding every public URL per language, with redirects for old URLs;
- one URL builder and one resolver for the public site;
- a cookie-less, cacheable public site with preview on its own URL;
- service objects as the single write path for admin, MCP, setup and seeds.

**Success:** the public site and MCP behave as today, except for the intended changes listed in §9. Every new unit has tests. Avo keeps working until the admin MVP (sub-project 3) replaces it.

**Context:** greenfield, no production. Schema changes drop old columns and indexes outright and rebuild derived data. There is no backfill or compatibility code.

## 2. Decisions (from brainstorming)

| Decision | Chosen | Rejected |
|---|---|---|
| Translation storage | Field-level translation stays (Mobility jsonb), plus a per-language URL table: the Drupal/Craft pattern | Keeping jsonb slugs with per-language indexes (every new language needs DDL). Row-per-language like TYPO3/WPML (duplicates the tree and makes every query language-aware). |
| Runtime languages | Model and site setting now; the management screen comes with the admin | Only splitting supported/enabled (touches routing twice). Building the screen now (there is no admin shell yet). |
| Preview | A separate `/preview` URL behind sign-in; the public site is session-free and cacheable | Same URL with cookie-dependent caching (a CDN would have to vary on the cookie). |
| URL upkeep | Derived in the model layer, like `cached_paths` today, so every write path stays correct (including Avo) | Written only by the services (Avo and fixtures would leave the table stale). Computed on read. |
| Avo | Keeps working until the admin MVP; no new Avo features | Dropping it now (no editing UI until sub-project 3). |
| Per-language content | Not now. Later option: an optional `locale` column on content blocks (null = all languages) | — |

## 3. Code organisation

- **Concerns** hold record-level behaviour: validations, scopes, derived data.
  - Shared concerns go in `app/models/concerns/`:
    - `Publishable` (exists);
    - `LocalizedSlug` (renamed from `SlugGeneration`; it also absorbs the duplicated per-language slug uniqueness validation from `Page` and `Post`);
    - `HasPublicPaths` (path-sync hooks for `Page` and `Post`).
  - Model-specific concerns are namespaced under the model, e.g. `app/models/page/tree_ranking.rb` → `Page::TreeRanking` for the "move to rank N" logic. They are included **after** `has_closure_tree`, keeping the callback-order rules in §6 of the structure review.
- **Services** in `app/services/`, namespaced by resource in the plural (`Pages::Save`, never `Page::Save`). They hold user actions that span models and are shared by admin, MCP, setup and seeds.
  - One public entry point: `.call(...)`, returning a `Result`.
  - Justification over plain fat models: several channels perform the same actions, and roles, audit and versioning need exactly one place to attach.
- **Public-site reading**: plain Ruby objects in `app/models/public_site/`:
  - `PublicSite::Urls`
  - `PublicSite::Resolver`
  - `PublicSite::Paths`
  - the AR model `PublicPath`
- **`Locales`** is top-level (`app/models/locales.rb`), because public, admin and MCP all use it.
- **Controllers**: `PublicController` (base) → `PagesController`, and a new `PreviewController`. The admin later lives under `Admin::`.
- **Optional last step** (can be cut): move MCP tools from `app/tools/` to `app/mcp/tools/`, e.g. `Mcp::Tools::UpdatePost` and `Mcp::PostSerializer`.

## 4. Languages

### 4.1 Supported vs enabled

- **`Locales::SUPPORTED`**: a built-in list of about 40 ISO 639-1 codes, each with an English and a native name.
  - `config.i18n.available_locales` is set from it, so I18n and Mobility accept any of them.
  - `SetupHelper::LANGUAGE_NAMES` is replaced by `Locales.name(code)`.
- **Enabled languages**: new column `site_settings.locales`, jsonb, not null.
  - It holds an ordered array, e.g. `[{ "code": "de" }, { "code": "en", "fallbacks": ["de"] }]`.
  - The existing `default_locale` column stays and must be one of the enabled codes.
  - Validations:
    - codes are supported and unique;
    - fallbacks name enabled codes;
    - at least one language is enabled;
    - the default language is enabled.
- **URL prefixes** follow today's rule: the default language has no prefix; every other language uses `/<code>`. There are no custom prefixes.

### 4.2 `Locales` API

- `Locales.enabled`: codes, ordered.
- `Locales.default`
- `Locales.enabled?(code)`
- `Locales.name(code, native: false)`
- `Locales.fallback_chain(code)`: the code, then its configured fallbacks, then the default language, then the remaining enabled languages in order, with no duplicates.

All of these read `Current.site` (§6.1).

### 4.3 Reading translations

- **Remove the fixed fallback.** `config.i18n.fallbacks = [:en]` and Mobility's static `fallbacks` default go.
- **One public reader.** Public reads go through a single fallback reader backed by `Locales.fallback_chain`. It replaces `ThemeHelper#translated`, whose call sites stay. It covers:
  - `title`, `subtitle`, `excerpt`, `meta_title`, `meta_description`, `caption`, `alt` and `hero_alt`;
  - ActionText `body`. This fixes the known "blank bodies in other languages" follow-up.
- **Admin and MCP read literally.** They use `record.title(locale:)` with no fallback, so an empty translation shows as empty. New code does not rely on the generated `title_de`-style accessors. They exist for all supported languages but are an Avo-era convenience.
- **Slugs.** `LocalizedSlug` fills blank slugs using the same chain: the language's own title first, then the fallback chain. This matches the rule shipped in 8c.

### 4.4 Routing and enabling

- The locale route constraint checks `Locales.enabled?` per request instead of a fixed regex. A disabled language's URLs return 404; its content stays stored.
- The setup wizard's language step writes `site_settings.locales` (the chosen default plus any extra languages).
- `Locales::Enable.call(code, fallbacks: [])` and `Locales::Disable.call(code)` update the setting and sync `public_paths` for every page and post (§5.4).
  - Disabling the default language is an error Result.
  - The management screen comes with the admin.

## 5. Public URLs

### 5.1 `public_paths` table

| Column | Type | Meaning |
|---|---|---|
| `record_type`, `record_id` | string, bigint | `Page` or `Post` |
| `locale` | string | language code |
| `path` | string | full path **without** the language prefix; the root page is `/`, e.g. `/about/team`, `/blog/hello-world` |
| `current` | boolean | `true` = the live URL; `false` = an old URL kept as a redirect |
| timestamps | | |

Indexes:
- unique on `(locale, path)` over all rows;
- unique on `(record_type, record_id, locale)` where `current`;
- `(record_type, record_id)`.

No index or column exists per language.

### 5.2 Slugs

- `pages.slug` and `posts.slug` stay per-language jsonb segments that editors see and edit.
- Dropped:
  - `pages.cached_paths` and its three expression indexes;
  - the per-language unique slug indexes on `pages` and `posts`.
- Uniqueness becomes a `LocalizedSlug` validation against `public_paths`:
  - the resulting path must not be current for another record in that language;
  - errors are keyed per language (`slug_de`) and name the language, e.g. "is already taken in DE";
  - the database index is only a safety net.
- The root page has no slug; its path is `/`.
- Posts additionally keep a slug-uniqueness validation per content type and language (a query on the jsonb, no index). A post without a listing page has no path to clash on, yet adding a listing page later must never make an existing post invalid. `LocalizedSlug` takes the scope: `localized_slug scope: :parent_id` for pages, `scope: :content_type` for posts.
- `SiteSetting`'s `default_locale` validation checks enabled codes instead of `I18n.available_locales`.

### 5.3 Canonical post URLs

- A post has at most one current URL per language: its **canonical listing page's** path, then `/`, then its slug.
- **Canonical listing page:** the first page in tree order (depth-first, sibling `position`) that has a `post_list` block matching the post. Matching means the same content type and, if the block sets a tag, a post carrying that tag. Publication state is ignored here; the resolver applies it (§6.3).
- **No listing page:** the post has no public URL, same as today.
- **Other listing pages:** the old behaviour, where a post also resolves under any other page that lists it, becomes a 301 to the canonical URL. Other listing pages are not stored as rows. The resolver computes this fallback (§6.3).

### 5.4 Upkeep (`PublicSite::Paths`, via `HasPublicPaths`)

- `PublicSite::Paths.sync(record)` recomputes a record's current rows in every enabled language.
- Triggers, all in the model layer, after save, inside the transaction:
  - **Page save:** sync the page and its descendants, replacing `recompute_cached_paths`. It keeps the rules the structure review marks "don't touch": the `where(parent_id:)` query, `update_columns`, and callback order. It also syncs posts whose canonical page lies in that subtree.
  - **Post save:** sync the post.
  - **Changes to a `post_list` block, or to page order or placement:** sync every post of that block's content type. Adding, editing or removing a block counts, and so do page moves and reorders.
  - **`Locales::Enable`/`Disable`:** a full sync.
- **When a path changes:**
  - The previous current row becomes `current: false` (a redirect).
  - If the new path is held by a non-current row, that row is deleted and the path reused.
  - A path held by another record's current row is a validation error (§5.2).
- **Deleting a page or post** deletes its rows. Trash will change this later.
- **`PublicSite::Paths.rebuild!`** truncates the table and syncs everything. It is exposed as `bin/rails public_paths:rebuild` and runs from seeds.
- **After commit**, the model emits `ActiveSupport::Notifications.instrument("public_paths.changed", record:, locale:, from:, to:)` for each changed path. This is the hook for CDN purge, webhooks and link checks. Nothing subscribes yet except tests.

## 6. Reading the public site

### 6.1 `Current.site`

- `Current.site` is `SiteSetting.instance`, loaded once per request. Outside requests (console, jobs, MCP), the lookup memoizes itself on first use.
- Every `SiteSetting.instance` call in `app/` and `config/` changes to `Current.site`. That's about 12 sites; see `grep -rn "SiteSetting.instance" app config lib db/seeds.rb`.
- `Setup.required?` uses a per-process "setup is done" flag. It is set once setup is complete, reset by the setup finish step, and reset in the test helper.

### 6.2 `PublicSite::Urls`

- `prefix(locale)` returns `""` or `"/de"`.
- `path_for(record, locale = I18n.locale)` returns the current `public_paths` path with the prefix, or `nil`.
- `url_for(record, locale = I18n.locale)` is the absolute version, using the request host or `config.action_mailer.default_url_options`. It is used by the sitemap, hreflang and the MCP `url` field.
- `alternates(record)` returns `{ locale => url }` for every enabled language where the record has a current path.

`PagesHelper#page_url_path/#post_url_path/#locale_prefix`, the prefix code in `config/sitemap.rb`, and the default-language prefix rule in `PagesController` all delegate here. A test fails if code outside `PublicSite::Urls` builds a public path by hand (grep-based guard, same style as existing guard tests).

### 6.3 `PublicSite::Resolver`

- `PublicSite::Resolver.new(scope: :published | :preview).call(locale:, path:)` returns a `PublicSite::Resolver::Result`, a type separate from the services' `Result`. It is one of:
  - `found(record)`
  - `redirect(location, status)`
  - `not_found`
- **Lookup:** one indexed lookup on `public_paths (locale, path)`.
  - **Current row:** found, subject to scope.
  - **Non-current row:** a 301 to the same record's current path in that language (via `Urls`).
  - **Miss:** try "listing page path + post slug", where the listing page lists the post. If that post has a canonical URL, 301 to it (§5.3). Otherwise 404.
- **`:published` scope:** the record and every ancestor page must be published. For a post, that means its canonical listing page and that page's ancestors. This is checked with one closure-table query, and it fixes the "published child of a draft parent" follow-up. `:preview` ignores publication state.
- The resolver never raises for a missing record.

### 6.4 Controllers

- **`PublicController`** is the base for `PagesController`. It has:
  - no `Authentication`, no session access, no CSRF meta tag, no cookies;
  - `fresh_when` with an ETag from the record's `updated_at`, the site settings' `updated_at`, and the newest `public_paths.updated_at`;
  - `Cache-Control: public, max-age=0, must-revalidate`.
  The theme toggle keeps working (localStorage).
- **`PagesController#show`** uses `Resolver(scope: :published)`:
  - found → render;
  - redirect → redirect;
  - not found → the theme 404.
- **`PreviewController`** handles `/preview(/:locale)(/*path)`:
  - it requires sign-in (existing `Authentication`) and uses `Resolver(scope: :preview)`;
  - it renders the same theme views with the preview banner: status, "Edit" (Avo edit URL for now) and "View live" (when published);
  - it sends `Cache-Control: private, no-store` and `X-Robots-Tag: noindex`;
  - links rendered inside a preview stay under `/preview`, through `Urls` taking a `preview: true` option.
- **Routes:** `/preview` is declared before both catch-alls. The existing routing rules (`format: false`, two separate catch-alls, 302 for the default-language prefix) are unchanged. The "Edit this page" link and preview banner on live pages are removed.

### 6.5 Sitemap and alternates

`config/sitemap.rb` lists every published page and every published post with a canonical URL, in every enabled language, via `Urls.url_for`. Pages get `<link rel="alternate" hreflang>` tags from `Urls.alternates`, plus `x-default` pointing at the default language.

## 7. Services

### 7.1 Shape

- `app/services/application_service.rb` defines `Result = Data.define(:record, :errors) { def ok? = errors.empty? }` and `ApplicationService.call(...) = new(...).call`.
- Every service:
  - runs in one transaction;
  - returns an error `Result` for validation and rule failures;
  - lets unexpected exceptions propagate.
- Each service calls `authorize!` and `record_event(name, **data)` at the right points. Both are no-ops in this sub-project, documented as the attachment points for policies and the audit log (sub-project 5).
- `Current.actor` (new) holds the user or API token and `Current.channel` (`:admin | :mcp | :setup | :console | :system`). Who sets them:
  - controllers set them from the session;
  - the MCP endpoint sets them from the token;
  - setup sets `:setup`;
  - defaults are `:console`/`:system`.

### 7.2 Services

| Service | Behaviour |
|---|---|
| `Posts::Save.call(post = Post.new, attributes:, translations: {}, actor:)` | `translations: { locale => { title, slug, excerpt, body } }`, several languages at once. `attributes`: `content_type`, typed fields (resume), `tag_names` (find-or-create, case-insensitive, stripped), `published: true\|false\|nil` (true: a live post keeps its date, a draft or scheduled post goes live now; false: unpublish; nil: unchanged), `published_at:` (schedule; wins over `published`). |
| `Pages::Save.call(page = Page.new, attributes:, translations: {}, actor:)` | parent (on create), page type, hero image, publish state (same rules as posts). Translations as above for title, slug, subtitle, meta fields, hero alt. |
| `Pages::Move.call(page, parent:, position:, actor:)` | Uses `Page::TreeRanking`. Errors for moving the root, moving a page under itself or a descendant, and position out of range (clamped, not an error). |
| `Pages::Destroy.call(page, actor:)` | Error Result for the root and for pages with children. |
| `ContentBlocks::Save.call(block, attributes:, translations: {}, actor:)` | `block_type`, `settings`, image, position (append if nil). |
| `ContentBlocks::Reorder.call(page, ordered_ids, actor:)` | The ids must be exactly the page's blocks; otherwise an error Result. |
| `Locales::Enable` / `Locales::Disable` | See §4.4. |
| `ApiTokens::Issue.call(user, rotate: false, actor:)` → Result whose record is `[token, raw]` | Replaces `SetupController#update_mcp_token`, `Avo::Actions::RegenerateApiToken` and ad-hoc creation. `ApiTokens::Revoke.call(token, actor:)`. |

### 7.3 Callers switched in this sub-project

- **MCP tools** (create/update/get/list post): thin wrappers around `Posts::Save` and the readers. The response shape stays; `url` comes from `Urls.url_for`.
- **Setup wizard:** the site, languages, MCP token and starter content steps.
- **Other callers:** `StarterContent`, `db/seeds.rb` and `Avo::Actions::RegenerateApiToken`.
- **Not switched:** Avo's resource forms keep saving through ActiveRecord. The model-layer hooks keep `public_paths` correct.

## 8. Avo during the transition

- Avo keeps working and gets no new features.
- Changes Avo needs:
  - its pages tree and anything reading `cached_paths` use `PublicSite::Urls`;
  - Avo's per-language tabs and `slug_<locale>` fields are built from `Locales.enabled`, not `I18n.available_locales`, so Avo shows only enabled languages rather than all ~40 supported ones;
  - the site settings form keeps `default_locale`.
- Avo's own tests stay green, adjusted only for the intended changes in §9.

## 9. Intended behaviour changes

1. Posts have one canonical URL per language. Other listing pages 301 to it.
2. Old URLs (renamed slugs, moved pages) 301 to the current URL.
3. A published page or post under an unpublished ancestor is no longer public.
4. Preview moves to `/preview/...`. Live pages carry no preview banner or edit link and set no cookies.
5. Public pages send `Cache-Control: public` and ETags, and answer conditional GETs with 304.
6. Languages are a site setting. Adding a supported language requires no migration.
7. Translated text, including rich-text bodies, falls back along the site's fallback chain instead of to English.
8. The sitemap lists posts and carries hreflang alternates.

## 10. Error handling

- **Services:** validation and rule failures come back as error `Result`s.
  - MCP tools map them to MCP error responses.
  - The setup wizard re-renders the step with errors.
- **Resolver:** `not_found` becomes a 404 rendered in the theme.
- **Path clashes:** caught by `LocalizedSlug` before save. If the unique index fires anyway, the transaction rolls back and the error propagates (it's a bug, not user input).
- **Language settings:**
  - `Locales::Disable` of the default language → error Result.
  - Unknown codes → validation errors on `site_settings.locales`.

## 11. Testing

- **Helpers** (`test/support/content_helper.rb`):
  - `create_page(title:, parent: root, locales: ..., published: true)`
  - `create_post(...)`
  - `with_locales(%w[de en], default: "de") { ... }`
  They build through the services. Existing tests move to them where they are touched anyway. A mass rewrite is not a goal.
- **Unit tests:**
  - `Locales`: fallback chains, validation;
  - `PublicSite::Paths`: sync, cascade, redirect rows, reclaiming a path, canonical post page, `rebuild!`, notifications;
  - `PublicSite::Urls`;
  - `PublicSite::Resolver`: published vs preview, draft ancestor, redirects, listing fallback;
  - every service: success and each error case.
- **Integration tests:**
  - public responses carry no `Set-Cookie` and send `Cache-Control: public` plus an ETag; a conditional GET returns 304;
  - 301s from old paths and non-canonical post URLs;
  - preview requires sign-in and sends `no-store`/`noindex`;
  - enabling and disabling a language;
  - a site whose default language is `de`;
  - sitemap posts and hreflang.
- **Regression:** existing routing, sitemap, MCP, setup and Avo tests pass, changed only where §9 changes behaviour. The setup wizard system test keeps its scripted clicks.

## 12. Out of scope

- Policies, roles, groups and audit tables (sub-project 5; only the attachment points exist).
- Admin screens, including the language management screen.
- Manual redirects.
- Open-types registries (sub-project 2).
- Trash, the media library and Tiptap.
- Per-language content blocks.
- Removing Avo.
