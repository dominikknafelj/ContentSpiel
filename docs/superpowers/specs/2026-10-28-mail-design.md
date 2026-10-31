# Mail

Status: built (2026-10-30; "As built" at the end). Approved by the owner 2026-10-28. The owner's decisions are from the brainstorm of 2026-10-28; the screens and words are Claude Design's (`.superpowers/design-answers/2026-10-28-mail.md`, M1–M7). Calls marked "(our call)" are this spec's.

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

Built on the branch `mail-delivery`, 2026-10-28 to 2026-10-30, in ten tasks (`docs/superpowers/plans/2026-10-28-mail.md`). The reference is `docs/reference/mail.md`; the rules a change can break are in `CLAUDE.md`, guarded by `test/lib/mail_guards_test.rb` among others. Every ruling made while planning and building, with its reason:

**Planning**

1. **The stand-in counts as a server in development and test.** "Not set up" needs a server, and "Development and test" wants "Send test mail" to turn resets on without a provider: `MailSettings#complete?` asks for a server only where there is no stand-in (production). Both sentences of the spec hold. The wizard's review says "not set up" by "no server was given", not by `ready?`, for the same reason.
2. **An invitation is not a user** (as finally built; see "The switch", below). It is a row of `invitations` (the address normalised as a user's, the name, the inviter, `sent_at`, `accepted_at`, the account it made), its groups a join table `invitation_groups`, one open invitation per address by a partial unique index; accepting it creates the user. "No password" in the spec is therefore "no account": nobody can sign in as an invitation by any path, because it is no user. (The first build made it a `users` row with `invited_at` set and the digest of a random password nobody was told, and asked `User.can_sign_in` in every place that counted or listed people.)
3. **The invitation's token is `Invitation`'s `generates_token_for(:accept, expires_in: 7.days) { [ sent_at, email_address ] }`** (the address since F1, below). Accepting sets `accepted_at` and keeps the row and both values, so a used link still finds its row and the page can say "already been used"; a resend moves `sent_at`; a withdrawal deletes the row. That gives the spec's four answers. (The first build signed `users.invite_sent_at`, and accepting cleared `invited_at`.)
4. **One reference file**, `docs/reference/mail.md`, with an index line in `CLAUDE.md`, not a section of `hosting.md`: mail is a domain with its own rules.
- P1. A minimal `InvitationsController#show` came with the route before the page was built, because a route to a missing class fails Zeitwerk and the routes test.
- P2. **One test-mail limit** for Settings and the wizard, `MailTestLimit` (5 per person per 3 minutes): the spec's figure is per person, not per screen. Rails keys `rate_limit` by the controller's path unless given a `scope:`, so the concern gives both `name:` and `scope:`; in the test environment, whose cache is a `NullStore` in which nothing trips, it counts in a memory store of its own.
- P3. The failed-send notice is drawn at the top of the dashboard (`Admin::Ui::MailFailedNoticeComponent`), for `settings.manage`, because the spec says "the dashboard shows an alert".

**Building**

- T2a. **`none` is plain SMTP**: `smtp_options` states all three of the mail gem's STARTTLS switches for every security, because the gem otherwise uses STARTTLS "if offered", which made `none` upgrade whenever a server offered it (seen on the wire by the stub test). `starttls` is STARTTLS required, refused before the login when it is not offered.
- T2b. **Only a failed delivery is a mail failure**: errors raised by the SMTP exchange (marked by `ApplicationMailer::SmtpDelivery`) are recorded; an error raised before delivery (job deserialization, a template, a mailer's code) is a bug, raised on as Active Job does and recorded as nothing. The first build's catch-all recorded everything and blamed the provider for a template error. With it, an SSL error is `security` only during the handshake: a server that hangs up mid-mail on TLS raises one too, and that is `other`.
- The test environment never dials a server that is not this machine (`config.x.mail.smtp_loopback_only`): `with_mail_state(:working)` with `smtp.example.test` delivers to `:test`, and the exchange is tested against a local stub (`SmtpStub`). Action Mailer logs a failed delivery's message at info, so the login is scrubbed from the error itself, not only from the stored line (found by the log test); a telemetry test reads the spans for the same.
- T3a. **The invitation's token is made in the mailer** (`InvitesMailer.invite(invitation, origin:)`; the inviter is read from the invitation), never passed in as the plan had it: a job's arguments are written to the queue's row and Active Job's log, and the spec's security rule outranks the plan. `Invitation::VALID_FOR` is on the model, which a mailer may read and not the other way round.
- T3b. **The accept page is under the admin path** (`<ADMIN_PATH>/invitation`), like the reset page: at the root it would have shadowed a page with the slug `invitation`, since the public router takes every other path as a page's address.
- T4a. **A quote in the sender name is allowed**; control characters, a line break among them, are refused. The mail gem quotes and escapes a display name, so a quote cannot break the From header, and "O'Brien" or "\"Nordlicht\" Studio" must work. (Review Focus 2 had expected a quote to be refused.)
- The AI key's and the mail login's instant forms share one concern, `Admin::CarriedBase` (the write, the carried base, the end of every answer), rather than two copies that had already drifted. The login is one "Save login" for both fields, since there is one `mail_login_saved_at` (M2 said a Save each). Without encryption keys `Settings::Save` answers the sentence for both and rolls the whole call back.
- The test mail is shared by the two screens through `MailTestSending` and `MailTestOutcomeComponent`; the wizard's success redirects back to the step, because Turbo refuses a 200 answer to a form (a real bug of the first build).
- T6a. **The console password command stays on System status's Mail row while mail is not ready** (Not set up, Saved not tested), copyable, as the old "Outgoing mail" row carried it; once mail works the reset link replaces it. The first build moved it to the documentation only, which left a sole owner with no mail and a forgotten password no path from any screen; M7 rules the console out of the SIGN-IN page only.
- T8a. **An invitation withdrawn before its mail went out** is an ordinary event: the job's one record, the invitation, cannot be found, and the job ends quietly with one line that names no address, and records nothing (under T2b a deserialization error would otherwise fail loudly). Any other mail whose record is gone still fails; an invitation whose inviter is gone is sent in the site's name (the reference is nulled, and the inviter is no argument of the job).
- Invite and Resend queue the mail after the outermost commit (`ActiveRecord.after_all_transactions_commit`; the application does not enqueue after commit by itself). Resend is refused while mail is not ready too (a resend whose mail cannot go would only kill the working link), with "Invites need mail.", and a resend or withdrawal of an invitation that is no longer open with "There is no open invite for this person." (the screen's routes find only an open one, so there it is a 404). `Invitations::Accept` answers its link refusals as symbols (`:expired`, `:used`) and the page words them; "used" also answers an invitation whose address has had an account made for it since, so accepting never makes a second account. (The first build's rule that `Users::Save` never made an invited row an owner went with the switch: an invitation is no row an owner flag can be set on.)
- The reset request (`new`, `create`) redirects to sign-in unless mail is ready; a lapsed link met then lands on sign-in with "This reset link has expired. Ask the site's owner to reset your password." (a sentence the spec did not have).
- T9a. **Accepting an invitation ends the browser's existing session first**, so a credential page leaves no stranger's session alive; **Resend counts in the invites' bucket** (ten per person per three minutes), so a holder of `users.manage` cannot mail one address without limit. The accept page's check answers 200 with the address and name (the page says "for <email>"), 409 for used and 410 for everything else; its script, `invitation-token`, extends `reset-token`'s class instead of copying it.
- Task 10's guard (`test/lib/mail_guards_test.rb`, "every User query in a sign-in path names can_sign_in") found the reset token's lookup (`Admin::PasswordsController#user_for_token`) reading every user: a reset token of an invited row, which only something outside the app could make, would have set a password on a row whose invite was open. That it took a guard over ten files to find one is part of why the switch, below, was made; with it the lookup reads every user again, and rightly: every user is someone who can sign in.

**After the final review**

- F0. **The wizard showed the host's login.** Its Mail step had hand-written its own "Set by the host" box, which printed the value; for the host's `MAIL_SMTP_USERNAME` and `MAIL_SMTP_PASSWORD` that was the credential in the page. A login half the host sets is now the card's mask in both screens (`MailLoginComponent.secret?`, `MASK`), and its value is never read by the view.
- F1. **The invitation's token is signed over `[sent_at, email_address]`.** In the first build the Users editor could correct an invited row's address; signed over the time alone, the link mailed to the wrong address kept working for seven days on the corrected account. Since the switch an invitation has no editor (a typo'd one is withdrawn and sent again), and the address stays in the token, so a change of the row's address by any path kills the old link. Accepting changes neither, so "already used" still works; a resend's link works.
- F2. **The sender address must be exactly one plain address, from either source.** A host's `MAIL_SENDER_ADDRESS=no-reply@` was never validated and made the mail gem raise while building the From: a 500 on "Send test mail" and every job a failure. `complete?` asks `MailSettings.one_address?` (the column's rule) of the effective value; a malformed one is "Not set up" with a sentence that names the host's variable or the field (`not_set_up_key`), on the card, System status and the test mail's answer, and `sender` answers nil instead of raising.
- F3. **The host's `MAIL_SMTP_SECURITY` is read whatever its case** (`TLS`, `STARTTLS`, `None`); before, a capital made the settings "Not set up" with no reason.

**The switch: an invitation is not a user (the owner's choice of 2026-10-30)**

The branch was first built with the invited person as a `users` row that could not sign in (Rulings 2 and 3 as first written). That made ten existing places learn `User.can_sign_in` (sign-in, the reset request and the reset token, mention suggestions, notes' deliveries and their mention check, the group member picker, the audit log's people filter, the last-owner protection in the model and on the editor, and a group's member list), each with a test, behind a guard over those files; it made a "stuck invited owner" possible (an owner row nobody could sign in to, counted by the owner rules until `other_owner_remains?` learnt to skip it); and it left a permanent rule that every future query of people had to remember. The owner chose the clean solution before the branch merged: an invitation lives in its own table and accepting it creates the user, so no user query knows invitations exist. The branch's own migration was replaced rather than reversed (`CreateInvitations`, under a version of its own, 20261031090000, so a database that ran the replaced one runs it), the ten places are back to what they were on `main` (the reset request keeps the mail gating of Task 7), `User.can_sign_in`, `User#invited?`, `INVITE_VALID_FOR` and the owner refusal for invited rows are gone, the services are `Invitations::Invite`, `Resend`, `Withdraw` and `Accept`, and the audit actions are `invitation.created`, `invitation.resent`, `invitation.withdrawn` and `invitation.accepted` (the last on the new user). The guard is the other way round now: nothing outside the invitation side names `Invitation` (`test/lib/mail_guards_test.rb`). An invitation is a member of nothing until it is accepted, so a group's screen says nothing about invitations, and the Users list shows the open ones among the users. The rework's review added three: an account made for an invited address closes its open invitation, heard from the audit log's after-commit notification (`Invitations::Accounts`), because an account made on New user and deleted later had brought the old link back to life; accepting records `session.created` as sign-in does; and the mailer sends nothing for an invitation that is no longer open.

**Departures and what is left.** The words the spec did not give (the failed state's short reasons, the validation sentences, the toasts, the dialog's help line, the remove dialog, the review's line, the no-JavaScript line, "Invites need mail.") were the plainest choice and are listed in the pull request as design questions; so are the card's state under its title (M3 had it on the header's right), and the mail's look. (The first build's "Invited" mark on a group's member chips went with the switch: an invitation is a member of nothing.) What a person would meet of the parked minors is under "Mail" in `docs/roadmap.md`'s known gaps, with the link-rewriting gateway and a mail's language per person.
