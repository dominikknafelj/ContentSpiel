# The whole backend under ADMIN_PATH, part 2: ADMIN_HOST — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** With the optional `ADMIN_HOST` set, every route under `ADMIN_PATH` answers only on that host, the public site does not answer on it, both answer `/up` and Active Storage's reads, and the mails that link into CS Studio name the admin host; unset, nothing changes.

**Architecture:** `SiteAddress.admin` parses `ADMIN_HOST` (one reader, memoised, reset with `SiteAddress.reset!`); `HostSettings.apply` adds it to `config.hosts` and refuses a combination that cannot work. Two route constraints in one new top-level module, `HostRouteConstraint::Backend` and `HostRouteConstraint::Site`, read `SiteAddress.admin` per request (so tests switch it with `with_admin_address`, without redrawing routes) and wrap the two scopes of `routes.rb` and the public routes. `ApplicationMailer#link_origin` prefers the admin address.

**Tech Stack:** Rails 8.1 routing constraints, `lib/site_address.rb`, `lib/host_settings.rb`, Action Mailer, Minitest.

**Spec:** `docs/superpowers/specs/2026-11-12-backend-under-admin-path-design.md`, section 5 ("Behind a DMZ"), parts 1, 2 and 4; "My calls" 6 and 7; "How it ships" (second PR). Part 1 is `docs/superpowers/plans/2026-11-12-backend-under-admin-path-1-move.md` and must be merged first.

## Global Constraints

- `ADMIN_HOST` is written with its scheme, like `PUBLIC_HOST` (`https://studio.example.internal`), parsed by `SiteAddress.parse(value, source: "ADMIN_HOST")`, and read in `lib/site_address.rb` alone. A test sets it only through `with_admin_address(value)` (`test/support/site_address_helper.rb`).
- Unset or blank: behaviour is exactly part 1's (one host serves both).
- On the wrong host: 404, never a redirect (spec, "My calls" 7).
- `/up` and Active Storage's routes (`/rails/active_storage/...`) carry no host constraint.
- No cookie is given a `domain:`.
- A refusal never repeats a value (`SiteAddress`'s rule): it names the variables.
- `CHANGELOG.md`, `## Unreleased`: `### Environment`, `### Added` and `### Breaking` lines exactly as in Task 5.

## Rulings made in planning (spec gaps settled)

- **R1 — `ADMIN_HOST` requires `PUBLIC_HOST`, another host name, and the same scheme.** `HostSettings.apply` raises `SiteAddress::Invalid` otherwise, so production does not start. Reasons: `config.hosts` is only set when `PUBLIC_HOST` is (without it, adding the admin host alone would refuse the public site); the same host would make every public route a 404; `force_ssl` is one switch for the process, so an http admin host beside an https public one would be redirected to an https address it does not serve. Messages:
  - `"ADMIN_HOST needs PUBLIC_HOST: set the site's public address too."`
  - `"ADMIN_HOST must be another host name than PUBLIC_HOST's."`
  - `"ADMIN_HOST and PUBLIC_HOST must both be https, or both http."`
- **R2 — the constraints read the address per request**, not at draw time. A constraint built from `SiteAddress.admin.host` while routes load could not be switched by a test, and `LocaleRouteConstraint` already reads its setting per request. The guard then holds that every backend route carries the constraint object whatever the environment says.
- **R3 — `HostRouteConstraint::Site` is "not the admin host"**, not "the public host": with `ADMIN_HOST` unset it matches everything, and with it set `config.hosts` (R1) already refuses every name but the two. A request's host is compared case-insensitively, port ignored, as `config.hosts` compares it.
- **R4 — the setup-required redirects stay outside both host constraints.** The spec puts them with the public routes; there they would stop gating CS Studio on the admin host while setup is pending (`test/integration/admin/invariants_test.rb`: "CS Studio is gated behind /setup while setup is required"). On the public host the redirect's target is a 404, which says nothing of the admin host.
- **R5 — no `allowed_request_origins` and no CSP change.** Action Cable 8.1's `allow_same_origin_as_host` defaults to true, so the cable on the admin host accepts the admin origin and refuses any other already (the spec's "refuses every origin" holds only with that switch off), and the policy in `config/initializers/content_security_policy.rb` sets neither `connect-src` nor `default-src`, so it does not restrict the socket. Task 3 pins both facts so a later change that alters them fails here.
- **R6 — one new top-level name, `HostRouteConstraint`** (`app/constraints/host_route_constraint.rb`), is named under `### Breaking` (CLAUDE.md: a new top-level name refuses a gem's hook owner of that name).
- **R7 — the mails that link into CS Studio are the three built on `link_origin`**: `PasswordsMailer#reset_url`, `SignInMailer#reset_request_url`, `InvitesMailer#invite_url`. `FormsMailer` and `SystemMailer` link nowhere (checked at planning; Task 3's guard keeps it so).

## Review Focus

1. **A half-configured DMZ** — `ADMIN_HOST` without `PUBLIC_HOST`, equal to it, or of another scheme: production must refuse to start with a message naming the variables and never the value (Task 1 tests and production boot test).
2. **The public host asked for a backend address** — `/cs-studio/sign-in`, `/cs-studio/cable`, `/cs-studio/preview/...`, `POST /cs-studio/mcp` on the public host answer 404 with no `Location` and no admin host name anywhere in the response (Task 2 test).
3. **A mail read outside the network** — a reset, invitation or lock-out mail links to the admin host, not the public one, also in development where the link would otherwise follow the request (Task 3 test).
4. **The copy link to a published page** on the editor, served on the admin host — must name `PUBLIC_HOST`, not the admin host (Task 3 test).
5. **A Host header in capitals or with a port** on the admin host (`Studio.Example.Internal`, `studio.example.internal:443`) still reaches CS Studio (Task 2 test).

---

### Task 0: Setup

- [ ] **Step 1: Merge main.** Part 1 must have merged.

```bash
cd /Users/dknafelj/src/ContentSpiel-backend-path   # or the worktree this part runs in
git fetch origin && git merge origin/main
bin/rails db:test:prepare
```

Expected: `test/lib/backend_paths_test.rb` exists and `config/routes.rb` has the second `scope ContentSpiel::ADMIN_PATH` with preview, setup, MCP and the cable mount. If not, stop: part 1 is not in.

- [ ] **Step 2: Baseline.** `bin/rails test` — green.

---

### Task 1: `SiteAddress.admin` and `HostSettings`

**Files:**
- Modify: `lib/site_address.rb` (`def self.admin` memoised in `@admin`, `parse(ENV["ADMIN_HOST"], source: "ADMIN_HOST")`; `reset!` clears `@admin` too; class comment: the second address, read here alone)
- Modify: `lib/host_settings.rb` (`apply(config, address: SiteAddress.current, admin: SiteAddress.admin, env: ENV)`: raise per R1 before anything is set; `config.hosts = [ address.host, admin.host ].compact` when `address.configured?`; `announcement(address, env = ENV, admin: SiteAddress.admin)` adds, when admin is configured, the line `"[ContentSpiel] CS Studio is served on #{admin.origin} alone; #{address.origin} answers no CS Studio address."`)
- Modify: `test/support/site_address_helper.rb` (`VARIABLES = %w[PUBLIC_HOST ADMIN_HOST]`; add `with_admin_address(value)`, the same shape as `with_site_address`, nesting with it)
- Test: `test/lib/site_address_test.rb`, `test/lib/host_settings_test.rb`, `test/lib/production_boot_test.rb`

**Interfaces:**
- Produces: `SiteAddress.admin -> SiteAddress` (unconfigured when unset); `with_admin_address(value) { … }`; `HostSettings.apply(config, address:, admin:, env:)`.

- [ ] **Step 1: Write the failing tests.**
  - `site_address_test.rb`: "admin reads ADMIN_HOST and is memoised until reset"; "an ADMIN_HOST that is no address is refused and the message names ADMIN_HOST" (`assert_equal "ADMIN_HOST must be the site's address with its scheme, for example https://www.example.org", error.message`); "with_admin_address puts the variable and the memo back, also when the block raises".
  - `host_settings_test.rb`: "an admin address is answered beside the public one" (`config.hosts == ["docs.example.org", "studio.example.internal"]`, `action_mailer.default_url_options` still the public host's); the three R1 refusals, each asserting the exact message and that the message does not include the value; "the boot names the admin origin" (the exact line above).
  - `production_boot_test.rb`: production with `PUBLIC_HOST=https://docs.example.org` and `ADMIN_HOST=https://docs.example.org` does not start and prints `"ADMIN_HOST must be another host name than PUBLIC_HOST's."`; with `ADMIN_HOST=https://studio.example.internal` it starts and prints the admin line. Add `"ADMIN_HOST" => nil` to the variables the file clears.
- [ ] **Step 2: Run** the three files — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the three files — PASS.
- [ ] **Step 5: Commit** `feat: ADMIN_HOST, the backend's own address, read by SiteAddress`.

---

### Task 2: The host constraints and their guards

**Files:**
- Create: `app/constraints/host_route_constraint.rb` (`module HostRouteConstraint`; `module Backend; def self.matches?(request)`: true when `SiteAddress.admin` is not configured, else `request.host.casecmp?(admin.host)`; `module Site; def self.matches?(request)`: true when not configured, else not the admin host. Header comment: per request (R2), "not the admin host" (R3), 404 and never a redirect on the wrong host, and why `/up` and Active Storage carry none)
- Modify: `config/routes.rb`: wrap the admin scope and the second scope in one `constraints(HostRouteConstraint::Backend) do … end`; wrap `post "forms/:form_id"`, the two locale/page catch-alls and `root` in `constraints(HostRouteConstraint::Site) do … end` (the comments above them stay with them); leave the setup-required redirects (R4) and `get "up"` outside both, each with a line saying why
- Modify: `test/lib/backend_paths_test.rb` (the host test below)
- Create: `test/integration/admin_host_test.rb`

**Interfaces:**
- Consumes: `SiteAddress.admin`, `with_site_address`, `with_admin_address` (Task 1); `BackendPathsTest::PUBLIC`, `key(route)`, `under_prefix?(route)` (part 1).
- Produces: `HostRouteConstraint::Backend.matches?(request) -> Boolean`, `HostRouteConstraint::Site.matches?(request) -> Boolean`.

- [ ] **Step 1: Write the failing tests.**

In `backend_paths_test.rb`, add the private helper `constrained_by?(route, constraint) -> Boolean` (true when `route.app` is an `ActionDispatch::Routing::Mapper::Constraints` whose `constraints` include `constraint`), and:

```ruby
test "every route under ADMIN_PATH carries the admin host's constraint, and every public page route the site's" do
  backend = Rails.application.routes.routes.select { |route| under_prefix?(route) }
  assert_empty backend.reject { |route| constrained_by?(route, HostRouteConstraint::Backend) }.map { |route| key(route) }

  site = %w[GET\ / GET\ /:locale(/*path) GET\ /*path POST\ /forms/:form_id]
  assert_empty Rails.application.routes.routes.select { |route| site.include?(key(route)) }
    .reject { |route| constrained_by?(route, HostRouteConstraint::Site) }.map { |route| key(route) }
end

test "the host check can fail" do
  set = ActionDispatch::Routing::RouteSet.new
  set.draw { scope(ContentSpiel::ADMIN_PATH) { get "bare", to: "x#y" } }
  assert_not constrained_by?(set.routes.first, HostRouteConstraint::Backend)
end
```

`test/integration/admin_host_test.rb` (`class AdminHostTest < ActionDispatch::IntegrationTest`; setup completes setup as `preview_test.rb` does; every test inside `with_site_address("https://docs.example.org") { with_admin_address("https://studio.example.internal") { … } }`, with `host!` choosing the host):

- "every backend route is unknown on the public host": for each route under the prefix, a sample path (each `:param` → `1`, each `*glob` → `x`, optional groups dropped) and its verb; `Rails.application.routes.recognize_path("http://docs.example.org#{sample}", method: verb)` either raises `ActionController::RoutingError` or answers `controller: "pages"`. The mount (no controller) is covered by the request test below.
- "every public route is unknown on the admin host": the same for `PUBLIC`'s page and form routes against `http://studio.example.internal`; never `pages` or `form_sends`.
- "on the public host the backend answers the public 404, with no redirect": `host! "docs.example.org"`; `get "/cs-studio/sign-in"`, `get "/cs-studio/cable"`, `get "/cs-studio/preview/about"`, `post "/cs-studio/mcp"`; each `assert_response :not_found`, `assert_nil response.location`, `assert_no_match(/studio\.example\.internal/, response.body)`.
- "on the admin host a page path is a 404": `host! "studio.example.internal"`; `get "/"` and `get "/about"` (a published page) → 404.
- "the admin host is matched as config.hosts matches it": `host! "Studio.Example.Internal"`; `get "/cs-studio/sign-in"` → 200; then with `"studio.example.internal:443"` over https → 200.
- "/up answers on both hosts", and "a made width of a library image answers on both hosts" (`make_renditions!(create_media_asset)`, `get asset.srcset.first.first` on each host → 200).
- "without ADMIN_HOST one host answers both": `with_site_address("https://docs.example.org")` only; `get "/cs-studio/sign-in"` → 200 and `get "/about"` → 200 on `docs.example.org`.

- [ ] **Step 2: Run** `bin/rails test test/lib/backend_paths_test.rb test/integration/admin_host_test.rb` — FAIL.
- [ ] **Step 3: Implement** the module and the two `constraints` blocks.
- [ ] **Step 4: Run** both files, then `bin/rails test test/integration` — PASS (the integration suite runs on `www.example.com` with no `ADMIN_HOST`, so it is part 1's behaviour). `bin/rails zeitwerk:check` and `bin/rails test test/lib/admin_namespace_shadow_test.rb` — PASS.
- [ ] **Step 5: Commit** `feat: with ADMIN_HOST, the backend answers on its host alone and the public site on the others`.

---

### Task 3: Mails, the MCP address, the copy link, cookies and the cable's origin

**Files:**
- Modify: `app/mailers/application_mailer.rb` (`link_origin`: `SiteAddress.admin.url_options` first when configured, then today's order; the "WHERE THE LINK POINTS" comment gains the admin host's line)
- Modify: `app/controllers/admin/api_tokens_controller.rb` (`mcp_url`: `"#{SiteAddress.admin.origin || PublicSite::Urls.default_host}#{mcp_path}"`, comment)
- Modify: `test/lib/mail_guards_test.rb`, `test/mailers/passwords_mailer_test.rb`, `test/mailers/sign_in_mailer_test.rb`, `test/mailers/invites_mailer_test.rb` (the files that exist for these mailers; `ls test/mailers`), `test/integration/admin_host_test.rb`, `test/integration/admin/api_tokens_test.rb`

**Interfaces:**
- Consumes: `SiteAddress.admin`, `with_admin_address`.

- [ ] **Step 1: Write the failing tests.**
  - Each of the three mailer tests: with both addresses set, the link's host is `studio.example.internal` (`URI.parse(link).host`), and with only `PUBLIC_HOST` it is still `docs.example.org`.
  - `mail_guards_test.rb`: "every link into CS Studio a mailer builds takes the link origin's options": every line under `app/mailers` (comments stripped, `test/support/source_code.rb`) that calls an `admin_\w+_url(` passes `**@url_options`, and no line under `app/mailers` or `app/views/*_mailer` calls a `_url` helper that is not `admin_…_url` (FormsMailer and SystemMailer link nowhere, R7). A can-fail sample: the check run on the string `admin_edit_password_url(anchor: x)` reports it.
  - `admin_host_test.rb`: "a reset mail's link names the admin host" (`post "/cs-studio/password"` on the admin host with a user's email, `perform_enqueued_jobs`, the delivered mail's link host); "the session cookie has no Domain attribute" (sign in on the admin host, `assert_no_match(/;\s*domain=/i, response.headers["Set-Cookie"].to_s)`); "the editor's copy link to a published page names the public host" (sign in on the admin host, open a published page's editor, `assert_select "[data-admin--ui--clipboard-url-value^='https://docs.example.org/']"`); "the content security policy restricts neither connect-src nor default-src" (on a CS Studio page, the `Content-Security-Policy` header has no `connect-src` and no `default-src`, R5); "the cable accepts its own origin and no other" (`assert ActionCable.server.config.allow_same_origin_as_host` and `assert_nil Rails.application.config.action_cable.allowed_request_origins`, with a comment pointing to R5: a list or a switched-off same-origin rule would change what the admin host's socket accepts).
  - `api_tokens_test.rb`: with both addresses, the client configuration's `"url"` is `"https://studio.example.internal/cs-studio/mcp"`.
  - A source check in `admin_host_test.rb`: no line under `app`, `config` or `lib` (comments stripped) passes `domain:` to `cookies`, a `session_store` or `cookies.encrypted`/`signed` writes.
- [ ] **Step 2: Run** the listed files — FAIL.
- [ ] **Step 3: Implement** `link_origin` and `mcp_url`.
- [ ] **Step 4: Run** the listed files and `bin/rails test test/mailers test/lib` — PASS.
- [ ] **Step 5: Commit** `feat: with ADMIN_HOST, mailed links into CS Studio and the MCP address name the admin host`.

---

### Task 4: System status names the admin address

**Files:**
- Modify: `app/models/setup/system_check.rb` (`initialize` takes `admin_address: SiteAddress.admin`; `run` adds `admin_address` after `site_address`, nil (no row) when not configured, else `ok("CS Studio address", "CS Studio answers at #{origin} alone. The public address answers no CS Studio page.")`)
- Test: `test/models/setup/system_check_test.rb`, and the System status integration test that lists the rows (`test/integration/admin/system_status_test.rb`), if it pins the row list

**Interfaces:**
- Consumes: `SiteAddress.admin`.

- [ ] **Step 1: Write the failing tests:** "with an admin address the CS Studio address row says where CS Studio answers" (exact message above, status `:ok`); "without one there is no such row".
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement** (the row's label and message follow the file's existing English literals; if System status's rows are already keys in `config/locales/admin/`, add keys there instead and `test/lib/admin_i18n_test.rb` holds it). **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `feat: System status names the CS Studio address`.

---

### Task 5: Docs, deploy files and CHANGELOG

**Files:**
- Modify: `docs/reference/hosting.md`: the "What a host sets" table gains `ADMIN_HOST` (what it does; without it, one host serves both); "Every variable the code reads" gains its row (host, no default, not a secret); "The site's address: `SiteAddress`" names `SiteAddress.admin` and `with_admin_address`; "What production does with it: `HostSettings`" the hosts, the three refusals and the boot line; a new part "Behind a DMZ" after "The visitor's address behind a proxy": the routes and the two constraints (R2, R3, R4), 404 never a redirect, `/up` and Active Storage on both, the cookie is host-only, CSRF unchanged, the cable's same-origin rule (R5), mailed links (R7), preview links on the request's origin and the copy link on `PUBLIC_HOST`, `TRUSTED_PROXIES` on both hosts, the admin hostname unproxied or its own Access application, the edge rule the public host may add (refuse `/<ADMIN_PATH>/*`), and the public-only role named as later and not built; "Rules a change can break silently": `ADMIN_HOST` is read by `SiteAddress` alone and set in tests through `with_admin_address` only (no guard finds a second reader), and every backend route carries `HostRouteConstraint::Backend` (`test/lib/backend_paths_test.rb`).
- Modify: `config/deploy.yml` and `lib/site_template/config/deploy.yml.tt` (a commented `# ADMIN_HOST: https://studio.example.internal` under `env.clear`, beside `PUBLIC_HOST`, with one line: only for a backend behind a DMZ, `docs/reference/hosting.md`, "Behind a DMZ")
- Modify: `test/lib/site_generator_test.rb` (add `ADMIN_HOST` to the names the generated `deploy.yml` holds)
- Modify: `CLAUDE.md` ("Deploy:": after the eight variables, `ADMIN_HOST`, optional, the backend's own host behind a DMZ, which needs `PUBLIC_HOST` (`docs/reference/hosting.md`, "Behind a DMZ"); the reference index's hosting line names `HostRouteConstraint`)
- Modify: `CHANGELOG.md`, `## Unreleased`:

```markdown
### Environment

- `ADMIN_HOST` (optional): the address, with its scheme, of a host that serves CS Studio alone, for a backend behind a DMZ. With it, every address under `/<ADMIN_PATH>/` answers only on that host and the public site does not answer on it; `/up` and images answer on both. It needs `PUBLIC_HOST`, another host name and the same scheme, or production does not start (`docs/reference/hosting.md`, "Behind a DMZ").

### Added

- `ADMIN_HOST`: CS Studio on a host of its own. Reset, invitation and lock-out mails link to it, the API tokens screen names the MCP address on it, and System status shows a "CS Studio address" row.

### Breaking

- A new top-level name, `HostRouteConstraint` (`app/constraints/host_route_constraint.rb`): a gem whose hook owner has that name is refused at boot.
```

- [ ] **Step 1: Write the edits.**
- [ ] **Step 2: Run** `bin/rails test test/lib` — PASS (`environment_variables_test.rb` holds the variable table to the code; `site_generator_test.rb` the deploy file). `bin/changelog-guard` as `bin/ci` runs it — PASS.
- [ ] **Step 3: Commit** `docs: ADMIN_HOST, behind a DMZ`.

---

### Task 6: Whole-suite verification and the pull request

- [ ] **Step 1:** `bin/rubocop`, `bin/brakeman` (exit 0), `bin/rails zeitwerk:check`, `bin/rails test` — green.
- [ ] **Step 2:** On a quiet machine: `bin/rails tailwindcss:build`, then `PARALLEL_WORKERS=6 bin/rails test:system` — green.
- [ ] **Step 3:** By hand in development: `PUBLIC_HOST=http://site.localhost:3000 ADMIN_HOST=http://studio.localhost:3000 bin/dev` (development keeps Rails' own `.localhost` hosts). `http://studio.localhost:3000/cs-studio` signs in, the editor's socket connects to `ws://studio.localhost:3000/cs-studio/cable`, `http://site.localhost:3000/cs-studio/sign-in` is the public 404, `http://studio.localhost:3000/` is a 404.
- [ ] **Step 4:** Open the pull request (`superpowers:finishing-a-development-branch`). Its "Documentation" section names the guide's hosting and Cloudflare pages and a new "Behind a DMZ" page (`contentspiel-docs`).
