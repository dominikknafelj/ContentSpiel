# Safe on a public address — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One variable, `PUBLIC_HOST`, makes a production site safe on a public address: its own address in everything it prints, other hosts refused, HTTPS from the scheme, a quiet log, no credential in a URL.

**Architecture:** A plain value object `SiteAddress` (in `lib/`, because the environment file needs it before autoloading) parses the variable once. `HostSettings.apply` turns it into Rails configuration and is the one thing `production.rb` calls, so every decision is testable without booting production. Public views take absolute addresses only from `PublicSite::Urls`. The reset token moves into the URL fragment.

**Tech stack:** Rails 8.1, Minitest + fixtures, Capybara/Cuprite, Stimulus via importmap, OpenTelemetry SDK.

**Spec:** `docs/superpowers/specs/2026-10-12-safe-on-a-public-address-design.md`

## Global constraints

- Read `CLAUDE.md` first; its rules bind. Read `docs/reference/page-tree-and-routing.md` before Task 3 and `docs/reference/design-system.md` and `docs/reference/i18n.md` before Tasks 5 and 7.
- Every test command is prefixed `PGGSSENCMODE=disable`. System tests: `bin/rails tailwindcss:build` first, `PARALLEL_WORKERS=6`. Never two test runners at once on this machine (worktrees share the test databases).
- No token, key or secret in a rendered page, a log line or an audit event.
- New CS Studio strings are locale keys (`config/locales/admin/`), never literals. No inline handlers. No colour literals.
- A Stimulus identifier follows its controller's path.
- Development and test behaviour does not change except where a task says so (telemetry's console output).
- The variable names are exactly: `PUBLIC_HOST`, `SITEMAP_HOST` (old name, still read), `ASSUME_SSL`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_CONSOLE`, `SETUP_TOKEN`, `SECRET_KEY_BASE`.
- Commits: conventional subject, ending with the two attribution lines the controller gives in the dispatch.
- Scratch files only in a directory made with `mktemp -d` and deleted by name.

## Review focus

1. A `PUBLIC_HOST` with a trailing slash, a path, upper case or a port: the site must still answer on that host (Tasks 1, 2).
2. `PUBLIC_HOST` unset in production: the app starts, nothing is refused, nothing is forced, the checks warn (Tasks 2, 5).
3. A request with a foreign `Host` and `X-Forwarded-Host`: no printed address follows either (Task 3).
4. A reset link opened twice, opened without its fragment, and opened with JavaScript off (Task 7).
5. A proxy health check on `/up` by IP over plain HTTP under an `https` address: 200, not a redirect and not a 403 (Task 2).

## File map

| File | Responsibility |
|---|---|
| `lib/site_address.rb` (new) | Parse and hold the site's address |
| `lib/host_settings.rb` (new) | Turn the address and the environment's variables into Rails configuration |
| `config/application.rb`, `config/environments/production.rb` | Require the two, call `HostSettings.apply` |
| `app/models/public_site/urls.rb` | `configured_host` reads `SiteAddress.current` |
| `app/controllers/public_controller.rb`, `app/views/layouts/application.html.erb`, `app/views/pages/_seo_meta.html.erb` | Head tags from the configured origin; canonical link |
| `app/mailers/passwords_mailer.rb`, its views, `app/controllers/admin/passwords_controller.rb` | Mail origin; fragment token |
| `app/javascript/controllers/admin/shell/reset_token_controller.js` (new) | Move the fragment into the form |
| `app/models/setup/system_check.rb` | Checks "Site address" and "HTTPS" |
| `app/components/admin/ui/insecure_notice_component.*` (new) | The plain-HTTP notice |
| `config/initializers/opentelemetry.rb`, `lib/telemetry/path_scrubber.rb` (new) | Quiet by default; scrub |
| `config/initializers/setup_token.rb`, `config/initializers/admin_path.rb` | Small things |

---

### Task 1: `SiteAddress`

**Files:** Create `lib/site_address.rb`, `test/lib/site_address_test.rb`. Modify `config/application.rb` (one `require_relative "../lib/site_address"` after `Bundler.require`), `app/models/public_site/urls.rb`.

**Interfaces — produces:**

```ruby
SiteAddress.parse(string_or_nil)  # => SiteAddress; raises SiteAddress::Invalid (< ArgumentError) on a value that is not blank and not an absolute http(s) address with a host
SiteAddress.current               # => parse(ENV["PUBLIC_HOST"].presence || ENV["SITEMAP_HOST"].presence), memoised; SiteAddress.reset! clears it (tests)
address.configured?  # false for nil/blank
address.origin       # "https://docs.example.org" or "http://localhost:3030"; nil when not configured. Lower-cased host, default ports dropped, path/query/fragment/trailing slash dropped
address.host         # "docs.example.org"; nil when not configured
address.port         # Integer or nil when it is the scheme's default
address.https?       # true only for a configured https address
address.url_options  # { host:, protocol: "https", port: } without nil values; {} when not configured
```

- [ ] **Step 1: failing tests.** `test/lib/site_address_test.rb` (`ActiveSupport::TestCase`), one test each:
  - `"https://Docs.Example.org/"` → origin `"https://docs.example.org"`, host `"docs.example.org"`, `https?` true, port nil.
  - `"http://localhost:3030/some/path?x=1#y"` → origin `"http://localhost:3030"`, port 3030, `https?` false.
  - `"https://example.org:443"` → origin without the port.
  - `nil`, `""`, `"  "` → `configured?` false, origin nil, `url_options` `{}`.
  - `"docs.example.org"`, `"ftp://example.org"`, `"https://"`, `"https:///path"`, `"not a url"` → `SiteAddress::Invalid`, and the message contains `PUBLIC_HOST` and `https://www.example.org`.
  - `url_options` for `"https://example.org:8443"` is `{ host: "example.org", protocol: "https", port: 8443 }`.
  - `current` reads `PUBLIC_HOST` before `SITEMAP_HOST` (set `ENV` in the test, restore in `ensure`, call `SiteAddress.reset!` both sides).
- [ ] **Step 2:** run `PGGSSENCMODE=disable bin/rails test test/lib/site_address_test.rb`; expect `NameError: uninitialized constant SiteAddress`.
- [ ] **Step 3: implement** with `URI.parse` inside a rescue of `URI::InvalidURIError`; `Data.define(:scheme, :host, :port)` or a small class; no Rails dependency beyond `blank?` (use `to_s.strip.empty?` so the file loads before Active Support extensions are certain). The message of `Invalid`: `PUBLIC_HOST must be the site's address with its scheme, for example https://www.example.org (got: "<value>")`.
- [ ] **Step 4:** `PublicSite::Urls.configured_host` becomes `SiteAddress.current.origin`; keep its comment true. Run `PGGSSENCMODE=disable bin/rails test test/lib/site_address_test.rb test/models/public_site` and `bin/rails zeitwerk:check`; expect green. (`lib/` is not autoloaded in this app; the file is required explicitly, so Zeitwerk does not manage it.)
- [ ] **Step 5:** commit `feat: SiteAddress — the site's address parsed once from PUBLIC_HOST`.

### Task 2: `HostSettings` — hosts, HTTPS, mail links, boot messages

**Files:** Create `lib/host_settings.rb`, `test/lib/host_settings_test.rb`, `test/integration/host_settings_test.rb`. Modify `config/application.rb` (require), `config/environments/production.rb`.

**Interfaces — consumes:** `SiteAddress`. **Produces:**

```ruby
HostSettings.apply(config, address: SiteAddress.current, env: ENV)
# sets on `config`:
#   config.hosts               = [ address.host ]            only when configured (left untouched otherwise)
#   config.host_authorization  = { exclude: HostSettings::HEALTH_CHECK }  always
#   config.force_ssl           = address.https?
#   config.ssl_options         = { redirect: { exclude: HostSettings::HEALTH_CHECK } }
#   config.assume_ssl          = env["ASSUME_SSL"] == "1"
#   config.action_mailer.default_url_options = address.url_options   ({} when not configured)
HostSettings::HEALTH_CHECK   # ->(request) { request.path == "/up" }
HostSettings.announcement(address)  # the boot log line (String)
HostSettings.require_secret!(env)   # raises HostSettings::MissingSecret with the message below unless env["SECRET_KEY_BASE"] is present
```

- [ ] **Step 1: failing unit tests** (`test/lib/host_settings_test.rb`) against a fake config: `config = ActiveSupport::OrderedOptions.new; config.action_mailer = ActiveSupport::OrderedOptions.new; config.hosts = []`.
  - https address → `hosts == ["docs.example.org"]`, `force_ssl` true, `assume_ssl` false, mail options `{ host:, protocol: "https" }`.
  - http address → `force_ssl` false, hosts set.
  - not configured → `hosts` still `[]`, `force_ssl` false, mail options `{}`.
  - `env: { "ASSUME_SSL" => "1" }` → `assume_ssl` true; `"true"` and `"0"` → false.
  - `HEALTH_CHECK` is true for a request whose path is `/up`, false for `/up/x` and `/`.
  - `announcement`: configured https → `[ContentSpiel] Serving https://docs.example.org. Other host names are refused; plain HTTP is redirected.`; configured http → `[ContentSpiel] Serving http://… . Other host names are refused. The connection is not encrypted.`; not configured → `[ContentSpiel] PUBLIC_HOST is not set. Any host name is accepted and nothing is forced to HTTPS.`
  - `require_secret!({})` raises with a message containing `SECRET_KEY_BASE` and `bin/rails secret`, and not the word `credentials`; with a value it returns nil.
- [ ] **Step 2: failing integration tests** (`test/integration/host_settings_test.rb`, `ActiveSupport::TestCase` using `Rack::MockRequest`): build the stack by hand from a config that `HostSettings.apply` filled, around `inner = ->(env) { [200, { "content-type" => "text/plain" }, ["ok"]] }`:

```ruby
def stack(address, env = {})
  config = ActiveSupport::OrderedOptions.new
  config.action_mailer = ActiveSupport::OrderedOptions.new
  config.hosts = []
  HostSettings.apply(config, address: SiteAddress.parse(address), env: env)
  app = ->(_env) { [ 200, { "content-type" => "text/plain" }, [ "ok" ] ] }
  app = ActionDispatch::HostAuthorization.new(app, config.hosts, **config.host_authorization) if config.hosts.any?
  app = ActionDispatch::SSL.new(app, **config.ssl_options) if config.force_ssl
  Rack::MockRequest.new(app)
end
```

  Tests: under `https://docs.example.org` — `GET https://docs.example.org/` is 200 with a `strict-transport-security` header; `GET http://docs.example.org/` is a 301 to `https://docs.example.org/`; `GET https://evil.example/` is 403; `GET http://10.0.0.5/up` is 200 (no redirect, no refusal); a request with `HTTP_X_FORWARDED_HOST: "evil.example"` and the right `Host` is 403 (Rails checks both). Under `http://localhost:3030` — `GET http://localhost:3030/` is 200 with no HSTS header; `GET http://evil.example/` is 403. Under `nil` — `GET http://anything.example/` is 200.
- [ ] **Step 3:** run both files; expect `NameError: uninitialized constant HostSettings`.
- [ ] **Step 4: implement** `lib/host_settings.rb`; require it in `config/application.rb` beside `site_address`.
- [ ] **Step 5: `production.rb`.** Replace the commented `assume_ssl`, `force_ssl`, `ssl_options`, `config.hosts` and `host_authorization` blocks and the literal `default_url_options` line with:

```ruby
  # Everything a host decides about the site's address: which host names
  # are answered, whether HTTPS is forced, and the address in mailed links.
  # One variable, PUBLIC_HOST (see lib/host_settings.rb and the guide's
  # "What ContentSpiel asks of its host"). A value that is not an address
  # stops the boot here, with a message that names the variable.
  HostSettings.apply(config)
```

  and, in `config/application.rb` inside the `Application` class, an `initializer "content_spiel.host_announcement", after: :initialize_logger` that, in production only, calls `HostSettings.require_secret!(ENV)` unless `ENV["SECRET_KEY_BASE_DUMMY"]` is set (asset precompilation in the Dockerfile uses the dummy) and logs `HostSettings.announcement(SiteAddress.current)` at `info`. Check `Dockerfile` for the dummy variable's exact name before writing the condition.
- [ ] **Step 6: prove production boots.** In a `mktemp -d` scratch directory nothing is needed; run from the worktree:
  `SECRET_KEY_BASE_DUMMY=1 RAILS_ENV=production PUBLIC_HOST=https://docs.example.org bin/rails runner 'puts Rails.application.config.hosts.inspect, Rails.application.config.force_ssl' 2>&1 | tail -3` → `["docs.example.org"]` and `true`;
  the same with `PUBLIC_HOST=nonsense` → exits non-zero and prints the `PUBLIC_HOST must be…` message;
  the same with no `PUBLIC_HOST` → `[]`-like hosts and `false`.
  If production cannot boot here for an unrelated reason (database), run with `DATABASE_URL` pointing at the development database and say so in the report; do not weaken the check.
- [ ] **Step 7:** `bin/rubocop lib config test/lib test/integration/host_settings_test.rb`, the two test files, `bin/rails zeitwerk:check`. Commit `feat: hosts, HTTPS and mailed links follow PUBLIC_HOST`.

### Task 3: head tags from the site's address, and a canonical link

**Files:** Modify `app/controllers/public_controller.rb`, `app/controllers/preview_controller.rb` (read it: it must stay as it is, preview addresses are the request's), `app/views/layouts/application.html.erb`, `app/views/pages/_seo_meta.html.erb`. Create `test/integration/public_head_address_test.rb`, `test/lib/public_address_guard_test.rb`.

**Interfaces — consumes:** `PublicSite::Urls.configured_host` (Task 1). **Produces:** `public_urls` built with `host: PublicSite::Urls.configured_host || request.base_url`; a `<link rel="canonical" href="…">` in the public layout's head for a page or post that was found.

- [ ] **Step 1: failing integration tests** (`ActionDispatch::IntegrationTest`; set `ENV["PUBLIC_HOST"]` and call `SiteAddress.reset!` in `setup`, restore both in `teardown`):
  - with `PUBLIC_HOST=https://docs.example.org`, `get "/about", headers: { "Host" => "evil.example", "X-Forwarded-Host" => "evil2.example" }` (use a live fixture page's real path; read `test/fixtures/pages.yml` and `public_paths.yml`): the body's `og:url`, every `hreflang` `href` and the `canonical` `href` start with `https://docs.example.org`, and the body contains neither `evil.example` nor `evil2.example`.
  - the canonical link is the page's own address in the language shown, and a request with `?utm=1` gives the same canonical without the query.
  - a post's permalink has a canonical link to itself.
  - a 404 response has no `rel="canonical"`.
  - with no `PUBLIC_HOST`, the three follow the request's host (`www.example.com` in integration tests).
  - `/preview/...` responses keep the request's origin and have no canonical link (sign in as the fixtures' admin; look at an existing preview test for how).
- [ ] **Step 2:** run; expect the `evil.example` assertions to fail.
- [ ] **Step 3: implement.** `public_urls` as above. In `_seo_meta.html.erb` `og:url` becomes `public_urls.url_for(post || page) || request.original_url` — read how the partial gets `page`/`post` and keep its comment true (the address is the record's in the language shown). In the layout, inside the existing `if (alternate_record = @post || @page)` block and only when `!public_urls.preview?`, add `<link rel="canonical" href="<%= … %>">` from `public_urls.url_for(alternate_record)`, skipped when nil.
- [ ] **Step 4: source guard** `test/lib/public_address_guard_test.rb`: scan `app/views/layouts/application.html.erb`, `app/views/layouts/public/**`, `app/views/pages/**`, `app/views/posts/**` (whatever public view folders exist; derive the list from `PublicController`'s descendants' view paths if that is simple, else list them with a comment) and `app/components/blocks/**`, `app/components/public*/**` for `request.original_url`, `request.base_url`, `request.host`, `request.url`, `request.protocol`, `root_url`, `_url(`; each match fails unless its `file:line-content` is in an `ALLOWED` hash with a reason. The one expected entry is the `og:url` fallback. The test also fails on an `ALLOWED` entry that matches nothing.
- [ ] **Step 5:** run the new files plus `PGGSSENCMODE=disable bin/rails test test/integration test/lib`; fix what the change breaks (tests that asserted `og:url` with a query string, if any: report each one you rewrite). Commit `feat: every address a public page prints is the site's own, and pages name their canonical address`.

### Task 4: the mailed link's origin

**Files:** Modify `app/mailers/passwords_mailer.rb`, `app/controllers/admin/passwords_controller.rb`, `test/mailers/passwords_mailer_test.rb` (create if absent), the controller's integration test.

**Interfaces — produces:** `PasswordsMailer.reset(user, origin: nil)`; the controller passes `origin: request.base_url` only when `SiteAddress.current.configured?` is false. Inside the mailer: `@url_options = SiteAddress.current.configured? ? SiteAddress.current.url_options : SiteAddress.parse(origin).url_options`; when that is empty the mail is not built: `Rails.logger.warn "[ContentSpiel] A password reset mail was not sent: no site address is known. Set PUBLIC_HOST."` and the method returns without calling `mail` (Action Mailer then delivers nothing). The views build the link with `**@url_options` (Task 7 changes the link's shape; here only its origin).

- [ ] **Step 1: failing tests:** configured address → the mail's link starts with it, whatever `origin:` says; not configured, `origin: "http://localhost:3000"` → the link starts with that; neither → `ActionMailer::Base.deliveries` stays empty and the log line is written (capture with a `StringIO` logger); the token never appears in that log line. Controller test: `post` to create with a known address enqueues the mail with `origin` only when no address is configured.
- [ ] **Step 2–4:** run (fail), implement, run (pass). The job serialises `origin` as a plain string argument.
- [ ] **Step 5:** commit `fix: a mailed reset link carries the site's address, never example.com`.

### Task 5: the system checks and the plain-HTTP notice

**Files:** Modify `app/models/setup/system_check.rb`, `app/controllers/admin/system_status_controller.rb`, `app/controllers/setup_controller.rb` (both pass the request's facts), `app/views/layouts/admin.html.erb`, the sign-in view (`app/views/admin/sessions/new.html.erb`; verify the path), `config/locales/admin/ui.en.yml`. Create `app/components/admin/ui/insecure_notice_component.rb` + `.html.erb`, their tests.

**Interfaces — produces:**

```ruby
Setup::SystemCheck.new(..., address: SiteAddress.current, request_ssl: nil, production: Rails.env.production?)
# run => [ site_address, https, storage, image_processing, background_jobs, mail ]
#   "Site address": ok "This site answers at <origin>."  |  warning "No site address is set. Any host name is accepted, and addresses in pages and mails follow the request." command: "PUBLIC_HOST=https://www.example.org"
#   "HTTPS": production only (omitted from the list otherwise, and omitted when request_ssl is nil);
#            ok "This page was reached over an encrypted connection."  |  warning "This page was reached over plain HTTP. Passwords and sessions can be read on the way. Set PUBLIC_HOST to an https address."
Admin::Ui::InsecureNoticeComponent.new(request:, production: Rails.env.production?)  # render? is production && !request.ssl?
```

  The mail check's `mail_host` default keeps working: with an address configured it is that host.

- [ ] **Step 1: failing tests:** `test/models/setup/system_check_test.rb` gains the cases above (address configured / not; `request_ssl` true / false / nil; `production` false omits HTTPS). Component test: renders the notice text (a locale key `admin.components.ui.insecure_notice.body`: "This connection is not encrypted. Passwords and sessions can be read on the way. Set PUBLIC_HOST to an https address.") with `role="alert"` when production and not SSL; renders nothing otherwise. Integration: the sign-in page and a CS Studio page show nothing in the test environment.
- [ ] **Step 2–4:** fail, implement, pass. The component uses the design system's existing warning tokens (read `docs/reference/design-system.md`; look for an existing banner or callout to match, e.g. the preview bar or the hold strip). In the shell it is rendered only for someone who holds the settings permission (use the same check the System status link in the navigation uses); on the sign-in page for everyone. Add the component to `test/lib/admin_i18n_test.rb`'s converted list if that list is per component.
- [ ] **Step 5:** run `PGGSSENCMODE=disable bin/rails test test/models/setup test/components/admin/ui test/integration/admin test/lib`. Commit `feat: System status says which address the site answers at and whether the connection is encrypted`.

### Task 6: telemetry is quiet by default and scrubs paths

**Files:** Modify `config/initializers/opentelemetry.rb`. Create `lib/telemetry/path_scrubber.rb`, `test/lib/telemetry/path_scrubber_test.rb`, `test/lib/telemetry_exporter_test.rb`.

**Interfaces — produces:**

```ruby
Telemetry.exporter_kind(env, rails_env)  # :memory (test) | :otlp (endpoint set) | :console (OTEL_CONSOLE == "1") | :none
Telemetry::PathScrubber.scrub(path)      # "/cs-studio/password/abc123/edit" => "/cs-studio/password/[FILTERED]/edit"; "/cs-studio/password/abc123" => "/cs-studio/password/[FILTERED]"; anything else unchanged. Built from ContentSpiel::ADMIN_PATH, not a literal.
Telemetry::PathScrubber::Processor       # a span processor whose on_start/on_finish rewrite the attributes "url.path", "http.target", "url.full", "http.url" with scrub
```

- [ ] **Step 1: failing tests:** `exporter_kind` for each row of the table, including that an endpoint wins over `OTEL_CONSOLE` and that `:none` is the answer in production and in development with neither variable. `scrub` for the two shapes, for `/cs-studio/password/edit` (unchanged: the new route), for `/cs-studio/password/new` (unchanged), and for a full URL with the token in it. A processor test: record a span with `url.path` set through the in-memory exporter the test environment already has (`Rails.application.config.x.otel_test_exporter`) and read the finished span's attribute. Read how an existing telemetry test does it (`grep -rn otel_test_exporter test`).
- [ ] **Step 2–4:** fail, implement, pass. In the initializer: when the kind is `:none`, do not call `OpenTelemetry::SDK.configure` at all (the API's no-op tracer stays in place, so any `OpenTelemetry.tracer_provider` call in the app still works; grep `app lib` for such calls and run their tests). Keep every existing comment that is still true, and rewrite the header's list of four cases. The scrubber's processor is added first, before the exporting processor. Attributes of a finished span are frozen in the SDK: scrub in `on_start` for attributes present at start and wrap the exporter (`export(spans)` maps over span data with `attributes` replaced) for those set later; choose what the SDK's version in `Gemfile.lock` allows and say which in the report.
- [ ] **Step 5: prove the quiet.** `bin/rails runner 'puts 1' 2>&1 | wc -l` in development prints a handful of lines, not hundreds; `OTEL_CONSOLE=1 bin/rails runner 'User.count' 2>&1 | grep -c SpanData` is at least 1. Put both numbers in the report.
- [ ] **Step 6:** commit `fix: telemetry prints nothing unless asked, and no span carries a reset token`.

### Task 7: the reset token leaves the address

**Files:** Modify `config/routes.rb` (the two password routes), `app/controllers/admin/passwords_controller.rb`, `app/views/admin/passwords/edit.html.erb`, `app/views/passwords_mailer/reset.{html,text}.erb`, `config/locales/admin/` (the file that holds the passwords views' strings; if those views still hold literals, add keys only for what you add). Create `app/javascript/controllers/admin/shell/reset_token_controller.js`, `test/system/admin/password_reset_test.rb`; modify the passwords integration test.

**Interfaces — produces:**

- Routes: `get "password/edit" → passwords#edit` as `admin_edit_password`; `patch "password" → passwords#update` as `admin_update_password` (check it does not collide with `resource :password, only: %i[new create]`: fold `edit` and `update` into that resource if that gives the same paths); `get "password/:token/edit" → passwords#legacy`, which redirects to `admin_edit_password_path` with status 302 and no parameter.
- Mail link: `admin_edit_password_url(**@url_options, anchor: @user.password_reset_token)`.
- `edit`: no lookup. Renders the form with `data-controller="admin--shell--reset-token"`, a hidden `token` field as the controller's target, a hidden-by-default "incomplete link" message target with a link to `new_admin_password_path`, and a `<noscript>` line.
- `update`: `User.find_by_password_reset_token!(params[:token])`; on `InvalidSignature` (or a blank token) redirect to `new_admin_password_path(expired: 1)`; on a validation failure re-render `edit` with status 422 and the token kept in the hidden field of THAT response only (it is in a response body to the person who holds it, not in a URL); success as today.
- The Stimulus controller, complete:

```javascript
import { Controller } from "@hotwired/stimulus"

// The password-reset token arrives after the "#" of the mailed link, which
// a browser never sends to a server: so it is in no request line, no span
// and no proxy log. This moves it into the form's hidden field and takes it
// out of the address bar; the form then carries it in its body, which the
// log filters. A page opened without it says the link is incomplete.
export default class extends Controller {
  static targets = ["token", "form", "incomplete"]

  connect() {
    const token = window.location.hash.slice(1)
    if (token) {
      this.tokenTarget.value = token
      history.replaceState(history.state, "", window.location.pathname + window.location.search)
    }
    const missing = !this.tokenTarget.value
    this.formTarget.hidden = missing
    this.incompleteTarget.hidden = !missing
  }
}
```

- [ ] **Step 1: failing tests.**
  - Integration: the mail's link matches `%r{/cs-studio/password/edit#\S+\z}` and its path holds no token; `get "/cs-studio/password/<any>/edit"` redirects to `/cs-studio/password/edit` and the `Location` holds no token; `patch` with a valid token in the body changes the password and ends the user's sessions (as the existing test asserts); with a tampered token redirects to `new?expired=1` and changes nothing; with a too-short password answers 422 and the body's hidden field holds the token.
  - "no logged line holds the token": swap `Rails.logger` for a `StringIO`-backed logger around the `get` of the old route and the `patch`, and assert the token string is absent from the captured log.
  - System (`test/system/admin/password_reset_test.rb`): request a reset for a fixture user, take the link from `ActionMailer::Base.deliveries.last` (use `perform_enqueued_jobs`), `visit` it, wait for the form (`assert_selector "form:not([hidden])"`), assert `page.current_url` has no `#` and no token, fill the two password fields, submit, land on the sign-in page with the notice, and sign in with the new password. A second test: visiting `/cs-studio/password/edit` with no fragment shows the incomplete-link message and no form. Follow the file's siblings for helpers (`await_admin_controllers` may not apply on this layout; wait for the form instead).
- [ ] **Step 2–4:** fail, implement, pass. `test/lib/source_layout_test.rb` must stay green (the identifier `admin--shell--reset-token` has its file). The `product` layout must load Stimulus controllers under `admin/shell`: check how the sign-in page gets its `password_field` controller and whether the admin controllers are loaded on that layout; if not, the controller belongs where that layout's controllers are (the top level `controllers/`, identifier `reset-token`) and the plan's name changes: say so in the report.
- [ ] **Step 5:** `bin/rails tailwindcss:build`, then `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test:system test/system/admin/password_reset_test.rb` and the sign-in system tests. Commit `fix: a password-reset token is never part of an address a server sees`.

### Task 8: small things and the documents

**Files:** `config/initializers/setup_token.rb`, `config/initializers/admin_path.rb`, `docs/reference/` (a new `hosting.md`, and a line in `page-tree-and-routing.md` where `PUBLIC_HOST` is described), `CLAUDE.md`, `docs/roadmap.md` (alone in its own commit, after re-reading it), the spec ("As built").

- [ ] **Step 1: setup token.** Failing test first (`test/initializers/setup_token_test.rb` or beside the existing one: find how the line is tested today): with `SETUP_TOKEN` set the message is `[ContentSpiel] Setup is not complete. Open /setup and enter the setup token you set in SETUP_TOKEN.` and holds no token; without it the line is as today. To make it testable, move the message into `Setup::Token.log_line` (read `app/models/setup/token.rb` for how `SETUP_TOKEN` is read) and have the initializer log that.
- [ ] **Step 2:** correct the `/cable` comment in `config/initializers/admin_path.rb`: Action Cable is mounted at `/cable` by Rails, and it stays a reserved admin path.
- [ ] **Step 3: `docs/reference/hosting.md`**: what a host sets (the seven variables, what each does, what happens without it), how `production.rb` gets its values (`HostSettings.apply`), why the address is not a setting, the reset link's shape and why, what a change can break silently. In `CLAUDE.md`: an index line ("Before changing how production reads its address, its HTTPS settings, telemetry's exporter or the reset link (`lib/site_address.rb`, `lib/host_settings.rb`, `config/environments/production.rb`, `config/initializers/opentelemetry.rb`, `Admin::PasswordsController`), read `docs/reference/hosting.md`") and rules, each naming its test: an absolute address in a public view comes only from `PublicSite::Urls` (`test/lib/public_address_guard_test.rb`); no credential is part of a route's path or query (the reset token travels in the fragment and the form's body); `production.rb` decides nothing about hosts or HTTPS itself. Correct the "Deploy" and telemetry sentences that this work makes untrue.
- [ ] **Step 4: roadmap** (own commit): mark T-03, T-06, T-07, T-08, T-13, T-14 and P-08 of the hosting gap list as done by this work, leave the rest, and add the three parts that follow (mail; sitemap and starting up; the wizard) in order if they are not there in those words.
- [ ] **Step 5:** `bin/rubocop`, `bin/brakeman`, `bin/rails zeitwerk:check`, `PGGSSENCMODE=disable bin/rails test`. Report, for the pull request: every on-screen string added, with where it appears; the guide pages affected (the new "What ContentSpiel asks of its host", the install page, signing in, System status); every existing test rewritten.
- [ ] **Step 6:** commit `docs: what ContentSpiel asks of its host`.
