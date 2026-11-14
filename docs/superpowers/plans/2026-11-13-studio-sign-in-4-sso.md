# CS Studio sign-in, part 4: OIDC single sign-on and the sign-in method hook — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An integrator turns on one OpenID Connect provider per site by environment variables alone. An invited person signs in with it; their first sign-in links the account to the provider's subject and clears its password. `SSO_REQUIRED` turns password and passkey sign-in off for everyone but owners, who never link. An SSO session is re-checked with the provider once a day and ends when the provider says no. An owner unlinks an account from the user editor. A gem can add a sign-in method of its own through a fifth `ContentSpiel::Plugins` hook. Each step is audited and traced, and no secret leaves its place.

**Architecture:**
- **The OIDC link is a set of plain objects** in `SignIn::Oidc` (spec §9), as PR 3's ceremonies are:
  - `SignIn::Oidc::Provider`: the provider from the environment, its discovery document and its keys;
  - `SignIn::Oidc::Authorization`: the redirect, with state, nonce and PKCE;
  - `SignIn::Oidc::Callback`: the code exchanged and the ID token verified, answering a `SignIn::Oidc::Identity`;
  - `SignIn::Oidc::Refresh`: the daily re-check.

  None of them knows a user, a session, a cookie, a route or a mail. Every request they make goes through `SignIn::OutsideCall` (bounded, untraced), under a CLIENT span of their own.
- **CS Studio's own parts:**
  - columns on `users` (the link) and on `sessions` (the provider's token and when it was last checked);
  - the services `Sso::Admit` (an identity to an account), `Sso::Link`, `Sso::Unlink` and `Invitations::AcceptWithSso`;
  - `Users::UpdatePassword(clear: true)`, the one path that clears a password;
  - the controllers `Admin::SsoSessionsController` (start, callback) and `Admin::SsoLinksController` (unlink), the concern `SsoStarts` that the invitation page shares, and `Sso::RecheckJob`;
  - the registry `SignInMethods` and the hook `ContentSpiel::Plugins.sign_in_methods`.
- **The screens** are the Design System card StudioSingleSignOn (v218), with its words verbatim.

**Tech Stack:** Rails 8.1, `openid_connect` (nov's, 2.3.x, with its `json-jwt` and `rack-oauth2`), Minitest with fixtures, a fake provider served by a local `TCPServer` in tests (the `with_http_stub` pattern of `test/support/sign_in_helper.rb`), ViewComponent, Solid Queue recurring jobs, OpenTelemetry through `Telemetry.in_span`.

**Spec:** `docs/superpowers/specs/2026-11-10-studio-sign-in-design.md`, which this plan implements for:
- §4, whole;
- §2, the SSO session (`authenticated_with: "sso"`, the daily re-check, `session.ended` with `sso_revoked`);
- §3, "passkey (or use SSO)" in the policy;
- §6, the OIDC variables in `hosting.md`, and SSO in the wizard's system check;
- §7, the spans of the redirect, the callback, the token exchange and the re-check;
- §9, the shape of `SignIn::Oidc`.

**The screens and every word** are in `/private/tmp/claude-501/-Users-dknafelj-src-ContentSpiel/dd7bb8f3-e1e2-40d2-a449-0b6c377c5f48/scratchpad/sso-design-cards.md`, which summarises the card StudioSingleSignOn, Design System v218 (version index `1794552254-57d8`, https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT). Task 11 copies that summary into `docs/superpowers/specs/2026-11-13-sso-screens.md` so it travels with the branch. Read it, and the card, before any screen task (11–14).

**One pull request** on branch `sso`, from `main` 18d7d1b5.

## Global Constraints

- **The variables** (each read only by `SignIn::Oidc::Provider`):
  - `SSO_ISSUER`: the issuer's URL, exactly as the provider names it (`https://example.okta.com/oauth2/default`);
  - `SSO_CLIENT_ID`;
  - `SSO_CLIENT_SECRET`, a secret;
  - `SSO_NAME`: the provider's name as a person reads it ("Okta"), put into every sentence as `%{provider}` (card D1);
  - `SSO_REQUIRED`: `1`, or unset.
- **The figures:**
  - a state lives 10 minutes and is spent once (`SignIn::Oidc::STATE_LIFETIME = 10.minutes`);
  - an SSO session is re-checked every 24 hours (`Session::PROVIDER_CHECK_EVERY = 24.hours`);
  - an SSO session whose provider cannot be reached ends 2 hours after that (`Session::PROVIDER_CHECK_GRACE = 2.hours`);
  - one with no refresh token ends at 24 hours;
  - the discovery document and the keys are cached for an hour (`SignIn::Oidc::CACHE_FOR = 1.hour`);
  - an outside call has 3 seconds to connect and 5 to answer, and a body over 64 KB is refused unread (`SignIn::Oidc::MAX_BODY = 65_536`).
- **Invite first.** An account exists only because an owner invited it. A provider identity matches an account by `(issuer, subject)`, then, only when it is not linked yet, by a verified email (`email_verified` true). Nothing creates an account from the provider but an open invitation.
- **Owners never link.** An owner's email answers the account refusal, and a linked account cannot be made an owner.
- **A linked account signs in through SSO only.** Its password is replaced by one nobody holds, and its passkeys and recovery codes are deleted (card D5; "For the owner" 1).
- **No secret leaves its place.** These reach no span, event, log line, audit snapshot, page attribute or Turbo cache:
  - the client secret;
  - an authorization code, a state, a nonce or a PKCE verifier;
  - an ID token, an access token or a refresh token;
  - the email the provider gave, outside the `sso.refused` event's metadata (where `session.failed` keeps the email tried).

  `filter_parameters` gains `/\Acode\z/` and `/\Astate\z/`, whole names only, since a bare `:code` would mask every parameter containing "code". `Telemetry::PathScrubber` already cuts the callback's query, and a test holds it for this route.
- **CLAUDE.md binds every task.** In particular:
  - `Audit.record` is the one audit path (services use `record_event`);
  - every string a person reads is a key, with the card's words verbatim;
  - the dependency direction holds: `SignIn::Oidc` and the services name no controller, component or route, and a mail's origin comes in as `origin:`;
  - a password changes only through `Users::UpdatePassword` or `Users::Save`;
  - queries follow "Active Record, then Arel, then SQL";
  - a single-column write on a table no public page reads carries `# version: none (<reason>)`;
  - no `Admin::<Domain>`: the screens' components are `Admin::UsersScreen::…` and `Admin::AccountScreen::…`, never `Admin::Sso`.
- **The comment rule.** A comment states an invariant, a hazard or a reason, never a plan step. Before each commit, PR 1's grep runs over the added lines and prints nothing (PR 1 plan, "Comment rule").
- **Tests and the machine.**
  - The worktree has already run `bin/rails db:test:prepare`, and runs it again after Task 1's migrations.
  - Browser tests run one file at a time, after `bin/rails tailwindcss:build`, never beside a build or `bin/dev`, and only while `sysctl -n vm.loadavg` is under the core count.
  - No test reaches the network. The provider is `OidcHelper`'s fake (Task 3), on `127.0.0.1`.
  - A new test file joins a shard if `test/lib/test_shards_test.rb` says so.
- **Commits** follow conventional commits, and each ends with:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT`

## Rulings made in planning

Each ruling is the decision, then the cost if it is wrong.

- **R1, the gem: `openid_connect` alone, used as a library; no OmniAuth.**
  - `omniauth_openid_connect` is Rack middleware. It answers `/auth/:provider/callback` before the router, so it stands outside `HostRouteConstraint::Backend`: with `ADMIN_HOST` set, the callback would answer on the public host too, which the DMZ forbids. It keeps its state in the Rails session, makes its HTTP calls through Faraday, which `opentelemetry-instrumentation-faraday` would trace with the call's address, and reports failures through `on_failure`, outside the spans and the audit. It also needs `omniauth-rails_csrf_protection` for a POST start, which a Rails controller has anyway.
  - `openid_connect` (the library `omniauth_openid_connect` is built on) gives us the parts that are easy to get wrong:
    - the discovery document's shape and its issuer check (`OpenIDConnect::Discovery::Provider::Config::Response`);
    - the authorization URL (`OpenIDConnect::Client#authorization_uri`);
    - the ID token's signature and claims (`OpenIDConnect::ResponseObject::IdToken.decode(jwt, keys)` and `#verify!(issuer:, client_id:, nonce:)`);
    - the key set (`JSON::JWK::Set`).
  - The three HTTP calls (discovery, keys, token endpoint) go through `SignIn::OutsideCall.perform`, so each is bounded, untraced and named by class or status, never by message.
  - The routes are the app's own, under `/<ADMIN_PATH>/sign-in/sso/`, inside the backend's host constraint.

  Cost if wrong: the token request's form is written by hand (`grant_type`, `code`, `redirect_uri`, `code_verifier`, client auth), about 30 lines.
- **R2, the variables and the boot.** `SignIn::Oidc::Provider.current(env = ENV)` is a provider only when `SSO_ISSUER`, `SSO_CLIENT_ID`, `SSO_CLIENT_SECRET` and `SSO_NAME` are all set and not blank. Then, as `TURNSTILE_*` does:
  - Some of the four but not all is no SSO. Production's boot logs `[ContentSpiel] Single sign-on is off: SSO_CLIENT_SECRET is not set.`, naming every missing name and never a value (`Provider.missing_variables`, in `config/initializers/sign_in.rb`).
  - Three things stop the boot in every environment (`SignIn::Oidc::Misconfigured`, raised by `Provider.check!` from the same initializer), because each would silently open what the host meant to close or point sign-in at the wrong place:
    - `SSO_REQUIRED` set without a whole provider ("SSO_REQUIRED is set, but single sign-on is not: set SSO_ISSUER, SSO_CLIENT_ID, SSO_CLIENT_SECRET and SSO_NAME.");
    - `SSO_REQUIRED` with a value other than `1` ("SSO_REQUIRED must be 1, or unset.");
    - an `SSO_ISSUER` that is no absolute `https` URL with a host. `http` is allowed only to `127.0.0.1`, `::1` or `localhost`, outside production, which is how the tests' fake provider is reached. The message names the variable and never repeats the value, as `SiteAddress` does.

  Cost if wrong: a host with a half-set provider gets a log line, not a stopped boot.
- **R3, where the link lives.** It is three columns on `users`: `sso_issuer` string, `sso_subject` string and `sso_linked_at` datetime, with a UNIQUE index on `(sso_issuer, sso_subject)`. The issuer is stored because a `sub` is unique only within its issuer: a site that changes provider matches nobody by subject, and the next sign-in matches by email again (R6). `User#sso_linked? = sso_subject.present?`. A member's account (§9) would carry its own. Cost if wrong: a column migration.
- **R4, where the refresh token lives.** It is on the session it was issued to, not the user: two browsers hold two tokens, and ending a session drops its token with the row. `sessions.provider_token` is text, `encrypts :provider_token` (the keys forms already need). `sessions.provider_checked_at` is a datetime, set at the sign-in and at each re-check.
  - Without encryption keys (`Forms::Encryption.available?` false) the token is not stored, and the session is one with no token.
  - The columns are named for the provider, not for OIDC, so a gem's method (R13) uses them too.

  Cost if wrong: a rename.
- **R5, the daily re-check.**
  - `Sso::RecheckJob` runs every hour in `config/recurring.yml`, in all three blocks beside `sessions_sweep`. For every SSO session with a token whose `provider_checked_at` is 24 hours old or more, it calls `SignIn::Oidc::Refresh`:
    - `:ok` writes `provider_checked_at` and, when the provider rotated it, the new token (`update_columns`, `# version: none`);
    - `:revoked` ends the session (`Sessions::End`, reason `sso_revoked`): an `invalid_grant`, or a refreshed ID token whose `sub` is not the link's;
    - `:unavailable` leaves the session for the next run.
  - `Session#expiry` ends an SSO session:
    - with no token, at `provider_checked_at + 24h`, with the new reason `expired_sso`;
    - with a token, at `+ 26h`: the provider stayed out of reach for two hours past the check, also `expired_sso`.

    `Session.from_cookies` and `Sessions::SweepJob` (a third swept reason) apply it.
  - So "removed from the IdP means out within a day" holds, with at most two hours more while the provider is down (Review Focus 4).
  - `offline_access` is asked for only when the discovery document lists it in `scopes_supported`: Google, for one, refuses the scope, and its sessions then end at 24 hours.

  Cost if wrong: the grace is one constant.
- **R6, matching an identity to an account** (`Sso::Admit`), in this order:
  1. `User.find_by(sso_issuer:, sso_subject:)`: that account.
  2. An identity whose `email_verified` is not `true` is refused (`email_unverified`).
  3. A start from an invitation (R9) compares the verified email with that invitation's. A mismatch answers `[:mismatch, email]`; a match accepts it (`Invitations::AcceptWithSso`).
  4. An account with that email:
     - an owner is refused (`owner`);
     - one linked under another subject or issuer is refused (`no_account`), so a second provider user holding a linked account's email takes nothing (Review Focus 2);
     - otherwise `Sso::Link`.
  5. An open invitation for that email: `Invitations::AcceptWithSso`.
  6. Anything else is refused (`no_account`).

  Each refusal records `sso.refused`. Cost if wrong: an order the tests pin.
- **R7, linking clears the password, and deletes passkeys and codes.** `Sso::Link.call(user, identity:, origin:)` runs one transaction:
  - it writes the three columns;
  - it calls `Users::UpdatePassword.call(user, clear: true, actor: user, keep_acting_session: false)`, which writes `User.unusable_password` (`SecureRandom.base58(48)`, never shown or kept), asks no leak lookup, ends every session (one `session.ended`, `password_changed`) and records `user.updated` with its credentials marker, as any change does;
  - it deletes the passkeys and the codes (card D5);
  - it records `sso.linked`.

  The new digest also kills every reset link issued before, since Rails' reset token is signed over the digest's salt. Cost if wrong: D5 is one statement each way.
- **R8, refusals by rule.** The password, passkeys and the reset each answer a linked account, and an unlinked non-owner under `SSO_REQUIRED`, without saying which:
  - `SignIn::PasswordAttempt` gains `allowed: ->(account) { true }`. The controller passes `SignInRules.password_allowed?`: false for a linked account, and for a non-owner while `SignIn::Oidc.required?`. A right password for an account it refuses is `:refused`, keeps its count in the account's bucket as a wrong one does, and runs the same `authenticate_by`, so neither the answer, nor the bucket, nor the time tells it apart.
  - `Admin::SessionsController#passkey` and `Admin::SecondFactorsController` refuse such an account as a wrong passkey (`passkey_failed`). PR 3 already sent the second step's code view the same way.
  - `Invitations::Accept` (the password) refuses under `SSO_REQUIRED` with `[:sso_required]`. The page then draws only the provider's button (card 4).
  - `Users::UpdatePassword` (without `clear:`) and `Users::Save` with a password refuse a linked account: "This account signs in with %{provider} and has no password here." (`admin.users.sso_linked_password`, "For the owner" 3). The console's way back for a linked account is `Sso::Unlink` with the trusted nil actor.
  - `Users::Save`'s owner change refuses to make a linked account an owner: "%{name} signs in with %{provider}. Unlink them first: owners keep a password and a passkey." (`admin.users.owner.sso_linked`, "For the owner" 3).
  - `Passkeys::Add` refuses a linked account (`denied`).

  Cost if wrong: one predicate, `SignInRules`.
- **R9, the invitation by SSO.** "Continue with %{provider}" on the invitation page posts the token (from the form's hidden field, never an address) to `POST <admin>/invitation/sso`. A token that finds an open invitation starts SSO with the invitation's id in the state; any other token answers as the page already does for it (`:expired` or `:used`). Pressing the sign-in page's provider button instead also accepts an open invitation by its email (R6, step 5). The account's name is the provider's `name` claim, cut to `User`'s limit, or none. Cost if wrong: none outside the page.
- **R10, the state cookie.** `cs_sso_state`:
  - It is `cookies.encrypted`, HttpOnly, Secure over HTTPS, with `path: "/#{ContentSpiel::ADMIN_PATH}/sign-in/sso"`.
  - It is **SameSite Lax**, unlike the passkey cookies' Strict: the callback is a top-level GET from the provider's site, on which a Strict cookie is not sent.
  - It holds `{ "state", "nonce", "verifier", "at", "intent", "invitation_id" }`.
  - It is taken once. `SignIn::SpentChallenge.take(purpose:, value:, expires_at:)` takes the HMAC and the rescue out of `PasskeyChallenges#spend_passkey_challenge` (its callers move, with no alias), and the state is spent under purpose `sso`.
  - A state older than 10 minutes, one already spent, one whose `state` parameter does not match (`ActiveSupport::SecurityUtils.secure_compare`) and a callback with no cookie are each `bad_state`.

  Cost if wrong: a person who takes over 10 minutes at the provider presses the button again.
- **R11, the redirect URI follows the admin address.** `SignIn::Oidc.callback_origin(request_origin:)` is the origin of `SiteAddress.admin` when it is configured, else `SiteAddress.current`'s, else the request's origin (development and test only), as `SignIn::RelyingParty` decides. The controller builds `admin_sso_callback_url(**origin options)` from it. `hosting.md` names the address to register with the provider: `<ADMIN_HOST or PUBLIC_HOST>/<ADMIN_PATH>/sign-in/sso/callback`. Cost if wrong: the provider refuses the redirect and says so.
- **R12, the audit events** (`noun.verb`; the sentences are English in `Audit::Sentence`):
  - `sso.linked`: the user as actor and subject, `{ "via" => "sign_in" | "invitation", "issuer_host", "passkeys_removed", "recovery_codes_removed" }`;
  - `sso.refused`: no actor, no subject, `{ "reason" => "no_account" | "email_unverified" | "owner", "issuer_host", "email" }`, the email cut to 254 characters and present only when the provider gave one;
  - `sso.unlinked`: the owner as actor, the user as subject, `{ "issuer_host" }`;
  - `session.created` with `{ "method" => "sso" }`;
  - `session.ended` with the reasons `sso_revoked`, `sso_unlinked` and `expired_sso` (`{ "after_hours" => 24 }`).

  All three `sso.*` join `SECURITY_ACTIONS`, and `sso.refused` joins `NO_ACTOR`. An unfinished sign-in (cancelled at the provider, a provider error, a bad state or token, an unreachable provider) is not audited: nobody is named, and a bot's run would bury the log. Its span carries it. Cost if wrong: one sentence each.
- **R13, the sign-in method hook.**

  ```ruby
  ContentSpiel::Plugins.sign_in_methods do |methods|
    methods.register "acme/saml", label: "acme.sign_in.saml", path: :acme_saml_start_path,
      recheck: Acme::Saml::Recheck, passkey_policy: :exempt
  end
  ```

  - The owner rules are the block types' (`Registrar`, kind `"sign-in method"`, `takes: %i[attributes]`).
  - It is kept and replayed into `SignInMethods` after `reset!` on every `to_prepare`, by `config/initializers/sign_in_methods.rb`.
  - The fields:
    - `label:` is an I18n key of the gem's;
    - `path:` names a route helper on `main_app` that the button POSTs to;
    - `recheck:` is optional, an object answering `call(session) -> :ok | :revoked | :unavailable`, called daily by `Sso::RecheckJob` as an OIDC session's refresh is;
    - `passkey_policy:` is `:applies` (the default) or `:exempt` (the method's provider is the second factor, as SSO's is).
  - A gem's controller signs a person in by including `Admin::SignInCompletion` and calling `complete_sign_in(user, method: "acme/saml", provider_token: nil)`.
  - `complete_sign_in` enforces three rules:
    - it raises `ArgumentError` for a method that is neither built in nor registered;
    - it answers `false` and signs nobody in for an owner by an outside method, since owners keep their own way in, which no outside service may stand in for;
    - it records `session.created` with the method.
  - `Session` validates `authenticated_with` against `Session::METHODS + SignInMethods.names`.
  - The documented limits: a method finds an invited account and never creates one; it records nothing in the audit log but `session.created`; and `SSO_REQUIRED` neither hides nor refuses it.

  Cost if wrong: the hook's contract is a breaking change once released, so the owner reads it ("For the owner" 5).
- **R14, the spans.**
  - New names in `Telemetry::SPANS`:
    - `auth.sso.redirect`, with `auth.sso.intent` (`sign_in` or `invitation`);
    - `auth.sso.callback`, with `auth.outcome` (`ok`, `refused` or `unfinished`) and `auth.sso.reason`;
    - `auth.sso.discovery`, a CLIENT span, with `server.address` and `auth.sso.cached`;
    - `auth.sso.token`, a CLIENT span, with `server.address`, `auth.sso.refresh_token` (whether the provider gave one) and `error.type`;
    - `auth.sso.recheck`, a CLIENT span per session, with `auth.outcome` (`ok`, `revoked` or `unavailable`);
    - `auth.sso.recheck_run`, the job's run, with `auth.session.count`.
  - New keys in `ATTRIBUTES`: `auth.sso.intent`, `auth.sso.reason`, `auth.sso.cached`, `auth.sso.refresh_token` and `auth.sso.issuer_host` (the last on `auth.sso.redirect` and `auth.sso.callback`).
  - `SignIn::OUTCOMES` gains `unfinished`, `revoked` and `unavailable`.
  - `auth.sign_in` gains `auth.method => "sso"` nowhere: SSO's attempt is `auth.sso.callback`.

  Cost if wrong: names in a list.
- **R15, the mails.**
  - A reset request for a linked account, or for a non-owner while SSO is required, sends `PasswordsMailer#sso_reminder`. It says to sign in with the provider and has a button to the sign-in page, never a reset link. The request's answer is the same, since `PasswordResetRequestJob` decides.
  - With SSO off, a linked account's request sends nothing and logs one line naming nobody ("For the owner" 4).
  - Unlinking queues the ordinary `PasswordsMailer#reset` after the commit. The words of `sso_reminder` are this plan's, since the card drew none ("For the owner" 3).

  Cost if wrong: words.
- **R16, the System status row.** `Setup::SystemCheck#single_sign_on`, after `admin_address` (System status and the wizard's check):
  - `:ok` when discovery answers, with `sso.ok`, and `sso.required` appended while `SSO_REQUIRED` is set;
  - `:warning` with `sso.unreachable` and a reason word (`unreachable`, `http_<status>`, `not_json`, `issuer_mismatch`, `missing_endpoint`);
  - `:off` with `sso.off` when no provider is configured. `Result` gains the status `:off`, which the status list draws with the state chip's neutral tone.

  This is the wizard's SSO (§6): owners never link, so the wizard's passkey step is unchanged ("For the owner" 2). Cost if wrong: one row.

## Review Focus

1. **A forged or replayed callback.** Five cases: a state spent once and sent again; a state cookie from another browser with this browser's `state` parameter; a callback with no cookie; a code whose ID token carries another nonce; and a state older than 10 minutes. Each is `bad_state` or `bad_token`, signs nobody in, and leaves no session. Task 8: `test "a replayed state, another browser's state, no cookie, another nonce and a late state each end unfinished with no session"`.
2. **Account takeover by email.** Two cases. A second provider user whose verified email is a linked account's email is refused, and the link stays. A linked person whose email changed at the provider still signs in by subject. Task 6: `test "a second subject with a linked account's email is refused and the link is unchanged; the linked subject with a new email still signs in"`.
3. **A junk ID token.** `alg: none`, a wrong `aud`, a wrong `iss`, an expired token, a signature by an unknown key (the keys are fetched again once, then refused), a token response over 64 KB, and a body that is no JSON. Each is `bad_token` or `unavailable`, without raising and without parsing the large body. Task 4: `test "alg none, wrong audience, wrong issuer, expired, unknown key and an oversized or non-JSON answer are refused without raising"`.
4. **The provider down, or saying no, at the re-check.** Unreachable leaves the session until 26 hours, then it ends. `invalid_grant` ends it at once with `sso_revoked`. A rotated token replaces the stored one. A session with no token ends at 24 hours. Task 9: `test "revoked ends the session, unavailable keeps it until the grace is spent, a rotated token is stored, and no token ends at 24 hours"`.
5. **The admin host.** With `ADMIN_HOST` set, the redirect URI names the admin host, the callback answers there, the callback path on the public host is the public 404, and the state cookie's path is under the admin path. Task 8: `test "with an admin host the redirect URI names it, the callback answers there alone, and the public host's callback is the public 404"`.

---

## File map

| File | Responsibility | Task |
|---|---|---|
| `Gemfile`, `db/migrate/20261113090000_add_sso_link_to_users.rb`, `db/migrate/20261113090100_add_provider_check_to_sessions.rb`, `app/models/user.rb`, `app/models/session.rb`, `app/models/sign_in/spent_challenge.rb`, `app/controllers/concerns/passkey_challenges.rb`, `config/initializers/filter_parameter_logging.rb`, `CHANGELOG.md` | the records | 1 |
| `app/models/sign_in/oidc.rb`, `app/models/sign_in/oidc/provider.rb`, `config/initializers/sign_in.rb`, `docs/reference/hosting.md` (the two variable tables), `test/support/sign_in_helper.rb` | the provider from the environment, the boot | 2 |
| `app/models/sign_in/oidc/{configuration,authorization,identity}.rb`, `lib/telemetry.rb`, `app/models/sign_in.rb`, `test/support/oidc_helper.rb` | discovery, keys, the redirect, the fake provider | 3 |
| `app/models/sign_in/oidc/{callback,refresh}.rb` | the code exchange, the ID token, the refresh | 4 |
| `app/models/sign_in_methods.rb`, `lib/content_spiel/plugins.rb`, `config/initializers/sign_in_methods.rb` | the hook and its registry | 5 |
| `app/services/sso/{admit,link,unlink}.rb`, `app/services/invitations/accept_with_sso.rb`, `app/services/users/update_password.rb`, `app/models/passkeys/policy.rb`, `app/models/audit/sentence.rb` | the writes | 6 |
| `app/models/sign_in_rules.rb`, `app/models/sign_in/password_attempt.rb`, `app/services/invitations/accept.rb`, `app/services/users/save.rb`, `app/services/passkeys/add.rb`, `app/jobs/password_reset_request_job.rb`, `app/mailers/passwords_mailer.rb`, `app/views/passwords_mailer/sso_reminder.*`, `config/locales/mail.en.yml`, `config/locales/admin/users.en.yml` | the refusals by rule, the reminder mail | 7 |
| `app/controllers/concerns/sso_starts.rb`, `app/controllers/admin/sso_sessions_controller.rb`, `app/controllers/concerns/admin/sign_in_completion.rb`, `app/controllers/concerns/authentication.rb`, `app/controllers/admin/sessions_controller.rb`, `app/controllers/admin/second_factors_controller.rb`, `config/routes.rb` | start and callback | 8 |
| `app/jobs/sso/recheck_job.rb`, `app/jobs/sessions/sweep_job.rb`, `config/recurring.yml` | the daily re-check | 9 |
| `app/models/setup/system_check.rb`, `config/locales/admin/system_status.en.yml` (or where `admin.system_status.*` lives), the status list's chip | System status | 10 |
| `app/views/admin/sessions/new.html.erb`, `config/locales/admin/sessions.en.yml`, `docs/superpowers/specs/2026-11-13-sso-screens.md` | the sign-in panel | 11 |
| `app/controllers/invitations_controller.rb`, `app/views/invitations/show.html.erb`, `config/locales/invitations.en.yml` | the invitation page | 12 |
| `app/components/admin/users_screen/sso_zone_component.*`, `app/controllers/admin/sso_links_controller.rb`, the user editor's view, `config/locales/admin/users_screen.en.yml` | the user editor | 13 |
| `app/components/admin/account_screen/sso_card_component.*`, `app/views/admin/accounts/edit.html.erb`, `app/controllers/admin/accounts_controller.rb`, `config/locales/admin/account_screen.en.yml` | Your account | 14 |
| `test/integration/sso_telemetry_test.rb`, `docs/reference/*.md`, `CLAUDE.md`, `CHANGELOG.md`, `test/support/design_system_entries.rb` | the span guard, the reference, the PR | 15 |

---

### Task 1: The gem, the columns and the records

**Files:**
- Modify:
  - `Gemfile` (`gem "openid_connect", "~> 2.3"`, with a one-line reason as `webauthn`'s has);
  - `app/models/user.rb`;
  - `app/models/session.rb`;
  - `app/models/sign_in/spent_challenge.rb`;
  - `app/controllers/concerns/passkey_challenges.rb` (it calls `SpentChallenge.take`);
  - `config/initializers/filter_parameter_logging.rb` (`/\Acode\z/`, `/\Astate\z/`, each with its reason);
  - `CHANGELOG.md` (`### Migrations`, both versions).
- Create: the two migrations.
  - `users`: `sso_issuer` string, `sso_subject` string, `sso_linked_at` datetime; UNIQUE index `(sso_issuer, sso_subject)`; a CHECK that the issuer and the subject are both null or both set.
  - `sessions`: `provider_token` text, `provider_checked_at` datetime.
- Test: `test/models/user_test.rb`, `test/models/session_test.rb`, `test/models/sign_in/spent_challenge_test.rb`, `test/controllers/concerns/passkey_challenges_test.rb` (or wherever PR 3 tested the spend; run unchanged)

**Interfaces:**
- Produces:
  - `User`:
    - `#sso_linked? -> Boolean`;
    - `.unusable_password -> String`;
    - `.linked_to(issuer:, subject:) -> User | nil` (a named scope plus `first`).
  - `Session`:
    - `PROVIDER_CHECK_EVERY = 24.hours` and `PROVIDER_CHECK_GRACE = 2.hours`;
    - `encrypts :provider_token`;
    - `END_REASONS += %w[sso_revoked sso_unlinked expired_sso]`;
    - `timeout_metadata("expired_sso") -> { "after_hours" => 24 }`;
    - `Session.start(…, provider_token: nil)`: it sets `provider_checked_at: at` when `method` is `sso` or a registered method (Task 5 widens the list), and drops the token when `Forms::Encryption.available?` is false;
    - `#expiry(at)` answers `expired_sso` per R5, after the absolute check and before the idle one;
    - `scope :expired_sso, ->(at)`, in Arel through `SqlNodes`: `provider_checked_at` at or before `at - 24h` with no token, or `at - 26h` with one.
  - `SignIn::SpentChallenge.take(purpose:, value:, expires_at:) -> Boolean`: the HMAC (`VisitorAddress.digest("#{purpose}:#{value}", purpose: SPENT_PURPOSE)`, the constant moved here), `spend!`, and the rescue of `StatementInvalid` and `ConnectionNotEstablished` as a refusal with one log line naming the class.
- [ ] **Step 1: Write the failing tests.**
  - `test "sso_linked? follows the subject, and an issuer without a subject is refused by the database"`.
  - `test "two users cannot hold one issuer and subject, and one subject under two issuers is two links"`.
  - `test "an sso session with no token expires at 24 hours and one with a token at 26, as expired_sso"`.
  - `test "the absolute timeout wins over expired_sso"`.
  - `test "without encryption keys an sso session starts with no token"` (`without_encryption_keys`).
  - `test "the provider token is stored encrypted"`: the raw column read through `connection.select_value` does not contain it.
  - `test "take spends a value once per purpose, and a database error is a refusal"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** `bundle install`, migrate, `bin/rails db:test:prepare`. The `Session` comment's list of the ways a session ends gains the re-check and the unlink.
- [ ] **Step 4: Run the tests above, the passkey challenge tests, `test/lib` (the version-bump, SQL strings and dependency guards), and `bin/changelog-guard origin/main`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: the SSO link on users and the provider's check on sessions`.

### Task 2: The provider from the environment, and the boot

**Files:**
- Create: `app/models/sign_in/oidc.rb`, `app/models/sign_in/oidc/provider.rb`
- Modify:
  - `config/initializers/sign_in.rb`;
  - `docs/reference/hosting.md`: both variable tables, the five names, with `SSO_CLIENT_SECRET` the one secret ("What a host sets" and "Every variable the code reads", which `test/lib/environment_variables_test.rb` holds to the code);
  - `test/support/sign_in_helper.rb` (`with_sign_in_env` accepts the `SSO_*` names, if it lists names).
- Test: `test/models/sign_in/oidc/provider_test.rb`, `test/lib/environment_variables_test.rb` (run), `test/lib/production_boot_test.rb`

**Interfaces:**
- Produces:
  - `SignIn::Oidc` (module):
    - `VARIABLES = %w[SSO_ISSUER SSO_CLIENT_ID SSO_CLIENT_SECRET SSO_NAME]`;
    - `STATE_LIFETIME = 10.minutes`, `CACHE_FOR = 1.hour`, `MAX_BODY = 65_536`, `OPEN_TIMEOUT = 3`, `READ_TIMEOUT = 5`;
    - `UNFINISHED_REASONS = %w[cancelled provider_error bad_state bad_token unavailable]`;
    - `ACCOUNT_REASONS = %w[no_account email_unverified owner]`;
    - `class Misconfigured < StandardError` and `class Unavailable < SignIn::OutsideCall::Unavailable` (with `#reason`, one of R16's words);
    - `.required?(env = ENV) -> Boolean`: `env["SSO_REQUIRED"] == "1"` and a whole provider;
    - `.callback_origin(request_origin:) -> Hash` (R11, `url_options`-shaped).
  - `SignIn::Oidc::Provider`:
    - `.current(env = ENV) -> Provider | nil` (R2);
    - `.missing_variables(env = ENV) -> Array<String>`, empty when all four or none are set;
    - `.check!(env = ENV, production: Rails.env.production?) -> nil`, which raises `Misconfigured` per R2;
    - `#issuer`, `#client_id`, `#name`, `#issuer_host`;
    - the secret is read through a private method alone. `#inspect` and `#to_s` show the issuer host only, so an error page or a console never prints the secret.
  - The initializer, in `after_initialize`: `SignIn::Oidc::Provider.check!` in every environment, then in production the log line for `missing_variables` (R2's words), beside the bot check's.
- [ ] **Step 1: Write the failing tests.**
  - `test "all four variables make a provider, and any three make none"`.
  - `test "missing_variables names the missing ones and is empty with none set"`.
  - `test "SSO_REQUIRED without a provider, SSO_REQUIRED=yes and an http issuer to another host each refuse, naming the variable and not the value"`. Plant a value in the issuer and assert it is not in the message.
  - `test "an http issuer to 127.0.0.1 is allowed outside production and refused in production"`.
  - `test "inspect never holds the client secret"`.
  - `test "callback_origin is the admin address, then the public address, then the request's"` (`with_site_address`, `with_admin_address`).
  - Production boot, two more children in `test/lib/production_boot_test.rb`:
    - `test "production with SSO_REQUIRED and no provider does not start, and says which variables"`;
    - `test "production with three of the four SSO variables starts and names the missing one"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** `SignIn::Oidc`'s head comment says what R1 says as an invariant: no Rack middleware, every call through `OutsideCall`, nothing here knows a user.
- [ ] **Step 4: Run the tests, `test/lib/environment_variables_test.rb`, `test/lib/production_boot_test.rb` and `test/lib/dependency_direction_test.rb`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: one OIDC provider per site, from five variables, refused at boot when it cannot work`.

### Task 3: Discovery, keys, the redirect, and the fake provider

**Files:**
- Create:
  - `app/models/sign_in/oidc/configuration.rb`;
  - `app/models/sign_in/oidc/authorization.rb`;
  - `app/models/sign_in/oidc/identity.rb`;
  - `test/support/oidc_helper.rb` (included in `ActiveSupport::TestCase` and `ActionDispatch::IntegrationTest`).
- Modify: `app/models/sign_in/oidc/provider.rb`, `lib/telemetry.rb` (all of R14's names and keys now), `app/models/sign_in.rb` (`OUTCOMES`; the head comment names `SignIn::Oidc`)
- Test: `test/models/sign_in/oidc/provider_test.rb`, `test/models/sign_in/oidc/authorization_test.rb`

**Interfaces:**
- Produces:
  - `SignIn::Oidc::Configuration = Data.define(:issuer, :authorization_endpoint, :token_endpoint, :jwks_uri, :scopes_supported, :token_auth_methods)`.
  - `Provider#configuration -> Configuration`:
    - It reads `Rails.cache` under `"content_spiel/oidc/discovery/#{Digest::SHA256.hexdigest(issuer)}"` for `CACHE_FOR`, else GETs `issuer.chomp("/") + "/.well-known/openid-configuration"` through `OutsideCall.perform` under an `auth.sso.discovery` CLIENT span.
    - The body is parsed by `OpenIDConnect::Discovery::Provider::Config::Response.new(hash)` and its `validate!(issuer)`.
    - It raises `Unavailable` with R16's reasons. A body over `MAX_BODY` is `not_json`, unread.
    - `token_auth_methods` defaults to `["client_secret_basic"]`.
  - `Provider#keys(refresh: false) -> JSON::JWK::Set`: the same cache and span, from `jwks_uri`.
  - `SignIn::Oidc::Identity = Data.define(:issuer, :subject, :email, :email_verified, :name, :refresh_token)`. Its `#inspect` leaves out `refresh_token`.
  - `SignIn::Oidc::Authorization.start(provider:, redirect_uri:) -> Authorization`:
    - `#url`, `#state`, `#nonce` and `#verifier` (each `SecureRandom.urlsafe_base64(32)`);
    - the URL is built by `OpenIDConnect::Client#authorization_uri` with `response_type: "code"`, `scope` (`openid email profile`, plus `offline_access` per R5), `state`, `nonce`, `code_challenge` (S256 of the verifier) and `code_challenge_method: "S256"`.
  - `OidcHelper`:
    - `with_fake_idp(email: "reader@example.com", email_verified: true, subject: "sub-1", name: "Rea Der", refresh_token: "rt-1", offline_access: true) { |idp| … }`. It starts a `TCPServer` on `127.0.0.1` that answers discovery, keys and the token endpoint, signs ID tokens with an RSA key it makes, sets the four `SSO_*` variables to it through `with_sign_in_env`, and clears `Rails.cache`'s discovery entries before and after.
    - The `idp` object:
      - `requests` (the paths and the form bodies seen);
      - `code_for(nonce:) -> String`;
      - `answer_token_with(status:, body:)` for one call;
      - `rotate_refresh_token(to)`;
      - `revoke!` (the next refresh answers 400 `invalid_grant`);
      - `down!` (the socket refuses);
      - `sign_with_unknown_key!`.
- [ ] **Step 1: Write the failing tests.**
  - `test "discovery is read once, then from the cache for an hour, and its span says cached"`.
  - `test "a discovery document naming another issuer is issuer_mismatch, and a refused socket is unreachable"`.
  - `test "the authorization URL carries the state, the nonce, an S256 challenge and the redirect URI, and asks offline_access only when listed"`.
  - `test "no span or log line holds the state, the nonce or the verifier"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them, plus `test/lib/telemetry_test.rb`, `test/lib/telemetry_spans_test.rb` and `test/models/sign_in/outside_call_test.rb`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: the provider's discovery, keys and authorization request, as plain objects`.

### Task 4: The code exchange, the ID token and the refresh

**Files:**
- Create: `app/models/sign_in/oidc/callback.rb`, `app/models/sign_in/oidc/refresh.rb`
- Test: `test/models/sign_in/oidc/callback_test.rb`, `test/models/sign_in/oidc/refresh_test.rb`

**Interfaces:**
- Consumes: Task 3.
- Produces:
  - `SignIn::Oidc::Callback.new(provider:, redirect_uri:)`, `#call(params:, kept:) -> Result`:
    - `Result = Data.define(:ok, :identity, :reason)`;
    - `params` is the callback's (`code`, `state`, `error`);
    - `kept` is R10's cookie hash, or nil.

    The steps, in order:
    1. `error == "access_denied"` is `cancelled`; any other `error` is `provider_error`.
    2. No `kept`, or a `state` that does not match, or no `code` (a non-String counts as none), is `bad_state`.
    3. The token request is a POST of `grant_type=authorization_code`, `code`, `redirect_uri` and `code_verifier`, with `client_secret_basic`, or `client_secret_post` when it is the only method listed. It goes through `OutsideCall.perform` under `auth.sso.token`. Unreachable, a status of 500 or more, or more than `MAX_BODY` is `unavailable`; another status is `provider_error`.
    4. `OpenIDConnect::ResponseObject::IdToken.decode(id_token, provider.keys)`, then `verify!(issuer: provider.issuer, client_id: provider.client_id, nonce: kept["nonce"])`. A key that is not found is fetched again once (`keys(refresh: true)`). Any `JSON::JWT::Exception`, `OpenIDConnect::ResponseObject::IdToken::InvalidToken`, `JSON::ParserError`, `ArgumentError` or `KeyError` is `bad_token`, as is an `alg` of `none`.
    5. Success answers the `Identity`: `email` only when it is a String of at most 254 characters, `email_verified` only when it is literally `true`, and the refresh token from the token response.

    It never raises for anything the provider or the browser sends.
  - `SignIn::Oidc::Refresh.new(provider:)`, `#call(refresh_token, subject:) -> Result`:
    - `Result = Data.define(:status, :refresh_token)`;
    - a `grant_type=refresh_token` POST under `auth.sso.recheck`;
    - 400 with `error: "invalid_grant"` is `:revoked`;
    - a returned ID token that verifies (with no nonce) but names another `sub` is `:revoked`;
    - unreachable, a status of 500 or more, or a body of the wrong shape is `:unavailable`;
    - success is `:ok` with the rotated token, or the one given.
- [ ] **Step 1: Write the failing tests.**
  - `test "a code exchanged for a signed ID token answers its identity, with the refresh token when given"`.
  - `test "access_denied is cancelled and another error is provider_error"`.
  - `test "a state that does not match, no kept state and no code are bad_state, and nothing is sent to the provider"`.
  - Review Focus 3: `test "alg none, wrong audience, wrong issuer, expired, unknown key and an oversized or non-JSON answer are refused without raising"`. The unknown key fetches the keys twice in all (`idp.requests`), never more.
  - `test "email_verified as the string true is not verified"`.
  - `test "a refresh answers ok with a rotated token, revoked on invalid_grant or another subject, unavailable when the provider is down"`.
  - `test "the token span names the server and whether a refresh token came, and no span holds the code, the tokens or the secret"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** The callback's comment says why each refusal is a reason word and never the provider's message: a provider's `error_description` is text from outside, kept from spans and pages.
- [ ] **Step 4: Run `test/models/sign_in`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: exchange the code, verify the ID token and refresh, refusing junk without raising`.

### Task 5: The sign-in method hook

**Files:**
- Create: `app/models/sign_in_methods.rb`, `config/initializers/sign_in_methods.rb`
- Modify: `lib/content_spiel/plugins.rb` (the fifth hook; the head comment's "These four" becomes five), `app/models/session.rb` (the method list)
- Test: `test/lib/content_spiel/plugins_test.rb`, `test/models/sign_in_methods_test.rb`, `test/models/session_test.rb`

**Interfaces:**
- Produces:
  - `SignInMethods` (a registry like `StudioModules`):
    - `Entry = Data.define(:name, :label, :path, :recheck, :passkey_policy)`;
    - `.reset!`;
    - `.register(name, label:, path:, recheck: nil, passkey_policy: :applies) -> Entry`, which raises on a duplicate name or a `passkey_policy` outside `%i[applies exempt]`;
    - `.entries -> Array<Entry>` in registration order;
    - `.find(name) -> Entry | nil`;
    - `.names -> Array<String>`;
    - `.exempt?(method) -> Boolean`: true for `"sso"` and for an entry with `:exempt`.
  - `ContentSpiel::Plugins.sign_in_methods(&block)`, `REPLAYED_SIGN_IN_METHODS = "ContentSpiel::Plugins.sign_in_methods, called at"`, and `.register_sign_in_methods(registry)`, through `Registrar` (R13). The hooks hash gains `sign_in_methods: []`.
  - The initializer: `Rails.application.config.to_prepare { SignInMethods.reset!; ContentSpiel::Plugins.register_sign_in_methods(SignInMethods) }`, with a comment saying why it is the application's `to_prepare` (the existing initializers' reason).
  - `Session`: `validates :authenticated_with, inclusion: { in: ->(_) { METHODS + SignInMethods.names } }`, and `provider_checked_at` is set at start for an entry with a `recheck`.
- [ ] **Step 1: Write the failing tests.**
  - Plugins: add the new hook to the tests that every hook already faces:
    - a bare name;
    - an owner named like a top-level constant;
    - two owners in one call;
    - an owner taken by another hook;
    - the error naming the hook's place;
    - a block passed where attributes are wanted.

    Plus `test "a sign-in method from outside is replayed after every reset, and a reload keeps it"`.
  - `test "a session may be made with a registered method and not with an unknown one"`.
  - `test "exempt? is true for sso and an exempt entry, false for password and an applying entry"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `test/lib/content_spiel`, `test/models/session_test.rb` and `test/lib/admin_namespace_shadow_test.rb`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: a hook for a gem's sign-in method, with the owner rules and replay of the others`.

### Task 6: Admit, link, unlink, and the invitation by SSO

**Files:**
- Create: `app/services/sso/admit.rb`, `app/services/sso/link.rb`, `app/services/sso/unlink.rb`, `app/services/invitations/accept_with_sso.rb`
- Modify:
  - `app/services/users/update_password.rb` (`clear:`);
  - `app/services/invitations/accept.rb` (the account-making steps the two share go into a private module of `Invitations`, beside `accounts.rb`; no behaviour changes);
  - `app/models/passkeys/policy.rb`;
  - `app/models/audit/sentence.rb`.
- Test: `test/services/sso/admit_test.rb`, `link_test.rb`, `unlink_test.rb`, `test/services/invitations/accept_with_sso_test.rb`, `test/services/users/update_password_test.rb`, `test/models/passkeys/policy_test.rb`, `test/models/audit/sentence_test.rb`

**Interfaces:**
- Consumes: Tasks 1, 4 (the `Identity`) and 5 (`SignInMethods.exempt?`).
- Produces:
  - `Sso::Admit.call(identity, invitation: nil, origin: nil) -> Result`:
    - `record` is the `User` to sign in;
    - `errors` is `[reason]` from `ACCOUNT_REASONS`, or `[:mismatch, email]`;
    - R6's order. A refusal records `sso.refused` (R12), and a mismatch records nothing (the person holds the invitation's link).
    - `# authorize: none (the provider's verified identity is the credential, as an invitation's token is)`.
  - `Sso::Link.call(user, identity:, via:, actor: user) -> Result`: R7; its `user.updated` and `session.ended` come from `UpdatePassword`.
  - `Invitations::AcceptWithSso.call(invitation, identity:) -> Result`, which does in one transaction:
    - it makes the account (the email, the name from the identity, `User.unusable_password`, the link's columns, the groups);
    - it marks the invitation accepted;
    - it records `invitation.accepted` and `sso.linked` (`via: "invitation"`).

    It locks the invitation and answers `[:used]` as `Accept` does.
  - `Sso::Unlink.call(user, actor: Current.actor, origin: nil) -> Result`:
    - only an owner or the trusted nil actor (the console) may (`Users::Manageability.actor_owner?`, else `denied("users.manage", user)`);
    - an unlinked user is a `failure` with no event;
    - in one transaction it clears the three columns, ends every session (`Session.destroy_each_locked`, one `session.ended` with `sso_unlinked` and the count) and records `sso.unlinked`;
    - after the commit it queues `PasswordsMailer.reset` with `origin:`, when mail is ready.
  - `Users::UpdatePassword.new(user, password: nil, password_confirmation: nil, clear: false, …)`:
    - with `clear: true` only the user's own actor or the trusted nil actor may;
    - it writes `User.unusable_password`, with no leak lookup and no blank check;
    - it ends the sessions as any change does, with `keep_acting_session` as passed;
    - it does not clear the throttle, since nobody can now type the password.
  - `Passkeys::Policy`:
    - `#covers?(user)` is false for a linked user;
    - `#enrolment_due?(user, method: "password")` is false when `SignInMethods.exempt?(method)`;
    - `#uncovered_count` leaves linked users out.

    `Authentication#start_new_session_for` passes `method:` (Task 8 calls it).
  - `Audit::Sentence`:
    - `sso.linked`: "linked their account to single sign-on (<issuer_host>)";
    - `sso.refused`: "Single sign-on refused <email or "an unnamed account">: <reason in words>", where the words are "no invited account", "the provider hasn't verified the email" and "an owner signs in with a password and passkey";
    - `sso.unlinked`: "unlinked <user> from single sign-on";
    - `session.created` with `method: "sso"`: "signed in with single sign-on";
    - the three new `session.ended` reasons: "signed out: single sign-on said no", "signed out: unlinked from single sign-on" and "signed out after 24 hours of single sign-on".

    R12's lists.
- [ ] **Step 1: Write the failing tests.**
  - Admit:
    - `test "a linked subject is its account, whatever email the provider now gives"`;
    - Review Focus 2: `test "a second subject with a linked account's email is refused and the link is unchanged; the linked subject with a new email still signs in"`;
    - `test "an unverified email links nothing and records sso.refused email_unverified"`;
    - `test "an owner's email is refused and the owner keeps their password"`;
    - `test "an email with no account and no invitation is refused as no_account, with the email in the event and nowhere else"`;
    - `test "an open invitation for the email is accepted, with the provider's name"`;
    - `test "a start from an invitation with another verified email is a mismatch naming that email, and records nothing"`.
  - Link: `test "linking stores the subject, makes the password unusable, ends every session, deletes passkeys and codes and records sso.linked"`; `test "a reset link issued before linking no longer works"`.
  - Unlink:
    - `test "an owner unlinks: the columns clear, every session ends as sso_unlinked, sso.unlinked is recorded and the reset mail is queued"`;
    - `test "a non-owner is denied and nothing changes"`;
    - `test "the console may unlink"`.
  - UpdatePassword: `test "clear needs the user's own actor or the console, and never asks the leak lookup"`.
  - Policy: `test "a linked user is not covered, and an sso session is never due for enrolment"`.
  - Sentences: one test per event, and `test "the three sso events are Security events and sso.refused has no actor"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** `Sso::Admit`'s comment carries R6's order as the invariant, and says why the email is matched only while an account is unlinked.
- [ ] **Step 4: Run `test/services`, `test/models/audit`, `test/models/passkeys` and `test/lib`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: admit a provider's identity to an invited account, link and unlink it`.

### Task 7: The refusals by rule, and the reminder mail

**Files:**
- Create:
  - `app/models/sign_in_rules.rb`;
  - `app/views/passwords_mailer/sso_reminder.{html,text}.erb`.
- Modify:
  - `app/models/sign_in/password_attempt.rb` (`allowed:`);
  - `app/services/invitations/accept.rb`, `app/services/users/save.rb`, `app/services/users/update_password.rb`, `app/services/passkeys/add.rb`;
  - `app/jobs/password_reset_request_job.rb`, `app/mailers/passwords_mailer.rb`;
  - `config/locales/mail.en.yml` (`mail.sso_reminder.*`) and `config/locales/admin/users.en.yml` (`sso_linked_password`, `owner.sso_linked`);
  - `test/mailers/previews/passwords_mailer_preview.rb`.
- Test: `test/models/sign_in_rules_test.rb`, `test/models/sign_in/password_attempt_test.rb`, `test/services/invitations/accept_test.rb`, `test/services/users/save_test.rb`, `test/jobs/password_reset_request_job_test.rb`, `test/mailers/passwords_mailer_test.rb`, `test/integration/sign_in_enumeration_test.rb` (PR 1's, gaining a case)

**Interfaces:**
- Consumes: Tasks 2 and 6.
- Produces:
  - `SignInRules` (module):
    - `.password_allowed?(user) -> Boolean`;
    - `.passkey_allowed?(user) -> Boolean`, the same rule;
    - `.reminder_instead_of_reset?(user) -> Boolean`: linked, or a non-owner while SSO is required.

    It reads `SignIn::Oidc.required?` and `SignIn::Oidc::Provider.current` and names no controller.
  - `SignIn::PasswordAttempt.new(…, allowed: ->(_account) { true })`: R8. `Telemetry` records `auth.outcome => "refused"` and nothing that says why.
  - `Invitations::Accept` answers `[:sso_required]` under `SSO_REQUIRED`, before it reads the token.
  - `PasswordsMailer#sso_reminder(user, provider:, origin: nil)`, with a button "Open the sign-in page" to `admin_sign_in_url(port: nil, **@url_options)`, built and logged as `reset` is when no origin is known. The words (this plan's, "For the owner" 3):
    - subject "Sign in to %{site} with %{provider}";
    - intro "Someone asked to reset the password of your account on %{site}.";
    - body "Your account signs in with %{provider}, so it has no password here. Sign in with %{provider} on the sign-in page.";
    - ignore "If you didn't ask, you can ignore this mail.".
  - `PasswordResetRequestJob#perform`:
    - `SignInRules.reminder_instead_of_reset?(user)` with a provider queues `sso_reminder`;
    - a linked user with no provider queues nothing and logs `[ContentSpiel] A reset was asked for an account linked to single sign-on, which is off.` (no email, no id);
    - everyone else gets the reset as before.
- [ ] **Step 1: Write the failing tests.**
  - `test "under SSO_REQUIRED a non-owner's right password is refused like a wrong one, and counts in the account's bucket"`.
  - `test "an owner's right password still signs in under SSO_REQUIRED"`.
  - `test "a linked account's password is refused, required or not"` (with the console's password set on it through `update_column` in the test, to prove the rule and not the random digest).
  - Enumeration, PR 1's pattern: `test "a refused-by-rule right password answers as a wrong one: status, body, redirect and the same authenticate_by"`.
  - `test "the password acceptance of an invitation is refused under SSO_REQUIRED"`.
  - `test "a manager's password for a linked user is refused with the sentence, and a linked user cannot be made an owner"`.
  - `test "a reset asked for a linked account sends the reminder with no reset link, and the answer is the same"`; `test "with SSO off a linked account's reset sends nothing and the line names nobody"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** `SignInRules`' comment says that a refusal by rule must look like a wrong password everywhere a bot can see it, and lists those places.
- [ ] **Step 4: Run `test/models/sign_in`, `test/integration/sign_in_*`, `test/services`, `test/jobs`, `test/mailers` and `test/lib/mail_guards_test.rb`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: SSO_REQUIRED and a linked account turn the password and passkeys off, and a reset says to use the provider`.

### Task 8: Start and callback

**Files:**
- Create: `app/controllers/concerns/sso_starts.rb`, `app/controllers/admin/sso_sessions_controller.rb`
- Modify:
  - `config/routes.rb`;
  - `app/controllers/concerns/admin/sign_in_completion.rb` (`provider_token:`, the outside-method rules of R13);
  - `app/controllers/concerns/authentication.rb` (`start_new_session_for(user, method:, provider_token: nil)` passes both on);
  - `app/controllers/admin/sessions_controller.rb` (`allowed:`, the passkey refusal by rule);
  - `app/controllers/admin/second_factors_controller.rb` (the same).
- Test: `test/integration/sso_sign_in_test.rb`, `test/integration/admin_host_test.rb`, `test/lib/telemetry/path_scrubber_test.rb` (or the scrubber's test file), `test/lib/backend_paths_test.rb` (run)

**Interfaces:**
- Consumes: Tasks 1–7.
- Produces:
  - Routes, inside the admin scope and so inside `HostRouteConstraint::Backend`, under `sign-in/` (which the setup redirect already exempts):
    - `post "sign-in/sso", to: "sso_sessions#create", as: :sso`;
    - `get "sign-in/sso/callback", to: "sso_sessions#callback", as: :sso_callback`.
  - `SsoStarts` (included by `Admin::SsoSessionsController` and `InvitationsController`):
    - `STATE_COOKIE = :cs_sso_state`;
    - `sso_provider -> SignIn::Oidc::Provider | nil`;
    - `start_sso(intent:, invitation: nil) -> void`. It builds `Authorization.start` with `admin_sso_callback_url(**SignIn::Oidc.callback_origin(request_origin: request.base_url))`, writes R10's cookie, and `redirect_to authorization.url, allow_other_host: true`, inside `auth.sso.redirect`. A provider whose discovery is `Unavailable` redirects to sign-in with `sso_unfinished`.
    - `take_sso_state -> Hash | nil`: R10's checks, the spend, and the cookie deleted whatever the answer.
  - `Admin::SsoSessionsController < ApplicationController`:
    - `layout "product"`, `allow_unauthenticated_access`, `include SsoStarts`, `include SignInCompletion`;
    - `before_action :require_sso_provider` (404 without one);
    - `rate_limit to: 20, within: 3.minutes, name: "sso"` on both actions, in `SignIn.store`, keyed as sign-in keys an address.

    The actions:
    - `create`: `start_sso(intent: "sign_in")`.
    - `callback`, inside `auth.sso.callback`:
      - `take_sso_state`, then `Callback#call`;
      - unfinished redirects to `admin_sign_in_path` with `admin.sessions.sso_unfinished`;
      - otherwise `Sso::Admit` (with the state's invitation, found by id and still open);
      - a refusal redirects to sign-in with `admin.sessions.sso_refused`;
      - a mismatch redirects to `admin_invitation_path` with `flash[:sso_mismatch] = { "got" => email, "email" => invitation.email_address }`;
      - success is `complete_sign_in(user, method: "sso", provider_token: identity.refresh_token)`, then `after_authentication_url`.
  - `complete_sign_in(user, method:, provider_token: nil) -> Boolean` (R13).
  - `Admin::SessionsController#create` passes `allowed: ->(account) { SignInRules.password_allowed?(account) }`. `#passkey` and the second step's passkey refuse `!SignInRules.passkey_allowed?(user)` as `passkey_failed`, after the verify, so the timing is a verify's.
- [ ] **Step 1: Write the failing tests.**
  - `test "the button redirects to the provider with a state cookie that is Lax, HttpOnly and pathed to the callback"`.
  - `test "the callback signs an invited person in with the sso method, the provider token on the session, and session.created saying sso"`.
  - `test "an SSO session is never sent to enrolment, whatever the policy"`.
  - Review Focus 1: `test "a replayed state, another browser's state, no cookie, another nonce and a late state each end unfinished with no session"`.
  - `test "a cancelled sign-in at the provider answers sso_unfinished and records nothing"`.
  - `test "a refused account answers sso_refused, the same sentence for no account, an unverified email and an owner"`.
  - `test "with no provider both actions are 404"`.
  - Review Focus 5: `test "with an admin host the redirect URI names it, the callback answers there alone, and the public host's callback is the public 404"`.
  - `test "the callback's code and state are in no exported span and no log line"`: the request's span `url.query` is `[FILTERED]`, and the parameters log masks both.
  - `test "under SSO_REQUIRED a non-owner's passkey is refused as passkey_failed, and an owner's signs in"`.
  - `test "complete_sign_in refuses an owner by an outside method and an unknown method raises"`, through a test-only controller class (no route) calling the concern.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** The controller's head comment gives the answers, in the shape of `Admin::SessionsController`'s "THE ANSWERS", and says why the state cookie is Lax.
- [ ] **Step 4: Run them, plus `test/integration/sign_in_*`, `test/integration/passkey_*`, `test/lib/backend_paths_test.rb` and `bin/brakeman`.** Expected: PASS. Brakeman is clean, because `allow_other_host` takes the provider's discovered endpoint and never a parameter.
- [ ] **Step 5: Commit** `feat: sign in to CS Studio through the site's OIDC provider`.

### Task 9: The daily re-check

**Files:**
- Create: `app/jobs/sso/recheck_job.rb`
- Modify: `app/jobs/sessions/sweep_job.rb` (`expired_sso` swept after the absolute and before the idle), `config/recurring.yml` (`sso_recheck`, every hour, in all three blocks), `test/lib/job_queues_test.rb` if it lists jobs
- Test: `test/jobs/sso/recheck_job_test.rb`, `test/jobs/sessions/sweep_job_test.rb`, `test/models/session_test.rb`

**Interfaces:**
- Consumes: Tasks 1, 4 and 5.
- Produces:
  - `Sso::RecheckJob#perform(at: Time.current)`, inside `auth.sso.recheck_run`:
    - for the due SSO sessions with a token, in batches of 100 (`Session.where(authenticated_with: "sso").where.not(provider_token: nil)` and `provider_checked_at` at or before `at - 24h`), it calls `Refresh` with the user's `sso_subject` and acts per R5;
    - for every `SignInMethods` entry with a `recheck`, it calls `entry.recheck.call(session)` on its due sessions the same way;
    - a recheck that raises is reported (`Rails.error.report`, handled) and counts as `:unavailable`, so one gem cannot stop the run.

    It records `auth.session.count` of the sessions it ended.
  - The writes on `sessions` carry `# version: none (a session is on no public page)`.
- [ ] **Step 1: Write the failing tests.**
  - Review Focus 4: `test "revoked ends the session, unavailable keeps it until the grace is spent, a rotated token is stored, and no token ends at 24 hours"`.
  - `test "a session checked less than 24 hours ago is not sent to the provider"`.
  - `test "a gem's recheck is called for its own sessions, and one that raises ends nothing and stops nothing"`.
  - `test "the sweep ends expired_sso sessions under one event per run"`.
  - `test "a request that meets an SSO session past its check ends it as expired_sso"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `test/jobs`, `test/models/session_test.rb` and `test/lib/job_queues_test.rb`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: re-check every SSO session with its provider once a day`.

### Task 10: System status's Single sign-on row

**Files:**
- Modify: `app/models/setup/system_check.rb` (`single_sign_on` after `admin_address`; `Result` gains the status `:off`), the component that draws a check's status (the state chip's neutral tone for `:off`), the locale file of `admin.system_status.*` (`sso.label`, `sso.ok`, `sso.required`, `sso.unreachable`, `sso.off`, verbatim from the card)
- Test: `test/models/setup/system_check_test.rb`, the status list's component test

**Interfaces:**
- Consumes: Tasks 2 and 3.
- Produces:
  - `Setup::SystemCheck.new(…, sso_provider: SignIn::Oidc::Provider.current, sso_required: SignIn::Oidc.required?)`.
  - `#single_sign_on -> Result` per R16. The `reason` is the `Unavailable`'s word, never a message.
- [ ] **Step 1: Write the failing tests.**
  - `test "with a provider that answers the row is ok and names the provider and the issuer host"`.
  - `test "required adds its sentence"`.
  - `test "a provider that doesn't answer is a warning with the reason word"`.
  - `test "without a provider the row is off, drawn neutral"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `test/models/setup`, `test/integration/admin/system_status_test.rb` and `test/integration/setup_*`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: System status says whether the SSO provider answers`.

### Task 11: The sign-in panel (depends on the design cards)

Build to the card StudioSingleSignOn, screens 1–3. The words are the card's, verbatim.

**Files:**
- Create: `docs/superpowers/specs/2026-11-13-sso-screens.md`, the scratchpad summary copied whole, with the card's link and version.
- Modify:
  - `app/views/admin/sessions/new.html.erb`;
  - `app/controllers/admin/sessions_controller.rb` (`new` reads `params[:owner]`);
  - `config/locales/admin/sessions.en.yml` (`new.sso`, `new.sso_lead`, `new.owner_sign_in`, `new.owner_title`, `new.owner_lead`, `new.sso_instead`, `sso_refused`, `sso_unfinished`);
  - `test/lib/admin_i18n_test.rb` if it lists the view.
- Test: `test/integration/sso_sign_in_page_test.rb`, `test/system/admin/sso_sign_in_test.rb`

**Interfaces:**
- Consumes: Task 8's routes, `SignIn::Oidc::Provider#name`, `SignInMethods.entries`.
- Produces: what the page draws.
  - With a provider, not required:
    - the password form unchanged;
    - "or";
    - "Sign in with %{provider}" (`button_to admin_sso_path`, secondary, full width) first, then the passkey button.

    Sign in stays the only primary.
  - With `SSO_REQUIRED` and no `owner` parameter:
    - the lead `sso_lead`;
    - the provider's button, primary;
    - the small link `owner_sign_in` to `admin_sign_in_path(owner: 1)`.
  - With `owner=1`:
    - the title `owner_title` and the lead `owner_lead`;
    - the password form and the passkey button;
    - the link `sso_instead`.

    The parameter only changes what is drawn: a non-owner who signs in there meets R8's ordinary refusal.
  - Each `SignInMethods` entry is a secondary button after the provider's, labelled `t(entry.label)`, posting to `main_app.public_send(entry.path)`. The card drew none, so it uses the provider button's look ("For the owner" 5).
  - `sso_refused` and `sso_unfinished` reach the panel's danger notice through the flash, as the other refusals do, with `provider:`.
- [ ] **Step 1: Write the failing tests.**
  - `test "with a provider the page offers it under the form, as a secondary button before the passkey's"`.
  - `test "with SSO required the provider is the primary, and the owner link opens the password form with its lead"`.
  - `test "a gem's sign-in method is a button on the page"`.
  - `test "the refusal sentences name the provider"`.
  - Browser (with `with_fake_idp`, and `Capybara.app_host` on the server's port): `test "Sign in with the provider signs an invited person in and lands on the dashboard"`; `test "a cancelled sign-in at the provider comes back to the panel with the sentence"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them, plus `test/integration/sign_in_*` and `test/lib/admin_i18n_test.rb`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: the sign-in panel offers the site's provider, and an owner's own way in when SSO is required`.

### Task 12: The invitation page (depends on the design cards)

Card StudioSingleSignOn, screen 4.

**Files:**
- Modify:
  - `app/controllers/invitations_controller.rb` (`include SsoStarts`; the action `sso`; the mismatch flash);
  - `config/routes.rb` (`post "invitation/sso", to: "/invitations#sso", as: :invitation_sso`, beside the invitation's routes);
  - `app/views/invitations/show.html.erb`;
  - the invitation page's script (`invitation_token_controller.js`), so the second form gets the token too;
  - `config/locales/invitations.en.yml` (`show.or`, `show.sso`, `show.sso_mismatch`).
- Test: `test/integration/invitation_sso_test.rb`, `test/system/invitation_sso_test.rb`

**Interfaces:**
- Consumes: Tasks 6, 8.
- Produces:
  - `InvitationsController#sso` reads the token from the body. An open invitation calls `start_sso(intent: "invitation", invitation:)`; any other token answers as `update` does for `:expired` and `:used`.
  - The page: the password form, "or", "Continue with %{provider}". Under `SSO_REQUIRED` it shows only "Continue with %{provider}", as the primary.
  - A `flash[:sso_mismatch]` draws `sso_mismatch` with `got:` and `email:` in the page's danger notice.
- [ ] **Step 1: Write the failing tests.**
  - `test "Continue with the provider accepts the invitation and signs the new person in, linked"`.
  - `test "another verified email comes back to the page naming both addresses"`.
  - `test "a lapsed or used token gets the page's own answer and goes nowhere"`.
  - `test "under SSO_REQUIRED the page shows only the provider's button"`.
  - Browser: `test "an invitation is accepted through the provider"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them, plus `test/integration/invitation*` and `test/system/invitation*`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: accept an invitation by signing in with the site's provider`.

### Task 13: The user editor's badge and Single sign-on zone (depends on the design cards)

Card StudioSingleSignOn, screen 5.

**Files:**
- Create:
  - `app/components/admin/users_screen/sso_zone_component.{rb,html.erb}`;
  - `app/controllers/admin/sso_links_controller.rb`.
- Modify:
  - `config/routes.rb` (in the users' `member` block: `delete :sso_link, to: "sso_links#destroy"`);
  - the user editor's view: the badge, and the zone after the Owner zone;
  - `config/locales/admin/users_screen.en.yml` (`sso_zone.*`, verbatim);
  - `test/lib/component_screens_test.rb`'s map if it asks;
  - `test/lib/admin_i18n_test.rb` (`CONVERTED`).
- Test: `test/components/admin/users_screen/sso_zone_component_test.rb`, `test/controllers/admin/sso_links_controller_test.rb`, `test/system/admin/user_sso_test.rb`

**Interfaces:**
- Consumes: Task 6 (`Sso::Unlink`).
- Produces:
  - `Admin::UsersScreen::SsoZoneComponent.new(user:, provider_name:, url_options: {})`, drawn only for a linked user, and only to an owner. It holds:
    - `heading` and `body`;
    - `trigger` ("Unlink…", secondary), opening a non-destructive `Admin::Ui::ConfirmDialogComponent` with `title` and `confirm_body`, whose confirm is `confirm`.
  - The badge `sso_zone.badge`, beside the user's name in the editor's head, for a linked user.
  - `Admin::SsoLinksController#destroy`:
    - `Sso::Unlink` with `origin: mail_link_origin`;
    - success is a `see_other` redirect to the user's editor with the toast `unlinked`;
    - a refusal is `Admin::RefusalStatus` with its toast;
    - an out-of-scope user is a 404 (`AccessControl.scope`).
  - With SSO off, `provider_name` is `I18n.t("admin.components.users_screen.sso_zone.provider_fallback")`: "your sign-in provider" ("For the owner" 4).
- [ ] **Step 1: Write the failing tests.**
  - Component: `test "the zone names the person and the provider, and its dialog's words"`; `test "the zone is not drawn for an unlinked user or for a viewer who is no owner"`.
  - Controller: `test "an owner unlinks, the person is signed out everywhere and the mail is queued"`; `test "an admin who is no owner is refused and nothing changes"`.
  - Browser: `test "Unlink… then Unlink unlinks, with the toast, and the badge is gone"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them, plus `test/integration/admin/users_*`, `test/lib/component_screens_test.rb`, `test/lib/admin_i18n_test.rb` and `test/lib/admin_design_rules_test.rb`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: the user editor shows who signs in with SSO, and an owner unlinks them`.

### Task 14: Your account for a linked person (depends on the design cards)

Card StudioSingleSignOn, screen 6.

**Files:**
- Create: `app/components/admin/account_screen/sso_card_component.{rb,html.erb}`
- Modify: `app/views/admin/accounts/edit.html.erb`, `app/controllers/admin/accounts_controller.rb` (no passkeys or codes loaded for a linked person), `config/locales/admin/account_screen.en.yml` (`sso_card.*`, verbatim), `test/lib/admin_i18n_test.rb`
- Test: `test/components/admin/account_screen/sso_card_component_test.rb`, `test/integration/admin/account_test.rb` (or the account screen's integration file)

**Interfaces:**
- Consumes: Task 6.
- Produces:
  - `Admin::AccountScreen::SsoCardComponent.new(provider_name:)`: `title`, `intro` and `body`.
  - For a linked person, Your account draws it in place of the Password card, draws neither the Passkeys card nor the Recovery codes card, and keeps Sessions.
  - The password update of `AccountsController` answers a linked person with R8's refusal, for a crafted request.
- [ ] **Step 1: Write the failing tests.**
  - `test "a linked person's account shows the Sign-in card and Sessions, and no password, passkeys or codes"`.
  - `test "a crafted password change for a linked person is refused and changes nothing"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them, plus `test/system/admin/account_*` one file at a time.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: Your account says a linked person signs in with the provider`.

### Task 15: The span guard, the reference, the changelog and the Design System stamp

**Files:**
- Create: `test/integration/sso_telemetry_test.rb`
- Modify:
  - `docs/reference/access-control-and-audit.md`:
    - a new part, "Single sign-on", covering R6, R7, R8, R10, R11 and R12 as invariants, with the tests that hold them;
    - a new part, "A sign-in method from outside", with R13's contract and limits;
    - the rules a change can break silently: **no guard** for a new place that reads a password or a passkey and does not ask `SignInRules`;
  - `docs/reference/content-blocks-and-types.md`: the hooks' list gains the fifth, pointing to the part above;
  - `docs/reference/hosting.md`:
    - "Sign-in on the open internet": SSO, the address to register (R11), `offline_access`, what a provider outage does (R5), and that the refresh token needs the encryption keys;
    - "Behind a DMZ": the callback follows the admin host;
    - "Telemetry": R14's spans and attributes, and a Honeycomb query: `auth.sso.callback` grouped by `auth.sso.reason` over time;
  - `docs/reference/users-groups-tokens.md`: the badge, the zone, unlink, and that a linked account cannot be an owner;
  - `docs/reference/mail.md`: the reminder, and unlink's reset mail;
  - `CLAUDE.md`: the access-control line of the reference index gains `app/models/sign_in/oidc/`, `app/models/sign_in_rules.rb`, `app/models/sign_in_methods.rb`, `app/services/sso/`, `app/jobs/sso/`, `app/controllers/concerns/sso_starts.rb`, `app/controllers/admin/sso_sessions_controller.rb` and `sso_links_controller.rb`, and its Deploy paragraph names the five `SSO_*` variables;
  - `test/support/design_system_entries.rb`: `VERSION = "1794552254-57d8"`, and `StudioSingleSignOn` in `ENTRIES`;
  - `CHANGELOG.md` `## Unreleased`:
    - `### Added`: SSO, `SSO_REQUIRED`, linking, unlinking, the invitation by SSO, the daily re-check, the System status row, the reminder mail, the events and the spans, and the sign-in method hook;
    - `### Changed`: a linked account's password is cleared and its passkeys removed; a reset for it sends the reminder;
    - `### Breaking`: the new top-level names `Sso`, `SignInRules` and `SignInMethods`, which a gem's owner of those names is now refused by (CLAUDE.md, "A new top-level name");
    - `### For a gem or an outside caller`: `ContentSpiel::Plugins.sign_in_methods`; `Admin::SignInCompletion#complete_sign_in(provider_token:)` and its answer; `SignIn::PasswordAttempt(allowed:)`; `Session.start(provider_token:)`; `Users::UpdatePassword(clear:)`; `SignIn::SpentChallenge.take`; the `SignIn::Oidc` objects; `SignIn::OUTCOMES`.
- Test: the span guard, `test/lib`, `bin/changelog-guard origin/main`

**Interfaces:**
- Consumes: everything.

- [ ] **Step 1: Write the span guard** `test/integration/sso_telemetry_test.rb`, in the pattern of PR 1's `sign_in_telemetry_test.rb`:
  - `test "an SSO sign-in, refused, unfinished and accepted, exports auth.sso.redirect, auth.sso.callback and auth.sso.token under the request with only listed words"`;
  - `test "the re-check job exports auth.sso.recheck_run with a CLIENT auth.sso.recheck per session"`;
  - `test "no span or event holds the code, the state, the nonce, the verifier, an ID, access or refresh token, the client secret or the provider's email"`. The values are planted through the fake provider and searched for in every attribute and event.
- [ ] **Step 2: Run it.** It passes on what Tasks 3–9 built, or it names the leak, which is fixed in the code that leaked it.
- [ ] **Step 3: Write the docs and the changelog.** Then run `bin/rails test test/lib` (the docs, the variable table, the Design System entries and the changelog guard's test) and `bin/changelog-guard origin/main`. Expected: PASS.
- [ ] **Step 4: Run the whole unit suite** (`bin/rails test`), then the browser files this PR added, one at a time, then `bin/rubocop` and `bin/brakeman`.
- [ ] **Step 5: Commit** `docs: single sign-on and the sign-in method hook in the reference, the changelog and the Design System stamp`.

The PR's Documentation section names these guide pages: Signing in, Your account, Users, the invitation, System status, and a new integrator page, "Single sign-on (OIDC)", which covers the variables, the redirect URI and `SSO_REQUIRED`. It also names an integrator page for the sign-in method hook.

## For the owner (not decided here)

1. **Linking deletes the account's passkeys and recovery codes** (card D5, R7). The spec says a linked account "signs in through SSO only" but is silent on its passkeys. The other choice keeps them, unusable, until an unlink.
2. **The wizard with SSO.** §6 says a covered site "can't finish the wizard without [a passkey], or without SSO when the site uses it". The founding person is an owner, and owners never link, so in this plan the wizard still asks for the passkey, and SSO appears there only as the system check's row (R16).
3. **Words the card did not draw:** the reminder mail (R15); "This account signs in with %{provider} and has no password here."; "%{name} signs in with %{provider}. Unlink them first: owners keep a password and a passkey."; and the audit sentences (Task 6). The owner zone's Make owner for a linked person answers with a toast, not a drawn disabled state.
4. **Taking the SSO variables away strands linked accounts.** They cannot sign in, a reset sends nothing (R15), and the zone calls the provider "your sign-in provider" until an owner unlinks each one. A console command that unlinks everyone is not in the spec.
5. **The sign-in method hook's contract** (R13) becomes public once released:
   - an outside method never signs in an owner;
   - it records only `session.created`;
   - `SSO_REQUIRED` does not touch it;
   - its button takes the provider button's look, which no card drew.
6. **Sessions already open when `SSO_REQUIRED` is turned on** carry on until they expire (12 hours idle, 14 days at most). Ending a non-owner's password sessions at their next request would take one more `session.ended` reason.
7. **Unlink sends the ordinary reset mail**, whose link lasts 15 minutes. A person who opens it later asks for a new reset on the sign-in page, which, now unlinked, sends the ordinary reset.
8. **An unreachable provider is given 2 hours of grace past the 24-hour check** (R5), so "out within a day" is at most 26 hours while the provider is down.
