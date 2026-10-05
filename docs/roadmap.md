# ContentSpiel roadmap

Living document (started 2026-09-26, consolidated 2026-10-05). ContentSpiel is a **generic, self-hosted CMS** that non-technical editors enjoy using and developers can extend without forking. Priorities: **Must** (needed before we'd call it a usable generic CMS), **Should**, **Could**. Refactors are judged against this list: they must open the seams these items need and never make one more expensive.

How to read it: **Next** is the agreed order of sub-projects. **Before the first deploy** is everything that must be true before a real site runs on this. **Product backlog (Phase 3)** and **Technical health** are grouped by topic, not ordered. **Known gaps** lists what was knowingly shipped incomplete, each under the item that closes it. What is done is one line under **Shipped**; the history is in git and in the specs.

Sources: product review (`docs/product/2026-09-26-backend-product-review.md`), code-structure review (`docs/architecture/2026-09-26-code-structure-review.md`, findings `#N`, sections `§N`), staff review (`docs/architecture/2026-10-04-staff-review.md`, findings `S`, `M`, `L`, `D`, `C`, `O` plus a number), and the specs under `docs/superpowers/specs/`.

## Decisions already made

| Decision | Detail |
|---|---|
| Our own admin, not Avo | Rails + Hotwire, product design tokens (`--cs-*`). Avo is removed. |
| Admin layout | Three columns: modules, page tree, content. |
| Rich text | Tiptap: one Tiptap/ProseMirror JSON document per locale, rendered to HTML on the server, Markdown for AI and MCP (custom nodes as directives). Node types come from a registry (the plugin seam). |
| Independent CSS | Product UI and public theme are separate Tailwind builds with separate tokens (`--cs-*` and `--th-*`); the demo look is only the default public theme. |
| One PR per body of work | Bugfixes and features of a round ship together; no production exists yet. |
| Live edits go live | CS Studio autosaves straight to the record; drafts of live records wait for versioning (see "Versioning"). |

## Shipped

| What | Spec |
|---|---|
| Foundations: locale model (supported and enabled languages), `PublicSite::Urls`, `PublicSite::Resolver`, stored `public_paths` with redirects, the service layer, test helpers, canonical post URLs and posts in the sitemap | `2026-09-26-foundations-design.md` |
| Setup wizard | `2026-09-26-setup-wizard-design.md` |
| Open types: string `content_type` / `block_type` with registries | `2026-09-27-open-types-design.md` |
| CS Studio: shell, page tree, inline block editor, Draft / Scheduled / Live with preview, typed fields per content type, "Connect an AI assistant" | `2026-09-27-cs-studio-design.md` |
| Tiptap editor with JSON storage, the ActionText migration, Avo removed | `2026-09-27-tiptap-and-avo-removal-design.md` |
| Access control (groups, scoped grants, owners) and the append-only audit log | `2026-09-28-access-control-and-audit-design.md` |
| Media library (`Media::Asset`, alt text, reuse, responsive variants) | `2026-09-29-media-library-design.md` |
| Trash: pages with their branch, posts and library images; Undo; retention job | `2026-09-29-trash-design.md` |
| Dashboard and the site time zone | `2026-09-30-dashboard-design.md` |
| Translation helpers: outdated tracking, status everywhere, the Translations matrix, translated site title and tagline, AI translation suggestions | `2026-10-02-translation-helpers-design.md` |
| CS Studio design pass, three rounds (PRs #35–#37, #45): tokens and theme, shared components, the shell and ⌘K; the editors, side-by-side translation, the dashboard and posts list; Settings, Media, Groups, Users, Tags, Trash, the audit log, System status, the preview bar, the Mind graph | `2026-10-03-cs-studio-design-pass-design.md` (§12 lists where round 3 departs from it) |
| Five staff-review bugs (S1–S5) | PR #39 and design pass round 3 |

## Next, in order

Agreed 2026-10-04. Each is its own sub-project with a spec and one PR.

1. **Mind graph on a canvas** (Should). Render the graph on a 2D canvas instead of SVG: D3's force simulation stays, and no new dependency unless WebGL proves necessary. Zoom and pan, with labels that fade in by zoom level, hubs first. Then a local graph (a post's or tag's neighbourhood to depth 1–2, filtered on the server) and a cap with a message on the global view; `PostGraph` selects only the columns it needs.
   - Constraints: colours come from the theme tokens, read from CSS custom properties (no literals in JS); status and type cues stay non-colour-only; the keyboard and screen-reader path is kept through a parallel list of links, since canvas nodes can't take focus; "everything fits inside the box" becomes "the initial view fits everything".
   - Closes: no cap on posts, overlapping labels, every node one size, and a retired type's ring differing from a 7–12 type's ring by colour alone. Lazy-loading d3-force (S13) belongs here too.
2. **Block and type catalogue** (Should). A demo site can only show layouts the block types allow. Today: 3 block types (rich text, image, post list), 3 content types (blog, resume entry, now update), 2 page types (standard, landing); the registries are generic, the shipped set is thin and still a personal site's.
   - Block candidates: hero or banner, columns or grid, gallery, call to action, quote or testimonial, video or embed, accordion or FAQ, teaser cards linking to pages, and a sitemap block (a human-readable list of the published tree in the visitor's language).
   - Content types: event, person or team member, project or case study; decide whether resume entry and now update stay defaults or move to an optional "personal site" starter set.
   - Page types: contact, legal, redirect or link page, and a sitemap page (a standard page carrying the sitemap block).
   - Not here: the contact form (see "Forms"), editor-defined types (see "Custom content types"). Needs designs for each block's editor card and public rendering.
3. **Demo content in the setup wizard, plus a large debug and performance data set** (Should). The wizard's starter-content step gains a "Demo site" choice; a second, much larger set with varied layouts and images serves debugging, performance checks and the design issues an almost empty site hides. Built through the save services, not a seed script. Open: who may pick the large set.
4. **Invites** (Should). A one-time set-password link without mail (`Users::Invite`).
5. **Admin UI in German** (Should, #49, M8). The public site's own strings in German and Spanish first (about 15), then the i18n key scheme for the admin, decided at the start of this sub-project. Known English-only spots that build sentences in Ruby: `Audit::Sentence`, and `Post.human_attribute_name` / `ContentBlock.human_attribute_name`.

## Before the first deploy

Everything here is Must. Three sub-projects; none is scheduled against the list above yet.

### Hardening

| Item | Ref |
|---|---|
| Pre-launch checklist: SSL and hosts, mailer host and sender, deploy secrets, error reporting, backups, no console span exporter in production | L1–L4 |
| API token lookup by an indexed SHA-256 digest. Today MCP auth does one bcrypt comparison per active token, and tokens accumulate, so authenticating gets linearly slower and costs an unauthenticated caller the same | S9 |
| Lost updates on the group and user forms: neither carries a stale check and each replaces whole lists (grants, members, a user's groups), so of two admins saving the same record the second silently undoes the first. `base_updated_at` and a 409 as Settings has; `replace_grants`, `sync_members` and `sync_groups` must touch the record | Round 3 final review |
| Access control, dormant grant names: `can_assign_group?`, `can_manage_group?` and `Groups::Save`'s member loop judge a group's live grants only. A removed content type's name grants nothing while the type is unregistered, but it can be handed on with a membership or a token by someone who couldn't grant it, and it revives if a type of that name is registered again. Judge the carried scope instead | Round 3, Tasks 10–12 |
| Access control, grants per permission: no unique index on `access_control_grants (group_id, permission)` while the group editor shows one grant per key, so a group holding two loses one on a save from the screen; `Groups::Save#live` matches greedily and can refuse a harmless shrink in that state | Round 3, Task 10 |
| Owner flag: `:owner` is still permitted in the ordinary user params (a second door beside `PATCH users/:id/owner`, owners only), and `Users::Save#owner_change?` reads a blank value as a flip | Round 3, Task 12 |
| Guarantees by behaviour, not grep: a behavioural service contract test, and the remaining permitted-attribute slices | S19, S21, S24 |
| `site_settings.locales` is read, changed and written without a row lock: two language changes at once can lose one. `lock!` the row in `Locales::Enable`, `Disable`, `MakeDefault`, `Configure` and `Settings::Save` | Round 3 final review |

### Performance and caching

In this order; each step needs the one before.

| Step | Ref |
|---|---|
| 1. Stop recomputing URLs on every page save: sync `public_paths` only when slug, parent, position, publication or trash state changed, set-based, from the services rather than `after_save` | S6, M2 |
| 2. A content version that moves only on changes to published output (one version row), instead of 14 aggregate queries per public request that any draft autosave invalidates; preload after `stale?` | S7, S8 |
| 3. A whole-page cache inside Rails keyed on the version row, path and language, so every publishing change takes effect at once | C1 |
| 4. A "Clear cache" button: site-wide under System (its own permission, audited) and "Clear this page's cache" in the editor's ⋯ menu, for what the services can't see (a console change, a restored backup, a stuck CDN) | C6 |

Then, Should: caching as a per-instance setting under Settings (the shared lifetime sent to proxies and CDNs, default 0; a CDN provider with encrypted credentials from a registry like `AI::Providers`, purged from a job after each version bump) (C7); a cache lifetime per page for static pages, as presets in the page settings (C8); library images served in Active Storage proxy mode with long-lived headers (C2); 404s cached briefly, and purge on publish once a CDN exists (C3, C4). Could: fragment and admin-side caching, deliberately deferred until measuring shows a need (C5).

### Observability

| Item | Priority | Ref |
|---|---|---|
| One span in `ApplicationService` (service, actor type, channel, outcome, audit event id) so every write is traced; attributes on the public request (resolver result, language, cache hit or miss); rescued exceptions reported through `Rails.error` | Must | O1, O2 |
| Guards against the performance problems returning: N+1 detection raising in tests, and query-count assertions on a public page render and a page save | Should | O5 |
| Structured logs tied to traces; a jobs dashboard and failed-job counts on System status; browser errors reported to the server; a cache hit rate; `/up` that checks the database | Should | O3, O4, O6, O7, O8 |

## Product backlog (Phase 3)

What comes after the admin; code comments and `CLAUDE.md` call it "Phase 3". Grouped by topic. Nothing here is ordered or scheduled.

### Publishing

| Item | Priority | Notes |
|---|---|---|
| Versioning: revisions and restore, with pending revisions (drafts of live records) | Must | §7.3. Audit snapshots are the version basis; they keep a translation source's digest but not its text, so a restore can't reproduce a word diff's "before". Closes the largest group of known gaps (see "Closed by versioning") |
| Publishing workflow: review and approval, draft comments, edit lock, scheduled unpublish | Should | Needs pending revisions |
| Release management: bundle changes to several pages and posts, preview the whole site with the release applied, shareable preview links, publish atomically | Should | A release is a set of pending revisions |
| Approval chains for releases: steps that specific groups must approve, defined in the admin by authorised groups, recorded in the audit log | Should | Needs releases |

### SEO, navigation and the public site

| Item | Priority | Notes |
|---|---|---|
| SEO: hreflang, Open Graph image per page and post, noindex, snippet preview, automatic sitemap | Must | Built on `PublicSite::Urls` |
| Navigation and menu management | Should | `Navigation.for` (#52) |
| RSS and Atom feeds | Should | Cheap now that URLs are canonical |
| Legal and GDPR: imprint and privacy pages, consent hook, user export and delete | Should | |
| A language dropdown on the public site | Could | |
| Public-site dates in the site time zone (today the public site and `/preview` render in UTC) | Could | The render cache must vary on the zone |
| 410 Gone for trashed or purged URLs instead of 404 | Could | Needs a tombstone; a trashed record's `public_paths` rows are deleted |
| Forms with submissions and spam protection | Could | Routes hook before the catch-alls |

### Content model and extension

| Item | Priority | Notes |
|---|---|---|
| Custom content types and fields defined in the admin | Should | Registry with DB-backed definitions |
| Plugin API v1: Rails engines, the registries behind one registration facade, event hooks, a routes hook, an MCP tool registry, a versioned API | Should | §8, M4 |
| Languages outside the built-in list: today a language is switched on in Settings from `SUPPORTED_LOCALES`; adding one needs a code change | Should | |
| Reusable content: global snippets, page templates, block presets | Could | Needs a block owner (#47) |
| Headless read API and webhooks on publish | Could | Generalised serializers and events |
| Import, export and backups | Could | A revision snapshot is the export format |
| Content quality checks: broken links, required alt | Could | Event subscribers or a job |
| Page authorship, so pages can have an `own` scope as posts do | Could | |

### Search

| Item | Priority | Notes |
|---|---|---|
| Site search and admin global search (Postgres full-text) | Should | ⌘K matches titles only today. `tsvector` for bodies and `pg_trgm` for titles (D2) |

### Security and accounts

| Item | Priority | Notes |
|---|---|---|
| Security basics: 2FA, session list and revoke, login history | Should | Login history is already in the audit log |
| Script CSP with nonces | Should | S20 |
| Audit log export and retention (the log grows without limit); partition `audit_events` by month when retention is built | Should | D5 |

### AI

Shipped: translation suggestions (provider registry, encrypted key, `ai.translate`, suggestions the editor applies with Use).

| Item | Priority | Notes |
|---|---|---|
| Suggestions as a background job that streams boxes back over Turbo. Today each request holds a Puma thread for up to two 25 s provider calls, and is capped at 6,000 characters to stay short | Should | Lets the cap and timeout grow |
| Excerpts, alt text and summaries | Could | `AI::Providers` and the suggestion box are the seams |
| A monthly AI budget per site | Could | `ai.translated` events already record characters |
| More built-in providers (an OpenAI-compatible one) | Could | Plugins can register providers today |
| Whole-site translation as a background job | Could | |
| Translation memory and glossary | Could | |

Deliberately not planned: AI tools over MCP. MCP clients are already AIs and can translate through `update_post`.

### Collaboration

| Item | Priority | Notes |
|---|---|---|
| Workspaces: a place to work on pages together with what the work needs — links to pages, posts and images, uploaded documents, the people involved, and an AI assistant that can read those references. A workspace's work can flow into a release | Could | Builds on documents in the media library, comments and edit locks, pending revisions, `AI::Providers` and groups. Open: per page, per project or free-form; what the AI may write without a human pressing Use |

### Media library

All Could (media library spec §8).

- Video and document files, not only images.
- Cropping and a focal point.
- Folders and tags for organising assets.
- Automatic cleanup of unused assets (can build on the trash; today cleanup is by hand or `bin/rails media:orphans`).
- Uploads through MCP (MCP is read-only over the library today).
- The site logo moved into the library (needs SVG sanitising).

### Trash

All Could (trash spec §10).

- Trash for single blocks, tags, groups, users and API tokens; deleting one is still permanent. Until tags have it, deleting or merging a tag also changes trashed posts, so a post restored later comes back without that tag.
- MCP trash tools (list, restore, purge). MCP can't delete anything today.
- A holder of `trash.empty` alone can't delete a single item from the Trash screen, though `Trash::Purge` would allow it: list by the purge right as well.

### Dashboard and CS Studio

| Item | Priority | Notes |
|---|---|---|
| Per-user time zones (today one site-wide zone) | Could | |
| Dashboard customisation, widgets, statistics | Could | |
| A resizable or collapsible page-tree column | Could | |
| A "sample" marker on starter content | Could | |

## Technical health

From the staff review unless noted. What must happen before a deploy is in "Before the first deploy"; this is the rest.

### Performance

| Item | Priority | Ref |
|---|---|---|
| Public read path: no `posts` scan on a 404, batched URL and internal-link lookups, a cap on unlimited listings | Should | S11, S14, S15 |
| Admin frame requests render a minimal layout; the tree loads only visible, kept pages | Should | S10 |
| MCP `list_posts` paginated, without rendering bodies | Should | S12 |
| Lazy-load Tiptap instead of evaluating it on every admin page | Should | S13 |
| Indexes the queries need: `updated_at` / `published_at` on posts and pages, one GIN index on the slug jsonb, `content_blocks.block_type` | Should | D1–D3 |
| The audit log pages by `offset` over `last_occurred_at`, which moves when an event coalesces, so a row can repeat or be skipped between pages: keyset paging on `(last_occurred_at, id)` | Should | Round 3 |
| The dashboard feed's event query grows with the readable set (hashed subplans, a `work_mem` cliff on a very large site); dashboard drafts without the per-row audit join | Could | S17, round 2 |
| `StateIndex.rebuild_all` runs synchronously on a language change, proportional to the site; `translated_record_count` runs on every Settings render for a `languages.manage` holder | Could | Round 2, round 3 |
| Drop redundant indexes; the missing `created_by_id` foreign key; narrower row loads | Could | S18, D4, D9 |

### Correctness

| Item | Priority | Ref |
|---|---|---|
| Sibling positions that can't collide (advisory lock, one set-based renumber, a deferrable unique constraint); an atomic stale-autosave check (a conditional `UPDATE`) | Should | S16, D6, D8 |
| `translation_states` doesn't follow code changes (a deploy that adds a required translated field leaves rows stale until `bin/rails translations:reindex`), and a record created outside the services has no row | Should | Round 2 |
| Changing the default language to a third one flags every translation as outdated, because digests are compared against the new original. Re-baseline the digests in the default-language change | Could | Translation helpers |
| A trashed page whose `trash_root_id` is NULL (its root's row deleted outside the services) is listed nowhere and never swept. Treat a NULL root as its own root in `Trash.roots`, or a repair task | Could | Round 3 |
| The trash row's date counts calendar days in the site zone while the purge job's cutoff is days × 24 hours: across a clock change an item can become purgeable an hour before the date shown | Could | Round 3 |
| A schedule set in the same save as other fields is recorded inside `*.updated`, so the log says "edited", not "scheduled" | Could | Round 3 |
| `ContentModel::FieldSet#assign` drops an unparseable date or integer for any caller but the post editor: a block's settings silently lose the value | Could | Round 2 |
| Social links are a jsonb hash, so their row order isn't kept and two rows with one label collapse; a scripted client posting them as an array clears the stored links | Could | Round 3 |
| Smaller defects: `AccessControl.holds?` counts a grant whose content types are all unregistered; `Tags::Merge` racing a `Posts::Save` that inserts the same tag answers "image doesn't exist"; unbounded titles in single-record flashes; forged param shapes that 500; a translate timeout that doesn't abort; two ways to enable a language; Duplicate across two transactions; a plugin's starter sample with a key outside the Save allow-lists raises | Could | S26–S32, round 3, PR #39 |

### Structure

| Item | Priority | Ref |
|---|---|---|
| Fix the remaining dependency inversions (a model calling `ApplicationController.render`, a model calling services, models and queries using route helpers), then a guard test. The direction is written down in `CLAUDE.md` ("Dependency order") | Should | M1 |
| One shared `fetchStream` helper, and one `AccessControl.edit_keys(record)` for the "published needs publish" rule (written out five times) | Should | M6 |
| One segmented-control component (drawn by hand on four screens) | Could | Round 3 |
| Split `queue.js`, `translate_controller.js`, `rich_text/document.rb` and `markdown.rb`; unit tests for the pure JavaScript; a posts list query object | Could | M3, M5, M7 |
| Remove leftovers: the ActionText import path, unused Action Mailbox and Action Cable, test gems in the production image, unpinned CI Postgres | Could | M9 |
| `CLAUDE.md` is about 127 KB and loaded into every session: move the per-screen descriptions to `docs/` and keep rules and pitfalls | Could | Round 3 final review |

### Tests

| Item | Priority | Ref |
|---|---|---|
| System tests fail on JavaScript errors and click natively; a Tiptap schema drift test; tests for the Turbo internals `queue.js` relies on (`turbo-rails` is pinned to 2.0.23) | Should | S22, S23, S25 |
| Fixed sleeps in system tests (a stubbed provider delay, wall-clock windows) are load-sensitive; replace them with flags the stubs set | Should | Round 2 |
| The system suite flakes at 12 parallel workers on a laptop (run it with `PARALLEL_WORKERS=6`): a leaner browser fixture, or CI-sized runners | Could | Round 2 |
| Mouse drag in the page tree and block list (SortableJS's fallback) was never hand-tested in Firefox | Could | Round 1 |

## Known gaps (interim states)

Knowingly shipped incomplete, and fine while tracked here. Grouped by what closes them.

### Closed by versioning

- CS Studio autosave writes straight to the record: edits to a published page or post go live as the editor types (the editor header says so).
- Editing an already-published page, post or block therefore needs `publish`, not only `edit`.
- A save the server processed but whose answer was lost is retried on the old base and gets a final "Changed elsewhere" refusal, locking the editor out until Reload. Per-record version columns would close it too.
- An edit typed between a header action's submit and its redirect is refused unseen; an edit typed during an in-flight save followed at once by Back or Forward is dropped.

### The write queue and Turbo

Small follow-up fixes to `app/javascript/autosave/queue.js` and its neighbours; none loses saved data.

- A `_top` link clicked while a `#content` frame navigation is loading loses to the visit that navigation is promoted to. Forms are held (the promotion hold); links are not.
- A held press whose screen was replaced is dropped unsent with an error toast, unless it is a Trash row's restore or purge form. Affected: the editor header's actions, the bulk bar, tags Merge, the user and group zones, "Still correct". Opting a form in (`data-promotion-stand-in`) is the follow-up, form by form.
- A press during a frame fetch that hangs waits up to 10 s before it is sent.
- A filter changed in the instant its own answer re-renders the toolbar (the audit log, the posts and media lists) is lost with the old control.
- Hover prefetch is off on the page and post editors, and a refetched `#content` frame can lose a flash toast the first answer relayed.
- After a block is deleted, the next queued write waits up to 1 s, because the queue doesn't recognise the delete answer's stream as applied.
- Three narrow cases in the content frame's stale-answer refetch (a 422 frame answer replaced by a fresh render; continuous typing across about three round trips after clicking the open page's own tree row; an aborted held request overwriting a newer write count).
- For up to 30 s after leaving a page with a hung save, the next page's visits wait and its header actions are declined.
- A double click on a header action that has already settled can fetch its redirect twice.
- A block reorder queued behind one that failed is lost without a toast of its own; a block card answered 410 keeps the unload prompt up.
- After Back or Forward, the toast controller's "this render came from the cache" flag stays set until the next visit, so a top-level form that then fails loses its error toast.
- A drag clone can stay on the page if the tree or block list re-renders mid-drag.
- Instant filters put focus back on the control that triggered the reload even if the editor moved focus elsewhere meanwhile.
- The tree re-render after a move marks the moved page as selected even when another page is open.

### Save footer screens

- The leave guard doesn't ask about a GET form submitted into `#content` or a script setting the frame's `src` (no explicit-save screen has either), and Back to an entry from before a full page load gets only the browser's own prompt.
- A refused Settings save can't put a chosen logo file back.
- A non-owner who couldn't grant a carried removed content type must press Remove before changing that group row in any other way, else the save is a 403. The locked tick ("You can't grant this") is unreachable from stored data and kept only as a defensive rendering.

### Media

- Until a variant has been processed, a page serves the original file at full size. `bin/rails media:variants` re-enqueues any still missing.
- The panel is a 340px column from 1024px and stacks under the grid below; the handoff's overlay at 1024–1279px is not built.
- Leaving mid-upload asks nothing and drops the files still queued.
- A file dropped on a rich-text editor may still make the browser open it (the file-drop guard leaves `contenteditable` alone; not verified).
- A tile activated twice within a few milliseconds renders the frame twice with no promoted visit. Whether a fast human double click does it is untested.
- A tile stays in the Missing alt segment after its alt was typed, until the grid reloads; in the picker a selected image whose tile isn't listed isn't named, a finished upload replaces a selection made by hand, and Escape from a tile doesn't return focus to the search; on an out-of-range page a finished upload's tile has nowhere to appear.
- The Media panel's "Only by items in the trash" line names trashed owners to a reader who may lack the delete right. Accepted.

### Lists and editors

- Posts list: Undo for a bulk trash is offered only while its URL fits the session cookie (a few dozen posts); the bulk bar precedes the table in the DOM, so a keyboard user tabs back up to it; `Posts::Save#find_tag` costs up to two queries per submitted tag name.
- Translations matrix: an old `?locale=` link lands on the unfiltered matrix; the summary cards don't count the Site settings row; the ordering expression is evaluated over the filtered set, not only the page.
- The New page and New post forms load when the dialog opens, and the title preset travels in a GET query string, so it appears in the request log.
- A schema group field's reference card shows the raw Hash.
- Escape during a suggestion search's 150 ms debounce closes the surrounding dialog.
- The error toast has no Retry action; nothing raises an error a retry could repeat yet.
- The group editor with scripts off shows an Edit scope button that does nothing on a ticked row; a stored branch root in the trash reads "A page you can't open (kept)" even to an owner. Ticking an ancestor above a page ticked in the same session drops the child where a stored one is kept.
- The token form decides whether a refusal belongs under Name or Group from the message's first word.
- The group delete dialog says tokens are "revoked" while `Groups::Destroy` deletes their rows.

### Accepted as they are

- The seeded Author group's `posts.read` and `posts.create` are unscoped, so an Author reads every post (only `posts.edit` is `own`-scoped). Revisit if it surprises in practice.
- A related post the viewer can't read is hidden but disclosed as a count ("+N related posts you can't open").
- The audit log's append-only trigger blocks `DELETE` and `UPDATE` but deliberately not `TRUNCATE`, so `db:truncate_all` works in development.

## Polish backlog

Departures from the design mocks that the visual checks listed; none is wrong. One polish pass.

- **Dashboard:** a date eyebrow above the heading; card titles with counts and "→ All drafts" / "Open →" links; a quieter empty-state line.
- **Editors:** the placeholder "Empty — write it, or use the suggestion."; a content-type dot in the post breadcrumb; the translation pair stacking at 1400px beside the page tree.
- **Settings and the AI assistant:** title and tagline stacked instead of side by side; a tall logo drop zone; inline labels instead of column headers in Languages; no active item in the in-page nav; the AI assistant's step 1 stacked instead of one row.
- **Media:** the panel as a card under the toolbar rather than a full-height column; the big "Choose file" drop zone still drawn above the grid.
- **Groups:** name, description and members in a narrow column without a card or breadcrumb.
- **Audit log:** large filter selects, row avatars and quoted titles; the event page's two unaligned change tables and raw ids for related posts.
- **System status:** rows without a card.
- **Across screens:** segmented controls' selected state tinted rather than inverted; lists and editors spanning the full width where the mocks cap them near 1100px; the preview bar barely set apart from a dark public page; the dark theme's dialog backdrop reading as a light wash; new toasts end with a full stop and older ones don't.

## Out of scope (for now)

Multi-site, e-commerce, memberships and paywalls, built-in comments.

## Guardrails while the roadmap is pending

From the structure review: no new integer enums, no new `has_one_attached` on content models, no new `after_save` side effects on `Page` or `Post` (use services and events), no hand-built URLs outside `PublicSite::Urls`, no new per-locale columns or indexes. Respect the "don't touch" list in §6 of the structure review.
