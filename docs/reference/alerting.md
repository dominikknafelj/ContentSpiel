# Alerting: errors, security alerts, the digest and readiness

> Describes: `app/models/alerts.rb`, `app/models/alerts/` (`Alert`, `ErrorSubscriber`, `Mailing`), `app/queries/alerts/rules.rb`, `app/jobs/alerts/` (`RecordErrorJob`, `CheckJob`), `app/mailers/alerts/digest_mailer.rb` with `app/views/alerts/digest_mailer/`, `app/models/audit/request_limits.rb`, `config/initializers/alerts.rb`, `config/recurring.yml` (`alerts_check`), `app/controllers/readiness_controller.rb`, `lib/host_settings.rb` (`HEALTH_PATHS`), `lib/telemetry.rb` (`error_event`), `app/components/admin/system_status_screen/alerts_component.*` and `alert_row_component.*`, `db/migrate/20261116120000_create_alerts.rb`.

Spec: `docs/superpowers/specs/2026-11-16-alerting-design.md` (issue #176; its rulings R1 to R14 say why each figure and boundary is where it is). Mail's mechanics are `docs/reference/mail.md`, the audit log's `docs/reference/access-control-and-audit.md`, the spans `docs/reference/hosting.md`, "Telemetry".

## What an alert is

A site's owners must learn that something is wrong without reading a server log, and an uptime monitor must tell "up" from "up but cannot reach its database". An alert is one row of `alerts` (`Alerts::Alert`): a `kind` (`error`, `sign_in_failures`, `owner_changed`, `token_issued`, `access_denied_burst`, `request_limited`), a unique `fingerprint` that folds repeats into the one row, `occurrences`, `first_seen_at`, `last_seen_at`, `mailed_at` and `details`, the fixed keys of its kind and nothing else. It is derived (from an error report or from the audit log) and written by jobs alone, as mail's state columns are, so no audit event is written for it: auditing it would add a row per row. There is no dismissing, no per-person setting and no environment variable: the figures below are constants and the recipients are the owners.

**Never in an alert** (its row, a log line this feature writes, a span, a mail or System status): an exception's message, a request's parameters, an IP address, a typed email address, a token or a key. A person is named through `PersonName.of`, never by a whole address; a subject with no name loses what follows its at sign (`Alerts::Rules#subject_name`).

## Errors

`Alerts::ErrorSubscriber` is Rails' error subscriber (`Rails.error.subscribe`, `config/initializers/alerts.rb`, which looks the class up at each report so a development reload is followed). Every report it accepts is three things, each holding the error's class, its place and the report's source, and no message: one log line (`[ContentSpiel] Error reported: <Class> at <place> (<source>)`, at `error` for an unhandled report and `warn` for a handled one), the span event `error.reported` on the current span (`Telemetry.error_event`, attributes `error.type` and `error.place`; `Telemetry::EVENTS`) and an `Alerts::RecordErrorJob`. The place is the first backtrace frame inside the application and outside `vendor/` (`app/models/page.rb:120`), or none. Rails' own request log keeps an unhandled exception's message for whoever reads the server log; this feature does not copy it.

`RecordErrorJob` upserts by `SHA256("error|<class>|<place>")` in one statement: a new row, or `occurrences + 1` and the later `last_seen_at`. Its arguments are the class, the place, the source, `handled` and the time. The queue is its own database, so the enqueue is not held for the reporter's transaction: a report from inside a transaction that rolls back still arrives (`test/models/alerts/error_subscriber_test.rb`: "a report inside a transaction that rolls back still arrives").

**What is not kept:**

- **A 4xx.** An error Rails answers with a status under 500 (`ActionDispatch::ExceptionWrapper.status_code_for_exception`: not found, a bad request, a stale form) is a visitor's typo, not the site's fault.
- **A report of a job of the `Alerts` namespace.** Solid Queue reports a failed job after its `perform`, through the executor, with the job in `context[:job]`; a guard set inside `perform` would be gone by then, so the subscriber reads the context. With the database down, `RecordErrorJob` would otherwise chain itself and `CheckJob` would add an alert a minute; `/ready` is what tells a monitor the database is down.
- **Anything while `Rails.configuration.x.alerts.errors` is off.** On by default (`config/application.rb`), off in the test environment so the suite's own handled reports queue nothing; a test turns it on with `with_error_alerts` (`test/support/error_alerts.rb`).

The subscriber never raises: a subscriber that raises takes the reporter's own error path, and the database it needs may be what is down. A failure is one line with the two class names.

## Security alerts

`Alerts::CheckJob` runs every minute (`config/recurring.yml`, in all three environments; `test/lib/job_queues_test.rb`) in three steps, each rescuing its own failure (one line with the step and the class, a report that the subscriber drops): the scan (`Alerts::Rules`), the digest (`Alerts::Mailing`) and the prune (`Alert.expired`, rows last seen over 30 days ago).

`Alerts::Rules` reads chosen columns of `audit_events` and never `snapshot` (nor `field_changes` beyond `user.owner_changed`'s `owner`), outside any request, so no subscriber on the audit notification runs in a request with the whole row. A window is `Alert::WINDOW`, 15 minutes, aligned to the clock; the scan evaluates the current and the previous one, so a scan that runs late still sees a window's end, and a window alert's fingerprint carries the window's start (`<kind>|<start>`), so a second scan updates the row and keeps its `first_seen_at` and `mailed_at`.

| Kind | Fires on | Figure |
|---|---|---|
| `sign_in_failures` | `session.failed`, `session.second_factor_failed` and `session.confirmation_failed` in the window, each row counted by its `occurrences`; `locked` is the window's `session.locked` | 20 or more (`FAILED_SIGN_INS`) |
| `access_denied_burst` | the `occurrences` of `access.denied` rows whose `last_occurred_at` falls in the window; `actors` counts distinct people, nobody as one | 20 or more (`DENIED`) |
| `request_limited` | `request.limited` events in the window, with the sorted distinct limit names | 1 (`LIMITED`) |
| `owner_changed`, `token_issued` | each `user.owner_changed` and `token.issued` event of the last two windows, one alert each, fingerprint `audit|<event id>`, inserted once and a repeat ignored | every one |

Coalescing makes `access_denied_burst` an approximation: a row extended into this window counts all its occurrences. A per-event alert is neither repeated nor missed by a scan that runs twice or late, for as long as the job runs at least every 30 minutes.

## The digest

`Alerts::Mailing#deliver` mails the owners (`User.owners`) one `Alerts::DigestMailer#digest` each, through `ApplicationMailer.queue` with the owner and the alerts' ids, never their details (a job's arguments are the queue's row and Active Job's log).

- **Due** (`Alert.due`): never mailed, or seen again since the mail (`last_seen_at > mailed_at`) with that mail at least `REMIND_AFTER`, one hour, old.
- **At most one digest every `DIGEST_EVERY`, 10 minutes**, measured from the newest `mailed_at` of any alert. The first alert after a quiet spell goes out at the next minute's run.
- **Nothing is marked that cannot go.** Mail not ready (`MailSettings.current.ready?`), or no site address for the link (`ApplicationMailer.link_url_options`, the rule every mailed link follows, `docs/reference/hosting.md`, "The reset mail"): nothing is queued and no alert is marked, so the alerts wait and System status says they were not mailed. One line says why, at most once an hour (a `CounterStore` mark; a store that fails logs the line again).
- **Marked, then queued, and one digest for two runs.** The alerts are claimed in one `update_all` that takes only those still due, and only the ones this run marked are queued: two runs overlapping never mail one alert twice. A queue write that fails after the mark loses one digest, whose alerts System status still shows and whose next occurrence mails again.
- **The mail** lists up to `DigestMailer::LISTED`, 20, alerts newest first, then "and N more"; an alert gone by delivery time is skipped and with none left no mail is built. Each line is `Alert#sentence` (the kind as the key, the values picked from `details`) worded by `mail.alerts_mailer.digest.*`; the button opens System status.

## `request.limited`

A refused request of Rails' `rate_limit` instruments `rate_limit.action_controller`; `config/initializers/alerts.rb` hands it to `Audit::RequestLimits.heard`, which records the first refusal of a window only (`count == to + 1`): one event per bucket per window, not one per refused request. The event is `Audit.record("request.limited", metadata: { "limit" => <name or "default">, "door" => "<controller_path>#<action>" })` with the actor, address and channel `Current` holds, and never the `by` key (an address's digest) or the `cache_key`. Its sentence is "<actor> hit the request limit at <door> (<limit>)" and it is a Security event with an actor (not in `NO_ACTOR`), so a signed-in person is named and the sign-in door's system actor reads as the system.

**Which doors.** Every door whose controller does not include `Cookieless`: sign-in, the second step, Confirm it's you, the passkey options, single sign-on, the reset, invitations, the setup wizard, Your account, invites and the test mail. A limit on a public door (the forms, the search, the suggestions: the `Cookieless` controllers) is not audited, since those protect load and spam and a scraper would fill the log; their spans carry them (`docs/reference/hosting.md`, "Sign-in on the open internet"). The MCP throttle (Rack::Attack, a middleware with no `Current`) is not audited either. It never raises: it runs inside the refused request, and an exception would turn a 429 into a 500; a failure logs the class alone.

## `/ready` and uptime monitoring

`GET /ready` (`ReadinessController`, an `ActionController::API`: no session, cookie or CSRF) answers `200` with `ok`, or `503` with `unavailable`, as `text/plain` with `Cache-Control: no-store`, and nothing else: no database or host name, no exception. It asks the primary database (`SELECT 1` through the pool) and, under Solid Queue, the queue database, since mail and alerts depend on it; the cache database is not asked, because every reader of it fails open. A probe that raises is a 503, never a 500, and the log line names the class only (a driver's message can hold a connection string). Production's databases take `connect_timeout: 5` (`config/database.yml`, inherited by cache, queue and cable), so an unreachable database answers in seconds and does not hold a Puma thread for the operating system's TCP timeout.

`/up` stays Rails' boot check for kamal-proxy and asks no database: a blip in the database must not make the proxy refuse a deploy a restart cannot fix. `/ready` is for uptime monitors. Both paths are outside both host constraints, so with `ADMIN_HOST` set either host answers them, and outside host authorization, the SSL redirect (`HostSettings::HEALTH_PATHS`) and the setup redirect (`Setup::RedirectConstraint`): a monitor asks by IP over plain HTTP, and a site not yet set up is up.

**Uptime monitoring** is not built in: an outside monitor (Uptime Kuma, Better Stack, UptimeRobot, or a cron'd `curl -fsS` on another host) asks `https://<site>/ready` every minute from outside the host and alerts after two failures in a row. A monitor on the host itself goes down with it.

## System status

The Alerts card lists the 10 newest alerts last seen within 7 days (`Alert.recent`; not counted in "n of m checks passed"), each with its kind chip, its sentence, how often, when last seen and its mail state; a security row links to the audit log for a viewer who holds `audit.view` (the screen needs only `system_status.view`, so another viewer sees the row without the link). While an alert exists and no digest can go, one notice says why, from the same answer the digest asks, `Alerts::Mailing.blocked_by`: mail not ready ("…outgoing mail is not set up.", linking to Settings → Mail for a holder of `settings.manage`), or mail ready and no site address for the link ("…the site has no address for the mail to link to. Set PUBLIC_HOST to the site's address.", an alert with no link), and each unmailed row's mail state says the same ("Not mailed: outgoing mail is not set up", "Not mailed: the site has no address"), never "Not mailed yet". Mail not ready wins when both are missing: one notice at most. A site without mail therefore still sees its alerts. The card's look is the Design System card StudioAlerts (the artifact, https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT, and the spec's section 6); its sentences are the component's own keys in `config/locales/admin/system_status_screen.en.yml`, built from `Alert#sentence`.

## In tests

`test/models/alerts/` (the model, the subscriber, `Mailing`), `test/queries/alerts/rules_test.rb` (each threshold just under and at, a re-run, a late scan), `test/jobs/alerts/`, `test/mailers/alerts/digest_mailer_test.rb` (an error whose message holds a secret-looking string, and no address, reaches nothing), `test/models/audit/request_limits_test.rb`, `test/integration/sign_in_throttles_test.rb` (the sign-in door's trip end to end) and `test/integration/readiness_test.rb` (200, 503 when a probe raises, no cookie, both hosts, while setup is pending). The doors whose limit counts in the default cache never trip in tests (a `NullStore`): their trips are covered by `heard` with a built payload.

## What a change can break silently

- **A new public door** (a controller outside `PublicController`) that does not include `Cookieless` has its rate limit audited as a CS Studio door's, and one scraper fills the log.
- **A new `details` key** that carries free text (a message, a path, a name someone typed) puts into the mail, the card and the log what this feature was made to keep out.
- **A new security action** that should alert is silent until a rule here names it; `SECURITY_ACTIONS` only marks it in the audit screen.
- **A change of a figure or of `Alert::WINDOW`** moves fingerprints (`<kind>|<window start>`): the alerts of the window it crosses are written twice.
- **A new job of the `Alerts` namespace** is dropped from error alerts whatever it fails with; one outside it that fails every minute adds an alert a minute.
- **A second `connect_timeout`** or a probe that does not use the pool makes `/ready` answer for a connection the app does not use.

## Rules a change can break silently

- Nothing a request carried reaches an alert, a log line this feature writes, a span, a mail or a page: the class and the place of an error, the kind and counts of a finding, a person's name through `PersonName.of` (`test/models/alerts/error_subscriber_test.rb`: "a report is one log line without its message, a span event and a job with five arguments"; `test/queries/alerts/rules_test.rb`: "no alert holds an address or a typed email", "a nameless subject user's address never reaches an alert"; `test/mailers/alerts/digest_mailer_test.rb`: "an error's message and an address never reach the mail").
- The error subscriber and `Audit::RequestLimits.heard` never raise, and `RecordErrorJob` and `CheckJob` never chain reports (`test/models/alerts/error_subscriber_test.rb`: "a report from a job of the Alerts namespace is dropped, as Solid Queue makes it after the perform", "the subscriber never raises: a failed enqueue is one line with the classes only"; `test/models/audit/request_limits_test.rb`: "a failure logs one line of its class and does not raise").
- Nothing is marked mailed that was not queued (`test/models/alerts/mailing_test.rb`: "with mail not ready nothing is queued or marked, and one line naming nobody is logged once an hour", "with no address to link to nothing is queued or marked", "two runs at once, the second finishing before the first marks, send one mail per owner", "blocked_by: nothing while mail is ready and an address is known, else why, mail not ready first"; `test/components/admin/system_status_screen/alerts_component_test.rb`: "no site address: the notice says so and names PUBLIC_HOST, as an alert with no link, and the row says why").
- A limit on a public door records nothing in the audit log (`test/models/audit/request_limits_test.rb`: "a public door records nothing"). **No guard** for a new public controller that leaves `Cookieless` out: its limit is audited.
- `/ready` answers 503, never 500, and nothing but `ok` or `unavailable` (`test/integration/readiness_test.rb`: "an unreachable database is a 503 and never a 500", "a failed probe writes one log line with the class and no message"). **No guard** that a new probe stays as cheap as `SELECT 1`.
- A new action of the audit log that is a security event and should alert needs a rule in `Alerts::Rules`. **No guard**: the rules are a hand list.
- `Alerts` and `ReadinessController` are top-level names (`TopLevelNames.owners`); a gem whose hook owner is one of them is refused at boot (`CHANGELOG.md`, "Breaking").
