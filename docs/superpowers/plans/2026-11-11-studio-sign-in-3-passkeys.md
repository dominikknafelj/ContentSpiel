# CS Studio sign-in, part 3: passkeys and recovery codes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A person signs in to CS Studio with a passkey alone, or with a password followed by a passkey or a recovery code. They manage their passkeys and ten single-use recovery codes in Your account, behind a "Confirm it's you" step. An owner sets who must hold a passkey, and a person that covers is taken to enrolment at their next sign-in. The wizard offers the founding owner a passkey. The console's reset can clear a lost owner's passkeys. Each step is audited, mailed where the spec says, and traced.

**Architecture:**
- **The WebAuthn and code checks are plain objects** in the `SignIn` namespace, as PR 1's throttle is (spec §9). A second kind of sign-in can call them:
  - `SignIn::RelyingParty`: which domain a passkey belongs to;
  - `SignIn::PasskeyRegistration` and `SignIn::PasskeyCheck`: the two ceremonies, over `webauthn-ruby`;
  - `SignIn::Proof`: a second proof of an account already named (a recovery code, a passkey or the password), counted in the account's throttle bucket.

  None of them knows a session, a cookie, a route or a mail.
- **CS Studio's own parts:**
  - the records `Passkey` and `RecoveryCode`;
  - the services `Passkeys::Add`, `Passkeys::Rename`, `Passkeys::Remove` and `RecoveryCodes::Generate`;
  - the policy, `Passkeys::Policy`, stored on `site_settings`;
  - two session columns, `confirmed_at` (Confirm it's you) and `enrolment_due` (the policy at sign-in);
  - the controllers: sign-in's passkey actions, `Admin::SecondFactorsController`, `Admin::ConfirmationsController`, `Admin::PasskeysController`, `Admin::RecoveryCodesController`, `Admin::EnrolmentsController`, and the wizard's `passkey` step.
- **The browser side** is the WebAuthn API with no npm: one plain module, `app/javascript/passkeys/ceremony.js`, used by four Stimulus controllers.

**Tech Stack:** Rails 8.1, `webauthn` (webauthn-ruby, 3.5.x; `WebAuthn::RelyingParty`, `WebAuthn::Credential`, `WebAuthn::FakeClient` in tests), `public_suffix` (already locked), Minitest with fixtures, ViewComponent, Stimulus over import maps, Cuprite with Chrome's virtual authenticator (`WebAuthn.*` DevTools commands) for the browser tests, OpenTelemetry through `Telemetry.in_span`.

**Spec:** `docs/superpowers/specs/2026-11-10-studio-sign-in-design.md`, which this plan implements for:
- §3, whole;
- §5, the passkey and recovery-code mails;
- §6, the wizard and the console reset;
- §7, the passkey and recovery-code spans;
- §9, the shape of `SignIn`.

The screens and every word are in `docs/superpowers/specs/2026-11-11-passkeys-screens.md`. That is Design System v208, plus v209 for "Confirm it's you". Read both before any task.

Not here: SSO (§4, PR 4), and the new-browser mail of §5, which the spec leaves to the builder and this plan drops.

**One pull request** on branch `passkeys`, from `main` 158e1bab.

## Global Constraints

- **The figures:**
  - ten codes (`RecoveryCode::COUNT = 10`), each `XXXX-XXXX`;
  - the second step is held 5 minutes (`SignIn::SECOND_STEP_LIFETIME = 5.minutes`);
  - Confirm it's you lasts 10 minutes (`Session::CONFIRM_WINDOW = 10.minutes`);
  - a WebAuthn challenge lives 5 minutes and is used once (`PasskeyChallenges::LIFETIME = 5.minutes`).
- **The policy:**
  - its values are `nobody`, `owners_and_admins` and `everyone` (`SiteSetting::PASSKEY_POLICIES`);
  - unset, it is `owners_and_admins` in production and `nobody` in development and test (owner decision 2);
  - it takes effect at each covered person's next sign-in, and an open session carries on (owner decision 3);
  - "admins" are holders of `users.manage`, `groups.manage` or `tokens.manage` (`Passkeys::Policy::ADMIN_PERMISSIONS`).
- **The account's second factor.** An account that holds a passkey or an unused recovery code is never signed in by its password alone (`User#second_factor?`).
- **Failures count in the account's bucket.** A wrong second step (a code or a passkey) and a wrong password in Confirm it's you count there, or in the known device's bucket (PR 1's `SignIn::Throttle`). A wrong code and a used code give the same sentence.
- **No secret leaves its place.** These reach no span, event, log line, audit snapshot, page attribute or Turbo cache:
  - passkey material (the credential JSON, a public key, a challenge, a credential id);
  - a recovery code, or its digest;
  - the typed password or email.

  `filter_parameters` gains `:credential` and `:recovery_code`. The codes are drawn once, as text in no attribute, and taken back at `turbo:before-cache` and `pagehide`.
- **CLAUDE.md binds every task.** In particular:
  - `Audit.record` is the one audit path (services use `record_event`);
  - every string a person reads is a key, with the screens file's words verbatim;
  - the dependency direction holds: `SignIn::*` and the services name no controller, component or route; a mail's origin comes in as `origin:`;
  - queries follow "Active Record, then Arel, then SQL";
  - a single-column write on a table no public page reads carries `# version: none (<reason>)` (`test/lib/version_bump_test.rb`);
  - no `Admin::<Domain>`: the screens' components are `Admin::AccountScreen::…`, `Admin::SettingsScreen::…` and `Admin::Ui::…`, never `Admin::Passkeys`.
- **The comment rule.** A comment states an invariant, a hazard or a reason, never a plan step. Before each commit, PR 1's grep runs over the added lines and prints nothing (PR 1 plan, "Comment rule").
- **Tests and the machine.**
  - The worktree runs `bin/rails db:test:prepare` once.
  - Browser tests run one file at a time, after `bin/rails tailwindcss:build`, never beside a build or `bin/dev`, and only while `sysctl -n vm.loadavg` is under the core count.
  - No test reaches the network: `WebAuthn::FakeClient` stands in for an authenticator in unit and integration tests, and Chrome's virtual authenticator in browser tests.
  - A new test file joins a shard if `test/lib/test_shards_test.rb` says so.
- **Commits** follow conventional commits, and each ends with:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT`

## Rulings made in planning

Each ruling is one line: the decision, then the cost if it is wrong.

- **R1, the tables.**
  - `passkeys`: `user_id` (FK, index), `external_id` string NOT NULL UNIQUE (the credential id, base64url), `public_key` text NOT NULL (COSE, base64url), `sign_count` bigint NOT NULL default 0, `name` string NOT NULL (at most 60 characters, `Passkey::NAME_LIMIT`), `transports` string[] NOT NULL default `{}`, `last_used_at` datetime, and timestamps.
  - `recovery_codes`: `user_id` (FK), `digest` string NOT NULL, `used_at` datetime, `generated_at` datetime NOT NULL; UNIQUE `(user_id, digest)`.
  - `users.webauthn_id` string UNIQUE, nullable: the random user handle, set at the first registration.
  - Both new tables are `dependent: :delete_all` from `User`.

  Cost if wrong: a column migration.
- **R2, the codes.** Eight characters of Crockford base32 (`0-9 A-Z` without `I L O U`), shown as `XXXX-XXXX`. A code typed is upper-cased, spaces and hyphens are dropped, `O` becomes `0`, and `I` and `L` become `1`. Its digest is HMAC-SHA256 under `Rails.application.key_generator`, with purpose `"content_spiel recovery code"`, and it is found by `(user_id, digest)`. Using a code is one `UPDATE … WHERE used_at IS NULL` (`update_all` == 1), so two tabs cannot both use one. Cost if wrong: a stolen database with a stolen secret makes 40 bits brute-forceable offline; bcrypt would cost ten hashes per attempt.
- **R3, the relying party.** `SignIn::RelyingParty.for(address:, request_origin:, name:)`:
  - With `PUBLIC_HOST` set, the id is the registrable domain of its host (`PublicSuffix.domain`, the full list with its private section), or the host itself when it is `localhost` or an IP. The one allowed origin is `SiteAddress#origin`.
  - With no address (development and test), the id is the request's host and the origin the request's (`localhost`; `www.example.com` in integration tests).
  - It is `nil` for an IP-literal request host. Then no passkey button is drawn, and every passkey endpoint answers 404.

  Cost if wrong: a development site reached at 127.0.0.1 offers no passkey.
- **R4, the challenges.** They are kept in the Rails session (the encrypted cookie store) under `:passkey_challenge` as `{ "purpose", "challenge", "at" }`. One is taken once, whatever the answer. One older than 5 minutes, or issued for another purpose (`sign_in`, `second_factor`, `confirm`, `register`), is no challenge. Cost if wrong: a sign-in page left open for over 5 minutes needs one more press (the script fetches anew after a refusal).
- **R5, the second step's cookie.** `cs_second_factor`: `cookies.encrypted`, HttpOnly, SameSite Lax, Secure over HTTPS, expiring in 5 minutes. It holds `{ "user_id", "at" }` and no password, and is re-checked against `at`. It is written only after a right password, and deleted on success, on Start over and on expiry. Cost if wrong: none outside the five minutes.
- **R6, the buckets.**
  - A right password for an account with a second factor is answered `:second_factor_required`. The password step's count in the account (or device) bucket stands until the second step succeeds. Its address counts are taken back at once (`Throttle#release_address`), so one full sign-in costs the address one count, as before.
  - The second step and the confirmation reserve in the account (or device) bucket again, before they check anything.
  - A passkey sign-in, with no account named until it is verified, counts in the wide address bucket only (`Throttle#reserve_address`), and is never refused by an account's lock. A passkey cannot be guessed, and a bot naming a credential id must not lock its account.

  Cost if wrong: a covered person's first wrong code is their second count.
- **R7, the known-device cookie** (`cs_known_device`) is written only once a sign-in is whole (`Admin::SignInCompletion#complete_sign_in`), never after the password step alone. Otherwise a stolen password would earn its own device bucket, beside the account's lock. Cost if wrong: the PR 1 protection is bypassed. Review Focus 1 holds it.
- **R8, Confirm it's you.**
  - It is `sessions.confirmed_at`, which `Session.start` sets to the sign-in time and `Session#confirm!` sets after a confirmation.
  - Four actions are gated on the server (`Admin::RecentConfirmation`): registration options, adding a passkey, removing one, and generating codes.
  - A gated request outside the window writes nothing. JSON gets 403 `{"confirm":true}`. A Turbo Stream gets 403 with a stream that connects a `request` target of `admin--passkeys--confirm`, which opens the dialog, then sends the remembered form or call again.
  - Rename and ending a session are not gated.

  Cost if wrong: a crafted request lands on 403, never on a write.
- **R9, the dialog's place.** Your account and the enrolment page both draw the dialog, so it is `Admin::Ui::ConfirmIdentityDialogComponent` (CLAUDE.md, "Where a component goes"). Its keys therefore live under `admin.components.ui.confirm_identity_dialog.*`, not v209's `admin.components.account_screen.confirm_dialog.*`, with the words verbatim. The one-locale-file-per-folder guard decides the path. Cost if wrong: a key path, and the design file's line.
- **R10, enrolment.**
  - `Session.start` takes `enrolment_due:`. `start_new_session_for` passes `Passkeys::Policy.current.enrolment_due?(user)`, so a policy change reaches a person at their next session only.
  - The guard is `Admin::PasskeyEnrolment#require_passkey_enrolment`, a `before_action` in `Admin::BaseController` and `PreviewController`.
    - It is skipped by `EnrolmentsController`, `PasskeysController#options` and `#create`, and `ConfirmationsController`. Sign-out is `Admin::SessionsController`, outside the base.
    - A page GET is redirected to `admin_enrolment_path`. A Turbo GET gets PR 2's whole-page answer. Anything else gets 403.
  - `Passkeys::Add` clears `enrolment_due` on every session of the person.

  Cost if wrong: one guard to move.
- **R11, the policy's storage.**
  - `site_settings.passkey_policy` is a nullable string. Nil is the environment's default (`SiteSetting#effective_passkey_policy`), so an existing site needs no backfill and "until an owner changes it" holds.
  - It is written through `Settings::Save`, which refuses a call carrying it from a non-owner (`Users::Manageability.actor_owner?`), whole.
  - `SettingsSections::Section` gains `owner_only`, and `SettingsSections.for(owner:)` leaves owner-only sections out for anyone else.
  - No "At a glance" row: the card doesn't draw one.

  Cost if wrong: a later backfill.
- **R12, codes and passkeys together.**
  - Adding a passkey generates ten codes in the same transaction, and shows them, when the person holds no unused code (the first passkey, or after the last code was used).
  - Removing the last passkey (allowed only when the policy does not cover the person) deletes the codes too, so `remove_last`'s "you'll sign in with your password again" is true.

  Cost if wrong: an owner question, below.
- **R13, the audit events** (`noun.verb`; the sentences are English in `Audit::Sentence`):
  - `passkey.added` (`{ "name" }`);
  - `passkey.renamed` (`field_changes` name);
  - `passkey.removed` (`{ "name", "recovery_codes_removed" }`, or for the console `{ "count", "recovery_codes_removed", "reason" => "console" }` with no actor);
  - `recovery_codes.generated` (`{ "count" => 10, "replaced" => n }`);
  - `recovery_code.used` (`{ "left" }`);
  - `session.second_factor_failed` (no actor, the user as subject, `{ "method" }`);
  - `session.confirmation_failed` (the user as actor and subject, `{ "method" }`).

  `session.created` gains `{ "method" }` when it is not `password`. All but `passkey.renamed` join `SECURITY_ACTIONS`, and `session.second_factor_failed` joins `NO_ACTOR`. Cost if wrong: one sentence each.
- **R14, the spans.**
  - New names in `Telemetry::SPANS`:
    - `auth.passkey`: one ceremony, with `auth.passkey.ceremony` (`register`, `sign_in`, `second_factor` or `confirm`) and `auth.outcome`;
    - `auth.recovery_code`: with `auth.outcome`;
    - `auth.second_factor` and `auth.confirmation`: the step as a whole, with `auth.method` and `auth.outcome`;
    - `auth.account_mail`: with `auth.mail.kind` (`passkey_added` or `recovery_code_used`) and `auth.mail.queued`.
  - New keys in `ATTRIBUTES`: `auth.passkey.ceremony`, `auth.policy`, `auth.second_factor.required` and `auth.mail.kind`.
  - `auth.sign_in` gains `auth.second_factor.required` and `auth.policy` on success.
  - `SignIn::OUTCOMES` gains `second_factor_required`.

  Cost if wrong: names in a list.
- **R15, the console.** `Users::UpdatePassword.new(…, remove_passkeys: false)`. `true` is accepted only from a trusted nil actor (`AccessControl.trusted?(nil, Current.channel)`, i.e. the console), and anyone else gets `denied("users.manage", user)`. In the password's transaction it deletes the passkeys and the codes, records one `passkey.removed` (R13), and the existing rule ends every session. The documented command is the existing one plus `, remove_passkeys: true`. `Setup::SystemCheck::MAIL_FALLBACK_COMMAND` is unchanged. Cost if wrong: one keyword.
- **R16, the ceremonies' options.**
  - Registration requires a discoverable credential: `authenticator_selection: { resident_key: "required", require_resident_key: true, user_verification: "required" }`, `attestation: "none"`, and `exclude:` the person's credentials.
  - Authentication uses `user_verification: "required"`. Its `allow:` is empty for the passkey sign-in and the person's credentials for the second step and the confirmation.
  - A sign-count that goes backwards is refused. A synced passkey's count stays 0 and passes.

  Cost if wrong: an authenticator without user verification can't register.
- **R17, two things left out.**
  - Autofill: the email field carries `autocomplete="username webauthn"` as the card says, but no conditional-mediation request is made. The button is the way in.
  - The passkey name is not prefilled: a browser gives no authenticator name before its prompt.

  Cost if wrong: a follow-up for each; the second is an owner question.
- **R18, the order around the browser's prompt.**
  - WebKit lets `navigator.credentials.create/get` run only in a user gesture, so the options are fetched before the press that opens the prompt, and the press calls the API at once:
    - on connect for sign-in and the second step;
    - when the Add dialog opens;
    - when the confirm dialog opens, for its passkey.
  - For Add, Confirm it's you therefore comes when "Add a passkey…" is pressed, before the Name dialog. Once confirmed, the Name dialog opens by itself, and its Continue starts the prompt.
  - For Remove and the codes, the confirmation comes after their own confirm, and the action goes on by itself.

  Cost if wrong: Safari refuses the prompt after an await.
- **R19, the wizard.** Its step `passkey` comes after `admin`. It is not gated by Confirm it's you: the session was made by the password just set. It uses its own endpoints under `/setup`, because `Setup::RedirectConstraint` sends every CS Studio path to `/setup` until the wizard ends. Cost if wrong: none.
- **R20, where the scripts go.**
  - `app/javascript/passkeys/ceremony.js` is the module, `pin_all_from … under: "passkeys", preload: false`, so no public page preloads it.
  - `controllers/passkey_sign_in_controller.js` (`passkey-sign-in`) serves the product layout's sign-in and second step.
  - `controllers/admin/passkeys/register_controller.js` and `confirm_controller.js` are the `passkeys` topic.
  - `controllers/admin/ui/recovery_codes_controller.js` belongs to the shared component.
  - The product layout gains the setup layout's `content_for(:entry_point) == "admin"` switch, so the enrolment page registers the admin controllers.

  Cost if wrong: a file move.

## Review Focus

1. **A stolen password at the second step.** It must get no session, no `cs_known_device` cookie, and no cleared account run; its wrong codes close the account as wrong passwords do. Task 7: `test "a right password then five wrong codes closes the account, and no session or known-device cookie was ever written"`.
2. **A challenge used twice, used late, or used for another purpose.** A replayed assertion, one answered after 5 minutes, and a registration challenge sent to sign-in are each refused like a wrong passkey. Task 6: `test "an assertion sent twice, one after five minutes and one made for another purpose's challenge are refused, and the second press works with a fresh challenge"`.
3. **Junk in place of a credential:** a string that is not JSON, 20 KB of JSON, a JSON array, or a hash with no `id`. Each is refused as a wrong passkey, with no 500 and no parse of the 20 KB. Task 2: `test "junk, an oversized credential and a hash of the wrong shape are refused without raising"`.
4. **The policy changed while people are signed in, and the last passkey.** An open session carries on, and the next sign-in is sent to enrolment. A covered person's last passkey can't be removed, by the screen or by a crafted DELETE. Task 11: `test "a policy saved while a covered person is signed in leaves that session alone; their next sign-in is sent to enrolment"`. Task 5: `test "the last passkey of a covered person is refused, the passkey and codes stay, nothing is recorded"`.
5. **Codes shown once, coming back.** After Done, the Back button, or a Turbo visit back to Your account, no code is in the page or in Turbo's snapshot. Task 8 builds the taking back; Task 10 tests it: `test "after Done and a visit back, the page holds no code"`.

---

## File map

| File | Responsibility | Task |
|---|---|---|
| `Gemfile`, `db/migrate/20261112090000_create_passkeys_and_recovery_codes.rb`, `db/migrate/20261112090100_add_passkey_policy_and_confirmation.rb`, `app/models/passkey.rb`, `app/models/recovery_code.rb`, `app/models/user.rb`, `app/models/session.rb`, `app/models/site_setting.rb`, `config/initializers/filter_parameter_logging.rb` | the records | 1 |
| `app/models/sign_in/relying_party.rb`, `passkey_registration.rb`, `passkey_check.rb`, `lib/telemetry.rb`, `app/models/sign_in.rb`, `test/support/passkey_helper.rb` | the ceremonies | 2 |
| `app/models/sign_in/throttle.rb`, `password_attempt.rb`, `proof.rb` | the second proofs and their buckets | 3 |
| `app/mailers/sign_in_mailer.rb`, `app/views/sign_in_mailer/{passkey_added,recovery_code_used}.{html,text}.erb`, `config/locales/mail.en.yml` | the two mails | 4 |
| `app/models/passkeys/policy.rb`, `app/services/passkeys/{add,rename,remove}.rb`, `app/services/recovery_codes/generate.rb`, `app/services/users/update_password.rb`, `app/models/audit/sentence.rb` | the writes, the policy, the console | 5 |
| `app/controllers/concerns/passkey_challenges.rb`, `app/controllers/concerns/admin/sign_in_completion.rb`, `app/controllers/admin/sessions_controller.rb`, `app/views/admin/sessions/new.html.erb`, `app/javascript/passkeys/ceremony.js`, `app/javascript/controllers/passkey_sign_in_controller.js`, `app/views/admin/shared/_icon.html.erb` | passkey sign-in | 6 |
| `app/controllers/admin/second_factors_controller.rb`, `app/views/admin/second_factors/show.html.erb`, `config/locales/admin/second_factor.en.yml` | the second step | 7 |
| `app/components/admin/ui/recovery_codes_component.*`, `app/javascript/controllers/admin/ui/recovery_codes_controller.js` | the codes, shown once | 8 |
| `app/controllers/concerns/admin/recent_confirmation.rb`, `app/controllers/admin/confirmations_controller.rb`, `app/components/admin/ui/confirm_identity_dialog_component.*`, `app/javascript/controllers/admin/passkeys/confirm_controller.js` | Confirm it's you | 9 |
| `app/components/admin/account_screen/{passkeys_card,passkey_dialog,recovery_card}_component.*`, `app/controllers/admin/{passkeys,recovery_codes}_controller.rb`, `app/javascript/controllers/admin/passkeys/register_controller.js`, `app/views/admin/accounts/edit.html.erb` | Your account | 10 |
| `app/values/settings_sections.rb`, `app/components/admin/settings_screen/sign_in_card_component.*`, `app/services/settings/save.rb`, `app/controllers/concerns/admin/passkey_enrolment.rb`, `app/controllers/admin/enrolments_controller.rb`, `app/views/admin/enrolments/show.html.erb`, `app/views/layouts/product.html.erb` | the policy and enrolment | 11 |
| `app/controllers/setup_controller.rb`, `app/views/setup/passkey.html.erb`, `config/locales/setup.en.yml` | the wizard | 12 |
| `test/integration/passkey_telemetry_test.rb`, `docs/reference/*.md`, `CLAUDE.md`, `CHANGELOG.md`, `test/support/design_system_entries.rb` | the span guard, the reference, the PR | 13 |

---

### Task 1: The gem, the tables and the records

**Files:**
- Modify: `Gemfile` (`gem "webauthn", "~> 3.5"`), `app/models/user.rb`, `app/models/session.rb`, `app/models/site_setting.rb`, `config/initializers/filter_parameter_logging.rb` (`:credential`, `:recovery_code`, each with a one-line reason as the entries above it have), `CHANGELOG.md` (`### Migrations`, both versions)
- Create: the two migrations (R1, then `sessions.confirmed_at` datetime, `sessions.enrolment_due` boolean NOT NULL default false, `site_settings.passkey_policy` string), `app/models/passkey.rb`, `app/models/recovery_code.rb`
- Test: `test/models/passkey_test.rb`, `test/models/recovery_code_test.rb`, `test/models/user_test.rb`, `test/models/session_test.rb`, `test/models/site_setting_test.rb`

**Interfaces:**
- Produces:
  - `Passkey` (`belongs_to :user`; `NAME_LIMIT = 60`; name stripped, required, at most 60).
    - `#used!(sign_count:, at: Time.current)`: `update_columns`, `# version: none (passkeys are on no public page)`.
    - `#user_handle -> String` (`user.webauthn_id`).
    - The blank-name message is `activerecord.errors.models.passkey.attributes.name.blank`: "Give the passkey a name." (`format: "%{message}"`, as the password's).
  - `RecoveryCode`:
    - the constants `COUNT = 10`, `ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"` and `KEY_PURPOSE = "content_spiel recovery code"`;
    - `.texts -> Array<String>` (ten fresh `XXXX-XXXX`, from `SecureRandom`);
    - `.digest(text) -> String | nil`, by R2's normalising, and nil for anything else or a non-String;
    - `scope :unused` (`where(used_at: nil)`);
    - `.redeem(text, at: Time.current) -> Boolean` on a relation: one `update_all(used_at: at)` on `unused.where(digest:)`, true when one row changed.
  - `User`:
    - `has_many :passkeys, dependent: :delete_all` and `has_many :recovery_codes, dependent: :delete_all`;
    - `#second_factor? -> Boolean` (a passkey, or an unused code);
    - `#webauthn_handle! -> String` (assigns `WebAuthn.generate_user_id` once, `update_column`, `# version: none`).
  - `Session`:
    - `CONFIRM_WINDOW = 10.minutes`;
    - `Session.start(user:, method:, user_agent:, ip_address:, enrolment_due: false, at: Time.current)` (sets `confirmed_at: at`);
    - `#confirmed_recently?(at = Time.current) -> Boolean`;
    - `#confirm!(at = Time.current)`, by `update_column` with `# version: none`.
  - `SiteSetting`:
    - `PASSKEY_POLICIES = %w[nobody owners_and_admins everyone]`, validated with `allow_nil`;
    - `#effective_passkey_policy(production: Rails.env.production?) -> String`.

- [ ] **Step 1: Write the failing tests.**
  - `test "a code is found however it is typed: lower case, spaces, a missing hyphen, O for 0 and I or L for 1"`: `RecoveryCode.digest("abcd efgh")` equals `digest("ABCD-EFGH")`; `digest("0O1I")` is nil (too short); `digest(["x"])` is nil.
  - `test "texts are ten distinct codes of the alphabet in XXXX-XXXX"`.
  - `test "a code is redeemed once; the second redeem of it and a redeem of an unknown code are false"`, by `users(:reader).recovery_codes.redeem(...)`.
  - `test "second_factor? is true with a passkey or an unused code, and false with only used codes"`.
  - `test "a session starts confirmed at its sign-in and stays so for ten minutes"`: travel 10 minutes and the answer is false; `confirm!` makes it true again; `updated_at` does not move.
  - `test "the policy unset is owners_and_admins in production and nobody elsewhere, and an unknown value is refused"`.
  - `test "a passkey's name is stripped, required and at most 60 characters, and the blank message is the dialog's sentence"`.
- [ ] **Step 2: Run them, and verify they fail.** `bin/rails test test/models/passkey_test.rb test/models/recovery_code_test.rb test/models/user_test.rb test/models/session_test.rb test/models/site_setting_test.rb`.
- [ ] **Step 3: Implement.** `bundle install`, migrate, and add `test/fixtures/passkeys.yml` and `recovery_codes.yml` only if a later task's test needs a fixture (tests here build rows).
- [ ] **Step 4: Run the tests above, then `test/lib` (the version-bump, the SQL strings and the dependency guards) and `bin/changelog-guard origin/main`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: passkeys, recovery codes and the passkey policy as records`.

### Task 2: The ceremonies: relying party, registration and check

**Files:**
- Create: `app/models/sign_in/relying_party.rb`, `app/models/sign_in/passkey_registration.rb`, `app/models/sign_in/passkey_check.rb`, `test/support/passkey_helper.rb`
- Modify: `lib/telemetry.rb` (R14's names and keys, all of them now), `app/models/sign_in.rb` (`OUTCOMES` += `:second_factor_required`; `SECOND_STEP_LIFETIME = 5.minutes`)
- Test: `test/models/sign_in/relying_party_test.rb`, `test/models/sign_in/passkey_registration_test.rb`, `test/models/sign_in/passkey_check_test.rb`

**Interfaces:**
- Produces:
  - `SignIn::RelyingParty.for(address: SiteAddress.current, request_origin:, name:) -> WebAuthn::RelyingParty | nil` (R3): `WebAuthn::RelyingParty.new(id:, name:, allowed_origins: [origin])`. Read the installed gem's README for the keyword, which the 3.x line names `allowed_origins`.
  - `SignIn::PasskeyRegistration.new(relying_party:)`:
    - `MAX_CREDENTIAL_BYTES = 16_384`;
    - `#options(user_handle:, user_name:, display_name:, exclude: []) -> [Hash, String]`, the options' `as_json` and the challenge (R16);
    - `#verify(credential_json, challenge:) -> SignIn::PasskeyRegistration::Result`, where `Result = Data.define(:ok, :external_id, :public_key, :sign_count, :transports)`.

    `verify` refuses `ok: false` without raising for these: a String over `MAX_CREDENTIAL_BYTES` (before any parse), a non-String, JSON that is no Hash, and any `WebAuthn::Error`, `JSON::ParserError`, `KeyError`, `ArgumentError` or `TypeError` from `WebAuthn::Credential.from_create(hash, relying_party:).verify(challenge, user_verification: true)`. It is one `auth.passkey` span, `ceremony: "register"`.
  - `SignIn::PasskeyCheck.new(relying_party:)`:
    - `#options(allow: []) -> [Hash, String]`;
    - `#verify(credential_json, challenge:, credentials:, ceremony:) -> SignIn::PasskeyCheck::Result`, where `Result = Data.define(:ok, :credential)`.

    `credentials` is a relation answering `find_by(external_id:)` (`Passkey`, or `user.passkeys`). The `userHandle` the response gives must equal the credential's `user_handle`. On success it calls `credential.used!(sign_count:)`. The same refusals as registration apply, plus an unknown id and a sign count that went backwards (`WebAuthn::SignCountVerificationError`). It is one `auth.passkey` span with the `ceremony` given.
  - `PasskeyHelper` (`test/support/passkey_helper.rb`, included in `ActiveSupport::TestCase` and `ActionDispatch::IntegrationTest`):
    - `fake_authenticator(origin: "http://www.example.com") -> WebAuthn::FakeClient`;
    - `add_passkey(user, client:, name: "1Password") -> Passkey` (registers through `SignIn::PasskeyRegistration`, as the app does);
    - `passkey_assertion(client, challenge:, user_handle: nil) -> String` (JSON).

- [ ] **Step 1: Write the failing tests.**
  - `test "the id is the registrable domain of PUBLIC_HOST and the origin the address"`. Use `with_site_address`: `https://www.example.org` gives the id `example.org` and the origins `["https://www.example.org"]`; `https://foo.github.io` gives `foo.github.io` (a private suffix); `http://localhost:3000` gives `localhost`.
  - `test "with no address the request's host is the id, and an IP host has no relying party"`.
  - `test "a registration made by an authenticator verifies, and one answered to another challenge does not"`.
  - `test "an assertion of a stored passkey verifies, moves its sign count and last_used_at, and one of another user's handle is refused"`.
  - Review Focus 3: `test "junk, an oversized credential and a hash of the wrong shape are refused without raising"`. Cover `"not json"`, `"[]"`, `{ "type" => "public-key" }.to_json`, and 20,000 bytes of valid JSON. The last raises nothing and is never handed to `JSON.parse` (`with_singleton_override(JSON, :parse)` counts calls).
  - `test "each ceremony is one auth.passkey span with its ceremony and outcome, and no attribute holds the credential id or the challenge"`, on the in-memory exporter, as `test/lib/telemetry_test.rb` reads it.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** The `SignIn` file's comment adds these objects to what "any kind of sign-in calls", and says the relying party is the one place the domain is decided.
- [ ] **Step 4: Run the tests, plus `test/lib/telemetry_test.rb`, `test/lib/telemetry_spans_test.rb` and `test/lib/dependency_direction_test.rb`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: passkey registration and verification as plain objects over webauthn-ruby`.

### Task 3: A second proof, counted in the account's bucket

**Files:**
- Modify: `app/models/sign_in/throttle.rb`, `app/models/sign_in/password_attempt.rb`
- Create: `app/models/sign_in/proof.rb`
- Test: `test/models/sign_in/throttle_test.rb`, `test/models/sign_in/password_attempt_test.rb`, `test/models/sign_in/proof_test.rb`

**Interfaces:**
- Consumes: `SignIn::PasskeyCheck` (Task 2); `User#second_factor?` and `RecoveryCode.redeem` (Task 1).
- Produces:
  - `Throttle#reserve_address(address:) -> Reservation`: the wide bucket alone.
  - `Throttle#release_address(address:) -> nil`: takes back this attempt's wide and bot-address counts. `record_success` calls it for its address half.
  - `PasswordAttempt#call`: for a right password whose account answers `second_factor?`, it calls `release_address` instead of `record_success`. The answer is `Outcome(status: :second_factor_required, account:)` and the span records `auth.second_factor.required => true`. Any other account is as before.
  - `SignIn::Proof.new(account:, identifier:, address:, device: nil, span:, throttle: SignIn::Throttle.new)`, where `span` is `"auth.second_factor"` or `"auth.confirmation"`:
    - `#recovery_code(text) -> Outcome`;
    - `#password(text) -> Outcome`;
    - `#passkey(credential_json, challenge:, check:, ceremony:) -> Outcome`.

    Each method reserves with `identifier:`, `address:` and the device as `PasswordAttempt` does (`device.id` when `device&.knows?(identifier)`). A closed bucket answers `:locked` with the trip, and nothing is checked. Then it checks: `account.recovery_codes.redeem(text)` inside an `auth.recovery_code` span, `account.authenticate(text)` (a non-String is ""), or `check.verify(…, credentials: account.passkeys, ceremony:)`. A success answers `record_success` and `:ok`; a failure answers `:refused` with the reservation's `closes`. Every call is one span named `span`, with `auth.method` (`recovery_code`, `password` or `passkey`) and `auth.outcome`.
- [ ] **Step 1: Write the failing tests.**
  - `test "a right password for an account with a second factor is second_factor_required, keeps the account's count and gives the address's back"`. The account's count reads 1 afterwards, and the wide count 0.
  - `test "a proof's failures count in the account's bucket: the fifth wrong code closes it and the right code is then refused as locked"`.
  - `test "a used code and a wrong code are the same refusal"`.
  - `test "a right proof clears the run the password step began"`: after a password step and a right code, the account's count is gone.
  - `test "from a known device the proof counts in the device's bucket and the account's lock does not refuse it"`.
  - `test "a passkey proof finds only the account's own passkeys"`: another user's registered credential is refused.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** The throttle's class comment gains a paragraph, "A SECOND PROOF", saying what R6 says as an invariant.
- [ ] **Step 4: Run `test/models/sign_in` and `test/integration/sign_in_*`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: a second proof of an account, counted where its password was`.

### Task 4: The two mails

**Files:**
- Modify: `app/mailers/sign_in_mailer.rb`, `config/locales/mail.en.yml` (the screens file's `mail.passkey_added` and `mail.recovery_code_used`, verbatim), `test/mailers/previews/sign_in_mailer_preview.rb`, and `test/lib/admin_design_rules_test.rb`'s mail list if it names the mail views
- Create: `app/views/sign_in_mailer/passkey_added.{html,text}.erb`, `recovery_code_used.{html,text}.erb`
- Test: `test/mailers/sign_in_mailer_test.rb`

**Interfaces:**
- Produces:
  - `SignInMailer#passkey_added(user, name:, added_at:, origin: nil)`;
  - `SignInMailer#recovery_code_used(user, used_at:, from_address:, left:, origin: nil)`, whose intro is plural on `left`.

  Each button is "Open Your account", linking to `admin_account_url(port: nil, anchor: "passkeys", **origin)`. With no origin known, no mail is built and one line is logged, as `locked` does. The time is in the site's zone (`admin.datetime`, as `locked_time`).
  - `SignInMailer.queue_alert(kind, user, **arguments) -> Boolean`: one `auth.account_mail` span (`auth.mail.kind`, `auth.mail.queued`). It queues through `ApplicationMailer.queue` only when `MailSettings.current.ready?`, and answers whether it queued.
- [ ] **Step 1: Write the failing tests.**
  - `test "passkey_added names the passkey and the time, and links to Your account's passkeys"`.
  - `test "recovery_code_used says the address and how many codes are left, one and many"`.
  - `test "with mail not ready queue_alert queues nothing and its span says so"`.
  - `test "a mail without a known origin is not sent and the line names nobody"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** The class comment gains the two mails, and says that neither carries a code or a key.
- [ ] **Step 4: Run `test/mailers` and `test/lib/mail_guards_test.rb`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: mail the account when a passkey is added or a recovery code used`.

### Task 5: The writes, the policy and the console

**Files:**
- Create: `app/models/passkeys/policy.rb`, `app/services/passkeys/add.rb`, `rename.rb`, `remove.rb`, `app/services/recovery_codes/generate.rb`
- Modify: `app/services/users/update_password.rb`, `app/models/audit/sentence.rb`
- Test: `test/models/passkeys/policy_test.rb`, `test/services/passkeys/add_test.rb`, `rename_test.rb`, `remove_test.rb`, `test/services/recovery_codes/generate_test.rb`, `test/services/users/update_password_test.rb`, `test/models/audit/sentence_test.rb`

**Interfaces:**
- Consumes: Tasks 1, 2 and 4.
- Produces:
  - `Passkeys::Policy.current(site: Current.site) -> Passkeys::Policy`:
    - `ADMIN_PERMISSIONS`;
    - `#name -> String`;
    - `#covers?(user) -> Boolean`: `everyone` covers all, `owners_and_admins` covers `user.owner?` or `AccessControl.holds?(user, key, channel: :admin)` for any admin key, and `nobody` covers none;
    - `#covers_owners? -> Boolean`;
    - `#enrolment_due?(user) -> Boolean`: covered, and no passkey;
    - `#uncovered_count -> Integer`: users with no passkey (`User.where.missing(:passkeys)`) that `covers?`, counted in Ruby over that relation, since a site has tens of users.
  - `Passkeys::Add.call(user, registration:, name:, actor: Current.actor, origin: nil) -> Result`, whose record is `[Passkey, Array<String> | nil]`:
    - only on the actor's own account; anyone else gets `denied("users.manage", user)`;
    - `registration` is a `SignIn::PasskeyRegistration::Result`, and one that is not `ok` gets `failure` with `admin.components.account_screen.passkey_dialog.failed`;
    - it creates the passkey and, per R12, the ten codes (through `RecoveryCodes::Generate#write_codes`, in the same transaction), clears `enrolment_due` on the user's sessions (`update_all`, `# version: none`), and records `passkey.added`, plus `recovery_codes.generated` when codes were made;
    - after commit it calls `SignInMailer.queue_alert(:passkey_added, …, origin:)`.
  - `Passkeys::Rename.call(passkey, name:, actor: Current.actor) -> Result`: own only; records `passkey.renamed`; a blank name is the model's refusal.
  - `Passkeys::Remove.call(passkey, actor: Current.actor) -> Result`: own only. The last passkey of a covered person is refused with `I18n.t("admin.components.account_screen.passkeys_card.last_required")`, and nothing is recorded. The last of an uncovered person also deletes the codes (R12). It records `passkey.removed`.
  - `RecoveryCodes::Generate.call(user, actor: Current.actor) -> Result`, whose record is `Array<String>`: own only. It deletes the user's codes and inserts ten digests with one `generated_at`, and records `recovery_codes.generated` (`replaced`: the unused count before). `#write_codes(user, at:) -> Array<String>` is its body without the authorization and the event, for `Passkeys::Add`.
  - `Users::UpdatePassword` gains `remove_passkeys: false` (R15).
  - `Audit::Sentence`: R13's sentences.
    - `passkey.added`: "added the passkey “<name>”".
    - `passkey.renamed`: "renamed the passkey “<old>” to “<new>”".
    - `passkey.removed`: "removed the passkey “<name>”". The console's has no actor: "<n> passkeys of <user> removed from the console".
    - `recovery_codes.generated`: "made new recovery codes".
    - `recovery_code.used`: "signed in with a recovery code (<left> left)".
    - `session.second_factor_failed`: "Failed second sign-in step for <user>".
    - `session.confirmation_failed`: "didn't confirm it was them before a sign-in change".
    - `session.created` with `metadata["method"]`: "signed in with a passkey" or "signed in with a recovery code".
- [ ] **Step 1: Write the failing tests.**
  - Policy: `test "owners_and_admins covers an owner and a holder of each admin key, and not an editor"`; `test "uncovered_count counts covered people without a passkey"`.
  - Add: `test "the first passkey makes ten codes and answers them; a second makes none"`; `test "a passkey added after the last code was used makes new codes"`; `test "adding clears enrolment_due on every session of the person"`; `test "another user's account is denied and nothing is written"`; `test "a refused registration writes nothing and records nothing"`; `test "the mail is queued after commit, and not when mail is not ready"`.
  - Remove, Review Focus 4 (service half): `test "the last passkey of a covered person is refused, the passkey and codes stay, nothing is recorded"`; `test "the last passkey of an uncovered person goes with the codes, in one event"`.
  - Generate: `test "regenerating replaces every code, used ones too, and records how many unused it replaced"`; `test "a code from before regenerating no longer redeems"`.
  - Console: `test "remove_passkeys from the console removes passkeys and codes, ends every session and records one passkey.removed"`; `test "remove_passkeys from a signed-in actor is denied and changes nothing"`.
  - Sentences: one test per event, and `test "every new event but passkey.renamed is a Security event"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `test/services`, `test/models/audit`, `test/models/passkeys` and `test/lib`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: add, rename and remove passkeys, make recovery codes, and the passkey policy`.

### Task 6: Sign in with a passkey

**Files:**
- Create:
  - `app/controllers/concerns/passkey_challenges.rb`;
  - `app/controllers/concerns/admin/sign_in_completion.rb`, which takes `DEVICE_COOKIE`, `known_device` and `remember_device` out of `Admin::SessionsController` (callers move, no alias);
  - `app/javascript/passkeys/ceremony.js`;
  - `app/javascript/controllers/passkey_sign_in_controller.js`.
- Modify:
  - `config/importmap.rb` (R20) and `config/routes.rb`;
  - `app/controllers/admin/sessions_controller.rb` (`passkey_options`, `passkey`; `rate_limit only: %i[create passkey]`);
  - `app/controllers/concerns/authentication.rb` (`start_new_session_for` passes `enrolment_due:` and records `auth.policy` on the current span);
  - `app/views/admin/sessions/new.html.erb`;
  - `app/views/admin/shared/_icon.html.erb` (`:fingerprint` and `:life_buoy`, Lucide's, covered by `LICENSE-lucide`);
  - `config/locales/admin/sessions.en.yml` (`new.or`, `new.passkey`, `passkey_failed` and `second_factor_expired`, verbatim).
- Test: `test/integration/passkey_sign_in_test.rb`, `test/system/admin/passkey_sign_in_test.rb`, `test/integration/public_javascript_test.rb` (unchanged, run)

**Interfaces:**
- Consumes: Tasks 2 and 3.
- Produces:
  - Routes: `post "sign-in/passkey/options", to: "sessions#passkey_options", as: :sign_in_passkey_options` and `post "sign-in/passkey", to: "sessions#passkey", as: :sign_in_passkey`.
  - `PasskeyChallenges` (included by `Admin::SessionsController`, the later Admin controllers and `SetupController`):
    - `LIFETIME = 5.minutes` and `PURPOSES = %w[sign_in second_factor confirm register]`;
    - `issue_passkey_challenge(purpose, challenge) -> void`;
    - `take_passkey_challenge(purpose) -> String | nil`;
    - `passkey_relying_party -> WebAuthn::RelyingParty | nil`, which is `SignIn::RelyingParty.for(request_origin: request.base_url, name: Current.site.title)`.
  - `Admin::SignInCompletion#complete_sign_in(user, method:) -> void`: starts the session, remembers the device by the user's normalised email, records `session.created` (with `{ "method" }` unless password), and clears `session[:sign_in_bot_check]`.
  - `passkey_options`: JSON options with `allow: []` (404 without a relying party).
  - `passkey`, in this order: `Throttle#reserve_address`; take the `sign_in` challenge; `PasskeyCheck#verify(params[:credential], credentials: Passkey, ceremony: "sign_in")`. Then:
    - on success, `release_address` and `complete_sign_in(passkey.user, method: "passkey")`, answered by JSON `{ "location": after_authentication_url }`;
    - on a refusal, JSON `{ "location": admin_sign_in_path }` with `flash[:alert] = t("admin.sessions.passkey_failed")`;
    - when the address is locked, the same with `admin.sessions.limited`.

    Every answer is 200 JSON, so a script can't tell the refusals apart.
  - `ceremony.js` exports:
    - `supported() -> boolean`;
    - `fetchOptions(url, body = {}) -> Promise<{ status, options }>`, a POST with the CSRF token;
    - `create(options)` and `get(options)`, which call the browser API at once, synchronously from the caller's press (R18), and parse with `PublicKeyCredential.parseCreationOptionsFromJSON` / `parseRequestOptionsFromJSON` where present, else a base64url decode of `challenge`, `user.id`, and `allowCredentials` / `excludeCredentials` ids;
    - `toJSON(credential) -> string`, through `credential.toJSON()` where present, else base64url;
    - `cancelled(error) -> boolean`, for `NotAllowedError` and `AbortError`.
  - `passkey-sign-in` (values `optionsUrl`, `verifyUrl`; targets `divider`, `button`):
    - while `supported()`, it shows the divider and the button, and fetches the options at connect;
    - a press calls `get` from the held options, posts `credential`, and goes to `location` (`window.location.assign`);
    - a cancelled prompt says nothing and fetches fresh options.
  - The view: under the form, "or" and the secondary full-width button (`ButtonComponent`, `:fingerprint`), both `hidden` until the script shows them, and drawn only when `passkey_relying_party`. The email field gets `autocomplete: "username webauthn"`.
- [ ] **Step 1: Write the failing tests.**
  - Integration:
    - `test "a passkey signs its person in, with the passkey method, the known-device cookie and session.created saying passkey"`.
    - `test "an unknown passkey answers the sign-in page with passkey_failed and counts in the address's wide bucket"`.
    - Review Focus 2: `test "an assertion sent twice, one after five minutes and one made for another purpose's challenge are refused, and the second press works with a fresh challenge"`.
    - `test "a passkey signs in an account whose email bucket a bot holds closed"` (R6).
    - `test "with an IP request host there is no passkey button and both endpoints answer 404"`.
  - Browser, `with_virtual_authenticator`, a helper added to `PasskeyHelper`:
    - It sets `Capybara.app_host = "http://localhost:#{Capybara.server_port}"` and restores it in an `ensure`.
    - It sends `WebAuthn.enable` and `WebAuthn.addVirtualAuthenticator` (`ctap2`, `internal`, `hasResidentKey`, `hasUserVerification`, `isUserVerified`, `automaticPresenceSimulation`) through `page.driver.browser.page.command`, and removes the authenticator after the test.
    - `add_virtual_passkey(user, authenticator)` makes a P-256 key in Ruby, sends it with `WebAuthn.addCredential` (`rpId: "localhost"`, resident, the user handle), and stores the matching `Passkey`.

    The tests:
    - `test "Sign in with a passkey signs in and lands on the dashboard"`.
    - `test "a cancelled prompt says nothing and the button works again"`: stub `navigator.credentials.get` to reject a `NotAllowedError` once, through the README's stub rule.
    - `test "without WebAuthn the divider and the button stay hidden"`: delete `window.PublicKeyCredential` before the controllers connect.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** The sessions controller's head comment gains the passkey answers, and the challenge concern's comment says R4.
- [ ] **Step 4: Run the two files, `test/integration/sign_in_*`, `test/integration/public_javascript_test.rb` and `test/lib/source_layout_test.rb`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: sign in to CS Studio with a passkey`.

### Task 7: The second step

**Files:**
- Create: `app/controllers/admin/second_factors_controller.rb`, `app/views/admin/second_factors/show.html.erb`, `config/locales/admin/second_factor.en.yml` (the screens file's `admin.second_factor.*`, verbatim)
- Modify: `app/controllers/admin/sessions_controller.rb` (`:second_factor_required`), `config/routes.rb`
- Test: `test/integration/second_factor_test.rb`, `test/system/admin/second_factor_test.rb`

**Interfaces:**
- Consumes: Tasks 3, 4, 5 and 6 (`complete_sign_in`, `PasskeyChallenges`, `passkey-sign-in`).
- Produces:
  - Routes:
    - `get "sign-in/second-step", to: "second_factors#show", as: :second_factor`;
    - `post "sign-in/second-step/options", to: "second_factors#options", as: :second_factor_options`;
    - `post "sign-in/second-step/passkey", to: "second_factors#passkey", as: :second_factor_passkey`;
    - `post "sign-in/second-step/code", to: "second_factors#code", as: :second_factor_code`;
    - `delete "sign-in/second-step", to: "second_factors#destroy"`.

    All are under `sign-in/`, which `Setup::RedirectConstraint` already exempts.
  - `Admin::SessionsController#create` on `:second_factor_required`: writes `cs_second_factor` (R5), and records neither a session nor a device. It redirects to `admin_second_factor_path`, with `?with=code` when the account has no passkey.
  - `Admin::SecondFactorsController < ApplicationController`:
    - `layout "product"`, `allow_unauthenticated_access`, and the `rate_limit` figures of sign-in in `SignIn.store`;
    - `SECOND_FACTOR_COOKIE = :cs_second_factor`;
    - private `pending_user -> User | nil`.

    The actions:
    - `show` draws the passkey view (lead with the email, "Use your passkey" primary, "Use a recovery code" link) or the code view (`code`, `code_help`, `submit_code`; the field `recovery_code`, `autocomplete="one-time-code"`), plus "Start over".
    - `code` and `passkey` go through `SignIn::Proof(span: "auth.second_factor")`.
      - Locked answers `admin.sessions.locked`.
      - Refused records `session.second_factor_failed` and redirects back with `code_failed`, `passkey_failed` (the person has codes) or `passkey_failed_no_codes`.
      - Success deletes the cookie and calls `complete_sign_in(user, method: "passkey" | "recovery_code")`.
      - For a code it also records `recovery_code.used` (`left`), calls `SignInMailer.queue_alert(:recovery_code_used, …)`, sets `flash[:recovery_code_left] = left`, and redirects to `admin_account_path(anchor: "passkeys")`.
    - A missing cookie goes to sign-in plainly. A cookie older than 5 minutes, or naming no user, is deleted, and goes to sign-in with `admin.sessions.second_factor_expired`.
- [ ] **Step 1: Write the failing tests.**
  - `test "a right password for an account with a passkey goes to the second step and starts no session"`.
  - `test "an account with codes and no passkey opens on the code view"`.
  - `test "a right code signs in, uses the code, records recovery_code.used with what is left, queues the mail and lands on Your account's passkeys"`.
  - `test "a wrong code and a used code get the same sentence"`.
  - Review Focus 1: `test "a right password then five wrong codes closes the account, and no session or known-device cookie was ever written"`.
  - `test "after five minutes the step says it took too long and the password must be typed again"`.
  - `test "a tampered cookie and one naming a deleted user are a plain sign-in"`.
  - `test "Start over forgets the step"`.
  - `test "a passkey finishes the step; another user's passkey is refused with passkey_failed"`.
  - `test "after a whole sign-in the account's run is clear and the address's wide count is one"`.
  - Browser: `test "password, then the passkey, signs in"`; `test "Use a recovery code, then a code, lands on Your account"`. The second asserts only the landing, since the notice is Task 10's.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them, plus `test/integration/sign_in_*` and `test/lib/admin_i18n_test.rb`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: a password is followed by a passkey or a recovery code once an account has one`.

### Task 8: The codes, shown once

**Files:**
- Create: `app/components/admin/ui/recovery_codes_component.{rb,html.erb}`, `app/javascript/controllers/admin/ui/recovery_codes_controller.js`, its Lookbook preview (`test/components/previews/admin/ui/recovery_codes_component_preview.rb`)
- Modify: `config/locales/admin/ui.en.yml` (`admin.components.ui.recovery_codes.*`, verbatim), `test/support/design_system_entries.rb` only if the contract test asks for the entry (the stamp is Task 13's), `test/lib/admin_i18n_test.rb` (`CONVERTED`)
- Test: `test/components/admin/ui/recovery_codes_component_test.rb`, `test/system/admin/recovery_codes_test.rb`

**Interfaces:**
- Produces: `Admin::Ui::RecoveryCodesComponent.new(codes:, frame: :dialog, done_href: nil, id: "recovery-codes")`.
  - The two frames:
    - `:dialog` wraps the block in `Admin::Ui::DialogComponent(id:, title: t(".title"), width: :form, open_on_load: true)`, and Done closes the dialog;
    - `:page` draws the title as an `h1` (`text-h1`), and Done is a primary link to `done_href`.
  - The block: `body`; the codes in `Admin::Ui::CopyValueComponent(layout: :block, value: codes.join("\n"), copy_label: t(".copy"))`, its box in two mono columns (`columns-2`, `font-cs-mono`) and `aria-label: t(".list_label")`; "Download" (a secondary button); the checkbox `saved` (`Admin::Ui::CheckboxComponent`); and Done, disabled until it is ticked.
  - `include Admin::Ui::Contract`:
    - `interface: %i[codes frame done_href id]`, `states: %i[dialog page]`;
    - `keys: %w[title body list_label copy download saved done]`;
    - `controller: "admin--ui--recovery-codes"`;
    - `script_states: { done_enabled: [file, test], downloaded: [file, test] }`;
    - the keyboard test;
    - `limits` saying the codes stand in no attribute and are taken back before the cache.
  - `admin--ui--recovery-codes`:
    - `toggle` enables or disables Done from the box;
    - `download` makes a `text/plain` Blob of the box's text, saved as `recovery-codes.txt` through a transient `<a download>`;
    - at `turbo:before-cache` and `pagehide` it empties the copy box's text and removes the block.
  - The answers that draw it carry `<meta name="turbo-cache-control" content="no-cache">` where the page itself is drawn (enrolment, the wizard).
- [ ] **Step 1: Write the failing tests.**
  - Component: `test "ten codes, the words, Done disabled, and no code in any attribute"`, which greps the rendered HTML's attributes for each code; `test "page frame draws a heading and a Done link to done_href"`.
  - No browser test here: the codes first appear on a screen in Task 10, whose browser file holds `test "Done waits for the box, Download saves the codes, Copy copies them"` and Review Focus 5's test. The contract's `script_states` and `keyboard` entries name that file.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `test/components/admin/ui`, `test/components/component_contract_test.rb` and `test/lib/component_parts_test.rb`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: the recovery codes, shown once, to copy, download or tick off`.

### Task 9: Confirm it's you

The words are v209's, in the screens file under "Confirm it's you", and go under `admin.components.ui.confirm_identity_dialog.*` (R9): `title`, `lead_passkey`, `lead_password`, `use_passkey`, `or`, `password`, `confirm_password`, `confirm`, `passkey_failed`, `wrong_password` and `limited`, verbatim.

**Files:**
- Create: `app/controllers/concerns/admin/recent_confirmation.rb`, `app/controllers/admin/confirmations_controller.rb`, `app/components/admin/ui/confirm_identity_dialog_component.{rb,html.erb}`, `app/javascript/controllers/admin/passkeys/confirm_controller.js`, its preview
- Modify: `config/routes.rb`, `config/locales/admin/ui.en.yml`, `test/lib/admin_i18n_test.rb` (`CONVERTED`)
- Test: `test/controllers/admin/confirmations_controller_test.rb`, `test/components/admin/ui/confirm_identity_dialog_component_test.rb`. The gate itself (`Admin::RecentConfirmation`) is tested through the four gated actions in Task 10, since the suite draws no test-only routes.

**Interfaces:**
- Consumes: Tasks 2, 3 and 6 (`SignIn::Proof`, `PasskeyChallenges`, `ceremony.js`).
- Produces:
  - Routes:
    - `post "account/confirmation", to: "confirmations#create", as: :account_confirmation`;
    - `post "account/confirmation/options", to: "confirmations#options", as: :account_confirmation_options`;
    - `post "account/confirmation/passkey", to: "confirmations#passkey", as: :account_confirmation_passkey`.
  - `Admin::ConfirmationsController < BaseController` (`rate_limit to: 10, within: 3.minutes` on `create` and `passkey`):
    - `create` runs `SignIn::Proof(span: "auth.confirmation")#password(params[:password])`. It answers 200 `{"confirmed":true}` after `Current.session.confirm!`; 422 `{"error": wrong_password}` with `session.confirmation_failed` (`method: "password"`) recorded; or 429 `{"error": limited}` when locked.
    - `options` answers request options for `Current.user.passkeys` (404 for none).
    - `passkey` mirrors `create`, with `passkey_failed`.
  - `Admin::RecentConfirmation`, `require_recent_confirmation(**before_action_options)` (R8):
    - JSON gets 403 `{"confirm":true}`;
    - a Turbo Stream gets 403, with `turbo_stream.append(ConfirmIdentityDialogComponent::REQUESTS_ID, <div data-admin--passkeys--confirm-target="request"></div>)`;
    - HTML gets a redirect to `admin_account_path(anchor: "passkeys")`.
  - `Admin::Ui::ConfirmIdentityDialogComponent.new(passkey:, url_options: {})`:
    - `ID = "confirm-identity"`, `REQUESTS_ID = "confirm-identity-requests"`;
    - `DialogComponent` `form_narrow`.
      - With a passkey: `lead_passkey`, "Use your passkey" (primary), "or", the Password field (`PasswordFieldComponent`, `autocomplete: "current-password"`), and "Confirm with password" (secondary) beside Cancel.
      - Without: `lead_password`, the field, and "Confirm" (primary) beside Cancel.
      - An error line (`role="alert"`) the script fills from the answer's `error`.
    - The contract: `controller: "admin--passkeys--confirm"`; `keys` as above; `script_states: { failed: …, confirmed: … }`.
  - `admin--passkeys--confirm` (on the dialog's wrapper; values `optionsUrl`, `passwordUrl`, `passkeyUrl`):
    - `ensure() -> Promise<boolean>` is used by `admin--passkeys--register` through an outlet. It opens the dialog, prefetching passkey options on open (R18), and resolves true once a confirmation answers 200, false on Cancel or ×.
    - It remembers a form with `data-confirm-identity` at its `turbo:submit-start`. When a `request` target connects, it calls `ensure()` and then `form.requestSubmit()`.
    - A cancelled passkey prompt says nothing.
- [ ] **Step 1: Write the failing tests.**
  - `test "a right password confirms the session for ten minutes and records nothing"`.
  - `test "a wrong password says so, records session.confirmation_failed, and counts in the account's bucket; the fifth answers limited"`.
  - `test "a passkey confirms; another user's is refused with passkey_failed"`.
  - `test "a sign-in counts as a confirmation for ten minutes"`.
  - Component: both shapes and their words; one primary per shape.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them, plus `test/components/component_contract_test.rb`, `test/lib/component_parts_test.rb` and `test/lib/script_messages_test.rb`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: confirm it's you before a change to how you sign in`.

### Task 10: Your account's Passkeys and Recovery codes cards

**Files:**
- Create:
  - `app/components/admin/account_screen/passkeys_card_component.{rb,html.erb}`;
  - `passkey_dialog_component.{rb,html.erb}`;
  - `recovery_card_component.{rb,html.erb}`;
  - `app/controllers/admin/passkeys_controller.rb`;
  - `app/controllers/admin/recovery_codes_controller.rb`;
  - `app/javascript/controllers/admin/passkeys/register_controller.js`.
- Modify:
  - `config/routes.rb`;
  - `app/controllers/admin/accounts_controller.rb` (`load_passkeys` beside `load_sessions`, on every answer that draws the screen);
  - `app/views/admin/accounts/edit.html.erb`: the two cards after the Password form and before Sessions, outside both forms, with one `ConfirmIdentityDialogComponent` and its requests slot;
  - `config/locales/admin/account_screen.en.yml` (`passkeys_card`, `passkey_dialog` and `recovery_card`, verbatim) and `config/locales/admin/accounts.en.yml` (`admin.accounts.passkeys.*`, verbatim);
  - `test/lib/admin_i18n_test.rb` (`CONVERTED`).
- Test: `test/components/admin/account_screen/{passkeys_card,recovery_card}_component_test.rb`, `test/controllers/admin/passkeys_controller_test.rb`, `test/controllers/admin/recovery_codes_controller_test.rb`, `test/system/admin/account_passkeys_test.rb`

**Interfaces:**
- Consumes: Tasks 5, 8 and 9.
- Produces:
  - Routes:
    - `post "account/passkeys/options", to: "passkeys#options", as: :account_passkey_options`;
    - `post "account/passkeys", to: "passkeys#create", as: :account_passkeys`;
    - `patch "account/passkeys/:id", to: "passkeys#update", as: :account_passkey`;
    - `delete "account/passkeys/:id", to: "passkeys#destroy"`;
    - `post "account/recovery-codes", to: "recovery_codes#create", as: :account_recovery_codes`.
  - `Admin::PasskeysController < BaseController`, with `require_recent_confirmation only: %i[options create destroy]`. Its passkey lookups are through `Current.user.passkeys.find`, so another user's id is a 404.
    - `options`: `Current.user.webauthn_handle!`, then the registration options with `exclude:` the person's credentials, issued under `register`.
    - `create` (`params[:credential]`, `params[:name]`): `Passkeys::Add` with `origin: mail_link_origin`. On success, it is a Turbo Stream: replace both cards, a toast `admin.accounts.passkeys.added`, and, with codes, an append of `RecoveryCodesComponent(frame: :dialog)`. From the enrolment page (`params[:from] == "enrolment"`) it is Task 11's answer. A failure is 422 JSON `{ "error" }`.
    - `update`: `Passkeys::Rename`. A stream replaces the card, with a toast `renamed`. On a refusal, a 422 stream redraws the rename dialog with the error.
    - `destroy`: `Passkeys::Remove`. It redirects `see_other` to `account#passkeys` with `removed`. A refusal (the last required) is a toast stream with `last_required`.
  - `Admin::RecoveryCodesController#create`: gated; `RecoveryCodes::Generate`. A stream replaces the recovery card and appends the codes dialog.
  - `Admin::AccountScreen::PasskeysCardComponent.new(passkeys:, covered:, recovery_left: nil, url_options: {})`:
    - `HEADING_ID = "passkeys"`, `icon: :fingerprint`;
    - each row has the name, "Added %{date}", and `last_used_html` with `TimeAgoComponent`, or `never_used`;
    - Rename (small tertiary, `aria-label` `rename_label`) and Remove… (`remove_label`, opening a destructive `ConfirmDialogComponent` whose form carries `data-confirm-identity`);
    - Remove is disabled with `last_required` on the row when it is the last and `covered`;
    - the foot has `count` and "Add a passkey…" (secondary), or `none` with no rows;
    - `recovery_left` draws the warn `NoticeComponent` (`used_recovery` by count, `used_last_recovery` at 0) at the card's top.
  - `Admin::AccountScreen::PasskeyDialogComponent.new(kind:, passkey: nil, last: false, url_options: {})`, `kind` one of `:add`, `:rename` or `:remove`, with the `passkey_dialog` words (`remove_last` added to the body when `last`).
  - `Admin::AccountScreen::RecoveryCardComponent.new(unused:, generated_at:, url_options: {})`:
    - `HEADING_ID = "recovery-codes"`, `icon: :life_buoy`;
    - the status `left` or `none`;
    - the warn notice `low` at 1–2 and `out` at 0 once codes were made;
    - Regenerate… (a non-destructive `ConfirmDialogComponent`, `regenerate_body` by count, its form `data-confirm-identity`), or Generate… as a `button_to` with `data-confirm-identity`.
  - `admin--passkeys--register` (values `optionsUrl`, `createUrl`, `from`; outlet `admin--passkeys--confirm`; targets `name`, `error`, `dialog`), by R18:
    - "Add a passkey…" fetches the options. On 403 `{"confirm":true}` it awaits `ensure()` and fetches again. Then it opens the Name dialog.
    - Continue refuses a blank name with `name_blank` (from `data-messages`), else calls `create` at once and posts `credential` and `name`.
    - On a redirected response it does `Turbo.visit(response.url)`. On a stream it does `Turbo.renderStreamMessage`. On 422 it says `failed`.
    - A cancelled prompt says nothing.
- [ ] **Step 1: Write the failing tests.**
  - Components: rows and words; Remove disabled with the reason; the count, singular and plural; `none`; the recovery status, `low` and `out`; Generate vs Regenerate.
  - Controllers:
    - `test "adding the first passkey answers the card, the toast and the codes, and a second answers no codes"`;
    - `test "the four gated actions outside the window write nothing and answer 403 with the confirm marker, as JSON and as a stream"`;
    - `test "renaming needs no confirmation"`;
    - `test "another user's passkey is not found"`;
    - Review Focus 4 (request half): `test "a crafted DELETE of a covered person's last passkey is refused and the passkey stays"`.
  - Browser (`with_virtual_authenticator`):
    - `test "Add a passkey… adds it, shows ten codes, and the card lists it"`;
    - `test "after ten minutes Add asks Confirm it's you first, and the Name dialog follows by itself"` (set `confirmed_at` back with `update_column`);
    - `test "Remove… then Confirm with password removes it"`;
    - `test "Regenerate… shows ten new codes"`;
    - `test "signing in with a code lands here with the warn notice"`;
    - Review Focus 5: `test "after Done and a visit back, the page holds no code"`: generate codes, press Done, visit the dashboard, go Back, and assert that no code's text is in `page.html`.
    - `test "Done waits for the box, Download saves the codes, Copy copies them"`: it reads the Blob through a stubbed `URL.createObjectURL` that keeps its argument.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them, plus `test/integration/admin` (the account screen), `test/lib/admin_i18n_test.rb`, `test/lib/admin_design_rules_test.rb` and `test/lib/source_layout_test.rb`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: Your account lists your passkeys and recovery codes, and adds, renames and removes them`.

### Task 11: The policy in Settings, and enrolment

**Files:**
- Create:
  - `app/components/admin/settings_screen/sign_in_card_component.{rb,html.erb}`;
  - `app/controllers/concerns/admin/passkey_enrolment.rb`;
  - `app/controllers/admin/enrolments_controller.rb`;
  - `app/views/admin/enrolments/show.html.erb`;
  - `config/locales/admin/enrolment.en.yml` (`admin.enrolment.show.*`, verbatim).
- Modify:
  - `app/values/settings_sections.rb` (R11), `app/queries/jump/search.rb` and `app/views/admin/settings/show.html.erb` (`owner: AccessControl.owner?(…)`);
  - `app/controllers/admin/settings_controller.rb` (permit `:passkey_policy`; the toast is `sign_in_card.saved` when the policy is the only change);
  - `app/services/settings/save.rb`: `OWNER_ATTRIBUTES = %i[passkey_policy]`, and a non-owner's call carrying one is denied whole, with one `access.denied`;
  - `config/locales/admin/settings_screen.en.yml` (`sections.sign_in: "Sign-in"`, and `sign_in_card.*`, verbatim);
  - `app/controllers/admin/base_controller.rb` and `app/controllers/preview_controller.rb` (`include Admin::PasskeyEnrolment`);
  - `app/views/layouts/product.html.erb` (R20's entry switch);
  - `config/routes.rb`.
- Test: `test/values/settings_sections_test.rb`, `test/services/settings/save_test.rb`, `test/components/admin/settings_screen/sign_in_card_component_test.rb`, `test/integration/passkey_enrolment_test.rb`, `test/system/admin/passkey_enrolment_test.rb`

**Interfaces:**
- Consumes: Tasks 5, 8, 9 and 10.
- Produces:
  - `SettingsSections::Section` gains `owner_only` (default false). The new section is `Section.new(id: "sign_in", permission: "settings.manage", family: :neutral, icon: :fingerprint, owner_only: true)`, after `mail`. The new signature is `SettingsSections.for(owner: false, &holds)`.
  - `Admin::SettingsScreen::SignInCardComponent.new(site:, policy:, uncovered:)`:
    - the `intro`;
    - an `Admin::Ui::SegmentedComponent` of radios `site_setting[passkey_policy]`, legend `legend`, with the three `policies` in order;
    - the help line `admins_help`;
    - the line `uncovered` by count, or `all_covered` at 0 (none at `nobody`).

    It is part of the Settings form, saved with the floating bar.
  - Route `get "enrolment", to: "enrolments#show", as: :enrolment`. The codes never pass through the flash or the session. `PasskeysController#create` with `from: "enrolment"` answers a Turbo Stream that replaces `#enrolment` with `RecoveryCodesComponent(frame: :page, done_href: after_authentication_url)` when codes were made, and a `see_other` redirect to `after_authentication_url` when none were.
  - `Admin::EnrolmentsController < BaseController`:
    - `layout "product"`, `skip_before_action :require_passkey_enrolment`;
    - `show` draws `title`, the `lead` by policy, `name`, `name_help`, "Add passkey" (on `admin--passkeys--register`, `from: "enrolment"`), the confirm dialog, `failed`, and Sign out (`button_to admin_sign_out_path`, method delete);
    - a session with no `enrolment_due` is redirected to the dashboard.
  - `Admin::PasskeyEnrolment#require_passkey_enrolment` (R10). `Admin::PasskeysController` skips it for `options` and `create`, and `Admin::ConfirmationsController` for all.
- [ ] **Step 1: Write the failing tests.**
  - `test "the sign-in section is offered to an owner only, in the nav, the cards and ⌘K"`.
  - `test "a non-owner's save carrying passkey_policy is refused whole and records access.denied"`.
  - `test "an owner saves the policy and settings.updated records it"`.
  - Component: three choices with the effective one checked; the uncovered line by count; `all_covered`; nothing at nobody.
  - Enrolment:
    - `test "a covered person without a passkey is sent to enrolment from every CS Studio page and the preview, and Sign out still works"`;
    - `test "a Turbo visit while enrolment is due is answered with a page Turbo loads whole"`;
    - Review Focus 4: `test "a policy saved while a covered person is signed in leaves that session alone; their next sign-in is sent to enrolment"`;
    - `test "adding the passkey on the enrolment page shows the codes, and Done goes where the person was going"`.
  - Browser: `test "enrolment adds a passkey and shows the codes"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** The comment on `Admin::PasskeyEnrolment` names every action it skips and why.
- [ ] **Step 4: Run them, plus `test/integration/admin/settings_test.rb`, `test/queries/jump/search_test.rb`, `test/components/admin/settings_screen` and `test/lib`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: an owner decides who must sign in with a passkey, and they are asked to add one`.

### Task 12: The wizard's passkey step

**Files:**
- Modify:
  - `app/controllers/setup_controller.rb`: `STEPS` gains `passkey` after `admin`; `update_admin` and `first_step` lead to it; `require_step_access` sends a later step back to it while `Passkeys::Policy.current.enrolment_due?(Current.user)`; `optional_step?("passkey")` is `!Passkeys::Policy.current.covers_owners?`; `include PasskeyChallenges`;
  - `config/routes.rb` (`post "setup/passkey/options", to: "setup#passkey_options", as: :setup_passkey_options`);
  - `config/locales/setup.en.yml` (`setup.passkey.*` and `setup.steps.passkey`, verbatim).
- Create: `app/views/setup/passkey.html.erb` (`content_for :entry_point, "admin"`)
- Test: `test/integration/setup_passkey_step_test.rb`, `test/system/setup_wizard_test.rb` (one more step in its walk)

**Interfaces:**
- Consumes: Tasks 5 and 8, and `admin--passkeys--register` (Task 10). The register controller's `createUrl` is `setup_step_path("passkey")` with method PATCH, and there is no confirm outlet (R19).
- Produces:
  - `SetupController#passkey_options`.
  - `update_passkey`: `Passkeys::Add`, then a Turbo Stream replacing the step's body with `RecoveryCodesComponent(frame: :page, done_href: setup_step_path("site"))`.
  - "Skip for now" is a tertiary link to `site`, drawn only when the policy does not cover owners.
- [ ] **Step 1: Write the failing tests.**
  - `test "after the admin step the wizard asks for a passkey, and adding one shows the codes then goes on to site"`.
  - `test "with production's default policy there is no Skip for now, and site is sent back to the passkey step"` (stub `Rails.env.production?` through `SiteSetting#effective_passkey_policy(production: true)`, or set the policy to `owners_and_admins`).
  - `test "with nobody the step is optional and Skip for now goes on"`.
  - `test "the step's endpoints are reachable while setup is pending"` (the redirect constraint).
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them, plus `test/integration/setup_*` and `test/system/setup_wizard_test.rb`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: the setup wizard offers the founding owner a passkey`.

### Task 13: The span guard, the reference, the changelog and the Design System stamp

**Files:**
- Create: `test/integration/passkey_telemetry_test.rb`
- Modify:
  - `docs/reference/access-control-and-audit.md`: passkeys, codes, the second step, R6 and R7 as invariants, Confirm it's you, enrolment, the policy, and the events with their sentences;
  - `docs/reference/hosting.md`:
    - "Sign-in on the open internet": the relying party, and that a domain move is answered by a recovery code then a new passkey;
    - "The reset mail": the console command with `remove_passkeys: true`;
    - "Telemetry": the new spans and attributes, and a Honeycomb query for second-step failures by outcome over time;
  - `docs/reference/users-groups-tokens.md`: the policy and "admins";
  - `docs/reference/mail.md`: the two mails;
  - `docs/reference/design-system.md`: the two new shared components in the shared list;
  - `CLAUDE.md`: the access-control line of the reference index gains `app/models/sign_in/` passkey files, `app/models/passkeys/`, `app/services/passkeys/`, `app/services/recovery_codes/` and the new controllers;
  - `test/support/design_system_entries.rb`: `VERSION = "1794419343-52dc"` (v209), and `StudioPasskeySignIn` and `StudioPasskeys` in `ENTRIES`;
  - `CHANGELOG.md` `## Unreleased`:
    - `### Added`: passkeys, the second step, codes, Confirm it's you, the policy, enrolment, the wizard step, the mails, the events and the spans;
    - `### Changed`: a password alone no longer signs in an account with a second factor; `session.created` carries a method;
    - `### For a gem or an outside caller`:
      - `Session.start(enrolment_due:)`;
      - `SettingsSections.for(owner:)`;
      - `SignIn::OUTCOMES`;
      - `Throttle#reserve_address`, `#release_address`;
      - the `SignIn` passkey objects and `SignIn::Proof`;
      - `Users::UpdatePassword(remove_passkeys:)`;
      - `Admin::Ui::RecoveryCodesComponent` and `ConfirmIdentityDialogComponent` with their signatures;
      - the product layout's entry switch.
- Test: the span guard, `test/lib`, `bin/changelog-guard origin/main`

**Interfaces:**
- Consumes: everything.

- [ ] **Step 1: Write the span guard** `test/integration/passkey_telemetry_test.rb`, in the pattern of PR 1's `sign_in_telemetry_test.rb`:
  - `test "a passkey sign-in, refused and accepted, exports auth.passkey under auth.sign_in's request with only listed words"`;
  - `test "the second step by code, wrong, right and locked, exports auth.second_factor and auth.recovery_code with only listed words"`;
  - `test "a refused confirmation exports auth.confirmation"`;
  - `test "no span or event holds the email, the password, the code typed, the credential id, the challenge or the passkey's name"`. The values are planted and searched for in every attribute and event.
- [ ] **Step 2: Run it.** It passes on what Tasks 2–9 built, or it names the leak, which is fixed in the code that leaked it.
- [ ] **Step 3: Write the docs and the changelog.** Then run `bin/rails test test/lib` (the docs, the environment-variable table, the Design System entries and the changelog guard's test) and `bin/changelog-guard origin/main`. Expected: PASS.
- [ ] **Step 4: Run the whole unit suite** (`bin/rails test`), then the browser files this PR added, one at a time.
- [ ] **Step 5: Commit** `docs: passkeys and recovery codes in the reference, the changelog and the Design System stamp`.

The PR's Documentation section names these guide pages: Signing in, Your account, Users (the policy), Settings, and the setup wizard.

## For the owner (not decided here)

1. **Removing the last passkey removes the recovery codes** (R12), so that `remove_last` ("you'll sign in with your password again") is true. The other choice keeps the codes, and the dialog's words then change.
2. **The passkey name can't be prefilled** before the browser's prompt (R17). Either drop the line from the card, or prefill it after the prompt from the authenticator's AAGUID, which is a lookup table.
3. **Confirm it's you comes before the Name dialog for Add** (R18), because WebKit runs the prompt only in a press. v209 says "the action carries on by itself (the browser's passkey prompt…)"; here the Name dialog opens by itself after the confirmation.
4. **The confirm dialog is a shared component** (R9), because the enrolment page asks too once 10 minutes have passed. So its keys are `admin.components.ui.confirm_identity_dialog.*`, not `account_screen.confirm_dialog.*`.
5. **Nobody but the console can clear another person's passkeys** today (spec §6). A user editor action for an owner ("Remove passkeys", for a lost device with no codes) is not in the spec.
