# Forms

Decided with the owner, 2026-11-03. Roadmap "Next", item 4: "Forms, with mail delivery". Where this says "implementer's call", the owner has not decided it and may overrule it.

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
