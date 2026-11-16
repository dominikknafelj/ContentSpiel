# Alerting: errors, security alerts, readiness (issue #176)

Status: design, 2026-11-16. Owner's instruction: "you don't need my approval, just get going". Every decision below marked **Ruling** is the orchestrator's call, recorded for the owner to check.

## Why

From the SOC 2 gap analysis (CC7.2, A1.1): the site reports errors (`Rails.error.report`, ten call sites, plus Rails' own reports of unhandled request and job exceptions) and nothing subscribes; the audit log's notification has no security listener; `/up` checks only that the app booted; throttle trips leave no trace in the audit log. A self-hosted site's owner must learn that something is wrong without watching a log, and an uptime monitor must be able to tell "up" from "up but cannot reach its database".

## Goals

1. **Errors reach a person.** Every error report becomes a log line, a span event and an alert row; owners get it by mail, in a digest.
2. **Security alerts.** Chosen audit events become alerts mailed to owners: repeated failed sign-ins, owner changes, API token creation, bursts of `access.denied`, requests over a rate limit.
3. **Throttle trips are audited** (CS Studio's doors).
4. **A readiness check** that includes the database.
5. **Uptime monitoring, documented.**
6. **System status shows recent alerts**, so a site without mail still sees them.

## Non-goals and anti-goals

- No third-party error SaaS gem, no new outside service. (Anti-goal: a site that needs a Sentry account to learn about its errors.)
- No new environment variable. **Ruling R1**: thresholds and windows are constants; recipients are the owners. A host who wants more uses an uptime monitor and `Rails.error.subscribe` from a gem. Cost if wrong: a later PR adds variables (and rows in the hosting table).
- No new plugin registry. **Ruling R2**: a gem that wants errors uses Rails' own `Rails.error.subscribe`; a gem that wants audit events waits for #130 (registered actions, a frozen event value). Cost if wrong: an integrator asks for an alert hook later.
- Not #130. **Ruling R3**: the issue's comment asks to do #130 first so an alert subscriber does not take the raw audit row with its snapshot and run in the request. This design avoids both without #130: security alerts are found by a recurring job that reads chosen columns of `audit_events` (never `snapshot`, never `field_changes` beyond what a rule names), outside any request. #130 stays open for the plugin extension point. Cost if wrong: a later #130 may want the alert rules moved onto its event value; the rules are small and isolated (`Alerts::Rules`).
- No dismiss/acknowledge of an alert, no per-person alert settings, no alert UI beyond System status (read only).
- Never a secret or personal free text in an alert: no exception message, no request parameters, no IP address, no typed email address, no token value. Anti-goal: an alert mail that leaks what the audit log and the log were careful to keep.

## Constraints (from the repo)

- `Audit.record` is the one write path of the append-only audit log; a new action registers in `Audit::Sentence` (English in Ruby, `SPECIAL_ACTIONS` + a `when` in `special_parts`), is SILENT in `Editing::Signals` (automatic via `SPECIAL_ACTIONS`), joins `SECURITY_ACTIONS` and `NO_ACTOR` as it applies, and the tests `test/models/audit/sentence_test.rb` (both directions, the security list) and `test/models/editing/signals_test.rb` hold it. Probably `Dashboard::Feed::NOT_A_CHANGE` too.
- Mail: queue only through `ApplicationMailer.queue`; mailer args are records/ids, never secrets; check `MailSettings.current.ready?` first (pattern `SignInMailer.queue_alert`); `link_origin` rules for links; every line a `mail.*` key in `config/locales/mail.en.yml`; text and HTML parts; `docs/reference/mail.md` "The mails" list and count updated. `test/lib/mail_guards_test.rb`.
- Telemetry: spans only through `Telemetry.in_span`; names in `Telemetry::SPANS`, attribute keys in `Telemetry::ATTRIBUTES`; direct `add_event` only inside `lib/telemetry.rb` or a `WRITERS` file (`test/lib/telemetry_spans_test.rb`).
- Recurring jobs: `config/recurring.yml` production, development and test blocks agree (`test/lib/job_queues_test.rb`).
- Queries: Active Record, then Arel through `SqlNodes`, then SQL with `# sql:` reason, as named scopes/query methods.
- `/up` is exempt from host authorization and the SSL redirect through `HostSettings::HEALTH_CHECK` (`lib/host_settings.rb`); kamal-proxy's healthcheck uses `/up` by default (`config/deploy.yml` sets none).
- Admin strings are i18n keys (`config/locales/admin/`); the look of anything new comes from the design agent's Design System card, never decided alone.
- The lock-order rule (settings row first) does not apply: nothing here writes a page, post, block or the settings row.

## Design

### 1. The alert store: `alerts` table, `Alerts::Alert` model

One row per alert, written only by jobs (like mail's state columns: a job's state, no audit event; **Ruling R4**: writing an alert is not audited, since it is derived from the log or from an error and auditing it would add a row per row).

Columns: `kind` (string, not null; one of `Alerts::Alert::KINDS`: `error`, `sign_in_failures`, `owner_changed`, `token_issued`, `access_denied_burst`, `request_limited`), `fingerprint` (string, not null, unique index), `details` (jsonb, not null, default `{}`; fixed keys per kind, below), `occurrences` (integer, not null, default 1), `first_seen_at`, `last_seen_at` (datetime, not null; index on `last_seen_at`), `mailed_at` (datetime, null), timestamps.

`details` keys, and nothing else:
- `error`: `error_class` (class name), `place` (first backtrace frame inside `Rails.root`, as `app/models/page.rb:120`, or nil), `source` (Rails' report source string, e.g. `application.action_dispatch`), `handled` (boolean).
- `sign_in_failures`: `window_start` (ISO time), `failed` (count), `locked` (count of `session.locked` in the window).
- `owner_changed`: `audit_event_id`, `subject_label`, `actor_name` (the actor's name as the audit log tells it, or nil for the system/console), `now_owner` (boolean).
- `token_issued`: `audit_event_id`, `token_name`, `group_name`, `actor_name`.
- `access_denied_burst`: `window_start`, `denied` (count), `actors` (count of distinct actors).
- `request_limited`: `window_start`, `limited` (count of `request.limited` events), `limits` (sorted distinct limit names).

Retention: rows whose `last_seen_at` is older than 30 days are deleted by the check job (`Alerts::Alert.expired`).

### 2. Errors: `Alerts::ErrorSubscriber`

Registered with `Rails.error.subscribe` in `config/initializers/alerts.rb` (named by a block that looks the constant up each time, as `config/initializers/editing.rb` does, so a reload is followed; or Rails' subscriber object API, the builder's choice as long as a development reload is followed).

`report(error, handled:, severity:, context:, source:)`:
- Ignores an error Rails would answer with a 4xx (`ActionDispatch::ExceptionWrapper.status_code_for_exception(error.class.name) < 500`: not found, a bad request, a stale form). **Ruling R5**: a 404 is a visitor's typo, not an alert.
- Ignores every report whose `context[:job]` is a job of the `Alerts` namespace (**Ruling R10**: Solid Queue reports a failed job after `perform`, through the executor, with the job in the context; a thread-local guard inside `perform` would be gone by then). So a broken database cannot chain `RecordErrorJob`s, and `CheckJob` failing every minute while the database is down adds nothing; `/ready` is what tells a monitor the database is down. The test drives the report as Solid Queue's path makes it (the context carrying the job), not only `perform_now`.
- **Ruling R11**: the subscriber is registered everywhere but acts only while `Rails.configuration.x.alerts.errors` is true: true by default, false in `config/environments/test.rb`, so the suite's existing handled reports queue nothing; its own tests turn it on around themselves (a helper). Cost if wrong: one more test switch.
- Writes one log line at `error` for unhandled, `warn` for handled: `[ContentSpiel] Error reported: <Class> at <place> (<source>)`. No message. **Ruling R6**: the message stays out of everything this feature writes (log, span, row, mail, page); Rails' own request log already logs an unhandled exception with its message for whoever reads the server log. Cost if wrong: an owner reads the server log for the message.
- Adds a span event on the current span through a new `Telemetry` helper (name `content_spiel.error`, attributes `exception.type` and `code.place` (or the names the Telemetry lists already use), joined to `ATTRIBUTES`).
- Enqueues `Alerts::RecordErrorJob.perform_later(error_class:, place:, source:, handled:, at:)`, with `enqueue_after_transaction_commit` off for that job: a report from inside a transaction that then rolls back must still arrive (Solid Queue writes to its own database).
- Never raises: everything is rescued and logged as one line with the class only.

`Alerts::RecordErrorJob` upserts the `error` alert by `fingerprint = SHA256("error|class|place")` (hex, cut to 64): a new row, or `occurrences + 1` and `last_seen_at`. (Upsert with `ON CONFLICT` is a SQL string with a `# sql:` reason, or `upsert` with `on_duplicate:` Arel, per the query rule.)

### 3. Throttle trips: `request.limited`

A subscriber on Rails' `rate_limit.action_controller` notification (`config/initializers/alerts.rb`; Rails instruments it on every refused request, payload `request`, `count`, `to`, `within`, `name`, `scope`, `by`, `cache_key`) calls `Audit::RequestLimits.heard(payload)` (`app/models/audit/request_limits.rb`: inside the existing `Audit` namespace, so no new top-level name):
- Records only the trip, the first refused request of a window: `count == to + 1`. One row per bucket per window.
- Records every limit whose controller does not include `Cookieless` (the rule, not an allowlist): today sign-in, the second step, Confirm it's you, passkey options, SSO, the reset, invitations, the setup wizard, Your account, invites, the test mail. **Ruling R12**: the doors whose limit counts in the default cache (`passwords`, `accounts#update`, `invitations#check`) never trip in tests (a `NullStore`); they are covered by a unit test of `heard` with a built payload and stay on their store; the sign-in door is proved end to end. **Ruling R7**: a limit on a public door (a controller that includes `Cookieless`: forms, search, suggestions) is not audited; those protect load and spam, a scraper would fill the log, and their spans carry them. The MCP throttle (Rack::Attack, a middleware with no `Current`) is not audited either. Cost if wrong: a later rule adds forms' trips.
- `Audit.record("request.limited", metadata: { "limit" => <name or "default">, "door" => "<controller_path>#<action>" })`, with whatever `Current` holds (the signed-in actor where there is one; the system with the request's IP at sign-in). Never `by` or `cache_key` (an address's HMAC, a user id).
- Sentence: a `SPECIAL_ACTIONS` entry, "Requests were limited at <door> (<limit>)" or similar, marked Security; `NO_ACTOR` is NOT set, since a signed-in actor is meaningful.
- Never raises (rescue, log one line, `Rails.error.report` is fine here since it is not in the error path).

The sign-in throttle's own buckets already record `session.locked`; unchanged.

### 4. Security alerts: `Alerts::CheckJob` (recurring, every minute)

One job, three steps in order: scan, digest, prune. Each step rescues its own failure (logged, reported) so one does not stop the next.

**Scan** (`Alerts::Rules`, a query object reading `audit_events` by named scopes; never `snapshot`):
- Fixed windows of 15 minutes (`WINDOW`), aligned to the clock; the scan looks at the current and the previous window, so a window's end is never missed. Fingerprints carry the window start, so an alert per window.
- `sign_in_failures`: `session.failed` + `session.second_factor_failed` + `session.confirmation_failed` in the window, counting each row's `occurrences`; at **20** or more (`FAILED_SIGN_INS`), upsert `sign_in_failures|<window_start>` with `occurrences = failed`, `details.failed`, `details.locked` (`session.locked` in the window).
- `access_denied_burst`: the sum of `occurrences` of `access.denied` rows whose `last_occurred_at` falls in the window, at **20** or more (`DENIED`). Coalescing makes this an approximation (a row extended into this window counts all its occurrences); documented, accepted.
- `request_limited`: any `request.limited` event in the window (at **1**), one alert per window with the count and the distinct limit names.
- `owner_changed` and `token_issued`: every `user.owner_changed` / `token.issued` event of the last two windows is one alert, fingerprint `audit|<event id>` (insert, ignore a duplicate), so a scan that runs twice, or late, neither repeats nor misses one while the job runs at least every 30 minutes.
- `last_seen_at` of a window alert is the newest event's time in it; `first_seen_at` the oldest's.

**Digest** (`Alerts::Digest`):
- Due alerts: `mailed_at` is nil, or the alert happened again since its last mail (`last_seen_at > mailed_at`) and that mail is at least **1 hour** old (`REMIND_AFTER`).
- At most one digest every **10 minutes** (`DIGEST_EVERY`), measured from the newest `mailed_at` of any alert. The first alert after a quiet spell goes out at the next minute's run.
- Only while `MailSettings.current.ready?` and an origin for the link exists (`link_origin`'s rule); otherwise nothing is marked and nothing is queued, so the alerts wait (System status says so). One log line per digest skipped for want of mail, at most once an hour (a `CounterStore` mark as `notice_due?` does; fail open).
- Recipients: every owner (`User.owners`, a new scope). One mail per owner: `Alerts::DigestMailer.digest` through `ApplicationMailer.queue(Alerts::DigestMailer, :digest, owner, alert_ids)` (ids, never details); mark the due alerts `mailed_at = now` in the same step (a single `update_all`, a job's write).
- The mail (`Alerts::DigestMailer#digest`): subject "<N> alerts on <site>" (plural keys); a line per alert, newest first, up to **20**, then "and <M> more"; a button "Open System status" to the System status route (its helper, with the link origin). An alert gone by delivery time is skipped; none left, no mail. All lines `mail.alerts_mailer.digest.*` keys. Look (card StudioAlerts): the existing mailer layout (560px white column on whitesmoke, named colours, the one `#6236d9` button). Subject "%{count} alerts on %{site}" (one: "1 alert on %{site}"). Intro "%{count} alerts on %{site} since the last mail:". A table, one row per alert: the kind bold with a colon ("**Security:**") and the sentence, with "12 times · last 13:47" under it in 13px dimgray; rows divided by 1px `gainsboro` (a named colour, the one new rule). After the 20th, "and N more". Button "Open System status", the address in plain text under it. Footer "You get this mail as an owner of %{site}. At most one mail every 10 minutes." above the layout's own footer. The text part is the same lines. An alert's sentence is built once from `details` for both the card and the mail (a helper on the drawing side, never the model).

**Prune**: delete `Alerts::Alert.expired`.

### 5. Readiness: `GET /ready`

**Ruling R8**: a separate path; `/up` stays exactly Rails' boot check for kamal-proxy (`/up` failing on a database blip would make kamal-proxy refuse a deploy for a reason a restart cannot fix, and its meaning is documented). `/ready` is for uptime monitors.

- `ReadinessController < ActionController::API` (no session, no cookie, no CSRF), route outside both host constraints like `/up`, and `/ready` added to `HostSettings::HEALTH_CHECK` (host authorization and the SSL redirect exclude it, exactly the path). Never behind the setup redirect.
- **Ruling R13**: production's `config/database.yml` gains `connect_timeout: 5` for its databases, so an unreachable database answers in seconds instead of holding a Puma thread for the operating system's TCP timeout; the probe uses the pool (its `checkout_timeout`) and a `SELECT 1`. Cost if wrong: a slow database connect over 5 s now fails a connection everywhere, not only in `/ready`.
- Checks: the primary database (`SELECT 1` through the pool; `# sql:` reason), and the queue database when the queue adapter is Solid Queue (mail and alerts depend on it). **Ruling R9**: the cache database is not checked; every reader of it fails open. Cost if wrong: a monitor misses a cache outage that only slows sign-in counting.
- Answers `200` with body `ok`, or `503` with body `unavailable`, `text/plain`, `Cache-Control: no-store`. The body names nothing more (no database name, no error).
- Never raises a 500: a check that raises is a 503, logged as one line with the class only.

### 6. System status

- A new "Alerts" card on System status (not counted in "n of m checks passed"): the 10 newest alerts of the last 7 days (`Alerts::Alert.recent`), each with its kind (Error / Security), its sentence, how often, last seen (site time), and its mail state ("Mailed <time>", "Not mailed yet", or the mail-not-set-up sentence); security rows link to the audit log. Empty: "No alerts in the last 7 days." While mail is not ready and an alert exists: a notice that owners cannot be mailed, linking to Settings → Mail. Read only.
- A sentence per kind is built by a component from `details` (the model returns data; dependency direction). Admin strings in `config/locales/admin/system_status.en.yml` (or the new component's own file per the i18n rule).
- Look: the Design System card **StudioAlerts** (Design System v250, marked "Decided, not built"; https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT, read only, never edited by the build). The design agent's decisions, which the builder follows exactly:
  - **Card frame:** under the checks, after Content, not counted. The Content card's frame (rounded-card, shadow-1, px-4, rows divided by cs-line), not a SettingsCard. Above it the h2 "Alerts" (20px/600) and the line "The last 7 days, newest first. Not part of the checks." (text-small cs-meta).
  - **Row:** new `Admin::SystemStatusScreen::AlertRowComponent` on `Admin::Ui::SystemCheckRowComponent`'s grid (`py-4`, a 110px chip column, then the text). The kind is `Admin::Ui::StateChipComponent`: Error `:danger`, Security `:warn`. The sentence is 600 cs-ink; an error's class and place are `<code>` (13px mono, weight 400). The facts are text-small cs-dim joined by " · ": "Once" / "12 times"; "last 14:02 today" / "last 9:15 yesterday" / "last 14 Nov, 18:03"; then the mail state: "Mailed 14:02", "Not mailed yet" in cs-meta, or "Not mailed: outgoing mail is not set up" in cs-warn-ink. A security row ends with "Open audit log →", the check row's tertiary LINK_CLASS link.
  - **Mail not ready:** `Admin::Ui::NoticeComponent` warn compact at the card's top: "Owners can't be mailed about these: outgoing mail is not set up. Open Mail settings →" (the link only for a holder of `settings.manage`).
  - **None:** one line in the card, "No alerts in the last 7 days." (text-sm cs-dim).
  - **Keys:** `admin.components.system_status_screen.alerts.*` (the component folder's locale file per the i18n rule).
  - The component lives in the screen's folder (one screen draws it), so it takes no shared-component contract.
- The setup wizard does not show the card.

### 7. Documentation

- New `docs/reference/alerting.md`: what is an alert, the rules and their figures, the digest, what is never in an alert, `/ready` vs `/up`, uptime monitoring (an outside monitor such as Uptime Kuma, Better Stack, UptimeRobot or a cron'd `curl -fsS`, asking `https://<site>/ready` every minute from outside the host and alerting after two failures; with `ADMIN_HOST`, both hosts answer it), `request.limited`, tests; and its "Rules a change can break silently".
- `CLAUDE.md` reference index: one entry for it.
- `docs/reference/hosting.md`: `/ready` beside `/up` where `/up` is described (host authorization, "What answers on both hosts"); a pointer from Telemetry to the span event.
- `docs/reference/mail.md`: the mails' list and count (nine).
- `docs/reference/access-control-and-audit.md`: `request.limited` in the audit log section.
- `CHANGELOG.md` `## Unreleased`: lines for each part, and the migration's version under `### Migrations`.

### 8. Tests (what the builder must prove)

- Subscriber: a report becomes one log line without the message, a span event, an enqueued job with only the five arguments; a 404-class error is ignored; a raising job does not loop; nothing raises.
- RecordErrorJob: new row, then increment; a report inside a rolled-back transaction still arrives.
- `request.limited`: the eleventh sign-in POST records one event, the twelfth none; a public limit records none; metadata has no address or key.
- Rules: each rule's threshold just under and at; idempotent re-run; per-event alerts not duplicated.
- Digest: one mail per owner, mailed_at set; a second run within 10 minutes sends nothing; a repeat after an hour; mail not ready sends nothing and marks nothing; no origin sends nothing; the mail holds no message, IP or email address (assert on a seeded alert whose error class has a message containing a secret-looking string).
- `/ready`: 200 ok; 503 when the database probe raises; no `Set-Cookie`; answers on both hosts with `ADMIN_HOST`; exempt from SSL redirect.
- System status: the card's empty, some, and mail-not-ready states.
- The existing guards stay green: sentence, signals, telemetry spans, job queues, environment variables (unchanged), mail guards, dependency direction, admin i18n.

### 9. Names

**Ruling R14**: new top-level names are kept to two, each listed under `### Breaking` in the changelog as the rule asks: `Alerts` (one namespace across `app/models/alerts/` with the model `Alerts::Alert` (table `alerts`), `app/jobs/alerts/`, `app/mailers/alerts/` (`Alerts::DigestMailer`), `app/queries/alerts/`, and `Alerts::ErrorSubscriber`), and `ReadinessController`. `Audit::RequestLimits` sits in `Audit`. Wherever the sections above say `Alert`, `AlertsMailer` or `RequestLimits`, read these names. Cost if wrong: a gem with owner `alerts` or `readiness_controller` must rename it.

## Left to the builder

Exact class placement inside the layer rules (`app/models/alerts/`, `app/jobs/alerts/`, `app/queries/alerts/`), the names of telemetry attribute keys if the lists already have equivalents, upsert mechanics, how the subscriber guard is held, and the exact sentence wording (in the reference file's voice).
