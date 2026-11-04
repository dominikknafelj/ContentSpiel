# Forms

Decided with the owner, 2026-11-03. Roadmap "Next", item 4: "Forms, with mail delivery". Where this says "implementer's call", the owner has not decided it and may overrule it.

Status: built (2026-11-04, branch `forms`; "As built" at the end). The reference is `docs/reference/forms.md`.

## Why

Most sites need a contact or enquiry form, and ContentSpiel's public site cannot take a single answer from a visitor. The owner wants editors to build forms themselves, choose where a submission goes, and keep submissions in CS Studio, with a way out to a CRM later.

## What the owner decided

1. **A form builder in CS Studio.** Editors make a form, add, order and remove its fields, with no code.
2. **The editor sets the target:** the addresses a form's submissions are mailed to.
3. **Submissions are kept,** and keeping is optional per form, with a setting for how long.
4. **Basic, but extendable.** A small set of field types now, new ones through a registry later.
5. **Destinations.** A submission goes to one or more destinations. Mail and keep are built in. A CRM is a later destination that a gem adds.
6. **A form is its own record,** reusable on several pages through a Form block, with its submissions in one place.

The owner, 2026-11-03, on the builder check's four questions ("I follow your recs"):

7. **Errors and thank-you without JavaScript.** Required, email and choice are also browser validation attributes, so most mistakes are caught before a send. With JavaScript, errors and the thank-you appear in place. Without JavaScript, a server-side error and the thank-you are a plain CMS page, not the theme's, with a link back to the page. No third controller draws a theme, and the public pages' rules are untouched.
8. **No translation tracking at first.** A form's texts are translated fields that fall back to the default language. They do not join `translation_states`, the Translations matrix or AI translation; that may come later.
9. **Submission answers are encrypted at rest.** Without Active Record encryption keys a site can only mail submissions: keeping is not offered, with the reason on the form's screen and as a row of System status.
10. **The rights are site-wide.** **View form submissions**: read them and send a failed destination again. **Manage forms**: build and change forms, and delete submissions. No per-form scope yet. Placing a Form block needs only the existing right to edit the page, and its picker lists every form by name.

## Goals

- An editor can build a contact form, put it on a page, and receive submissions by mail and in CS Studio within minutes.
- A visitor can send a form with or without JavaScript, in the page's language, with clear errors and a thank-you message (decision 7 for how).
- Spam is stopped well enough for a small site with no third-party captcha.
- Personal data is handled correctly by default: kept only where the form says, deleted on time, deletable sooner, readable only with a right.
- A gem can add a field type and a destination without touching core.

## Non-goals

File uploads, multi-step forms, conditional fields, payment, a CRM integration itself, a visual drag-and-drop canvas, export (a later item), analytics, and forms on CS Studio's own screens.

## Anti-goals

- A submission lost because a mail or a destination failed.
- A public page that becomes uncacheable, carries a cookie or a session, or lets a theme's template post anywhere: the public site's wall stays as it is (`PublicController`, `docs/reference/theming.md`).
- A form that silently stops mailing when mail is not set up.
- Personal data in a log line, a span, an audit event or a URL.

## What is built

### The form

A `Form` record, managed on a new **Forms** screen in CS Studio. It holds:

- **Name:** for editors, not shown to visitors.
- **Fields,** ordered.
- **Submit label** and **thank-you message,** both translated.
- **Destinations,** below.
- **Keep submissions:** on or off. If on, a **keeping time** in days, defaulting to a site-wide value in Settings (implementer's call: 90 days).

A form is a content-like record, written through `ApplicationService`s that authorize and audit, as every write is. Whether it is trashable and whether it has drafts and publishing like a page is the implementer's call. The suggestion is: trashable as pages and posts are; no drafts, since a form's fields are what a visitor sends and a half-built form is not shown until it is placed. Say what was chosen and why.

### Fields

Each field has a **type,** a **label,** **required or not,** an optional **help line,** and the type's own options (a choice list's choices). The label, help line and choices are translated. The stored key of a field is stable when the label changes or the field is reordered.

Labels, help lines and choices follow decision 8 for translation.

Field types to start: **short text, email, long text, choice** (a dropdown or radio buttons, one value), **checkbox** (one box: also a consent box).

Field types are a registry, like block types. A type says how it renders on the public page, how a value is cleaned and validated, and how it shows in a submission. A gem can register a type through `ContentSpiel::Plugins`, the way outside block types are added. Whether this reuses `ContentModel::FieldTypes` or is a registry of its own is the implementer's call, with the reason. The roadmap's admin-defined content types (#114) are to reuse it later, so it does not assume a form.

### Placing it

A **Form block** names one form and draws it. A theme can replace its template like any block's, and the contract gets the block's names with a release note. One form may be placed on many pages. A trashed or missing form draws nothing on the public page.

### Sending

- The form posts to **its own endpoint,** not to the page. Public pages stay cookie-free, token-free and cacheable. That endpoint is not a `PublicController`, is never cached, answers in the visitor's language and answers as decision 7 says: in place with JavaScript, otherwise with a plain CMS page for the thank-you or the errors, linking back. The page itself is never answered differently for a visitor, so its ETag and caching are unchanged.
- **No CSRF token and no session cookie:** a public page cannot carry either. The protection against a forged submission is that a submission can do nothing but be a submission, plus the spam measures below. Write this down in the reference, as the reason, for review.
- **Spam measures,** with no third-party captcha: a hidden honeypot field; a minimum time between the page being drawn and the send, carried in the form and signed so it cannot be faked; and a rate limit per visitor and per form. A send that trips one is answered as a success and stored nowhere.
- **Validation:** required fields, an email that is one address, a choice that is one of the choices, length limits. Errors are shown beside the fields, the typed values kept.

### Destinations

A destination is a registry entry: a name, its settings (stored per form, secrets encrypted and never shown again, as the mail login is), and a job that delivers one submission.

- **Mail:** to the form's recipients, through `ApplicationMailer.queue` and `MailSettings` (`docs/reference/mail.md`). One mail per submission, listing the fields with their labels. The reply-to is the visitor's email field if the form has one. While mail is not ready, the form's screen says so, and a submission is kept, or warned about if keeping is off.
- **Keep:** the submission is stored, with its time, its language, the page it came from and its answers, and nothing about the visitor beyond what they typed. The answers are encrypted (decision 9); the list's summary is built so it needs no unencrypted copy of them, or is encrypted too.
- **Later, by a gem:** a CRM or a webhook. Core provides the seam: register, configure per form, deliver in a job.

Each destination runs as a background job with retries. The submission records each destination's result: sent, failed with a reason scrubbed of secrets, waiting. In CS Studio a failed one can be sent again. A visitor never waits for a destination.

If keeping is off and every destination fails, the submission is lost. So the form's screen warns when keeping is off. The implementer may keep such a submission until its destinations succeed, then delete it, and should say if that is what was built.

### Submissions

- A list per form on the Forms screen: newest first, with time, language, page and a summary. One submission opens whole, with its destinations' results.
- Rights as decision 10 says, both new permissions held by the Admin group by default and grantable as rights are today (`docs/reference/users-groups-tokens.md`).
- **Delete:** one or all of a form's submissions, with Manage forms, audited without the content.
- **Kept for the form's keeping time,** then deleted by a recurring job, as the trash's retention is. Changing the time applies to existing submissions too.
- **Never in a log, a span, an audit event or a URL:** the answers. Audit records that a submission arrived or was deleted, by id and form, not its content. Filter the parameters.

### Settings

A **Forms** card or a line in Settings for the default keeping time, implementer's call where.

## Constraints

- Every rule in `CLAUDE.md` and its reference files holds. In particular: services authorize and audit; derived rows are refreshed in their write's transaction; a trashed record is hidden at each narrowing point; nothing public reads a published record's rows; the public site commits no session and lets no cookie leave; telemetry carries no query string. A rule that this work must bend is named in the spec's "As built", with its reason and its new guard.
- New admin strings are keys. Public strings a visitor reads that no editor typed are keys in `config/locales/public.en.yml`.
- Accessibility: every field has a real label; required is said in words, not only by colour; errors are announced and linked to their fields; the honeypot is hidden from people and from screen readers.
- No colour literals; the Form block's tokens are declared and measured like the Note block's.
- Generic fixtures only. Nothing of any client site.

## Design questions, for the Design System

The Forms screen and the builder's layout; how a field is added, reordered and edited; the submissions list and a submission; the Form block's public look in the default theme, its error and thank-you states. The build uses placeholders where an answer is missing, and lists them.

## Documentation

Guide: a new page for editors, "Collect answers with a form"; site settings; users and groups for the two rights; the theme contract and rendering pages for the Form block; a page for integrators on adding a field type and a destination from a gem.

## Left to the builder

Table and column names; whether the field registry is shared; trash and drafts for forms, with the suggestion above; where the keeping-time default lives; the minimum send time and the rate limit's numbers; and the exact failure handling with keeping off, all recorded in the spec's "As built".

## As built

Built by `docs/superpowers/plans/2026-11-03-forms.md` in ten tasks on the branch `forms` (the tenth, the guide, in `contentspiel-docs`). The reference is `docs/reference/forms.md`, with the Form block in `docs/reference/content-blocks-and-types.md` ("The Form block", "Field types", "Form field types and destinations from outside") and `docs/reference/theming.md` ("The Form block"), and the rest in the reference file of each part it touched (access control and audit, users and groups, mail, trash, settings, hosting). The looks are the design lead's (`.superpowers/sdd/2026-11-03-forms/design.md`, delegated by the owner on 2026-11-04), each recorded for the owner to overrule. Where the code differs from this spec or the plan it is below, with what the departure costs if it is wrong.

### The owner's two rulings on the plan (2026-11-04)

1. **A rate limit is said to the visitor.** The spec's "a send that trips one is answered as a success" holds for the honeypot and the minimum time; a rate limit is a 429 with "Too many messages. Please try again in a few minutes." (`public.forms.rate_limited`), as JSON `rate_limited` to the script and as a plain page without it, and nothing is stored. Why: a person who is refused must be told, or they think their message went. Cost if wrong: a bot learns it hit a limit, which tells it nothing it can use.
2. **No keys, no answers.** Without Active Record encryption keys a form takes no answers at all: no sealed copy in a mail job (the plan's `Forms::Transit` was not built), no answers in any job's arguments. `Forms::Submit`'s `UNAVAILABLE` means "this site has no encryption keys"; the form is drawn with "This form can't take answers at the moment. Please try again later." and its fields disabled, the builder says why, and System status's Forms row says "This site has no encryption keys, so its forms can't take answers." **This bends spec decision 9** ("without keys a site can only mail submissions"), named here as the bent rule; its guards are `test/services/forms/submit_test.rb` ("without encryption keys the send is UNAVAILABLE, and nothing is written or queued"), `test/integration/form_sends_test.rb` ("no keys and mail not ready is a 503 that says try again later, and writes nothing", run with mail working too), `test/components/blocks/form_component_test.rb` ("without encryption keys the form says it can't take answers, and nothing in it can be typed or sent") and `test/integration/public_form_block_test.rb` ("the page's ETag follows the site's encryption keys, which decide whether the form takes answers"). Cost if wrong: a site without keys gets no contact form until it sets them, where it would have had mail only.

### The decisions the spec left to the builder (the plan's 1 to 13), as built

1. **Tables and columns**: `forms`, `form_destinations`, `form_submissions`, `form_deliveries` and `site_settings.form_keep_days` (90), as the plan named them, with three changes: `form_destinations.secrets` is text holding a JSON object of separately sealed values (each secret encrypted on its own with Active Record encryption, so a secret is replaced without decrypting the others and `secret_set?` needs no key), not one encrypted column; `form_deliveries` gained `queued_fingerprint` (ruling R9, below) and a check constraint on `state`; `secrets_saved_at` is one time per destination, when any secret was last written. Why: a field list saved whole by one Save needs no row per field, and a destination and a delivery have their own secrets and state.
2. **Field types reuse `ContentModel::FieldTypes` for what a value is**, with a thin form registry (`Forms::FieldTypes`) for what a visitor's form adds: as planned. `:email` and `:form` joined the content model's types and `:text` learnt `max:`; `Forms::FieldType` gained `unsent:` (what a value is when the browser sends nothing: a checkbox's `false`), so nothing names a type to read an unticked box. #114's admin-defined fields can take the value half as it is.
3. **Trashable, no drafts**: as planned. A form's change is live at its explicit Save; moving, restoring and purging go through the trash services; purging needs `trash.empty` alone (its submissions are personal data); forms joined `Trash.roots` (after posts, before images) with the Trash screen's Forms tab.
4. **The default keeping time is `site_settings.form_keep_days`, in a Forms card of Settings** (`#forms`, after Publishing), saved by `Settings::Save`, 1 to 3,650; a form with no days of its own follows it at every run of the clean-up.
5. **Spam numbers**: 3 seconds' minimum (`Forms::Drawn::MIN_SECONDS`); 5 sends per visitor in 10 minutes across all forms and 30 per form in 10 minutes (`Forms::SendLimit`); the visitor counted by an HMAC of the address, an IPv6 address cut to its /64 first (one household is handed a /64). The plan's "during a flood a real send is answered as a success" is overruled by ruling 1: it is the 429. Every request counts toward the limit, spam trips and refusals included (Rails' `rate_limit` counts before the action). The limit trusts `request.remote_ip`: behind a CDN its ranges go in `config.action_dispatch.trusted_proxies` (`docs/reference/hosting.md`, "Forms"), with no guard.
6. **Failure handling with keeping off**: with keys every submission is a row, deleted once every delivery is sent (`delivered`), or after `Forms::UNDELIVERED_DAYS` (30) with a failed one (`undelivered`), listed meanwhile as not delivered with Send again. Two changes from the plan: the no-keys half (the sealed mail, a lost mail logged by id) is gone with ruling 2; and mail is tried whenever it is set up (`MailSettings#complete?`, ruling R18), not only while it is ready, so settings saved and never tested are tried and a success verifies them, and `not_ready` means only "mail is not set up". Two jobs finishing at once may both see the other still waiting; the later one decides from the locked submission row, and the daily sweep, under the same lock, is the backstop.
7. **The list's summary is computed, never stored**: `Forms::Summary.of`, the first two answers whose type says `summary` (short text, email), blanks skipped, " · ", 80 characters; an unreadable row reads "Can't be read" and can be deleted.
8. **A visitor's write is a service that authorizes, with one new actor: the bent rule.** `AccessControl::VISITOR` is allowed exactly `forms.submit` on `:public`; `forms.submit` is `grantable: false` (`Permissions.register` learnt `grantable:`, and the matrix, the seeds, `Grant` and `can_grant?` read `Permissions.grantable`). Built stricter than planned: the visitor is ONE instance (`Visitor::ONE`; `new` and `[]` private; the checker and the audit log ask for that instance by `equal?`, `Visitor.one?`; `Audit.record` used `is_a?` until the final review, and now raises on a copy rather than write it as anybody), so a copy is no visitor. What bends, "a nil or unknown actor on `:public` is denied everything", becomes "everything but `forms.submit` for the visitor". Guards: `test/models/access_control/visitor_test.rb` (every registered key on every channel) and `test/lib/visitor_actor_test.rb` (only `FormSendsController` and `Forms::Submit`'s tests name it; nothing constructs a second). The visitor's event has no actor row, `actor_label` "visitor", channel `public`, no IP, and never coalesces. An owner still passes `forms.submit` (owners pass every key); only the endpoint calls `Forms::Submit`.
9. **Content version**: `Forms::Save` and the three trash services on a form move it in their transaction; a submission and a delivery never do. A save that changes only a form's destinations (or writes a secret) touches the form, so the builder's stale base moves, and moves no content version, since a placed form draws nothing of its destinations.
10. **The signed draw time, without a session**: as planned, no expiry. A page served from a cache (a 304, a CDN) hands an older token, which only makes a send look slower; the ETag does not name the token and is right without it.
11. **The mail destination delivers inside `Forms::DeliveryJob`, through `ApplicationMailer.deliver_in_job`**: as planned, with `fingerprint:` added (R9) so a success verifies the settings only under the fingerprint the delivery was queued with.
12. **The endpoint answers JSON to its script and a plain page otherwise**, as planned, except the layout: the plain pages use `layouts/form_send`, a small layout of their own (the visitor's `lang`, `shared/theme_head`, no CSRF tag, no import map, no wordmark, no sign-in link; design.md 5.1, ruling R14), not `product`, which prints a CSRF token, loads the admin import map and hard-codes English. **`PublicController`'s cookie wall moved, word for word with its comments, into the concern `Cookieless`** (`app/controllers/concerns/cookieless.rb`), which `PublicController` and `FormSendsController` both include first; the spec's anti-goal "the public site's wall stays as it is (`PublicController`)" holds as behaviour, and the rule's text now names the concern (`docs/reference/theming.md`, `CLAUDE.md`). The route has `format: false`, the public routes' rule.
13. **The model is `Forms::Form`, not `Form`** (table `forms`): as planned.

**The non-service write.** A delivery's state (`Forms::Delivery#record_attempt!`, `#record_sent!`, `#record_failed!`, `#resend!`) is written outside a service, one statement each with `# version: none`, from `Forms::DeliveryJob` and `Forms::Resend`, because it is a job's state, as mail's state columns are, nobody asks for it by name, and auditing every attempt would bury the log; Send again and a delete are services that audit. It is listed with the other exceptions in `docs/reference/access-control-and-audit.md` ("Services") and in `CLAUDE.md`; `test/lib/version_bump_test.rb` holds the mark, and no guard keeps another caller from writing it.

### Rulings taken while building, where they changed behaviour

- **R3**: the Form block draws the "can't take answers" line through a theme method of its own, `unavailable` (so the template is promised thirteen names, not twelve), and the page's ETag holds `Forms::Encryption.available?`. Cost: one ETag key.
- **R5**: a submission's stored labels and displays (a checkbox's Yes or No, a choice's label) are the site's default language, whatever the visitor's: editors read them. Cost: a reader in another language reads the default's words.
- **R10**: the `page_id` a send names is believed only for a live page whose published copy places the form; otherwise no page is stored and the link back goes home.
- **R16**: a network failure says so ("Your answers couldn't be sent. Please check your connection and try again.") and keeps the typed answers; the script never makes the browser send the form itself (the plan had it fall back to a browser send, which loses the answers when the network is what failed). So `string` answers six words, with `network`.
- **R18**: form mail is tried whenever mail is set up, not only while it is ready (decision 6 above).
- **The retention sweep decides from the stored `keep_submissions` and its days, never `Form#keeps?`**, which is also false without keys: deleting kept submissions because the keys went is irreversible. Cost if wrong: rows kept a day longer than needed.
- **Send again is hidden for `no_destination` and `unknown_destination`**: such a resend can only fail again until the form changes. Cost if wrong: a button re-added.
- **"A page that's gone" was removed** from the submissions: `page_id` nullifies when a page is purged, so such a submission reads "—", as one that stored no page. Telling them apart needs a column of its own.
- **A spam trip answers "sent" even for a trashed form or a site without keys**: a bot learns nothing either way.
- **A send from `/preview` is a real submission**: an editor testing a form expects it to work, and the endpoint cannot tell; a draft page stores no page (R10). The guide says so.
- **Same-page anchors go native, site-wide** (`site.js`, a `turbo:click` listener): Turbo 8 (turbo-rails 2.0.23) refetches and redraws the page for a link to an anchor of the same page, which wiped the form's thank-you or errors; now such a link is the browser's on every public page, and another page or another query is still a visit. The Code block's browser test was rewritten for it. Cost if wrong: one listener to revert.
- **`string(:error_summary)` without `count:` raises in development and test and is empty, logged once, in production** (as an unknown key is: no public 500 from a theme's mistake). The guard is shared with the Code block's, `Blocks::FixedWords`.
- **The form's script takes back what it wrote at connect (to a copy Turbo shows again) and at disconnect, never at `turbo:before-cache`**, which Turbo also fires for a page that is not left (code-copy's incident, met again).
- **JSON errors carry `item`**, the summary link's words, so the script holds no words.
- **The five inputs were rewritten to call only `field`, `value` and `error`**, the names their contract lines promise; the label markup repeated in each is accepted as the price of each being a contract component.
- **The plain pages keep the CMS's `cs-` tokens** (decision 7: the plain page is the CMS's, never the theme's), measured in `test/lib/admin_contrast_test.rb`.
- **Two names for one trip**: `Forms::Drawn.check` answers `:invalid` and `Forms::SpamCheck` `:invalid_token` (internal only).
- **The audit action for a delete is `form_submissions.deleted`** (plural, as the plan's interface had it).
- **The answers' log filter is a lambda scoped to the controller `form_sends`**, not a bare `:answers`, which would match by substring and drop a snapshot key such as `faq_answers` from the audit log.

### Other departures from the plan, by task

- **Field types (Task 1)**: an unticked optional checkbox is stored `false` and reads "No"; the email input has no `maxlength` (the type's limit is the server's) and has `autocomplete="email"`; the hook's `Registrar` refuses what a kind does not take (a block for a field type, unknown members) rather than ignoring it; `Plugins::REPLAYED_ALL` lets the theme's refusal recognise all three hooks.
- **Forms and their writes (Task 2)**: destinations are matched by id and kind alone (matched by position, removing the first of two destinations of one kind left the second holding the first's secret); a text in a language that is turned off is kept, and one given in it dropped without a refusal, as content's are; extra refusals with sentences (a name over 120 characters, a choice without a default-language label, a code this CMS does not serve, a trashed form, a secret without keys); the fixtures are `test/fixtures/form_destinations.yml` (a `forms/` folder would be read as rows of `forms`); the data migration is checked in `test/lib/built_in_data_test.rb`'s `GRANTED_BY_MIGRATION`; Groups' "Forms" toggle card is a placeholder for the Design System.
- **Delivery (Task 3)**: `Forms::DeliveryJob#perform` takes the delivery only; any error that is not a delivery's failure fails the delivery with the key `error` and is raised on; a failure's line is scrubbed of the submission's answers as well as the destination's secrets; Reply-To is the first answer whose type's value type is `:email`, so a gem's such type counts.
- **The Forms screen (Task 4)**: the picker's buttons and badges use the registry's `label` ("Email address", not the design's "Email"), so no per-type key branches on a name; "Mail not set up" asks `MailSettings#complete?` (R18); the keeping card is part of `DestinationsComponent`; **Placed on stands inside the `<form>` element** (the save bar finds its targets as their ancestor), where the design put it outside, and holds no input; the name's card is not drawn on another language's tab; a gem destination's secret is labelled by its name, humanised.
- **Submissions (Task 5)**: the tabs are a shared component, `Admin::Ui::TabLinksComponent`, used by the Trash screen too; `form_submission.resent` is in `Dashboard::Feed::NOT_A_CHANGE` with the other submission events.
- **System status (Task 8)**: the Forms row's words are I18n keys (`admin.system_status.forms.*`), where the other rows' are literals.

### The final review's fixes (2026-11-04, `.superpowers/sdd/2026-11-03-forms/final-review.md`, with the controller's rulings)

- **A type taken out is dormant** (`CLAUDE.md`'s registry rule). A stored field of a field type no longer registered is left out of a send by `Forms::Answers.clean` (the block already drew nothing for it), so the form takes answers again where every send was a 500; `Forms::Save` carries such a field and such a destination as stored, where it refused every save of the form; the builder draws the destination by its stored kind with "This destination's type isn't installed." and a "Remove it when the form is saved" box. Its deliveries still fail `unknown_destination`. Beyond the ruling, the same carry was given to a dormant field in `Forms::Save` (the builder draws its row with the stored type as its badge, and its Remove), since otherwise a form holding one could not be saved either. Cost if wrong: a dormant row stays until someone removes it.
- **"Submissions are sent once it is."** The builder and the list said submissions wait until mail is set up, and each failed `not_ready` at once and needed Send again by hand. Now `Forms::ResendNotReadyJob`, every 15 minutes in every environment, sends again the failed `not_ready` mail deliveries of kept forms while `MailSettings#complete?` and the keys hold, through `Forms::Resend` as the trusted nil actor on `:system` (each a `form_submission.resent` event reading "System", the way the system jobs audit, through the services they call). A recurring job, not a hook on the mail settings' save, because host variables can set mail up with no save. The clean-up no longer sweeps such a submission of a keep-nothing form as undelivered while mail is not set up, since the words promise it is sent once mail is; the builder's line for a keep-nothing form says "Until then they wait here, though this form doesn't keep submissions." in place of "They wait for at most 30 days." Cost if wrong: on a keep-nothing form whose site never sets mail up, submissions are kept for as long as that lasts, with the warnings on the builder, the list and System status saying why.
- **Minors**: a form purged between the endpoint's read and `Submit`'s lock is `GONE`, not a 500; `Audit.record` asks `Visitor.one?`; `FormsMailer` logs a placeholder in the place of its mail, so a visitor's answers are in no log at debug either (through Rails' private hook `set_payload_for_mail`, held by a test); the two lines that wrote "30 days" read `Forms::UNDELIVERED_DAYS`; and unticking keeping on a form that keeps submissions now draws "Turning this off deletes the submissions already kept tonight." under the box. **That line is a placeholder for the Design System**, as is the dormant destination's look.

### Parked, each a row of `docs/roadmap.md`

- The clean-up locks every submission of a keep-nothing form for that form's transaction; batching the locks is left until a form has a backlog large enough to matter.
- `Forms::SendLimit.store` and `MailTestLimit.store` follow one rule written twice; a shared helper is left.
- No test pins the per-form counter's key (the per-visitor one is pinned).
- A failure after a real send (a template error after the server took the mail) marks the delivery failed, and Send again could send the mail twice; a transient error is a permanent failure that needs Send again.

### Open questions

**For the owner**: the New form starter's three labels are English keys written into the form's default-language texts, so on a site whose default language is German they are English until renamed. Acceptable, or should the starter be offered only when the default language is English? (design.md 1; unanswered.)

**For the Design System** (each a placeholder or a decision the design lead took, recorded for the owner to overrule): the Forms list (its columns, the warn badge, the ⋯ menu, the empty state, New form and its starter); the builder (adding a field from the "+ Add field" row, ordering by ↑ and ↓ with no drag, editing a field's row, a choice's choices, the language tabs with the default language's text as a reference line, a field's type fixed once added, no per-field length limit); the destinations and keeping card (the keeping box and its days, the warn boxes for keeping off, no keys and mail not set up, the placeholder line for unticking keeping on a form that keeps some, a dormant destination's section and its Remove box, which take no live role: which is right for a standing condition is open, as the insecure notice and the dashboard's mail notice take `role="alert"`); Placed on; the submissions list (no selection column for deleting several) and one submission (the answers, the delivery rows and their chips, "Mail to …" listing the recipients as they are now, not as they were at the send); the Form block's look in the default theme with its error and thank-you states (the six token values, no mark beside a required label beyond the word, the select's native arrow); the plain pages (the sign-in page's shape, the site's name or a bare link, the visitor's light or dark choice); the Settings Forms card; and the Groups screen's "Forms" toggle card's place.

**For the documentation (work in `contentspiel-docs`, Task 10)**: a new editors' page, "Collect answers with a form" (a send from the preview is a real submission); site settings (the Forms card); users and groups (the two rights); the theme contract and rendering pages (the Form block's names, inputs, tokens, the script's markup, the same-page anchor rule); a page for integrators on adding a field type and a destination from a gem; hosting (encryption keys, a CDN's trusted proxies).
