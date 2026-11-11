# CS Studio sign-in, PR 1 (throttles, the bot check, leaked passwords) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Password sign-in to CS Studio holds up on the open internet: three throttle buckets, a Cloudflare Turnstile check after repeated failures, a leaked-password refusal on every path that sets a password, equal answers and timing whether or not an account exists, a mail to the account on a lock-out, and a span on each of those decisions.

**Architecture:**
- **One layer of plain objects** that a later kind of sign-in can call (the design's §9), in a new domain namespace `SignIn` (`app/models/sign_in.rb` and `app/models/sign_in/`):
  - `SignIn::Throttle`: the account bucket and the wide address bucket, plus the bot check's trigger, counted in `SignIn.store`;
  - `SignIn::BotCheck`: the Turnstile client;
  - `SignIn::LeakedPassword`: the Have I Been Pwned range client;
  - `SignIn::PasswordAttempt`: the one decision, returning a `SignIn::Outcome`.

  None of them knows a controller, a session, a cookie or a mail. The screens, the route, the session, the audit and the mail are CS Studio's: `Admin::SessionsController` asks the attempt and answers.
- **The leaked check runs in the three services** that set a password: `Users::Save` (wizard, user editor), `Users::UpdatePassword` (reset, Your account) and `Invitations::Accept`. It shares one module, `Users::LeakedPasswordRule`. It runs only after the record is otherwise valid, and outside the service's own transaction.
- **Equal timing comes from doing the same work either way, never from a sleep.**
  - Sign-in already hashes a password for an unknown address: `User.authenticate_by` builds a `User.new(password:)`, which runs `BCrypt::Password.create`.
  - The two lookups that differed, the reset request's and the lock-out mail's, move into jobs. The request then enqueues the same job whoever is asked for.
- **Telemetry's first hand-made spans** go through `Telemetry.in_span` and `Telemetry.record` (`lib/telemetry.rb`). They refuse a name not in `Telemetry::SPANS` and an attribute key not in `Telemetry::ATTRIBUTES`. Every span is a child of the request's. The two outside calls run `untraced`, so the Net::HTTP instrumentation records no address (HIBP's path holds five characters of the hash).

**Tech Stack:** Rails 8.1, Solid Cache (production's `Rails.cache`), Minitest with fixtures, Capybara on Cuprite 0.20 for one browser test, Stimulus over import maps, `Net::HTTP` and `JSON` from the standard library (no new gem), OpenTelemetry SDK 1.13 with `opentelemetry-instrumentation-all`, Action Mailer through `ApplicationMailer.queue`.

**Spec:** `docs/superpowers/specs/2026-11-10-studio-sign-in-design.md`. This plan is its "How it ships" PR 1:
- §1, whole;
- §5, the lock-out mail only;
- §6, `hosting.md`'s Cloudflare rule, the Turnstile keys, the leaked-password switch and the spans;
- §7, for exactly these parts: the shared tracer, the spans named below, and the span-content guard test;
- §9's seam, as the shape of `SignIn`;
- "My calls" for the figures.

Not here: sessions (§2), passkeys and recovery codes (§3), SSO (§4), the other mails of §5, the wizard's passkey step and the console reset (§6).

**One pull request** on branch `sign-in-1-throttles`, made from `main`, targeting `main`. It holds no migration: the counters live in the cache store (decisions, below).

---

## Design answer: the bot check's place (handed in by the coordinator)

The Turnstile widget's place on the sign-in panel is the design agent's StudioSignIn card. The look is not decided here.

**Handed in.** This is the design agent's StudioSignIn card, at Design System version 194 (index `1794358556-b35f`). Task 10 sets `test/support/design_system_entries.rb` `VERSION` to that id. No card is new.

Checked against main cb7f4cb1 (`admin/sessions/new.html.erb`, the product layout's panel).

1. **When it shows:** only after 3 failures within 15 minutes, from the address or for the email. The email bucket counts whether or not an account exists, so showing the check reveals nothing. It never shows when the site has no Turnstile keys.
2. **Placement:** inside the `form_with`, after the Password field, and after the "Ask the site's owner…" line when mail is off. It comes before Sign in. The form's existing `gap-[18px]` spaces it.
3. **Markup:**
   - a group `<div class="flex flex-col gap-2">`;
   - in it, the hint `<p id="turnstile-hint" class="text-small text-dim">`;
   - then the widget's box `<div class="min-h-[65px] w-full">`, given its height from the first paint so Sign in doesn't jump.
4. **Widget options:**
   - `size: "flexible"`, at most 356px. Use `size: "compact"` (150×140, left-aligned) when the box is narrower than 300px, which is a window under about 392px. The size is chosen once, at render.
   - `theme` from `document.documentElement.dataset.theme`, "light" or "dark", never "auto". When the theme switch changes it, the widget renders again.
   - `language` from the page's `lang`, and `action: "sign_in"`.
5. **Sign in** stays enabled; the server decides.
6. **Words** (keys under `admin.sessions`):
   - `new.check_hint`: "A quick check is needed before you can sign in."
   - `check_failed`: the `#alert` notice, `NoticeComponent :danger, :compact`, reading "Complete the check, then sign in again." It is used when the token is failed, expired or missing. The password is not tried, the email stays filled in, and the check is shown again.
   - `new.check_unavailable`: "The check couldn't load. Reload the page to try again." It replaces the hint when Turnstile's script fails to load.
7. **A temporarily locked account:**
   - It answers exactly `refused`, "Try another email address or password.", and the panel shows nothing else.
   - The check is already showing by then, because 3 failures come before the lock.
   - The person learns of the lock from the mail §1 sends to the account's address.
   - The per-address `limited` "Try again later." stays as it is.
   - The owner is deciding on the neutral alternative "Try again in a few minutes"; see the ledger.
8. **Light and dark:** the hint and the notice use tokens only. Cloudflare draws the widget itself, in the theme passed.

**The lock-out's words (the owner decided, 2026-11-11):** while the email's bucket is closed, the panel says "Try again in a few minutes." under the key `admin.sessions.locked`, as the `#alert` notice (`NoticeComponent :danger, :compact`). It replaces design point 7's "identical to `refused`". An email with no account locks and answers exactly the same, which a test holds: a known and an unknown address, five failures each, get the same status, body and redirect. The address buckets keep `limited` ("Try again later.").

---

## Decisions the spec left open

| Question | Decision | Why |
|---|---|---|
| Where the counters live | `SignIn.store`: `Rails.cache`, unless that is an `ActiveSupport::Cache::NullStore`, and then one `ActiveSupport::Cache::MemoryStore` of the process. It is memoised, the rule `MailTestLimit.store` and `Forms::SendLimit.store` already follow. Production is Solid Cache (`config/environments/production.rb:48`), shared by every process. Development is `:memory_store`. Test is `:null_store` (`config/environments/test.rb:23`), so the memory store stands in, and `test/test_helper.rb` clears it before every test. | A counter that every process sees, with no table and no migration. A throttle that cannot trip in tests would be untested, and this is the rule the codebase already has. Solid Cache's `increment` with `expires_in` is what Rails' own `rate_limit` relies on. |
| The per-address bucket's store | `Admin::SessionsController`'s `rate_limit to: 10, within: 3.minutes` keeps its figures and its sentence, and gains `store: SignIn.store`. | Its default store is the controller's `cache_store`, `null_store` in tests, so today it never trips under test. Production and development keep the store they had. |
| Gems | None. `SignIn::BotCheck` and `SignIn::LeakedPassword` are each one `Net::HTTP` request with a timeout, parsed with `JSON` or by lines. | Two small, documented endpoints. A gem would add a dependency and its own HTTP stack for 30 lines. |
| The account bucket's figures | Failures are counted per normalised address, whether or not an account exists. The count expires 24 hours after the run's first failure (`ACCOUNT_RUN`). From the 5th failure on, each failure closes the bucket for `min(1.minute * 2**(failures - 5), 1.hour)`: 1, 2, 4, 8, 16, 32 and then 60 minutes. The backoff level is `failures - 5`. A success clears the count and the lock. An attempt made while the bucket is closed checks no password and counts nothing. | The design's values ("5 failures → 1 minute, doubling to 1 hour, reset by a success"). Counting attempts made during a lock would let a bot keep a real person out for good. The 24 hours are this plan's: some end is needed, or one mistyped password a month would lock a person on the fifth. |
| The wide address bucket | 50 failures per address in a window of 1 hour from the first (`WIDE_LIMIT`, `WIDE_WINDOW`). At 50 the address is refused, without a password check, until the window ends. The address is `VisitorAddress.key(request.remote_ip, purpose:)`: an HMAC, with IPv6 cut to its /64, as the forms count it. | The design's value. The store holds no IP. |
| When the bot check is due | Turnstile is configured, and either the address or the account has 3 or more failures in a 15-minute window from the first (`BOT_CHECK_AFTER`, `BOT_CHECK_WINDOW`). `new` cannot know the account, so the page shows the widget when the address's count is due, or when `session[:sign_in_bot_check]` is set. `create` sets that flag on any refusal after which the check is due, and a success clears it. | The design's values. Without the flag, a person whose account (not address) tripped the check would be refused with no widget to answer it. |
| A required bot check | No token, or a token that is not a String, or one over 2,048 characters, gives `:bot_check_required`. A token Cloudflare refuses gives `:bot_check_failed`. Either way no password is checked and nothing is counted. | A bot without a token learns nothing about the password and costs the account nothing. |
| Turnstile unreachable | Fails **open**: the attempt goes on as if the check passed. It writes one line, `[ContentSpiel] The bot check could not be verified: <error class>`, and the span records `unavailable`. `internal-error` in Cloudflare's answer counts as unavailable. | The spec is silent. Its anti-goal is "an owner locked out of their own site by a provider outage", and the two throttles still stand without the check. |
| Leaked passwords | `SignIn::LeakedPassword.check(password, env: ENV)` → `:leaked`, `:clean`, `:unavailable` or `:off`. It sends `GET https://api.pwnedpasswords.com/range/<first 5 of the upper-case SHA-1 hex>` with `Add-Padding: true` and `User-Agent: ContentSpiel/<ContentSpiel::VERSION>`, opening within 2 s and reading within 3 s. A line `<the other 35>:<count>` with a count above 0 is leaked, and a padded line has count 0. A non-200 answer and the errors in `NETWORK_ERRORS` are unavailable: the password is accepted and one line is written, `[ContentSpiel] The leaked-password check could not be made: <error class or status>`. A body that is not lines of `HEX:DIGITS` is unavailable too. Any other error raises: it is a bug. | The design's rule (fail open and log). The padding hides the answer's size. The timeouts bound a refused save. |
| The leaked-password switch | `LEAKED_PASSWORD_CHECK=off`, exactly that value, turns the check off. Anything else, unset included, leaves it on. `test/test_helper.rb` sets `off` before the application loads, and a test turns it on with `with_leaked_password_check`. | One value, as `OTEL_CONSOLE=1` has it. No test reaches the network. |
| Turnstile's keys | `TURNSTILE_SITE_KEY` and `TURNSTILE_SECRET_KEY`. The check is on only when both are set and not blank. One without the other is off, and production's boot writes `[ContentSpiel] The bot check is off: TURNSTILE_SECRET_KEY is not set.` (or the site key), naming the variable and never a value. `test/test_helper.rb` deletes both before the application loads. | A widget whose answer cannot be verified would refuse everyone. |
| Which paths get the leaked check | Five, through three services: the wizard's founding owner (`SetupController#update_admin` → `Users::Save`), the user editor's new user and a typed password (`Admin::UsersController` → `Users::Save`), the reset (`Admin::PasswordsController#update` → `Users::UpdatePassword`), Your account (`Admin::AccountsController#update` → `Users::UpdatePassword`) and an invitation's acceptance (`InvitationsController#update` → `Invitations::Accept`). `db/seeds.rb`, `bin/setup` and the console write the model directly and are not checked. | Every person-facing path, found by `git grep -n "password" app/controllers app/services`. The seeds' dev passwords would fail a leak check and are not set by a person. |
| Where the check runs in a service | After the model's own validations pass (`record.valid?`: a too-short, blank or unconfirmed password never leaves the process), and before the service's transaction. `Invitations::Accept` builds and validates the account before `Invitation.transaction` and saves it inside, so the outside call never runs under the invitation's row lock. The wizard's `Users::Save` runs inside `SetupController`'s `LOCK TABLE users` transaction, so the call runs under that lock, bounded by the 5 s of timeouts. That step has one person and one row. | No HTTP under a row lock that other requests wait on. The wizard's lock is the one exception, and it is bounded. |
| The leaked sentence | `activerecord.errors.models.user.attributes.password.leaked`: "This password is in a list of leaked passwords, so it isn't safe to use. Choose another one." (`format: "%{message}"` already applies to `password`.) | "A sentence that says why". It reads whole under the field and in the summary. |
| Timing, how it is held | It is never asserted on the wall clock. A test counts the work instead: the SQL statements (`capture_sql`) and the calls to `BCrypt::Engine.hash_secret` (counted with `with_singleton_override`), for a known and an unknown address. It asserts they are equal. | Deterministic. A sleep or a measured time would be flaky and would prove nothing. |
| The reset request | `Admin::PasswordsController#create` always enqueues `PasswordResetRequestJob.perform_later(email_address, origin:)` (`self.log_arguments = false`) and looks up nothing. The job finds the user and calls `ApplicationMailer.queue(PasswordsMailer, :reset, user, …)`, as `create` did. A missing user ends the job quietly, with no line naming the address. | Before, a known address enqueued a job and an unknown one did not. That is a database write's difference in time. |
| The lock-out mail's lookup | The request enqueues `SignIn::LockoutMailJob.perform_later(email_address, locked_at:, from_address:, minutes:, origin:)` (`log_arguments = false`) for every account-bucket trip whose hour's mark is new, whether or not an account exists. The job finds the user, and mails only when `MailSettings.current.ready?`. The mark is `Throttle#notice_due?(identifier:)`, `write(…, unless_exist: true, expires_in: 1.hour)` under the account's key, so at most one mail an hour per account. | Equal work in the request. A doubling lock would otherwise mail at 1, 2, 4… minutes. |
| Audit action names | `session.locked`, recorded when a bucket closes (not for each refused attempt during the lock). It has no subject and no actor, as `session.failed` has. Its metadata: for the account bucket `{ "bucket" => "account", "email_address" => <cut to 254, only with "@">, "level" => n, "seconds" => s }`, and for the wide bucket `{ "bucket" => "address_wide", "seconds" => s }` (the address is the event's own `ip`). Its sentences are "Sign-in to one account paused after repeated failures" and "Sign-in from one address paused after repeated failures". It joins `SPECIAL_ACTIONS` and `SECURITY_ACTIONS`. `session.failed` stays as it is, for a checked password that failed. An attempt refused by a closed bucket or a missing bot check records nothing. | One action, in the repo's `noun.verb` pattern. Without a lookup the request stays equal-time. An event per refused attempt would bury the log under a bot run, and the spans carry that run instead. |
| The answer's words | A refused password and a closed account bucket give `admin.sessions.refused` ("Try another email address or password."). A closed address bucket, the rate limit and the wide cap give `admin.sessions.limited` ("Try again later."). A required or failed bot check gives `admin.sessions.bot_check`: "Confirm you're a person below, then sign in again." (or the card's words). Every one is the same redirect to `admin_sign_in_path`. | The design: "a lock-out answers like any refusal". The address buckets say nothing about an account, and they keep the sentence they have. The bot check's sentence is keyed per address and per normalised email, whether or not an account exists, so it reveals none. |
| Span names | `auth.sign_in` (INTERNAL, the attempt), `auth.throttle` (INTERNAL, one per bucket decided), `auth.bot_check` (CLIENT, Turnstile's siteverify), `auth.leaked_password` (CLIENT, the range lookup), `auth.lockout_mail` (INTERNAL, the mail's enqueue in the request). These are `Telemetry::SPANS`. | One prefix, `auth.`. Each is a child of the request's server span. The mail is delivered in its job's own trace. |
| Attribute keys | `Telemetry::ATTRIBUTES`: `auth.method` (`password`), `auth.outcome` (`SignIn::OUTCOMES`: `ok refused locked bot_check_required bot_check_failed`), `auth.account_exists` (Boolean, only once a password was checked), `auth.bucket` (`address address_wide account`), `auth.tripped` (Boolean), `auth.backoff_level` (Integer), `auth.bot_check.required` (Boolean), `auth.bot_check.result` (`passed failed unavailable`), `auth.leaked_password.result` (`leaked clean unavailable`), `auth.mail.queued` (Boolean), `server.address`, `http.response.status_code`, `error.type`. | The spec's allowed list, in OpenTelemetry's `server.*`, `http.*` and `error.*` names where one exists. A value is a fixed word, a number or a Boolean, never text that came in a request. |
| The span helpers | `Telemetry.tracer` is `OpenTelemetry.tracer_provider.tracer("contentspiel", ContentSpiel::VERSION)`, memoised. The API's proxy provider delegates once the SDK is configured, and is a no-op when it never is. `Telemetry.in_span(name, kind: :internal, attributes: {}, tracer: self.tracer) { |span| … }` and `Telemetry.record(span, attributes)` raise `ArgumentError` for a name or a key not listed. No file but `lib/telemetry.rb` calls `in_span`, `start_span` or `start_root_span`. A `set_attribute`, `add_attributes` or `add_event` outside it is listed in the guard's `WRITERS` with its reason. Today that is `app/jobs/media/rendition_job.rb`, the image figures on its job's span. | The checked pair is where a new attribute has to be named. A planted-value test holds what the values are. |
| The outside calls and the HTTP instrumentation | Each request runs inside `OpenTelemetry::Common::Utilities.untraced { … }`, within its own CLIENT span. | Net::HTTP's instrumentation would record `url.path` = `/range/ABCDE`, five characters of the password's hash, which the spec puts in no span. `PathScrubber` cuts queries, not paths. |
| Where the bot check's script lives | `app/javascript/controllers/bot_check_controller.js` (`bot-check`), a top-level controller of the product pages, beside `password_field` and `reset_token`. It loads `https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit` once per page (a `<script>` it adds when `window.turnstile` is missing), calls `turnstile.render(this.element, { sitekey, size, theme })` in `connect` and `turnstile.remove(id)` in `disconnect` and before `turbo:before-cache`. | Turbo keeps a page's body across visits. An implicit widget would render twice or not at all. |
| CSP | `Admin::SessionsController` overrides `frame_src` for `new` alone: `content_security_policy(only: :new) { |policy| policy.frame_src :self, "https://challenges.cloudflare.com" }`. | The app's policy sets `frame_src :self, youtube-nocookie`, and Turnstile is an iframe. No other page widens. |
| The token in logs | `:turnstile` joins `filter_parameters` (`cf-turnstile-response` holds no `token`). | The spec: "never in a span, an event or a log: the Turnstile token". |
| The address key | `VisitorAddress` (`app/values/visitor_address.rb`) takes `Forms::SendLimit.visitor` and `.visitor_key`'s code: `VisitorAddress.normalise(ip) -> String` and `VisitorAddress.key(ip, purpose:) -> String` (hex HMAC-SHA256, its key per purpose from `Rails.application.key_generator`, memoised per purpose). `Forms::SendLimit` calls it with its own `KEY_PURPOSE`. The old two methods go, and their callers and tests move. | Two counters need one rule. A model may not call a controller concern. No alias. |

## Global Constraints

- **Development stays simple (the owner, 2026-11-11):**
  - The leaked-password check defaults to **off** in development and test, and **on** in production. `LEAKED_PASSWORD_CHECK=on` or `off` overrides it in any environment.
  - The dev seed's password must keep working.
  - The bot check needs both Turnstile keys, which development doesn't set.
  - Sign-in in development is plain email and password.

- **The design's figures, exactly:**
  - the per-account back-off is "5 failures, then 1 minute, doubling to a 1 hour cap, reset by a success";
  - the wide per-address cap is "50 failures an hour";
  - Turnstile comes "after 3 failures from an address or for an account within 15 minutes";
  - "the leaked-password check fails open, and is logged when it does".

  Each is a constant on `SignIn::Throttle`, written once.
- **Bots learn nothing.** For a known and an unknown address, a refused sign-in, a closed account bucket, a reset request and a refused bot check answer alike: the same status, `Location`, flash, rendered page and cookie names, the same SQL statements and the same number of password hashes. Whether an account exists may be a span attribute (`auth.account_exists`), and is never in a response.
- **No secret anywhere it does not belong.** These never reach a span, an event, a log line, an audit snapshot or a page:
  - the email typed (beyond `session.failed`'s and `session.locked`'s metadata, as today);
  - a password, or any part of its SHA-1;
  - the Turnstile token or secret.

  A job that carries an email address sets `self.log_arguments = false`.
- **CLAUDE.md binds every task.** In particular:
  - `Audit.record` is the one audit write path;
  - a password changes only through `Users::UpdatePassword` or `Users::Save`;
  - no `Admin::<Domain>`: `SignIn` is top level, and nothing under `Admin` is named `SignIn`;
  - the dependency direction: `SignIn` names no controller, component, route or mailer, and the jobs and the controller call it;
  - strings are keys (`config/locales/admin/sessions.en.yml`, `config/locales/mail.en.yml`, `config/locales/en.yml` for the model message). `Audit::Sentence` stays English, as `docs/reference/i18n.md` names.
- **No compatibility code.** `Forms::SendLimit.visitor` and `.visitor_key` go with no alias. `git grep -n "SendLimit.visitor"` prints nothing outside `docs/superpowers/` when Task 2 ends.
- **`lib/` placement.** Only the tracer helpers, `Telemetry::SPANS` and `Telemetry::ATTRIBUTES` go into `lib/telemetry.rb`, which `config/application.rb` already requires. They name no app constant, and `ContentSpiel::VERSION` is required before it. Everything else is autoloaded under `app/`.
- **Every variable the code reads is in `docs/reference/hosting.md`'s table** (`test/lib/environment_variables_test.rb`). Each read is a literal at the read, `env["TURNSTILE_SITE_KEY"]`, so no `INDIRECT` entry is needed.
- **Comment rule (#117).** A comment states a current invariant, a hazard or a reason, never a plan step, a review round, "spec §", "Task N", "decision", "C3" or what used to be there. Every task rewrites the comments of the code it changes, including the long ones in `sessions_controller.rb` and `passwords_controller.rb` that its change makes untrue. The last step before each commit runs this grep over the lines the task added, and it prints nothing:

  ```
  git diff -U0 main... -- <files> | grep '^+' | grep -n "spec §\|handoff\|Task [0-9]\|round [0-9]\|fix round\|final review\|[Rr]uling [A-Z]\?[0-9]\|decision D\?[0-9]\|design answer\|bug [0-9]\|\bC[0-9][0-9]\?\b\|old name\|used to\|no longer"
  ```
- **Tests and the machine.**
  - The worktree runs `bin/rails db:test:prepare` once.
  - The one browser test (Task 10) runs after `bin/rails tailwindcss:build`, never beside a running `bin/dev`, and only while the first figure of `sysctl -n vm.loadavg` is under 6 and `pgrep -f "rails test"` prints nothing. It begins on `visit` followed by the page's own wait, as `password_reset_test.rb` does: the product layout has no shell.
  - No test reaches the network. A test of an outside call replaces `SignIn::BotCheck.siteverify` or `SignIn::LeakedPassword.range` with `with_singleton_override`, or points the call at a `TCPServer` on 127.0.0.1.
- **Commits** follow conventional commits and end with:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT`

## Review Focus

1. **Behind a CDN the site does not trust, every visitor is one address.** With Cloudflare in front and its ranges not in `config.action_dispatch.trusted_proxies`, `request.remote_ip` is Cloudflare's edge:
   - 10 attempts in 3 minutes from anyone close sign-in for everyone;
   - 50 failures in an hour from anyone close it for an hour;
   - 3 failures show the widget to all.

   A host expects the throttles to count people. Task 6 tests that a trusted proxy's `X-Forwarded-For` keeps two people apart:
   - `test "behind a trusted proxy two people count in two wide buckets, and the fiftieth failure of one leaves the other signing in"` (`test/integration/sign_in_throttles_test.rb`).

   Task 11 writes the hazard into `hosting.md`, beside the forms' identical one, and into its "What a change can break silently".
2. **One person, one bucket, however they type it.** " Ann@Example.ORG " and "ann@example.org" count as one account. So does an address of 300 characters cut to 254 in the audit log, which counts whole. A blank or non-String address (a list, a hash) is refused like any other, with no 500, and counts in the bucket of `""`. Task 6:
   - `test "the address is counted as User normalises it: case and spaces fall into one account bucket"`;
   - `test "an email that is a list or a hash is refused as any wrong address is, and counts"`.
3. **The locked-out person with the right password.** During a lock their correct password is refused with the same sentence, and the lock is not extended. Once it ends, the same password signs them in and clears the count, so their next mistake starts again at one. Task 2 (unit) and Task 6 (integration):
   - `test "an attempt during the lock checks no password and leaves the lock as it was"`;
   - `test "the right password during a lock is refused with the same sentence, and once the lock ends it signs in and the count starts again"`.
4. **Have I Been Pwned misbehaving.** Each of these accepts the password, writes one log line with no password and no hash, and records the span `unavailable`:
   - a 503;
   - a timeout;
   - a captive portal's HTML at 200;
   - a refused connection.

   Task 4:
   - `test "a 503, a timeout, a refused connection and an HTML page at 200 are each unavailable, and the line names the class or the status"`.

   Task 5:
   - `test "with the range lookup unavailable a new password is saved and the save says nothing of the check"` (Your account).
5. **Turnstile half configured, or sent junk.**
   - A site key with no secret: the widget never shows and nothing is required.
   - A token that is a list or 3,000 characters long: `:bot_check_required`, with no call to Cloudflare.
   - Cloudflare unreachable: the attempt goes on to the password.

   Task 3:
   - `test "one key without the other is no bot check, and the boot line names the missing variable"`;
   - `test "a token that is no String or is over 2,048 characters is refused without asking Cloudflare"`.

   Task 6:
   - `test "with Cloudflare unreachable the attempt goes on to the password, and the span says unavailable"`.

---

## File map

| File | Responsibility | Task |
|---|---|---|
| `lib/telemetry.rb`, `test/lib/telemetry_test.rb` (new), `test/lib/telemetry_spans_test.rb` (new) | the tracer, the checked span helpers, the guard | 1 |
| `app/values/visitor_address.rb` (new), `app/controllers/concerns/forms/send_limit.rb`, `app/models/sign_in.rb` (new), `app/models/sign_in/throttle.rb` (new), `test/test_helper.rb`, the tests | the counters | 2 |
| `app/models/sign_in/bot_check.rb` (new), `config/initializers/sign_in.rb` (new), `test/support/sign_in_helper.rb` (new) | Turnstile | 3 |
| `app/models/sign_in/leaked_password.rb` (new), `test/support/sign_in_helper.rb` | HIBP | 4 |
| `app/services/users/leaked_password_rule.rb` (new), `users/save.rb`, `users/update_password.rb`, `invitations/accept.rb`, `config/locales/en.yml` | the five password paths | 5 |
| `app/models/sign_in/password_attempt.rb` (new), `app/models/sign_in/outcome.rb` (new), `app/controllers/admin/sessions_controller.rb`, `app/models/audit/sentence.rb`, `config/locales/admin/sessions.en.yml` | the sign-in decision and its answers | 6 |
| `app/jobs/sign_in/lockout_mail_job.rb` (new), `app/mailers/sign_in_mailer.rb` (new), `app/views/sign_in_mailer/locked.{html,text}.erb` (new), `config/locales/mail.en.yml`, `test/mailers/previews/sign_in_mailer_preview.rb` (new), `test/lib/admin_design_rules_test.rb` (`MAIL_SOURCES`) | the lock-out mail | 7 |
| `app/jobs/password_reset_request_job.rb` (new), `app/controllers/admin/passwords_controller.rb` | the reset request's equal work | 8 |
| `test/integration/sign_in_telemetry_test.rb` (new) | the span-content guard | 9 |
| `app/views/admin/sessions/new.html.erb`, `app/javascript/controllers/bot_check_controller.js` (new), `config/initializers/filter_parameter_logging.rb`, `test/system/admin/sign_in_bot_check_test.rb` (new) | the widget | 10 |
| `docs/reference/{hosting,access-control-and-audit,mail,users-groups-tokens}.md`, `CLAUDE.md`, `CHANGELOG.md` | the reference and the PR | 11 |

---

### Task 1: One tracer, checked spans, and their guard

**Files:**
- Modify: `lib/telemetry.rb` (add after `exporter_kind`)
- Create: `test/lib/telemetry_test.rb`, `test/lib/telemetry_spans_test.rb`

**Interfaces:**
- Produces:
  - `Telemetry::SPANS` (frozen Array of the five names in the decisions table);
  - `Telemetry::ATTRIBUTES` (frozen Array of the thirteen keys);
  - `Telemetry.tracer -> OpenTelemetry::Trace::Tracer`;
  - `Telemetry.in_span(name, kind: :internal, attributes: {}, tracer: Telemetry.tracer) { |span| … } -> block's value`;
  - `Telemetry.record(span, attributes) -> span`.

  Each raises `ArgumentError` naming an unlisted name or key.

- [ ] **Step 1: Write the failing tests.**
  - `telemetry_test.rb`:
    - `test "in_span refuses a name that is not in SPANS and a key that is not in ATTRIBUTES, and record refuses an unlisted key"`;
    - `test "in_span under a request's span is its child, with the kind and attributes given"`. Inside `tracer.in_span("probe", kind: :server)` on the test exporter, `Telemetry.in_span("auth.sign_in", attributes: { "auth.method" => "password" })` finishes a span whose `parent_span_id` is the probe's, `kind` is `:internal`, and `attributes["auth.method"] == "password"`;
    - `test "with no SDK the span is a no-op and the block's value comes back"`. With `tracer: OpenTelemetry::Trace::TracerProvider.new.tracer`, the yielded span is not `recording?` and the call answers the block's value.
  - `telemetry_spans_test.rb`, reading `app/` and `lib/` with comments stripped:
    - `test "no file but lib/telemetry.rb starts a span"`. The pattern is `/\.(in_span|start_span|start_root_span)\b/`;
    - `test "every write to a span outside lib/telemetry.rb is listed with its reason, and every listed one is still there"`. `WRITERS = { "app/jobs/media/rendition_job.rb" => "the image figures on the job's own span" }`, the pattern `/\.(set_attribute|add_attributes|add_event)\b/`;
    - `test "every span name and attribute key is auth., server., http. or error."`, over `SPANS + ATTRIBUTES`.
- [ ] **Step 2: Run them, and verify they fail.** `bin/rails test test/lib/telemetry_test.rb test/lib/telemetry_spans_test.rb` fails with `NoMethodError: undefined method 'in_span' for module Telemetry`.
- [ ] **Step 3: Implement** in `lib/telemetry.rb`. `in_span` checks, then calls `tracer.in_span(name, kind:, attributes:)`. The comment says why the lists exist: a new attribute is named here or it fails, and the planted-value test is what holds the values. It also says why no span here is a root: `Telemetry::WorkSampler` drops an INTERNAL or CLIENT root with its trace.
- [ ] **Step 4: Run.** `bin/rails test test/lib/telemetry_test.rb test/lib/telemetry_spans_test.rb test/lib/telemetry test/integration/opentelemetry_test.rb test/lib/dependency_direction_test.rb`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: one tracer for the CMS's own spans, checked against a list of names and keys`.

---

### Task 2: The counters: `VisitorAddress`, `SignIn.store` and `SignIn::Throttle`

**Files:**
- Create: `app/values/visitor_address.rb`, `app/models/sign_in.rb`, `app/models/sign_in/throttle.rb`
- Modify: `app/controllers/concerns/forms/send_limit.rb` (remove `visitor` and `visitor_key`, and call `VisitorAddress.key(request.remote_ip, purpose: KEY_PURPOSE)`), and every test that called them (`git grep -n "SendLimit.visitor" test`)
- Modify: `test/test_helper.rb` (`setup { SignIn.store.clear }` beside `Setup.reset!`)
- Test: `test/values/visitor_address_test.rb` (the moved forms cases, plus a second purpose), `test/models/sign_in/throttle_test.rb`, `test/integration/form_send_limits_test.rb`

**Interfaces:**
- Produces:
  - `VisitorAddress.normalise(ip) -> String`;
  - `VisitorAddress.key(ip, purpose:) -> String` (64 hex characters);
  - `SignIn.store -> ActiveSupport::Cache::Store`;
  - `SignIn::Throttle.new(scope: "studio", store: SignIn.store)`, whose `scope` is part of every key, so a later members' sign-in counts apart;
  - the constants `ACCOUNT_FREE_FAILURES = 5`, `BACKOFF_FIRST = 1.minute`, `BACKOFF_CAP = 1.hour`, `ACCOUNT_RUN = 24.hours`, `WIDE_LIMIT = 50`, `WIDE_WINDOW = 1.hour`, `BOT_CHECK_AFTER = 3`, `BOT_CHECK_WINDOW = 15.minutes`, `NOTICE_EVERY = 1.hour`, `KEY_PURPOSE = "content_spiel sign-in throttle"`;
  - `SignIn::Throttle::Trip = Data.define(:bucket, :level, :seconds)`, where `bucket` is `:account` or `:address_wide`, `level` is an Integer or nil, and `seconds` is the time left or the new lock's length;
  - `SignIn::Throttle.lock_seconds(failures) -> Integer | nil`;
  - `#closed(identifier:, address:) -> Trip | nil`, which asks the wide bucket first;
  - `#record_failure(identifier:, address:) -> Trip | nil`: the bucket this failure closed, if any;
  - `#record_success(identifier:) -> nil`;
  - `#bot_check_due?(address:, identifier: nil) -> Boolean`;
  - `#notice_due?(identifier:) -> Boolean`, which writes the hour's mark.

  `identifier` is the caller's normalised String. The key is its `VisitorAddress`-style HMAC under `KEY_PURPOSE`, never the address itself. `address` is `request.remote_ip`.

  Every decision runs in `Telemetry.in_span("auth.throttle", attributes: { "auth.bucket" => …, "auth.tripped" => …, "auth.backoff_level" => … })`: `closed` makes one span per bucket asked, and `record_failure` one per bucket that closed.

- [ ] **Step 1: Write the failing tests** in `throttle_test.rb`, each on a fresh `ActiveSupport::Cache::MemoryStore` and with `travel`:
  - `test "lock_seconds is nil below five failures, then 60, 120, 240 … and 3600 from the eleventh"`, which asserts `[nil]*4 + [60, 120, 240, 480, 960, 1920, 3600, 3600]` for 1..12;
  - `test "the fifth failure closes the account for a minute, and the bucket opens again after it"`, where the Trip is `bucket: :account, level: 0, seconds: 60`;
  - `test "an attempt during the lock checks no password and leaves the lock as it was"` (Review Focus 3): `closed` twice in the minute leaves the count at 5 and the lock's end unchanged;
  - `test "a success clears the account's count and lock, and the next failure counts from one"`;
  - `test "an account's failures are forgotten 24 hours after the run's first"`;
  - `test "the fiftieth failure from an address closes it until the hour ends, whatever accounts it tried"`, where the Trip is `bucket: :address_wide`;
  - `test "the bot check is due after three failures from the address or for the account in 15 minutes, and not after the window"`;
  - `test "a notice is due once an hour per account"`;
  - `test "two scopes count apart, and the store holds neither the address nor the IP"` (scan `store.instance_variable_get(:@data).keys`).
  - `visitor_address_test.rb`: the forms' cases (IPv4 whole, IPv6 by its /64, an unparsable value as written), plus `test "two purposes give two keys for one address"`.
- [ ] **Step 2: Run them, and verify they fail.** `bin/rails test test/models/sign_in test/values/visitor_address_test.rb`. Expected: `NameError: uninitialized constant SignIn`.
- [ ] **Step 3: Implement.**
  - Counts use `store.increment(key, 1, expires_in:)`, which sets the window at the first write, as Rails' `rate_limit` does.
  - A lock is `store.write(lock_key, until_epoch, expires_in: seconds)`.
  - `SignIn.store`'s comment states the NullStore rule and Solid Cache's sharing.
  - `sign_in.rb`'s comment says what the namespace is for: plain objects that any kind of sign-in calls, and nothing that knows a session, a cookie, a route or a mail.
- [ ] **Step 4: Run.** `bin/rails test test/models/sign_in test/values test/integration/form_send_limits_test.rb test/controllers/form_sends_controller_test.rb test/lib/admin_namespace_shadow_test.rb test/lib/dependency_direction_test.rb`. Expected: PASS. Then `git grep -n "SendLimit.visitor"` prints nothing outside `docs/superpowers/`.
- [ ] **Step 5: Comments and commit.** Commit `feat: the sign-in throttle's account and wide address buckets, counted where every process sees them`.

---

### Task 3: The bot check (Turnstile)

**Files:**
- Create: `app/models/sign_in/bot_check.rb`, `config/initializers/sign_in.rb`, `test/support/sign_in_helper.rb`
- Modify: `test/test_helper.rb` (add `TURNSTILE_SITE_KEY TURNSTILE_SECRET_KEY` to the list deleted before load, require and include `SignInHelper`)
- Test: `test/models/sign_in/bot_check_test.rb`

**Interfaces:**
- Produces:
  - `SignIn::BotCheck.current(env = ENV) -> SignIn::BotCheck | nil`, which reads `env["TURNSTILE_SITE_KEY"]` and `env["TURNSTILE_SECRET_KEY"]` literally;
  - `SignIn::BotCheck.missing_variable(env = ENV) -> String | nil`: the name of the one key that is unset while the other is set;
  - `#site_key -> String`;
  - `#verify(token, address:) -> :passed | :failed | :unavailable`;
  - the constants `VERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify"`, `TOKEN_MAX = 2048`, `OPEN_TIMEOUT = 2`, `READ_TIMEOUT = 3`, and `NETWORK_ERRORS` (`Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError, IOError, Net::HTTPBadResponse, JSON::ParserError`);
  - `SignIn::BotCheck.siteverify(form, url: VERIFY_URL) -> Hash` (the parsed JSON), the one network call, run `untraced`. It raises `SignIn::BotCheck::Unavailable` on a non-200.
  - In `SignInHelper`, `with_bot_check(answer = :passed) { … }`: it sets both variables (Cloudflare's documented always-pass test keys) and overrides `siteverify` to answer `{"success" => true}`, `{"success" => false, "error-codes" => ["invalid-input-response"]}`, or raise `Errno::ECONNREFUSED` for `:passed`, `:failed` or `:unavailable`. It records each form it was sent in `bot_check_requests`.
  - `verify` runs in `Telemetry.in_span("auth.bot_check", kind: :client, attributes: { "server.address" => "challenges.cloudflare.com" })` and records `auth.bot_check.result`, `http.response.status_code` and, when unavailable, `error.type`.

- [ ] **Step 1: Write the failing tests** in `bot_check_test.rb`:
  - `test "one key without the other is no bot check, and the boot line names the missing variable"` (Review Focus 5). `current` is nil and `missing_variable` names the absent one, for both orders. Blank counts as unset;
  - `test "a token that is no String or is over 2,048 characters is refused without asking Cloudflare"` (Review Focus 5). `verify(["x"], …)`, `verify("a" * 2049, …)` and `verify(nil, …)` are `:failed`, and `bot_check_requests` is empty;
  - `test "Cloudflare's yes is passed, its no is failed, and internal-error or a network error is unavailable with one line naming the class"`, using `LogCapture`, and asserting the line holds neither the token nor the secret;
  - `test "the form sent is the secret, the token and the address, and nothing else"`;
  - `test "siteverify runs untraced: no span of the HTTP instrumentation is recorded for it"`. A `TCPServer` on 127.0.0.1 answers `HTTP/1.1 200 OK` with `{"success":true}`. The call is made with `url:` pointing at it, inside a `:server` probe span, and no finished span but the probe's and `auth.bot_check` has an attribute naming the stub's port.
- [ ] **Step 2: Run them, and verify they fail.** `bin/rails test test/models/sign_in/bot_check_test.rb`.
- [ ] **Step 3: Implement.**
  - `config/initializers/sign_in.rb` runs in `Rails.application.config.after_initialize`, in production only. When `SignIn::BotCheck.missing_variable` names one, it logs `[ContentSpiel] The bot check is off: <NAME> is not set.` at warn.
  - The class comment states the fail-open rule and its reason, and that the secret is never logged.
- [ ] **Step 4: Run.** `bin/rails test test/models/sign_in test/lib/environment_variables_test.rb`. Expected: the environment test fails on the two new names until Task 11 lists them. Note it in the commit body. Everything else passes.
- [ ] **Step 5: Comments and commit.** Commit `feat: the Turnstile check, verified on the server, failing open when Cloudflare can't be reached`.

---

### Task 4: The leaked-password lookup (Have I Been Pwned)

**Files:**
- Create: `app/models/sign_in/leaked_password.rb`
- Modify: `test/test_helper.rb` (`ENV["LEAKED_PASSWORD_CHECK"] = "off"` before load, beside the deletions, with the reason), `test/support/sign_in_helper.rb`
- Test: `test/models/sign_in/leaked_password_test.rb`

**Interfaces:**
- Produces:
  - `SignIn::LeakedPassword.check(password, env: ENV) -> :leaked | :clean | :unavailable | :off`. It reads `env["LEAKED_PASSWORD_CHECK"]` literally;
  - `SignIn::LeakedPassword.range(prefix, url: RANGE_URL) -> String` (the body), run `untraced`, raising `SignIn::LeakedPassword::Unavailable` on a non-200;
  - the constants `RANGE_URL = "https://api.pwnedpasswords.com/range/"`, `OPEN_TIMEOUT = 2`, `READ_TIMEOUT = 3`, and `NETWORK_ERRORS` (as BotCheck's, without `JSON::ParserError`);
  - in `SignInHelper`, `with_leaked_password_check(leaked: [], unavailable: nil) { … }`. It sets the variable to nil for the block, and overrides `range` to answer the suffixes of the `leaked` passwords at count 7, one padded line at count 0, and three unrelated lines. With `unavailable:` (an exception or an Integer status) it raises or fails accordingly.
  - `check` runs in `Telemetry.in_span("auth.leaked_password", kind: :client, attributes: { "server.address" => "api.pwnedpasswords.com" })` and records `auth.leaked_password.result`, `http.response.status_code` and `error.type`.

- [ ] **Step 1: Write the failing tests:**
  - `test "a password whose suffix is listed with a count is leaked, one at count 0 is clean, and only the five-character prefix is asked for"`;
  - `test "off, exactly, turns the check off and sends nothing; any other value leaves it on"`;
  - Review Focus 4: `test "a 503, a timeout, a refused connection and an HTML page at 200 are each unavailable, and the line names the class or the status"`. The captured log holds neither the password nor its SHA-1 hex, upper or lower case;
  - `test "the request asks for padding and names ContentSpiel as its agent"` (the stub server reads the request's headers);
  - `test "range runs untraced: no span holds the prefix"` (the `TCPServer` stub, as Task 3).
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** The class comment states:
  - what leaves the process (five hex characters);
  - why the HTTP instrumentation is suppressed;
  - the fail-open rule.
- [ ] **Step 4: Run.** `bin/rails test test/models/sign_in`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: the leaked-password lookup against Have I Been Pwned's range API, failing open`.

---

### Task 5: Every password a person sets is checked

**Files:**
- Create: `app/services/users/leaked_password_rule.rb`
- Modify: `app/services/users/save.rb`, `app/services/users/update_password.rb`, `app/services/invitations/accept.rb`, `config/locales/en.yml` (`activerecord.errors.models.user.attributes.password.leaked`)
- Test: `test/services/users/save_test.rb`, `test/services/users/update_password_test.rb`, `test/services/invitations/accept_test.rb`, and one integration test per path: `test/integration/setup_early_steps_test.rb` (the admin step), `test/integration/admin/users_editor_test.rb`, `test/controllers/admin/passwords_controller_test.rb`, `test/integration/admin/accounts_test.rb`, `test/controllers/invitations_controller_test.rb`

**Interfaces:**
- Consumes: `SignIn::LeakedPassword.check` (Task 4).
- Produces: `Users::LeakedPasswordRule`, included by the three services, with:
  - `leaked_password?(password) -> Boolean` (true only for `:leaked`);
  - `leaked_password_failure(record) -> ApplicationService::Result` (`record.errors.add(:password, :leaked)`, then `failure(record)`).

- [ ] **Step 1: Write the failing tests.**
  - Service tests, each inside `with_leaked_password_check(leaked: ["correct horse battery"])`:
    - `Users::Save`: `test "a leaked password is refused on a new user and on a typed change, with the sentence on the password, and nothing is written or audited"`;
    - `Users::Save`: `test "a password too short or unconfirmed is refused by the model first and is never looked up"` (`with_leaked_password_check` records its prefixes, and none is recorded);
    - `Users::UpdatePassword`: `test "a leaked password is refused and the user's sessions all stay"`;
    - `Invitations::Accept`: `test "a leaked password is refused, the invitation stays open, and the lookup runs before the invitation is locked"`. Assert with `capture_sql` that no `FOR UPDATE` precedes the override's call: the override appends `:looked_up` to an array that the SQL callback also appends to.
  - One integration test per path, each asserting the 422 and the sentence on the page:
    - `test "the wizard refuses a leaked password for the founding owner"`;
    - `test "the user editor refuses a leaked password"`;
    - `test "the reset refuses a leaked password and keeps the token in the form"`;
    - `test "Your account refuses a leaked password in its card"`;
    - `test "an invitation refuses a leaked password and draws the form again"`.
  - Review Focus 4 (Your account): `test "with the range lookup unavailable a new password is saved and the save says nothing of the check"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
  - In `Users::Save` and `Users::UpdatePassword`: after `assign_attributes` and the unconfirmed or blank refusals, `return leaked_password_failure(@user) if password_typed && @user.valid? && leaked_password?(password)`, before `User.transaction`.
  - In `Invitations::Accept`: split `create_user` into `build_user` (outside the transaction: build, validate, the confirmation rule and the leak check) and its `save` (inside it, after `lock!` and the `used?` re-check). The comments that name the order are rewritten to say why the lookup comes first.
- [ ] **Step 4: Run.** `bin/rails test test/services/users test/services/invitations test/integration/setup_early_steps_test.rb test/integration/admin/users_editor_test.rb test/integration/admin/accounts_test.rb test/controllers/admin/passwords_controller_test.rb test/controllers/invitations_controller_test.rb test/services/service_behaviour_contract_test.rb`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: a leaked password is refused wherever a person sets one`.

---

### Task 6: The sign-in decision, its answers and its audit

**Files:**
- Create: `app/models/sign_in/password_attempt.rb`, `app/models/sign_in/outcome.rb`
- Modify:
  - `app/controllers/admin/sessions_controller.rb` (`rate_limit … store: SignIn.store, with: -> { answer_address_limited }`; `create` asks the attempt; `session[:sign_in_bot_check]`; the `session.locked` record);
  - `app/models/audit/sentence.rb` (`session.locked` in `SPECIAL_ACTIONS`, `SECURITY_ACTIONS`, `special_parts`, and `actor_for`'s `none:`);
  - `config/locales/admin/sessions.en.yml` (`bot_check`);
  - every list where `session.failed` stands, found with `git grep -n "session.failed" app`, e.g. `Dashboard::Feed::NOT_A_CHANGE` if it names it.
- Test: `test/models/sign_in/password_attempt_test.rb`, `test/integration/sign_in_throttles_test.rb` (new), `test/integration/sessions_test.rb`, `test/models/audit/sentence_test.rb`, `test/components/admin/audit_screen/sentence_component_test.rb`, `test/models/editing/signals_test.rb`

**Interfaces:**
- Consumes: Task 2's `Throttle`, Task 3's `BotCheck`, Task 1's `Telemetry.in_span`.
- Produces:
  - `SignIn::OUTCOMES = %i[ok refused locked bot_check_required bot_check_failed].freeze` (in `sign_in.rb`);
  - `SignIn::Outcome = Data.define(:status, :account, :trip, :bot_check_due)`, where `trip` is the `Throttle::Trip` that closed a bucket now or that refused this attempt, and `bot_check_due` is whether the next attempt must carry the check;
  - `SignIn::PasswordAttempt.new(email:, password:, address:, bot_check_token:, accounts: User, throttle: SignIn::Throttle.new, bot_check: SignIn::BotCheck.current)`;
  - `#call -> SignIn::Outcome`;
  - `#identifier -> String` (`accounts.normalize_value_for(:email_address, email.is_a?(String) ? email : "")`).

  The order inside `#call`, all in `Telemetry.in_span("auth.sign_in", attributes: { "auth.method" => "password" })`, which records `auth.outcome` at the end and `auth.account_exists` once a password was checked:
  1. `throttle.closed` → `:locked`;
  2. if `bot_check` and `throttle.bot_check_due?(address:, identifier:)`: no usable token → `:bot_check_required`, a `:failed` verify → `:bot_check_failed` (records `auth.bot_check.required`);
  3. `accounts.authenticate_by(email_address: email, password: password)`, with each value a String or `""`;
  4. an account → `throttle.record_success` → `:ok`; none → `throttle.record_failure` → `:refused`, with the trip it closed.

- [ ] **Step 1: Write the failing tests.**
  - `password_attempt_test.rb` (a fake throttle store, `with_bot_check`):
    - `test "the right password is ok and clears the count; a wrong one is refused and counts; the fifth refusal carries the trip that began"`;
    - `test "a closed bucket is locked before any password is checked"`. `BCrypt::Engine.hash_secret` is counted at 0 with `with_singleton_override`;
    - `test "a due bot check without a token is bot_check_required, a refused one bot_check_failed, and neither checks a password or counts"`;
    - `test "with Cloudflare unreachable the attempt goes on to the password, and the span says unavailable"` (Review Focus 5);
    - `test "without Turnstile configured no check is ever due and the throttles still stand"`.
  - `sign_in_throttles_test.rb` (integration, the real controller):
    - `test "a refused sign-in answers the same for a known and an unknown address: status, location, flash, page, cookie names, statements and one password hash each"`. Compare `capture_sql` with the audit insert's id-bearing values stripped, `response.location`, `flash[:alert]`, the page after `follow_redirect!` with the CSRF token's value removed, `cookies.to_hash.keys`, and the `hash_secret` count;
    - `test "a closed account bucket answers the same for a known and an unknown address, and checks no password"`;
    - `test "the fifth failure records one session.locked with the bucket, level and seconds, and the sixth attempt in that minute records nothing"`;
    - `test "the fiftieth failure from an address answers Try again later and records session.locked for address_wide"`;
    - Review Focus 1: `test "behind a trusted proxy two people count in two wide buckets, and the fiftieth failure of one leaves the other signing in"`. Set `REMOTE_ADDR` to a private hop and `X-Forwarded-For` per person;
    - Review Focus 2: `test "the address is counted as User normalises it: case and spaces fall into one account bucket"`;
    - Review Focus 2: `test "an email that is a list or a hash is refused as any wrong address is, and counts"`;
    - Review Focus 3: `test "the right password during a lock is refused with the same sentence, and once the lock ends it signs in and the count starts again"`;
    - `test "after three failures the next page asks for the bot check, a success forgets it, and a required check's refusal says so"` (`with_bot_check`, reading `session[:sign_in_bot_check]` and `flash[:alert] == I18n.t("admin.sessions.bot_check")`);
    - `test "the eleventh attempt in three minutes is limited, now in tests too"`.
  - `sentence_test.rb`:
    - `test "a lock-out reads as paused sign-in, for one account or one address, with no actor, as a security event"`;
    - the existing "every action recorded anywhere in app/ has a sentence" covers the new literal.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
  - `create`:
    - builds the attempt from `params[:email_address]`, `params[:password]`, `request.remote_ip` and `params["cf-turnstile-response"]`;
    - on `:ok` deletes the flag, starts the session, records `session.created` and redirects as today;
    - otherwise records `session.failed` (only for `:refused`) and `session.locked` (only when `outcome.trip` began with this attempt);
    - sets the flag when `outcome.bot_check_due`;
    - redirects with the sentence from the decisions table.
  - `answer_address_limited` wraps its redirect in an `auth.sign_in` span (`auth.outcome` `locked`) holding one `auth.throttle` span (`auth.bucket` `address`, `auth.tripped` true).
  - `new` sets `@bot_check = SignIn::BotCheck.current` when it is due: the address's count or the flag. Task 10 draws it.
  - The controller's comments are rewritten: which answer each outcome gets and why, what is audited and why only then, and the store's reason.
- [ ] **Step 4: Run.** `bin/rails test test/models/sign_in test/integration/sign_in_throttles_test.rb test/integration/sessions_test.rb test/controllers/admin/sessions_controller_test.rb test/models/audit test/components/admin/audit_screen test/models/editing/signals_test.rb test/integration/admin/audit_log_screen_test.rb`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: sign-in asks the account and address buckets and the bot check, and answers the same whoever exists`.

---

### Task 7: The lock-out mail

**Files:**
- Create:
  - `app/jobs/sign_in/lockout_mail_job.rb`;
  - `app/mailers/sign_in_mailer.rb`;
  - `app/views/sign_in_mailer/locked.html.erb` and `locked.text.erb`;
  - `test/mailers/sign_in_mailer_test.rb`, `test/mailers/previews/sign_in_mailer_preview.rb`, `test/jobs/sign_in/lockout_mail_job_test.rb`.
- Modify:
  - `app/controllers/admin/sessions_controller.rb`: on an account-bucket trip that began, when `throttle.notice_due?(identifier:)`, enqueue the job inside `Telemetry.in_span("auth.lockout_mail")`, recording `auth.mail.queued`;
  - `config/locales/mail.en.yml`;
  - `test/lib/admin_design_rules_test.rb`: `MAIL_SOURCES` gains `app/views/sign_in_mailer`.

**Interfaces:**
- Consumes: Task 6's `Outcome#trip`, Task 2's `notice_due?`.
- Produces:
  - `SignIn::LockoutMailJob.perform_later(email_address, locked_at:, from_address:, minutes:, origin: nil)`, with `log_arguments = false`;
  - `SignInMailer.locked(user, locked_at:, from_address:, minutes:, origin: nil)`.

  The origin follows `PasswordsMailer`: `{ origin: request.base_url }` only when no site address is configured and `PasswordsMailer.request_origin_used?`, else none. The link is `new_admin_password_url(port: nil, **link_origin(origin))`, the reset *request* page, which carries no token. With no origin the mailer builds no mail and logs, as `reset` does.

  The words, `mail.locked.*`:
  - `subject`: "Signing in to %{site} is paused";
  - `intro.one` / `intro.other`: "There were several failed attempts to sign in to your account on %{site}, so signing in is paused for %{count} minute." / "… for %{count} minutes.";
  - `details`: "The last attempt was at %{time}, from the address %{address}.";
  - `button`: "Reset password";
  - `outro`: "If this was you, wait and try again, or reset your password. If it wasn't, your password kept them out, and resetting it is still the safest step."

  `%{time}` is `I18n.l(locked_at.in_time_zone(SiteSetting.instance.effective_time_zone), format: :"admin.datetime")`.

- [ ] **Step 1: Write the failing tests.**
  - `sign_in_mailer_test.rb`:
    - `test "the lock-out mail names the site, the minutes, the time in the site's zone and the address, and links to the reset request with no token"`;
    - `test "with no address known outside development and test no mail is built"`.
  - `lockout_mail_job_test.rb`:
    - `test "the job mails the account through ApplicationMailer.queue when mail is ready"`;
    - `test "for an address with no account, or with mail not ready, it sends nothing and logs no address"`;
    - `test "the job's arguments are not logged"` (`LogCapture` around `perform_enqueued_jobs`; the email is in no line).
  - In `sign_in_throttles_test.rb`:
    - `test "the fifth failure enqueues one lock-out job for a known and an unknown address alike, and the next lock within the hour enqueues none"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** The views use `mails/_button` and the mailer layout, as `passwords_mailer/reset.*` do.
- [ ] **Step 4: Run.** `bin/rails test test/mailers test/jobs/sign_in test/integration/sign_in_throttles_test.rb test/lib/admin_design_rules_test.rb test/lib/mail_guards_test.rb test/lib/admin_i18n_test.rb`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: a lock-out mails the account once an hour, from a job, so the request is the same either way`.

---

### Task 8: The reset request does the same work for every address, and the invitation is held to one answer

**Files:**
- Create: `app/jobs/password_reset_request_job.rb`, `test/jobs/password_reset_request_job_test.rb`
- Modify: `app/controllers/admin/passwords_controller.rb` (`create`)
- Test: `test/controllers/admin/passwords_controller_test.rb`, `test/controllers/invitations_controller_test.rb`

**Interfaces:**
- Produces: `PasswordResetRequestJob.perform_later(email_address, origin: nil)`, with `log_arguments = false`. `email_address` is the String typed, or `""` for anything else.

- [ ] **Step 1: Write the failing tests.**
  - `passwords_controller_test.rb`:
    - `test "a reset request runs the same statements and enqueues the same one job for a known and an unknown address"`;
    - `test "a reset request with an address that is a list enqueues the job with an empty address"`.
  - `password_reset_request_job_test.rb`:
    - `test "the job queues the reset mail for an account and nothing for an unknown address, logging no address"`;
    - `test "the origin reaches the mail as before"`.
  - `invitations_controller_test.rb`. If they are missing, add `test "check and update answer a tampered, a lapsed, a resent and a withdrawn token the same: status, body and no-store"` and `test "an invitation's answers name no account but the invitation's own"`. If an existing test holds this, name it in the commit body and add nothing.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** `create` enqueues the job and redirects. The long comment says what the job holds and why the request looks up nothing.
- [ ] **Step 4: Run.** `bin/rails test test/controllers/admin/passwords_controller_test.rb test/jobs test/mailers/passwords_mailer_test.rb test/controllers/invitations_controller_test.rb test/integration/opentelemetry_test.rb`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `fix: the reset request looks up nobody, so a known and an unknown address take the same time`.

---

### Task 9: The span-content guard

**Files:**
- Create: `test/integration/sign_in_telemetry_test.rb`

**Interfaces:**
- Consumes: every span of Tasks 1 to 8, through `Rails.application.config.x.otel_test_exporter`.

- [ ] **Step 1: Write the tests.** Plant per test `email = "planted.#{SecureRandom.hex(6)}@example.test"`, `password = "planted-#{SecureRandom.hex(12)}"`, and a token `"planted-token-#{SecureRandom.hex(12)}"`. A user made with the planted password stands for the successful case. The helper `written(spans)` joins every span's name, attribute keys and values, and events' names and attributes, as `opentelemetry_test.rb` does.
  - `test "a refused, a throttled and a successful password sign-in are auth spans under the request's server span"`:
    - names `auth.sign_in` and `auth.throttle`;
    - `auth.sign_in`'s parent is the root, and the root's kind is `:server`;
    - each `auth.throttle`'s parent is `auth.sign_in`;
    - `auth.outcome` is `refused`, then `locked` with `auth.bucket` `account` and `auth.tripped` true, then `ok`.
  - `test "no span of those sign-ins holds the email, the password or a part of its SHA-1"`. Search `written` for the email, the password, the full SHA-1 hex in both cases and its five-character upper-case prefix.
  - `test "a required bot check is a CLIENT span under the sign-in and holds no token"`, `with_bot_check(:failed)`.
  - `test "a leaked-password lookup on Your account is a CLIENT span under the request's and holds no part of the hash"`, `with_leaked_password_check`.
  - `test "a lock-out's mail is an auth.lockout_mail span under the request's, and its job's trace holds no email"`, which also runs `perform_enqueued_jobs` and reads the consumer trace.
  - `test "the address limit's answer is an auth.sign_in span with the address bucket"`.
- [ ] **Step 2: Run.** `bin/rails test test/integration/sign_in_telemetry_test.rb`. Expected: PASS. Any failure here is fixed in the owning task's file, not by loosening the test.
- [ ] **Step 3: Prove it guards.** Temporarily add `"auth.method" => email` in `PasswordAttempt` and see the second test fail, then revert. The commit body says so.
- [ ] **Step 4: Commit** `test: no sign-in span holds what was typed, and each is a child of the request's`.

---

### Task 10: The bot check on the sign-in panel (per the design agent's StudioSignIn card)

**Precondition:** "Design answer: the bot check's place" above is filled in. Otherwise stop with **NEEDS_CONTEXT**.

**Files:**
- Modify:
  - `app/views/admin/sessions/new.html.erb`;
  - `config/locales/admin/sessions.en.yml` (any words the card adds);
  - `app/controllers/admin/sessions_controller.rb` (the `content_security_policy` override);
  - `config/initializers/filter_parameter_logging.rb` (`:turnstile`).
- Create: `app/javascript/controllers/bot_check_controller.js`, `test/system/admin/sign_in_bot_check_test.rb`
- Test: `test/controllers/admin/sessions_controller_test.rb`

**Interfaces:**
- Consumes: `@bot_check` (Task 6): a `SignIn::BotCheck` or nil.
- Produces:
  - the element `<div data-controller="bot-check" data-bot-check-site-key-value="…" data-bot-check-size-value="…" data-bot-check-theme-value="…">`, placed where the card says, inside the sign-in `<form>`, so Turnstile's hidden `cf-turnstile-response` is posted with it;
  - nothing at all when `@bot_check` is nil.

- [ ] **Step 1: Write the failing tests.**
  - `sessions_controller_test.rb`:
    - `test "a first visit draws no bot check, and the page's policy is the site's"`;
    - `test "after three failures the page draws the bot check with the site key, and allows Cloudflare's frame on this page alone"`, where `Content-Security-Policy`'s `frame-src` names `https://challenges.cloudflare.com` and the reset page's does not;
    - `test "the Turnstile response is filtered from the log"` (`LogCapture` around a POST).
  - `sign_in_bot_check_test.rb`. One browser test, with `window.turnstile` stubbed by a script the test injects before connect, rendering a hidden input:
    - `test "the bot check renders once, posts its answer with the form, and is removed before Turbo caches the page"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement** to the card: the place, the gap, any words, `size`, `theme`, and the loading state. The controller loads the script once per document, renders in `connect` and removes in `disconnect`, and its header comment says why it is explicit (Turbo's snapshot).
- [ ] **Step 4: Run.** `bin/rails test test/controllers/admin/sessions_controller_test.rb test/lib/source_layout_test.rb test/lib/admin_i18n_test.rb test/integration/public_javascript_test.rb`. Then, after `bin/rails tailwindcss:build`: `bin/rails test test/system/admin/sign_in_bot_check_test.rb` and `bin/rails test test/system/admin/password_reset_test.rb`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: the bot check's widget on the sign-in panel, drawn only after repeated failures`.

---

### Task 11: The visitor's real address behind a proxy

**Why:** every per-address bucket (sign-in's 10 in 3 minutes, the new 50 an hour, the bot check's trigger, and the forms' own limit) keys on `request.remote_ip`. Production names no `trusted_proxies`. Behind Cloudflare, every visitor is then a few Cloudflare addresses, and 50 failures from anyone close sign-in for the whole site, owners included. That breaks the design's sixth goal. The coordinator's ruling: this cannot stay documented-only.

**Files:**
- Create: `lib/trusted_proxies.rb`. It is read before autoloading, from `config/environments/production.rb` or an initializer, following CLAUDE.md's `lib/` rule.
- Modify: `config/environments/production.rb` or the initializer; `Setup::SystemCheck`, which gains one row; its component and locale keys; `docs/reference/hosting.md`, both the variable table and the Forms section; `CLAUDE.md`'s Deploy paragraph, where it names `trusted_proxies`.
- Test: `test/lib/trusted_proxies_test.rb`, `test/models/setup/system_check_test.rb`, and an integration test of `remote_ip` behind a trusted proxy.

**Interfaces:**
- `TRUSTED_PROXIES`, an environment variable: a comma-separated list of CIDRs. They are added to Rails' default trusted proxies (the private ranges), never replacing them. A malformed entry stops the boot with a message that names it. Unset, it changes nothing.
- `Setup::SystemCheck` row "Visitor address":
  - **OK** when a request carries no `CF-Connecting-IP`, or when that header equals `request.remote_ip`.
  - **A warning** when the header is present and differs: "Requests come through Cloudflare, but the visitor's own address is not read: every visitor counts as Cloudflare's. Set TRUSTED_PROXIES to Cloudflare's ranges." It links the hosting page.
  - The header is never trusted to set the address, since it can be forged without Cloudflare in front. It only tells whether the setting is missing.
- `hosting.md`: how to fill `TRUSTED_PROXIES` with Cloudflare's published ranges (https://www.cloudflare.com/ips/), and that they change rarely and are re-checked at upgrades.

- [ ] **Step 1: Write the failing tests.**
  - The parser accepts IPv4 and IPv6 CIDRs and refuses a malformed one by name.
  - With `TRUSTED_PROXIES` set to a range, a request from that range carrying `X-Forwarded-For` gets the forwarded `remote_ip`. Without the setting, it gets the proxy's address.
  - The system check row is OK without the header, OK when the header equals `remote_ip`, and the warning when they differ.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** One reader for the variable; the row follows the existing rows' pattern and words-as-keys.
- [ ] **Step 4: Run** the tests above, `test/lib/environment_variables_test.rb` (the variable must be listed in `hosting.md`'s table, done in this task) and the system status tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat: TRUSTED_PROXIES, and System status says when Cloudflare's visitors all count as one address`.

---

### Task 12: The reference, the changelog and the pull request

**Files:**
- Modify:
  - `docs/reference/hosting.md`:
    - the "Describes" line gains `app/models/sign_in/`;
    - "What a host sets" gains `TURNSTILE_SITE_KEY`, `TURNSTILE_SECRET_KEY` and `LEAKED_PASSWORD_CHECK`;
    - "Every variable the code reads" gets the three rows: who sets them (host / a developer), the defaults (unset: no bot check; unset: the check is on), and Secret (`TURNSTILE_SECRET_KEY` yes, the others no);
    - a new section, "Sign-in on the open internet": the three buckets and their figures, the bot check (keys, Cloudflare's test keys for development, fail-open), the leaked check (what leaves, the switch, fail-open), the Cloudflare rate-limit rule to set by hand, that Cloudflare Access may stay as an extra layer, and the CDN hazard of Review Focus 1;
    - "Telemetry" gains "The CMS's own spans": the table of `SPANS` and `ATTRIBUTES`, the never list, and the Honeycomb query;
    - "What a change can break silently" gains the CDN bullet and "a new outside call made without `untraced`";
  - `docs/reference/access-control-and-audit.md`: "Auth" gains the `SignIn` layer and the three buckets. The audit section gains `session.locked`, its metadata and why it has no subject;
  - `docs/reference/mail.md`: the "Describes" line and the mailers gain `SignInMailer` and the two jobs. The reset section says the request enqueues `PasswordResetRequestJob` for every address;
  - `docs/reference/users-groups-tokens.md`: the leaked-password refusal on the five paths, and where the check runs;
  - `CLAUDE.md`: the reference index's authentication line names `app/models/sign_in/`, `app/jobs/sign_in/`, `app/mailers/sign_in_mailer.rb` and `app/values/visitor_address.rb`; the Deploy paragraph names the three new variables;
  - `CHANGELOG.md` `## Unreleased`: `### Added` (the throttles, the bot check, the leaked check, the lock-out mail, the spans, each one line with its figures) and, under `### Changed`, the reset request's job and the sessions limit's store.
- Test: `test/lib/environment_variables_test.rb`, `test/lib/source_layout_test.rb`

- [ ] **Step 1: Run the guard that is red.** `bin/rails test test/lib/environment_variables_test.rb`. Expected: FAIL naming `LEAKED_PASSWORD_CHECK`, `TURNSTILE_SECRET_KEY` and `TURNSTILE_SITE_KEY`.
- [ ] **Step 2: Write the reference.** The Cloudflare rule to set by hand:
  - Security → WAF → Rate limiting rules;
  - the expression `(http.request.uri.path eq "/<ADMIN_PATH>/sign-in" and http.request.method eq "POST")`;
  - counted by IP;
  - the action Managed Challenge (or Block).

  Its figures are checked against Cloudflare's current plan limits while writing (the free plan's period and timeout are fixed). The text says the rule is a first fence and the app's buckets stand without it.

  The Honeycomb query is two parts:
  - a credential-stuffing run: `WHERE name = auth.throttle AND auth.tripped = true`, `GROUP BY auth.bucket`, `COUNT`, a time series over the last 24 hours;
  - the refusals: `WHERE name = auth.sign_in AND auth.outcome != ok GROUP BY auth.outcome`.
- [ ] **Step 3: Run.** `bin/rails test test/lib`, then the whole unit suite once, `bin/rails test`. Then `bin/rubocop`, `bin/brakeman` (exit 0, with no new ignore) and `bin/bundler-audit`. Expected: PASS.
- [ ] **Step 4: Commit** `docs: sign-in on the open internet, its variables and its spans`.
- [ ] **Step 5: The pull request body** (written by the coordinator, never pushed by an implementer). It holds:
  - the summary;
  - the figures;
  - the decisions table's "why" column in one line each;
  - "Documentation":
    - the guide's signing-in page (the bot check, "Try again later", the lock-out mail);
    - its setting-a-password pages (the leaked refusal, in the wizard, the invitation, the reset, Your account and Users);
    - the integrator's hosting page (the three variables, the Cloudflare rule, trusted proxies behind a CDN);
  - "Migrations: none".

---

## Pre-flight

Done while writing this plan, against `main` at ee85098a plus the spec. No test database exists in this worktree, so nothing was run.

- **A file changed in two tasks:**
  - `sessions_controller.rb`: Tasks 6, 7 and 10;
  - `test/test_helper.rb`: Tasks 2, 3 and 4;
  - `sign_in_helper.rb`: Tasks 3 and 4;
  - `sign_in_throttles_test.rb`: Tasks 6 and 7.
- **Red mid-stack.** `environment_variables_test.rb` is red from Task 3 to Task 11, named in each commit body. Nothing else should be.
- **Verified in the code:**
  - `User.authenticate_by` hashes for an unknown address (Rails 8.1, `ActiveRecord::SecurePassword`). Task 6's hash count proves it before relying on it;
  - `rate_limit`'s default store is the controller's `cache_store`;
  - `Telemetry::WorkSampler` keeps every child of a server root;
  - the CSP sets `frame_src` and no `script_src`.
- **Not verified while planning:**
  - that Solid Cache 1.x's `increment` keeps the `expires_in` of the first write on later increments. Task 2 reads `SolidCache::Store#increment` first and says in `SignIn.store`'s comment what it found. If it does not keep it, each window's key carries its start (`floor(now / window)`) instead;
  - that `opentelemetry-instrumentation-net_http` (in `-all` 0.100) honours `untraced`. Tasks 3 and 4's stub-server tests decide it.

### Conflicts found, and rulings

| C | Conflict | Ruling | Why |
|---|---|---|---|
| C1 | §1 says the three buckets are "each counted on failed attempts only", and that the per-address one is "the existing `rate_limit`, kept as it is". That limit counts every POST, successes included. | Kept as it is (every attempt). Only the account and wide buckets count failures. | The design names it twice as unchanged. 10 in 3 minutes is never met by a person. |
| C2 | "Kept as it is" is a limit that never trips in tests (`null_store`). | It gains `store: SignIn.store`. The figures and the sentence are unchanged, and so are production and development. | The brief: a throttle must not silently do nothing in tests. |
| C3 | §1: "only the first five characters of its SHA-1 are sent". §7: never in a span "any part of its hash". The Net::HTTP instrumentation records the request's path, `/range/ABCDE`. | The lookup and siteverify run `untraced` inside their own CLIENT span. | Both sentences hold only this way. `PathScrubber` cuts queries, not paths. |
| C4 | §1's per-address buckets assume `request.remote_ip` is the person. Behind Cloudflare, which `config/deploy.yml` plans for, without its ranges in `trusted_proxies`, it is the edge. The wide cap then closes sign-in for everyone after 50 failures from anyone. | Documented and tested (Review Focus 1). No code can detect it. | The same hazard the forms' limit already documents. The fix is the host's configuration. |
| C5 | "A lock-out answers like any refusal, with the same sentence", while the existing per-address limit says "Try again later.". | The account bucket answers "Try another email address or password.". Both address buckets answer "Try again later.". | An address bucket says nothing about an account, and the design keeps that limit as it is. |
| C6 | §1 asks for "a dummy password hash when no account exists". `User.authenticate_by` already computes one. The parts that did differ are the reset request's and the lock-out mail's lookup and enqueue. | No dummy compare is added. Both lookups move into jobs, and the tests count hashes and statements. | A second dummy hash would make the unknown path slower than the known one. |
| C7 | §1 records `session.locked` and mails "when the email belongs to an account". Naming the account as the subject needs a lookup in the request, which breaks §1's equal timing. | `session.locked` has no subject and carries the email in its metadata, as `session.failed` does. The mail's lookup is the job's. | Equal timing is a goal, and the subject is not. |
| C8 | The spec is silent on Turnstile being unreachable. | Fails open, logged, span `unavailable`. | Its anti-goal names a provider outage locking an owner out, and the throttles still stand. |
| C9 | §7 lists "the lock-out and alert mails" as spans, but a mail is delivered by a job in its own trace. | `auth.lockout_mail` marks the enqueue in the request. The delivery is the job's consumer trace, which the instrumentation already records. | No span here is a root (§7). |
| C10 | §1's leaked check "when a password is set" includes the wizard, whose `Users::Save` runs inside `LOCK TABLE users`. | The lookup runs under that lock, bounded by 5 s. | One person, one row, and the wizard is the site's first minute. Moving the check out would mean a second call site. |
| C11 | §1 reviews "an invitation's acceptance" for enumeration. Its answers are judged by the token alone, and the "used" state names an account only to the token's holder. | No change. Task 8 holds the one answer with a test. | Nothing to equalise. |

## Self-review

1. **Spec coverage.**
   - §1: the throttles (Tasks 2 and 6), the bot check (3, 6 and 10), the leaked passwords (4 and 5), and enumeration and timing (6 and 8).
   - §5: the lock-out mail (7).
   - §6: hosting.md's Cloudflare rule, the keys, the switch and the spans (11).
   - §7: the tracer (1), the spans (2 to 8), the guard (9), and the docs and query (11). The OIDC callback's scrub is PR 4's.
   - §9: `SignIn` names no session, cookie, route or mail, and `Throttle`'s `scope:` and `PasswordAttempt`'s `accounts:` are the seam.
   - Not in PR 1, by the brief: §2, §3, §4, the other §5 mails, and §6's wizard passkey step and console reset.
2. **Step scan.** Each code step names its file, signature and pinned values. Each test step names its test and its assertions. The one look is deferred to the card, with a stop.
3. **Type consistency.**
   - `Throttle::Trip` is consumed in Tasks 6, 7 and 9.
   - `SignIn::Outcome`'s `status`, `account`, `trip` and `bot_check_due` are used in 6, 7 and 10.
   - `BotCheck.current` and `#site_key` are used in 6 and 10.
   - `LeakedPassword.check` is used in 5.
   - `Telemetry.in_span` and `Telemetry.record` are used in 2 to 7.
   - `with_bot_check` and `with_leaked_password_check` are used in 3 to 9.
4. **Review Focus.** Each of the five lines has its tests in the owning task (1: Tasks 6 and 11; 2: Task 6; 3: Tasks 2 and 6; 4: Tasks 4 and 5; 5: Tasks 3 and 6).
5. **Proportion.** Signatures, figures and test names, with no bodies. The decisions table carries the choices the spec left open.
