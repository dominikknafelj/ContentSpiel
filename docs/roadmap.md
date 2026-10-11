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
| Technical cleanup: system tests that fail on JavaScript errors, click natively and wait without fixed sleeps; a behavioural service contract and a dependency-direction guard; the admin i18n key scheme; `queue.js` and `CLAUDE.md` split; one grant per permission, dormant names judged as stored, stale checks on the group and user forms, the owner flag through one endpoint, API tokens found by an indexed digest, language changes under a row lock; URLs synced only when they can have changed; a content version that moves only on published changes | `2026-10-05-technical-cleanup-design.md` (§10 lists the rulings made while building) |
| Mind graph on a canvas: one 2D canvas laid out by d3-force in a Web Worker, zoom and pan, hubs sized and labelled first with labels that never overlap, a local view around a post or tag to depth 1–2, a cap of 2,000 posts with a message, a search field that reaches everything else, a selection card beside its node, a list beside the canvas whose rows select (the keyboard path), a layout shown at frame pace, nodes that stay where they are dropped, a retired type told apart by shape; d3-force loaded only by that screen | `2026-10-07-mind-graph-canvas-design.md` (§7 holds the measured numbers, §11 the departures made while building and the round after the owner's trial of 2026-10-08) |
| Sections: a block that holds blocks in columns (six layouts) with a background and a width; in the editor a card of lanes and tiles with one block's form open under them, every move by drag and from a menu; on the public page a band with a grid that follows its own width. The first of the four sub-projects the block and type catalogue became | `2026-10-08-sections-layout-design.md` (§12 lists where the build left the spec and the plan) |
| Notes on content, with live delivery (step 1 of "Collaboration on content"): threads of short plain-text messages on a page, a post, a block or a library image, with mentions, following, resolve, reopen and pin, reactions and files; a drawer beside the editors, a section in the Media panel, counts in the posts list, the page tree, the media grid and the mind graph; a per-person inbox on the dashboard with the sidebar's unread count; and delivery to open tabs over Action Cable, as signals that carry ids only, with a toast, a chime and an optional desktop notification for a mention | `2026-10-09-notes-on-content-design.md` (§12 lists where the build left the spec; the look is its handoff's, with the decisions taken while building) |
| Presence (step 2 of "Collaboration on content"): who else has a page, a post or a library image open, as initials in the editors' header and the media panel and a marker in the page tree and the posts list, live over the cable; with the three seams it stood on, extracted from notes — a registry of record kinds, a live core on the server (`Live::Signals`, `Live::RecordChannel`) and in the browser (`live/connection`, `live/state`), and screen slots — and the notes script split into four files first | `2026-10-10-presence-design.md` (§9 "As built" lists where the build left the spec; the look is `2026-10-10-presence-handoff.md`; `docs/reference/presence.md`) |
| Source layout cleanup: every CS Studio screen has one shape (components in `Admin::Ui` or a screen folder, scripts in `controllers/admin/<topic>/` with their modules in `app/javascript/<topic>/`, one locale file per component folder); no behaviour changed, guarded by `test/lib/source_layout_test.rb` | `2026-10-10-source-layout-cleanup-design.md` |

## Next, in order

Agreed 2026-10-04; reordered 2026-10-08, when the block and type catalogue became four sub-projects (layout, shipped as "Sections" above; the built-in catalogue; content types defined in the admin; forms) and the owner put collaboration on content ahead of the three that remain. Each is its own sub-project with a spec and one PR.

1. **Collaboration on content** (Should; decided 2026-10-08). Four steps in this order, each its own sub-project:
   1. Notes on pages, posts, blocks and library images, with live delivery to open tabs: shipped as "Notes on content" above (2026-10-09). Tags take no notes and a note has one subject (its spec's D5); what it left open is under "Collaboration" in the backlog and "Notes" in the known gaps.
   2. Presence (who else has a page, a post or a library image open): shipped as "Presence" above (2026-10-10), with the three seams below and the notes script split first. Presence is per record, not per block: the label on a block ("Dana is editing this block") waits for step 3. What it left open is under "Presence" in the known gaps.
   3. Live refresh of blocks changed by someone else, and edit reservations.
   4. True co-editing of rich text (Yjs): only if steps 1–3 prove insufficient, and after pending revisions (see "Versioning").
   - Steps 1 and 3 are the notes and edit locks that "Publishing workflow" and "Workspaces" below build on.
   - **Extension seams in the core, built as the first tasks of step 2** (Should; decided 2026-10-09, while step 1 was being built; the same day the owner chose NOT to make it a sub-project of its own: an interface drawn from one user is usually wrong, so each seam is extracted when presence, the second feature that attaches to content, is on the table beside notes, and only where both need it; what only notes needs stays a direct call, listed as a known exception in `test/lib/notes_boundary_test.rb`). Notes is the first feature that attaches to content rather than being a content type, and the core had no seam for it: step 1 edited about 60 existing files (the two services that delete content call `Notes::Remove` by name; the editor header, block card, section tile, media tile and panel, posts table, page tree, sidebar and dashboard were each changed to make room for a notes control or count; the dashboard feed, activity, the audit sentence and the mind graph builder gained notes-specific lines; `Session` learned to disconnect cable connections). Presence, edit reservations and the publishing workflow would cut into the same files. The seams to consider, at the start of step 2: (a) content lifecycle hooks: one place where a domain registers what to do when a page, post, block or image is removed, run inside the caller's transaction in a defined order (the order and the lock are the hard part: see the lock-order rule and `Notes::Remove`), with `Notes::Remove` as the first subscriber and the media-usage and translation-state cleanups as candidates; (b) screen slots with a registry: header actions, block-card markers and menu items, list columns, dashboard cards, sidebar badges, so the core components stop naming notes; (c) domain events after commit, generalising the audit log's notification, for things like "a session ended". No dependency-injection container (keyword arguments with defaults do that job) and no engine or plugin packaging (see "Namespaces, not engines"). Notes is converted onto each seam in the task that extracts it. **This is the inside half of "Plugin API v1"** ("Content model and extension" below: the registries behind one registration facade, event hooks, a routes hook, an MCP tool registry): the hooks, slots and events built here are the ones that item later publishes to plugins, with notes as their first user from inside the app. What stays with Plugin API v1, and waits until someone outside actually asks for it: packaging as Rails engines, the routes hook, the MCP tool registry. Until then that item is the documentation of whatever seams exist. **Two tiers of plugin, one interface** (the owner's framing, 2026-10-09): a *core plugin* is tied to the CMS, lives in this repository as a plain namespace, is always on and cannot be switched off (notes is the first; presence, edit reservations and the publishing workflow are the next candidates); an *optional plugin* is third-party code, packaged as an engine, installed or not, and held to the versioned contract. Both register through the same hooks, slots and events, so the interface a third party gets is one the app itself already lives on. The core proper (pages, posts, blocks, access control, the audit log, the services) is not a plugin and knows neither tier. The owner works alone and builds and maintains core plugins only: an optional plugin is written and maintained by whoever wants one. So nothing the owner ships is an optional plugin, no feature is split out of the repository to become one, and the interface is published as it is (the one the core plugins use, documented) without a compatibility layer kept alive for outside code. Candidates found on 2026-10-09 for a second round of seams, each to be judged when its second user appears: notifications as their own domain (one inbox, badge, live signal and per-person settings, with kinds a domain registers; notes' deliveries are the first), live updates (ids-only signal plus a scoped re-fetch, which presence and block refresh need too), per-person preferences, file attachments with protected serving (the media library's upload check and notes' are two copies), audit wording by registration, the trashable kinds, the translation index's record types, ⌘K's lists, the sidebar's list of screens.
     - **Built with presence (2026-10-10): three seams were extracted, and the rest were left with their triggers** (`docs/reference/presence.md`, "The seams"). Extracted, each used by notes and presence: (b) screen slots, `Admin::Slots` with seven names, notes converted onto them; live updates, the second-round candidate named above, as `Live::Signals` (the one sender) and `Live::RecordChannel` on the server and `live/connection` and `live/state` in the browser; and a registry of record kinds, `RecordKinds`, which this list did not name (notes held its fixed list of kinds in three places). Left as direct code, each with the trigger that would extract it: (a) content lifecycle hooks, since `Notes::Remove` is still called by name from `Trash::Purge` and `ContentBlocks::Destroy` and presence has nothing to clean up (trigger: edit reservations); (c) domain events, since "a session ended" stays `Session`'s own callback (trigger: a second listener); the block card's marker and menu item and the section tile's (trigger: block-level presence, step 3); the dashboard's cards, the sidebar's badge, the mind graph's count and nodes and the media tile's chip (trigger: a second feature on each); a column mechanism for lists, the posts table's Notes column header being the one place left in a core template (trigger: a second feature that wants a column). Nothing of this is published to plugins.
2. **The built-in catalogue of blocks, content types and page types** (Should). A demo site can only show layouts the block types allow. Today: 4 block types (rich text, image, post list, section), 3 content types (blog, resume entry, now update), 2 page types (standard, landing); the registries are generic, the shipped set is thin and still a personal site's. The target is all three kinds of site: business, portfolio, editorial.
   - Block candidates: hero or banner, gallery, call to action, quote or testimonial, video or embed, accordion or FAQ, teaser cards linking to pages, and a sitemap block (a human-readable list of the published tree in the visitor's language). Columns and grids are sections; each block is designed for both places it can sit, the page's list and a section's column.
   - Content types: event, person or team member, project or case study; decide whether resume entry and now update stay defaults or move to an optional "personal site" starter set.
   - Page types: contact, legal, redirect or link page, and a sitemap page (a standard page carrying the sitemap block). Page types become a registry first (no new integer enums, see "Guardrails").
   - Needs designs for each block's editor card and public rendering: a real design pass on a design canvas.
3. **Content types defined in the admin** (Should). "Custom content types and fields defined in the admin" under "Content model and extension": definitions stored in the database beside the code registry.
4. **Forms, with mail delivery** (Should). A form block whose fields share the field builder of admin-defined types; submissions; spam protection without a third-party captcha; mail delivery, which is not set up yet. This is "Forms with submissions and spam protection" under "SEO, navigation and the public site", and the contact page type of item 2 waits for it.
5. **Demo content in the setup wizard, plus a large debug and performance data set** (Should). The wizard's starter-content step gains a "Demo site" choice; a second, much larger set with varied layouts and images serves debugging, performance checks and the design issues an almost empty site hides. Built through the save services, not a seed script. Open: who may pick the large set.
6. **Invites** (Should). A one-time set-password link without mail (`Users::Invite`).
7. **Admin UI in German** (Should, #49, M8). The public site's own strings in German and Spanish first (about 15), then the admin. The key scheme exists (`docs/reference/i18n.md`), and the shared components, the admin layout and the Tags screen are converted and guarded (`test/lib/admin_i18n_test.rb`); every other screen is still inline English, so this sub-project converts them, adds the German file and decides how CS Studio picks its own UI language. Known English-only spots that build sentences in Ruby: `Audit::Sentence`, and `Post.human_attribute_name` / `ContentBlock.human_attribute_name`.
8. **More tools in the MCP server** (Should; added 2026-10-10 by the owner). The server has six tools today, all for posts and the media library (`list_posts`, `get_post`, `create_post`, `update_post`, `list_media`, `get_media`), so an AI client can neither read nor build a page, see or write a note, upload an image or restore anything. This step starts with a look at what an assistant should be able to do in CS Studio and in which order, then builds it as one sub-project. The candidates, each already listed where its area is: page and block tools (under "Sections", in the gaps: they carry a block's section and column on create and move and report them on read); notes tools ("Collaboration": list a record's open threads, read a thread, start one, reply; the twelve `Notes::` services take any actor already); uploads ("Media"); trash tools (list, restore, purge); and `list_posts` paginated, without rendering bodies. To decide in its brainstorm: whether a note or an edit made through a token is marked as written by an assistant (the screens cannot show that today), and whether an assistant may mention people, which notifies them. Not part of it: the MCP tool registry for plugins (that stays with "Plugin API v1") and AI tools over MCP (deliberately not planned, see "AI").

## Before the first deploy

Everything here is Must. Three sub-projects; none is scheduled against the list above yet.

### Hardening

| Item | Ref |
|---|---|
| Pre-launch checklist: SSL and hosts, mailer host and sender, deploy secrets, error reporting, backups, no console span exporter in production | L1–L4 |
| `Settings::Save` assigns the attributes it is handed; give it an allow-list as `Pages::Save` and `Posts::Save` have | S21 |
| Access control, unregistered permission keys: `can_assign_group?`, `can_manage_group?` and `Groups::Save`'s added-member check skip a grant whose permission is no longer registered (a removed plugin's key). It grants nothing meanwhile, but someone who never held it can hand it on with a membership or a token, and it revives if the key is registered again. Judge it as stored, as a removed content type's name is | Technical cleanup §10 |
| The cable, which notes are the first to use: the `cable` database (`content_spiel_production_cable`, named in `config/database.yml`) exists and has its schema loaded from `db/cable_schema.rb` (there is no `db/cable_migrate` directory, although `database.yml` names one as its migrations path); the proxy passes WebSocket upgrades on `/cable`; and a same-origin handshake has been tried through the real proxy (`assume_ssl`, `force_ssl` and the proxy's `ssl` are still commented out). Without it CS Studio works as without push | Notes §6.5, §12 |
| A cable outage costs every notes write a timeout per person and per record told: `Notes::Signals` sends one synchronous broadcast for each (the failure is swallowed, the note is saved, the request is slow). Send them from a job, or with a short timeout, before the cable is relied on | Notes, final review |
| Nothing in front of the app limits the size of an upload: a body of any size is received in full before `Notes::Files` (or the media library) refuses it, and a read-only account has an upload form now, the notes composer's. Set a body limit at the proxy | Notes §12 |

### Performance and caching

In this order; each step needs the one before. The two steps they build on shipped with the technical cleanup: URLs are synced only when they can have changed, and the content version is one counter row that moves only on published changes.

| Step | Ref |
|---|---|
| 1. A whole-page cache inside Rails keyed on the version row, path and language, so every publishing change takes effect at once. Revisit here whether URL and version maintenance move from the models' callbacks into the services | C1, M2 |
| 2. A "Clear cache" button: site-wide under System (its own permission, audited) and "Clear this page's cache" in the editor's ⋯ menu, for what the services can't see (a console change, a restored backup, a stuck CDN) | C6 |

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
| Publishing workflow: review and approval, draft comments, edit lock, scheduled unpublish | Should | Needs pending revisions. Comments and edit reservations come first, with collaboration ("Next", item 1) |
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
| Forms with submissions and spam protection | Could | Routes hook before the catch-alls. Scheduled as "Next", item 4 |

### Content model and extension

| Item | Priority | Notes |
|---|---|---|
| Custom content types and fields defined in the admin | Should | Registry with DB-backed definitions. Scheduled as "Next", item 3 |
| Plugin API v1: Rails engines, the registries behind one registration facade, event hooks, a routes hook, an MCP tool registry, a versioned API | Should | §8, M4. Its inside half comes first, as "extension seams in the core" ("Next", item 1, at the start of presence): hooks and slots used by notes and presence. The owner maintains core plugins only, so no compatibility promise: the rest of this item waits for a real outside author |
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
| Following a whole page or post, so that every new thread on it notifies | Could | Notes §11. Today a person follows threads: by writing in one, by being mentioned, or with "Notify me" |
| Notifications with no CS Studio tab open: a service worker and web push | Could | Notes §11. Today a mention reaches open tabs only; the inbox holds it until the next visit |
| Mail for a mention, and per-person mail settings | Could | Notes D2. Waits for mail delivery ("Next", item 4) |
| A sound or a desktop notification for more than a mention (a reply, a resolve) | Could | Notes §11 |
| GIF search in the composer, behind a key the install provides | Could | Notes D11. An outside service sees editors' IP addresses |
| An anchored highlight in the text for a note on a passage, tracked through edits | Could | Notes D4: a quote is a copy today. With step 4 of collaboration |
| Notes on tags, users or settings, and a note on several records at once | Could | Notes D5: "what if you may see only one of them" for every list and count |
| Notes on one language version of a record | Could | A thread is on the record; the language it was started in is context only |
| MCP tools for notes | Could | Notes §3.4. The twelve `Notes::` services take any actor; no tool exists |
| Assigning a thread to a person, due dates, "review requested" | Could | With "Publishing workflow" above, which builds on notes |
| A permission of their own for notes | Could | Notes D3: today whoever reads a record reads and writes its notes, and whoever edits it moderates them |
| Presence on the dashboard, in the mind graph and in the media grid | Could | Presence D2 and §7: the design left them out. Each is a named exception in `test/lib/notes_boundary_test.rb` with its slot as the trigger |
| Workspaces: a place to work on pages together with what the work needs — links to pages, posts and images, uploaded documents, the people involved, and an AI assistant that can read those references. A workspace's work can flow into a release | Could | Builds on documents in the media library, the notes (shipped) and edit reservations of collaboration ("Next", item 1, steps 1 and 3), pending revisions, `AI::Providers` and groups. Open: per page, per project or free-form; what the AI may write without a human pressing Use |

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
- A purge does not re-check `trashed_at` under its lock: a record restored in another tab after the purge loaded it is still deleted (older than notes; found while placing `Notes::Remove`).
- A holder of `trash.empty` alone can't delete a single item from the Trash screen, though `Trash::Purge` would allow it: list by the purge right as well.

### Dashboard and CS Studio

| Item | Priority | Notes |
|---|---|---|
| Per-user time zones (today one site-wide zone) | Could | |
| Dashboard customisation, widgets, statistics | Could | |
| A resizable or collapsible page-tree column | Could | |
| A "sample" marker on starter content | Could | |
| A post's neighbourhood in the post editor (an embedded mind graph panel) | Could | Mind graph spec §2, §10 |
| WebGL rendering for sites beyond the mind graph's cap (2,000 posts) | Could | Mind graph spec §2, §10 |

## Technical health

From the staff review unless noted. What must happen before a deploy is in "Before the first deploy"; this is the rest.

### Performance

| Item | Priority | Ref |
|---|---|---|
| Public read path: no `posts` scan on a 404, batched URL and internal-link lookups, a cap on unlimited listings | Should | S11, S14, S15 |
| Admin frame requests render a minimal layout; the tree loads only visible, kept pages | Should | S10 |
| MCP `list_posts` paginated, without rendering bodies | Should | S12 |
| Lazy-load Tiptap instead of evaluating it on every admin page (done for d3-force, which only the Mind graph's layout worker loads now; Tiptap's is still open) | Should | S13 |
| One GIN index on the slug jsonb (slugs and titles are queried inside jsonb with no index) | Should | D2 |
| The audit log pages by `offset` over `last_occurred_at`, which moves when an event coalesces, so a row can repeat or be skipped between pages: keyset paging on `(last_occurred_at, id)` | Should | Round 3 |
| The dashboard feed's event query grows with the readable set (hashed subplans, a `work_mem` cliff on a very large site); dashboard drafts without the per-row audit join | Could | S17, round 2 |
| `StateIndex.rebuild_all` runs synchronously on a language change, proportional to the site; `translated_record_count` runs on every Settings render for a `languages.manage` holder | Could | Round 2, round 3 |
| Drop redundant indexes; the missing `created_by_id` foreign key; narrower row loads | Could | S18, D4, D9 |
| Notes, small: `note_threads.created_by_id`, `resolved_by_id` and `pinned_by_id` have no index, so deleting a user runs three `SET NULL` updates that scan the table; the mind graph card's JSON endpoint loads the listing's first 50 threads for three rows; `Notes::Listing#heading_of` preloads an image block's stored file where only its type is shown; the page tree's two note-count statements are paid by every stream that redraws it; `Notes::Listing#users` is memoised from the first load | Could | Notes, final review |

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
| A tag merge and a page's purge can still deadlock, and so can two purges of sibling pages: the purge locks its branch's pages in id order, but closure_tree's sibling renumbering (`_ct_reorder_siblings`) then updates the purged root's later siblings outside that order (`app/services/trash/purge.rb`, `app/services/tags/merge.rb`; both carry comments saying it cannot happen). Add the root's siblings to the lock | Could | Sections |
| The purge of a trashed post that carries a tag can deadlock against a merge of that tag: `Posts::Save` and `Tags::Merge` take a post's row and its `post_tags` rows in opposite orders, so `Trash::Purge` cannot take them in an order that agrees with both. Older than notes; found while placing `Notes::Remove` in the purge, whose own row lock ahead of the destroy was taken out again for the `Posts::Save` half (`Trash::Purge#remove_notes`) | Could | Notes §12 |
| Deleting a user at the instant someone writes in a thread that names them can deadlock, or raise a foreign-key error: a notes transaction holds the thread's row and then needs a key-share lock on the user's row for a delivery, a follow or a message, while `Users::Destroy` deletes the user's row first and its foreign keys then reach into the notes rows. A 500 and a rollback for one of the two; nothing is lost and a retry works | Could | Notes, final review |
| A storage failure while a note's file is uploaded (a full disk) raises out of the commit: the note is saved with a file row whose bytes are missing (the file action answers 404 for it), the request is a 500, and the signals queued behind it are not sent. `Notes::Files.attach` answering false covers a failed save of the rows only | Could | Notes, final review |
| `Notes::Remove` finds a record's threads by subject, not by container: a thread whose block had gone without its notes (no path does that today) would outlive the purge of its page as a row nobody can reach, and is counted but not listed meanwhile. A refusal from `Notes::Remove` becomes a generic failure of the purge, and it raises `KeyError` for a block whose page is gone (both unreachable today) | Could | Notes, final review |
| A block create that waits on the lock of a page which is purged meanwhile goes on to write a block whose page is gone: `ContentBlocks::Structure#lock_owner` answers nil for a missing row, nobody checks it, and the polymorphic owner has no foreign key (`app/services/content_blocks/save.rb`) | Could | Sections |
| Smaller defects: `Tags::Merge` racing a `Posts::Save` that inserts the same tag answers "image doesn't exist"; unbounded titles in single-record flashes; forged param shapes that 500; a translate timeout that doesn't abort; two ways to enable a language; Duplicate across two transactions; a plugin's starter sample with a key outside the Save allow-lists raises | Could | S26–S32, round 3, PR #39 |

### Structure

| Item | Priority | Ref |
|---|---|---|
| One shared `fetchStream` helper, and one `AccessControl.edit_keys(record)` for the "published needs publish" rule (written out five times) | Should | M6 |
| One segmented-control component (drawn by hand on four screens) | Could | Round 3 |
| Split `admin/translation/translate_controller.js`, `rich_text/document.rb` and `markdown.rb`; `admin/editor/blocks_controller.js` (over 1,100 lines: the remembered orders, the menu moves with their dialog and focus rule are separable units) and the stream helpers of `Admin::ContentBlocksController` (a streams object); unit tests for the pure JavaScript; a posts list query object | Could | M3, M5, M7, sections |
| Notes, written more than once: the frame-params expression (six places), `add_note_item` (card and tile), the inbox sentence's three cases and the read of `X-Notes-Tab` (component or concern, and `NoteInboxController`), `NotesForYou::KINDS` and `Admin::NotePathsHelper::TYPES`, the avatar's classes and initials (`AvatarComponent`, the composer's picker, `card_notes.js`), the disabled state of a message's reaction chips (the component, and `takeReactions` in the browser: the most fragile copy, no test compares the two), `"cs-notes-open"` (the script and the layout's head script), `FOCUSABLE` (two different lists under one name), the burst's 10 seconds, "this tab" (`TAB` in both body controllers), "a message being worked in" (three selectors), "is there a draft" (the composer and `note_unsaved`), the shape `…/threads/<id>` (two scripts), and the 1024px breakpoint (the stylesheet, Tailwind's `lg:` and one `matchMedia`; a resize across it with the drawer open is not handled). `signal.thread_id` is carried through three functions to an event detail nobody reads; `Deliveries.write` is public; `"list"` in `Notes::Thread::ORIGIN_VIEWS` is reserved and unused | Could | Notes, final review |
| Rename `data-notes-live` and `await_notes_live` (they say "notes" and now cover presence's subscriptions too), and move the icon buttons from `title` to the shared tooltip (`Admin::Ui::TooltipComponent`), one sweep; the tooltip then also needs a vertical collision check (it checks the window's and a clipping box's edges sideways only) | Could | Presence |
| A column mechanism for lists, so that the posts table's Notes column header stops being the one place a core template names a feature (`test/lib/notes_boundary_test.rb`); `Presence::Roster#here_counts` has no caller since the markers named people: use it or delete it | Could | Presence |
| Remove leftovers: the ActionText import path, unused Action Mailbox (Action Cable is used by notes since 2026-10-09), test gems in the production image, unpinned CI Postgres | Could | M9 |

### Tests

| Item | Priority | Ref |
|---|---|---|
| A Tiptap schema drift test; tests for the Turbo internals the write queue relies on (`turbo-rails` is pinned to 2.0.23) | Should | S23, S25 |
| Two-connection race tests for the settings row lock (`Settings::Save`, `Locales::Enable` / `Disable` / `MakeDefault` / `Configure`) and for the lock order of a page's blocks (the page's row, then block rows: `ContentBlocks::Save` / `Destroy` / `Reorder` / `Duplicate`, `Tags::Merge`, `Trash::Purge`; `test/services/content_blocks/`): today the tests prove where the lock is taken and what is read after it, not two writers meeting | Could | Technical cleanup §10, sections |
| The system suite flakes at 12 parallel workers on a laptop (run it with `PARALLEL_WORKERS=6`): a leaner browser fixture, or CI-sized runners | Could | Round 2 |
| The system suite needs a quiet machine: macOS background services (Software Update, Spotlight, photo analysis) at a load average of 80 to 110 made two whole runs worthless on 2026-10-10 (4 and 27 failures, 817 and 2,483 seconds), and the same suite passed on a machine at load 2 in 381 seconds. A guard that refuses to run, or says so, above a load average; or fewer waits that depend on timing | Could | Presence |
| The system-test job takes about 17 minutes in CI (16m41s for 477 tests on PR #52, against 4m20s for the unit job), and the mind graph's tests now each wait out a real settle of about five seconds: find where the time goes, then split the job across runners, raise its workers, or shorten the waits | Should | PR #52 |
| Mouse drag in the page tree and block list (SortableJS's fallback) was never hand-tested in Firefox | Could | Round 1 |
| A full system run prints Cuprite's "Modal window with text `` has been opened" once, among the media picker tests (`test/system/admin/media_picker_test.rb`) and never from the sections tests alone: find which test opens a dialog nobody answers | Could | Sections |
| The coverage report (`COVERAGE=1 bin/rails test`) lists about 66 files at 0% that are loaded while the app boots, so its total (85.65% on the sections branch) understates: 98.7% of the lines it did measure are covered. Find why those files are not measured (`test/test_helper.rb`: where `SimpleCov.start` runs, and whether the parent process's result is merged with the workers') before a minimum is set | Could | Sections |

### Accessibility

| Item | Priority | Ref |
|---|---|---|
| After a block or a section is deleted, or a section is removed with its blocks kept, the focus falls to `<body>`, the top of the page for a keyboard user (`Admin::ContentBlocksController#removal_streams`, `admin/editor/blocks_controller.js`): move it to the neighbouring block, or to the first of the kept blocks' cards | Could | Sections |
| From a section's ⋯ menu, "Remove section, keep blocks" shows no waiting state while the write queue drains (up to 10 s on a slow connection, `DRAIN_LIMIT_MS`): the menu closes on the press, so the busy look `admin--saving--queue-hold` gives the button is in a closed menu, and the focus is left at the top of the page meanwhile | Could | Sections |
| A queue drain that passes its 10 s limit is reported as unclean, so the toast says "Your last change wasn't saved" when the save is only slow (`admin/saving/queue_hold_controller.js`, `drained()`'s `timedOut`; also met by the editor header's actions): say that it is still saving and offer to try again | Could | Sections |
| Notes, small: the header's Notes button carries both `aria-pressed` and `aria-expanded`; the mention field sets `aria-activedescendant` on a textarea with no `role="combobox"` and no `aria-expanded`; the composer's emoji buttons have no name (the reaction set's have); the sidebar's unread badge is a bare number in the link's name ("Dashboard 3"); the account page goes from `h1` to `h3`; a deleted author's avatar reads "AD"; a block's notes marker has no `aria-controls`; an open "⋯" menu closes when its thread is refreshed; the focus is given back by index inside an open emoji set | Could | Notes, final review |
| A section's Layout button does not say which layout is current, and the six diagrams in its menu have no visible name (`Admin::EditorScreen::SectionLayoutMenuComponent`) | Could | Sections |

## Known gaps (interim states)

Knowingly shipped incomplete, and fine while tracked here. Grouped by what closes them.

### Closed by versioning

- CS Studio autosave writes straight to the record: edits to a published page or post go live as the editor types (the editor header says so).
- Editing an already-published page, post or block therefore needs `publish`, not only `edit`.
- A save the server processed but whose answer was lost is retried on the old base and gets a final "Changed elsewhere" refusal, locking the editor out until Reload. Per-record version columns would close it too.
- An edit typed between a header action's submit and its redirect is refused unseen; an edit typed during an in-flight save followed at once by Back or Forward is dropped.

### The write queue and Turbo

Small follow-up fixes to `app/javascript/saving/queue.js` and its neighbours; none loses saved data.

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
- A group that stores a removed content type's name is view-only for a manager who couldn't grant that type, until an owner or someone whose own grant covers the name removes it. The locked tick ("You can't grant this") is unreachable from stored data and kept only as a defensive rendering.
- Issuing or revoking a token moves no group's `updated_at`, so a group form opened before it isn't stale, though the group's delete dialog names its tokens.
- The stale banner names nobody when a group was changed from a user's editor or a user from a group's: the audit event is the other record's.
- The Settings save checks for a stale base before the service, so a viewer posting a field outside their right (a languages-only holder posting site fields) gets the 409 rather than the service's 403 and its `access.denied`; the group and user editors stand back for such a write. Deciding "outside their right" in the controller would copy `Settings::Save`'s split of the site and language parts.

### Public URLs and the content version

Left by the technical cleanup (spec §10). The caching sub-project ("Performance and caching" above) revisits how URLs and the version are maintained, and is where these are picked up.

- A record that had to yield its address to another has no URL in that language, and neither have the descendants of a page that yielded. An unrelated save no longer tries again and the editor is told nothing; only a save that changes a URL input, a listing block write or `bin/rails public_paths:rebuild` syncs it. Rare: it needs a slug clash that validation normally refuses. The same rebuild is needed after a content type is registered again, for the posts that lost their URLs with it.
- `PublicSite::Paths.rebuild!` lets a page win a clash between a page and a post, where the incremental sync lets the current holder keep the address, so a rebuild can move an address between the two.
- The go-live sweep (`PublicSite::SyncWentLiveJob`, every five minutes) re-reads the listed posts for 24 hours after any publish, and logs a yielded post's warning on each run. It writes `public_paths` in the background without a lock, so it can meet an editor's save on the unique index and one of the two fails (the same race two concurrent saves have).
- A restored backup rewinds the version counter to values already used: `bin/rails public_site:bump_version` is not enough, the cache must be cleared too, and a browser's or CDN's stored ETag can match again until the counter has passed its old value. The bump task should jump past it. A database whose version row was recreated with an id above 1 needs the stray rows deleted and the cache cleared.
- An `after_commit` callback that raises stops the callbacks queued behind it, a deferred version bump among them; the data is committed and the old pages stay cached until the next bump or `bin/rails public_site:bump_version`.
- Without `KAMAL_VERSION` or a `REVISION` file, `RichText.code_revision` is random per boot, so two processes of one release build different cache keys and ETags.

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
- Mind graph: a label can run over a neighbouring node or past the canvas's right edge; the overlap rule compares labels with labels only.
- Mind graph: a node can be pinned from the keyboard (its card's Pin) but not moved: dragging is pointer-only.
- Mind graph: with reduced motion a large graph shows an empty canvas between "ready" and its one layout message (about two and a half seconds at the cap), and a change of the motion setting applies from the next load.
- Mind graph: the search results close and reopen on each keystroke, and have no arrow-key navigation.

### Sections

Left by the sections sub-project (spec §12).

- MCP has no page or block tools, so an AI client can't read or build a page at all. When they are built they carry a block's section and column on create and move and report them on read.
- No Undo for a move into, out of or inside a section; the toast follows only a reorder of the page's own list.
- An image inside a rich-text block in a column is requested at the content width: the rich-text render is cached by document digest and can't vary by where the block sits. Only an image block's `sizes` follows its column.
- A tile in a section's lane has no pick-up-and-arrows keyboard drag; every one of its moves is in its ⋯ menu.
- A duplicated section is several audit events (a `block.created` per copy and one `block.reordered`), not one.
- "Remove section, keep blocks" is refused while ANY form on the screen holds unsaved text, not only one inside the section, and the toast does not say which form (`admin/saving/queue_hold_controller.js` asks `settled()` and `drained()` of the whole screen). The fix is to ask only the forms inside the section's card.
- Text typed into a form of the section after "Remove section, keep blocks" was pressed, while the removal's request is on the wire, is lost with the form: the section's card is not held `inert` during the removal as a moved block and its form are (`admin--editor--blocks`' `hold`).

### Notes

Left by the notes sub-project (spec §12; `docs/reference/notes.md`).

- A right taken away while a cable subscription is open is not re-judged for that subscription: `Notes::RecordChannel` asks the read scope when a tab subscribes, and an ended session disconnects its sockets, but a grant removed or an owner demoted without the session ending leaves the stream open. It tells such a tab nothing (a signal is ids only, and the fetch it leads to is scoped); it should still be closed.
- A note's file whose erase from storage failed after the delete committed is left in `storage/notes` with no row, and nothing sweeps for it (`bin/rails media:orphans` skips the notes' service on purpose).
- A file is sent from memory: `Admin::NoteFilesController` downloads up to 10 MB per request and ignores `Range`.
- Legacy Office files (.doc, .xls, .ppt) are refused: they share one signature with files that are none of them.
- The chime, the permission prompt and the desktop notification are tested against fakes only (`AudioContext` and `Notification` stubbed); no test plays real audio, meets the real prompt or runs in Safari.
- A notes setting saved on the account screen reaches the person's open tabs of THAT browser at once (the tabs' own channel). A tab in another browser or on another device keeps the old sound and desktop settings until it is loaded in full again, which in CS Studio can be long: moving between screens does not redraw `<body>`, where they stand. A signal on the person's cable stream would close it.
- Two tabs can each chime once when two mentions arrive in the same instant and different tabs win them; and a visible tab that is busy for longer than the 150 ms the tabs take to agree cannot answer, so a hidden one may chime and notify with CS Studio in view.
- The posts list, the page tree and the media grid are not live: their note counts are fresh on load. The media picker's tiles show no note counts.
- A reopen's inbox row names nobody ("A note was reopened"): a thread records who resolved it, not who reopened it.
- "Mark all read" also marks the rows the inbox is hiding at that moment (a record in the trash, a right since lost), so a mention on a restored record can come back already read.
- You can't delete your own note on a trashed record until it is restored: every notes write is refused there, which is what keeps one from running unlocked beside a purge.
- The Media panel and the mind graph's card do not have the handoff's collapsed "Write a note…" input: the panel shows the list with "New note", the card a plain field without mentions or files.

From the review of the whole branch (2026-10-09), none of them blocking:

- `/notes/<type>/<id>` opened as a page (a thread row opened in a new tab) shows the list in the shell with no heading, no title and no link to the record.
- The sheet's rows use the drawer's sizes: the handoff's sheet has `py-3`, 14px text and an uncut first line.
- Nothing is fetched when a cable subscription is first confirmed: a note committed between the frame's GET and the confirmation shows with the next signal.
- A mention's name map is keyed by the name a note shows (`Notes.name_of`), in the browser and in `Notes::Mentions.display`: with two readers of one name a picked mention goes to whichever was picked last, and saving an edit that mentions both re-points one to the other. `Mentions.tokenize` has no word boundary ("@Dana" inside "@Danab"), and `Notes::Text` drops a URL's trailing `)` or `]`.
- A reader can take a moderator's pin off by resolving the thread: `Notes::Resolve` unpins under the read right, `note.resolved` is the only event, and reopening does not restore the pin. Stated as the rule in `docs/reference/notes.md`; it needs the owner's yes or a change.
- An edit sent to a message, or a delete confirmed on one, that went a moment before answers the list with "This note is gone…": only a REPLY's text is handed back there (in the new-note field). And the draft of a reply or an edit whose thread or message is gone stays in the tab under its old key until sign-out.
- `Notes::Start` on a block of a trashed page says "This block was deleted."; `Notes::MarkRead` with a trashed record says "This note is gone"; `Notes::EditMessage` works out the newly mentioned before it takes the lock; "only the author edits" is audited as `access.denied` against the read key; a refused file's sentence repeats the uploader's own (truncated) name; `user.updated` is recorded with empty `field_changes` when the account form is saved unchanged; `Notes::Listing#reactions_of` answers `[]` for a thread it did not list; a rich-text block that starts with an image is named "[image]…"; N ended sessions send N cable disconnects.
- Resolved threads stop at 50 with no "Show more". The mention lookup has no minimum length. The names in a reaction chip's title are not capped. "4,000" and "20" are written into sentences beside the constants that set them. `composer.send_title` says "Send (Ctrl+Enter)" on buttons that read "Reply", "Add note" and "Save". An unavailable block's tile has a marker and "Add note", an unavailable card has neither. `data-notes-count` names two things. The inbox row's `deleted:` and `reopened.somebody_html` keys are close to unreachable. The account view and controller are not on the i18n guard's `CONVERTED` list (the password form's literals), and two `aria_label: "Block actions"` literals were added to the block card, which is not converted either. `admin_unread_notes_path` and the note toast's inbox path are built without `admin_url_options`. `.sub("inline-block", "inline-flex")` on a shared class does nothing if that class changes. The contained save footer still counts as a save bar (`admin-save-bar`, the `bar` target), so a screen with only a contained footer would lift its toasts for nothing.
- In the notes scripts: the "NEW" divider's anchor is read after the messages being worked in were moved, so it slips to the next message when the one under it has an open edit or question; `refreshInbox` reloads the dashboard's two frames even when the count's fetch said "nothing"; a live refresh retries twice a second, unguarded, while its frame is busy; the sidebar badge can flicker; a rejected subscription is kept across a revisit; the badge and the dashboard cards are stale after Back until the next signal; a second signal can name a delivery that is being read; a message whose emoji set is open keeps stale chips; `sent` stays set after a POST with no render; a refused edit relies on the reply's draft; the send guard has no way out if a submit never starts (no path reaches it today); `inside` and `fromList` are cleared only by a frame load; `markActive()` runs once per connecting marker; the Escape key and a row's click can race in the drawer.
- In the mind graph's card: its fetches carry no abort signal, so two loads can land out of order; `select()` on the same index after a reload keeps the old card; a post deleted while its card is open gets the generic sentence; Escape in the field closes the card (its text is kept as a draft now).
- In the alert: the winning tab is chosen without regard to which one has had a click (a tab without one plays nothing); a winner closed within the 150 ms says nothing; `burst.said` is not reduced when a toast is dismissed; `quiet` is not reset on a change of person; a desktop notification opens the delivery's URL as given, where the toast takes only its path and query.
- A thread deleted elsewhere while its reply field holds text keeps the text on screen ("This thread was deleted" above the field, sending switched off) only until that view is left: nothing offers it as a new note there, as the answer to a reply that was already sent does.
- A new note's draft is keyed by the record and the block, not by the quoted passage: text typed about one selection comes back under another selection of the same block.
- Tidiness, from the same review: one index of `note_threads` carries the name Rails made up because the usual one was too long (`idx_on_container_…`), not a name of its own; a block card's name button is no longer `flex-1` since the marker stands beside it; the editor header's wrapper has children that are not indented in its template; and in the drawer Escape and a click on a row can race (closing the drawer while the row's thread is on its way).
- Sign-out and drafts, two narrow paths: a key or pointer press between the Sign out press and the document going takes the removal back, so the drafts stay in the tab on the sign-in page until another person loads a page there (which then removes them); and after "Leave site?" answered with Stay, a reload by the browser's own button, with no press in the page first, removes the person's own drafts.
- A reply handed back in the list's new-note field (its thread was gone) is stored as that field's draft only when no older draft is there: with one, the text is on screen and not stored until a key is pressed.
- A Pin or Notify refused because the note is gone returns the drawer to the list after four seconds; that refusal is drawn in the thread only when the RECORD went to the trash under an open thread, and what the list then answers for a trashed record was not looked at.
- The notes guards (`test/lib/notes_guards_test.rb`) are tripwires with known misses: a `turbo-refresh-method` meta written by a script; a notes service that takes the container's lock in one branch only, or after it has read a notes row (order is the `capture_sql` tests'); a link inside the notes frame that names no frame at all (it targets the frame by default and can be prefetched), and one on the line directly after a `form_with` or `button_to` line.
- The password form's refusal is said by the error summary at the top of "Your account", above the three cards, while the page comes back at the Password card: in a short window the focused message is out of view (a design question, open).

### Presence

Left by the presence sub-project (spec §9; `docs/reference/presence.md`).

- Nothing limits how fast a client may send `report` or `beat` on `Presence::Channel`: each is one indexed update, and a `report` that changes the state also two broadcasts. A minimum interval per subscription would close it. Also `seen_at` is in the record index, so every keep-alive is a non-HOT update (one indexed row per open tab every 30 seconds).
- "Away N min" restarts when a laptop reconnects: an arrival resets `state_at`, so a person who was away for an hour is "away 0 min" again. Telling a reconnect from a first arrival needs the server to know what the tab last said.
- Two narrow races in the heal, both corrected within 150 seconds by the stale limit: a `beat` that updated nothing and asks to heal just after its own subscription's leave began can put a row back, and a heal can overwrite a newer subscription's token. `Presence::Channel#heal` is check-then-act.
- A subscription already open is not re-judged when a right is taken away, as for notes (above): the signal says nothing and every fetch it leads to is scoped, and the record's script ends its own subscription when its next read, within a minute, is answered with a 404 or 403 (`Presence::Channel` itself is not asked again).
- A list open with the focus on the button and the pointer away is closed by a real redraw (someone arrived or left), which replaces the group; the next press opens it again. The `restoring` reset in the record script (`turbo:load`) has no test of its own.
- A list reads once about half a second after a full load, on top of what the server rendered, because the script cannot know what was signalled between the render and its subscription being confirmed.
- Checked by hand only, and only in Chrome: Safari; idle detection on a second real machine; reduced motion; a real back/forward-cache restoration; a throttled hidden tab's keep-alives. Everything else has a machine test.
- The label on a block ("Dana is editing this block") and live refresh of blocks wait for step 3.

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

Multi-site, e-commerce, memberships and paywalls, built-in visitor comments on the public site (editors' notes on content are shipped; the rest of collaboration is "Next", item 1).

## Guardrails while the roadmap is pending

From the structure review: no new integer enums, no new `has_one_attached` on content models, no new `after_save` side effects on `Page` or `Post` (use services and events), no hand-built URLs outside `PublicSite::Urls`, no new per-locale columns or indexes. Respect the "don't touch" list in §6 of the structure review.
