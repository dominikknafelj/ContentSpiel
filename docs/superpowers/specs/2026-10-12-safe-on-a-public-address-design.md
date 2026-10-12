# Safe on a public address

Date: 2026-10-12. Status: design, approved in conversation; the plan follows. Built the same day: the last section, "As built", lists where the code departed from this design.

## Why

The dry run of the documentation site (2026-10-11, `contentspiel-docs` `GAPS.md`) found 25 gaps between `main` and a site a stranger can put on a public address. They are worked in four parts: this one, then mail, then the sitemap and starting up, then the setup wizard. Theming, a published image and loading content are their own work.

This part closes the gaps that make a public address unsafe: T-06 (telemetry prints every span to the production log, and a password-reset token is in it), T-07 (the `Host` header is trusted), T-08 (no HTTPS settings), T-13 (the setup token in the log), P-08 (CS Studio works over plain HTTP with no notice), T-03 (a misleading error without `SECRET_KEY_BASE`) and T-14 (a stale comment).

## What a person gets

- An administrator sets one variable, `PUBLIC_HOST`, to the site's address with its scheme (`https://docs.example.org`). Everything below follows from it.
- A visitor, a search engine and a link preview see the site's own address in every absolute address a page prints, whatever `Host` a request carried.
- A request for another host is refused.
- With an `https://` address: plain HTTP is redirected, the session cookie is `Secure`, HSTS is sent.
- The production log holds no spans and no credential that this application can keep out of it.
- Someone who reaches CS Studio over plain HTTP in production is told.

## Decisions

1. **The site's address is an environment variable, not a setting.** Refusing hosts and the HTTPS settings are decided when the application starts, before the database is read; a wrong value typed into a Settings screen could lock everyone out with no screen left to fix it. The wizard (part four) will show the value read-only and say where it comes from. (Owner's decision, 2026-10-12.)
2. **HTTPS follows the address's scheme.** No `FORCE_SSL` variable: one fact, one place.
3. **A production start without `PUBLIC_HOST` works as today** (any host accepted, addresses follow the request), because the wizard must be reachable on a fresh server. System status and the wizard's system check say so as a warning.
4. **The reset token leaves the URL's path and query.** Rails' log, the spans and the proxy's own access log each record a request's path, and the proxy's log is not this application's to filter. The token travels after a `#`, which a browser never sends.
5. **Telemetry prints nothing by default, in development too.** `OTEL_CONSOLE=1` turns the console exporter on.

## 1. The site's address

`PublicSite::Urls.configured_host` stays the one reader of the variable (`PUBLIC_HOST`, else `SITEMAP_HOST` as the old name). A new value object, `SiteAddress` (`app/values/site_address.rb`), parses it once: `origin` (scheme, host, port), `host`, `https?`, `configured?`. A value that is not an absolute `http` or `https` address with a host stops the boot in production with a message naming the variable and an example; a trailing slash or path is dropped.

Used for:

- **Host authorisation.** `config.hosts` is the address's host when one is configured, in production only. The health check `/up` is excluded (the proxy asks it by IP). The refusal is Rails' own (a 403 from `ActionDispatch::HostAuthorization`); its response in production carries no detail.
- **Head tags.** `og:url` (`app/views/pages/_seo_meta.html.erb`, today `request.original_url`), the `hreflang` alternates in the public layout, and a new `<link rel="canonical">` are built from `PublicSite::Urls` with the configured origin; with none configured they fall back to the request's origin, as CS Studio's "Copy address" does today. The canonical link is the page's or post's own address in the language being shown, without query string; a page that is not found has none.
- **Mail links.** `config.action_mailer.default_url_options` in production comes from the address (host, port, protocol) instead of the literal `example.com` it is today, and the one mail that exists, the password reset, builds its link from the configured address in every environment; with none configured it uses the origin of the request that asked for it, handed to the mailer as a string and parsed there, in development and test only. In every other environment (production, and any that is not development or test: the rule is an allow-list) with no address configured the mail is not built and a line in the log says to set `PUBLIC_HOST`, because that origin is whatever `Host` the request named and such a site refuses none: anyone could have a valid reset link for a known account mailed to its owner pointing at a host of their own.
- **The sitemap** already reads it.

`Setup::SystemCheck` gains a check "Site address": ok with the address; a warning "No site address is set. Any host name is accepted, and addresses in pages and mails follow the request." with the variable's name as its command. It appears on System status and in the wizard's system check, which both render the same results.

## 2. HTTPS

When the address is `https`:

- `config.force_ssl = true` with `/up` excluded from the redirect; this gives the redirect, the `Secure` cookie and HSTS (Rails' defaults: one year, subdomains not included unless the host opts in later).
- `config.assume_ssl = true` only when `ASSUME_SSL=1`, for a proxy that ends TLS and does not send `X-Forwarded-Proto`. Kamal's proxy and Thruster send it, so the default is off.

When the address is `http` or absent, nothing is forced. In production, a CS Studio page (the shell and the sign-in page) then shows a notice when `request.ssl?` is false: "This connection is not encrypted. Passwords and sessions can be read on the way. Set PUBLIC_HOST to an https address." It is shown to everyone on the sign-in page and in the shell to people with the settings permission. Development and test never show it.

`Setup::SystemCheck` gains "HTTPS": ok when the request arrived over HTTPS; a warning otherwise, production only.

## 3. Telemetry

`config/initializers/opentelemetry.rb` picks, in order: test → in-memory (unchanged); `OTEL_EXPORTER_OTLP_ENDPOINT` set → OTLP, batched (unchanged); `OTEL_CONSOLE=1` → console; otherwise no exporter and the SDK is not configured at all (no instrumentation installed, so no cost).

A span must not carry a credential even when exported. The Rack instrumentation's `url.path` (and `http.target`, `url.full` where present) is scrubbed by a span processor that replaces the token segment of the two password routes with `[FILTERED]`; after section 4 no route carries a token in its path, and the scrubber stays for the old route's redirect (below).

## 4. The password-reset link

Today: `GET /cs-studio/password/<token>/edit`, `PATCH /cs-studio/password/<token>`.

New:

- The mail's link is `/cs-studio/password/edit#<token>`.
- `GET password/edit` renders the form with no token and no lookup. A Stimulus controller (`admin--shell--reset-token`, `app/javascript/controllers/admin/shell/reset_token_controller.js`) reads `location.hash`, puts it in a hidden field `token`, and removes the fragment from the address with `history.replaceState`. With no fragment the page says the link is incomplete and offers to request a new one.
- `PATCH password` carries `token` in the body. `token` joins `filter_parameters`. An invalid or expired token is answered as today ("link is invalid or has expired"), after the form is sent, not before.
- The old `GET password/:token/edit` redirects to `password/edit` WITHOUT the token (a redirect cannot carry a fragment the server never saw, and must not log more than it has to): the page then says the link is incomplete. Reset links live 15 minutes, so links mailed before a deploy are an accepted loss. The old `PATCH password/:token` is removed.
- The same audit, session and rate-limit behaviour as today (`Users::UpdatePassword`).

The cost: resetting a password needs JavaScript. CS Studio needs it everywhere else. The page says so in a `<noscript>`.

## 5. Small things

- **Setup token.** When `SETUP_TOKEN` is set by the host, the log line names no token ("…enter the setup token you set in SETUP_TOKEN"). Otherwise it is printed as today: that is how a stranger gets it, and it is gone once setup is finished.
- **`SECRET_KEY_BASE`.** A production start without it stops with a message that names the variable and how to make a value (`bin/rails secret`), instead of pointing at credentials.
- **`config/initializers/admin_path.rb`**: the comment about `/cable` says what is true.
- **`config.hosts` in development and test** is untouched.

## What this does not do

Mail delivery and its test (part two). The sitemap being built by the application, the four database addresses, the entrypoint, background jobs (part three). The wizard asking for or showing the address beyond the system check (part four). `Content-Security-Policy` changes. Scrubbing a proxy's own log.

## Risks

- **Locking out by a wrong address.** A typo in `PUBLIC_HOST` refuses every request. Mitigations: the boot stops on a value that does not parse; `/up` stays reachable; the refusal page in production says nothing, so the guide page and the boot log line ("Serving https://… ; other host names are refused") are where a person finds out. The boot log line is part of this work.
- **HSTS is sticky.** A browser that saw it refuses plain HTTP for a year. That is the point, and the guide page says it.
- **A fragment is not sent to the server**, so nothing on the server can tell a truncated link from a missing one. The page's message covers both.

## Testing

- `SiteAddress`: parsing, the refusals, `https?`.
- Integration, production-like configuration built in the test: a request for another host is refused and `/up` is not; `og:url`, `hreflang` and `canonical` carry the configured origin under a foreign `Host`; with none configured they follow the request.
- HTTPS: the cookie's `Secure` flag, the HSTS header and the redirect under an `https` address, none under `http`; the notice appears on the sign-in page and in the shell only when it should.
- Telemetry: no exporter and no output without the variables; the scrubber replaces the token of the old route.
- The reset flow as a browser test: the mailed link, the fragment gone from the address, a new password set, and no logged line (captured Rails log) holding the token; an integration test that the old route redirects without it.
- The system checks' results in each state.
- Guards: nothing under `app/views` or `app/components` of the public site reads `request.original_url`, `request.base_url` or `request.host` for an address it prints (a source guard with named exceptions, in the style of `test/lib/public_readers_test.rb` on the drafts branch).

## Documentation

New guide page in `contentspiel-docs`, administrators: "What ContentSpiel asks of its host", with `PUBLIC_HOST`, `ASSUME_SSL`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_CONSOLE`, `SETUP_TOKEN`, `SECRET_KEY_BASE`, what each does and what happens without it. Affected: the install page (draft), "Signing in" (the reset link), the System status page. In this repository: `docs/reference/` gains what a change here can break silently, and `CLAUDE.md` its rules (absolute addresses only through `PublicSite::Urls`; no token in a path).

## As built

Built 2026-10-12 on the branch `safe-address`. Where the code departed from the sections above, and why. The description of what is there now is `docs/reference/hosting.md`; where this section and a section above differ, this one is what was built.

1. **The reset mail has no fallback outside development and test** (§1, "Mail links"; the section's text was corrected during the build). The design had the request's origin as the link's origin wherever no address is configured. That origin is whatever `Host` the request named, and a site with no address refuses none: anyone could have a valid reset link for a known account mailed to its owner, pointing at a host of their own (password-reset poisoning). So the request's origin is used in development and test only, by an allow-list (`PasswordsMailer.request_origin_used?` is `env.local?`, so a staging environment nobody named fails closed), and everywhere else a site without `PUBLIC_HOST` builds no reset mail and logs one line that says to set it. The cost: a production site without `PUBLIC_HOST` cannot reset a password by mail, and its request page still says a link was sent; the console fallback exists, and the Mail part makes the page say so.
2. **HSTS is written out: `max-age=31536000` and nothing more** (§2). The section says "Rails' defaults: one year, subdomains not included". That was wrong about Rails, whose default is two years with subdomains. The design's values stand and are set explicitly (`HostSettings::HSTS`: one year, no `includeSubDomains`, no `preload`), because `includeSubDomains` would force HTTPS on whatever else a host runs under the same name, for as long as a browser remembers it. A site that wants its subdomains covered gets weaker HSTS than it might want.
3. **A secret in the credentials starts production too** (§5). The design asked for `SECRET_KEY_BASE` as the variable. `HostSettings.require_secret!` accepts the variable or, when the variable is not set, a `secret_key_base` in the credentials file that `RAILS_MASTER_KEY` opens, as Rails itself does: the Kamal configuration this repository ships supplies the secret exactly that way. A variable that is set but blank is refused even then, and credentials that cannot be read are named by the error's class, never its text. The message never says "credentials" unless a credentials file could not be read. The cost: someone whose master key is what is wrong is told the secret is missing.
4. **No query string leaves in a span** (§3). The design scrubbed the token segment of the two password routes. The scrubber also replaces `url.query` whole and cuts `http.target`, `url.full` and `http.url` at their first `?`: a request answered before a controller keeps its query unfiltered, a note's quote travels in a query string as `note_quote`, and a note's text reaches no log line. A tracing backend therefore shows no query at all. The segment rule is also wider than the two routes (any segment after `<admin>/password/` but a final `new` or `edit`), because a path is recorded before the router has said whether it is a route. And scrubbing is a processor's `on_start` plus a wrapper around the exporter, not `on_finish`: the SDK freezes a span's attributes before that hook.
5. **A middleware scrubs the old reset addresses** (§4), which the design did not have. `OldResetAddress` (`lib/old_reset_address.rb`), first in the stack, replaces the token segment of `<admin>/password/<token>/edit` and `<admin>/password/<token>` in the request before Rails reads it. A redirecting route alone does not keep the token out of the log: Rails writes the request's first line before the router is asked, and for the old form's address, which has no route any more, the routing error's line as well. The design's test "no logged line holds the token" could not pass without it.
6. **The script is a top-level controller, `reset-token`** (`app/javascript/controllers/reset_token_controller.js`), not `admin--shell--reset-token` (§4). The reset page is drawn in the `product` layout, which loads only the `application` entry point, where no admin controller is registered. It does two things the design did not name: the form is drawn hidden by the server until a token is there, and the hidden field is emptied on `turbo:before-cache` and `pagehide`, because writing a hidden input's value writes its attribute and Turbo's snapshot and the back/forward cache would keep the token. The form's answers are `Cache-Control: no-store`, and a refused password is a 422 of the form itself with the token in its field, not a redirect, which could carry it only in an address or the session.
7. **The plain-HTTP notice is in the setup wizard too** (§2). The design named the sign-in page and the shell. The wizard takes the setup token and the first account's password, so the `setup` layout draws the notice for everyone on every wizard page. In the shell it is shown to a holder of `settings.manage` or of `system_status.view` (the design said "the settings permission"; the plan said the right that opens System status; the union was ruled). On the `product` layout it also covers both password pages.
8. **The boot's announcement is several lines, not one** (Risks). `HostSettings.announcement` returns an Array: what is served and what is refused; that the host match is exact (`www.` and other subdomains are refused, which is the surprise; the clause is left out for an IP address, `localhost` or any single label); a line for `ASSUME_SSL=1`; and one more when `ASSUME_SSL=1` meets an http address, which contradict each other. With `RAILS_LOG_LEVEL=warn` none is printed.
9. **With no address configured the public ETag includes the request's origin** (§1, "Head tags"), which the design did not mention. The fallback writes the request's origin into the head (`og:url`, `hreflang`, the canonical link), so without it a 304 could confirm a body printed under another host. With an address configured the ETag is built from the keys it had.
10. **`SiteAddress` is in `lib/`, not `app/values`, and is stricter than "an absolute http or https address with a host"** (§1). `config/environments/production.rb` runs before autoloading and cannot reach a class under `app/`. Also refused: user info, a port out of range, whitespace or a control character, a host that is not ASCII, and a host that is not a host name (a leading dot would open every subdomain in `config.hosts`). Its refusal never repeats the value and carries no cause, since the message goes to the boot log and a value can hold a password. `SITEMAP_HOST` alone turns on everything `PUBLIC_HOST` does.
11. **The "Site address" warning has two wordings, neither the design's** (§1). The design's sentence, "addresses in pages and mails follow the request", is true in development and test only, after item 1. Elsewhere the warning says that password reset mails are not sent until the address is set. The "Outgoing mail" warning names the missing address when a mail server is set and the address is why no reset mail goes out.
12. **`OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` counts as an endpoint** (§3): the exporter reads it ahead of the general variable, and someone who set only that one must not get silence. The guide's page therefore has seven variables, not six.
13. **A redirect's `Location` follows the request** and is not among the addresses built from the configured origin (§1). With an address configured a foreign `Host` is refused before any redirect is made; without one the request's host is all there is. The source guard covers what a page prints, controllers included, with two allowed lines.
14. **The localised homepage's canonical address is `/de/`**, and `/de` answers 200 with the same page: found while pinning the canonical link, left as it is (a redirect would be a routing change) and on the roadmap.
