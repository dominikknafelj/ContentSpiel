# ContentSpiel code structure review (snapshot `main` @ a46f923)

Scope: `/tmp/cs-structure-review`, read-only. Avo code (≈1,615 LOC app + ≈1,130 LOC tests) is out of scope except where non-Avo code exists only to serve it.

## 1. Summary

The domain core is healthy. `Page`'s path cache, the routing invariants and the setup wizard are correct, thoroughly tested and well commented. What makes the code hard to change is that it has **no service layer at all**. Writes happen in five different places: Avo resources, Avo tools, MCP tools, `StarterContent` and `db/seeds.rb`, and each one re-implements "create or update a post or page in a locale". The own admin would become a sixth copy.

The biggest structural issues:
1. The public-URL rule ("default locale gets no prefix") is written three times: `PagesHelper`, `config/sitemap.rb` and `PagesController`. The locale list is hard-coded in four places, and `I18n.available_locales` serves as the content, Mobility, admin-UI and route locale list all at once.
2. `published` is baked into `Page.find_by_full_path` and `ContentBlock#listed_posts`. This works against the in-flight signed-in preview.
3. Two real bugs are hidden by the structure:
   - Mobility falls back to a fixed `:en` while the site's default locale is set at runtime. A site set up in German gets child pages whose en/es path collapses to `/`.
   - `UpdatePostTool` re-stamps `published_at`.
4. Some invariants live only in Avo controllers: the last user can't be deleted, and API tokens can't be created by hand.
5. Layouts and JavaScript are shared by the public site and the product UI (`:app` stylesheet, Trix on the public site, public pages behind the session and CSRF stack). This blocks the second Tailwind build and CDN caching.

For the roadmap, the expensive structures are:
- closed integer enums (`block_type`, `content_type`)
- hard deletes
- attachments hard-wired per model (no media library, and alt text would land per usage)
- blocks that can only belong to a `Page`
- path changes that overwrite silently, with no "from → to" record for redirects or CDN purge
- boot-time-only locales

## 2. Findings

When: **N** = now-refactor, **A** = with own admin, **X** = goes away with Avo.

Roadmap keys:
- RL roles/permissions
- AU audit log
- VE versioning
- PL plugin API
- CT custom content types & fields
- NAV navigation management
- FEED RSS/Atom
- TR trash/restore
- SR search
- RC reusable content (snippets, templates, presets)
- SEC security basics
- GDPR legal/GDPR
- FRM forms
- WF publishing workflow
- API headless API + webhooks
- CDN caching/purge + responsive images
- MED media library + alt text
- IMP import/export/backups
- QC quality checks
- AI18N admin UI i18n
- SEO redirects/hreflang/OG/noindex/sitemap
- LANG runtime languages
- INV invites

In the Roadmap impact column, "+" means the refactor enables the item and "✗" means the current structure blocks or overcharges it.

| # | Area | file:line | What's wrong / duplicated | Proposed simplification | Benefit | Effort | When | Risk | Roadmap impact |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Models | page.rb:277-301, post.rb:91-115 | The per-locale slug uniqueness validation is duplicated word for word. Only the scope differs (`parent_id` vs `content_type`). | Fold it into the in-flight `SlugGeneration` concern (rename it `LocalizedSlug`): `localized_slug scope: :parent_id`. It then covers generation, per-locale presence and uniqueness. | One implementation of a subtle invariant. | S | N | Low. Keep errors keyed `slug_de`. | + LANG (one place to adapt), + CT, + TR (scope must exclude trashed) |
| 2 | Models / i18n (**bug**) | application.rb:30; page.rb:66, 188-190, 243-245; post.rb:35, 60-65; starter_content.rb:43 | Slug presence is checked only in the ambient locale, and fallbacks go to a fixed `:en`. A site set up in `de` gets child pages whose en/es `cached_paths` are `"/"`, which collides with Home. The sitemap then lists `/en/` twice. `find_by_localized_slug` falls back to the static `I18n.default_locale`. | Generate and require slugs in **every** enabled locale (in-flight concern). Resolve fallbacks via `Locales.fallback_chain(locale)` against the site default. Add a regression test that runs setup in `de`, then `GET /en/blog`. | Removes a real two-pages-one-URL path. | M | N | Med | + LANG, + SEO (hreflang needs valid per-locale URLs); ✗ LANG as is |
| 3 | Models | page.rb (310 lines) | One class holds three jobs: tree integrity, the path cache (116-252) and sibling ranking (98-114, 194-214). | Split into `page/cached_paths.rb` and `page/sibling_ranking.rb`. Include both after `has_closure_tree`. | About 100-line Page, and invariants readable in isolation. | M | N | Med (callback order, §6) | + SEO/CDN (path-change events live in one concern, #45), + VE |
| 4 | Comments (stale) | page.rb:8-10 vs 98-106; CLAUDE.md:40, 58 | Contradictory drag-and-drop claims (Avo pages_tree *does* drag). CLAUDE.md claims a `Page#body` rich text that doesn't exist. | Rewrite: rank semantics apply to any move. Fix CLAUDE.md. | No false premises for agents. | S | N | None | — |
| 5 | Models (Avo-only) | page.rb:26-36 | `accepts_nested_attributes_for` + the `reject_if` blank row exist only for Avo's `NestedContentBlocks`. | Delete with Avo. Blocks become their own resources (per-block Turbo frames). | Smaller params surface. | S | X | Low | + RC, + VE (block ops go through services) |
| 6 | Models | content_block.rb:38-50, 62-67; avo/resource_tools/nested_content_blocks.rb; _post_list.html.erb:10 | `settings` is stringly typed jsonb, with its keys listed in three places. `discard_blank_settings` exists for Avo's all-keys row form. `limit` stays a string. | A typed settings object per block type (ActiveModel::Attributes), registered in `BlockTypes` (§8). Per-type admin partials. | Typed forms, one key list. | M | A | Low | + PL, + FRM (form block settings), + RC (presets = saved settings), + CT |
| 7 | Views / query | _post_list.html.erb:9-10; pages_controller.rb:80-84 | Listing order and limit are applied in the partial. | `ContentBlock#listing` (ordered, limited). `listed_posts` stays unlimited. | The view stops querying. | S | N | Low | + FEED (feed = listing), + API, + WF (scope) |
| 8 | URLs / posts | pages_helper.rb:39-43; post.rb:58, 106; sitemap.rb:30; seeds.rb:117 | A post's URL depends on the listing that rendered it, with no canonical. Posts are missing from the sitemap. `where(...).first` without `order` is nondeterministic across content types. The admin and MCP can't compute a post URL. | `PublicUrls#post_path` resolves a canonical listing page. Add `.order(:id)` and posts in the sitemap. | Deterministic URLs | M | N | Med | + SEO, + FEED, + API/webhooks (payload URL), + CDN (purge targets), + QC (link check) |
| 9 | Dead code | post.rb:68-72, 16-17 | `all_related_posts` is test-only. `related_posts` is one-directional and exists for Avo. | Rename to `related_posts` after Avo. | Undirected in one place | S | N | Low | + API |
| 10 | Models | starter_content.rb:51-54 | `added?(locale:)` has an unused keyword. | Drop it. | Noise | S | N | None | — |
| 11 | Seeds / tests | seeds.rb:14-34, 132-160; seeds_test.rb:14-17 | Seeds re-implement `StarterContent` and define methods on `Object`. The test monkeypatches `Rails.env`. | Seeds call `StarterContent` + `DemoContent.seed!`, and the test calls those directly. | About 60 fewer lines, non-brittle | S | N | Low | + IMP (demo content as importable data), + RC (templates) |
| 12 | Perf / state | pages_controller.rb:90, 107; pages_helper.rb:53; setup.rb:7; routes.rb:6 | `SiteSetting.instance` runs a query per call, including one per rendered link. `Setup.required?` queries on every request. | `Current.site` memo, plus a process-level latch for setup-done (reset in the test helper). | Removes N+1 queries on the public site. | S | N | Low | + CDN, + LANG (enabled locales read per request), + GDPR (consent settings) |
| 13 | Controller → model | setup_controller.rb:148-158 | Social-link row normalization sits in the controller. | `SiteSetting#social_link_rows=`. | Reuse in the admin | S | A | Low | + SEO/theme (links in footer), + IMP |
| 14 | Invariants in Avo | avo/users_controller.rb; avo/api_tokens_controller.rb | "No user deletion" and "no hand-made tokens" are enforced only in Avo. | `User#ensure_not_last_owner`, `ApiToken.issue!` only. Port the tests before deleting Avo. | Invariants survive | S | A (before Avo deletion) | Low | + RL, + INV, + GDPR (user delete must respect it) |
| 15 | Duplication | setup_controller.rb:174-178; avo/actions/regenerate_api_token.rb:15-16 | Two token-minting paths with different semantics. | `ApiToken.issue!(user, rotate:)`. | One semantics, one audit point | S | A | Low | + SEC, + AU, + API (read-API tokens) |
| 16 | Duplication | rack_attack.rb; mcp_controller.rb:44 | The bearer regex is duplicated. | `ApiToken.raw_from_authorization`. | Minor | S | N | None | + API (headless API reuses it) |
| 17 | Locales hard-coded | routes.rb:91; application.rb:23; setup_helper.rb:4 | The locale list is repeated, and `LANGUAGE_NAMES` is trapped in `SetupHelper`. | A `Locales` module (`supported`, `enabled`, `name`, `fallback_chain`). The route constraint is built from it. | Single source | S | N | Low | + LANG, + AI18N, + SEO hreflang |
| 18 | Controller | pages_controller.rb:92 vs 113-116 | Path normalization is duplicated. | Reuse `requested_path`. | Minor | S | N | None | — |
| 19 | Structure vs preview | page.rb:144-146; content_block.rb:63; pages_controller.rb:47-87 | `published` is hard-wired into both lookups. | `PublicSite::Resolver.new(scope:)` → `Result(page, post, listing_block)`. The scopes become arguments. | Preview = one argument | M | N | Med | + WF (preview/review, scheduled unpublish), + TR (exclude trashed), + API (same resolution), + SEO (redirect fallback on miss, noindex) |
| 20 | Controller | application_controller.rb:4 | `allow_browser :modern` returns 406 to older browsers on the **public site**. | Move it to the product/admin base. | Public reachability | S | N | Low | + CDN |
| 21 | Avo coupling | authentication.rb:43-45; setup_controller.rb:187 | Redirects go to the Avo root. | `admin_root_path`. | Needed for removal | S | A | None | — |
| 22 | Controller (optional) | setup_controller.rb:9-16; layouts/setup.html.erb:21 | The layout reaches into `SetupController::STEPS`. | `Setup::Steps` PORO. | Small | S | N (low) | Low | + AI18N (labels → i18n keys) |
| 23 | MCP | tools/*.rb | Locale default, `with_locale` + serializer, responses and not-found handling are repeated four times. | `ApplicationTool` base; the serializer wraps the locale itself. | About 10-line tools | S | N | Low | + PL (MCP tool registry), + RL (authorize in the base), + API (shared serializers) |
| 24 | MCP (**bug**) | update_post_tool.rb:29-30 | Re-publishing re-stamps `published_at`, and the two `update!` calls aren't atomic. | `published_at \|\|= now` inside `Posts::Save`. | Correctness | S | N | Low | + WF |
| 25 | Seams | create/update_post_tool.rb; starter_content.rb:70-74; seeds | Post writes are implemented separately in every caller. | `Posts::Save` (§4). | Single write path | M | A (first) | Low | + RL, AU, VE, WF, SR (index update), API webhooks, CDN purge, QC, PL hooks: **the key seam** |
| 26 | Avo logic to salvage | avo/tools_controller.rb:16, 26-34, 46-61 | Domain logic sits in Avo controllers. | `Pages::Move`, `PageTree`, `PostGraph`. | Reuse | S | A | Low | + AU (move events), + NAV (tree query reused as default nav) |
| 27 | URL building ×3 | pages_helper.rb:29-54; sitemap.rb:42-45; pages_controller.rb:89-95 | The prefix rule is written three times. | A `PublicUrls` PORO (§4), with absolute URLs (#51). | One rule | S | N | Low | + SEO (hreflang, redirects), FEED, API, CDN, NAV (menu items → URLs), QC, LANG |
| 28 | Product UI kit | setup_helper.rb:6-20; setup/_errors, _flash, _system_check_results | Product-UI primitives are scoped to setup. | `ProductUiHelper` + `app/views/product/`. | No second copy | S | A | None | + AI18N, + PL (plugin screens reuse the kit) |
| 29 | Layouts / CSS | application.html.erb:23, 28; setup.html.erb:9; sessions/new.html.erb | `stylesheet_link_tag :app` loads every build into both layouts. Sign-in and passwords use the public layout, styled with generator grays. | Explicit stylesheets per layout, and a `product` layout. | Keeps the `--cs`/`--th` boundary | S | N | Low | + PL themes, + CDN; ✗ second Tailwind build as is |
| 30 | Views | pages/show.html.erb:33-36 | `children.published` runs twice. | Load once. | Minor | S | N | None | + NAV (moves into `Navigation`, #52) |
| 31 | Leftovers | views/pwa/*; routes.rb:54-56; application.html.erb:15-16 | Generator leftovers. | Delete. | Noise | S | N | None | — |
| 32 | JS payload | application.js:5-6 | Trix and ActionText load on public pages. | An `admin.js` entrypoint. | Lighter public JS | S | A | Low | + CDN, + FRM (public JS stays minimal) |
| 33 | Dead code | controllers/hello_controller.js | Generator leftover. | Delete. | Noise | S | N | None | — |
| 34 | Editor JS | youtube_embed_paste.js:7-8, 24; youtube_embed.rb:22-25 | The `/avo/...` URL is hard-coded, and the regex is duplicated in Ruby and JS. | A Stimulus controller with a URL value; the server is authoritative. | Survives Avo | S | A | Low | + MED (paste/drop into library) |
| 35 | Config | mobility.rb:23-24 | The `backend_reader` plugin is unused. | Remove. | Noise | S | N | None | — |
| 36 | Avo comments | mobility.rb:42-46; youtube_embed.rb:46-51; youtube_embeds/*; starter_content.rb:1; system_check.rb:1; redirect_constraint.rb:2-3; mcp_controller.rb:8-11; authentication.rb:37-42; action_text.rb:9; CLAUDE.md | These comments justify still-needed code by reference to Avo. | Reword them on Avo removal. | Accurate docs | S | X | None | — |
| 37 | Security | initializers/action_text.rb:1-24; content_security_policy.rb | The comment says iframe `src` is never taken from input, but `iframe`/`src` are allowed in every body (MCP raw HTML, JS paste fallback). There is no CSP. | A scrubber that allows only youtube-nocookie `src`, plus a CSP `frame-src`. | Real defense | M | N | Med | + SEC, + RL (less-trusted authors), + FRM, + GDPR (consent hook needs CSP-aware embeds) |
| 38 | Models (low) | page.rb:119-121, 221-223 | `compute_full_path` fallback for pre-column rows (no prod, NOT NULL default). | Drop the fallback. | One source of truth | S | N | Low | + LANG (a missing locale key must be a visible bug) |
| 39 | Tests | pages_routing_test.rb (73×), page_test.rb (86×), sitemap_test.rb | About 180 repeated `Page.create!(...)` calls, and a 680-line routing test. | A `page_tree_helper.rb` + split files. | About 30% fewer lines | S | N | None | Speeds every roadmap refactor |
| 40 | Avo tests | test/integration/avo_*.rb, pages_tree, mind_graph, system_status; test/models/*_action_test.rb | About 1,130 lines carrying real invariants. | Port the invariants to model/service tests, then delete. | Coverage survives | M | X | Low | + RL (guards) |
| 41 | Test gaps | — | Missing tests for #2, #8, `PublicUrls`, #24. | Add them with the fixes. | — | S | N | None | + SEO, LANG |
| 42 | Routes | routes.rb:21-25; avo/youtube_embeds_controller.rb | The embed endpoint is editor infrastructure inside `mount_avo`. | `Admin::YoutubeEmbedsController`. | Survives Avo | S | A | None | + MED |
| 43 | Hard deletes | page.rb:24 (`dependent: :destroy`), 303-309; post.rb:13-23; schema per-locale unique slug indexes | Everything is destroyed physically. A trashed page would still hold its slug in the unique indexes. There is no restore path. | A `Trashable` concern (`trashed_at`). `Pages::Destroy`/`Posts::Destroy` trash by default and purge from the trash as a separate step. Add `WHERE trashed_at IS NULL` to the partial unique indexes and resolver scopes. GDPR deletion keeps a real hard-delete path. | Restore without backups | M | A (with Destroy services) | Med (index rewrite; no prod) | + TR, + VE, + GDPR (explicit purge); ✗ TR as is |
| 44 | Locale coupling | application.rb:23-30; mobility.rb (accessors at boot); routes.rb:91; schema expression indexes per locale | `config.i18n.available_locales` is content locales, Mobility's boot-time accessor set, admin-UI locales and route constraint all at once. Per-locale expression and unique indexes are fixed in the schema. | Split `Locales.supported` (a boot-time superset for Mobility accessors) from `Locales.enabled` (`site_settings`, runtime) and admin-UI locales. Evaluate a normalized `page_slugs(page_id, parent_id, locale, slug, path)` table: uniqueness, path lookup, redirects and runtime locales without per-locale DDL. | Runtime languages without deploys or migrations | L | N (decide before admin locale tabs) | Med | + LANG, + AI18N, + SEO hreflang/redirects; ✗ LANG as is |
| 45 | Path changes unobservable | page.rb:158-167 (`write_cached_paths`) | Old paths are overwritten silently. Redirects, CDN purge, webhooks and broken-link checks all need "from → to". | The cascade collects `{page_id, locale, from, to}` and the service emits `page.paths_changed` after commit. An auto-redirect subscriber writes `redirects(from_path, locale, page_id)`, and the resolver checks redirects on a miss. | Slug edits stop breaking URLs | S-M | N | Low | + SEO redirects, + CDN purge, + API webhooks, + QC; ✗ SEO as is |
| 46 | Attachments per model | page.rb:38; content_block.rb:27; site_setting.rb:2; content_blocks/_image.html.erb:3; pages/show.html.erb:11 | `has_one_attached` directly on each model, with raw `image_tag` and no variants. In-flight alt text would land per usage. | A `MediaAsset` (file, translated `alt_text`/`caption`, focal point), referenced by `belongs_to :media_asset` from blocks, pages (hero, OG image) and settings (logo). Alt text lives on the asset, with an optional per-usage override. A `responsive_image_tag(asset, sizes:)` helper. | One place for alt, variants and reuse | M | A (before admin image pickers; align the in-flight alt text) | Med | + MED, + QC (required alt), + CDN (variants), + SEO (OG image), + IMP, + VE (snapshot references asset ids, fixing purge-on-replace); ✗ MED as is |
| 47 | Block owner | content_block.rb:20; schema `content_blocks.page_id NOT NULL` | Blocks can only live on a Page. | A polymorphic `owner` (Page, Snippet, Template), or a `snippet` block type referencing a `Snippet` that owns blocks. Decide during the `block_type` → string migration. | Reuse without copy-paste | M | N (with the §8 string migration) | Med | + RC, + FRM, + PL; ✗ RC as is |
| 48 | Public cacheability | PagesController < ApplicationController (Authentication); application.html.erb:9 (`csrf_meta_tags`); no `Cache-Control`/`fresh_when` | The public site runs the session stack and emits per-session tokens, so no CDN can cache it. Preview (in-flight) would mix private and public responses on one URL. | `PublicController` base: no session, `fresh_when(page, site version)` / `Cache-Control: public`. Preview sends `private, no-store` (or uses a separate path). Forms fetch CSRF through JS. | CDN-ready | S-M | N (with in-flight layout/preview) | Low | + CDN, + FRM, + WF preview, + GDPR (no cookies before consent) |
| 49 | Hard-coded English in product UI | setup_controller.rb:12-16, 106, 127; system_check.rb messages; sessions/new.html.erb | Strings are not in I18n. | Use `t()` keys from the first admin view; the product locale is independent of content locales (#44). | Cheap if done from the start | S | A | None | + AI18N |
| 50 | Content types are code | post.rb:25; starter_content.rb:17-26; tools enums; mind_graph_controller.js:11-15; in-flight resume `store_accessor`s | Types and their fields need Ruby. The per-type `store_accessor`s put resume fields on every post. | String `content_type` + `ContentTypes` registry sourced from code (plugins, built-ins) **and** DB (`content_type_definitions` with a jsonb field schema). `post.fields` is an ActiveModel object built from either (§8). | Types without deploys | M-L | N (before admin post forms; align the in-flight resume work) | Med | + CT, + PL, + API (schema endpoint), + IMP; ✗ CT as is |
| 51 | Canonical host | sitemap.rb:14 (ENV `SITEMAP_HOST`); pages/_seo_meta.html.erb:23 (`request.original_url`) | There is no canonical public origin in the app. | `site_settings.public_url` + `PublicUrls#absolute_*`. | Absolute URLs everywhere | S | N | Low | + FEED, API/webhooks, SEO (canonical, hreflang, OG), INV/SEC emails |
| 52 | Navigation = tree | pages/show.html.erb:30-41; in-flight header nav | Navigation is derived straight from the tree inside views. | `Navigation.for(:header, locale:) → [Item(label, url, children)]`, tree-backed at first and replaceable by `menus`/`menu_items`. | Menus become a data change | S | A (with the in-flight public layout) | Low | + NAV, + LANG |

## 3. Proposed target structure (after the refactors and the own admin)

```
app/
  models/
    page.rb                      # tree integrity, associations, validations only
    page/cached_paths.rb         # concern: recompute/cascade cached_paths (after has_closure_tree)
    page/sibling_ranking.rb      # concern: "move to rank N" semantics
    post.rb                      # associations, content-type lookup via registry
    content_block.rb             # block row; delegates type behaviour to BlockTypes registry
    concerns/localized_slug.rb   # per-locale generation + presence + uniqueness(scope:)
    concerns/publishable.rb      # (in-flight) published scope, published?, publish!/unpublish!
    concerns/revisable.rb        # revision_snapshot / restore_snapshot! (§7)
    site_setting.rb              # + social_link_rows=, plugin_settings (§8)
    user.rb                      # + role enum, ensure_not_last_owner
    api_token.rb                 # + issue!(user, rotate:), raw_from_authorization
    audit_event.rb, revision.rb  # §7
    concerns/trashable.rb        # trashed_at, scopes; partial unique indexes exclude trashed (#43)
    media_asset.rb               # file + translated alt_text/caption; referenced by blocks/pages/settings (#46)
    redirect.rb                  # from_path/locale -> page; auto-created on page.paths_changed (#45)
    content_type_definition.rb   # DB-defined content types + field schema (#50, §8)
    current.rb                   # session, user, api_token, channel, request_ip, site
    locales.rb                   # codes, names, fallback_chain(locale) against Current.site
    setup.rb, setup/*            # unchanged (+ Setup::Steps)
    starter_content.rb           # via Pages::Save / Posts::Save
  services/                      # the only write path (admin, MCP, setup, seeds)
    posts/save.rb                # create/update with translations, publish semantics, tags
    pages/save.rb                # page attrs + translations
    pages/move.rb                # parent/position (drag & typed)
    pages/destroy.rb             # leaf-only rule surfaced as a Result
    content_blocks/save.rb       # one block, typed settings
    content_blocks/reorder.rb    # ordered ids for one page
    revisions/restore.rb         # §7
  queries/
    public_site/resolver.rb      # locale+path -> Result(page, post, listing_block), scope-injectable
    page_tree.rb                 # preloaded tree for admin nav/tree screen
    post_graph.rb                # nodes/edges for mind graph
    navigation.rb                # Navigation.for(:header, locale:) -> items; tree-backed now, menus later (#52)
  policies/                      # §7: ApplicationPolicy + Page/Post/ContentBlock/SiteSetting/User/ApiToken
  lib-ish/content_spiel/         # (lib/content_spiel/) plugin API: registry, block_types, content_types, hooks (§8)
  urls/public_urls.rb            # (or models/) locale prefix + page/post paths + canonical post page
  tools/                         # application_tool.rb + 4 tools, each ~10 lines, calling services
  controllers/
    application_controller.rb    # Authentication; no allow_browser
    public_controller.rb         # base for the public site: no session/CSRF, HTTP caching (#48)
    pages_controller.rb          # < PublicController; thin: resolver + render; preview via policy (private, no-store)
    sessions/passwords/setup/mcp # unchanged, product layout
    admin/
      base_controller.rb         # layout "admin", allow_browser, authorize helpers
      dashboard_controller.rb
      pages_controller.rb        # CRUD + tree screen (Turbo); move via Pages::Move
      content_blocks_controller.rb   # nested under pages, per-block Turbo frames
      posts_controller.rb        # per-locale tabs over Mobility locale accessors
      tags_controller.rb, site_settings_controller.rb, users_controller.rb
      api_tokens_controller.rb   # issue/revoke only
      youtube_embeds_controller.rb, system_status_controller.rb, mind_graph_controller.rb
      revisions_controller.rb, audit_events_controller.rb   # §7
  views/
    layouts/public.html.erb (in-flight), product.html.erb (auth/setup), admin.html.erb
    product/_errors, _flash, _system_check_results   # shared product UI partials
    content_blocks/<type>.html.erb        # public render, one per registered type
    admin/content_blocks/_<type>_form.html.erb   # admin form, one per registered type
  helpers/
    pages_helper.rb              # seo_* + thin delegation to PublicUrls
    product_ui_helper.rb         # ex-SetupHelper class strings
  javascript/
    application.js (public: turbo + public controllers), admin.js (trix, actiontext, admin controllers)
    controllers/theme_controller.js; controllers/admin/{pages_tree,mind_graph,youtube_paste}_controller.js
```

## 4. Shared seams for the own admin (introduce first)

All services return `Result = Data.define(:record, :errors) { def ok? = errors.empty? }`. None of them raise on validation failure, so admin forms, MCP tools and setup all branch the same way. Each one runs `Policy.authorize!` (§7), writes in a transaction, captures a revision and records an audit event (§7).

1. **`PublicUrls`**
   - Interface:
     - `PublicUrls.new(default_locale: Current.site.default_locale)`
     - `#prefix(locale) → "" | "/de"`
     - `#page_path(page, locale = I18n.locale)`
     - `#post_path(post, locale = I18n.locale, via: nil)`: canonical listing page unless `via:` is given
     - `#canonical_page_for(post) → Page?`
     - `#redundant_prefix?(locale_param) → bool`
   - Replaces `PagesHelper#page_url_path/#post_url_path/#locale_prefix`, `sitemap.rb:42-45` and `PagesController#redirect_default_locale_prefix`. New users: the language switcher, admin "view on site" and the MCP serializer `url`.
2. **`PublicSite::Resolver`**
   - Interface: `.new(scope: :published | :preview).call(locale:, path:) → Result(page:, post:, listing_block:)`
   - Replaces the body of `PagesController#show` and `#resolve_post_detail`. The in-flight preview uses `scope: :preview`.
3. **`Posts::Save`**
   - Interface: `.call(post = Post.new, attributes:, locale: nil, actor: Current.user) → Result`
   - `attributes`:
     - untranslated keys: `content_type`, `metadata`/typed fields, `tag_names`
     - `published: true/false/nil`: true sets `published_at ||= now`, false sets nil, nil leaves it alone
     - translations as `{ title:, slug:, excerpt:, body: }` for `locale`, or `translations: { "de" => {...} }` for multi-locale admin forms
   - Replaces the bodies of `CreatePostTool` and `UpdatePostTool` (fixes #24), `StarterContent.find_or_create_sample_post!`, the seeds and the Avo post form.
4. **`Pages::Save` / `Pages::Move` / `Pages::Destroy`**
   - Interface:
     - `Pages::Save.call(page = Page.new, attributes:, translations:, actor:) → Result`
     - `Pages::Move.call(page, parent:, position:, actor:) → Result`
     - `Pages::Destroy.call(page, actor:) → Result`: surfaces `ensure_no_children` errors
   - Replaces `Avo::ToolsController#reorder_page`, the Avo page form (nested attrs) and `StarterContent#find_or_create_section_page!`.
5. **`ContentBlocks::Save` / `ContentBlocks::Reorder`**
   - Interface:
     - `Save.call(block, attributes:, translations:, actor:)`: attributes include `block_type` and typed `settings` validated by the block type's settings class (§8)
     - `Reorder.call(page, ordered_ids, actor:)`
   - Replaces `Page#content_blocks_attributes` and `NestedContentBlocks`.
6. **`ApiToken.issue!(user, rotate: false) → [token, raw]`, `ApiToken#revoke!`, `ApiToken.raw_from_authorization(header)`**
   - Replaces `SetupController#update_mcp_token`, `Avo::Actions::RegenerateApiToken`, `McpController#authenticate` and the `rack_attack` regex.
7. **`Current.site` + `SiteSetting#social_link_rows=`**
   - Replaces every `SiteSetting.instance` call site (12 in app/config) and `SetupController#site_params`.
8. **`PageTree.call → root (children preloaded, ordered)`, `PostGraph.call → { nodes:, edges: }`**
   - Replaces the queries in `Avo::ToolsController#pages_tree/#mind_graph`. `editUrl` moves to the view, built with `admin_post_path`.

## 5. Prioritised refactor list

Assumption: the Must-have roadmap items are roles/permissions, audit, security basics, legal/GDPR, SEO (incl. redirects and auto sitemap), runtime languages, media library + alt text, trash and versioning. Re-rank if the roadmap says otherwise. Ordering favours seams for those items first, then bugs.

| Order | Item | Rationale (roadmap) | Effort | Timing |
|---|---|---|---|---|
| 1 | #2 locale fallback / slugs in all locales (+ test), with #1 `LocalizedSlug` | A real bug, and a prerequisite for LANG and SEO hreflang. Belongs on the in-flight slug branch. | M | Before the own admin (in-flight branch) |
| 2 | #24 re-publish bug, #37 iframe scrubber + CSP | Correctness and SEC. Authors (RL) widen the trust boundary. | S+M | Now |
| 3 | #44 locale split decision (`Locales.supported/enabled`, slug-table evaluation), #17 | LANG and AI18N. It decides how admin locale tabs and slug indexes are built, so settle it before any admin form. | L (decision + `Locales` S) | Now |
| 4 | #27 + #51 + #12 `PublicUrls` with absolute URLs, `Current.site`, latch | SEO, FEED, API, NAV and CDN all build URLs. The language switcher is in flight now. | S | Now |
| 5 | #19 `PublicSite::Resolver` + #7 `listing` + #48 `PublicController`/caching + #20 | Preview (in flight), WF, TR, CDN and GDPR (no cookies). | M | Now (with preview) |
| 6 | #45 path-change events + auto redirects | SEO redirects (Must). Cheap now while `write_cached_paths` is fresh in mind. | S-M | Now |
| 7 | #29 explicit stylesheets + product layout | The theme build is in flight. | S | Now |
| 8 | §8 prerequisites: string `block_type`/`content_type`, `BlockTypes`/`ContentTypes` registries (#50, #6), and the block-owner decision (#47) | CT, PL and RC. The admin forms are generated from the registry. Align the in-flight resume `store_accessor`s. | M-L | Before the own admin |
| 9 | #8 canonical post URL + posts in sitemap | SEO (auto sitemap, Must), FEED, API | M | Before the own admin |
| 10 | #39 test helpers + #41 gaps | Makes the rest cheaper. | S | Now |
| 11 | §4 services (`Posts::Save`, `Pages::*`, `ContentBlocks::*`, `ApiToken.issue!`) + #23, #25 | The single write path that RL, AU, VE, WF, SR, API webhooks, CDN purge and PL hooks all attach to. MCP switches first. | M | Before the own admin (first build step) |
| 12 | Roles + policies + `Current.channel/api_token` + `audit_events` (§7.1-7.2), #14, #15 | RL, AU and SEC (login history = audit), INV | M | With the own admin (start) |
| 13 | #43 `Trashable` + Destroy services + partial indexes | TR (Must). Easiest while Destroy services are new. | M | With the own admin |
| 14 | #46 `MediaAsset` (+ align the in-flight alt text) | MED and alt QC (Must). It must exist before the admin grows image pickers. | M | With the own admin (early) |
| 15 | #13, #21, #26, #28, #32, #34, #42, #49, #52, #6: admin build items | NAV, AI18N | M | With the own admin |
| 16 | #3 split Page into concerns | Readability, and hosts #45 | M | With or after the own admin |
| 17 | Revisions + restore, including pending revisions for WF (§7.3) | VE, WF | M | After the own admin MVP |
| 18 | #40 port Avo invariants → delete Avo; #5, #36, #4, #9 | Cleanup | M | After admin parity |
| 19 | #10, #11, #18, #22, #30, #31, #33, #35, #38 | Hygiene | S | Opportunistic |

## 6. Don't touch (looks odd, is right)

- **Callback declaration order in `Page`**:
  - `has_closure_tree` comes first.
  - `after_save :recompute_cached_paths` must run after closure_tree's own `after_save`.
  - `before_destroy :ensure_no_children, prepend: true` must come before `_ct_before_destroy`.
  - Any concern split (#3) must `include` *after* `has_closure_tree` and keep the prepend.
- **`update_columns` in `write_cached_paths` and `place_among_siblings`**. This is deliberate: it avoids re-entering callbacks and validations across the subtree.
- **The query inside `write_cached_paths`** (`where(parent_id:)` rather than `children`). It avoids stale associations.
- **`slug_in` goes *through* fallbacks; the uniqueness check uses literal locale accessors.** The asymmetry is intended (even after #2, keep "path uses the visitor's view, validation uses the literal value").
- **`find_by_full_path … .order(:id).first`**. The explicit tiebreak is a guarantee, not noise.
- **`find_by_localized_slug`'s two queries and the `IS NULL` fallback half**: one URL per post per locale. Only add `order`.
- **`listed_posts` does not apply `limit`**: the limit trims display, not responsibility. Keep this in `#listing` (#7).
- **Routes**:
  - two separate catch-alls
  - `format: false`
  - `(/*path)` with `defaults: { path: "" }`
  - `root` separate from `*path`
  - `before_action { request.format = :html }`
  - 302, not 301, for the default-locale redirect
- **`Setup::RedirectConstraint` as a route constraint** rather than a before_action. It covers engines and Active Storage, and plugin engines (§8) too.
- **`LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE`** in `update_admin`.
- **`SetupController::RATE_LIMIT_STORE`** as a per-process MemoryStore, since `Rails.cache` is a null store in test.
- **`Setup::Token`** derived from `secret_key_base`.
- **`SystemCheck::STORAGE_PROBE`** talks to the service directly, not through `Blob.create_and_upload!`.
- **MCP**: a fresh `MCP::Server` per request, `ActionController::API`, `stateless: true`, `serve_subscriptions_listen: false`.
- **`PostSerializer`'s `post.body.body&.to_html`**, not `post.body.to_s`.
- **Per-locale partial unique indexes and expression indexes in schema.rb** (`nulls_not_distinct`). Don't replace them with a generic GIN index. Runtime languages will need a migration generator, not removal.
- **No Page/Post fixtures.** Fixtures bypass closure_tree hierarchy rows and the `cached_paths` callbacks. Use helpers (#39), not YAML.
- **`has_one_attached :image` sharing a name with the `image` enum value**, and `inverse_post_relations dependent: :destroy`.
- **Mobility `presence` and `locale_accessors` plugins.** The admin's per-locale tabs need non-falling-back accessors.
- **`YoutubeEmbed#to_trix_content_attachment_partial_path`**. The own admin still uses Trix, which strips iframes.
- **Theme CSS choices**: no global `color-scheme`, and `font-cs` rather than `--font-sans`.

## 7. Permissions, audit log, versioning

All three plug into the §4 service layer, which is why the services come first. Model callbacks are the wrong seam for all three:
- `update_columns` cascades bypass them.
- Seeds and starter content would create noise.
- Callbacks can't tell "publish" from "edit".
- Nested block edits would produce one event per row instead of one per user action.

**Shared context.** Extend `Current` with `user`, `api_token`, `channel` (`:admin | :mcp | :setup | :console | :system`), `request_ip`, `request_id` and `site`:
- `Admin::BaseController`, `SetupController` and `McpController#authenticate` set them. The MCP controller sets `Current.user = api_token.user` and `Current.api_token`, in addition to `server_context`.
- Console and jobs default to `:console`/`:system` with `user = nil`.

### 7.1 Permissions / roles

- **Roles.** Add `users.role` as a string enum: `owner | admin | editor | author`. Capabilities are cumulative:
  - author: create posts, edit own drafts (needs `posts.created_by_id`), no publishing, no pages or tree changes
  - editor: all content (pages, blocks, posts, tags), publish/unpublish, move pages, preview
  - admin: editor plus site settings, users except owners, API tokens for self and others, system status
  - owner: everything, plus managing admins and owners
  - The setup wizard's first user becomes `owner`. Invariant: the last owner can't be deleted or demoted. This replaces the Avo-only guard (#14).
- **Mechanism: an in-house policy layer, no gem.** Pundit-shaped, about 60 LOC:
  - `ApplicationPolicy.new(user, record)` with `#<action>?` methods
  - a nested `Scope#resolve`
  - `Policy.for(user, record)`
  - `Policy.authorize!(user, action, record)`, raising `Policy::NotAuthorized`
  - `Policy.allowed?(user, action, record)`

  Justification: 4 roles × about 7 resources fit a small matrix, and the main non-controller caller (MCP tools) gets nothing from Pundit's controller helpers. The Pundit-compatible shape means switching later is mechanical. ActionPolicy's extras (caching, reasons, scope matchers) aren't needed yet.
- **Where enforced.**
  - **Services are authoritative.** Each §4 service calls `Policy.authorize!(actor, :update, record)` first. `Posts::Save` also checks `:publish` when `published:` is non-nil.
  - Controllers use `allowed?` only to hide UI, through a `can?(action, record)` helper.
  - Index screens and `ListPostsTool` use `PostPolicy::Scope.new(user).resolve`.
- **MCP.** A token acts as its user's role; the tools call the same services, so the same rules apply automatically. Optionally add `api_tokens.scope` (`read | write`), checked in `ApplicationTool` against each tool's `read_only_hint`. Token scope is intersected with the role.
- **Public preview.**
  - `PagePolicy#preview?`: any signed-in user with role ≥ author (authors only for their own posts).
  - `PagesController` picks `PublicSite::Resolver.new(scope: policy.preview? ? :preview : :published)`.
  - Preview responses must send `Cache-Control: private, no-store`.
- **Seams.**
  - `Policy.authorize!(user, action, record)`
  - `Policy.allowed?(user, action, record)`
  - `XPolicy::Scope.new(user).resolve`
  - `User#role`
  - `User#ensure_not_last_owner`
  - `ApiToken#scope`
- **Timing.** The role column and the policy layer come **with the own admin, at its start**: in place before the first admin controller, so no screen ships unguarded. Wire them into the services as soon as those exist; MCP benefits immediately.

### 7.2 Audit log

- **Table `audit_events`.**

  | Column | Notes |
  |---|---|
  | `id` | |
  | `occurred_at` | |
  | `action` | string, e.g. `post.published`, `page.moved`, `user.role_changed`, `session.signed_in`, `session.sign_in_failed`, `api_token.issued`, `setup.completed` |
  | `subject_type`, `subject_id` | nullable |
  | `subject_label` | denormalized title, so the entry survives deletion |
  | `actor_id` | FK users, nullable |
  | `api_token_id` | nullable |
  | `channel` | |
  | `ip`, `user_agent`, `request_id` | |
  | `details` | jsonb: a changed-attribute summary, e.g. `{ "title.de" => [old, new] }`, or `{from_parent:, to_parent:, position:}` |

  Indexes: `(subject_type, subject_id, occurred_at)` and `(actor_id, occurred_at)`. Append-only: no update or destroy in the app.
- **Recording.** `AuditEvent.record!(action, subject: nil, details: {})` reads the rest from `Current`.
  - It is called inside each service transaction, after a successful save. Details come from `saved_changes` plus Mobility's per-locale diff (compare `record.<attr>_<locale>` before and after for the translated attributes). One helper, `AuditEvent.translated_changes(record, attrs)`, does this.
  - Auth events (`SessionsController#create` success and failure, `destroy`, `PasswordsController#create`/`#update`) and setup steps call `record!` directly. They are not content services.
- **In scope:**
  - content create/update/destroy, publish/unpublish, page move, block reorder
  - tag changes
  - site settings
  - user create, role change, delete, password change
  - token issue/revoke
  - sign-in, sign-out and failed sign-in
  - password reset requested/completed
  - setup token verified, admin created, setup completed
  - every MCP write (reads optional; `api_tokens.last_used_at` already exists)
- **Out of scope:** public reads.
- **Hooks.** `record!` also publishes `ActiveSupport::Notifications.instrument("<action>.content_spiel", event:)`. This is the plugin hook source (§8), so the audit log and the hooks can't drift apart.
- **Timing.** **With the own admin.** The table is trivial and the seams are the services. Build it together with the policy layer so every admin action is logged from day one.

### 7.3 Versioning

**Options against this schema**

- **PaperTrail.** It versions one row per model.
  - Pros: mature, whodunit.
  - Cons: A page "version" here is an aggregate:
    - translated jsonb columns
    - `action_text_rich_texts` rows, one per locale per record, keyed `(record, name, locale)` and owned by Rails
    - ordered `content_blocks`, each with its own rich-text rows and attachments
    - post tags

    Restoring that needs association reification. That comes from `paper_trail-association_tracking`, which is separate and lags PaperTrail. `reify` on `Page` would also write back stale `parent_id`, `position` and `cached_paths` unless those are ignored. On top of that, the `update_columns` cascade isn't captured, which is correct, but it means versions never describe paths anyway.
- **Logidze.** Trigger-based `log_data` jsonb on each row.
  - Pros: fast, captures even `update_columns`, time travel with `at(time:)`.
  - Cons:
    - The triggers need `fx` or `structure.sql`, and CLAUDE.md fixes the project on `schema.rb`.
    - It needs triggers on the Rails-owned `action_text_rich_texts` table.
    - The slug-cascade `update_columns` writes a log entry on every descendant, which is noise.
    - Actor attribution needs `Logidze.with_responsible` wrapping everywhere.
    - Aggregate restore across blocks and rich texts is still hand-written.
- **In-house snapshot table (recommended).**
  - `revisions` columns: `id`, `item_type`, `item_id`, `number`, `snapshot jsonb`, `audit_event_id`, `created_at`, unique `(item_type, item_id, number)`.
  - One revision per *user action* on an aggregate root (Post, Page), written by the service after a successful save.

**Recommendation: in-house snapshots.**

- **`Revisable` concern.**
  - `#revision_snapshot → Hash`
  - `#restore_snapshot(hash)`: assigns attributes; does not save
- **Post snapshot:**
  - `{ translations: { title:, slug:, excerpt: } }` (raw jsonb, all locales)
  - `body: { locale => html }` (via `body_<locale>&.body&.to_html`)
  - `content_type`, `metadata`, `published_at`, `tag_ids`
- **Page snapshot:**
  - `translations` (title, slug, subtitle, meta_*), `page_type`, `published_at`, `hero_image_blob_id`
  - `blocks: [{ id, block_type, position, settings, caption:{…}, body:{locale=>html}, image_blob_id }]`
  - Blocks are part of the page's revision, not separately versioned, because they are edited as part of the page.
- **Excluded on purpose:** `parent_id`, `position` and `cached_paths`. Tree placement is not content. Moves are audited, not versioned.
- **Restore.** `Revisions::Restore.call(revision, actor:)` builds attributes from the snapshot and runs them **through `Pages::Save` / `Posts::Save`**, so policies, validations and audit all apply, and a new revision records the restore. As a result:
  - `cached_paths` are recomputed by the normal after_save.
  - A restored slug that now collides with a current sibling surfaces as a normal `slug_<locale>` form error, instead of silently taking the URL.
  - Blocks are reconciled by `id`: update existing, recreate missing, destroy extra.
  - A destroyed page restores under its old parent only if that parent still exists. Otherwise the admin asks for a parent.
- **Attachments.**
  - `has_one_attached` purges the replaced blob, so image restore would dangle. Either attach with the previous blob kept (skip purge when the blob is referenced by a revision), or accept that image restore works only while the blob exists.
  - Blobs embedded in rich text are not purged on body edits, so the sgids in body HTML stay restorable.
- **Retention:** keep the last N per item (a setting), pruned by a job.
- **Roadmap hooks:**
  - Add `revisions.state` (`applied | pending`) from day one. A *pending* revision is the working copy of already-published content under a review/approval workflow: an edit is saved as a pending snapshot, and approval runs `Revisions::Restore`. This avoids a second draft-copy mechanism later.
  - Snapshots reference `media_asset_id` (#46), not blob ids, which removes the purge-on-replace problem.
  - Trashed records (#43) keep their revisions, so trash plus history gives a full undo.
- **Seams:**
  - `Revision.capture!(record, audit_event:)`
  - `Revisions::Restore.call(revision, actor:) → Result`
  - `Revisable#revision_snapshot`
  - `Revisable#restore_snapshot`
- **Timing.** **After the own admin MVP.** Define the snapshot methods (and a capture test) alongside the services, so the table and restore UI can be added without touching the write paths.

## 8. Plugin API

**Principle.** A plugin is a gem containing a `Rails::Engine`: views, migrations, locales and importmap pins come for free. It registers itself through one small, versioned Ruby API (`ContentSpiel.plugin`). No new gems are needed. Plugins are trusted code with no sandbox; document that.

```ruby
# in the plugin's engine initializer
ContentSpiel.plugin :gallery, requires: "~> 1.0" do |p|
  p.block_type :gallery, settings: Gallery::Settings,          # ActiveModel::Attributes
    public_partial: "gallery/blocks/gallery", admin_partial: "gallery/admin/block_form"
  p.content_type :event, fields: Events::Fields                 # typed metadata (ActiveModel)
  p.mcp_tool Gallery::ListTool
  p.admin_menu "Galleries", path: -> { gallery.admin_root_path }, permission: [:manage, Gallery::Album]
  p.dashboard_widget "gallery/admin/widget", permission: [:read, Gallery::Album]
  p.policy Gallery::Album, Gallery::AlbumPolicy
  p.settings Gallery::PluginSettings                            # stored in site_settings.plugin_settings["gallery"]
  p.routes { mount Gallery::Engine, at: "/admin/ext/gallery" }
  p.subscribe "post.published" { |event| ... }                  # sugar over AS::Notifications
end
```

| Extension point | Mechanism / where it plugs in | Refactor needed | When |
|---|---|---|---|
| **Block types** | `ContentSpiel::BlockTypes` registry: `name`, settings class, public partial, admin form partial, capabilities (`lists_posts?` for permalink resolution). `show.html.erb:27` already dispatches on a naming convention; it would use `registry.fetch(type).public_partial`. `PagesController:77` (`find_by(block_type: :post_list)`) and `Resolver` ask for blocks with `lists_posts?`. `ContentBlock#listed_posts` moves to the post_list type object. | `content_blocks.block_type` changes from integer enum to **string** (no prod: edit the migration) with inclusion validated against the registry. `settings` becomes a typed object per type (#6). Built-in types register through the same API. | **Before** the own admin (admin forms are built from the registry) |
| **Content / post types** | Roadmap: types must also be definable **without code** (#50). The registry therefore has two sources: code (built-ins and plugins, below) and the DB (`content_type_definitions`: name, labels per locale, a jsonb field list `[{key, type, required, translated}]`). A small `FieldSet` builder turns either source into the same ActiveModel fields class, so admin forms, validation, MCP schemas and the API schema are generated from it. `ContentSpiel::ContentTypes` registry: `name`, label, `fields` class (ActiveModel over `posts.metadata`), admin partial, public partial for detail and list items. `post.fields` returns `registry.fetch(content_type).fields.new(post.metadata)`. | `posts.content_type` changes from integer enum to **string**. The in-flight **resume `store_accessor`s on `Post` work against this**: every post would get resume fields. Prefer `ResumeEntry::Fields` (typed object) registered as a built-in type. MCP tool `enum: Post.content_types.keys` (evaluated at class load) must read the registry after boot (`to_prepare`), and the hard-coded `StarterContent::SECTIONS` and mind-graph colours (mind_graph_controller.js:11-15) must too. | **Before** the own admin (coordinate with the in-flight resume work) |
| **Themes** | A theme is a plugin (or `app/themes/<name>`) providing a view path, a public layout and a `--th-*` token stylesheet. `PagesController` does `prepend_view_path Current.theme.view_path` and `layout -> { Current.theme.layout }`. Block and content-type public partials can be overridden by the theme through view-path precedence. The active theme lives in `site_settings.theme`. | Explicit stylesheets per layout (#29). The public layout must not use `:app`. | **After** the in-flight public theme lands (it defines the first theme); before third-party themes |
| **Admin extensions** | `ContentSpiel::Admin.menu` / `.dashboard_widgets` registries, rendered by the admin layout and filtered through `Policy.allowed?`. Plugin screens are engine controllers inheriting `ContentSpiel::Admin::BaseController`: layout, auth, `Current`, policies and the product UI kit (#28) all come for free. | `Admin::BaseController` must be a public API class (stable name). The admin Tailwind build needs `@source` entries for plugin view paths, generated from the registry at build time (Tailwind v4 only scans the app by default). Plugin Stimulus controllers are pinned under `controllers/<plugin>/…` so `eagerLoadControllersFrom` picks them up. | **With** the own admin |
| **Routes** | `routes.rb` calls `ContentSpiel::Plugins.draw_routes(self)` **before** the public catch-alls (engine routes appended after boot would be swallowed by `get "*path"`). Plugin admin routes live under `/admin/ext/<name>`. Public plugin routes need an explicit reserved prefix. | A hook in routes.rb. `Setup::RedirectConstraint` stays in front of everything (it covers engines by design). | **With** the own admin |
| **MCP tools** | `ContentSpiel::Mcp.tools` registry. `McpController:21`'s hard-coded array becomes `ContentSpiel::Mcp.tools`. Tools subclass `ApplicationTool` (#23) and call services, so policies and audit apply. | #23 | **Now** (cheap) |
| **Event hooks** | `ActiveSupport::Notifications` `"<action>.content_spiel"`, emitted by `AuditEvent.record!` (§7.2): one event vocabulary for the audit log and for plugins. Subscribers are synchronous and must not veto. Veto belongs in validations and policies; plugins should enqueue jobs for slow work. Payload: `{ event: AuditEvent, subject: }`. | Services + audit (§7) | **With** the own admin |
| **Settings** | `site_settings.plugin_settings jsonb`, namespaced per plugin, read and written through the plugin's ActiveModel settings class. The admin renders a generic settings screen per plugin from that class's attributes (or the plugin's partial). | Add the column. | **With** the own admin |
| **Policies / roles** | `p.policy Model, PolicyClass` registers with `Policy.for`. Plugin permissions map onto the four built-in roles; custom roles are out of scope for v1. | §7.1 | **With** the own admin |

**Install and enable.**
- Installing a plugin means adding the gem to the Gemfile, then `bin/rails <plugin>:install:migrations && db:migrate`, then a rebuilt image (Kamal).
- Enabling: a registered plugin is active unless it appears in `site_settings.disabled_plugins`. Disabling hides its menu, blocks and tools; its blocks render nothing publicly and show as "unavailable type" in the admin. Data is kept.
- Plugins namespace their tables (`<plugin>_*`).

**API versioning and compatibility.**
- `ContentSpiel::PLUGIN_API_VERSION = "1.0"`. `ContentSpiel.plugin(..., requires:)` is checked at boot, and a mismatch fails fast with a clear message.
- The public surface is exactly:
  - the `ContentSpiel.plugin` DSL
  - `Admin::BaseController`
  - the §4 service signatures
  - `Policy`
  - the event names and payloads
  - `PublicUrls`

  Everything else is internal. Document this in `docs/plugin-api.md`, and follow semver for that surface only.
- A sample plugin under `test/dummy_plugins/sample` (a block type + an MCP tool + a menu item) loads in the test suite, as a contract test that the seams keep working.

**What must be refactored now (before the own admin), so the seams exist:**
1. String `block_type`/`content_type` columns and the `BlockTypes`/`ContentTypes` registries, with built-ins registered through them (#6 folds in).
2. The services of §4 as the only write path.
3. The `ApplicationTool` + MCP tool registry (#23).
4. Explicit stylesheets per layout (#29).
5. A routes hook before the catch-alls.

Everything else in this section comes **with** (admin menu, widgets, settings, hooks, policies) or **after** (themes as plugins, the public plugin docs and sample plugin) the own admin.

## 9. Roadmap fit: structures that make roadmap items expensive

| Roadmap item | Current structure that makes it expensive | Seam that fixes it (finding / section) |
|---|---|---|
| Custom content types & fields (no code) | Integer `content_type` enum, per-type Ruby (`store_accessor`s in flight), enums baked into MCP schemas at class load, hard-coded JS colours | #50, §8 registry with a DB-backed definition, string column |
| Navigation separate from tree | Nav derived inline from `children` in views | #52 `Navigation.for` + #27 `PublicUrls` for item URLs |
| RSS/Atom | No canonical post URL, no absolute host, listing query in a partial | #8, #51, #7. A feed is then `listing` + `PublicUrls#absolute_post_url` |
| Trash / restore | Hard deletes, unique slug indexes without a trash predicate, no Destroy seam | #43, §4 Destroy services, resolver scope #19 |
| Visitor + admin search | Translated text spread over jsonb columns and `action_text_rich_texts` rows per locale; no write seam to maintain an index | §4 services + `*.content_spiel` events (§7.2) feeding a `search_documents(locale, record, tsvector)` table (Postgres FTS, no gem). Admin global search reads the same table and is filtered by `Policy::Scope` |
| Reusable content (snippets, templates, presets) | `content_blocks.page_id NOT NULL`; nested attrs on Page | #47 block owner, #6 typed settings (preset = saved settings), `ContentBlocks::Save` |
| Security basics (2FA, password policy, sessions, login history) | Mostly fine: `sessions` has ip/UA; `start_new_session_for` is one seam | 2FA as a second step before `start_new_session_for`; password policy as a `User` validation; session list/revoke = `Current.user.sessions`; login history = audit events (§7.2). Keep `allow_browser` off the public site (#20) |
| Legal / GDPR | Session and CSRF stack on public pages (cookies before consent); no hook for consent; audit rows reference users | #48 cookie-less public controller; a consent hook = theme layout `content_for :consent` + a plugin setting; user export via `Revisable` snapshots + audit rows; user delete nullifies `actor_id` (`subject_label` kept); hard-delete path beside trash (#43) |
| Forms + submissions + spam | No public POST route slot (catch-alls), CSRF tied to cached pages, closed block enum | §8 routes hook before catch-alls; `form` block type via registry; JS-fetched CSRF or honeypot + rate-limit (Rack::Attack already present) |
| Publishing workflow (review, comments, edit lock, scheduled unpublish) | `published_at` is the only state; edits to published content go live immediately (no working copy) | In-flight `Publishable` must own `status` + `published_at` + `unpublish_at` in one scope. Pending revisions (§7.3) are the working copy. Edit lock = `locked_by_id/locked_at` on aggregate roots checked in `Pages::Save`/`Posts::Save`. Policies (§7.1) gate approval |
| Headless read API + webhooks | Serialization exists only for MCP (`PostSerializer`); no absolute URLs; no events | Generalize serializers (+ block and page serializers) for `Api::V1` behind `ApiToken` scopes; webhooks = subscribers to `post.published`/`page.paths_changed` events (#45, §7.2) |
| Caching / CDN purge + responsive images | Session stack on public pages, no ETags, raw `image_tag`, silent path changes | #48, #45 (purge targets), #46 `responsive_image_tag` |
| Media library + alt text | `has_one_attached` per model; alt text planned per usage | #46 `MediaAsset` |
| Import / export / backups | No aggregate serialization | `Revisable#revision_snapshot` (§7.3) doubles as the export format; blobs via `MediaAsset` |
| Content quality checks | Internal links in rich text are literal URLs (break on slug change); no alt source | #45 redirects soften breakage; checks run as event subscribers or a job over `PublicUrls` + `PublicSite::Resolver` (resolves internal links); required alt via `MediaAsset` |
| Admin UI i18n | English literals; UI locale list = content locale list | #49, #44 |
| SEO (redirects, hreflang, OG image, noindex, auto sitemap) | URL building ×3, no host, silent path changes, sitemap via rake only, no posts in sitemap | #27/#51 (`PublicUrls#alternates(page)` for hreflang), #45 redirects, #46 OG image, `noindex` column read by `_seo_meta`, sitemap regenerated by a job subscribed to publish/path events, #8 |
| Runtime languages | Mobility accessors fixed at boot, per-locale DDL (expression and unique indexes), route regex, I18n config coupling | #44 (supported vs enabled, slug table), #17, #2 |
| Invites | Users created only by the setup wizard (and Avo) | `Users::Invite.call(email, role:, actor:)` using `generates_token_for :invitation` (same pattern as password reset); roles #7.1; audit |

Flags (structures to avoid adding while the roadmap is pending):
- More integer enums.
- More `has_one_attached` on content models.
- More `after_save` side effects on `Page`/`Post`. Put side effects in services and event subscribers.
- More hand-built URLs outside `PublicUrls`.
- More per-locale columns or indexes in migrations.

---
**Finding count by "when":** now-refactor (N) 34 · with own admin (A) 15 · goes away with Avo (X) 3. Total 52.
