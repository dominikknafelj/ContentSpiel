# The whole backend under ADMIN_PATH, part 1: the move — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every route a person or a client of CS Studio uses answers under `/<ADMIN_PATH>/` (preview, setup wizard, MCP, Action Cable join sign-in and the screens), Action Mailbox is gone, Active Storage's two write endpoints answer 404 to everyone, and a guard test fails on any new route outside the prefix that is not on a public list with its reason.

**Architecture:** Preview, setup and MCP move into a second plain `scope ContentSpiel::ADMIN_PATH do … end` in `config/routes.rb` (no `module:`, no `as:`), so controllers and route helper names stay and every helper caller follows. Action Cable is mounted in that same scope by `routes.rb` itself (Rails' own prepended mount is switched off), and the admin layouts carry `action_cable_meta_tag` so turbo-rails' consumer asks the new address. The guard `test/lib/backend_paths_test.rb` reads the drawn route set, internal routes included.

**Tech Stack:** Rails 8.1.4 routing (Journey), Action Cable 8.1, turbo-rails 2.0.23 (`config.turbo.draw_routes`), Active Storage, Rack::Attack, Minitest + fixtures, Capybara/Cuprite for the browser suite.

**Spec:** `docs/superpowers/specs/2026-11-12-backend-under-admin-path-design.md`, sections 1 to 4, "My calls" 1 to 5, "Left to the builder", "How it ships" (first PR). Part 2 (`ADMIN_HOST`) is `docs/superpowers/plans/2026-11-12-backend-under-admin-path-2-admin-host.md`.

## Global Constraints

- New addresses, with the default `ADMIN_PATH` `cs-studio`: `/cs-studio/preview(/*path)`, `/cs-studio/preview/:locale(/*path)`, `/cs-studio/setup`, `/cs-studio/setup/:step`, `POST /cs-studio/mcp`, `/cs-studio/cable`. Code never writes `cs-studio` literally: it writes `ContentSpiel::ADMIN_PATH` or a route helper. Tests write `/cs-studio/...` literally, as the suite already does for every CS Studio path.
- Route helper names and controllers do not change: `preview_path`, `localized_preview_path`, `setup_path`, `setup_step_path`, `mcp_path`; `PreviewController`, `SetupController`, `McpController`.
- No alias, redirect or fallback from `/preview`, `/setup`, `/mcp` or `/cable` (CLAUDE.md: no compatibility code). They become ordinary public page paths.
- `ContentSpiel::RESERVED_PATHS` becomes `%w[up rails lookbook assets sitemap.xml] + SUPPORTED_LOCALES.keys`.
- `Setup::RedirectConstraint::EXEMPT_PREFIXES` becomes `/<ADMIN_PATH>/setup`, `/<ADMIN_PATH>/mcp`, `/<ADMIN_PATH>/sign-in`, `/<ADMIN_PATH>/sign-out`, `/<ADMIN_PATH>/password`, `/up`, `/rails/active_storage`.
- Active Storage routes stay drawn (`draw_routes` stays on: `rails_blob_path` and the other `direct` routes share its file).
- Comments state the current invariant and its reason, never "moved from" or "used to be" (CLAUDE.md). Rewrite the comments the move makes false (`routes.rb`'s "Declared before /preview", `admin_path.rb`'s list, `active_storage_access.rb`, `api_tokens_controller.rb`'s "outside the admin scope", `note_signals_test.rb`'s `/cable` comment).
- `CHANGELOG.md`, `## Unreleased`: `### Breaking` and `### Removed` lines exactly as in Task 8.
- Browser tests run only on a quiet machine (`sysctl -n vm.loadavg` well under the core count), `PARALLEL_WORKERS=6`, never while a build runs.

## Rulings made in planning

- **R1 — the cable is mounted by `routes.rb`, not by `config.action_cable.mount_path`.** `config/application.rb` sets `config.action_cable.mount_path = nil` (Rails then prepends no mount), `routes.rb` draws `mount ActionCable.server => "cable", internal: true, anchor: true` inside the new scope, and `config/initializers/admin_path.rb` sets `Rails.application.config.action_cable.url = "/#{ADMIN_PATH}/cable"` (what `action_cable_meta_tag` prints when `mount_path` is nil). Reason: the mount sits in `routes.rb` beside the other backend routes, and part 2 can wrap it in the host constraint with them; Rails' prepended mount stands outside every block of `routes.rb`. Cost if wrong: one setting moves back.
- **R2 — Turbo's historical-location routes are switched off** (`config.turbo.draw_routes = false` in `config/application.rb`), not listed: turbo-rails 2.0.23 has the switch, the `*path` catch-all shadows them anyway, and nothing in the app names `turbo_*_historical_location_*`.
- **R3 — the write refusal is a renamed concern, `ActiveStorageWriteRefusal`** (`app/controllers/concerns/active_storage_write_refusal.rb`), replacing `ActiveStorageWriteAuthentication`: `before_action :refuse_write, except: :show`, which answers `head :not_found`. It does not include `Authentication`, so no session is read or written. The same name pattern as `ActiveStorageNoteFilesRefusal`.
- **R4 — the guard's `PUBLIC` keys are `"VERB spec"` strings** (`"GET /up(.:format)"`, `" /*path"` for a `via: :all` route, whose `route.verb` is `""`), the spec exactly as `route.path.spec.to_s` prints it.

## Review Focus

1. **An old address after the move** — `GET /preview/draft`, `GET /setup`, `POST /mcp`, `GET /cable` with no page of that slug answer the public site's 404 ("Page not found", no `Set-Cookie`), and a top-level page slugged `preview` is served at `/preview` (Task 2, Task 3, Task 4, Task 5 tests).
2. **Setup still pending after the move** — `/cs-studio/setup` must not redirect to itself (a redirect loop locks out a fresh install), `POST /cs-studio/mcp` stays exempt, and `/cs-studio/preview` is redirected to the wizard (Task 3 test).
3. **The live socket after the move** — turbo-rails' consumer falls back to `/cable` when no meta tag is there, so notes, presence and live editing would silently stop reconnecting; the admin layout's tag must name `/cs-studio/cable` and the browser suite's live tests must pass (Task 5 test and Task 9 run).
4. **A link inside a preview** (rich text, a list block, the plain theme's tree and crumb, the post list) keeps the visitor under `/cs-studio/preview/...`, never `/preview/...` (Task 2: `urls_test.rb`, `preview_test.rb` and the other preview tests rewritten, not deleted).
5. **A non-default ADMIN_PATH** — with `ADMIN_PATH=studio` the preview, setup, MCP and cable addresses all follow (Task 7 boot test).

---

### Task 0: Setup

- [ ] **Step 1: Merge main.** The passkeys branch (sign-in PR 3) must have merged first; it changes `config/routes.rb` and `app/controllers/concerns/authentication.rb`.

```bash
cd /Users/dknafelj/src/ContentSpiel-backend-path
git fetch origin && git merge origin/main
bin/rails db:test:prepare
```

Expected: a clean merge (this branch holds only the spec and the plans). If `git log origin/main` shows no passkeys merge, stop and say so.

- [ ] **Step 2: Baseline.** `bin/rails test` — expected: green. Record any failure that is not this branch's before starting.

---

### Task 1: Action Mailbox and Turbo's historical routes are gone

**Files:**
- Modify: `config/application.rb` (delete `require "action_mailbox/engine"`; add `config.turbo.draw_routes = false` inside the application class with a one-line reason)
- Modify: `docs/roadmap.md` (the "Remove leftovers" row: Action Mailbox is done)
- Test: `test/integration/backend_routes_test.rb` (create)

**Interfaces:**
- Produces: no route whose path starts with `/rails/action_mailbox`, `/rails/conductor` or contains `historical_location`.

- [ ] **Step 1: Write the failing tests** in `test/integration/backend_routes_test.rb` (class `BackendRoutesTest < ActionDispatch::IntegrationTest`, with `preview_test.rb`'s `setup` line `site_settings(:default).update!(setup_completed_at: Time.current)`; Tasks 2 to 5 add to it, using `create_page` from `test/support/content_helper.rb`):

```ruby
test "Action Mailbox draws no route" do
  specs = Rails.application.routes.routes.map { |route| route.path.spec.to_s }
  assert_empty specs.grep(%r{\A/rails/(action_mailbox|conductor)})
  assert_not defined?(ActionMailbox::Engine)
end

test "Turbo's historical-location routes are not drawn" do
  assert_empty Rails.application.routes.routes.map { |route| route.path.spec.to_s }.grep(/historical_location/)
end
```

- [ ] **Step 2: Run** `bin/rails test test/integration/backend_routes_test.rb` — expected: both FAIL.
- [ ] **Step 3: Implement** the two `config/application.rb` changes. Grep `app config lib test` for `mailbox`, `historical_location` and `turbo_.*_historical` to confirm nothing else names them.
- [ ] **Step 4: Run** the file again — PASS; then `bin/rails zeitwerk:check` — "All is good!".
- [ ] **Step 5: Commit**

```bash
git add config/application.rb docs/roadmap.md test/integration/backend_routes_test.rb
git commit -m "chore: remove Action Mailbox and Turbo's unreachable historical-location routes"
```

---

### Task 2: The preview under ADMIN_PATH

**Files:**
- Modify: `config/routes.rb` (move `localized_preview` and `preview` into a new `scope ContentSpiel::ADMIN_PATH do … end` declared right after the admin scope's `end` and before `post "forms/:form_id"`; keep both routes' options and their comment)
- Modify: `app/models/public_site/urls.rb` (`#prefix`: `"/#{ContentSpiel::ADMIN_PATH}/preview#{code_prefix}"`, its comment)
- Modify: comments naming `/preview` in `app/constraints/locale_route_constraint.rb`, `app/controllers/preview_controller.rb`, `app/controllers/public_controller.rb`, `app/controllers/form_sends_controller.rb`, `app/controllers/concerns/public_page_rendering.rb`, `app/controllers/admin/link_targets_controller.rb`, `app/components/application_component.rb`, `app/components/public/preview_bar_component.rb`, `app/models/rich_text/document.rb`, `app/models/public_site/paths.rb`, `app/helpers/theme_helper.rb`, `app/views/pages/_seo_meta.html.erb`, `config/routes.rb` (write `/<ADMIN_PATH>/preview` where a comment names the address)
- Test: every test that requests or asserts `/preview…`: `test/integration/preview_test.rb`, `preview_internal_link_test.rb`, `public_drafts_test.rb`, `public_head_address_test.rb`, `public_canary_test.rb`, `rich_text_body_test.rb`, `theme_pages_test.rb`, `card_link_target_test.rb`, `trash_visibility_test.rb`, `admin/access_control_test.rb`, `test/models/public_site/urls_test.rb`, `test/models/rich_text/html_renderer_test.rb`, `test/queries/public_site/branch_test.rb`, `test/system/admin/system_status_and_preview_test.rb`; and `test/integration/backend_routes_test.rb`

**Interfaces:**
- Produces: the second scope block in `routes.rb` (Tasks 3 to 5 add to it). `PublicSite::Urls.new(preview: true).path_for(record, locale)` answers `/cs-studio/preview/...`.

- [ ] **Step 1: Write the failing tests.** In `backend_routes_test.rb`:

```ruby
test "the preview answers under the admin path, and /preview is a public page path" do
  create_page(title: "Draft", published: false)       # slug "draft"
  sign_in_as(users(:one))

  get "/cs-studio/preview/draft"
  assert_response :success

  get "/preview/draft"
  assert_response :not_found
  assert_equal "Page not found", response.body
end

test "a top-level page slugged preview is served at /preview" do
  create_page(title: "Preview", published: true)
  get "/preview"
  assert_response :success
end
```

In `urls_test.rb`, change "preview urls stay under /preview" to assert `"/cs-studio/preview/about"` and `"/cs-studio/preview/de/about"`, and rename it "preview urls stay under the admin path's preview".

- [ ] **Step 2: Run** `bin/rails test test/integration/backend_routes_test.rb test/models/public_site/urls_test.rb` — expected: FAIL.
- [ ] **Step 3: Implement** the scope and `PublicSite::Urls#prefix`. Then rewrite every listed test's literal `/preview` to `/cs-studio/preview` (`assert_redirected_to "/preview/elsewhere"` becomes `"/cs-studio/preview/elsewhere"`; selectors such as `a[href^='/preview']` likewise), and the comments listed above.
- [ ] **Step 4: Grep** `grep -rnE "[\"'(\` ]/preview\b" app lib config test` — expected: no line but comments that name `/<ADMIN_PATH>/preview`.
- [ ] **Step 5: Run** every listed test file but the system one: `bin/rails test test/integration/preview_test.rb test/integration/preview_internal_link_test.rb test/integration/public_drafts_test.rb test/integration/public_head_address_test.rb test/integration/public_canary_test.rb test/integration/rich_text_body_test.rb test/integration/theme_pages_test.rb test/integration/card_link_target_test.rb test/integration/trash_visibility_test.rb test/integration/admin/access_control_test.rb test/models/public_site/urls_test.rb test/models/rich_text/html_renderer_test.rb test/queries/public_site/branch_test.rb test/integration/backend_routes_test.rb` — PASS.
- [ ] **Step 6: Commit** (`git add` the files touched, by path) with `feat!: the preview answers under ADMIN_PATH`.

---

### Task 3: The setup wizard under ADMIN_PATH

**Files:**
- Modify: `config/routes.rb` (the three setup routes into the second scope; the two setup-required catch-alls redirect to `"/#{ContentSpiel::ADMIN_PATH}/setup"`)
- Modify: `app/constraints/setup/redirect_constraint.rb` (`EXEMPT_PREFIXES` as in Global Constraints; the comment's "/setup")
- Modify: `app/models/setup/token.rb` (`log_line`: "Open /#{ContentSpiel::ADMIN_PATH}/setup and …"; the class comment)
- Modify: `config/initializers/setup_token.rb` comment; `lib/site_template/README.md.tt` (`https://<your-host>/cs-studio/setup`, saying `cs-studio` is the default `ADMIN_PATH`, as its sign-in line does); `lib/site_template/config/deploy.yml.tt` (the `SETUP_TOKEN` comment's address)
- Test: `test/integration/setup_redirect_test.rb`, `setup_access_test.rb`, `admin/invariants_test.rb`, `test/models/setup/token_test.rb`, `test/system/setup_wizard_test.rb`, `test/system/theme_toggle_test.rb` (comment), `test/fixtures/site_settings.yml` (comment), `test/integration/backend_routes_test.rb`

**Interfaces:**
- Consumes: the second scope from Task 2.
- Produces: `setup_path == "/cs-studio/setup"`; `Setup::Token.log_line` exact strings:
  - `"[ContentSpiel] Setup is not complete. Open /cs-studio/setup and enter the setup token you set in SETUP_TOKEN."`
  - `"[ContentSpiel] Setup is not complete. Open /cs-studio/setup and enter this setup token: #{value}"`

- [ ] **Step 1: Write the failing tests.** In `setup_redirect_test.rb`, every `assert_redirected_to "/setup"` becomes `"/cs-studio/setup"` (its `post "/mcp"` line is Task 4's), and add:

```ruby
test "the wizard itself is not redirected, and the preview is" do
  start_fresh_install

  get "/cs-studio/setup"
  assert_response :success              # or the wizard's first-step redirect: never to itself
  assert_not_equal "/cs-studio/setup", URI.parse(response.location.to_s).path if response.redirect?

  get "/cs-studio/preview"
  assert_redirected_to "/cs-studio/setup"
end
```

In `backend_routes_test.rb`: with setup complete, `get "/setup"` answers 404 "Page not found". Update `token_test.rb`'s two strings to the exact ones above, `setup_access_test.rb`'s path, `invariants_test.rb`'s redirect target, and `setup_wizard_test.rb`'s `assert_current_path`/`visit` to `/cs-studio/setup/token`.

- [ ] **Step 2: Run** `bin/rails test test/integration/setup_redirect_test.rb test/integration/setup_access_test.rb test/integration/admin/invariants_test.rb test/models/setup/token_test.rb test/integration/backend_routes_test.rb` — expected: FAIL.
- [ ] **Step 3: Implement** the routes, `EXEMPT_PREFIXES`, `log_line`, comments and the two site-template files.
- [ ] **Step 4: Run** the same files — PASS. Run `bin/rails test test/lib/site_generator_test.rb` — PASS.
- [ ] **Step 5: Commit** with `feat!: the setup wizard answers under ADMIN_PATH`.

---

### Task 4: MCP under ADMIN_PATH

**Files:**
- Modify: `config/routes.rb` (`post "mcp", to: "mcp#create"` into the second scope; its comment)
- Modify: `app/controllers/admin/api_tokens_controller.rb` (`mcp_url`: `"#{PublicSite::Urls.default_host}#{mcp_path}"`, the comment no longer says "outside the admin scope")
- Modify: `app/views/setup/mcp_token.html.erb` (`tag.code(mcp_path, class: "font-cs-mono")`)
- Modify: `config/initializers/rack_attack.rb` (`req.path == "/#{ContentSpiel::ADMIN_PATH}/mcp"`; its first comment line)
- Test: `test/integration/mcp_test.rb`, `mcp_access_control_test.rb`, `mcp_media_test.rb`, `mcp_rate_limit_test.rb`, `trash_visibility_test.rb` (its `post "/mcp"`), `admin/api_tokens_test.rb`, `setup_redirect_test.rb` (if not done in Task 3), `test/integration/backend_routes_test.rb`

**Interfaces:**
- Consumes: the second scope. Produces: `mcp_path == "/cs-studio/mcp"`; the token screen's client configuration `"url"` ends in `/cs-studio/mcp`.

- [ ] **Step 1: Write the failing tests.** Every `post "/mcp"` in the listed files becomes `post "/cs-studio/mcp"`. In `admin/api_tokens_test.rb`, assert the reveal's configuration names `"#{PublicSite::Urls.default_host}/cs-studio/mcp"` (find the existing assertion on `mcp_url` or the config JSON and change its expected value; add one if none exists). In `backend_routes_test.rb`:

```ruby
test "POST /mcp is no endpoint any more" do
  post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
    headers: { "Content-Type" => "application/json", "Authorization" => "Bearer anything" }
  assert_response :not_found
end
```

- [ ] **Step 2: Run** the listed files — FAIL.
- [ ] **Step 3: Implement.** Then check the rate limit still counts: `mcp_rate_limit_test.rb` must exceed `Rack::Attack::MCP_RATE_LIMIT` at the new path and get 429.
- [ ] **Step 4: Run** the listed files — PASS. `bin/rails test test/lib` — PASS (i18n and source guards read the view).
- [ ] **Step 5: Commit** with `feat!: the MCP endpoint answers under ADMIN_PATH`.

---

### Task 5: Action Cable under ADMIN_PATH

**Files:**
- Modify: `config/application.rb` (`config.action_cable.mount_path = nil`, with the reason: `routes.rb` mounts it under the admin path)
- Modify: `config/initializers/admin_path.rb` (after the constant: `Rails.application.config.action_cable.url = "/#{ADMIN_PATH}/cable"`)
- Modify: `config/routes.rb` (in the second scope: `mount ActionCable.server => "cable", internal: true, anchor: true`, with a comment: the socket of notes, presence and live editing; `internal` keeps it out of `bin/rails routes`, the guard reads it anyway)
- Modify: `app/views/layouts/admin.html.erb` and `app/views/layouts/setup.html.erb` (`<%= action_cable_meta_tag %>` beside `csp_meta_tag`; a one-line ERB comment: turbo-rails' consumer reads it and otherwise asks `/cable`). Grep the other layouts: one that imports the `admin` entry or draws `turbo_stream_from` gets it too; the public layouts do not.
- Modify: `app/javascript/live/connection.js` header comment if it names `/cable`
- Test: `test/integration/admin/note_signals_test.rb` ("the cable's address is Action Cable's own…"), `test/channels/application_cable/connection_test.rb` (comment), `test/integration/backend_routes_test.rb`

**Interfaces:**
- Produces: `ActionCable.server.config.url == "/cs-studio/cable"`; a CS Studio page's `<meta name="action-cable-url" content="/cs-studio/cable">`.

- [ ] **Step 1: Write the failing tests.** Rewrite the note_signals test as "the cable's address is under the admin path, and /cable is a public page path":

```ruby
create_page(title: "cable", published: true)

get "/cs-studio/cable"
assert_response :not_found            # Action Cable's own refusal of a plain GET
assert_nil response.headers["Set-Cookie"]

get "/cable"
assert_response :success              # the page slugged "cable"
```

Keep "a public page loads and names nothing of the cable" as it is. In `backend_routes_test.rb`:

```ruby
test "a CS Studio page names the cable's address for turbo-rails' consumer" do
  sign_in_as(users(:one))
  get "/cs-studio"
  assert_select "meta[name='action-cable-url'][content='/cs-studio/cable']"
end
```

- [ ] **Step 2: Run** `bin/rails test test/integration/admin/note_signals_test.rb test/integration/backend_routes_test.rb test/channels` — FAIL.
- [ ] **Step 3: Implement.** Action Cable copies `config.action_cable` into `ActionCable.server.config` in an `ActiveSupport.on_load(:action_cable)` hook, so the initializer's assignment reaches it only if nothing loaded the server earlier. If the meta tag's content is not `/cs-studio/cable`, find what loads it first and set `ActionCable.server.config.url` there too; never read `ENV["ADMIN_PATH"]` a second time (the constant is its one reader).
- [ ] **Step 4: Run** the same files — PASS. Then the live browser tests, on a quiet machine: `PARALLEL_WORKERS=6 bin/rails test test/system/admin/notes_live_test.rb` (and the presence and live-editing system files; `ls test/system/admin | grep -E "live|presence|editing"`) — PASS.
- [ ] **Step 5: Commit** with `feat!: Action Cable answers under ADMIN_PATH`.

---

### Task 6: Active Storage's writes answer 404 to everyone

**Files:**
- Create: `app/controllers/concerns/active_storage_write_refusal.rb` (`module ActiveStorageWriteRefusal`, `extend ActiveSupport::Concern`, `included { before_action :refuse_write, except: :show }`, private `def refuse_write = head(:not_found)`; header comment: nothing calls the two endpoints, every upload goes through a CS Studio controller that checks the file, and a session that could create orphan blobs is surface with no use; no session is read)
- Delete: `app/controllers/concerns/active_storage_write_authentication.rb`
- Modify: `config/initializers/active_storage_access.rb` (include `ActiveStorageWriteRefusal` in `ActiveStorage::DirectUploadsController` and `ActiveStorage::DiskController` with the existing `include?` guards; drop `allow_unauthenticated_access only: :show`; rewrite the first paragraph of the comment)
- Test: `test/integration/active_storage_access_test.rb`

**Interfaces:**
- Produces: `POST /rails/active_storage/direct_uploads` and `PUT /rails/active_storage/disk/:encoded_token` answer 404 signed in or out; `GET /rails/active_storage/disk/...` unchanged.

- [ ] **Step 1: Write the failing tests.** In `active_storage_access_test.rb`: the two "signed out" tests expect `:not_found` (and still no blob, no bytes); "signed in, a direct upload still works" becomes:

```ruby
test "signed in, a direct upload is refused too, and opens no session" do
  sign_in_as(users(:one))

  assert_no_difference -> { ActiveStorage::Blob.count } do
    post "/rails/active_storage/direct_uploads", params: BLOB_PARAMS, as: :json
  end
  assert_response :not_found
  assert_nil response.headers["Set-Cookie"]
end
```

and add "signed in, a disk upload with a valid token writes nothing" (as the signed-out one, after `sign_in_as`, 404). Update the class comment.

- [ ] **Step 2: Run** `bin/rails test test/integration/active_storage_access_test.rb` — FAIL.
- [ ] **Step 3: Implement.** Grep `app config lib test docs/reference CLAUDE.md` for `ActiveStorageWriteAuthentication` and `direct upload` and fix each mention.
- [ ] **Step 4: Run** that file plus `test/integration/image_delivery_test.rb` — PASS. `bin/rails zeitwerk:check` — "All is good!".
- [ ] **Step 5: Commit** with `feat!: Active Storage's direct uploads answer 404 to everyone`.

---

### Task 7: RESERVED_PATHS and the route guard

**Files:**
- Modify: `config/initializers/admin_path.rb` (`RESERVED_PATHS = %w[up rails lookbook assets sitemap.xml].freeze + SUPPORTED_LOCALES.keys`; the comment's list loses the four entries, and says the backend's own segments are under the admin path and so collide with nothing)
- Modify: `test/integration/admin/shell_test.rb` (the denylist test's expected list; the boot-refusal test uses `%w[up de]` and its comment)
- Create: `test/lib/backend_paths_test.rb`

**Interfaces:**
- Produces: `BackendPathsTest::PUBLIC` (Hash of `"VERB spec"` → reason); private helpers `key(route) -> String` (`"#{route.verb} #{route.path.spec}"`), `under_prefix?(route) -> Boolean` and `outside(route_set) -> Array<String>` (the keys of each route neither under the prefix nor in `PUBLIC`). Part 2 adds a host test to this file and uses all three.

- [ ] **Step 1: Write the guard.** Header comment: what it holds (the spec's Goal 1), what it reads (`Rails.application.routes.routes`, internal routes included, since the cable mount is internal and `bin/rails routes` hides it), and what it cannot see (routes drawn only in development: `/lookbook`, `/rails/info`, `/rails/mailers`). Under prefix means `spec == "/#{ADMIN_PATH}"` or `spec.start_with?("/#{ADMIN_PATH}/")` or `spec.start_with?("/#{ADMIN_PATH}(")` (Journey writes an optional format group straight after the segment). `PUBLIC` entries, each with its reason as the value:
  - the two setup-required redirects (`/` and `/*path`, verb `""`): they only send a request to the wizard;
  - `GET /`, `GET /:locale(/*path)`, `GET /*path`: the public site's pages;
  - `POST /forms/:form_id`: a visitor's send of a form;
  - `GET /up(.:format)`: the health check, asked by the proxy;
  - each `/rails/active_storage/...` route as `bin/rails routes -g active_storage` lists it in the test environment: the reads with "public pages embed these; `ActiveStoragePublicFiles` decides what they serve", the two writes with "drawn because the read helpers share their file; `ActiveStorageWriteRefusal` answers 404 to everyone".

Tests:

```ruby
test "the guard is looking at the routes" do
  set = ActionDispatch::Routing::RouteSet.new
  set.draw do
    scope(ContentSpiel::ADMIN_PATH) { get "inside", to: "x#y" }
    post "export", to: "x#y"
  end
  assert_equal [ "POST /export(.:format)" ], outside(set)
end

test "every route outside ADMIN_PATH is on the public list, with its reason" do
  assert_empty outside(Rails.application.routes),
    "these answer outside /#{ContentSpiel::ADMIN_PATH}/: move them under it, or add them to PUBLIC with the reason they are public"
end

test "the public list names only routes that exist" do
  drawn = Rails.application.routes.routes.map { |route| key(route) }
  assert_empty PUBLIC.keys - drawn
end

test "the cable mount is among the routes the guard reads" do
  assert_includes Rails.application.routes.routes.map { |route| route.path.spec.to_s }.grep(/cable/).first.to_s, "/#{ContentSpiel::ADMIN_PATH}/cable"
end

test "with another ADMIN_PATH every backend address follows" do
  script = 'h = Rails.application.routes.url_helpers; puts [h.preview_path, h.setup_path, h.mcp_path, ActionCable.server.config.url].join(" ")'
  output, status = Open3.capture2e({ "ADMIN_PATH" => "studio", "RAILS_ENV" => "test" }, "bin/rails", "runner", script)
  assert status.success?, output
  assert_equal "/studio/preview /studio/setup /studio/mcp /studio/cable", output.lines.last.strip
end
```

- [ ] **Step 2: Run** `bin/rails test test/lib/backend_paths_test.rb test/integration/admin/shell_test.rb` — expected: shell_test FAILS on the list until the initializer changes; the guard tests PASS (Tasks 1 to 6 already moved everything). If `outside` names a route, it is one this plan missed: move it or list it with its reason, never silently.
- [ ] **Step 3: Implement** `RESERVED_PATHS` and its comment.
- [ ] **Step 4: Run** both files — PASS. Temporarily add `post "export", to: "pages#show"` at the top level of `routes.rb`, run the guard, see it named, and remove the line.
- [ ] **Step 5: Commit** with `test: a guard holds every route outside ADMIN_PATH to a public list with its reason`.

---

### Task 8: Docs and CHANGELOG

**Files:**
- Modify: `docs/reference/hosting.md`: the `SETUP_TOKEN` row and "The setup token's log line" (the new address and line); "Sign-in on the open internet": Cloudflare Access on `/<ADMIN_PATH>` alone now covers the whole backend (screens, sign-in, preview, setup, MCP, cable), and a paragraph that an MCP client cannot complete Access's interactive login, so it needs an Access service token (`CF-Access-Client-Id` and `CF-Access-Client-Secret` sent by the client) or a Service Auth policy on `/<ADMIN_PATH>/mcp`, and that an invitee needs an Access policy that admits them before their link works; "Rules a change can break silently": a rule that every route outside `ADMIN_PATH` is on `PUBLIC` with its reason (`test/lib/backend_paths_test.rb`), and that routes drawn only in development (`/lookbook`, `/rails/info`, `/rails/mailers`) have **no guard**; the "Describes" line names the guard.
- Modify: `docs/reference/page-tree-and-routing.md` ("Public routing": the named routes that must win first are `/<ADMIN_PATH>/…` and `/up`, no `/mcp`), and every other file under `docs/reference/` that names `/preview`, `/setup`, `/mcp` or `/cable` (`grep -rnE "/(preview|setup|mcp|cable)\b" docs/reference`: i18n, trash, content-blocks-and-types, forms, access-control-and-audit, rich-text, writing-tests, publishing, theming, design-system, media, mail, notes, cs-studio-shell-and-dashboard; `users-groups-tokens.md` for the MCP address), each to `/<ADMIN_PATH>/…`; any that names `ActiveStorageWriteAuthentication` or "signed-in direct uploads".
- Modify: `CLAUDE.md` (the lines naming `/preview`, e.g. "A send from `/preview` is a real submission"; the reference-index lines naming the moved addresses), keeping each sentence's form.
- Modify: `CHANGELOG.md`, under `## Unreleased`:

```markdown
### Breaking

- The MCP endpoint is now `POST /<ADMIN_PATH>/mcp` (`/cs-studio/mcp` by default). `/mcp` is an ordinary public page path.
- The preview is now at `/<ADMIN_PATH>/preview/...`, the setup wizard at `/<ADMIN_PATH>/setup`, and Action Cable at `/<ADMIN_PATH>/cable`. The old addresses are ordinary public page paths, with no redirect. A guard in front of `/<ADMIN_PATH>` (Cloudflare Access, a WAF rule) now covers the whole backend; an MCP client behind Cloudflare Access needs a service token.
- `ADMIN_PATH` may now be `preview`, `setup`, `mcp` or `cable`, and a top-level page with one of those slugs is now reachable.

### Removed

- Action Mailbox and its routes (the ingresses and the conductor under `/rails/conductor/action_mailbox/`).
- Active Storage's direct uploads: `POST /rails/active_storage/direct_uploads` and `PUT /rails/active_storage/disk/:encoded_token` answer 404 to everyone, signed in or not. Every upload goes through CS Studio.
- Turbo's native-app historical-location routes, which the public catch-all already shadowed.
```

- [ ] **Step 1: Write the doc and changelog edits.**
- [ ] **Step 2: Run** the guards that read the docs: `bin/rails test test/lib` — PASS (`environment_variables_test.rb`, the source-layout and reference guards). Run `bin/changelog-guard origin/main` if it takes a base (see `bin/ci`) — PASS.
- [ ] **Step 3: Final grep** `grep -rnE "[\"'(\` =]/(preview|setup|mcp|cable)\b" app lib config test docs/reference CLAUDE.md install bin` — every remaining hit is a test of the old address's 404 or a sentence that names the old address as gone.
- [ ] **Step 4: Commit** with `docs: the backend's addresses under ADMIN_PATH, the guard, and the changelog`.

---

### Task 9: Whole-suite verification and the pull request

- [ ] **Step 1:** `bin/rubocop`, `bin/brakeman` (exit 0), `bin/rails zeitwerk:check`, `bin/rails test` — all green.
- [ ] **Step 2:** On a quiet machine: `bin/rails tailwindcss:build`, then `PARALLEL_WORKERS=6 bin/rails test:system` — green (the setup wizard, preview and live tests are the ones this branch can break).
- [ ] **Step 3:** In development, `bin/dev`, open `/cs-studio`, open a page in the editor, open its preview from the editor, and confirm in the browser's network panel that the WebSocket connects to `/cs-studio/cable`.
- [ ] **Step 4:** Open the pull request (`superpowers:finishing-a-development-branch`). Its body has a "Documentation" section naming the guide pages (`contentspiel-docs`): install and the setup wizard (the setup address), API tokens and the AI assistant (the MCP address, the Access service token), hosting and Cloudflare (Access on `ADMIN_PATH` alone).
