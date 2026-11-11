# The whole backend under ADMIN_PATH: design

Status: draft for the owner's approval, 2026-11-12.
Builds on: `docs/superpowers/specs/2026-11-10-studio-sign-in-design.md` (sign-in on the open internet). Roadmap: the Action Mailbox removal is the "Remove leftovers" row of `docs/roadmap.md`.

## Why

CS Studio lives under one configurable segment, `ContentSpiel::ADMIN_PATH` (`config/initializers/admin_path.rb`, default `cs-studio`), so a site can put one guard in front of it: Cloudflare Access, a WAF rule, a rate limit. Four parts of the backend still sit outside it: the preview (`/preview`, `/preview/:locale`), the setup wizard (`/setup`, `/setup/:step`), the MCP endpoint (`POST /mcp`) and Action Cable (`/cable`, Rails' default mount). A guard on `/cs-studio` leaves them open. Fifteen Action Mailbox routes are drawn too (the ingresses and, in production as well, the conductor under `/rails/conductor/action_mailbox/`), for an engine nothing uses.

The owner (2026-11-11): "we want to move everything related to cs-studio behind that path"; "the mcp is not used so far". The backend should be hidden from the public.

Some organisations go further and put the backend behind a DMZ, where the public internet cannot reach it at all. A path prefix is not enough for them, so the spec also covers an optional second host (see "Behind a DMZ").

## Goals

1. **One prefix is the whole backend.** Every route a person or a client of CS Studio uses answers under `/<ADMIN_PATH>/`, and nothing else does. The only routes outside it are the public site's.
2. **A test holds it.** A new route outside the prefix fails a guard unless it is on a public list, and each entry on that list gives its reason.
3. **Optionally, a host of its own.** With `ADMIN_HOST` set, the backend answers only on that host and the public site does not answer on it.
4. **Less surface.** Action Mailbox is gone, and Active Storage's two write endpoints answer nobody.

## Non-goals

- **Aliases or redirects from the old addresses.** CLAUDE.md: no compatibility code. `/preview/...`, `/setup` and `/mcp` become ordinary public page paths and answer 404 unless a page has that slug.
- **Moving Active Storage's reads.** Public pages embed `/rails/active_storage/...`, so they stay public. The existing allow-list (`ActiveStoragePublicFiles` and its siblings) still decides what they serve.
- **A public-only deployment role.** That is a later, separate step ("Behind a DMZ", part 3).
- **Hiding the admin path from someone who already knows it.** The prefix decides where a guard is drawn. It is not a secret. `robots.txt` stays as it is and does not name the path.

## Decided by the owner

- Everything that belongs to CS Studio moves under `ADMIN_PATH`. This includes `/mcp`, which no client uses yet. It still goes under `### Breaking` in `CHANGELOG.md`, because a gem or an integrator may have written the address down.
- No alias for any old address.
- Organisations with a DMZ get an optional `ADMIN_HOST`. A public-only role is named here but built later.

## The design

### 1. What moves

| Today | After | Where |
|---|---|---|
| `GET /preview(/*path)`, `GET /preview/:locale(/*path)` | `/<ADMIN_PATH>/preview/...` | `config/routes.rb`; the prefix in `PublicSite::Urls#prefix` (`"/preview#{code_prefix}"`, written out literally) |
| `GET /setup`, `GET`/`PATCH /setup/:step` | `/<ADMIN_PATH>/setup/...` | routes; `Setup::RedirectConstraint` (target and `EXEMPT_PREFIXES`); `Setup::Token.log_line` ("Open /setup"); `lib/site_template/README.md.tt` and `config/deploy.yml.tt` |
| `POST /mcp` | `POST /<ADMIN_PATH>/mcp` | routes; `Admin::ApiTokensController#mcp_url` (a literal `"/mcp"`, which becomes the route helper); `app/views/setup/mcp_token.html.erb` (a literal `/mcp`); `config/initializers/rack_attack.rb` (`req.path == "/mcp"`); the `EXEMPT_PREFIXES` entry |
| Action Cable `/cable` | `/<ADMIN_PATH>/cable` | `config.action_cable.mount_path`, plus `action_cable_meta_tag` in the layouts that load `live/connection.js`. turbo-rails' consumer reads `<meta name="action-cable-url">` and falls back to `/cable`, so without the tag the script keeps asking the old address. |

The three route groups go in a second plain `scope ContentSpiel::ADMIN_PATH do … end` (no `module:`, no `as:`), declared right after the admin scope and before the public catch-alls. Their controllers (`PreviewController`, `SetupController`, `McpController`) and route helper names (`preview_path`, `localized_preview_path`, `setup_path`, `setup_step_path`, `mcp_path`) stay as they are, so the paths move and every caller of a helper follows without change. Every caller that writes a path out literally is listed in the table above. The builder greps once more for any it missed.

The setup catch-alls at the top of `routes.rb` redirect to `setup_path`'s new address. `EXEMPT_PREFIXES` becomes `/<ADMIN_PATH>/setup`, `/<ADMIN_PATH>/mcp`, the three sign-in prefixes, `/up` and `/rails/active_storage`.

`RESERVED_PATHS` loses `preview`, `setup`, `mcp` and `cable`, which are no longer first segments that another route claims. `test/integration/admin/shell_test.rb` and `note_signals_test.rb` follow, and the boot-refusal test uses a remaining reserved word (`up`). As a side effect, a top-level page slugged `preview`, `setup` or `mcp` used to be hidden silently behind those routes and is now reachable.

### 2. What is removed

- **Action Mailbox.** Delete `require "action_mailbox/engine"` from `config/application.rb`. No code, schema table, config or test refers to it (checked: the only mentions are `Gemfile.lock` through `rails`, the roadmap row and the staff review). Removing it takes away its 15 routes, the production conductor among them. The roadmap row's Action Mailbox part is done.
- **Active Storage's two write endpoints answer 404 to everyone** (see "My calls"). These are `POST /rails/active_storage/direct_uploads` and `PUT /rails/active_storage/disk/:encoded_token`. `ActiveStorageWriteAuthentication` becomes a refusal that a session does not open. The routes stay drawn, because `draw_routes = false` would also remove `rails_blob_path` and the other `direct` routes (the reason recorded in `config/initializers/active_storage_access.rb`). `test/integration/active_storage_access_test.rb` changes from "signed out is 401" to "signed in is 404 too".

### 3. What stays public, by design

The pages (`root`, `localized_page`, `page`), the visitor's form send (`POST /forms/:form_id`), Active Storage's reads, the health check `/up`, and the two setup-required redirects (they only send a request to the wizard). Turbo's three historical-location routes (`/recede_…`, `/resume_…`, `/refresh_…`) need a correction to the brief: turbo-rails draws them after `routes.rb`, so the `*path` catch-all takes them first and they are never reached. They go on the list with that reason. If the installed turbo-rails can switch them off, the builder does that instead.

### 4. The guard: `test/lib/backend_paths_test.rb`

It is modelled on `test/lib/component_screens_test.rb`. It reads `Rails.application.routes.routes`, including `internal` routes. The cable mount is drawn `internal: true` and `bin/rails routes` hides it, so a guard that skipped internal routes would miss `/cable`. For each route it takes the path spec (`route.path.spec.to_s`). A route passes if the spec starts with `/#{ADMIN_PATH}/` or equals `/#{ADMIN_PATH}`. Every other route must match an entry of `PUBLIC`, a hash of path spec and verb to the reason, as in section 3.

- "the guard is looking at the routes": run against a `RouteSet` drawn in the test with a `post "export"` at the top level, the check names it. This is the can-fail sample.
- "every route outside ADMIN_PATH is on the public list, with its reason"
- "the public list names only routes that exist": a stale entry fails.
- With `ADMIN_HOST` set: the host tests in "Behind a DMZ", part 4.

What it cannot see: routes drawn only in development (`/lookbook`, `/rails/info`, `/rails/mailers`) are not drawn in the test environment. That gap goes into `docs/reference/hosting.md`'s "Rules a change can break silently" as a rule with **no guard**.

### 5. Behind a DMZ: `ADMIN_HOST`

**1. The variable.** `ADMIN_HOST` is optional and written with its scheme, like `PUBLIC_HOST` (`https://studio.example.internal`). It is read in one place, `SiteAddress` (a second instance, `SiteAddress.admin`, or a `VARIABLES` entry of its own: the builder's choice) and nowhere else, as `PUBLIC_HOST` is. When it is unset, everything behaves as after sections 1 to 4: one host serves both. When it is set:

- **Routes.** Every route under `ADMIN_PATH` (sign-in, the screens, preview, setup, MCP, cable) is drawn inside `constraints(host: admin_host)`, and the public routes (pages, the form send, the setup-required redirects) inside a constraint for the public host. A request on the wrong host falls through to a 404 and never to a redirect, so the public host says nothing about where the backend lives. `/up` answers on both hosts, because each box's health check asks its own. Active Storage's reads answer on both: the editor draws library images through them, and a public page embeds them. Its writes answer nobody (section 2), so they need no host.
- **Host authorization.** `HostSettings.apply` adds the admin host to `config.hosts`.
- **The session cookie** is written with no `domain:`, so it is a host-only cookie of the admin host and the browser never sends it to the public host. Today's cookie is also host-only; the difference is that sign-in now happens on the admin host. The same holds for `cs_known_device` and the CSRF session. No change is needed beyond signing in on the admin host. The builder checks that no cookie is given a `domain:`, because a parent-domain cookie would reach both hosts.
- **CSRF and origin.** Rails' `forgery_protection_origin_check` compares `Origin` with the request's own base URL, so a form on the admin host posting to the admin host passes unchanged. The public form send takes no token (`Cookieless`) and does not change.
- **Action Cable.** `config.action_cable.allowed_request_origins` is set to the admin origin. Rails' default only allows same-origin in development. In production an unset list refuses every origin unless `disable_request_forgery_protection` is set, so the list must name it.
- **Mailed links.** The reset and invitation links, and every other mailed link into CS Studio (a form's submission mail, a note mail, the lock-out mail), are built with the admin host's URL options. Mail that points a reader to the public site keeps `PUBLIC_HOST`. `HostSettings` keeps `action_mailer.default_url_options` on the public host, and the mailers that link into CS Studio take the admin options explicitly. The builder lists them; `test/lib/mail_guards_test.rb` is the place to hold them.
- **Preview links.** The preview is served on the admin host, and `PublicSite::Urls` with `preview: true` builds its addresses on the request's own origin, as it does today (`docs/reference/hosting.md`, "Addresses a public page prints"). The editor's "View" and "Open preview" links use the route helpers and follow automatically. The "View live" link to a published page goes to `PUBLIC_HOST`.
- **CSP.** The admin layouts' `connect-src` names the admin origin's `wss:` (or `ws:` in development) for the cable. The public site's policy does not change.
- **Proxy and Cloudflare.** `TRUSTED_PROXIES` and the visitor-address rules apply on both hosts. Behind Cloudflare, the admin hostname is either not proxied at all (it resolves only inside the network) or is its own Access application. The System status "Site address" check gains a row for the admin address.

**2. The edge rule this enables.** The public hostname serves only public paths. Its proxy or WAF can refuse `/<ADMIN_PATH>/*` outright, and even without that rule the app answers 404 there. The admin hostname resolves only inside the network (split DNS, or a load balancer listening only on the internal interface). The same image and the same database serve both.

**3. Later, separately: a public-only role.** Some organisations want no admin code reachable from the DMZ at all, not just unanswered. That needs a process role (for example `CONTENTSPIEL_ROLE=public`) in which:

- the admin routes, cable, MCP and setup are not drawn;
- the database user can only read;
- pages are served from the published copies (`docs/reference/publishing.md`) with no write path. This rules out the form send, so forms would deliver through the admin side or a queue.
- jobs, the presence and editing sweeps and the trash purge run only on the admin box;
- `public_paths` and the render cache stay correct with no writer in that process.

It is not in this spec.

**4. Guard tests.** `test/integration/admin_host_test.rb`. Under a helper `with_admin_address` (the counterpart of `with_site_address`, the only way a test sets it), these hold for every route under `ADMIN_PATH` (taken from the route set, one sample request per route) and every public route:

- each backend route answers 404 on the public host;
- each public route answers 404 on the admin host;
- `/up` answers on both;
- a reset mail's link names the admin host;
- the session cookie has no `Domain` attribute.

Without the variable, the same requests answer on the one host. The route-set test in section 4 asserts that every `ADMIN_PATH` route carries the host constraint when `ADMIN_HOST` is set, so a new route outside the constraint fails.

## My calls (marked so the owner can check them)

1. **A second plain scope, not the admin scope.** Preview, setup and MCP move under `ADMIN_PATH` without `module: :admin` or `as: :admin`, so their controllers and route helper names stay the same and only the path changes. Folding them into `Admin::` would rename three controllers and every helper call for no gain.
2. **Active Storage writes answer 404 to everyone, not only to the signed out.** Nothing calls them (every upload goes through a CS Studio controller that checks the file), and a signed-in session that can create orphan blobs is surface with no use. They stay drawn only because the read helpers share their file.
3. **`RESERVED_PATHS` drops `preview`, `setup`, `mcp`, `cable`.** No compatibility code, and they no longer collide with anything.
4. **MCP behind Cloudflare Access** needs an Access service token (`CF-Access-Client-Id` and `CF-Access-Client-Secret` on the client) or a Service Auth policy on `/<ADMIN_PATH>/mcp`. An MCP client cannot complete Access's interactive login. `docs/reference/hosting.md` says so beside "Access on ADMIN_PATH alone", and an invitee also needs an Access policy that admits them before their link works.
5. **The Turbo historical-location routes are listed as unreachable, not as public.** The brief listed them as public by design. The code shows the catch-all shadows them.
6. **`ADMIN_HOST` is read by `SiteAddress`** as `PUBLIC_HOST` is, with the same rule that it has one reader and that tests set it through a helper only.
7. **On the wrong host, 404 and never a redirect.** A redirect from the public host to the admin host would reveal the hostname the DMZ hides.

## Left to the builder

- Where `config.action_cable.mount_path` is set. `config/application.rb` runs before `admin_path.rb` defines the constant, and Action Cable reads the mount path in an `after_initialize`, so the admin path's initializer is the natural place.
- Whether `SiteAddress.admin` is a second instance or a class method.
- The full list of mailers that link into CS Studio.
- A last grep for literal `/preview`, `/setup`, `/mcp` and `/cable` in `app/`, `lib/`, `test/` and `docs/reference/` (the tests found today: `preview_test.rb`, `preview_internal_link_test.rb`, `public_drafts_test.rb`, `public_head_address_test.rb`, `setup_redirect_test.rb`, `setup_access_test.rb`, `mcp_access_control_test.rb`, `urls_test.rb`, `token_test.rb`, `setup_wizard_test.rb`, `system_status_and_preview_test.rb` and the static guards in `test/lib/` that name the paths).
- Docs: `docs/reference/hosting.md` (the variable tables with `ADMIN_HOST`; the setup token's line; "Sign-in on the open internet": Access on `ADMIN_PATH` alone now covers the whole backend, plus the MCP note; a new "Behind a DMZ" part); `docs/reference/page-tree-and-routing.md`, `rich-text.md`, `publishing.md` and the other reference files that name `/preview`; `users-groups-tokens.md` and `rich-text.md` for the MCP address; `CLAUDE.md`'s lines naming `/preview`, `/setup` and `/mcp`.

## How it ships

- **After sign-in PR 3 (passkeys, branch `passkeys`) merges**, because that branch changes `config/routes.rb` and `app/controllers/concerns/authentication.rb`. **Before OIDC (PR 4)**, whose callback then starts under `ADMIN_PATH` from the beginning.
- **Two pull requests.** The first carries sections 1 to 4 (the move, the removals, the guard). The second carries `ADMIN_HOST` (section 5, parts 1, 2 and 4). It can follow straight after or wait for the first organisation that asks. The public-only role is a project of its own.
- `CHANGELOG.md`, `## Unreleased`:
  - `### Breaking`: the MCP address is now `/<ADMIN_PATH>/mcp`; preview addresses are under `/<ADMIN_PATH>/preview`; the setup wizard is at `/<ADMIN_PATH>/setup`; the cable is at `/<ADMIN_PATH>/cable`.
  - `### Removed`: Action Mailbox and its routes; Active Storage's direct uploads.
  - `### Added` (second PR): `ADMIN_HOST`.
- **Documentation** (the guide, `contentspiel-docs`): the install and setup wizard pages (the setup address), API tokens and the AI assistant (the MCP address, and the Access service token), and hosting and Cloudflare (Access on `ADMIN_PATH` alone; and, with the second PR, a "Behind a DMZ" page).
