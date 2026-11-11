# CS Studio sign-in, part 2: sessions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CS Studio sessions end when idle (12 h) and absolutely (14 days), each person sees and ends their own sessions in Your account, an owner ends all of another user's, a sweep job removes expired rows, and every ending is audited and traced.

**Architecture:** `Session` gains `last_seen_at`, `expires_at` and `authenticated_with`; `Session.from_cookies` (the one lookup the controllers and the cable share) answers only a live session and ends an expired one through `Sessions::End`. Endings are services under a new `Sessions` namespace (`End`, `EndOthers`, `EndAll`), audited as `session.ended` with a reason; the sweep is `Sessions::SweepJob`. The screens are `Admin::AccountScreen::SessionsCardComponent` and `Admin::UsersScreen::SessionsZoneComponent`, drawn from the Design System's cards.

**Tech Stack:** Rails 8.1, Minitest + fixtures, ViewComponent, Stimulus, Solid Queue recurring jobs, the `useragent` gem (already in `Gemfile.lock` through Rails' `allow_browser`; add it to the `Gemfile` by name), OpenTelemetry through `Telemetry.in_span`.

**Spec:** `docs/superpowers/specs/2026-11-10-studio-sign-in-design.md`, §2 (sessions), §7 (telemetry, the session parts), §6 (docs), §8 (screens).

## Global Constraints

- Idle timeout **12 hours**; absolute timeout **14 days** (`Session::IDLE_TIMEOUT = 12.hours`, `Session::ABSOLUTE_TIMEOUT = 14.days`).
- `last_seen_at` is written **at most every five minutes** (`Session::SEEN_EVERY = 5.minutes`), with `update_column` (no `updated_at` churn, no callbacks).
- `authenticated_with` is one of `password`, `passkey`, `sso`, `recovery_code` (`Session::METHODS`); every session made in this PR is `password`.
- The cookie `session_id` is no longer `permanent`: it expires at the session's `expires_at`.
- Every ending records `session.ended` with `metadata["reason"]` one of `expired_idle`, `expired_absolute`, `ended_by_self`, `ended_by_owner`, `password_changed` (`sso_revoked` arrives with PR 4). Sign-out keeps its existing event `session.destroyed` (see Ruling R1).
- No ending uses `delete_all`: every row goes through `destroy`, so `Session#disconnect_cable` runs (`app/models/session.rb`).
- The migration deletes every existing session row; `CHANGELOG.md` names it under `### Migrations needing action`.
- Telemetry: span names join `Telemetry::SPANS`, attribute keys `Telemetry::ATTRIBUTES` (`lib/telemetry.rb`); no span holds an email, a session id, a cookie or a user agent string.
- Strings a person reads are keys (`config/locales/admin/…`); comments state invariants, never history; queries follow CLAUDE.md "Queries are Active Record, then Arel, then SQL".
- Test commands are prefixed `PGGSSENCMODE=disable`. Browser tests one file at a time, only when `sysctl -n vm.loadavg` is under 6.

## Rulings made in planning

- **R1 — sign-out stays `session.destroyed`.** The append-only log already holds `session.destroyed` rows whose sentence must keep reading "signed out", and `Users::LastSignIn` reads `session.created`. A second name for the same act would split the audit filter. Every other ending is `session.ended`. Cost if wrong: renaming later is one sentence and a filter entry.
- **R2 — one audit event per act, not per row.** "Sign out everywhere else", "End all sessions" and a password change record ONE `session.ended` with `metadata["count"]`; the sweep records at most one per reason per run (`expired_idle`, `expired_absolute`) with a count and no subject. A request that meets its own expired session records one event with the user as subject. Cost if wrong: the log shows fewer rows than sessions.
- **R3 — the expiry span is drawn only when a session is ended for expiry** (`auth.session`), never on a live request: a span on every signed-in request would be noise the WorkSampler keeps.
- **R4 — the owner zone's "End all sessions" is not offered on your own account** (Your account's "Sign out everywhere else" is that), and `Sessions::EndAll` refuses it.

## Review Focus

1. **A cable connection resuming an expired session** — the WebSocket's connect goes through `Session.from_cookies` too, so an expired cookie must be rejected there and the row ended (Task 2 test).
2. **Two tabs racing the five-minute `last_seen_at` write** — both may write; neither may raise or bump `updated_at` (Task 2 test: `update_column`, and `updated_at` unchanged).
3. **Ending a session id that is not yours** (a crafted DELETE with another user's session id, or one already gone) — ends nothing and answers exactly as for one of yours that had already ended ("That session had already ended."), so an id tells nothing (Task 3 and Task 6 tests).
4. **The current session in "Sign out everywhere else"** — must survive, and the person stays signed in on the answer (Task 6 test).
5. **A password change made by an owner for another user** — ends ALL that user's sessions (the acting session is not theirs) and audits `password_changed` once with the count; a change with no other sessions records nothing (Task 3 test).

---

### Task 1: The columns, the migration and the cookie

**Files:**
- Create: `db/migrate/20261111090000_add_expiry_to_sessions.rb`
- Modify: `db/schema.rb` (by migrating), `app/models/session.rb`, `app/controllers/concerns/authentication.rb` (`start_new_session_for`), `test/fixtures/sessions.yml` (if present; otherwise sessions are made in tests), `CHANGELOG.md`
- Test: `test/models/session_test.rb`, `test/integration/sessions_test.rb`

**Interfaces:**
- Produces: `Session::IDLE_TIMEOUT`, `Session::ABSOLUTE_TIMEOUT`, `Session::SEEN_EVERY`, `Session::METHODS`; columns `last_seen_at :datetime, null: false`, `expires_at :datetime, null: false`, `authenticated_with :string, null: false`; `Session.start(user:, method:, user_agent:, ip_address:, at: Time.current) -> Session` (sets `last_seen_at: at`, `expires_at: at + ABSOLUTE_TIMEOUT`); `Authentication#start_new_session_for(user, method: "password")`.

- [ ] **Step 1: Write the failing tests**
  - `session_test.rb` "a new session is seen now and ends fourteen days on": `Session.start(user: users(:reader), method: "password", user_agent: "UA", ip_address: "192.0.2.1", at: t)` → `last_seen_at == t`, `expires_at == t + 14.days`, `authenticated_with == "password"`.
  - "a method outside METHODS is refused": `Session.start(..., method: "magic")` raises `ActiveRecord::RecordInvalid`.
  - `sessions_test.rb` "the session cookie expires with the session": after a sign-in, the `Set-Cookie` for `session_id` carries an `expires` within a minute of 14 days ahead (freeze time).
- [ ] **Step 2: Run them; they fail** (`PGGSSENCMODE=disable bin/rails test test/models/session_test.rb test/integration/sessions_test.rb`).
- [ ] **Step 3: Migration** adds the three columns; in `up`, before adding them NOT NULL, it deletes every row of `sessions` (`execute "DELETE FROM sessions" # sql: …` is allowed only with the `# sql:` reason; prefer `Session.reset_column_information` then a plain model-free `delete` through `ActiveRecord::Base.connection`, a migration needing no callbacks: nobody is connected during a deploy's migrate). Add an index on `expires_at` and on `last_seen_at` (the sweep's reads). `down` removes the columns.
- [ ] **Step 4: `Session.start`** validates `authenticated_with` inclusion in `METHODS`. `start_new_session_for(user, method: "password")` calls it and writes `cookies.signed[:session_id] = { value: session.id, httponly: true, same_site: :lax, expires: session.expires_at }` (no `.permanent`). The three callers (`Admin::SessionsController#create`, `InvitationsController`, `SetupController`) need no change but are covered by the default.
- [ ] **Step 5: CHANGELOG** under `## Unreleased`: `### Migrations` the migration's version and one line; `### Migrations needing action`: "Everyone is signed out once: `20261111090000_add_expiry_to_sessions` deletes every open session, since none of them has an end. Each person signs in again." `### Changed`: the cookie is no longer permanent.
- [ ] **Step 6: Run the tests; they pass. Run `bin/changelog-guard origin/main`.**
- [ ] **Step 7: Commit** `feat: sessions carry when they were last seen, when they end and how they signed in`.

### Task 2: Expiry in the one lookup

**Files:**
- Modify: `app/models/session.rb`, `app/controllers/concerns/authentication.rb`, `app/channels/application_cable/connection.rb` (only if the signature changes), `lib/telemetry.rb`
- Create: `app/services/sessions/end.rb`
- Test: `test/models/session_test.rb`, `test/services/sessions/end_test.rb`, `test/channels/application_cable/connection_test.rb` (create if absent), `test/integration/sessions_test.rb`

**Interfaces:**
- Consumes: Task 1's columns and constants.
- Produces:
  - `Session#expiry(at = Time.current) -> nil | "expired_idle" | "expired_absolute"` (absolute wins when both hold: `at >= expires_at` → absolute; `at >= last_seen_at + IDLE_TIMEOUT` → idle).
  - `Session#seen!(at = Time.current) -> void`: `update_column(:last_seen_at, at)` only when `last_seen_at <= at - SEEN_EVERY`.
  - `Session.from_cookies(cookies, at: Time.current) -> Session | nil`: finds the row; an expired one is ended with `Sessions::End.call(session, reason: session.expiry(at), actor: nil)` and nil answered; a live one gets `seen!(at)` and is answered.
  - `Sessions::End.call(session, reason:, actor: Current.actor) -> ApplicationService::Result`: destroys the row and records `session.ended` (`subject: session.user`, `metadata: { "reason" => reason, "count" => 1 }`) in one transaction. Reasons accepted: `Session::END_REASONS = %w[expired_idle expired_absolute ended_by_self ended_by_owner password_changed]`; another raises `ArgumentError`. No authorization here (it is the low-level ending; callers authorize — Task 3's services do).
  - `Telemetry::SPANS` += `auth.session`, `auth.session_sweep`; `ATTRIBUTES` += `auth.session.reason`, `auth.session.count`.
- [ ] **Step 1: Failing tests**
  - "a session unused for 12 hours is idle-expired, one at 14 days absolute, and absolute wins": travel to each boundary (`last_seen_at + 12.hours` exactly is expired; one second earlier is live).
  - "from_cookies ends an expired session and answers nil": the row is gone, one `session.ended` with reason `expired_idle`, `actor_id` nil, subject the user; the user's cable got a disconnect (reuse `disconnects`).
  - "from_cookies writes last_seen_at at most every five minutes and never updated_at": at +4 min no write; at +5 min written; `updated_at` unchanged both times.
  - Review Focus 1, `connection_test.rb` "an expired cookie is refused at connect": `connect cookies:` with a signed `session_id` of a session past 14 days → `assert_reject_connection`; the row is gone.
  - Review Focus 2: covered by the `updated_at` assertion above.
  - `sessions_test.rb` "an idle-expired session sends the next request to sign-in": sign in, travel 12 hours, GET `/cs-studio` → redirect to sign-in.
  - Telemetry, in `sessions_test.rb` with the in-memory exporter (as `test/integration/sign_in_spans_test.rb` or the PR-1 span test does): the expired request exports one `auth.session` span, child of the request span, attributes exactly `{ "auth.session.reason" => "expired_idle" }`; a live request exports no `auth.session`.
- [ ] **Step 2: Run; they fail.**
- [ ] **Step 3: Implement** the interfaces above; `from_cookies` wraps the ending in `Telemetry.in_span("auth.session", attributes: { "auth.session.reason" => reason })`. `Authentication#find_session_by_cookie` and the cable's `connect` keep calling `Session.from_cookies(cookies)`.
- [ ] **Step 4: Audit sentence.** `app/models/audit/sentence.rb`: add `session.ended` to `SPECIAL_ACTIONS`; its sentence by reason (the subject user is the linked name where there is one, `count` read from metadata, `n` below):
  - `expired_idle`: "Session of <user> ended after 12 hours unused" / summary with no subject: "<n> sessions ended after 12 hours unused"
  - `expired_absolute`: "Session of <user> ended 14 days after sign-in" / summary: "<n> sessions ended 14 days after sign-in"
  - `ended_by_self`: "<actor> ended <n> of their other sessions" (n = 1: "ended one of their other sessions")
  - `ended_by_owner`: "<actor> ended every session of <user>" ("(<n>)" appended)
  - `password_changed`: "<n> sessions of <user> ended by a password change"
  - Add `session.ended` to `SECURITY_ACTIONS` (every ending is security-relevant; the list is by action). The expiries have no actor: the sentence builds them without one when `actor_id` is nil, as `NO_ACTOR`'s actions are built, without adding `session.ended` to `NO_ACTOR` (its other reasons have an actor). Extend `test/models/audit/sentence_test.rb` with one test per reason.
- [ ] **Step 5: Run the tests above plus `test/models/audit` and `test/lib`; all pass.**
- [ ] **Step 6: Commit** `feat: an expired session is ended at its next request or connection, audited and traced`.

### Task 3: The endings a person asks for

**Files:**
- Create: `app/services/sessions/end_others.rb`, `app/services/sessions/end_all.rb`
- Modify: `app/services/users/owner_protection.rb` (`end_sessions_after_password_change`)
- Test: `test/services/sessions/end_others_test.rb`, `test/services/sessions/end_all_test.rb`, `test/services/users/update_password_test.rb`, `test/services/users/save_test.rb`

**Interfaces:**
- Consumes: `Sessions::End`, `Session::END_REASONS`.
- Produces:
  - `Sessions::EndOthers.call(user: Current.user, keep: Current.session, only: nil) -> Result`: ends the user's sessions but `keep`; `only:` a session id ends that one session (found through `user.sessions.find_by(id:)`; nil, or `keep` itself, → an `ok` result with `value: 0`, nothing ended or recorded: the controller answers it as already ended). Records ONE `session.ended` `{ reason: "ended_by_self", count: n }` with the user as actor and subject, nothing when n = 0. `ok` result with `value: n`.
  - `Sessions::EndAll.call(user, actor: Current.actor) -> Result`: owner-only (`Users::Manageability.actor_owner?(actor)`; else `denied("users.manage", user)` as `OwnerProtection#owner_only_denial` answers), refused for `user == actor` (R4) with `I18n.t("admin.components.users_screen.sessions_zone.reason_own")` (Task 7 adds the words); ends all; one event `{ reason: "ended_by_owner", count: n }`, nothing when n = 0.
  - `end_sessions_after_password_change` keeps its rule (which sessions) and records one `session.ended` `{ reason: "password_changed", count: n }` subject the user, when n > 0, in the service's transaction.
- [ ] **Step 1: Failing tests**: each service's counts, events (exactly one, the metadata above), the kept session alive, cable disconnects of the ended rows; `only:` with another user's session id, an unknown id, or `keep`'s id → `value: 0`, nothing ended, nothing recorded (Review Focus 3, service half); `EndAll` by a non-owner admin → denied, nothing ended; on own account → refused; Review Focus 5: an owner changing another user's password through `Users::Save` ends all that user's sessions and records `password_changed` with the count; a change with none open records no `session.ended`.
- [ ] **Step 2: Run; fail. Step 3: Implement. Step 4: Run plus `test/services/users`; pass.**
- [ ] **Step 5: Commit** `feat: ending your other sessions, an owner ending all of someone's, and a password change say so in the audit log`.

### Task 4: The sweep

**Files:**
- Create: `app/jobs/sessions/sweep_job.rb`
- Modify: `config/recurring.yml` (production, development, test: `sessions_sweep`, `class: Sessions::SweepJob`, `queue: default`, `schedule: every hour at minute 40`), `app/models/session.rb` (scopes)
- Test: `test/jobs/sessions/sweep_job_test.rb`, `test/lib/recurring_schedule_test.rb` (if such a guard exists, it learns the job)

**Interfaces:**
- Produces: `Session.expired_absolute(at)` (`where(expires_at: ..at)`), `Session.expired_idle(at)` (`where(last_seen_at: ..(at - IDLE_TIMEOUT))`; the job destroys the absolute ones first, so an idle read after them holds only idle ones), each with a one-line comment saying what it answers. `Sessions::SweepJob#perform(at: Time.current)`: destroys each expired row in batches of 500 (`find_each` + `destroy`), absolute first, then idle; records at most two `session.ended` events (no actor, no subject, `count`), inside `Telemetry.in_span("auth.session_sweep", attributes: { "auth.session.count" => total })` (record the count with `Telemetry.record` once known).
- [ ] **Step 1: Failing tests**: three sessions (live, idle, absolute) → only the live one remains; two events with counts 1 and 1; a run with nothing to do records nothing; the job's span has the count and is not a root when run under a job span (`perform_now` inside the test's own parent span) — or, as the PR-1 job (`SignIn::LockoutMailJob`) test does it.
- [ ] **Step 2–4: fail, implement, pass.**
- [ ] **Step 5: Commit** `feat: an hourly sweep removes expired sessions`.

## Screens (Design System v205, card `StudioSessions`; owner's answers 2026-11-11)

The owner chose: one row's End acts at once (no confirm), the two bulk endings confirm; the sign-in panel says the session ended only to a browser whose cookie names a gone session; on your own account the user editor's Sessions zone is drawn disabled with its reason. The words below are the card's, verbatim; every one is a key.

`config/locales/admin/accounts.en.yml`, `admin.accounts.sessions`:

```yaml
title: "Sessions"
intro: "Where you're signed in. End a session you don't recognise, then change your password."
this_session: "This session"
device: "%{browser} on %{os}"
browser_only: "%{browser}"
os_only: "A browser on %{os}"
unknown_device: "Unknown browser"
active: "Active %{time}"
active_now: "Active now"
signed_in_with:
  password: "Signed in with password"
  passkey: "Signed in with a passkey"
  sso: "Signed in with single sign-on"
  recovery_code: "Signed in with a recovery code"
end: "End"
end_label: "End the session in %{device}"
others: { one: "1 other session", other: "%{count} other sessions" }
none_else: "You're not signed in anywhere else."
end_others: "Sign out everywhere else…"
end_others_title: "Sign out everywhere else?"
end_others_body:
  one: "Your other session ends, and that browser must sign in again. You stay signed in here."
  other: "Your %{count} other sessions end, and those browsers must sign in again. You stay signed in here."
end_others_confirm: "Sign out everywhere else"
ended: "Session ended."
already_ended: "That session had already ended."
ended_others: { one: "Signed out of 1 other session.", other: "Signed out of %{count} other sessions." }
```

`config/locales/admin/users_screen.en.yml`, `admin.components.users_screen.sessions_zone`:

```yaml
heading: "Sessions"
body:
  one: "%{name} has 1 open session. Ending it signs %{name} out everywhere."
  other: "%{name} has %{count} open sessions. Ending them signs %{name} out everywhere."
body_none: "Ending sessions signs a person out everywhere."
reason_none: "%{name} has no open sessions."
reason_own: "End your own sessions from Your account."
trigger: "End all sessions…"
title: "End all of %{name}'s sessions?"
confirm_body: "%{name} is signed out on every browser and must sign in again. Their saved work stays; text they were still typing may be lost."
confirm: "End all sessions"
ended: "%{name} is signed out everywhere."
```

`admin.sessions.ended`: "Your session ended. Sign in again." (with the sign-in panel's keys).

### Task 5: The device a session is in

**Files:**
- Create: `app/values/session_device.rb`
- Modify: `Gemfile` (`gem "useragent"`, the version already locked), `config/locales/admin/accounts.en.yml` (the `admin.accounts.sessions` block above)
- Test: `test/values/session_device_test.rb`

**Interfaces:**
- Produces: `SessionDevice.new(user_agent_string) -> SessionDevice`; `#browser -> String | nil` (the `useragent` gem's browser name, nil for none/unknown), `#os -> String | nil` (a person's OS name: "macOS", "Windows", "iOS", "Android", "Linux", "ChromeOS"; nil otherwise), `#key_and_values -> [String, Hash]` (`["device", {browser:, os:}]`, `["browser_only", …]`, `["os_only", …]` or `["unknown_device", {}]`). A value object: it reads no locale; the component turns it into words.
- [ ] **Step 1: Failing tests** with real user agent strings: Firefox on macOS → `["device", { browser: "Firefox", os: "macOS" }]`; Chrome on Windows; Safari on iOS (iPhone); Chrome on Android; `curl/8.4.0` → browser "curl"? — whatever the gem answers for a non-browser is NOT shown: a non-browser (`UserAgent#bot?`, or a product the gem names outside its browser list) is `os_only`/`unknown_device`; nil and "" → `unknown_device`; a 1000-character junk string → `unknown_device`, no raise.
- [ ] **Step 2–4: fail, implement, pass.** **Step 5: Commit** `feat: a session's browser and system, read from its user agent`.

### Task 6: Your account's Sessions card and its two endings

**Files:**
- Create: `app/components/admin/account_screen/sessions_card_component.rb` + `.html.erb`, `app/controllers/admin/account_sessions_controller.rb`, `app/assets/images/icons/monitor-smartphone.svg` (Lucide's `monitor-smartphone`, in the same form as `user.svg`; `LICENSE-lucide` covers it)
- Modify: `config/routes.rb`, `app/views/admin/accounts/edit.html.erb` (the third card after the Password card, OUTSIDE both forms), the icon registry the settings card reads (`icon: :monitor_smartphone`, `family: :neutral`), `test/lib/admin_i18n_test.rb` (`CONVERTED` gains the component), `config/locales/admin/account_screen.en.yml` only if the component scope demands its own file (`test/lib/source_layout_test.rb` decides: one locale file per component folder; then the `admin.accounts.sessions` keys move there as `admin.components.account_screen.sessions_card.*` — follow the guard, keep the words)
- Test: `test/components/admin/account_screen/sessions_card_component_test.rb`, `test/controllers/admin/account_sessions_controller_test.rb`, `test/system/admin/account_sessions_test.rb`

**Interfaces:**
- Consumes: `SessionDevice`, `Sessions::EndOthers` (Task 3), `Session` columns.
- Produces: routes `delete "account/sessions/:id", to: "account_sessions#destroy", as: :account_session` and `delete "account/sessions", to: "account_sessions#destroy_others", as: :account_sessions`; `Admin::AccountScreen::SessionsCardComponent.new(sessions:, current:)`, its row's DOM id `session-<id>`, the card's id `account-sessions`.
- The card (from `StudioSessions`): `SettingsCardComponent` heading "Sessions", intro, icon `:monitor_smartphone`; rows: the current session first, then the others by `last_seen_at` desc. Line 1: the device words, plus `Admin::Ui::BadgeComponent` (neutral) "This session" on the current one. Line 2 joined by " · ": the address (`ip_address`, omitted when blank), "Active now" on the current one / "Active %{time}" with `Admin::Ui::TimeAgoComponent` on the others, and `signed_in_with.<method>`. Each other row: a small secondary `button_to` "End" (`aria-label` `end_label`) DELETE `account_session_path`. Foot: `others` count and "Sign out everywhere else…" (small secondary) opening `Admin::Ui::ConfirmDialogComponent` (not destructive; the primary confirms with `end_others_confirm`, body `end_others_body` by count); with no other session the foot says `none_else` and the button is not drawn. Narrow: the details wrap under the device; End stays at the row's end. Not a form field of either form; no save bar, never counted by "Leave without saving?".
- Answers: `destroy` → `Sessions::EndOthers.call(only: params[:id])`; Turbo Stream: remove `session-<id>` (also when nothing was ended), redraw the foot, a toast `ended` (n = 1) or `already_ended` (n = 0), via `Admin::ToastStream`; focus moves to the next row's End or the foot's button (a small Stimulus controller `admin--account--sessions` in `app/javascript/controllers/admin/account/`, which exists for the password answer, connected on the card; it moves focus after the stream's removal). Without Turbo: redirect to `account#sessions` anchor with the flash. `destroy_others` → `Sessions::EndOthers.call`; redirect to the account page (`status: :see_other`, `anchor: "sessions"`), toast `ended_others` by count. Both are open to every signed-in user, for `Current.user` only (the request names no user).
- [ ] **Step 1: Failing tests**
  - Component: current first with "This session" and no End; others ordered; device words for the four `SessionDevice` cases; "Active now" vs "Active …"; blank address omitted; the foot's count and button vs `none_else` with no button.
  - Controller: End of my other session → 200 stream removing it, `session.ended` `ended_by_self` count 1; End of another user's session id → the same 200 answer with `already_ended`, their session alive, nothing recorded (Review Focus 3); End of my own current id → `already_ended`, still signed in; `destroy_others` → only the current remains, redirect with the toast, still signed in (Review Focus 4); signed out → redirect to sign-in.
  - Browser (one file; `visit_screen`): End a row → it goes, the toast reads "Session ended.", focus on the next End; "Sign out everywhere else…" → the dialog, confirm → only "This session" left and "You're not signed in anywhere else.".
- [ ] **Step 2–4: fail, implement, pass** (`bin/rails tailwindcss:build` once before the browser test, never during).
- [ ] **Step 5: Commit** `feat: Your account lists your sessions, and ends one or all the others`.

### Task 7: The user editor's Sessions zone

**Files:**
- Create: `app/components/admin/users_screen/sessions_zone_component.rb` + `.html.erb`
- Modify: `app/views/admin/users/edit.html.erb` (between the Owner zone and the Delete zone, for an owner viewer only, as the Owner zone is drawn), `config/routes.rb` (`member { delete :sessions }` in the users resources → `Admin::UsersController#sessions`), `app/controllers/admin/users_controller.rb`, `config/locales/admin/users_screen.en.yml` (the block above)
- Test: `test/components/admin/users_screen/sessions_zone_component_test.rb`, `test/controllers/admin/users_controller_test.rb`

**Interfaces:**
- Consumes: `Sessions::EndAll` (Task 3).
- Produces: `Admin::UsersScreen::SessionsZoneComponent.new(user:, own:, count:, url_options: {})`, `self.dialog_id(user) = "sessions-user-#{user.id}"`.
- The zone: `Admin::Ui::ActionZoneComponent` heading "Sessions", body `body` by count (`body_none` at 0), `pending_lock: true` like the Owner zone; trigger "End all sessions…" (small secondary) opening a `ConfirmDialogComponent` (title, `confirm_body`, primary `confirm`) whose form DELETEs `sessions_admin_user_path`. Disabled with `reason_none` at 0 sessions, with `reason_own` on your own account (owner's answer: drawn, disabled). The action: `Sessions::EndAll.call(@user)`; ok → redirect to the editor (`see_other`) with notice `ended`; refused → as `owner` does (`forbidden_or(result)`).
- [ ] **Step 1: Failing tests**: the zone's body by count, disabled states and reasons; an owner ends another user's 2 sessions → both gone, one event `ended_by_owner` count 2, the notice; a non-owner admin → 403/404 as the owner action answers, nothing ended; own account → refused, nothing ended; the zone is not drawn for a non-owner viewer.
- [ ] **Step 2–4. Step 5: Commit** `feat: an owner ends every session of another user from the user editor`.

### Task 8: The sign-in panel after an ended session

**Files:**
- Modify: `app/controllers/concerns/authentication.rb` (`request_authentication`), `app/views/admin/sessions/new.html.erb`, `config/locales/admin/sessions.en.yml` (`admin.sessions.ended`)
- Test: `test/integration/sessions_test.rb`

**Interfaces:**
- `request_authentication`: when the request carries a signed `session_id` cookie that `Session.from_cookies` did not resolve, it deletes the cookie and sets `flash[:session_ended] = true` before the redirect; the sign-in page draws `Admin::Ui::NoticeComponent` neutral, compact, role note, `admin.sessions.ended`, above the form, only for that flash (and not together with an `alert`). A browser without the cookie never sees it; Sign out (`terminate_session` deletes the cookie first) says nothing; it names no email.
- [ ] **Step 1: Failing tests**: a session ended elsewhere (destroy it) → the next GET redirects to sign-in, which shows "Your session ended. Sign in again." once, and the `session_id` cookie is cleared; idle expiry → the same; after Sign out → no notice; a fresh browser → no notice; a forged unsigned cookie → no notice.
- [ ] **Step 2–4. Step 5: Commit** `feat: sign-in says a session ended to the browser it ended in`.

### Task 9: Docs, the Design System stamp and the changelog

**Files:**
- Modify: `docs/reference/access-control-and-audit.md` (sessions: the limits, the lookup's expiry, the endings and `session.ended`'s reasons, R1/R2 as invariants), `docs/reference/hosting.md` ("Telemetry": `auth.session` and `auth.session_sweep` with their attributes; a Honeycomb query for sessions ended by reason), `docs/reference/users-groups-tokens.md` (the Sessions zone), `test/support/design_system_entries.rb` (`VERSION` → the Design System's latest index id at the time of this task — `1794401715-7a0f` (v205) unless the design agent has published since — and an entry for `StudioSessions` as its other Studio · Screens entries are written), `CHANGELOG.md` `## Unreleased` (`### Added`: the limits, Your account's Sessions card, the owner's End all sessions, the sweep, the sign-in sentence, `session.ended`, the spans; `### Changed`: a password change's endings are now audited; `### For a gem or an outside caller`: `Session.from_cookies` answers only a live session and ends an expired one; `start_new_session_for` takes `method:`)
- Test: `test/lib` (the docs guards, the environment-variable table, the Design System entries test), `bin/changelog-guard origin/main`
- [ ] **Step 1:** write; **Step 2:** `PGGSSENCMODE=disable bin/rails test test/lib`; `bin/changelog-guard origin/main`; pass. **Step 3: Commit** `docs: sessions in the reference, the changelog and the Design System stamp`.
