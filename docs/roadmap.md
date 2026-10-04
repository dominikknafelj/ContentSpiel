# ContentSpiel roadmap

Living document (started 2026-09-26). ContentSpiel is a **generic, self-hosted CMS** that non-technical editors enjoy using and developers can extend without forking. Priorities: **Must** (needed before we'd call it a usable generic CMS), **Should**, **Could**. Refactors are judged against this list: they must open the seams these items need and never make one more expensive.

Sources: product review (`docs/product/2026-09-26-backend-product-review.md`), code-structure review (`docs/architecture/2026-09-26-code-structure-review.md`, findings referenced as `#N`, sections as `§N`), product decisions from the 2026-09-26 sessions.

## Decisions already made

| Decision | Detail |
|---|---|
| Replace Avo with our own admin | Rails + Hotwire, product design tokens (`--cs-*`), Claude Design backend screens. Avo stays mounted only during the switch. Forking Avo rejected (LGPL-3.0; wanted features are closed add-ons). |
| Admin layout | TYPO3-style three columns: **modules \| page tree \| content**. |
| Rich text | **Tiptap**: store a Tiptap/ProseMirror JSON document per locale (replacing ActionText/Trix HTML), render HTML server-side, Markdown view for AI/MCP (custom nodes as directives). Node types come from a registry (plugin seam). Markdown as storage rejected. |
| Independent CSS | Product UI and public theme are separate Tailwind builds with separate tokens (`--cs-*` vs `--th-*`); the demo look is only the default public theme. |
| One branch per round of work | Bugfixes and features of a round ship together; no production exists yet. |

## Phase 0 — in flight: `editor-experience` branch

Public demo theme with independent stylesheets (spec §9); per-locale slugs, tag filter, publish status + signed-in preview, resume fields, alt texts (spec §10.1–10.4, model side). Added from the structure review: MCP re-publish keeps `published_at` (#24), iframe scrubber + CSP `frame-src` (#37), slugs filled from the default locale for untitled locales (#2). The Avo-specific parts of spec §10 were dropped and move to Phase 2.

## Phase 1 — foundations (refactor before the own admin)

| Item | Why (roadmap it unblocks) | Priority | Ref |
|---|---|---|---|
| Locale model decision: supported vs enabled locales, how slugs/indexes scale | Runtime languages, admin i18n; decides admin form shape | Must | #44, #17 — done (sub-project 1, spec `2026-09-26-foundations-design.md`) |
| `PublicUrls` (one URL builder, absolute URLs) + `Current.site` | SEO/hreflang, feeds, API, navigation, CDN purge, "view on site" | Must | #27, #51, #12, §4.1, §4.7 — done (sub-project 1, spec `2026-09-26-foundations-design.md`) |
| `PublicSite::Resolver` (published vs preview scope) + cookie-less public controller | Preview, workflow, caching/CDN, GDPR | Must | #19, #48, §4.2 — done (sub-project 1, spec `2026-09-26-foundations-design.md`) |
| Path-change events + automatic redirects | SEO redirects, CDN purge, content quality | Must | #45 — done (sub-project 1, spec `2026-09-26-foundations-design.md`) |
| Open types: string `content_type`/`block_type` + registries | Custom content types, plugin API, reusable content | Must | #50, #6, #47, §8 — done (sub-project 2, spec `2026-09-27-open-types-design.md`) |
| Canonical post URL + posts in the sitemap | SEO, feeds | Should | #8 — done (sub-project 1, spec `2026-09-26-foundations-design.md`) |
| Service layer: `Posts::Save`, `Pages::Save/Move/Destroy`, `ContentBlocks::Save/Reorder`, `ApiToken.issue!` | The single write path roles, audit, versioning, webhooks, search and plugins attach to; MCP switches first | Must | §4.3–4.6, #25 — done (sub-project 1, spec `2026-09-26-foundations-design.md`) |
| Test helpers for content setup | Makes everything after cheaper | Should | #39, #41 — done (sub-project 1, spec `2026-09-26-foundations-design.md`, `test/support/content_helper.rb`) |

## Phase 2 — own admin (replaces Avo)

| Item | Priority | Notes |
|---|---|---|
| Three-column shell: modules \| page tree \| content | Must | Tree: drag reorder, status per node, add child, open page — done (sub-project 3, spec `2026-09-27-cs-studio-design.md`) |
| Tiptap editor + JSON storage + ActionText migration | Must | Markdown view for MCP; node registry — done (sub-project 4, spec `2026-09-27-tiptap-and-avo-removal-design.md`) |
| Inline block editor (type-specific fields, add/reorder/delete, alt text, post-list inputs) | Must | Design from dropped plan Tasks 12–13 — done (sub-project 3, spec `2026-09-27-cs-studio-design.md`) |
| Draft / Scheduled / Live, Publish now / Unpublish, preview & "View on site" / "Edit this page" | Must | Dropped Task 11 design; preview from Phase 0 — done (sub-project 3, spec `2026-09-27-cs-studio-design.md`) |
| Typed fields per content type (resume fields), type-dependent forms | Must | Dropped Tasks 9–10; generated from the type registry — done (sub-project 3, spec `2026-09-27-cs-studio-design.md`) |
| Dashboard (drafts, scheduled, recent, quick create) | Should | Dropped Task 14 — done (sub-project 6c, spec `2026-09-30-dashboard-design.md`) |
| "Connect an AI assistant" (token shown once, MCP URL + config, revoke) | Must | Dropped Task 15 — done (sub-project 3, spec `2026-09-27-cs-studio-design.md`) |
| Translation helpers (source hint, status per locale) | Should | Dropped Task 16 — done (spec `2026-10-02-translation-helpers-design.md`): outdated tracking with "Mark as up to date", status in lists and the page tree, a Translations overview, translatable site title and tagline, AI translation suggestions |
| Roles & permissions (owner/admin/editor/author), in-house policy layer, enforced in services for admin and MCP; design for user **groups** from the start (approval chains in Phase 3 assign steps to groups) | Must | §7.1 — done (sub-project 5, spec `2026-09-28-access-control-and-audit-design.md`) |
| Audit log (`audit_events`, append-only, written by services, also emits plugin hooks) | Must | §7.2 — done (sub-project 5) |
| Trash / soft delete + restore | Must | #43 — done (sub-project 6b, spec `2026-09-29-trash-design.md`): pages (with their branch), posts and library images; Trash screen, Undo, retention job |
| Media library (`Media::Asset`, alt text, reuse, responsive variants) | Must | #46 — done (sub-project 6a, spec `2026-09-29-media-library-design.md`) |
| CS Studio design pass (admin polish): new shell, shared components, every screen rebuilt to the v3 design handoff, in three rounds | Must | In progress — spec `2026-10-03-cs-studio-design-pass-design.md`; handoff in `docs/design/cs-studio-handoff-v3/`. Round 1 (foundations and bugs: tokens and theme, the shared components, the new shell, ⌘K, sign-in and setup, eight bug fixes) is done (PR pending). Round 2 (editors with the header, Schedule dialog, view-only and the refused stale save; side-by-side translation with the word diff and suggestions; blocks; rich-text dialogs; the page tree and `/pages`; the New dialogs; the dashboard and its activity feed; the posts list with bulk actions; the translations matrix; the stored `translation_states`) is done (PR pending); round 3 settings/media/people/system is open |
| Block and type catalogue: more built-in block types, and a review of the built-in content and page types | Should | **After the design pass, before the demo content** (agreed 2026-10-04) — a demo site can only show layouts the block types allow. Today: 3 block types (rich text, image, post list), 3 content types (blog, resume entry, now update), 2 page types (standard, landing); the registries are generic, the shipped set is thin and still a personal site's. Candidates — blocks: hero/banner, columns or grid, gallery, call to action, quote/testimonial, video/embed as its own block, accordion/FAQ, teaser cards linking to pages, and a sitemap block (a human-readable list of the published page tree, in the visitor's language, for a "Sitemap" page; the XML `sitemap.xml` already exists via `rake sitemap:create`, and generating it automatically stays with the SEO row below). Content types: event, person/team member, project/case study; decide whether resume entry and now update stay defaults or move into an optional "personal site" starter set. Page types: contact, legal (see Legal/GDPR below), redirect/link page, and a sitemap page (a standard page carrying the sitemap block, offered in the starter set). Contact form stays with "Forms with submissions"; editor-defined types stay with "Custom content types & fields defined in the admin". Needs its own spec (and designs from Claude Design for each block's editor card and public rendering) |
| Demo content in the setup wizard, plus a debug and performance data set | Should | **After the block and type catalogue** (asked for 2026-10-04). The wizard's optional starter-content step gains a "Demo site" choice; a second, much larger set with advanced data, varied layouts and images serves debugging, performance checks and exposing design issues an almost empty site hides. Not a `db:seed` script. Open question from the first brainstorm: who may pick the large set (developers only, everyone, or behind an environment setting). Assumed so far: built through the save services, with generated or bundled images. Needs its own spec |
| Invites (one-time set-password link without mail) | Should | `Users::Invite`; after the design pass, which only renames the button to "New user" |
| Admin UI in German (admin i18n) | Should | #49 |
| Port Avo-only invariants, then remove Avo | Must | #40 — done (sub-project 4) |

## Phase 3 — after the admin MVP

| Item | Priority | Notes |
|---|---|---|
| Versioning: revisions + restore (in-house snapshots, pending revisions) | Must | §7.3 |
| SEO: hreflang, OG image, noindex, snippet preview, auto sitemap | Must | Built on `PublicUrls` |
| Custom content types & fields defined in the admin | Should | Registry with DB-backed definitions |
| Navigation / menu management | Should | `Navigation.for` (#52) |
| Plugin API v1 (Rails engines, registries, event hooks, routes hook, MCP tool registry, versioned API) | Should | §8 |
| Publishing workflow: review/approval, draft comments, edit lock, scheduled unpublish | Should | Pending revisions + policies |
| Release management: bundle changes to several pages/posts into a release, preview the whole site with the release applied, shareable preview links (no account needed), schedule/publish a release atomically | Should | Needs pending revisions (versioning) + `PublicSite::Resolver` preview scope; releases are sets of pending revisions |
| Approval chains for releases: steps where specific user groups must approve (e.g. editor submits → Legal approves → Publishers publish); the chains themselves are **defined in the admin by authorized groups** (a permission of its own), not hard-coded; approvals/rejections recorded in the audit log | Should | Needs user **groups** in the permission model (not only fixed roles) + releases + audit log |
| Security basics: 2FA, password policy, session list/revoke, login history | Should | Login history = audit events |
| Legal / GDPR: imprint & privacy pages, consent hook, user export/delete | Should | Cookie-less public site first (Phase 1) |
| RSS / Atom feeds | Should | Cheap once URLs are canonical |
| Site search + admin global search (Postgres FTS) | Should | Fed by service events; the design pass adds a ⌘K "Jump to…" palette that matches titles only, not this |
| Reusable content: global snippets, page templates, block presets | Could | Needs block owner (#47) |
| Forms with submissions and spam protection | Could | Routes hook before catch-alls |
| Headless read API + webhooks on publish | Could | Generalised serializers + events |
| Caching / CDN purge | Could | Needs cookie-less public controller |
| Import / export / backups | Could | Revision snapshot = export format |
| Content quality checks (broken links, required alt) | Could | Event subscribers / job |
| Runtime-configurable languages (define N in setup, add later) | Should | Locale decision in Phase 1 |
| Workspace in CS Studio: a place to work on pages together, with reference material | Could | Asked for 2026-10-04, deliberately placed further down. A workspace gathers what a piece of work needs: links to internal resources (pages, posts, images), uploaded documents (briefs, source texts, PDFs), the people working on it, and an AI assistant that can read those references while helping with the relevant pages. Builds on: media library for documents (see "video and document files"), comments and edit locks from the publishing workflow, versioning with pending revisions (so drafts can be worked on without going live), `AI::Providers`, and access control groups. Needs its own brainstorm and spec; open questions include whether a workspace is per page, per project or free-form, and what the AI may write without a human pressing Use |
| In-admin AI assistant (translate, excerpts, alt text, summarise) | Could | Partially done: translate only (translation helpers spec `2026-10-02-translation-helpers-design.md` §6 — provider registry, encrypted key in Settings, `ai.translate`, suggestions the editor applies with Use, `ai.translated` audit events). Excerpts, alt text and summaries are still open (row below) |
| AI for excerpts, alt text and summaries | Could | Out of scope for translation helpers, spec `2026-10-02-translation-helpers-design.md` §9; `AI::Providers` and the suggestion box (`Admin::TranslationScreen::SuggestionComponent`) are the seams |
| A monthly AI budget (spend cap per site) | Could | Same spec §9; `ai.translated` events already record `characters` per request |
| More built-in AI providers (an OpenAI-compatible one) | Could | Same spec §9; `AI::Providers.register` takes plugin providers today |
| Background whole-site translation (translate everything missing in a language as a job) | Could | Same spec §9; today "Translate empty fields" works per editor screen, and nothing is saved without Use |
| Translation memory and glossary | Could | Same spec §9 |
| A side-by-side translate mode (original and translation in two full columns) | Could | Same spec §9 — done in round 2 of the CS Studio design pass (PR pending): the original beside each field, stacking below 880px of the form |
| A language dropdown on the public site | Could | Left out of the CS Studio design pass, spec `2026-10-03-cs-studio-design-pass-design.md` §10 |
| Share images (Open Graph image per page and post) | Could | Left out of the CS Studio design pass, spec `2026-10-03-cs-studio-design-pass-design.md` §10 |
| A "sample" marker on starter content | Could | Left out of the CS Studio design pass, spec `2026-10-03-cs-studio-design-pass-design.md` §10 |
| AI tools over MCP | Could | Same spec §9; deliberately not planned — MCP clients are already AIs and can translate through `update_post` themselves |
| Shared workspaces: people collaborate on content and assets (drafts, media, notes) in a shared space, with an optional AI agent helping produce the output; a workspace's work can flow into a release | Could | Builds on groups/permissions, media library, releases, AI assistant; agent edits go through services + audit log |
| Media library: video and document files, not only images | Could | Out of scope for sub-project 6a, spec `2026-09-29-media-library-design.md` §8 |
| Media library: cropping and a focal point | Could | Same spec §8 |
| Media library: folders and tags for organizing assets | Could | Same spec §8 |
| Media library: automatic cleanup of unused assets | Could | Can now build on the trash (e.g. move long-unused images to the trash and let the retention job purge them); today cleanup is manual only, by design — an editor moves an unused asset to the trash by hand, or runs `bin/rails media:orphans` for orphaned blobs (same spec §8; trash spec §10) |
| Media library: uploads through MCP | Could | MCP is read-only over the library today (`list_media_tool`/`get_media_tool`); same spec §8 |
| Move the site logo into the media library | Could | Needs SVG sanitising the library doesn't have (SVG stays refused everywhere else); the logo stays its own separate `SiteSetting` attachment until then (same spec §8) |
| Trash for single content blocks, tags, groups, users and API tokens (deleting one is still permanent) | Could | Out of scope for the trash, spec `2026-09-29-trash-design.md` §10; `Trashable` + `Trash::` services are the seam |
| MCP trash tools (list, restore, purge; MCP can't delete anything today) | Could | Same trash spec §10; the services already take a token actor |
| 410 Gone for trashed (or purged) URLs instead of 404 | Could | Same trash spec §10; a trashed record's `public_paths` rows are deleted, so this needs a tombstone of its own |
| Per-user time zones (today: one site-wide zone in Settings) | Could | Out of scope for the dashboard, spec `2026-09-30-dashboard-design.md` §8 |
| Dashboard customisation and widgets (today: the three cards, the activity feed and the quick-create row are fixed) | Could | Same spec §8 |
| Dashboard statistics and counts | Could | Same spec §8 |
| An audit-event feed on the dashboard (today: "Recently updated" shows the records themselves, newest `updated_at` first, not individual audit events) | Could | Same spec §8 — done in round 2 of the CS Studio design pass (PR pending, spec `2026-10-03-cs-studio-design-pass-design.md` §5.6): `Dashboard::Activity`, a content-only feed |
| Inline page quick create (today: quick create's title + type form is posts-only; "New page" opens the existing new-page flow) | Could | Same spec §8 — done in round 2 of the CS Studio design pass (PR pending): "Page" in quick create opens the New page dialog |
| Public site dates in the site time zone (today: `ThemeHelper#post_date` on the public site and `/preview` still renders in UTC — only CS Studio and MCP run inside `Time.use_zone`) | Could | Needs the rich-text/page render cache to vary on the zone (a zone change must invalidate cached renders); dashboard spec §5 kept the public site unchanged |

## Known interim states

Deliberate gaps shipped ahead of the item that closes them (greenfield: fine while tracked here).

| Interim state | Since | Closed by |
|---|---|---|
| CS Studio autosave writes straight to the record: edits to published pages/posts go live as the editor types (the editor header says so) | Sub-project 3 (CS Studio) | Versioning with pending revisions (Phase 3), then release management |
| ~~Deletes are permanent~~ — resolved: pages, posts and library images now go to the trash first (single blocks, tags, groups, users and tokens are still deleted for good, by design) | Sub-project 3 | Trash (sub-project 6b, spec `2026-09-29-trash-design.md`) — done |
| ~~CS Studio times (schedule input, "Saved HH:MM", scheduled hover) were UTC — no site time zone~~ — resolved: `site_settings.time_zone` (default UTC) wraps every CS Studio and MCP request (`Time.use_zone`); schedule inputs, "Saved HH:MM", the dashboard, the trash and audit screens, and MCP's own ISO-8601 dates all show and parse local time now; storage stays UTC | Sub-project 3 | Site time zone setting (sub-project 6c, spec `2026-09-30-dashboard-design.md`) — done |
| ~~CS Studio tree column isn't a drawer on narrow screens~~ — resolved by round 1 of the design pass (PR pending): the sidebar is a drawer below 1280px and the page-tree column one below 1024px. The posts list is paginated since round 2 (PR pending). Still open: the tree column isn't resizable/collapsible | Sub-project 3 | Not scheduled |
| Until a variant (`w480`/`w960`/`w1600`/`w2400`) has actually been processed, a page serves the original file at full size instead | Sub-project 6a (media library) | Preprocessing catches up on its own shortly after upload; `bin/rails media:variants` re-enqueues any still missing (design spec §8) |
| MCP token auth does one bcrypt comparison per active token (tokens now accumulate — `ApiTokens::Issue` never rotates an existing one out), so authenticating gets linearly slower as tokens pile up | Sub-project 4 | A lookup prefix on `ApiToken` (future work) |
| No drag-and-drop language reorder in CS Studio's Languages module — fallback/display order is set via a position select | Sub-project 4 | CS Studio design pass, round 3 (same spec §5.6) |
| Editing an already-published page/post/block requires `publish`, not just `edit`, because autosave writes straight to the live record | Sub-project 5 (access control) | Versioning with pending revisions (Phase 3) |
| Pages have no author, so there is no `own` scope for pages the way posts have one | Sub-project 5 | Page authorship (out of scope for now, spec §9) |
| The audit log (`audit_events`) has no export or retention setting and grows without limit; the append-only trigger blocks `DELETE`/`UPDATE`/raw SQL but deliberately not `TRUNCATE`, so `db:truncate_all` still works in development | Sub-project 5 | Audit export/retention (not yet scheduled) |
| The seeded Author group's `posts.read`/`posts.create` are unscoped by spec §5, so an Author reads every post, not only their own (only `posts.edit` is `own`-scoped) | Sub-project 5 | Revisit the seeded Author grants if this proves surprising in practice |
| The Tags list shows each tag's post count across every kept post, not scoped to what the viewer can read (the module itself is gated by `tags.manage`) | Sub-project 5 | Scope tag counts to `AccessControl.scope` (future work) |
| Deleting a tag (still permanent) takes it off trashed posts too, so a post restored later comes back without that tag; the Tags list's count and its delete dialog count kept posts only | Sub-project 6b (trash) | Trash for tags (see "Trash for single content blocks, tags, …" above) |
| A related post the viewer can't read is hidden from the editor but disclosed as a count — "+N related posts you can't open" — rather than fully hidden | Sub-project 5 | Accepted trade-off; revisit if disclosure of the count matters |
| The dashboard's "Recently edited by you" scans every page/post/image the viewer may read (a `LATERAL` join per candidate row, `Dashboard::Feed#recently_edited`) to find whose newest audit event is theirs — each probe is an index lookup (`index_audit_events_on_subject_and_newest`, `(subject_type, subject_id, last_occurred_at DESC)`), but the scan still grows with the number of readable records | Sub-project 6c (dashboard) | Revisit (a query driven from the actor's own events) if dashboard load time grows with site size |
| Changing the default language to a third one flags every translation as outdated: `translation_sources` stores the original's digest but not which language the original was in, so after en → de every Spanish translation (made from English) is compared against the German original and differs. "Mark as up to date" clears them one field at a time | Translation helpers (Task 1) | Record the primary language next to each digest (or re-baseline digests in the default-language change), if default-language changes happen on real sites |
| AI translation suggestions run inside the web request: each holds a Puma thread (3 by default) for up to two 25 s provider calls, so concurrent bulk "Translate empty fields" runs can starve the site of threads, and the request depends on the proxy's `response_timeout` (75 s in `config/deploy.yml`). The cap is 6,000 characters per request to keep each one short | Translation helpers (final fix wave) | Run suggestions as a background job (Solid Queue) that streams the suggestion boxes back over Turbo Streams; the per-request cap and timeout can then grow |
| ~~The Translations overview filtered in Ruby, walking every readable record per request~~ — resolved by round 2 of the design pass (PR pending): the stored `translation_states` table (`Translations::StateIndex`) replaces `Translations::CachedStatus`; the matrix, the posts list's Translation filter, the tree counts and the dashboard card read it in SQL | Translation helpers (Task 4) | CS Studio design pass, round 2 (spec §5.3) — done |
| ~~The mind graph fills the whole content column and some nodes animate outside its box~~ — resolved by round 1 of the design pass (PR pending): the graph fills the view (the content column's width, the window's remaining height) and clamps its nodes and labels to that box (its fallback node colour is a token now). Still open: node colours, legend and edges | Found 2026-10-02 | CS Studio design pass, round 3 (colours, legend and edges) |
| The error toast has no "Retry" action (design pass spec §4): nothing raises an error a retry could repeat yet. Upload progress on a media tile is deferred with it (the chip input and the pending suggestion box landed in round 2) | CS Studio design pass, round 1 | CS Studio design pass, round 3 (each lands with its first caller) |
| The explicit-save leave guard (`admin--save-bar`, "Leave without saving?") only sees Turbo Drive visits (`turbo:before-visit`) and a page unload: a Turbo *frame* navigation inside `#content` and the browser's Back button both leave a dirty form without asking. The save-bar screens' own in-frame links break out with `data-turbo-frame="_top"` for that reason | CS Studio design pass, round 1 | CS Studio design pass, round 3 — before Settings moves onto the save bar |
| ~~`test/system/admin/translations_test.rb` "Translate empty fields, then Use all" flaked under load; suspected race between the page's autosave and a block autosave's touch of the page~~ — the race was real and is closed by round 2 (PR pending): a stale save is now refused outright and every autosave of one screen goes through one write queue (`app/javascript/autosave/queue.js`), so a block's answer moves the page form's base before the next request is sent; "Use all" can no longer trip its own "Changed elsewhere" (two system tests pin it: the page's own fields and its block's, and two blocks). Rerun it alone if it ever fails again under load | CS Studio design pass, round 1 (final review) | CS Studio design pass, round 2 — done |
| After a Back or Forward, the toast controller's "this render came from the cache" flag stays set until the next Turbo visit, so a top-level form that then fails with a 4xx re-render (a refused "Move to trash" on a page) loses its error toast | CS Studio design pass, round 1 (final review) | Clear the flag once the restored page has loaded (`turbo:load`) — a small follow-up fix |
| A drag clone can stay on the page if the tree or block list is re-rendered while a row is being dragged with the mouse (SortableJS's fallback clone lives on `<body>` and `destroy` doesn't remove it) | CS Studio design pass, round 1 (final review) | Remove `Sortable.ghost` in the controllers' `disconnect` — a small follow-up fix |
| Instant filters put focus back on the control that triggered the reload even if the editor moved focus elsewhere during the round trip | CS Studio design pass, round 1 (final review) | Restore focus only when it is still on `<body>` or inside the filter form — a small follow-up fix |
| Mouse drag in the page tree and block list uses SortableJS's JS fallback (`forceFallback`) so it starts from a `<button>` handle in every browser; this was not hand-tested in Firefox | CS Studio design pass, round 1 (final review) | A manual check in Firefox |
| Autosave: a save the server processed but whose answer was lost is retried on the old base and gets a final "Changed elsewhere" refusal (the editor locks themselves out until Reload) | CS Studio design pass, round 2 | Per-record version columns or pending revisions (Phase 3) instead of `updated_at` as the base |
| Autosave: an edit typed between a header action's submit and its redirect is refused unseen; an edit typed during an in-flight save followed at once by Back/Forward is dropped | CS Studio design pass, round 2 | Pending revisions (Phase 3), or a page-level lock while an action runs |
| Autosave: for up to 30 s after leaving a page with a hung save, the next page's visits wait and its header actions are declined; frame navigations inside `#content` don't start a new page generation until the promoted visit renders | CS Studio design pass, round 2 | Cancel the queue on a hung request sooner (`HOLD_LIMIT_MS`/`DRAIN_LIMIT_MS` in `autosave/queue.js`) |
| `translation_states` doesn't follow code changes (a deploy that adds a required translated field leaves rows stale until `bin/rails translations:reindex`), and a record created outside the services has no row: it reads complete and is absent from the matrix and the counts. `StateIndex.rebuild_all` runs synchronously on a language change, proportional to the site's size | CS Studio design pass, round 2 (spec §5.3) | Run the rebuild from a job and on deploy; a row for every record at creation |
| A schema group field's reference card shows the raw Hash | CS Studio design pass, round 2 | A formatted rendering of a group value |
| `Post.human_attribute_name` / `ContentBlock.human_attribute_name` name typed fields without an I18n lookup | CS Studio design pass, round 2 | Admin UI in German (admin i18n) |
| The dashboard's activity feed looks back 90 days (`Dashboard::Activity::WINDOW`), and its event query's cost grows with the readable set (hashed subplans over readable ids: a `work_mem` cliff on a very large site) | CS Studio design pass, round 2 | A query driven from the viewer's grants, or a materialised feed, if it shows on large sites |
| The dashboard feed says "via an API token" without naming the token (the user is shown, the token never loaded) | CS Studio design pass, round 2 | Token names, `api_tokens.name` (round 3, spec §5.4) |
| Translations matrix: an old `?locale=` link lands on the unfiltered matrix (use `?language=`); the summary cards don't count the Site settings row; the ordering expression is evaluated over the filtered set, not only the page | CS Studio design pass, round 2 | Not scheduled |
| Posts list: Undo for a bulk trash is offered only while its URL (which names the posts and keeps the filters) fits the session cookie (`Admin::BulkResponses::MAX_UNDO_URL`, 1,500 bytes: a few dozen posts); `Posts::Save#find_tag` costs up to two queries per submitted tag name | CS Studio design pass, round 2 | Hold the batch server-side instead of in the URL |
| The chip input and the rich-text link search share `search/suggestions.js`; Escape during its 150 ms debounce closes the surrounding dialog | CS Studio design pass, round 2 | Swallow Escape while a search is pending |
| The New page / New post forms load when the dialog opens (a short loading state), and the title preset travels in a GET query string, so it appears in the request log | CS Studio design pass, round 2 | Render the form with the page, or POST the preset |

## Out of scope (for now)

Multi-site, e-commerce, memberships/paywall, built-in comments.

## Guardrails while the roadmap is pending

From the structure review: no new integer enums, no new `has_one_attached` on content models, no new `after_save` side effects on `Page`/`Post` (use services and events), no hand-built URLs outside `PublicUrls`, no new per-locale columns/indexes without the locale decision. Respect the "don't touch" list in §6 of the structure review.
