# CS Studio sign-in for the open internet: design

Status: draft for the owner's approval, 2026-11-10.
Issues: #172 (lock-out per account), #170 (sessions expire, "Your sessions"), #169 (second factor; built here as passkeys), a new SSO part for integrators. #176 (alerting) and #175 (backups) are separate projects and only touched where noted.

## Why

The owner wants to publish sites whose CS Studio sign-in faces the internet with nothing in front of it. Today the guide site sits behind Cloudflare Access only because it is not launched yet. Once it launches, and on every client site, `/cs-studio/sign-in` is open to every bot. Sign-in has to hold up without help from in front.

There are two kinds of site, and each gets its own way in:

- **The owner's own sites** (the guide, a personal page). The owner signs in with a passkey kept in 1Password: no password to guess, phish or leak.
- **Integrators' client sites.** The client's team signs in through their company's identity provider (Okta, Entra, Google Workspace and similar), which also enforces their second factor. The integrator configures this per site.

## Goals

1. **Guessing is pointless.** Once a person has a passkey or uses SSO, a stolen or guessed password alone signs nobody in.
2. **Guessing is slow and noticed.** Attempts are throttled by address and by account. A run spread across many addresses is still slowed. Every lock-out is audited, and the account's owner is mailed.
3. **Bots learn nothing.** Sign-in, password reset and invitation acceptance give the same answer, with the same timing, whether or not an account exists.
4. **A leaked session is bounded.** Sessions expire when idle and absolutely. A person sees their own sessions and can end any of them or all of them. An owner can end anyone's.
5. **Integrators can plug in a company IdP** through OpenID Connect, by configuration only, with no code in the site.
6. **Nobody gets locked out of their own site.** An emergency owner path always exists that depends on no outside service, and the setup wizard and the console reset keep working.

## Non-goals

- **Automatic provisioning or group mapping from the IdP.** The owner chose invite-first, because it is simpler: an account exists only because an owner invited it, and CS Studio's groups decide what it may do. SSO only replaces the password.
- **SAML.** It comes later, when a client asks.
- **Authenticator-app codes (TOTP).** Left out at first: passkeys and recovery codes cover the same ground more safely. They can be added later if a client asks.
- **Sign in with Google or GitHub for individuals** (social login). Any of them can be configured as the site's one OIDC provider if wanted, but there is no multi-provider picker.
- **General alerting** (an error tracker, audit-event alert rules, the readiness check) is #176. **Backups** are #175.

## Anti-goals (a failure even if it technically works)

- An owner locked out of their own site by a provider outage, a lost phone or a misconfigured IdP.
- A response that tells a bot an address has an account: a different message, a different status, a measurably different time, or a different redirect.
- A bot check that ordinary people meet on every sign-in.
- Weakening the existing rules: owners stay protected by `Users::OwnerProtection`, a password still changes only through `Users::UpdatePassword` or `Users::Save`, and `Audit.record` stays the one path for events. No secret (a password, passkey material, a recovery code or an OIDC secret) reaches a log, an audit snapshot or a page.

## Decided by the owner

- **Scope:** all three sign-in issues (#172, #170, #169) plus SSO for integrators, in one project.
- **SSO:** invite first. A provider identity is tied to an invited account on its first SSO sign-in. Accounts are not created from the IdP.
- **The owner's own way in:** passkeys (1Password).
- **The integrator's way in:** OIDC with Okta and similar providers.
- **The target:** the sign-in must be "iron clad against bots brute-forcing".
- **Who owns a client's site:** on a client site with SSO, the integrator holds the owner accounts, which use passkeys and recovery codes as the site's emergency way in. The client's own people are admins, editors and so on, signing in through SSO. Removing them from the IdP therefore always locks them out.

## The design

**Development stays simple (the owner, 2026-11-11).** In development, sign-in is plain email and password, as today:
- The leaked-password check is off unless switched on. The dev seed's simple password would otherwise be refused.
- There is no bot check, since development has no Turnstile keys.
- When passkeys come, the policy defaults to "nobody required" in development.

The throttles stay, because they never get in the way of ordinary use. Production's defaults are unchanged, and tests switch each part on where they test it.

### 1. Throttles, the bot check and leaked passwords (#172)

**Throttles.** There are three independent buckets, each counted on failed attempts only:
- **Per address:** the existing `rate_limit` in `Admin::SessionsController`, kept as it is.
- **Per account:** keyed by the normalised email, whether or not an account exists, so the bucket does not reveal one. It is an exponential back-off. A lock-out is temporary, never permanent, so a bot cannot lock a real person out for good.

  **How "a bot cannot lock a real person out for good" is met (as built).** A temporary lock alone does not meet it: a bot that tries once at each lock's end keeps the email closed nearly all day. So a browser that has signed in to the account carries a signed, encrypted device cookie (OWASP's "device cookie": a random id and an HMAC of the account, set only after a right password), and its attempts count in a bucket of that account and that device, with the same back-off, which the account's lock does not touch; the address buckets and the bot check still apply to it. A new password, set through the reset or the console command, clears the account's run and lock, so the reset the lock-out mail offers lets the person in from any browser.
- **Wide per address:** a longer-window cap per address, so a slow drip is caught too.

The counters live where every process sees them: `Rails.cache` (Solid Cache) or a table. They never live in a process's memory, unlike Rack::Attack's current `MemoryStore`. While the account's bucket is closed, the panel says "Try again in a few minutes." The owner decided this on 2026-11-11. It reveals nothing, because the email bucket counts the same whether or not an account exists, so an address with no account locks and answers exactly alike. The lock records `session.locked`. When the email belongs to an account, the account's address is mailed: the time and the address the attempts came from, and how to reset.

**The bot check.** Cloudflare Turnstile appears on the sign-in form only after repeated failures from an address or for an account. A first-time visitor never sees it. It is verified on the server. It is optional per site: with no Turnstile keys configured, the throttles still stand alone.

**Leaked passwords.** When a password is set or changed (wizard, invitation, reset, Your account, the user editor), it is checked against Have I Been Pwned's range API. Only the first five characters of its SHA-1 are sent, and a known-leaked password is refused with a sentence that says why. If the API is unreachable, the password is accepted and the check is logged, never failed closed. It can be switched off for offline development.

**Enumeration.** The reset request already answers the same either way. Sign-in, the reset and an invitation's acceptance are reviewed for status, body, redirect and timing differences, and timing is equalised with a dummy password hash when no account exists. A test holds each.

### 2. Sessions (#170)

- **New columns on `sessions`:** `last_seen_at`, written at most every five minutes; `authenticated_with` (`password`, `passkey`, `sso`, `recovery_code`); and `expires_at`, the absolute end.
- **Limits:** an idle timeout and an absolute timeout, checked in `Session.from_cookies` (or where the authentication concern resolves the cookie). The cookie stops being `permanent` and lives for the absolute timeout.
- **An SSO session** re-checks with the IdP once a day, silently where the provider allows it. If the check fails, the session ends, so a person removed from Okta is out within a day.
- **"Your sessions"** in Your account lists browser and OS from the user agent, the address, last seen and how the session signed in, marked "This session" where it applies. It offers End on each and "Sign out everywhere else".
- **An owner** can end every session of another user from the user editor. This is in the owner zone, bounded as owner actions are today.
- **A sweep job** deletes expired sessions.
- **Sessions already open on deploy:** the release that brings this signs everyone out once. Every existing session row is deleted in the migration, which `CHANGELOG.md` names under "Migrations needing action". Nobody keeps an unbounded session.
- **Audit:** every ending records `session.ended` with a reason: `signed_out`, `expired_idle`, `expired_absolute`, `ended_by_self`, `ended_by_owner`, `sso_revoked` or `password_changed`. A sweep may record one summary per run instead of one event per row; that is the builder's call.

### 3. Passkeys and recovery codes (#169)

- **Passkeys:** WebAuthn through a maintained gem (`webauthn-ruby`). A person may hold several, each with a name they choose ("1Password", "MacBook").
- **Sign-in with a passkey alone:** "Sign in with a passkey" on the sign-in page, using discoverable credentials. A passkey is already two factors: the device plus its unlock.
- **A password together with a passkey:** once an account holds a passkey or recovery codes, its password alone is not enough. Password sign-in then asks for the passkey or a recovery code before a session starts. The password stays only as a way to enroll a passkey and as the emergency path.
- **Recovery codes:** ten single-use codes, shown once at enrolment, stored only as digests. Using one is audited and mailed, and the person is asked to add a new passkey.
- **Which domain a passkey belongs to:** a passkey is registered to the registrable domain of `PUBLIC_HOST`, so `www.example.org` and `example.org` share it. If the site moves to a new domain, every passkey stops working. The recovery codes still do, because they are not tied to a domain. The documented path after a move is to sign in with a recovery code and add a new passkey. The console is not needed.
- **Policy, per site:** set in Settings, by owners only. Who must have a passkey (or use SSO): nobody, owners and admins, or everyone. "Admins" are holders of `users.manage`, `groups.manage` or `tokens.manage`. A person the policy covers who has no passkey is taken to enrolment after their next sign-in, and can do nothing else until they enroll.
- **Audit:** `passkey.added`, `passkey.removed`, `recovery_codes.generated`, `recovery_code.used` and `session.second_factor_failed`. Adding a passkey and using a recovery code are mailed to the account.

### 4. Single sign-on for integrators (OIDC)

- **One OpenID Connect provider per site,** configured by environment variables (listed in `hosting.md`'s variable table and held by #138's guard):
  - the issuer;
  - the client id;
  - the client secret, which is a secret;
  - the button's label ("Sign in with Okta");
  - an optional `SSO_REQUIRED`.

  Discovery comes from the issuer's well-known document. A maintained gem is used, for example `omniauth_openid_connect` with `omniauth-rails_csrf_protection`, or `openid_connect`.
- **Invite first:**
  - The first SSO sign-in matches the IdP's verified email (`email_verified` must be true) to an existing account or a pending invitation, then stores the provider's subject (`sub`) on the account. Later sign-ins match on `sub` only, so an email change at the IdP doesn't break the link, and nobody can take over an account by changing their IdP email.
  - An email that matches no invited account is refused with the same sentence as any refusal, and is audited.
  - An invitation can be accepted by SSO instead of choosing a password.
- **With `SSO_REQUIRED`:**
  - Password and passkey sign-in are off for everyone but owners.
  - Owners keep a password with a passkey or recovery codes as the emergency path, which the policy then requires of them.
  - The sign-in page shows the SSO button, and the owner path stays reachable from a small "Owner sign-in" link.
- **Linking ends the account's own password sign-in.** Once an account's `sub` is stored, that account signs in through SSO only. This holds whether or not `SSO_REQUIRED` is set, and doesn't apply to owners. Its password is cleared, and a reset request for it answers exactly as any reset does. The mail that goes out says to sign in with the provider, and no reset link is in it. Unlinking an account is an owner action in the user editor, and it sends an ordinary password-setting mail. **Owners never link.** They keep a password together with a passkey or recovery codes, which are the site's emergency way in.
- **The daily re-check:** where the provider gives a refresh token (`offline_access`), it is stored encrypted with the Active Record encryption keys that forms already need, and used once a day. Where it doesn't, the SSO session ends after 24 hours and the person signs in again. "Removed from the IdP means out within a day" therefore always holds.
- **The second factor is the IdP's:** an SSO session is not asked for a passkey.
- **A hook for gems:** `ContentSpiel::Plugins` gains a sign-in method hook, with an owner check and replay as the existing hooks have. A gem can then add SAML or another method later without core changes. Its contract and limits are written in the hooks reference.
- **Audit:** `session.created` carries `authenticated_with: "sso"`, plus `sso.linked` and `sso.refused`.

### 5. Mail the owner of an account

Minimal mail, for these events only:
- a lock-out;
- a new passkey;
- a recovery code used;
- a sign-in from a browser not seen on that account in the last 90 days, if that is cheap to tell from the stored user agent and address.

Each goes to the account's own address. They use the existing mailer and layout, with words as keys. General alerting stays #176.

### 6. Operations and documentation

- **`docs/reference/hosting.md`:**
  - the Cloudflare rate-limit rule for the sign-in path, to set by hand;
  - the Turnstile keys;
  - the OIDC variables;
  - that Cloudflare Access may stay as an extra layer.
- **The order for the guide site:** ship this, enroll the owner's passkey, set the policy, then remove Access.
- **The setup wizard:** the founding owner sets a password (checked against leaked passwords) and is then asked to add a passkey. A site whose policy covers owners can't finish the wizard without one, or without SSO when the site uses it.
- **The console reset:** the existing console password command also removes the account's passkeys and recovery codes, if asked, and ends its sessions. That is the last-resort path and must stay simple.
- **The guide:** the pages on signing in, Your account, users and the setup wizard, plus a new integrator page on SSO. These are named in each PR's Documentation section.

### 7. Telemetry: spans on every sign-in decision

The owner wants each part of sign-in visible in traces (Honeycomb today). A bot run must show up as a pattern, and a slow provider or an outside check must show up as a slow span. The app has no hand-made spans yet; this feature brings in the first ones, and with them the rules for all later ones.

- **One tracer.** It lives on `Telemetry` (`lib/telemetry.rb`), for example `Telemetry.tracer`, and is a no-op when the SDK isn't configured, so a test or a plain development boot pays nothing. Spans are started with `in_span`.
- **Under the request's own span.** Every span is a child of the request's (or job's) server span. `Telemetry::WorkSampler` keeps the trace then, and drops nothing new: no span here is a root.
- **The spans** (the names are the builder's, but keep one prefix such as `auth.`):
  - the sign-in attempt as a whole;
  - each throttle decision, with which bucket and whether it tripped;
  - the bot check's server verification, a CLIENT span to Turnstile;
  - the leaked-password lookup, a CLIENT span to Have I Been Pwned;
  - passkey registration and verification;
  - recovery code use;
  - the OIDC redirect, callback, token exchange and daily re-check, the last two as CLIENT spans to the IdP;
  - session expiry decisions and the sweep job;
  - the lock-out and alert mails.
- **Attributes say what happened, never who or what was typed.** Allowed:
  - the method (`password`, `passkey`, `sso`, `recovery_code`);
  - the outcome (`ok`, `refused`, `locked`, `bot_check_required`, `bot_check_failed`, `second_factor_required`);
  - the bucket;
  - the back-off level;
  - whether the account exists, **only** as a span attribute, never in a response;
  - the policy that applied;
  - the provider's issuer host;
  - an outside check's result class (`leaked`, `clean`, `unavailable`);
  - durations.
- **Never in a span, an event or a log:**
  - the email address, a password or any part of its hash;
  - passkey material or a challenge;
  - a recovery code;
  - an OIDC code, state, token or secret;
  - the Turnstile token.

  The user's id may appear only after a successful sign-in, as on any signed-in request. The request's own address attribute is the instrumentation's and stays as it is.
- **Held by tests:**
  - A test exports the spans of one refused, one throttled and one successful sign-in by each method, into the in-memory exporter the test environment already uses (`test/integration/opentelemetry_test.rb`'s pattern).
  - It asserts the names, the parent, and that no attribute or event holds the email typed, the password typed, a recovery code or an OIDC token. The values are planted and searched for.
  - `Telemetry::PathScrubber` already drops the OIDC callback's query (code and state), and a test holds that for the callback route.
- **Documented.** `docs/reference/hosting.md`, "Telemetry", lists the spans and their attributes. It also gives a Honeycomb query that shows a credential-stuffing run: refused attempts grouped by the bucket that tripped, over time.

### 8. The screens

These are drawn by the design agent before the build, as cards in the Design System, then built:
- the sign-in panel's passkey and SSO buttons and the second-factor step;
- the bot check's place;
- Your account's Passkeys and Sessions cards;
- recovery codes, shown once;
- the enrolment interstitial;
- the Settings policy card;
- the owner's "End all sessions" in the user editor.

### 9. A seam for a members area later

**What the owner foresees:** a sign-in on the public site, where a page and its children form a private section that only signed-in readers see. That is its own later project. Its private pages bypass the public cache and ETag, and stay out of the sitemap, the feeds, search and post lists. It is not built here. This design must not block it:
- **One layer for both kinds of sign-in.** The throttles, the bot check, the leaked-password check, the enumeration rules, passkey verification and the OIDC link sit in plain objects that a second kind of sign-in can call. Only the screens, routes and session handling are CS Studio's own.
- **Members get their own sessions and cookie.** If members come, they are a separate kind of account with their own sessions and their own cookie name. A member's sign-in can then never be a CS Studio session, and the CS Studio cookie never reaches public pages. Nothing in this design assumes that `User` is the only account kind.

## How it ships

There are separate PRs, each with its own reviewed plan. Each is usable on its own:
1. **Throttles, enumeration, the bot check and leaked passwords** (§1). This is the biggest protection for the least change, and needs no design work beyond the Turnstile spot.
2. **Sessions** (§2), with the Sessions card.
3. **Passkeys, recovery codes and the policy** (§3), with their cards and mails.
4. **OIDC SSO and the gem hook** (§4).

## My calls (marked so the owner can check them)

- **Per-account back-off:** 5 failures, then 1 minute, doubling to a 1 hour cap, reset by a success.
- **Wide per-address cap:** 50 failures an hour.
- **Turnstile** after 3 failures from an address or for an account within 15 minutes.
- **Idle timeout:** 12 hours. **Absolute timeout:** 14 days. An SSO session re-checks every 24 hours.
- **The leaked-password check** fails open, and is logged when it does.
- **Ten recovery codes.**
- **The admin-holder definition** for the policy: `users.manage`, `groups.manage` or `tokens.manage`.
- **The sign-in method hook for gems** is in scope, to match the owner's "options for integrators".
- **MCP API tokens are unchanged:** they are bearer credentials, already throttled per token, and outside this design.

## Left to the builder

- Gem choices, within "maintained and widely used".
- Where the counters live (Solid Cache or a table).
- How timing equalisation is measured in tests.
- The exact audit event names, within the repo's pattern.
- The sweep cadence.
- How the new-browser check is computed, or dropping it if it is costly.
