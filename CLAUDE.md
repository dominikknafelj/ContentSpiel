# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

ContentSpiel is a Rails 8.1 CMS: a page-tree-driven public website plus an Avo-powered admin. Content editors build pages out of ordered content blocks (rich text, images, post listings), organize them in a tree, and the same tree drives navigation, routing, and the sitemap. Everything is translated into three locales (en/de/es) via Mobility.

## Setup & Commands

```sh
docker compose up -d          # Postgres 17, published on host port 5433 -- start this first
bin/setup --skip-server       # installs gems, prepares dev + test databases
bin/rails db:seed             # creates a development admin account (dev only, see db/seeds.rb)
bin/rails server               # or `bin/dev`, which runs server + `tailwindcss:watch` (see Procfile.dev)
```

- App: http://localhost:3000
- Sign in: http://localhost:3000/session/new
- Admin (Avo, behind the same sign-in): http://localhost:3000/avo

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

`ContentBlock` (`app/models/content_block.rb`) is one polymorphic-by-enum table (`block_type`: `rich_text` / `image` / `post_list`) belonging to a `Page`, ordered by `position`, edited via nested attributes inside the page form in Avo. `Post` uses the same single-model-plus-enum shape for its own `content_type` (`blog` / `resume_entry` / `now_update`). A `post_list` block's `settings` jsonb names a `content_type` filter, a `tag`, and a `limit`; `listed_posts` is the canonical query both the listing partial and the permalink-resolution fallback in `PagesController` must agree on.

### Public routing

Routes: `config/routes.rb`. Two catch-all routes, declared last (named routes like `/avo`, `/session`, `/up` must win first): `get ":locale(/*path)"` for an explicit locale prefix (`/de/about`), and `root`/`get "*path"` for no prefix at all (served in `SiteSetting#default_locale`, editable in Avo, checked per request — not a code-level default). `PagesController#redirect_default_locale_prefix` 302s an explicit prefix that happens to name the *current* default locale to the unprefixed URL, so each page has exactly one canonical address even though the default can change at runtime. `PagesController#show` first tries an exact `Page` match by cached path; if none, it treats the URL as "a listing page's path + a post slug" and resolves a `Post` permalink instead — posts have no page-tree node of their own. `PagesHelper#page_url_path`/`#post_url_path` and `config/sitemap.rb` both mirror the same default-locale-omits-prefix rule when building links — grep for `default_locale` if changing how locales map to URLs. Read the routes.rb comments before touching `format: false` or the locale constraint; there's a documented history of a 500-vs-404 regression here.

### Admin (Avo)

Mounted at `/avo` (`mount_avo` in routes), behind the same session-based auth as the rest of the app (no separate Avo auth). Resources live in `app/avo/resources/*.rb` (Page, Post, ContentBlock, Tag, SiteSetting, User, ApiToken); a custom resource tool (`app/avo/resource_tools/nested_content_blocks.rb`) renders the nested content-block editor inside the page form. `Avo::*Controller`s under `app/controllers/avo/` are thin wrappers Avo generates around these resources.

### i18n / Mobility

Translated attributes (`Page#title/slug/subtitle/meta_title/meta_description`, `Post#title/slug/excerpt`, `ContentBlock#caption`) are plain jsonb columns via the Mobility `:jsonb` backend (`config/initializers/mobility.rb`); rich text (`Page`/`Post`/`ContentBlock#body`) uses `mobility-actiontext` since ActionText needs its own table. Available/default locales are set once in `config/application.rb` (`config.i18n.available_locales`), not in the Mobility initializer, because Mobility needs it at load time to define per-locale accessors. Falls back to `:en` everywhere. Because translated columns are jsonb, `where(slug: ...)` on them is a bug (comparing jsonb to a string) — use Mobility's `.i18n` scope, as the slug-uniqueness validations on `Page`/`Post` do.

### Auth

Custom session-based auth (`app/controllers/concerns/authentication.rb`), not Devise — `has_secure_password` on `User`, signed cookie holds a `Session` id, `Current.session`/`Current.user` per-request. `ApplicationController` requires authentication by default; `PagesController` (the public site) opts out with `allow_unauthenticated_access`. `ApiToken` is a separate `has_secure_password`-backed token model (hashed, revocable) for non-session API access.

### SEO / sitemap

`config/sitemap.rb` (gem `sitemap_generator`) walks the published page tree across all locales; built via `rake sitemap:create`, output to `public/sitemap.xml`.

## Key Conventions

- **No RSpec** — Minitest + fixtures (`test/fixtures/`), not factories.
- **No Devise / no ActiveAdmin** — auth and admin are both hand-rolled/Avo as described above; don't reach for those gems' idioms.
- **No npm/webpack** — JS is import-maps only (`importmap-rails`); CSS is Tailwind via `tailwindcss-rails` (`bin/rails tailwindcss:watch` in dev).
- **Long, load-bearing code comments are the norm in this codebase**, especially in `page.rb`, `content_block.rb`, `post.rb`, and `routes.rb` — they document non-obvious invariants and past incidents (e.g. the Accept-header 500, the two-pages-one-URL collision). Read them before changing the code they annotate, and match that density when adding similarly non-obvious logic; don't strip them out during cleanup.
- **Design docs**: `docs/superpowers/specs/` and `docs/superpowers/plans/` hold the original design specs and implementation plans this app was built from — useful background when a change touches the page tree or content blocks.
