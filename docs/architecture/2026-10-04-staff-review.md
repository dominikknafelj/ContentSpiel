# ContentSpiel staff review (snapshot `studio-design-round-3` @ 5d662bb, 2026-10-04)

Scope: all of `app/`, `config/`, `db/`, `lib/`, `test/` (structurally) and the deploy files, about 40,000 lines of app code. Read-only: **nothing was run, profiled or measured**. Query counts are counted from the code, plan shapes are read from the SQL and `db/schema.rb`, never from `EXPLAIN`.

Not reviewed: the uncommitted round-3 work in the tree at the time (`save_bar_controller.js`, `save_bar_component.*`, `pending_lock_controller.js`, the admin layout edits).

Findings are referenced as `S<n>` (defects, performance, weak guarantees), `M<n>` (modularisation), `L<n>` (before a first deploy), `D<n>` (database structure and Postgres features, §8) and `C<n>` (public-site caching, §9). Each carries a status:

- **checked**: the lines named were read a second time by the reviewer who collated this document, and say what the finding says.
- **reported**: found and traced by one reviewer, not read a second time. Treat as a strong lead, confirm before fixing.
- **suspected**: plausible from the source, not traced end to end.

## 1. Summary

The codebase is sound where it has been deliberate: read scoping and "not found, not forbidden", denials that survive a rollback, the rich-text renderer and scrubber, the append-only audit log, listener cleanup in the Stimulus controllers, and the write queue's liveness (no deadlock found).

The debt sits in three patterns:

1. **Derived data is recomputed far too broadly.** A page save re-derives every URL below it and every listed post's URL (S6); the public content version moves on any write, drafts included, and costs 15 queries per request (S7); a tree click re-renders the whole shell (S10).
2. **Guarantees are enforced by grep tests and comments, not behaviour.** The service contract test reads whole files (S19), the "strict CSP" does not exist (S20), two Save services mass-assign what they are given (S21), system tests swallow JavaScript errors (S22).
3. **A fix lands in one copy of a pattern and not its siblings.** Autosave checks its response, block reorder and tree move do not (S3); a password change ends sessions in two controllers but not in the service (S2); the "published needs publish" rule is written out five times (M6).

Suggested order: S1–S5 (real bugs, each small), then S6 and S7 together with M2 (one cause), then S19–S24.

## 2. Bugs

### S1. Trashed subpages are still listed on the public site — checked
- `app/views/pages/show.html.erb:72-75`: `@page.children.published` with no `.kept`. `Trashable` has no `default_scope`, and `Trash::Move` leaves `published_at` and `parent_id` alone, so a published subpage trashed on its own keeps its title in its parent's "page-children" list (the link has no target, its `public_paths` rows are gone).
- The header nav does filter (`app/helpers/theme_helper.rb:29`, `children.kept.published`).
- `test/integration/trash_visibility_test.rb` has no kept-vs-trashed pair for this list.
- Direction: `@page.children.kept.published.to_a` once (this also removes the `any?` + `each` double query), and add the pair to the visibility test.

### S2. An admin changing another user's password leaves that user's sessions alive — checked
- `app/services/users/save.rb:57-61` assigns `:password` and touches no sessions. No `User` callback does either.
- Session invalidation exists only in two controllers: `app/controllers/admin/passwords_controller.rb:38` (reset) and `app/controllers/admin/accounts_controller.rb:28` (own change), both outside the service transaction and unaudited.
- Consequence: resetting a compromised account from the Users screen does not sign the attacker out.
- Direction: move it into `Users::Save` / `Users::UpdatePassword`, inside the transaction, keyed on `saved_change_to_password_digest?`, with an optional "keep this session" id.

### S3. Block reorder and tree move render any response as a Turbo Stream and are silent on failure — checked
- `app/javascript/controllers/admin/blocks_controller.js:223-244` and `tree_controller.js:135-158`: `const text = await response.text(); … Turbo.renderStreamMessage(text)` with no check of `response.ok`, `response.redirected` or the content type, then `.catch(() => {})`.
- An expired session answers the PATCH with a redirect to sign-in, which `fetch` follows; the sign-in page's markup is then appended to the document. A 500 page behaves the same. On a network error or the 30 s timeout nothing is shown and the dragged order stays on screen as if saved.
- `admin--autosave` already handles this (`autosave_controller.js:353-366`, `:498-503`, `isTurboStreamAnswer` and a signed-out state).
- Direction: one `fetchStream()` helper (CSRF, timeout, redirected → signed out, status and content-type check) used by autosave, blocks, tree and translate (see M6). On failure revert the optimistic move or raise an error toast.

### S4. Autosave has no unload guard — checked
- No `beforeunload`/`pagehide` listener in `autosave_controller.js` or `autosave/queue.js`; the only one for unsaved work is in `save_bar_controller.js`.
- Closing the tab, a hard reload or a non-Turbo link loses text silently within the 1 s debounce, during a retry, or in the "NOT SAVED · Retry" and 409 "your text is still here" states.
- Direction: one `beforeunload` in `queue.js` that calls `preventDefault()` while the queue is not settled. Round 3 is reworking the save bar's leave guard, so do this alongside it.

### S5. Multi-file upload reloads the page over its own error rows — checked
- `app/javascript/controllers/admin/media_upload_controller.js:48-50`: `if (outcomes.some((ok) => ok)) window.location.reload()`. Drop five files with one refused and the refusal is never seen.
- Reported, same file: `response.ok` is true for a followed sign-in redirect, so an expired session reads as "uploaded"; all files are sent at once against 3 Puma threads.
- Direction: reload only when every upload succeeded, otherwise keep the list and refresh the grid; require a 201 and an id, as the picker does.

## 3. Performance

### S6. Every page save re-derives the URL of its whole subtree and of every listed post — checked
- `app/models/page.rb:177` (`after_save :sync_public_paths`, unconditional), `:205-208`, `:233-237`; `app/models/public_site/paths.rb:34-37` (`sync_subtree`), `:55-58` (`sync_posts`), `:149` (`canonical_page(post) = canonical_pages([ post ])`), `:201-208` (`post_path`), `:243-246` (`write`).
- `sync_subtree` recurses with one children query per node plus per-locale path lookups, even when nothing moved (`write` returns early only after its own query).
- `sync_posts` loads every post of the listed types in full and, per post per locale, calls `canonical_page`, which reloads every listing block and its ancestry chains each time. The batch form `canonical_pages(posts)` exists and is not used here.
- The homepage's subtree is the whole site, so every homepage autosave pays for all pages and all listed posts, inside the save transaction. A single post save pays the post cost twice per locale (validation in `has_public_paths.rb:30-35`, then `after_save`).
- Same path from `content_block.rb:90-91`, `tags/rename.rb:59`, `tags/destroy.rb:34`, `locales/enable.rb:50`.
- Direction: skip the sync when raw `slug`, `parent_id`, `position`, `published_at` and `trashed_at` are unchanged (capture in `before_save`, since closure_tree's reload clears the dirty flags); when a sync is needed, load the subtree and its current `public_paths` rows in two queries and diff in memory; compute `canonical_pages(batch)` once per batch in `sync_posts`. See M2 for where this should live.

### S7. `PublicSite.content_version`: 15 aggregate queries per public request, and any write invalidates everything — checked
- `app/models/public_site.rb:38-47`: five `maximum(:updated_at)`, two `maximum(:published_at)`, six `count`, two on variant records. `db/schema.rb` has no index on `updated_at` or `published_at` for any of those tables.
- It is the ETag (`app/controllers/pages_controller.rb:37`) and part of every rich-text cache key (`app/models/rich_text/document.rb:182`). A draft autosave moves `posts.updated_at`, so while anyone edits, every visitor's 304 is defeated and every cached body is a miss, written again to Solid Cache.
- `CLAUDE.md` describes the version as moving when a link or asset target could change; the code is much broader.
- Direction: one version row (or column on `site_settings`) bumped in `after_commit` only by changes that can affect published output, plus the next scheduled go-live for the time-based case. Reported: `RichText::Schema.version` and the document digest are recomputed on every `to_html`; memoise.

### S8. A 304 still pays for the image preload — checked
- `app/controllers/pages_controller.rb:27` runs `assign_record` (blocks, assets, attachments, blobs, variant records) before `stale?` on `:37`.
- Direction: preload after the `stale?` check.

### S9. MCP auth bcrypt-compares the bearer against every active token — checked
- `app/models/api_token.rb:28-30`: `active.find { |candidate| candidate.authenticate_token(raw_token) }`.
- Already in the roadmap's "Known interim states" as "linearly slower as tokens pile up". What that row does not say: a **wrong** bearer runs every compare before authentication, bounded only by Rack::Attack at 60 requests a minute per IP in a per-process store, on 3 Puma threads.
- Direction: the token is `SecureRandom.hex(32)`, so a slow hash adds nothing. Store a SHA-256 digest in a unique indexed column and `find_by` it. Throttle the `last_used_at` write.

### S10. Each tree click renders the whole admin shell and loads every page — checked
- `app/controllers/admin/base_controller.rb:73` (`layout "admin"`) applies to `#content` frame requests too; the layout branches on `turbo_frame_request?` only for toasts.
- `app/components/admin/tree_component.rb:65-72`: `Page.all.to_a.select { |page| visible_ids.include?(page.id) }` — the full table, every jsonb column, trashed rows included, filtered in Ruby. Turbo then keeps only the frame.
- Direction: a minimal layout for frame requests; load the tree with `Page.kept.where(id: visible_ids)` and only the columns it shows.

### S11. A public 404 scans `posts` on an unindexed jsonb expression — checked
- `app/models/public_site/resolver.rb:65-71`: `Post.kept.where("slug ->> ? = ?", …).find { … page_row.record.content_blocks.listing.any? … }`. Runs for every miss whose parent path resolves, and `/anything` resolves to the homepage. The listing blocks are re-queried per candidate.
- Direction: check the parent page has a listing block before touching `posts`, hoist the block load, add per-locale expression indexes on `(slug ->> 'xx')`.

### S12. MCP `list_posts` is unbounded and renders every body before dropping it — checked
- `app/mcp/mcp/tools/list_posts.rb:44-51`: `scope.order(:id).map { |post| PostSerializer.call(post, locale).except(:body) }`, no limit. `CLAUDE.md` says the MCP list tools page at about 50; only `list_media.rb` does.
- Direction: paginate like `ListMedia`, a list serializer that never touches the body, batch the path lookup as `Admin::PostsController#listed_paths` does.

### S13. Every admin page evaluates Tiptap, SortableJS and d3-force — checked
- `app/javascript/controllers/index.js:20-30` eagerly imports every controller in the import map; `mind_graph_controller.js:2` and `rich_text_controller.js:2` import their libraries statically.
- Direction: `await import()` inside `connect()` for those two, and drop their `preload`.

### S14. Public URL building is one query per link per locale — reported
- `app/models/public_site/urls.rb:39-46` memoises per instance but fills each miss with one `find_by`. Nav links, listed posts, child links and the language switcher all pay it. `app/components/blocks/post_list_component.rb:30-31` applies `limit` only when set, so an unlimited listing renders every post.
- Direction: `Urls#preload(records, locales)` with one query; cap or paginate unlimited listings.

### S15. Internal links cost three or more queries each at render — reported
- `app/models/rich_text/built_ins.rb:490-501`: `find_by` per mark occurrence, then `Resolver.visible?` (a closure query), then `path_for`. Images are preloaded from `document.references`; links are not.

### S16. Sibling positions are renumbered without a lock — reported
- `app/models/page/tree_ranking.rb:57-78`: read siblings, write dense positions from that snapshot, one `UPDATE` per shifted row. Two editors (or an editor and MCP) moving under one parent can leave duplicate positions, which `canonical_pages`' ranking assumes are unique.
- Direction: `pg_advisory_xact_lock` on the parent at the start of `Pages::Move` and page create; one `UPDATE … FROM (VALUES …)`.

### S17. Dashboard "Your drafts" evaluates its LATERAL for every readable draft — reported
- `app/queries/dashboard/feed.rb:44-46`, `:93-104`, `:119-154`. The block half joins every event of every block of the page and sorts. `audit_events` is never pruned.
- Direction: maintain `last_changed_by_id` / `last_changed_at` on pages and posts next to `record_event`.

### S18. Schema hygiene and wide rows — reported
- `media_assets.created_by_id` is indexed but has no foreign key.
- Missing for queries actually issued: `posts(updated_at)`, `posts(published_at)`, `pages(published_at)`.
- Redundant prefixes of a composite: `access_control_grants(group_id)`, `access_control_memberships(user_id)`, `post_tags(post_id)`, `post_relations(post_id)`, `media_usages(media_asset_id)`.
- `app/queries/post_graph.rb:46-49` loads full post rows (every locale's body plus `translation_sources` text) for id, title and type.
- ⌘K and the posts-list title search (`jump/search.rb:75-78`, `admin/posts_controller.rb:363`) are full scans; fine until tens of thousands of rows.

## 4. Guarantees weaker than documented

### S19. `service_contract_test` can be satisfied without being correct — checked
- `test/services/service_contract_test.rb:51-54` reads the whole file `#call` lives in, not the method. `:16` and `:27`: one `# audit: none (…)` comment skips the `authorize!` assertion as well as the audit one.
- It already shapes code: `app/services/users/update_profile.rb:21-27` calls `authorize!("users.manage", @user)`, discards the result and returns `denied`; the success path has no authorization call.
- Direction: keep it as a tripwire, add a behavioural contract (each service called as a no-grant user on `:admin` answers `denied?`, writes one `access.denied`, changes nothing), and separate the two exemptions.

### S20. There is no script CSP — checked
- `config/initializers/content_security_policy.rb:15-27` sets only `frame_src`, `object_src` and `base_uri`, and says so. `CLAUDE.md` claims "a strict CSP refuses inline handlers".
- Reported: `test/lib/inline_handlers_test.rb` lists a fixed set of events, so `onpointerdown`, `ontoggle` and `ondrag*` pass.
- Direction: correct `CLAUDE.md`; a nonce-based `script-src` as a roadmap item.

### S21. `Pages::Save`, `Posts::Save` and `Settings::Save` mass-assign what they are handed — checked for pages, reported for the other two
- `app/services/pages/save.rb:155-162` strips only `:parent`; `parent_id`, `position`, `trashed_at`, `trash_root_id` and `translation_sources` would bypass `Pages::Move` and `Trash::Move`. `posts/save.rb:217` is the same shape. No caller passes them today.
- Direction: an explicit `PERMITTED` slice per service, as `ContentBlocks::Save` and `Media::Save` have, raising on unknown keys.

### S22. System tests hide two classes of bug — checked
- `test/application_system_test_case.rb:23` (`js_errors: false`) and `:109-111` (`press` clicks with `this.click()`); 49 `sleep` calls under `test/`. The scripted clicks and fixed sleeps are already a "Known interim states" row; `js_errors: false` is not.
- Direction: `js_errors: true` with a filter for Turbo's `AbortError`; native clicks by default.

### S23. `turbo-rails` is unpinned under about ten Turbo internals — checked
- `Gemfile:14` has no version (lockfile: 2.0.23). `app/javascript/autosave/queue.js` relies on `Turbo.navigator.currentVisit.willRender` (`:608`), deleting `event.detail.fetchRequest` (`:588`), header names (`:578-580`), stream recognition by `outerHTML` (`:263-286`) and event ordering (`:600-603`); `controllers/index.js:27` uses `application.router.modulesByIdentifier`.
- Direction: pin `~> 2.0.23`; one test asserting each internal exists with the expected shape.

### S24. The Trash restore parent picker skips the read scope — checked
- `app/controllers/admin/trash_controller.rb:206-208`: `Page.kept.find_by(id: params[:parent_id])`. An existing out-of-scope page answers a 403, a missing id does not, so a `pages.delete` holder can probe ids.
- Direction: load through `admin_scope`.

### S25. The server's rich-text content model mirrors Tiptap by hand, with no drift test — reported
- `app/models/rich_text/built_ins.rb:34-44`. After a Tiptap re-pin the server may refuse what the editor produces, or accept what it opens read-only.
- Direction: one system test that dumps `editor.schema.spec` and compares it with `RichText::Schema`.

### S26–S32. Smaller, all reported
- **S26.** Single-record trash/restore/purge flashes put an unbounded title in the session cookie (`admin/pages_controller.rb:237-239`, `posts_controller.rb:213-214`, `trash_controller.rb:94-96`); titles have no length validation (checked). Expected: `CookieOverflow` after the write commits. Share `BulkResponses`' truncation.
- **S27.** Forged param shapes still 500: `params.dig(:block, :block_type)` with a scalar (`content_blocks_controller.rb:50`, `tags_controller.rb:46`, `settings_controller.rb:54,106`), `fields.to_unsafe_h` on a String (`posts_controller.rb:172`, `content_blocks_controller.rb:278`).
- **S28.** (suspected) A Turbo form submission held by the queue is cancelled by the next submission in the same frame (`queue.js:326-339`): Duplicate then "+ Add block" during a slow save drops the Duplicate.
- **S29.** The translate timeout sets a flag and does not abort the fetch (`translate_controller.js:405-417`), so a bulk run stalls behind a request the UI gave up on.
- **S30.** Results ignored or answered inconsistently: `setup_controller.rb:234` (no `ok?` check on `ApiTokens::Issue`), `users_controller.rb:69-74` (redirect instead of 403), `dashboard_controller.rb:33` (title written in `Locales.default`, not `admin_locale`), `tree_controller.rb:47` (rescue wraps the whole action).
- **S31.** Two ways to enable a language with different side effects: `Locales::Enable` versus `Settings::Save(locales:)` plus `PublicSite::Paths.rebuild!` in `setup_controller.rb`, which deletes redirect rows and fills no slugs.
- **S32.** Block Duplicate is orchestrated in the controller across two transactions and two audit events (`content_blocks_controller.rb:48-57`, `:171-187`); a failed reposition leaves screen and database disagreeing.

## 5. Modularisation

The folder layout is good: clear domain namespaces (`AccessControl`, `Media`, `RichText`, `Translations`, `PublicSite`, `Audit`, `Trash`, `ContentModel`), services per aggregate under one `ApplicationService`, components per screen, five small model concerns. The weakness is at the dependency level. The counts below are greps of which namespace is mentioned from where (comments included), not a traced dependency graph.

### M1. The domains are a mesh, and four dependencies point the wrong way
- Under `app/models`, `PublicSite` is mentioned from 11 other areas, `Media` from 10, `RichText` from 9. No direction is written down and nothing enforces one.
- Inversions: `rich_text/built_ins.rb:443` and `:467` call `ApplicationController.render` from a model; `starter_content.rb` (a model) calls `Pages::Save`, `Posts::Save` and `ContentBlocks::Save`; `queries/dashboard/activity.rb:149` builds an `Admin::UserNameComponent` for a label; `media/asset.rb:162,224`, `jump/search.rb:67` and `post_graph.rb:40` reach for route helpers.
- Direction: write one order into `CLAUDE.md` (roughly `RichText`/`ContentModel` → `AccessControl`/`Audit` → content models → `PublicSite`/`Translations`/`Media` indexes → services → controllers and components) and fix the four inversions. Engines or Packwerk are more ceremony than this stage needs.

### M2. Derived tables are maintained two different ways
- `public_paths` is written from model callbacks; `media_usages` and `translation_states` from services. The callback variant is what makes S6 unavoidable: a callback cannot know what the caller changed.
- The roadmap's guardrail already says "no new `after_save` side effects on `Page`/`Post`".
- Direction: move `public_paths` maintenance into the services, like the other two.

### M3. `app/models` is a catch-all, and query objects are used inconsistently
- 69 of its 88 files are not Active Record models (registries, the Markdown parser, the HTML renderer, AI providers, index writers, setup steps, `Pagination`, a route constraint, `admin/field_params.rb`).
- `app/queries` holds three things, while the posts list's filtering, counting and search live in the 587-line `admin/posts_controller.rb`, and eight components run their own queries (`changed_elsewhere_component.rb`, `trash_screen/list_component.rb`, `columns/rich_text_column_component.rb`, `new_page_form_component.rb`, among others).
- Direction: a `Posts::ListQuery`; pass loaded data into components.

### M4. The plugin seam is four separate registries
- `ContentModel`, `RichText::Schema`, `AccessControl::Permissions` and `AI::Providers` each have their own register and reset, wired by hand in `config/initializers/types.rb`.
- Direction: one registration facade a plugin calls once. Belongs with "Plugin API v1".

### M5. `rich_text/` is a library living in `app/models`
- 3,660 lines. `document.rb` (760) holds the value object, the validator, the normaliser, the text extractor and the cache wrapper; `markdown.rb` (918) holds loader, dumper and escaping; five separate tree walkers exist.
- Direction: extract `RichText::Validator` and `RichText::Normalizer`, split loader and dumper; it can leave `app/models` once M1's controller call is gone.

### M6. Rules and plumbing written out several times
- "Editing a published record needs `publish`": `posts/save.rb:59-60`, `pages/save.rb:46-47`, `content_blocks/owner_permissions.rb:23-24`, `translations/edit_right.rb:32-33`, `access_control_helper.rb:39`, and a variant in `editor_screen/header_component.rb:102`. This rule is due to be removed with pending revisions; one `AccessControl.edit_keys(record)` makes that a one-line change.
- JavaScript: the CSRF lookup in six controllers, `fetch` + `renderStreamMessage` four ways (the cause of S3), keyboard reorder duplicated between `blocks_controller.js:252-339` and `tree_controller.js:180-303`.
- Controllers: pages and posts share copy-pasted `publish`/`unpublish`/`schedule`; posts and blocks share `normalize_group_fields`, `apply_missing_groups` and the field splitting.

### M7. `queue.js` and `translate_controller.js` each hold several separable things, with no unit tests
- `queue.js` (610 lines): slot queue, form registry and drain, stream and base syncing, three Turbo navigation interceptors, sharing module state. `translate_controller.js` (639): one class in three roles plus a module-level job manager.
- About 7,000 lines of admin JavaScript are tested only through Cuprite.
- Direction: `queue/slots.js` (pure), `queue/forms.js`, `queue/turbo_navigation.js`; `translate/jobs.js` plus three controllers; a small headless runner for the pure parts.

### M8. No i18n in the UI
- Zero `t(` calls under `app/components`, `app/views`, `app/helpers`; only `config/locales/en.yml`. Estimated 900–1,100 admin strings, plus English grammar built in Ruby (`pluralize`, `to_sentence`).
- Visible to visitors today on `/de/…` and `/es/…`: `posts/now_list_component.html.erb`, `pages/not_found.html.erb`, the theme toggle, `aria-label`s, `strftime` month names in `theme_helper.rb:37`.
- Direction: fix the public strings now (about 15); decide the admin key scheme before more strings are added.

### M9. Leftovers
- `rich_text/html_import.rb`, `action_text_import.rb` and their rake task and tests (about 700 lines) are reachable only when a table that no schema-built database has exists.
- `config/application.rb:17-18` still requires `action_cable/engine` and `action_mailbox/engine`; `jbuilder` and `solid_cable` are unused (reported).
- `Dockerfile:27` `BUNDLE_WITHOUT="development"` ships the test gems.
- CI uses `image: postgres` (`.github/workflows/ci.yml:79,132`); dev pins `postgres:17`.
- Reported: data migrations call live app code without a guard (`20260928060000_seed_access_control_groups.rb:13-14` and three grant migrations).

## 6. Before a first deploy

- **L1.** `config/environments/production.rb:28-31` (`assume_ssl`, `force_ssl` commented out), `:61` (mailer host `example.com`), `:85` (`config.hosts` unset); `app/mailers/application_mailer.rb:2` (`from@example.com`). Reported: `config/deploy.yml` has placeholder servers and registry, and passes no database password or host.
- **L2.** `config/initializers/opentelemetry.rb`: with no OTLP endpoint, production prints every span to stdout synchronously on the request thread.
- **L3.** Reported: no error reporting, and no backup story for Postgres or the uploads volume.
- **L4.** (suspected) Web and Solid Queue threads share a 5-connection pool (`config/puma.rb`, `config/queue.yml`, `config/database.yml`).

## 7. `CLAUDE.md` drift found on the way

- "A strict CSP refuses inline handlers" (S20).
- The contract test "greps its `#call` source" (S19).
- MCP list tools paginate "about 50 per call" (S12; only media does).
- `content_version` "bumps whenever anything publishing/renaming/deleting a link or asset target could invalidate a cached render" (S7; it moves on any write).

## 8. Database structure and Postgres features

Added after the first hand-off, from a full read of `db/schema.rb` against the queries the code issues. Still nothing measured. Status "checked" here means the schema and the named query were both read.

### D1. No index on any `updated_at` or `published_at` — checked
- The posts list sorts `updated_at DESC, id DESC` with an offset (`app/controllers/admin/posts_controller.rb:317`); `Publishable`'s `published` scope is `where(published_at: ..Time.current)` (`app/models/concerns/publishable.rb:11`) and sits on every public listing; the dashboard sorts on both (`app/queries/dashboard/feed.rb:45`, `:56`, `:85`); S7's five `maximum(:updated_at)` run per public request.
- Add: `posts(updated_at)`, `posts(published_at)`, `pages(published_at)`. These treat the symptom; S7 removes most of the need on the public side.

### D2. Slugs and titles are queried inside jsonb with no index — checked
- Slug uniqueness runs on every save, once per locale: `self.class.i18n.where(slug: value)` (`app/models/concerns/localized_slug.rb:80`). The public 404 fallback is the same shape (S11).
- Direction: one GIN index with `jsonb_path_ops` on `slug`, queried by containment (`slug @> '{"de": "ueber-uns"}'`). It serves every language from one index, so it survives runtime-configurable languages, which per-locale expression indexes on `(slug ->> 'xx')` do not. **Not checked:** what SQL Mobility's `.i18n` scope generates; if it is `slug ->> ?`, the lookups need writing as containment for the index to be used.
- Title search (`jump/search.rb:75-78`, `posts_controller.rb:363`) unnests the jsonb and does `ILIKE '%q%'`. `pg_trgm` over a generated "all titles" column, when it starts to matter.

### D3. `content_blocks.block_type` has no index — checked
- `scope :listing` (`app/models/content_block.rb:97`) filters on it, and S6's `canonical_page` calls that scope once per post per locale.
- Add a partial index restricted to the listing block types, or a plain one on `block_type`.

### D4. Wide content rows — checked (schema), reported (callers)
- `posts` and `content_blocks` carry `body` for every locale plus `translation_sources`, which stores a copy of the original text per translated field per language. Whole-row loads pay for all of it: `Page.all` in the tree (S10), the mind graph (S18), `sync_posts` (S6).
- Direction: `select` only the columns a list needs; consider moving source text out of the hot row.

### D5. `audit_events` — checked
- Unbounded (already a "Known interim states" row), a full `snapshot` per row, five indexes maintained on every write. Two are near-duplicates: `(subject_type, subject_id, occurred_at)` and `(subject_type, subject_id, last_occurred_at)`. Check which readers still use the `occurred_at` one before dropping it.
- When retention is built: partition by month and expire by dropping a partition. The table blocks `DELETE` by trigger, so this is the clean way. `db/schema.rb` cannot express partitions; it would need the reapply-after-schema-load hook `config/initializers/db_triggers.rb` already provides for the trigger.

### D6. Sibling positions (extends S16) — checked (schema)
- `pages.position` is nullable with no uniqueness per parent.
- Direction: `pg_advisory_xact_lock` on the parent in `Pages::Move` and page create; renumber with `row_number() OVER (PARTITION BY parent_id ORDER BY position, id)` in one `UPDATE … FROM`; a **deferrable** unique constraint on `(parent_id, position)` so duplicates are impossible, not just unlikely. Trashed siblings need thought first: `Page::TreeRanking` counts kept siblings only.

### D7. Set-based path sync (extends S6)
- Compute a subtree's paths in one statement (a recursive CTE, or a join on `page_hierarchies`) and write them with `INSERT … ON CONFLICT`, instead of recursing per page with per-locale lookups.

### D8. Atomic stale-autosave check
- `CLAUDE.md` documents that "the check and the save are not atomic". A conditional update closes it: `UPDATE … WHERE id = ? AND updated_at = ?`, then read the affected row count (or Rails' `lock_version`).

### D9. Smaller
- Redundant single-column indexes, each a leading prefix of a composite: `access_control_grants(group_id)`, `access_control_memberships(user_id)`, `post_tags(post_id)`, `post_relations(post_id)`, `media_usages(media_asset_id)`.
- `media_assets.created_by_id` has no foreign key (also S18).
- `api_tokens.token_digest` is a salted bcrypt hash and cannot be indexed: S9's SHA-256 column with a unique index is the fix.
- `media_library_migrated_assets` is a leftover ledger table (M9).

### Postgres features to use later, and ones to leave alone
- **Later:** `tsvector` full-text search with per-language configurations for the roadmap's site search (German and Spanish dictionaries ship with Postgres); `pgvector` only if translation memory or semantic search is built.
- **Not recommended:** row-level security (it would duplicate `AccessControl`'s grant and token-intersection rules in a second language); materialized views (the derived tables are already updated inside the writing transaction, which a refreshed view cannot match); more triggers (writes go through services, where they are authorised and audited; the one existing trigger is a backstop, which is the right use); `LISTEN`/`NOTIFY` (nothing needs push between processes yet).

### Sound in the schema
- `page_hierarchies` has both indexes closure_tree needs.
- `public_paths`: unique `(locale, path)` and a partial unique index for the current row, so the public lookup is one index hit.
- `translation_states` and `media_usages` have unique keys matching how they are read and upserted.
- The single-root rule is backed by a partial unique index.

## 9. Public-site caching

Added after the first hand-off. The user's priority: caching for the public site matters now, caching for CS Studio does not. From the config and code; nothing measured.

What exists: one application cache (the rich-text body render, `app/models/rich_text/document.rb:182`, see S7), Solid Cache in production (a hit is a database query), no fragment caching in any view, fingerprinted assets cached for a year, and a cookie-less public controller (the prerequisite for any shared cache).

### C1. No shared cache can hold a page, although one is already deployed — checked
- `app/controllers/pages_controller.rb:36`: `expires_in 0, public: true, must_revalidate: true`. Every visitor request reaches Puma's three threads and, at best, ends in a 304 that still costs S7's 15 queries and S8's preload.
- The container starts through Thruster (`Dockerfile:77`, `CMD ["./bin/thrust", "./bin/rails", "server"]`), which has an HTTP cache. With `max-age=0` it stores nothing.
- The preconditions hold: the public response is the same for every visitor (no cookies, no CSRF tag, the theme toggle is client-side), and `/preview` already answers `private, no-store` (`app/controllers/preview_controller.rb:16`).
- Direction, revised after the user asked for a Clear cache button (C6): a button that takes a minute to work would look broken, so the first cache is **inside Rails**: the whole rendered page in `Rails.cache`, keyed on S7's version row, the path, the language and `RichText.code_revision`. A version bump then invalidates everything at once with no purge mechanism. A request costs one version read and one cache read.
- A short shared lifetime at the proxy (for example `s-maxage=60`, keeping the ETag) is an optional layer on top. Its trade-off: a publish, a scheduled go-live or a Clear cache shows up to that long late. Only add it if the user accepts that delay. **Not asked explicitly; the default taken here is "no delay".**
- Scheduled go-lives need a version bump of their own at the scheduled time (or the next go-live time in the key), since nothing is written when the clock passes `published_at`.
- **Not checked:** which directives Thruster honours, and whether it can purge or serve stale while revalidating. Its cache is in memory, per container.

### C2. Library images are served in Active Storage's redirect mode — checked (code), general knowledge (behaviour)
- `app/models/media/asset.rb:162` (`rails_blob_path`) and `:224` (`rails_representation_path`). Each image is a request to Rails answered by a redirect to a short-lived URL, so a browser or CDN cannot keep it for long, and each costs two requests.
- Direction: proxy mode (`rails_storage_proxy_path` and the proxy representation route), which gives stable URLs with long-lived cache headers. That is how Active Storage behaves in general; it was not tested in this app. Images are most of a page's requests, so once pages are cached this matters more than the HTML.

### C3. 404s are never cached, and each can scan `posts`
- See S11. A brief shared lifetime on the 404 response keeps bot traffic off the database.

### C4. Purge on publish
- Already in the roadmap as "Caching / CDN purge". It removes C1's staleness trade-off once a real CDN is in front. S7's narrow version row is what a purge would key on, and the path-change events from Phase 1 name the URLs.

### C5. Deferred on purpose
- Fragment caching: worth little once whole pages are cached.
- The rich-text body cache: a detail of the miss path. Keep it only if measuring shows it still helps under the whole-page cache.
- CS Studio caching (S10, S13): not a priority now.

### C6. A "Clear cache" button in CS Studio — requested by the user
- Two layers of invalidation. **Automatic:** every service that changes published output (publish, unpublish, a title or slug change, a move, trash, restore, a newly processed image variant) bumps the site version after commit, so editors never think about the cache when publishing. **Manual:** the button, for what the services cannot see (a console change, a restored backup, a stuck CDN).
- Site-wide by default. One change reaches further than its own URL: a title is in the navigation of every page, a post is on every listing page that shows it, a slug is in every page that links to it. Tracking those dependencies per page is where CMS caches go wrong; a site this size re-warms quickly.
- Shape: "Clear cache" under System (its own permission, for example `cache.clear`, seeded onto Admin; an `ApplicationService` that records `cache.cleared`), and "Clear this page's cache" in the editor's ⋯ menu for when one page looks wrong. The per-page action can delete that page's entries per language, or simply bump the site version too; start with whichever is simpler.
- When a CDN exists, the same service also calls its purge API (C4).

Order: S7's version row and S8, then C1 with C6, then C2, C3 and C4.

## 10. Checked and found sound

- Read scoping through `AccessControl.scope` on pages, posts, blocks, the tree, bulk actions, MCP get/update and preview (S24 is the one exception found).
- Denials are recorded outside the service transaction; savepoints are used where a rescue would otherwise swallow a failure; no external call inside a transaction.
- Rich-text XSS surface: text escaped before marks, tags from helpers, `safe_href?` re-checked at render, output through `RichTextScrubber`; `MAX_DEPTH` guards; linear validation.
- `Audit::Coalescer` locks its candidate; the append-only guards hold.
- `public_paths` unique indexes back the check-then-write; single root is validated and indexed.
- `Translations::StateIndex`, `Media::UsageIndex`, `Dashboard::Activity`: constant query counts, set-based writes.
- JavaScript: user data reaches the DOM through `textContent` and templates; listeners, timers and observers are cleaned up; the queue's slots release in `finally` or under a limit; `search/suggestions.js` is correct.
- No dead CSS selectors found; no admin JavaScript on public pages; three fixture sets, no sprawl.
