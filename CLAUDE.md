# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

ContentSpiel is a Rails 8.1 CMS: a page-tree-driven public website plus CS Studio, its own admin. Content editors build pages out of ordered content blocks (rich text, images, post listings), organize them in a tree, and the same tree drives navigation, routing, and the sitemap. Rich text is Tiptap/ProseMirror JSON. Everything is translated into three locales (en/de/es) via Mobility.

## Setup & Commands

```sh
docker compose up -d          # Postgres 17, published on host port 5433 -- start this first
bin/setup --skip-server       # installs gems, prepares dev + test databases
bin/rails db:seed             # creates a development admin account (dev only, see db/seeds.rb)
bin/rails server               # or `bin/dev`, which runs server + `tailwindcss:watch` (see Procfile.dev)
```

- App: http://localhost:3000
- Sign in: http://localhost:3000/session/new
- Admin (CS Studio, behind the same sign-in): http://localhost:3000/cs-studio (`ContentSpiel::ADMIN_PATH`, configurable via `ADMIN_PATH`)

**Tests:** `bin/rails test` (full suite, minitest). Single file: `bin/rails test test/models/page_test.rb`. Single test: `bin/rails test test/models/page_test.rb -n test_method_name` or `bin/rails test test/models/page_test.rb:42` (line number). System tests (Capybara/Selenium) are separate: `bin/rails test:system`.

**Lint/scan** (all run in CI, see `.github/workflows/ci.yml`):
```sh
bin/rubocop            # style (rubocop-rails-omakase, config in .rubocop.yml)
bin/brakeman            # static security analysis
bin/bundler-audit       # known CVEs in gems
bin/importmap audit     # known CVEs in JS deps (import maps, no npm/node_modules)
```

**DB:** `bin/rails db:prepare` / `db:migrate` / `db:test:prepare`. Schema lives in `db/schema.rb` (Postgres, jsonb-heavy) -- no `db/structure.sql`.

**Deploy:** Kamal (`.kamal/`), containerized via `Dockerfile`. Not typically invoked from Claude Code sessions.

## Architecture

### The page tree

`Page` (`app/models/page.rb`) is a `closure_tree` (gem `closure_tree`), backed by a `page_hierarchies` closure table, with exactly one root (the homepage, enforced by `only_one_root_page`). Sibling order is the `position` column; closure_tree renumbers it, but reordering ("type a new position number" -- there is no drag-and-drop) is implemented on top of that in `remember_requested_position`/`place_among_siblings` because closure_tree's own renumbering doesn't do what a literal "move to rank N" UI needs.

Each page's public URL is precomputed and cached: `pages.cached_paths` is a jsonb `{locale => path}` map, recomputed recursively (`recompute_cached_paths` → `write_cached_paths`) whenever a page saves, since a slug change on an ancestor shifts every descendant's URL. The public router (`PagesController#show`) does a single indexed lookup against this column via `Page.find_by_full_path` rather than walking the tree per-request. Read the extensive comments in `page.rb` before changing any of this -- the two-pages-one-URL and nil-position footguns it guards against are non-obvious and previously shipped as bugs (see commit `da80c58`).

### Content blocks

`ContentBlock` (`app/models/content_block.rb`) is one polymorphic-by-enum table (`block_type`: `rich_text` / `image` / `post_list`) belonging to a `Page`, ordered by `position`, edited via nested attributes inside the page form in CS Studio. `Post` uses the same single-model-plus-enum shape for its own `content_type` (`blog` / `resume_entry` / `now_update`). A `post_list` block's `settings` jsonb names a `content_type` filter, a `tag`, and a `limit`; `listed_posts` is the canonical query both the listing partial and the permalink-resolution fallback in `PagesController` must agree on.

### Public routing

Routes: `config/routes.rb`. Two catch-all routes, declared last (named routes like `/cs-studio`, `/session`, `/up` must win first): `get ":locale(/*path)"` for an explicit locale prefix (`/de/about`), and `root`/`get "*path"` for no prefix at all (served in `SiteSetting#default_locale`, editable in CS Studio's Settings module, checked per request — not a code-level default). `PagesController#redirect_default_locale_prefix` 302s an explicit prefix that happens to name the *current* default locale to the unprefixed URL, so each page has exactly one canonical address even though the default can change at runtime. `PagesController#show` first tries an exact `Page` match by cached path; if none, it treats the URL as "a listing page's path + a post slug" and resolves a `Post` permalink instead — posts have no page-tree node of their own. `PagesHelper#page_url_path`/`#post_url_path` and `config/sitemap.rb` both mirror the same default-locale-omits-prefix rule when building links — grep for `default_locale` if changing how locales map to URLs. Read the routes.rb comments before touching `format: false` or the locale constraint; there's a documented history of a 500-vs-404 regression here.

### Admin (CS Studio)

Our own admin, mounted at `ContentSpiel::ADMIN_PATH` (`config/initializers/admin_path.rb`, default `cs-studio`, configurable via `ADMIN_PATH`, one URL segment, can't be a reserved path), behind the same session-based auth as the rest of the app (no separate admin auth). Controllers live under `app/controllers/admin/` (`Admin::BaseController` and per-module controllers: `PagesController`, `PostsController`, `ContentBlocksController`, `TagsController`, `SettingsController`, `LanguagesController`, `UsersController`, `ApiTokensController`, `SystemStatusController`, `MindGraphController`, `LinkTargetsController`, `MediaAssetsController`, `StarterContentsController`, `TreeController`). Every write goes through a service object (`app/services/`, e.g. `Pages::Save`, `ApiTokens::Issue`), never straight from a controller — see individual services' own comments for authorization and audit-event conventions. Views use autosave (`admin--autosave` Stimulus controller, `Admin::AutosaveResponses#autosave_stream`) rather than a submit button for most edits.

### i18n / Mobility

Translated attributes (`Page#title/slug/subtitle/meta_title/meta_description`, `Post#title/slug/excerpt`, `ContentBlock#caption`) are plain jsonb columns via the Mobility `:jsonb` backend (`config/initializers/mobility.rb`); rich text (`Post#body`, `ContentBlock#body` — pages have none) is the same jsonb backend, one Tiptap/ProseMirror JSON document per locale, via `HasRichTextBody` (see "Rich text" below), not ActionText. Available/default locales are set once in `config/application.rb` (`config.i18n.available_locales`), not in the Mobility initializer, because Mobility needs it at load time to define per-locale accessors. Falls back to `:en` everywhere. Because translated columns are jsonb, `where(slug: ...)` on them is a bug (comparing jsonb to a string) — use Mobility's `.i18n` scope, as the slug-uniqueness validations on `Page`/`Post` do.

### Auth

Custom session-based auth (`app/controllers/concerns/authentication.rb`), not Devise — `has_secure_password` on `User`, signed cookie holds a `Session` id, `Current.session`/`Current.user` per-request. `ApplicationController` requires authentication by default; `PagesController` (the public site) opts out with `allow_unauthenticated_access`. `ApiToken` is a separate `has_secure_password`-backed token model (hashed, revocable) for non-session API access.

### Rich text

`Post#body`/`ContentBlock#body` (via `HasRichTextBody`, `app/models/concerns/has_rich_text_body.rb`) store a Tiptap/ProseMirror JSON document per locale, read back as a `RichText::Document` value object (`app/models/rich_text/document.rb`) and written through `#assign_body` rather than the raw Mobility accessor. Node/mark types (built-ins: `doc paragraph heading bulletList orderedList listItem blockquote codeBlock horizontalRule hardBreak text youtube image` / `bold italic strike code link internalLink`) are declared in the `RichText::Schema` registry (`app/models/rich_text/schema.rb`, `built_ins.rb`) — the plugin seam: plugins register prefixed `owner/name` types, duplicates raise. `Document#validate` checks types/attributes are registered and allowed and that referenced records (internal links, image `MediaAsset`s) exist; existence checks only block references that are new relative to the locale's *stored* document, so a pre-existing dead reference never blocks an unrelated edit, and validation only re-runs on the locales that actually changed in a given save. `#to_html`/`#to_markdown`/`.from_markdown` convert to/from rendered HTML (via `RichText::HtmlRenderer`, always scrubbed by `RichTextScrubber`) and CommonMark (via `RichText::Markdown`, backed by `commonmarker`); the render cache key (`Rails.cache.fetch`) is `["rich_text", digest, RichText::Schema.version, locale, preview, PublicSite.current_content_version]` — `content_version` is memoised per request on `Current` and bumps whenever anything publishing/renaming/deleting a link or asset target could invalidate a cached render, since a document's own digest only covers the document, not the world its links and images resolve against.

MCP (`create_post`/`update_post`/`get_post`) exchanges `body` as Markdown: standard nodes are CommonMark, custom nodes are directives (`::youtube{id="…"}`, `::image{asset="42" alt="…" caption="…"}`) on their own line, and internal links are `[text](cs:page/42)` / `[text](cs:post/7)`. Unknown directives are kept as text and reported as warnings, never a hard failure.

The Tiptap editor is vendored under `vendor/javascript` via import maps (`config/importmap.rb`) — no npm, no CDN at runtime. Its pins are `preload: false` (they'd otherwise modulepreload on every page, public ones included); admin controllers are lazy-loaded so the editor's own JS only loads inside CS Studio. Re-pinning Tiptap (`bin/importmap pin @tiptap/core @tiptap/starter-kit @tiptap/extension-link ...`) undoes those two manual edits — re-add `preload: false` to the new/changed pins and re-check the lazy-load list in `app/javascript/controllers/index.js` afterwards.

`bin/rails rich_text:migrate_from_action_text` (`lib/tasks/rich_text.rake`) converts existing ActionText/Trix HTML into `RichText::Document`s via `RichText::HtmlImport`; it never aborts partway and reports unmapped fragments. The ActionText tables are dropped by a later, guarded migration (`db/migrate/20260928040000_drop_action_text.rb`) that refuses to run while unimported rows remain, unless `FORCE_DROP_ACTION_TEXT=1` overrides the guard.

### SEO / sitemap

`config/sitemap.rb` (gem `sitemap_generator`) walks the published page tree across all locales; built via `rake sitemap:create`, output to `public/sitemap.xml`.

## Key Conventions

- **No RSpec** — Minitest + fixtures (`test/fixtures/`), not factories.
- **No Devise / no ActiveAdmin** — auth and admin (CS Studio) are both hand-rolled as described above; don't reach for those gems' idioms.
- **No npm/webpack** — JS is import-maps only (`importmap-rails`); CSS is Tailwind via `tailwindcss-rails` (`bin/rails tailwindcss:watch` in dev).
- **Long, load-bearing code comments are the norm in this codebase**, especially in `page.rb`, `content_block.rb`, `post.rb`, and `routes.rb` — they document non-obvious invariants and past incidents (e.g. the Accept-header 500, the two-pages-one-URL collision). Read them before changing the code they annotate, and match that density when adding similarly non-obvious logic; don't strip them out during cleanup.
- **Design docs**: `docs/superpowers/specs/` and `docs/superpowers/plans/` hold the original design specs and implementation plans this app was built from — useful background when a change touches the page tree or content blocks.
