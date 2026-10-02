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
| Translation helpers (source hint, status per locale) | Should | Dropped Task 16 |
| Roles & permissions (owner/admin/editor/author), in-house policy layer, enforced in services for admin and MCP; design for user **groups** from the start (approval chains in Phase 3 assign steps to groups) | Must | §7.1 — done (sub-project 5, spec `2026-09-28-access-control-and-audit-design.md`) |
| Audit log (`audit_events`, append-only, written by services, also emits plugin hooks) | Must | §7.2 — done (sub-project 5) |
| Trash / soft delete + restore | Must | #43 — done (sub-project 6b, spec `2026-09-29-trash-design.md`): pages (with their branch), posts and library images; Trash screen, Undo, retention job |
| Media library (`Media::Asset`, alt text, reuse, responsive variants) | Must | #46 — done (sub-project 6a, spec `2026-09-29-media-library-design.md`) |
| Invites (one-time set-password link without mail) | Should | `Users::Invite` |
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
| Site search + admin global search (Postgres FTS) | Should | Fed by service events |
| Reusable content: global snippets, page templates, block presets | Could | Needs block owner (#47) |
| Forms with submissions and spam protection | Could | Routes hook before catch-alls |
| Headless read API + webhooks on publish | Could | Generalised serializers + events |
| Caching / CDN purge | Could | Needs cookie-less public controller |
| Import / export / backups | Could | Revision snapshot = export format |
| Content quality checks (broken links, required alt) | Could | Event subscribers / job |
| Runtime-configurable languages (define N in setup, add later) | Should | Locale decision in Phase 1 |
| In-admin AI assistant (translate, excerpts, alt text, summarise) | Could | Provider/API key + opt-in; audit AI edits |
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
| Dashboard customisation and widgets (today: the two columns and quick-create bar are fixed) | Could | Same spec §8 |
| Dashboard statistics and counts | Could | Same spec §8 |
| An audit-event feed on the dashboard (today: "Recently updated" shows the records themselves, newest `updated_at` first, not individual audit events) | Could | Same spec §8 |
| Inline page quick create (today: quick create's title + type form is posts-only; "New page" opens the existing new-page flow) | Could | Same spec §8 |
| Public site dates in the site time zone (today: `ThemeHelper#post_date` on the public site and `/preview` still renders in UTC — only CS Studio and MCP run inside `Time.use_zone`) | Could | Needs the rich-text/page render cache to vary on the zone (a zone change must invalidate cached renders); dashboard spec §5 kept the public site unchanged |

## Known interim states

Deliberate gaps shipped ahead of the item that closes them (greenfield: fine while tracked here).

| Interim state | Since | Closed by |
|---|---|---|
| CS Studio autosave writes straight to the record: edits to published pages/posts go live as the editor types (the editor header says so) | Sub-project 3 (CS Studio) | Versioning with pending revisions (Phase 3), then release management |
| ~~Deletes are permanent~~ — resolved: pages, posts and library images now go to the trash first (single blocks, tags, groups, users and tokens are still deleted for good, by design) | Sub-project 3 | Trash (sub-project 6b, spec `2026-09-29-trash-design.md`) — done |
| ~~CS Studio times (schedule input, "Saved HH:MM", scheduled hover) were UTC — no site time zone~~ — resolved: `site_settings.time_zone` (default UTC) wraps every CS Studio and MCP request (`Time.use_zone`); schedule inputs, "Saved HH:MM", the dashboard, the trash and audit screens, and MCP's own ISO-8601 dates all show and parse local time now; storage stays UTC | Sub-project 3 | Site time zone setting (sub-project 6c, spec `2026-09-30-dashboard-design.md`) — done |
| CS Studio tree column isn't resizable/collapsible and isn't a drawer on narrow screens; the posts list isn't paginated | Sub-project 3 | Sub-project 6 (admin polish) |
| Until a variant (`w480`/`w960`/`w1600`/`w2400`) has actually been processed, a page serves the original file at full size instead | Sub-project 6a (media library) | Preprocessing catches up on its own shortly after upload; `bin/rails media:variants` re-enqueues any still missing (design spec §8) |
| MCP token auth does one bcrypt comparison per active token (tokens now accumulate — `ApiTokens::Issue` never rotates an existing one out), so authenticating gets linearly slower as tokens pile up | Sub-project 4 | A lookup prefix on `ApiToken` (future work) |
| No drag-and-drop language reorder in CS Studio's Languages module — fallback/display order is set via a position select | Sub-project 4 | Admin polish (sub-project 6), same as the page tree's own typed-position pattern |
| Editing an already-published page/post/block requires `publish`, not just `edit`, because autosave writes straight to the live record | Sub-project 5 (access control) | Versioning with pending revisions (Phase 3) |
| Pages have no author, so there is no `own` scope for pages the way posts have one | Sub-project 5 | Page authorship (out of scope for now, spec §9) |
| The audit log (`audit_events`) has no export or retention setting and grows without limit; the append-only trigger blocks `DELETE`/`UPDATE`/raw SQL but deliberately not `TRUNCATE`, so `db:truncate_all` still works in development | Sub-project 5 | Audit export/retention (not yet scheduled) |
| The seeded Author group's `posts.read`/`posts.create` are unscoped by spec §5, so an Author reads every post, not only their own (only `posts.edit` is `own`-scoped) | Sub-project 5 | Revisit the seeded Author grants if this proves surprising in practice |
| The Tags list shows each tag's post count across every kept post, not scoped to what the viewer can read (the module itself is gated by `tags.manage`) | Sub-project 5 | Scope tag counts to `AccessControl.scope` (future work) |
| Deleting a tag (still permanent) takes it off trashed posts too, so a post restored later comes back without that tag; the Tags list's count and its delete dialog count kept posts only | Sub-project 6b (trash) | Trash for tags (see "Trash for single content blocks, tags, …" above) |
| A related post the viewer can't read is hidden from the editor but disclosed as a count — "+N related posts you can't open" — rather than fully hidden | Sub-project 5 | Accepted trade-off; revisit if disclosure of the count matters |
| The dashboard's "Recently edited by you" scans every page/post/image the viewer may read (a `LATERAL` join per candidate row, `Dashboard::Feed#recently_edited`) to find whose newest audit event is theirs — each probe is an index lookup (`index_audit_events_on_subject_and_newest`, `(subject_type, subject_id, last_occurred_at DESC)`), but the scan still grows with the number of readable records | Sub-project 6c (dashboard) | Revisit (a query driven from the actor's own events) if dashboard load time grows with site size |
| The Translations overview filters in Ruby: `Translations::Status` is computed per record (field digests, block roll-ups), so `Admin::TranslationsController` walks every readable page, post and image in batches of 200 until a page of 50 incomplete items is filled — cheap for early pages, a full scan for a late page or a language with few gaps | Translation helpers (Task 4) | A stored per-locale translation state kept current by the save services, if overview load time grows with site size |

## Out of scope (for now)

Multi-site, e-commerce, memberships/paywall, built-in comments.

## Guardrails while the roadmap is pending

From the structure review: no new integer enums, no new `has_one_attached` on content models, no new `after_save` side effects on `Page`/`Post` (use services and events), no hand-built URLs outside `PublicUrls`, no new per-locale columns/indexes without the locale decision. Respect the "don't touch" list in §6 of the structure review.
