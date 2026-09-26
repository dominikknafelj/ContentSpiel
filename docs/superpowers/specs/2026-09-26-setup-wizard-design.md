# Setup Wizard & Design Tokens — Design

Supersedes [§11 "Setup wizard"](2026-09-13-contentspiel-design.md#11-setup-wizard)
of the original design spec. Everything else in that spec still stands.

## 1. Context and goals

A fresh ContentSpiel install should go from an empty database to a working
public site plus an admin login **entirely in the browser** — no `db:seed`,
no Rails console. ContentSpiel is a generic CMS other people deploy, so the
flow must be safe on a publicly reachable server and keep every
non-essential step skippable.

§11 as originally written has three gaps this design closes:

- **Takeover window.** "Reachable while `User.none?`" means whoever reaches
  `/setup` first becomes admin.
- **Locks itself out.** Creating the admin (step 1) makes `User.none?`
  false, so the remaining steps would become unreachable.
- **No homepage.** The public site is driven by the page tree (built after
  §11 was written); with no root `Page`, `/` is a 404 even after setup.

Visual design comes from the Claude Design project "Content Spiel design
system" (https://claude.ai/design/p/dd6bda29-ca72-4e73-8a55-de40f9a18257):
`content-spiel.css` / `content-spiel.tailwind.css` (tokens, light + dark),
`Setup Wizard.dc.html`, `Backend.dc.html`, `Demo Site.dc.html`.

### Theme boundary

The Claude Design look splits into two things with different lifetimes:

- **Product UI** — setup wizard, sign-in/password screens, Avo branding. Owned
  by ContentSpiel, identical on every install, styled with the product
  tokens.
- **Public site** — the Claude Design demo site is only the **initial demo
  (default) theme**. Real integrations must be able to use their own
  templates and/or themes. Nothing in this work may couple public views to
  the demo theme's tokens in a way that a future theme/template mechanism
  couldn't replace. (That mechanism itself is out of scope — §7.)

## 2. Design tokens foundation (PR 1, merged first)

- Add Claude Design's `content-spiel.tailwind.css` under
  `app/assets/tailwind/` and import it from `application.css`. Its
  `@theme inline` block maps every token to a CSS variable, so utilities like
  `bg-surface` / `text-meta` follow the active theme.
- **Light/dark:** `data-theme="light|dark"` on `<html>`. Default follows
  `prefers-color-scheme`; a small Stimulus controller toggles and stores an
  explicit choice in `localStorage` (wrapped in try/catch — it's a per-viewer
  convenience, and must render correctly without it). An inline script in
  `<head>` applies the stored choice before first paint to avoid a flash.
- **No restyle in this PR.** Existing public and auth views keep their
  current markup; the tokens only become available. Restyling the
  sign-in/password screens (product UI) and the Avo theme are follow-ups;
  the public demo theme is a separate follow-up that must respect the theme
  boundary above.

## 3. Access control and setup state (PR 2)

### Setup state

New column `site_settings.setup_completed_at` (datetime, null). Setup is
**required** until it's set. The migration backfills it to `now` wherever
`User.exists?` — existing installs (including every current dev database)
are never redirected into the wizard. `db/seeds.rb` sets it too.

`Setup.required?` is the single predicate everything uses.

### Setup token

- Default: derived, not stored — an HMAC of a fixed purpose string using
  `Rails.application.key_generator` (i.e. from `secret_key_base`), as the
  first 24 hex characters (the admin copies it from the log). Stable across restarts and across Puma workers,
  no storage needed. Anyone who holds `secret_key_base` already owns the app.
- `SETUP_TOKEN` env var overrides it.
- While `Setup.required?`, printed to the log at boot (an
  `after_initialize` hook that tolerates the database not being reachable
  yet, e.g. during `assets:precompile`).
- Compared with `ActiveSupport::SecurityUtils.secure_compare`; on success
  `session[:setup_token_verified] = true`.

### Who can reach `/setup`

| State | Access |
|---|---|
| No `User` exists | Anyone who has entered the setup token (this session) |
| Admin exists, setup not completed | Only a signed-in user (sign in → back into the wizard) |
| `setup_completed_at` set | `/setup` returns 404 |

### Redirect while setup is required

A route constraint at the **top** of `config/routes.rb` sends every HTML
request to `/setup` while `Setup.required?`. It lives in routes (not a
`before_action`) so it also covers the mounted Avo engine, whose controllers
don't inherit from `ApplicationController`.

Exempt: `/setup/*`, `/session/*` and `/passwords/*` (so an admin can sign in
and resume), `/up` (health check), `/mcp` (has its own auth and no tokens
exist yet anyway), and Active Storage (logo preview during setup).

## 4. Wizard steps and data flow (PR 2)

`SetupController`, `GET`/`PATCH /setup/:step`, own layout
`layouts/setup.html.erb` built on the product tokens. A progress list shows
every step; optional steps have a **Skip** link. Each step persists
immediately, so closing the browser mid-way is resumable (sign in → wizard).

| # | Step | Required | Behaviour |
|---|---|---|---|
| 1 | Setup token | yes* | Verify token (above). *Skipped automatically once an admin exists and is signed in. |
| 2 | System check | optional | Read-only `Setup::SystemCheck`, "Re-run" + "Continue". **Never blocks** — failures are warnings. |
| 3 | Admin account | yes | Email + password + confirmation → `User` → signed in via the existing `start_new_session_for`. |
| 4 | Site identity | yes | Title, tagline, logo, social links → `SiteSetting`. |
| 5 | Languages | yes (preselected) | Choose the default from the configured locales. List is read-only for now (`en`/`de`/`es`); laid out so add/remove can follow (§7). |
| 6 | MCP token | optional | "Generate" → `ApiToken.generate!(current_user)`; the raw value is rendered once in that response, never put in session or flash. |
| 7 | Starter content | optional | `StarterContent.create_pages_and_posts!` — Blog, Resume, Now pages (each with a `post_list` block) + one sample post per content type, in the chosen default locale. |
| 8 | Review | — | Summary with edit links. **Finish** → in one transaction: `StarterContent.ensure_home!` (root "Home" page + welcome rich-text block) and set `setup_completed_at`; redirect to Avo. |

### System check (`Setup::SystemCheck`)

Each check returns `ok` or `warning` plus a message and, for warnings, what
won't work and how to fix it.

| Check | How | Warning means |
|---|---|---|
| File storage | Upload, read back, and delete a small blob through the Active Storage service | Logo and image uploads will fail (shown prominently, still not blocking) |
| Image processing | Resize a tiny in-memory image through `image_processing`/vips | Image variants and logo resizing will fail |
| Background jobs | A Solid Queue process heartbeat within the last few minutes | Queued work (Active Storage analysis, mail) never runs — mention `SOLID_QUEUE_IN_PUMA` or a separate jobs process |
| Outgoing mail | Delivery method/SMTP configured and a real `default_url_options` host | Password reset by email won't work; fallback: `bin/rails console` → `User.find_by(email_address: …).update!(password: …)` |

No database check: if the wizard renders, the database works, and
migrations run in `bin/docker-entrypoint` (`db:prepare`).

### `StarterContent`

Extracted from the page/post-building logic in `db/seeds.rb` (which can then
reuse it). Every method is idempotent — finds existing records by
Mobility's `.i18n` scope before creating, the same way seeds do today.

## 5. Backend settings (PR 2)

Everything the wizard sets stays editable afterwards in Avo:

| Wizard step | Avo today | Change |
|---|---|---|
| Site identity | Site settings resource | `social_links` becomes a `:key_value` field instead of raw JSON (`:code`); the Settings sidebar entry opens the singleton's edit form directly instead of a one-row index (`Avo::SiteSettingsController#index` redirects to `SiteSetting.instance`'s edit page) |
| Languages | `default_locale` select on Site settings | none |
| MCP token | API tokens resource + "Regenerate my API token" action | none |
| Starter content | — | Standalone Avo action **"Create starter pages"** reusing `StarterContent` |
| System check | — | **"System status"** page reusing `Setup::SystemCheck`, built like the existing mind-graph tool page |

**Admin-only:** today every user is an admin, so these are admin-only by
construction. Enforcing it for non-admin users waits for roles (§7).

## 6. Error handling and testing

### Errors

- Invalid step input re-renders the step with model errors (422), matching
  the existing session forms.
- Token form: `rate_limit to: 10, within: 3.minutes` (same as sign-in).
- Admin step re-checks `User.none?` inside a transaction; if another admin
  already exists → redirect to sign-in.
- Finish and "Create starter pages" are idempotent (no second Home page).

### Tests

- **Integration:** redirect-while-required for `/`, a page path, and `/avo`;
  exemptions (`/up`, `/mcp`, sign-in); token gate (missing / wrong / right /
  rate-limited); 404 after completion; each step's success and error paths,
  including skipping optional steps; resume after sign-in.
- **Unit:** `Setup::Token` (derived vs. `SETUP_TOKEN`), each
  `Setup::SystemCheck` check (ok and warning), `StarterContent` idempotency,
  the backfill migration.
- **System (Capybara):** one full browser run through the wizard.
- **Existing suite:** add a completed `site_settings` fixture so the ~300
  existing tests aren't redirected to `/setup`; adjust `SiteSettingTest`,
  which currently assumes an empty table.
- **PR 1:** layout renders with tokens; system test for the light/dark
  toggle and its persisted choice.

## 7. Out of scope / later

- **Theme/template mechanism for the public site** (the demo design is only
  the initial default theme — see "Theme boundary").
- **Runtime-configurable languages** — define N languages in setup, add more
  later. Blocked today by `available_locales` being fixed in
  `config/application.rb` (Mobility defines per-locale accessors at load
  time); needs its own design covering Mobility, `cached_paths`, and routes.
- **Roles and permissions**, including enforcing admin-only settings. Avo's
  per-resource authorization needs the separate `avo-authorization` plugin
  (paid tier, as far as known); per-user sidebar hiding needs `avo-menu`.
  Decide plugin vs. self-enforced when this is picked up.
- **Image processing and asset management** (media library). Needed, but
  its own design. Today images are attached per record
  (`SiteSetting#logo`, `ContentBlock#image`, `Page#hero_image`) and each
  upload is a separate blob — nothing can be browsed or reused. Only
  images inside rich text get resized variants
  (`active_storage/blobs/_blob.html.erb`); content-block and hero images
  are served at original size (`content_blocks/_image.html.erb`,
  `pages/show.html.erb`). The later design should cover a reusable media
  library in Avo (the Claude Design backend already has a "Media" entry),
  responsive variants/formats for every image, and metadata such as alt
  text. The system check's image-processing check (§4) is the only
  overlap with this work.
- **Production mail configuration** (SMTP settings, real
  `default_url_options` host) — the console is the accepted fallback for
  password resets; the system check only reports it.
- Restyling the sign-in/password screens and the Avo theme with the tokens
  (follow-up PRs after PR 1).

## 8. Delivery

1. **PR 1 — Design tokens & light/dark** (§2).
2. **PR 2 — Setup wizard + backend settings** (§3–§6).
