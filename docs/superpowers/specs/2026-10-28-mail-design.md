# Mail

Status: draft (2026-10-28). The owner's decisions are from the brainstorm of 2026-10-28; the screens and words are Claude Design's (`.superpowers/design-answers/2026-10-28-mail.md`, M1–M7). Calls marked "(our call)" are this spec's.

## Why

A site cannot send mail today. `ApplicationMailer` sends from the literal `from@example.com`, production's mail settings are commented-out boilerplate, and the password-reset request always says a link was sent, also when nothing could be (roadmap: "Hosting and the dry run", part 2, "Mail"; known gaps). Invites (roadmap "Next", item 6) need mail too, and so will notifications later.

## What a person gets

**Whoever sets up a site** gets a "Mail" step in the setup wizard: the SMTP details of the provider they choose, and "Send test mail" to their own address. They can skip it.

**An owner** (`settings.manage`) finds the same settings in Settings → Mail, with the state of mail at a glance: not set up, saved but not tested, working, or the last send failed.

**Everyone signing in** sees "Forgot your password?" only once mail works. Before that the place of the link says "Forgot your password? Ask the site's owner to reset it."

**Someone who manages users** (`users.manage`) can invite a person by email once mail works. The invited person gets a mail with a link, sets a password and is signed in.

## Decisions

1. **The CMS names no provider** (owner). The first and only transport is SMTP, which nearly every provider offers (Postmark, Amazon SES, Resend, Mailgun, a host's own server, Gmail). A provider-specific connection (an API, Cloudflare's) is a later registry like the AI providers', not this spec's.
2. **Settings live in the database, set in the wizard and in Settings** (owner). On `SiteSetting`: `mail_server`, `mail_port`, `mail_security` (`starttls` or `tls`), `mail_sender_name`, `mail_sender_address` in plain columns; `mail_username` and `mail_password` encrypted with Active Record encryption, as `ai_api_key` is (owner: "should these be encrypted?" — the username too, because for several providers it is a credential: Postmark's server token, SES's access key id). The login is written once and never shown again: "Set on 14 Oct 2026", Replace, Remove.
3. **The host's environment overrides, field by field** (owner). Variables `MAIL_SMTP_SERVER`, `MAIL_SMTP_PORT`, `MAIL_SMTP_SECURITY`, `MAIL_SMTP_USERNAME`, `MAIL_SMTP_PASSWORD`, `MAIL_SENDER_NAME`, `MAIL_SENDER_ADDRESS` (our names). A field set by the host is shown read-only as "Set by the host" and cannot be saved from the screen; every field from the host gives the card one line, "These settings come from the host's environment." One reader, `MailSettings` (a value in `app/values`), answers the effective settings and where each came from; nothing else reads those variables or the columns for delivery. A value is never logged, printed at boot or rendered (the password and username from the host are not shown either: "Set by the host").
4. **"Mail works" means: the effective settings are complete and a send succeeded with them** (owner: hidden "until mail works"). A test mail or any real mail that succeeds records `mail_verified_at`; a change to any delivery setting (server, port, security, login, sender address) clears it, so the state goes back to "Saved, not tested" and the reset link and invites hide until a test passes again (our call: "works" is about the settings as they are now; a typo fixed and not tested is not known to work). A change of the sender NAME alone does not clear it. In production a missing site address (`PUBLIC_HOST`) also means mail does not work, since no link could be built.
   **The host's variables count too** (our call): a variable changed at a deploy is a change no save sees, so verification is stored with a fingerprint of the effective delivery settings (`mail_verified_fingerprint`: an HMAC-SHA256, keyed by a key derived from the application's secret through `Rails.application.key_generator`, over server, port, security, username, password and sender address, from whichever source each comes) and `MailSettings#state` compares it on every read: settings that differ from the verified ones are "Saved, not tested". The HMAC is one-way and keyed, so the stored value says nothing of the password without the application's secret; it is never shown, logged or audited.
5. **A later failure does not hide anything** (owner; Claude Design M3). A real mail that fails records `mail_failed_at` and a short reason; the state reads "Last send failed …" until a send succeeds, and the reset link and invites stay. One outage must not lock people out of the link.
   **Retries and what is recorded** (our calls): a job retries a connection failure (refused, timeout, unknown host) three times with backoff and records the failure only after the last attempt; a refused login or a refused sender is not retried and is recorded at once. A job carries the fingerprint of the settings it was queued under (decision 4): a success marks the settings verified only when that fingerprint is the current one, so a mail queued under old settings never verifies new ones. The state columns (`mail_verified_at`, `mail_verified_fingerprint`, `mail_last_sent_at`, `mail_failed_at`, `mail_failure`) are written with `update_columns` and `# version: none (mail's state is not content)`, because any save of `SiteSetting` bumps the public content version (`site_setting.rb`, `reset_cached_state`) and a mail must not empty the site's caches.
6. **The two mails of this spec are the password reset and the invite**, plus the test mail. Notifications (a note mention) are later and the design leaves room: every mail is a template of keys, sent by a job, to one person, in a language that can follow that person (English now) (owner: "keep that in mind").
7. **Invites are in, and only when mail works** (owner: "yes when mail works"). Mailed with a one-time link valid 7 days (Claude Design M4). The roadmap's earlier idea of an invite as a link copied by hand, without mail (item 6), is dropped: the owner chose to hide invites until mail works. The roadmap's item is rewritten in this change.
8. **Single sign-on and passkeys are a separate project** (owner): added to the roadmap's "Security and accounts" in this change, with the note that "Forgot your password?" applies only to accounts that have a password.

## The states (Claude Design M3)

One method, `MailSettings#state`, answers one of four, shown on the card's header and as System status's row (which replaces today's "Outgoing mail" check), each a dot and a word:

| State | When | Words |
|---|---|---|
| Not set up | the effective settings are incomplete (server, port, sender address), or production has no site address | "Not set up. Password resets and invites are off." (production without an address: "Not set up: the site's address (PUBLIC_HOST) is missing, so no link can be mailed.") |
| Saved, not tested | complete, `mail_verified_at` empty | "Saved, not tested. Send a test mail to turn on resets and invites." |
| Working | verified, no failure since | "Working. Last mail sent 14 Oct, 09:12." |
| Last send failed | verified, and a failure later than the last success | "Last send failed 14 Oct, 09:12: could not reach the server." |

`MailSettings#ready?` (what shows the reset link and invites) is true for Working and Last send failed. System status adds "Open Mail settings →"; the dashboard shows an alert to holders of `settings.manage` (who can fix it) only while the last send failed.

## The setup wizard (Claude Design M1)

- A new optional step `mail` after `site` (`SetupController::STEPS`, `OPTIONAL_STEPS`).
- Title "Mail"; intro "Content Spiel sends two kinds of mail: password reset links and invites. Use the SMTP details from your mail provider."
- Fields in order: Server (placeholder "smtp.example.com"); Port (587 by default); Security, a segmented control STARTTLS / TLS (TLS sets the port to 465, STARTTLS to 587, unless a port was typed; STARTTLS is REQUIRED, never "if offered": with "if offered" someone on the network can strip the offer and read the login. A host's own relay without TLS is the one case for `none`, which only the host's variable `MAIL_SMTP_SECURITY=none` can choose, and only without a login; our call); Username; Password; Sender name (defaults to the site's name from the previous step); Sender address (placeholder "no-reply@yourdomain").
- "Send test mail" (secondary), meta "Sends to <the admin's address> (your address)", saves and sends; success "Test mail sent to <address>. Check your inbox."; failure in the warn alert, a sentence then the server's answer in mono (below). "Continue" (primary) and "Skip for now" (ghost).
- On the review step when skipped: "Mail: not set up. Password resets and invites stay off until mail works. Set it up later in Settings → Mail."

**A failure's sentence**, by what the SMTP exchange raised (our mapping of Claude Design's four): refused login (`Net::SMTPAuthenticationError`, a 535) "The server refused the login. Check username and password."; cannot connect (connection refused, timeout, unknown host) "Could not reach <server> on port <port>. Check server and port."; security mismatch (an SSL error, or STARTTLS refused) "The server expects a different security setting. Try STARTTLS with port 587, or TLS with port 465."; sender refused (a 550/553 on MAIL FROM) "The server refused the sender address."; anything else "The mail could not be sent." Then the server's one reply line, in mono, with the effective username and password replaced by "…" wherever they appear in it, before it is shown or stored (some servers echo the login, and for several providers the username is a credential). The stored reason on `mail_failure` is the sentence's key and that scrubbed line; System status (open to `system_status.view`) shows the sentence only, the Mail card (`settings.manage`) shows the line too (our calls).

## Settings → Mail (Claude Design M2)

- A new card after AI, for `settings.manage`.
- In the card's part of the main form, saved with the sticky save bar: server, port, security, sender name, sender address.
- Instant forms, as the AI key's: username and password together under "Login": each field with its own Save before it is set; afterwards "Set on 14 Oct 2026" with Replace and Remove.
- "Send test mail" at the card's foot, outside the save bar, the result in place under it; disabled with "Save your changes first" while the main form has unsaved changes. Sent to the person pressing it.
- A field from the host: a sunken read-only box with "Set by the host".

## Sign-in and the reset (Claude Design M5, M7)

- "Forgot your password?" on sign-in and on Your account shows only when `MailSettings#ready?`. Otherwise sign-in shows the meta line "Forgot your password? Ask the site's owner to reset it." and Your account shows nothing in its place.
- Only the request (`new`, `create`) depends on ready: otherwise it redirects to sign-in (our call; a bookmarked request page must not pretend to send). `edit`, `check` and `update` keep working whatever the state, so a person holding a valid link finishes even if an owner has just changed the settings. `create` finds only a user who can sign in (an invited row is no such user).
- The reset mail's link keeps the token in the fragment (hosting.md, "The reset link"), and the page keeps its shape, with three cases: valid (the form), expired or invalid ("This reset link has expired. Ask for a new one."), used (the same, since a used reset token is no longer valid; the reset page cannot tell them apart and says nothing that would).
- The reset token's life stays `has_secure_password`'s 15 minutes; the mail says minutes, not hours (Claude Design's "{hours}" becomes "{minutes}").

## Invites (Claude Design M4, M5)

- **Starting one:** "Invite person" beside "New user" on the Users screen, for `users.manage`, only when mail is ready; otherwise owners see the meta line "Invites need mail. Set up mail →". The dialog "Invite a person": Email (required), Name (optional), Groups (the existing checkbox list); "Send invite" and Cancel. Errors: "Someone with this address already has an account." and "This address is already invited." with a Resend link.
- **The invited person is a user row in an invited state**: no password, so no way to sign in by any path; counted nowhere a user who can sign in is counted (owner checks, "last owner" protection, presence, the dashboard's people); listed with the email as the name when none was given, a neutral pill "Invited" and "Invited 14 Oct · expires 21 Oct", or "Invite expired". How the row is shaped (columns on `users`, or an `invitations` table) is the builder's, under this rule.
- **The link** carries a token valid 7 days, signed over what a resend or a withdrawal changes, so the old link dies with either (`generates_token_for`); in the URL's fragment, as the reset token is.
- **Row menu:** "Resend invite" (new link, 7 more days) and "Withdraw invite" (confirm: "Withdraw the invite to <email>? The link stops working."), which deletes the invited row.
- **The invited person's page:** "Welcome to <site name>", "Set a password to finish your account for <email>" (read-only), Name (prefilled), Password, Confirm, "Set password and sign in". Afterwards signed in on the dashboard with "Your account is ready." Expired, withdrawn or invalid: "This invite has expired. Ask the person who invited you to send a new one." (one answer, so the page does not say whether an invite existed). Used: "This invite has already been used." with a "Sign in" link.
- **Services:** `Users::Invite`, `Users::ResendInvite`, `Users::WithdrawInvite`, `Users::AcceptInvite`, each an `ApplicationService` with `authorize!` and `record_event` (the accept as the invited user), in `EXPECTED_SERVICES` with factories. Audit actions `user.invited`, `user.invite_resent`, `user.invite_withdrawn`, `user.invite_accepted`, placed in `Editing::Signals::SILENT` and `Audit::Sentence` like every action.
- **Rate limits:** sending invites and test mails as the reset request is limited (our figures: 10 invites and 5 test mails per person per 3 minutes).

## The mails (Claude Design M6)

- A plain-text part and a simple HTML part: one column up to 560px, system fonts, the site's name as text at the top, the link as one button and the full URL in plain text under it, no tracking pixel or rewritten link. From: the effective sender name and address.
- Every line a key under `mail.` in `config/locales/mail.en.yml`, with `%{site}`, `%{inviter}`, `%{minutes}`, `%{date}`; read in the recipient's language when one exists (English now).
- Reset: "Reset your password for %{site}"; "Someone asked to reset the password for your account on %{site}. Use this link within %{minutes} minutes:" [Reset password]; "If this wasn't you, ignore this mail. Your password stays the same."
- Invite: "%{inviter} invited you to %{site}"; "%{inviter} invited you to work on %{site} in Content Spiel. Set a password to finish your account:" [Set password]; "This link works until %{date}. If you weren't expecting this, ignore this mail."
- Test: "Test mail from %{site}"; "Mail from Content Spiel works."
- Footer: "Sent by %{site} via Content Spiel".
- Sent by a job (`deliver_later` on Solid Queue) with retries for a connection failure; the test mail is sent at once (`deliver_now`) because its answer is the point.

## Development and test

The states and `ready?` are the same in every environment. Where no server is set, development and test keep Rails' own delivery method as the stand-in for SMTP (`:test` in test, `:file` into `tmp/mails` in development, our call) and a send through it counts as a send that succeeded, so in development "Send test mail" once turns resets and invites on without a real provider. Tests that need a state set it through a helper, and tests of the SMTP exchange itself use a local SMTP stub, never the network. Development keeps taking a link's origin from the request when no site address is set (`PasswordsMailer.request_origin_used?`).

## Security rules

- The login never reaches a page, a log line, an audit snapshot or a job's arguments: `mail_username` and `mail_password` join `Audit::Snapshot::NEVER_STORED` and `filter_parameters`; the audit records "Mail login" as "set"/"not set", as "AI key" is; a job is handed a record's id, never settings.
- No credential in a URL: the invite token travels in the fragment like the reset token, and the accept form posts it in the body.
- **Without encryption keys** a save of the login, and of the AI key, answers a sentence, never a 500: "This site has no encryption keys, so a password can't be stored. See Hosting: encryption keys." (roadmap: the same part gives a sentence to whatever needs the keys).
- At `RAILS_LOG_LEVEL=debug` Action Mailer logs a whole mail, link included; production's boot warning about debug (hosting.md) names invite links too.

## What this does not do

- Notifications, per-person mail preferences, a mail's language per person (the keys allow it).
- A provider API, OAuth to a provider, DKIM or SPF set-up (the provider's and the domain's, said in the guide).
- Single sign-on, passkeys (roadmap entry).
- A bounce or complaint feed; a mail log screen.
- A logo in the mail.

## Risks

- **Two sources of a setting** (the host and the database): `MailSettings` is the only reader, and its test covers each field from each source.
- **A link-rewriting gateway** (some providers' click tracking) may drop the `#` fragment of the reset and invite links (roadmap known gap): the guide tells an owner to switch click tracking off.
- **An invited row is a user row that cannot sign in**: every query that counts or lists people who can sign in must leave it out; the guard is a test per such place named in the plan.

## Testing

- `MailSettings`: each field from the database and from the host, the four states with their edges (sender name change keeps verified; any delivery field clears it; production without an address is Not set up), `ready?`.
- Delivery: an SMTP server stub (a local test server, not the network) for success and each of the four failures and their sentences; a failure records `mail_failed_at` without hiding anything.
- Settings and the wizard: fields, the instant login forms, "Set by the host", the test button's disabled state, the review step's line; the sentence without encryption keys (and the AI key's, which today is a 500).
- Sign-in and Your account with and without ready mail; the request route redirecting when not ready.
- Invites: the four services (rights, audit, rate limit), the token's 7 days and its death on resend and withdrawal, the invited row in no count of people who can sign in, the accept page's four answers; browser tests for inviting, accepting and signing in, and the dialog's errors.
- The mails: subjects and bodies from keys, both parts, the link in the fragment, no credential in any log line of a send.

## Documentation

In `contentspiel-docs`: administrators' setup and Settings pages (Mail), hosting's variables (the seven `MAIL_*`), the users page (invites), the sign-in and reset pages for editors, and "When things go wrong" (mail failures, click tracking).

## As built
